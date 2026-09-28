[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$EvidencePath = 'tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/semantic-settlement.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/semantic-contract.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
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
  return $utf8Strict.GetString([System.IO.File]::ReadAllBytes($path)) | ConvertFrom-Json
}

function Read-Text {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing text: $RelativePath" }
  return $utf8Strict.GetString([System.IO.File]::ReadAllBytes($path))
}

function Assert-Contract {
  param([bool]$Condition, [string]$Id, [string]$Message)
  $script:assertions++
  if ($Condition) {
    return
  }
  [void]$script:failures.Add("${Id}: $Message")
}

function Write-AtomicJson {
  param([string]$RelativePath, [object]$Value)
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 70), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$evidence = Read-Json $EvidencePath
$mapping = Read-Json 'tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/reference-mapping.json'
$runtime = Read-Text 'entry/src/main/resources/rawfile/legado_runtime.html'
$jsApiRegistry = Read-Text 'entry/src/main/ets/Framework/Novel/LegadoJsApiContractRegistry.ets'
$legadoExtensions = Read-Text 'legado/app/src/main/java/io/legado/app/help/JsExtensions.kt'
$legadoAnalyzeRule = Read-Text 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeRule.kt'
$legadoAnalyzeUrl = Read-Text 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeUrl.kt'

Assert-Contract ([string]$evidence.status -eq 'passed_static_only') 'status' 'semantic settlement must be static-only passed.'
Assert-Contract ([string]$evidence.baseline.sourcePackageSha256 -eq $sourceHash -and [int]$evidence.baseline.sourceCount -eq 458 -and [string]$evidence.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'semantic settlement baseline drifted.'
Assert-Contract ([int]$evidence.summary.apiCount -eq 44 -and [int]$evidence.summary.occurrenceCount -eq 140 -and [int]$evidence.summary.callLikeCount -eq 98) 'counts' 'API, occurrence or call-like counts drifted.'
Assert-Contract ([int]$evidence.summary.namespaceOrImportCount -eq 7 -and [int]$evidence.summary.staticMemberReferenceCount -eq 6) 'static_categories' 'namespace/static-member categories drifted.'
Assert-Contract ([int]$evidence.summary.supportedCount -eq 6 -and [int]$evidence.summary.unsupportedApiCount -eq 24 -and [int]$evidence.summary.needsInteractionCount -eq 1) 'capability_categories' 'capability category counts drifted.'
Assert-Contract (@($evidence.settlements).Count -eq 44 -and @($mapping.apiMappings.PSObject.Properties).Count -eq 44) 'settlement_rows' 'settlement rows do not cover all mapped APIs.'
Assert-Contract ((@($evidence.settlements.occurrenceCount) | Measure-Object -Sum).Sum -eq 140) 'occurrence_sum' 'settlement occurrence sum is not 140.'
Assert-Contract ((@($evidence.settlements.callLikeCount) | Measure-Object -Sum).Sum -eq 98) 'call_like_sum' 'settlement call-like sum is not 98.'
Assert-Contract (@($evidence.settlements | Where-Object { @($_.affectedSourceOrdinals).Count -eq 0 }).Count -eq 0) 'source_binding' 'every API lacks an affected source binding.'
Assert-Contract (@($evidence.settlements | Where-Object { [bool]$_.semanticMatchAllowed }).Count -eq 0) 'semantic_gate' 'semanticMatchAllowed was enabled in static evidence.'
Assert-Contract (@($evidence.settlements | Where-Object { @($_.runtimeActionsPerformed).Count -gt 0 }).Count -eq 0) 'runtime_gate' 'runtime actions were recorded in static evidence.'

Assert-Contract ($legadoExtensions.Contains('fun androidId()') -and $legadoExtensions.Contains('fun bytesToStr(bytes: ByteArray)') -and $legadoExtensions.Contains('fun importScript(path: String)') -and $legadoExtensions.Contains('fun s2t(text: String)') -and $legadoExtensions.Contains('fun openUrl(url: String)')) 'legado_extensions' 'fixed JsExtensions declarations are missing.'
Assert-Contract ($legadoAnalyzeUrl.Contains('fun initUrl()') -and $legadoAnalyzeUrl.Contains('fun getStrResponse(') -and $legadoAnalyzeUrl.Contains('fun getUserAgent()')) 'legado_analyze_url' 'fixed AnalyzeUrl declarations are missing.'
Assert-Contract ($legadoAnalyzeRule.Contains('fun reGetBook()') -and $legadoAnalyzeRule.Contains('fun refreshTocUrl()')) 'legado_analyze_rule' 'fixed AnalyzeRule lifecycle declarations are missing.'

Assert-Contract ($runtime.Contains('head: function (url, headers)') -and $runtime.Contains('bytesToStr: function (bytes, charset)') -and $runtime.Contains('hexEncodeToString: function (value)') -and $runtime.Contains('importScript: function (path)') -and $runtime.Contains('Jsoup = {')) 'v2_supported_bridges' 'known V2 supported bridge implementations are missing.'
Assert-Contract (-not $runtime.Contains('androidId: function') -and -not $runtime.Contains('refreshTocUrl: function') -and -not $runtime.Contains('refreshExplore: function') -and -not $runtime.Contains('getStrResponse: function') -and -not $runtime.Contains('getUserAgent: function')) 'v2_absent_bridges' 'known V2 absent bridge unexpectedly appeared without a new contract.'
Assert-Contract ($jsApiRegistry.Contains("this.add('java.webView'") -and $jsApiRegistry.Contains("this.add('java.imageDecode'") -and $jsApiRegistry.Contains("this.add('java.getVerificationCode'")) 'registry_policy_examples' 'existing interaction/policy registry contracts are missing.'

$rawEvidence = $utf8Strict.GetString([System.IO.File]::ReadAllBytes((Get-RepoPath $EvidencePath)))
Assert-Contract (-not $rawEvidence.Contains('http://') -and -not $rawEvidence.Contains('https://')) 'redaction_urls' 'semantic evidence contains a raw URL.'
Assert-Contract (-not [regex]::IsMatch($rawEvidence, '(?i)"(?:cookie|set-cookie)"\s*:')) 'redaction_cookie' 'semantic evidence contains a raw cookie field.'
Assert-Contract (-not $rawEvidence.Contains('bookSourceName')) 'redaction_source_name' 'semantic evidence contains source names or raw source fields.'

$resultStatus = if ($failures.Count -eq 0) { 'passed' } else { 'failed' }
$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_js_api_capability_settlement_semantic_contract'
  status = $resultStatus
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  evidencePath = $EvidencePath
  assertions = $assertions
  failures = @($failures.ToArray())
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
}
Write-AtomicJson $ResultPath $result
if ($failures.Count -gt 0) {
  throw "JS API semantic contract failed: $($failures.Count) assertion(s). Evidence: $ResultPath"
}
Write-Output "JS_API_SEMANTIC_CONTRACT status=passed assertions=$assertions evidence=$ResultPath runtimeActions=0 semanticMatchAllowed=false"
