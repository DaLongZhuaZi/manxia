[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-dom-selector-group-document-order-context.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-dom-selector-group-document-order-pre-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$RelativePath); return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "required file is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return $strictUtf8.GetString($bytes)
}
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100) }
function Assert-Witness { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 DOM selector-group document-order witness failed: $Message" }; $script:assertions++ }
function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$fixture = Read-StrictJson -Path (Get-RepoPath $FixturePath)
$state = Read-StrictJson -Path (Get-RepoPath 'tools/legado-compat/state/full-source-validation-state.json')
$elementPath = Get-RepoPath 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$element = Read-StrictText -Path $elementPath
$sourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
$packageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePackagePath).Hash.ToUpperInvariant()
$sourceObjects = @($strictUtf8.GetString([System.IO.File]::ReadAllBytes($sourcePackagePath)) | ConvertFrom-Json -Depth 100)
$queryStart = $element.IndexOf('  querySelectorAll(selector: string): HTMLElement[] {')
$queryEnd = $element.IndexOf("`r`n  /**", $queryStart + 1)
if ($queryEnd -lt 0) { $queryEnd = $element.IndexOf("`n  /**", $queryStart + 1) }
$queryBody = if ($queryStart -ge 0 -and $queryEnd -gt $queryStart) { $element.Substring($queryStart, $queryEnd - $queryStart) } else { '' }
$representative = ($sourceObjects[96] | ConvertTo-Json -Depth 100 -Compress)

Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline drifted.'
Assert-Witness ($packageHash -eq $baselineHash -and $sourceObjects.Count -eq 458) 'frozen source package drifted.'
Assert-Witness ([string]$fixture.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and @($fixture.cases).Count -eq 2) 'fixture binding or case count changed.'
Assert-Witness ($representative.Contains('.book_other:nth-child(4)') -and $representative.Contains('.book_other:nth-child(5)')) 'ordinal 97 selector-group source binding is missing.'
Assert-Witness ($queryBody.Contains('for (const chain of selectorGroups)') -and $queryBody.Contains('if (!seen.has(match))') -and $queryBody.Contains('results.push(match)')) 'selector-group union branch is missing.'
Assert-Witness (-not $queryBody.Contains('results.sort(') -and -not $queryBody.Contains('documentOrder')) 'the DOM union has no document-order projection.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'failure_witness'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  failureClass = 'v2_dom_selector_group_union_is_not_in_document_order'
  selectionPath = @($fixture.selectionPath)
  affectedCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  affectedSourceSet = $fixture.representativeSourceSet
  failureWitness = [pscustomobject][ordered]@{
    branch = 'HTMLElement.querySelectorAll -> selector-group union'
    observed = 'Each selector group is appended in declaration order and only object identity is de-duplicated; no document-order sort is applied.'
    expected = 'Jsoup Element.select returns the union in source-document order and de-duplicates only the same Element node.'
    sourcePattern = 'for (const chain of selectorGroups) { ... results.push(match) } without a final document-order projection'
  }
  sourcePaths = @('entry/src/main/ets/libs/htmlparser/HTMLElement.ets', 'entry/src/main/ets/libs/htmlparser/LegadoHtmlBridge.ets', 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt')
  assertions = $script:assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred'
}
Write-AtomicJson -Path (Get-RepoPath $ResultPath) -Value $result
$result | ConvertTo-Json -Depth 100
