param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-structural-tag-scanner-context.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-structural-tag-scanner-pre-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$RelativePath); return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$RelativePath); $path = Get-RepoPath $RelativePath; if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required file is missing: $RelativePath" }; $bytes = [System.IO.File]::ReadAllBytes($path); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }; return $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$RelativePath); return (Read-StrictText -RelativePath $RelativePath | ConvertFrom-Json -Depth 100) }
function Assert-Witness { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 structural tag-scanner failure witness failed: $Message" }; $script:assertions++ }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value); $path = Get-RepoPath $RelativePath; $directory = Split-Path -Parent $path; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporaryPath -Destination $path -Force } finally { if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) } } }

$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$fixture = Read-StrictJson -RelativePath $FixturePath
$state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$analyzer = Read-StrictText -RelativePath $analyzerPath

Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline drifted.'
Assert-Witness ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and -not [bool]$state.governance.semanticMatchAllowed) '243 queue binding drifted.'
Assert-Witness ([string]$fixture.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and @($fixture.cases).Count -eq 5) 'fixture binding changed.'
Assert-Witness ([string]$fixture.cases[0].html -like '*data-note="a > <fake>"*') 'quoted markup-like attribute fixture is missing.'
Assert-Witness ($analyzer.Contains('const tagRegex = /<([a-zA-Z][a-zA-Z0-9]*)[^>]*>/g;')) 'getChildElements raw tag regex was already removed before the failure witness.'
Assert-Witness ($analyzer.Contains('const openingMatch = html.substring(index).match(/^<([a-zA-Z][a-zA-Z0-9]*)[^>]*>/);')) 'findDirectChildOccurrences raw opening regex was already removed before the failure witness.'
Assert-Witness ($analyzer.Contains('const anyTagMatch = html.substring(i).match(/^<\/?([a-zA-Z][a-zA-Z0-9]*)[^>]*>/);')) 'findDirectChildren raw tag regex was already removed before the failure witness.'
Assert-Witness ($analyzer.Contains('const tagMatch = content.substring(i).match(/^<\/?([a-zA-Z][a-zA-Z0-9]*)[^>]*>/);')) 'findParentEndTag raw tag regex was already removed before the failure witness.'
Assert-Witness ($analyzer.Contains("while (tagEnd >= 0 && content[tagEnd] !== '>' )") -or $analyzer.Contains("while (tagEnd >= 0 && content[tagEnd] !== '>'")) 'findParentStartTag quote-blind backwards scan was already removed before the failure witness.'
Assert-Witness ($analyzer.Contains('const tagRegex = /<([a-zA-Z][a-zA-Z0-9]*)[^>]*>/g;') -and $analyzer.Contains('private findAllElements(html: string): string[]')) 'findAllElements raw wildcard traversal path was already removed before the failure witness.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'failure_witness'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  failureClass = 'v2_structural_html_scanners_are_not_quote_aware_and_wildcard_descendants_are_truncated'
  selectionPaths = @($fixture.selectionPaths)
  affectedCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  failureWitness = [pscustomobject][ordered]@{
    branch = 'LegadoRuleAnalyzer structural string fallback'
    observed = 'Structural helpers use raw tag regular expressions or backwards/forwards > scans; findAllElements advances past a complete element after each match and therefore does not enumerate nested wildcard descendants.'
    sourcePatterns = @('getChildElements', 'findDirectChildren', 'findParentEndTag', 'findParentStartTag', 'findAllElements', 'findDirectChildOccurrences')
    expected = 'Use one quote-aware tag scanner for structural traversal and return all descendant elements in document order for wildcard XPath axes.'
    legadoReference = 'Pinned Legado AnalyzeByJSoup delegates to a parsed Jsoup DOM; parent, sibling, child and descendant axes operate on element nodes, never markup-like attribute text.'
  }
  assertions = $script:assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_structural_tag_scanner_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
}
Write-AtomicJson -RelativePath $ResultPath -Value $result
$result | ConvertTo-Json -Depth 100
