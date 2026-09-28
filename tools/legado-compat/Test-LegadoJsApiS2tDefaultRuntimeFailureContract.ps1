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
  $OutputPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-jsapi-s2t-default-runtime-pre-fix-20260809.json'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-JSAPI-JAVA-S2T-DEFAULT-RUNTIME'
$assertions = 0
$failures = New-Object 'System.Collections.Generic.List[string]'

function Read-Json {
  param([string]$RelativePath)
  $path = Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing JSON: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes) | ConvertFrom-Json
}

function Read-Text {
  param([string]$RelativePath)
  $path = Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing text: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}

function Assert-Contract {
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
$state = Read-Json 'tools/legado-compat/state/full-source-validation-state.json'
$mapping = Read-Json 'tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/reference-mapping.json'
$legadoExtensions = Read-Text 'legado/app/src/main/java/io/legado/app/help/JsExtensions.kt'
$rawRuntime = Read-Text 'entry/src/main/resources/rawfile/legado_runtime.html'
$runtimeV2 = Read-Text 'entry/src/main/ets/Framework/Novel/LegadoRuntimeV2.ets'
$engine = Read-Text 'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets'
$registry = Read-Text 'entry/src/main/ets/Framework/Novel/LegadoJsApiContractRegistry.ets'

Assert-Contract ([string]$fixture.issueId -eq $issueId) 'fixture_issue' 'fixture is not bound to the s2t root cause.'
Assert-Contract ([int]$fixture.baseline.sourceCount -eq 458 -and [string]$fixture.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$fixture.baseline.legadoCommit -eq $legadoCommit) 'fixture_baseline' 'fixture baseline drifted.'
Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'state_baseline' 'machine baseline drifted.'
Assert-Contract ([string]$fixture.api.name -eq 'java.s2t' -and [int]$fixture.api.occurrenceCount -eq 4 -and [int]$fixture.api.callLikeCount -eq 4) 'api_counts' 's2t call counts drifted.'
Assert-Contract (@($fixture.api.affectedSourceOrdinals) -join ',' -eq '9,10,202,226') 'affected_ordinals' 'affected source ordinals drifted.'
Assert-Contract (@($fixture.api.affectedSourceHashPrefixes).Count -eq 4) 'affected_hashes' 'affected source hash prefixes are incomplete.'
Assert-Contract ([int]$mapping.apiMappings.'java.s2t'.occurrenceCount -eq 4 -and [int]$mapping.apiMappings.'java.s2t'.sourceCount -eq 4) 'mapping_binding' 'reference mapping does not contain four s2t occurrences.'
Assert-Contract ($legadoExtensions.Contains('fun t2s(text: String): String') -and $legadoExtensions.Contains('fun s2t(text: String): String') -and $legadoExtensions.Contains('return ChineseUtils.s2t(text)')) 'legado_semantics' 'fixed Legado s2t implementation is missing.'
Assert-Contract ($rawRuntime.Contains('t2s: function (value)') -and -not $rawRuntime.Contains('s2t: function (value)')) 'default_runtime_gap' 'pre-fix default runtime must expose t2s but not s2t.'
Assert-Contract (-not $runtimeV2.Contains('s2t')) 'runtime_loader_gap' 'V2 loader unexpectedly contains a direct s2t bridge before the default runtime fix.'
Assert-Contract ($engine.Contains('s2t: function(text)')) 'diagnostic_native_shim' 'diagnostic Native JSVM s2t marker is missing.'
Assert-Contract ($registry.Contains("this.add('java.t2s'") -and -not $registry.Contains("this.add('java.s2t'")) 'registry_gap' 'capability registry must remain unregistered in the pre-fix witness.'
Assert-Contract (@($fixture.consumerMatrix).Count -eq 6) 'consumer_matrix' 'all six V2 consumer layers must be listed.'
Assert-Contract ([string]$fixture.primaryCause -eq 'default_arkweb_runtime_capability_injection_missing_java_s2t') 'primary_cause' 'primary cause must be the default ArkWeb injection gap.'
Assert-Contract ([string]$fixture.classification -eq 'UNSUPPORTED_API') 'classification' 'pre-fix state must remain unsupported_api.'
Assert-Contract (@($fixture.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$fixture.semanticMatchAllowed) 'static_only' 'failure witness cannot perform runtime actions or authorize semantic match.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_jsapi_s2t_default_runtime_pre_fix_contract'
  issueId = $issueId
  status = if ($script:failures.Count -eq 0) { 'failed' } else { 'contract_error' }
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = $fixture.baseline
  fixture = 'tools/legado-compat/fixtures/legado-jsapi-s2t-default-runtime.json'
  assertions = $script:assertions
  failedAssertions = @($script:failures.ToArray())
  primaryCause = [string]$fixture.primaryCause
  classification = [string]$fixture.classification
  affectedSourceOrdinals = @($fixture.api.affectedSourceOrdinals)
  expectedDefaultRuntimeMember = 'java.s2t'
  observedDefaultRuntimeMember = 'missing'
  diagnosticNativeMember = 'present_but_non_default'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_static_failure_witness_only;source_fix_and_R4_runtime_differential_deferred'
  closeCondition = [string]$fixture.closeCondition
}
Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Depth 20
if ([string]$result.status -ne 'failed') { exit 1 }
