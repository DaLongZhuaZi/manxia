[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-has-pseudo-selector.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-has-pseudo-selector-pre-fix-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing JSON: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  try { return ($strictUtf8.GetString($bytes) | ConvertFrom-Json) } catch { throw "Invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Get-GitFileText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $text = (& git -C $RepositoryRoot show ("HEAD:" + $RelativePath) 2>$null | Out-String)
  if (-not $?) { throw "Unable to read baseline file from git HEAD: $RelativePath" }
  return $text
}

function Get-LegadoFileText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing Legado reference file: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}

function Get-TextHash {
  param([Parameter(Mandatory = $true)][string]$Text)
  $bytes = $strictUtf8.GetBytes($Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToUpperInvariant() }
  finally { $sha.Dispose() }
}

function Assert-Witness {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Legado Jsoup :has pre-fix witness failed: $Message" }
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value)
  $absolute = Get-RepoPath -RelativePath $RelativePath
  $directory = Split-Path -Parent $absolute
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$absolute.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 40), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $absolute -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$fixture = Read-StrictJson -RelativePath $FixturePath
$state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$result = $null
try {
  Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$state.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'frozen baseline drifted.'
  Assert-Witness ([string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS') '235 must remain active while 236 pre-fix evidence is recorded.'
  Assert-Witness ([string]$fixture.contract -eq 'legado_jsoup_has_pseudo_selector' -and @($fixture.cases).Count -eq 5) 'the five-case :has fixture changed.'

  $paths = @(
    'entry/src/main/ets/libs/htmlparser/HTMLElement.ets',
    'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
    'entry/src/main/resources/rawfile/legado_runtime.html'
  )
  $baselineTexts = [ordered]@{}
  $baselineHashes = [ordered]@{}
  foreach ($path in $paths) {
    $text = Get-GitFileText -RelativePath $path
    $baselineTexts[$path] = $text
    $baselineHashes[$path] = Get-TextHash -Text $text
  }
  $element = [string]$baselineTexts[$paths[0]]
  $analyzer = [string]$baselineTexts[$paths[1]]
  $runtime = [string]$baselineTexts[$paths[2]]
  Assert-Witness (-not $element.Contains("pseudo.name === 'has'") -and -not $element.Contains("argument.startsWith('>')") -and -not $element.Contains('elem.querySelectorAll(argument)')) 'HEAD DOM matcher has no :has implementation.'
  Assert-Witness (-not $analyzer.Contains("pseudo.name === 'has'") -and -not $analyzer.Contains('matchesStringHasPseudo')) 'HEAD string fallback has no :has implementation.'
  Assert-Witness (-not $runtime.Contains("name === 'has'") -and -not $runtime.Contains('relativeSelector') -and -not $runtime.Contains('legadoSelectWithJsoupRegex(node')) 'HEAD ArkWeb runtime has no :has implementation.'

  $legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
  $legadoHead = (& git -C (Get-RepoPath -RelativePath 'legado') rev-parse HEAD 2>$null | Out-String).Trim()
  Assert-Witness ($legadoHead -eq [string]$state.baseline.legadoCommit) 'Legado checkout is not at the pinned commit.'
  $legadoText = Get-LegadoFileText -RelativePath $legadoPath
  Assert-Witness ($legadoText.Contains('temp.select(ruleStr)') -and $legadoText.Contains('element.text()') -and $legadoText.Contains('element.ownText()')) 'fixed Legado AnalyzeByJSoup selector and text handoff is not present.'

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_jsoup_has_pseudo_selector_pre_fix_contract'
    issueId = 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    classification = 'v2_has_pseudo_selector_missing_in_baseline_dom_string_and_arkweb_paths'
    baseline = [pscustomobject][ordered]@{
      sourceCount = [int]$state.baseline.sourceCount
      sourcePackageSha256 = [string]$state.baseline.sourcePackageSha256
      legadoCommit = [string]$state.baseline.legadoCommit
      projectHead = (& git -C $RepositoryRoot rev-parse HEAD 2>$null | Out-String).Trim()
    }
    fixture = $FixturePath
    impact = [pscustomobject][ordered]@{ ruleStringCount = 70; affectedSourceCount = 5; baselineSourceCount = 458 }
    failingCases = @($fixture.cases | ForEach-Object { [string]$_.id })
    staticWitnesses = @(
      [pscustomobject][ordered]@{ path = $paths[0]; finding = 'baseline HEAD has no :has pseudo branch, descendant query or direct-child argument handling.' },
      [pscustomobject][ordered]@{ path = $paths[1]; finding = 'baseline HEAD has no complete-element string fallback for :has, so nested/direct-child predicates cannot be evaluated.' },
      [pscustomobject][ordered]@{ path = $paths[2]; finding = 'baseline HEAD has no ArkWeb :has bridge or relative-selector projection.' },
      [pscustomobject][ordered]@{ path = $legadoPath; finding = 'fixed Legado delegates CSS selection to Jsoup Element.select and projects Element.text/ownText.' }
    )
    baselineSourceHashes = $baselineHashes
    rootCauseDecision = 'pending_236_consumer_mapping_and_current_head_audit; do not activate 236 until the static transition gate passes.'
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_236_pre_fix_witness_only;runtime_regression_build_device_and_legado_diff_deferred'
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_jsoup_has_pseudo_selector_pre_fix_contract'
    issueId = 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR'
    status = 'contract_error'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    error = $_.Exception.Message
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_236_pre_fix_witness_only;runtime_regression_build_device_and_legado_diff_deferred'
  }
}

Write-AtomicJson -RelativePath $OutputPath -Value $result
$result | ConvertTo-Json -Depth 40
if ([string]$result.status -eq 'contract_error') { exit 1 }
