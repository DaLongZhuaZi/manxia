[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-jsapi-s2t-default-runtime-current-head-audit-20260809.json'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-JSAPI-JAVA-S2T-DEFAULT-RUNTIME'
$assertions = 0
$failures = New-Object 'System.Collections.Generic.List[string]'

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-Json {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing JSON: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes) | ConvertFrom-Json
}

function Read-Text {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing text: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}

function Assert-Static {
  param([bool]$Condition, [string]$Id, [string]$Message)
  $script:assertions++
  if (-not $Condition) { [void]$script:failures.Add("${Id}: $Message") }
}

function Write-AtomicJson {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 30), [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$fixture = Read-Json 'tools/legado-compat/fixtures/legado-jsapi-s2t-default-runtime.json'
$failureWitness = Read-Json 'tools/legado-compat/evidence/contract-legado-jsapi-s2t-default-runtime-pre-fix-20260809.json'
$settlement = Read-Json 'tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/semantic-settlement.json'
$mapping = Read-Json 'tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/reference-mapping.json'
$legadoExtensions = Read-Text 'legado/app/src/main/java/io/legado/app/help/JsExtensions.kt'
$legadoAnalyzeRule = Read-Text 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeRule.kt'
$rawRuntime = Read-Text 'entry/src/main/resources/rawfile/legado_runtime.html'
$runtimeV2 = Read-Text 'entry/src/main/ets/Framework/Novel/LegadoRuntimeV2.ets'
$compiler = Read-Text 'entry/src/main/ets/Framework/Novel/LegadoCompatibilityCompiler.ets'
$analyzer = Read-Text 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$engine = Read-Text 'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets'
$scriptRuntime = Read-Text 'entry/src/main/ets/Framework/Novel/LegadoSourceScriptRuntime.ets'
$orchestrator = Read-Text 'entry/src/main/ets/Framework/Novel/LegadoWorkflowOrchestrator.ets'
$types = Read-Text 'entry/src/main/ets/Framework/Novel/LegadoCompatibilityTypes.ets'
$registry = Read-Text 'entry/src/main/ets/Framework/Novel/LegadoJsApiContractRegistry.ets'

Assert-Static ([string]$settlement.status -eq 'passed_static_only' -and [string]$failureWitness.status -eq 'failed') 'evidence_states' 'settlement and pre-fix witness must be static-only.'
Assert-Static ([int]$settlement.baseline.sourceCount -eq 458 -and [string]$settlement.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$settlement.baseline.legadoCommit -eq $legadoCommit) 'settlement_baseline' 'settlement baseline drifted.'
Assert-Static ([string]$fixture.primaryCause -eq 'default_arkweb_runtime_capability_injection_missing_java_s2t') 'cause' 'fixture primary cause drifted.'
Assert-Static ([string]$failureWitness.issueId -eq $issueId -and @($failureWitness.affectedSourceOrdinals).Count -eq 4) 'failure_binding' 'failure witness is not bound to the four affected sources.'
Assert-Static ($legadoExtensions.Contains('fun s2t(text: String): String') -and $legadoExtensions.Contains('return ChineseUtils.s2t(text)')) 'legado_member' 'fixed Legado s2t declaration/semantic handoff missing.'
Assert-Static ($legadoAnalyzeRule.Contains('preUpdateJs') -or $legadoAnalyzeRule.Contains('ruleSearch')) 'legado_workflow_context' 'fixed Legado workflow context could not be located.'
Assert-Static ($rawRuntime.Contains('var java = {') -and $rawRuntime.Contains('t2s: function (value)') -and -not $rawRuntime.Contains('s2t: function (value)')) 'default_runtime_gap' 'default runtime gap is not reproducible at current HEAD.'
Assert-Static ($runtimeV2.Contains('legado_runtime') -or $runtimeV2.Contains('loadRuntime')) 'runtime_loader' 'V2 runtime loader path is not present.'
Assert-Static ($engine.Contains('s2t: function(text)')) 'native_diagnostic' 'diagnostic Native JSVM s2t implementation is missing.'
Assert-Static ($compiler.Contains('Legado') -and $analyzer.Contains('Rule') -and $scriptRuntime.Contains('variable')) 'compiler_path' 'Analyzer/compiler/script scope consumer paths are not present.'
Assert-Static ($orchestrator.Contains('Search') -and $orchestrator.Contains('Explore') -and $orchestrator.Contains('Content')) 'workflow_path' 'workflow consumer paths are not present.'
Assert-Static ($types.Contains('TEXT') -or $types.Contains('outputKind')) 'output_path' 'typed output consumer path is not present.'
Assert-Static ($registry.Contains("this.add('java.t2s'") -and -not $registry.Contains("this.add('java.s2t'")) 'registry_gap' 'registry gap is not reproducible at current HEAD.'
Assert-Static ([int]$mapping.apiMappings.'java.s2t'.occurrenceCount -eq 4 -and [int]$mapping.apiMappings.'java.s2t'.sourceCount -eq 4) 'mapping' 'reference mapping does not bind four s2t occurrences.'
Assert-Static (@($fixture.consumerMatrix).Count -eq 6) 'consumer_matrix' 'candidate consumer matrix is incomplete.'
Assert-Static (@($fixture.conversionCases).Count -eq 4) 'conversion_fixture' 'conversion fixture must contain four deterministic cases.'
Assert-Static (@($fixture.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$fixture.semanticMatchAllowed) 'runtime_gate' 'audit must remain static-only.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_jsapi_s2t_default_runtime_current_head_audit'
  issueId = $issueId
  status = if ($script:failures.Count -eq 0) { 'passed_static_only' } else { 'failed' }
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  targetRevision = [string]$fixture.targetRevision
  baseline = $fixture.baseline
  primaryCause = [string]$fixture.primaryCause
  classification = [string]$fixture.classification
  affectedSourceOrdinals = @($fixture.api.affectedSourceOrdinals)
  affectedSourceHashPrefixes = @($fixture.api.affectedSourceHashPrefixes)
  consumerMatrix = @($fixture.consumerMatrix)
  assertions = $script:assertions
  failures = @($script:failures.ToArray())
  currentHeadPaths = @(
    'entry/src/main/resources/rawfile/legado_runtime.html',
    'entry/src/main/ets/Framework/Novel/LegadoRuntimeV2.ets',
    'entry/src/main/ets/Framework/Novel/LegadoCompatibilityCompiler.ets',
    'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
    'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets',
    'entry/src/main/ets/Framework/Novel/LegadoSourceScriptRuntime.ets',
    'entry/src/main/ets/Framework/Novel/LegadoWorkflowOrchestrator.ets',
    'entry/src/main/ets/Framework/Novel/LegadoCompatibilityTypes.ets',
    'entry/src/main/ets/Framework/Novel/LegadoJsApiContractRegistry.ets'
  )
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_static_candidate_audit_only;R4_runtime_differential_build_and_device_deferred'
  closeCondition = [string]$fixture.closeCondition
}
Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Depth 30
if ([string]$result.status -ne 'passed_static_only') { exit 1 }
