[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-url-attribute-resolution-011-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$utf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBom = [System.Text.UTF8Encoding]::new($false)
$sourceCount = 458
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-011'

function Get-Path([string]$RelativePath) { Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-Text([string]$RelativePath) {
  $path = Get-Path $RelativePath
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191) { throw "UTF-8 BOM: $RelativePath" }
  return $utf8.GetString($bytes)
}
function Read-Json([string]$RelativePath) { return (Read-Text $RelativePath | ConvertFrom-Json) }
function Get-Hash([string]$RelativePath) { return (Get-FileHash -LiteralPath (Get-Path $RelativePath) -Algorithm SHA256).Hash.ToUpperInvariant() }
function Assert-Contract([bool]$Condition, [string]$Message) { if (-not $Condition) { throw "CONTRACT_FAILED:$Message" } }
function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-Path $RelativePath
  $dir = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $dir)) { [IO.Directory]::CreateDirectory($dir) | Out-Null }
  $tmp = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try { [IO.File]::WriteAllText($tmp, ($Value | ConvertTo-Json -Depth 30), $noBom); Move-Item -LiteralPath $tmp -Destination $path -Force }
  finally { if (Test-Path -LiteralPath $tmp) { [IO.File]::Delete($tmp) } }
}

$fixture = Read-Json 'tools/legado-compat/fixtures/legado-url-attribute-resolution-011.json'
$legadoJsoupPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$legadoRulePath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeRule.kt'
$v2AnalyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$v2WorkflowPath = 'entry/src/main/ets/Framework/Novel/LegadoWorkflowOrchestrator.ets'
$legadoJsoup = Read-Text $legadoJsoupPath
$legadoRule = Read-Text $legadoRulePath
$v2Analyzer = Read-Text $v2AnalyzerPath
$v2Workflow = Read-Text $v2WorkflowPath
$assertions = 0
Assert-Contract ([int]$fixture.baseline.sourceCount -eq $sourceCount) 'fixture source count drifted'; $assertions++
Assert-Contract ([string]$fixture.baseline.sourcePackageSha256 -eq $sourceHash) 'fixture source hash drifted'; $assertions++
Assert-Contract ([string]$fixture.baseline.legadoCommit -eq $legadoCommit) 'fixture Legado commit drifted'; $assertions++
Assert-Contract (@($fixture.cases).Count -eq 4) 'fixture case count must remain four'; $assertions++
Assert-Contract ($legadoJsoup.Contains('val url = element.attr(lastRule)')) 'Legado AnalyzeByJSoup must read Element.attr'; $assertions++
Assert-Contract ($legadoJsoup.Contains('internal fun getString0')) 'Legado URL extraction must have first-value path'; $assertions++
Assert-Contract ($legadoRule.Contains('NetworkUtils.getAbsoluteURL(redirectUrl, str)')) 'Legado URL consumer must resolve only at AnalyzeRule URL boundary'; $assertions++
Assert-Contract ($legadoRule.Contains('NetworkUtils.getAbsoluteURL(redirectUrl, url.toString())')) 'Legado URL list consumer must resolve each value'; $assertions++
Assert-Contract ($v2Analyzer.Contains('private getStringListByCSS(selector: string): string[]')) 'V2 analyzer must keep a list extraction path'; $assertions++
Assert-Contract ($v2Analyzer.Contains('elements.map((el: string): string => this.extractAttribute(el, result.attr))')) 'V2 list extraction must preserve each raw attribute value'; $assertions++
Assert-Contract ($v2Analyzer.Contains('async getUrlStringAsync') -and $v2Analyzer.Contains('async getUrlStringListAsync')) 'V2 analyzer must separate URL consumers from selector extraction'; $assertions++
Assert-Contract ($v2Analyzer.Contains('AnalyzeByJSoup uses Element.attr here and keeps the source value') -and
  $v2Analyzer.Contains('unchanged. URL consumers decide when and against which redirect')) 'V2 analyzer must document raw attribute semantics'; $assertions++
Assert-Contract ($v2Workflow.Contains('private resolveRequestUrlTemplate') -and $v2Workflow.Contains('requestCarrier')) 'V2 workflow must own URL resolution and carrier handoff'; $assertions++
Assert-Contract ($v2Workflow.Contains('getContentNextUrls') -and $v2Workflow.Contains('getTocNextUrls')) 'Toc and Content pagination must consume URL lists'; $assertions++

$references = [ordered]@{
  legado = @(
    [ordered]@{ path = $legadoJsoupPath; lines = '48-80,272-276'; sha256 = Get-Hash $legadoJsoupPath },
    [ordered]@{ path = $legadoRulePath; lines = '263-319'; sha256 = Get-Hash $legadoRulePath }
  )
  v2 = @(
    [ordered]@{ path = $v2AnalyzerPath; lines = '935-1042,1693-1738,3436-3660,4663-4670,5325-5380'; sha256 = Get-Hash $v2AnalyzerPath },
    [ordered]@{ path = $v2WorkflowPath; lines = '383-420,663-715,805-835,2270-2470'; sha256 = Get-Hash $v2WorkflowPath }
  )
}
$result = [ordered]@{
  schemaVersion = 1
  kind = 'legado_issue_011_url_attribute_static_contract'
  status = 'passed_static_only'
  issueId = $issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  fixturePath = 'tools/legado-compat/fixtures/legado-url-attribute-resolution-011.json'
  assertions = $assertions
  references = $references
  consumerMatrix = @(
    'Analyzer: Element.attr-compatible raw href/src/data-* extraction and multi-value list projection',
    'Rule IR: source rule node remains distinguishable from URL resolution node',
    'ArkWeb/JSVM: selector extraction does not resolve or consume request option suffixes',
    'Workflow: Search/Explore/BookInfo/Toc/Content/File resolve URL at request-owning boundary',
    'Output: requestCarrier preserves resolved identity plus untouched URL option suffix'
  )
  semanticBoundary = 'selector extraction returns raw attributes; isUrl/request consumers resolve against effective redirect URL'
  closeCondition = 'R4 must run the affected source equivalence class, 458-source deterministic Harness, same-input Legado differential, build and device gates; no unexplained raw-versus-resolved or multi-value URL difference may remain.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_static_contract_only;R4_runtime_build_device_and_legado_diff_deferred'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 30
