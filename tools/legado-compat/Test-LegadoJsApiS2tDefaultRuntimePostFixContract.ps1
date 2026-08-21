[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$EvidenceRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
  $EvidenceRoot = Join-Path $RepositoryRoot 'tools\legado-compat\evidence'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-JSAPI-JAVA-S2T-DEFAULT-RUNTIME'
$targetRevision = '2026-08-09-actual-docs-source-refactor-js-api-s2t-default-runtime'
$fixtureRelative = 'tools/legado-compat/fixtures/legado-jsapi-s2t-default-runtime.json'
$preFixRelative = 'tools/legado-compat/evidence/contract-legado-jsapi-s2t-default-runtime-pre-fix-20260809.json'
$historicalAuditRelative = 'tools/legado-compat/evidence/v2-jsapi-s2t-default-runtime-current-head-audit-20260809.json'
$contractRelative = 'tools/legado-compat/evidence/contract-legado-jsapi-s2t-default-runtime-20260809.json'
$sourceFixRelative = 'tools/legado-compat/evidence/v2-jsapi-s2t-default-runtime-source-fix-20260809.json'
$currentHeadRelative = 'tools/legado-compat/evidence/v2-jsapi-s2t-default-runtime-current-head-audit-20260809-r1/current-head-hash-audit.json'
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

function Get-Sha256 {
  param([string]$RelativePath)
  $hash = Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $RelativePath)
  return [string]$hash.Hash
}

function Assert-Static {
  param(
    [bool]$Condition,
    [string]$Id,
    [string]$Message
  )
  $script:assertions++
  if (-not $Condition) { [void]$script:failures.Add("${Id}: $Message") }
}

function Write-AtomicJson {
  param(
    [string]$Path,
    [object]$Value
  )
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 40), [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$fixture = Read-Json $fixtureRelative
$preFix = Read-Json $preFixRelative
$historicalAudit = Read-Json $historicalAuditRelative
$state = Read-Json 'tools/legado-compat/state/full-source-validation-state.json'
$objective = Read-Json 'tools/legado-compat/state/refactor-objective.json'
$rawRuntime = Read-Text 'entry/src/main/resources/rawfile/legado_runtime.html'
$runtimeV2 = Read-Text 'entry/src/main/ets/Framework/Novel/LegadoRuntimeV2.ets'
$compiler = Read-Text 'entry/src/main/ets/Framework/Novel/LegadoCompatibilityCompiler.ets'
$analyzer = Read-Text 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$engine = Read-Text 'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets'
$scriptRuntime = Read-Text 'entry/src/main/ets/Framework/Novel/LegadoSourceScriptRuntime.ets'
$orchestrator = Read-Text 'entry/src/main/ets/Framework/Novel/LegadoWorkflowOrchestrator.ets'
$types = Read-Text 'entry/src/main/ets/Framework/Novel/LegadoCompatibilityTypes.ets'
$registry = Read-Text 'entry/src/main/ets/Framework/Novel/LegadoJsApiContractRegistry.ets'
$legadoExtensions = Read-Text 'legado/app/src/main/java/io/legado/app/help/JsExtensions.kt'
$chineseUtils = Read-Text 'legado/app/src/main/java/io/legado/app/utils/ChineseUtils.kt'

$preFixHash = Get-Sha256 $preFixRelative
$historicalAuditHash = Get-Sha256 $historicalAuditRelative

Assert-Static ([int]$fixture.baseline.sourceCount -eq 458 -and [string]$fixture.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$fixture.baseline.legadoCommit -eq $legadoCommit) 'fixture_baseline' 'fixture baseline drifted.'
Assert-Static ([string]$preFix.status -eq 'failed' -and [string]$preFix.issueId -eq $issueId) 'failure_witness_preserved' 'pre-fix failure witness must remain failed and bound to S2T.'
Assert-Static (@($preFix.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$preFix.semanticMatchAllowed) 'failure_witness_static_only' 'pre-fix witness must not contain runtime actions or semantic match.'
Assert-Static ([string]$historicalAudit.status -eq 'passed_static_only' -and [string]$historicalAudit.issueId -eq $issueId) 'historical_audit_preserved' 'pre-fix current-head audit must remain historical static evidence.'
Assert-Static ([string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and [int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'state_baseline' 'machine baseline drifted.'
Assert-Static ([string]$state.governance.activeIssueId -eq $issueId -and [string]$state.governance.status -eq 'running') 'active_issue' 'S2T must remain the sole in-progress machine issue during this contract.'
Assert-Static ([string]$objective.authority.activeIssueId -eq $issueId -and [string]$objective.executionTarget.currentIssue -eq $issueId) 'objective_binding' 'objective does not select S2T.'

Assert-Static ($rawRuntime.Contains('var java = {') -and $rawRuntime.Contains('t2s: function (value)') -and $rawRuntime.Contains('s2t: function (value)')) 'default_runtime_member' 'default ArkWeb java object must expose both t2s and s2t.'
Assert-Static (([regex]::Matches($rawRuntime, 's2t:\s*function\s*\(value\)')).Count -eq 1) 'default_runtime_unique_member' 'default ArkWeb runtime must contain exactly one s2t member.'
Assert-Static ($rawRuntime.Contains("String(value || '')") -and $rawRuntime.Contains('map[text[i]] || text[i]')) 'default_runtime_boundary' 's2t must preserve the t2s-style string coercion and unmapped-character boundary.'
Assert-Static ($runtimeV2.Contains('legado_runtime') -or $runtimeV2.Contains('loadRuntime')) 'runtime_loader' 'V2 runtime loader path is not present.'
Assert-Static ($engine.Contains('s2t: function(text)')) 'native_alignment' 'diagnostic Native JSVM s2t path is missing.'
Assert-Static ($registry.Contains("this.add('java.s2t', LegadoJsApiStatus.SUPPORTED") -and ([regex]::Matches($registry, "this\.add\('java\.s2t'")).Count -eq 1) 'registry_supported' 'registry must register java.s2t exactly once as SUPPORTED.'
Assert-Static ($legadoExtensions.Contains('fun s2t(text: String): String') -and $legadoExtensions.Contains('return ChineseUtils.s2t(text)')) 'legado_reference' 'fixed Legado s2t declaration and ChineseUtils handoff are missing.'
Assert-Static ($chineseUtils.Contains('fun s2t(content: String): String') -and $chineseUtils.Contains('ChineseUtils.s2t(content)')) 'legado_conversion_boundary' 'fixed Legado ChineseUtils.s2t boundary is missing.'
Assert-Static ($compiler.Contains('Legado') -and $analyzer.Contains('Rule') -and $scriptRuntime.Contains('variable')) 'analyzer_consumer_paths' 'Analyzer/compiler/script consumer paths are not present.'
Assert-Static ($orchestrator.Contains('Search') -and $orchestrator.Contains('Explore') -and $orchestrator.Contains('Content')) 'workflow_consumer_paths' 'workflow consumer paths are not present.'
Assert-Static ($types.Contains('TEXT') -or $types.Contains('outputKind')) 'output_consumer_paths' 'typed output consumer path is not present.'
Assert-Static (@($fixture.consumerMatrix).Count -eq 6) 'consumer_matrix' 'candidate consumer matrix must contain six layers.'

$conversionCases = @($fixture.conversionCases)
foreach ($case in $conversionCases) {
  $input = [string]$case.input
  $expected = [string]$case.expected
  Assert-Static ($input.Length -eq $expected.Length) ("case_length_{0}" -f [string]$case.id) 'static mapping cases must preserve character count.'
  $limit = [Math]::Min($input.Length, $expected.Length)
  for ($index = 0; $index -lt $limit; $index++) {
    $inputChar = $input.Substring($index, 1)
    $expectedChar = $expected.Substring($index, 1)
    if ($inputChar -ne $expectedChar) {
      $pair = "'$inputChar':'$expectedChar'"
      Assert-Static ($rawRuntime.Contains($pair)) ("case_mapping_{0}_{1}" -f [string]$case.id, $index) ("default runtime mapping is missing $pair")
    }
  }
}

Assert-Static (@($fixture.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$fixture.semanticMatchAllowed) 'fixture_runtime_gate' 'fixture must remain static-only.'

$currentHeadPaths = @(
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
$currentHeadHashes = @($currentHeadPaths | ForEach-Object {
  [pscustomobject][ordered]@{ path = $_; sha256 = Get-Sha256 $_ }
})

$status = if ($script:failures.Count -eq 0) { 'passed_static_only' } else { 'failed' }
$contractPath = Get-RepoPath $contractRelative
$sourceFixPath = Get-RepoPath $sourceFixRelative
$currentHeadPath = Get-RepoPath $currentHeadRelative
$contract = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_jsapi_s2t_default_runtime_post_fix_contract'
  issueId = $issueId
  status = $status
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  targetRevision = $targetRevision
  baseline = $fixture.baseline
  fixture = $fixtureRelative
  preFixFailureWitness = [pscustomobject][ordered]@{ path = $preFixRelative; sha256 = $preFixHash; status = [string]$preFix.status }
  historicalCurrentHeadAudit = [pscustomobject][ordered]@{ path = $historicalAuditRelative; sha256 = $historicalAuditHash; status = [string]$historicalAudit.status }
  assertions = $script:assertions
  failures = @($script:failures.ToArray())
  conversionCases = $conversionCases
  defaultRuntimeMember = 'java.s2t'
  registryStatus = 'SUPPORTED'
  currentHeadHashes = $currentHeadHashes
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_static_post_fix_contract_only;R4_runtime_differential_build_and_device_deferred'
  closeCondition = [string]$fixture.closeCondition
}
$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_jsapi_s2t_default_runtime_source_fix'
  issueId = $issueId
  status = $status
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  targetRevision = $targetRevision
  baseline = $fixture.baseline
  changedFiles = @(
    'entry/src/main/resources/rawfile/legado_runtime.html',
    'entry/src/main/ets/Framework/Novel/LegadoJsApiContractRegistry.ets'
  )
  sourceFixSummary = 'Default ArkWeb java.s2t was added with the frozen t2s-style mapping boundary and registered as SUPPORTED; Native JSVM remains diagnostic-only.'
  failureWitnessPath = $preFixRelative
  postFixContractPath = $contractRelative
  currentHeadAuditPath = $currentHeadRelative
  assertions = $script:assertions
  failures = @($script:failures.ToArray())
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_source_fix_static_only;R4_runtime_differential_build_and_device_deferred'
}
$currentHeadAudit = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_jsapi_s2t_default_runtime_current_head_audit_post_fix'
  issueId = $issueId
  status = $status
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  targetRevision = $targetRevision
  baseline = $fixture.baseline
  currentHeadHashes = $currentHeadHashes
  preFixEvidence = [pscustomobject][ordered]@{ path = $preFixRelative; sha256 = $preFixHash; status = [string]$preFix.status }
  assertions = $script:assertions
  failures = @($script:failures.ToArray())
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_current_head_static_audit_only;R4_runtime_differential_build_and_device_deferred'
}

Write-AtomicJson -Path $contractPath -Value $contract
Write-AtomicJson -Path $sourceFixPath -Value $sourceFix
Write-AtomicJson -Path $currentHeadPath -Value $currentHeadAudit
$contract | ConvertTo-Json -Depth 40
if ($status -ne 'passed_static_only') { exit 1 }
