[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-selector-group-occurrence-context.json',
  [string]$SourcePackagePath = 'F:/Downloads-E/墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json',
  [string]$PreFixSnapshotPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets.bak_20260810_sibling_combinator',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-selector-group-occurrence-pre-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
}
function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  $resolved = Get-RepoPath $Path
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Missing text: $Path" }
  return $strictUtf8.GetString([System.IO.File]::ReadAllBytes($resolved))
}
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText $Path | ConvertFrom-Json -Depth 100) }
function Assert-Witness { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 selector-group occurrence failure witness failed: $Message" } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value); $path = Get-RepoPath $RelativePath; $directory = Split-Path -Parent $path; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temp = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temp -Destination $path -Force } finally { if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) } } }

$fixture = Read-StrictJson $FixturePath
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$analyzer = Read-StrictText $PreFixSnapshotPath
$legado = Read-StrictText $legadoPath
$packageBytes = [System.IO.File]::ReadAllBytes((Get-RepoPath $SourcePackagePath))
$sha = [System.Security.Cryptography.SHA256]::Create()
try { $packageHash = ([System.BitConverter]::ToString($sha.ComputeHash($packageBytes))).Replace('-', '').ToUpperInvariant() } finally { $sha.Dispose() }
$package = $strictUtf8.GetString($packageBytes) | ConvertFrom-Json -Depth 100
$target = @($package)[96]
$targetKind = [string]$target.ruleExplore.kind

Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen machine baseline drifted.'
Assert-Witness ([int]@($package).Count -eq 458 -and $packageHash -eq $baselineHash) 'pinned source package count or hash drifted.'
Assert-Witness ([string]$fixture.issueId -eq $issueId -and [string]$fixture.contract -eq 'legado_jsoup_selector_group_occurrence_context' -and @($fixture.cases).Count -eq 2) 'fixture binding or case count changed.'
Assert-Witness ([string]$fixture.html -eq '<section><p>same</p><p>same</p></section>' -and [regex]::Matches([string]$fixture.html, '<p>same</p>').Count -eq 2) 'fixture must contain two distinct nodes with identical outerHTML.'
Assert-Witness ([int]$fixture.cases[0].expectedCount -eq 2 -and [int]$fixture.cases[1].expectedCount -eq 1) 'fixture must distinguish occurrence union from same-node de-duplication.'
Assert-Witness ($targetKind -match '\.book_other:nth-child\(4\),\s*\.book_other:nth-child\(5\)') 'affected ordinal 97 selector-group evidence is missing.'
Assert-Witness ($analyzer.Contains('const seen = new Set<string>();') -and $analyzer.Contains('if (!seen.has(result))')) 'pre-fix string group de-duplication witness is absent.'
Assert-Witness (-not $analyzer.Contains('mergeSelectorGroupResultsByOccurrence')) 'pre-fix occurrence-aware group merge already exists.'
Assert-Witness ($analyzer.Contains('mapStringElementOccurrences(contextHtml, elements)') -and -not $analyzer.Contains('annotateStringSelectorHtml')) 'pre-fix context mapping snapshot is missing the duplicate-occurrence ambiguity.'
Assert-Witness ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado selector handoff is missing.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'failure_witness'
  issueId = $issueId
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  failureClass = 'v2_large_document_string_selector_group_deduplicates_equal_outer_html'
  fixturePath = $FixturePath
  sourcePackagePath = 'redacted_pinned_package'
  sourcePackageHash = $packageHash
  affectedSourceSet = [pscustomobject][ordered]@{ sourceOrdinals = @(97); ruleStringCount = 1; rulePaths = @('$[96].ruleExplore.kind') }
  sourcePaths = @($PreFixSnapshotPath, $legadoPath)
  preFixSnapshotPath = $PreFixSnapshotPath
  preFixSnapshotSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $PreFixSnapshotPath)).Hash.ToUpperInvariant()
  failureWitness = [pscustomobject][ordered]@{
    branch = 'findElementsBySingleSelector selectorGroups.length > 1'
    path = 'LegadoRuleAnalyzer.getElementsByCSSWithBridge -> findElementsBySingleSelector -> top-level selector-group union'
    observed = 'group results are de-duplicated by equal outerHTML strings, so two distinct matching nodes with identical markup collapse into one output.'
    expected = 'Jsoup Element.select retains distinct Element occurrences and de-duplicates only the same node identity while preserving document order.'
    secondaryObserved = 'The same pre-fix string pipeline maps a positional pseudo result back with indexOf from offset zero, so a selected last identical node can be mistaken for the first identical node before selector-group union.'
  }
  rootCauseDecision = 'The string fallback loses occurrence identity twice: selector-group union uses value identity (Set<string>) and context projection remaps positional results by first matching outerHTML. The pinned Legado contract requires source-node identity; the DOM matcher already de-duplicates by HTMLElement object identity.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_selector_group_occurrence_failure_witness_static_only;runtime_regression_build_device_and_legado_diff_deferred'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
