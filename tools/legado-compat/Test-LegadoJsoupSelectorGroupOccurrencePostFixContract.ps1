[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-selector-group-occurrence-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-selector-group-occurrence-pre-fix-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-selector-group-occurrence-post-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$RelativePath); return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$RelativePath); $path = Get-RepoPath $RelativePath; if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing text: $RelativePath" }; return $strictUtf8.GetString([System.IO.File]::ReadAllBytes($path)) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$RelativePath); return (Read-StrictText $RelativePath | ConvertFrom-Json -Depth 100) }
function Assert-Contract { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 selector-group occurrence post-fix contract failed: $Message" }; $script:assertions++ }
function Get-TextHash { param([Parameter(Mandatory = $true)][string]$Text); $sha = [System.Security.Cryptography.SHA256]::Create(); try { return ([System.BitConverter]::ToString($sha.ComputeHash($strictUtf8.GetBytes($Text)))).Replace('-', '').ToUpperInvariant() } finally { $sha.Dispose() } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value); $path = Get-RepoPath $RelativePath; $directory = Split-Path -Parent $path; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temp = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temp -Destination $path -Force } finally { if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) } } }

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$elementPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$analyzer = Read-StrictText $analyzerPath
$element = Read-StrictText $elementPath
$legado = Read-StrictText $legadoPath
$mergeStart = $analyzer.IndexOf('private mergeSelectorGroupResultsByOccurrence(')
$mergeEnd = if ($mergeStart -ge 0) { $analyzer.IndexOf(([Environment]::NewLine + '  /**'), $mergeStart) } else { -1 }
$mergeBody = if ($mergeStart -ge 0 -and $mergeEnd -gt $mergeStart) { $analyzer.Substring($mergeStart, $mergeEnd - $mergeStart) } else { '' }

Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$state.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'frozen baseline drifted.'
Assert-Contract ([string]$failure.status -eq 'failed' -and @($failure.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed) 'failure witness must remain failed and static-only.'
Assert-Contract ([string]$fixture.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and @($fixture.cases).Count -eq 2 -and @($fixture.affectedSourceSet.sourceOrdinals) -contains 97) 'selector-group fixture binding drifted.'
Assert-Contract ([string]$fixture.html -eq '<section><p>same</p><p>same</p></section>' -and [regex]::Matches([string]$fixture.html, '<p>same</p>').Count -eq 2) 'fixture must contain two distinct nodes with identical outerHTML.'
Assert-Contract ([int]$fixture.cases[0].expectedCount -eq 2 -and [int]$fixture.cases[1].expectedCount -eq 1) 'fixture must distinguish occurrence union from same-node de-duplication.'
Assert-Contract ($analyzer.Contains('private mergeSelectorGroupResultsByOccurrence(') -and $analyzer.Contains('const seenOffsets = new Set<number>();')) 'occurrence-aware selector-group merge is absent.'
Assert-Contract ($analyzer.Contains('const groupOccurrences = this.mapStringElementOccurrences(html, groupResults);') -and $analyzer.Contains('occurrences.sort(')) 'group results must be projected by source offset and returned in document order.'
Assert-Contract ($mergeBody.Length -gt 0 -and -not $mergeBody.Contains('const seen = new Set<string>();') -and -not $mergeBody.Contains('if (!seen.has(result))')) 'value-based selector-group deduplication remains in the selector-group merge branch.'
Assert-Contract ($analyzer.Contains('private annotateStringSelectorHtml(html: string, baseOffset: number): string') -and $analyzer.Contains('data-legado-occurrence-index')) 'selector-group evaluation must carry explicit source occurrence markers.'
Assert-Contract ($analyzer.Contains('private findAnnotatedSelectorOccurrences(') -and $analyzer.Contains('const absoluteOffset = parseInt(markerMatch[1], 10);')) 'marked selector results must be restored to source occurrences.'
Assert-Contract ($analyzer.Contains('const selectionContextHtml = needsOccurrenceMarkers') -and $analyzer.Contains('return this.stripStringSelectorOccurrenceMarker(element);')) 'large-document CSS chains must preserve and strip occurrence markers at the workflow boundary.'
Assert-Contract ($analyzer.Contains('if (html.includes(') -and $analyzer.Contains('data-legado-occurrence-index') -and $analyzer.Contains('return html;')) 'occurrence annotation must be idempotent across nested selector evaluation.'
Assert-Contract ($analyzer.Contains('originalHtml.includes(') -and $analyzer.Contains('stripStringSelectorOccurrenceMarker(markedResult)')) 'nested marked fragments must preserve absolute offsets while restoring unmarked elements.'
Assert-Contract ($element.Contains('const seen = new Set<HTMLElement>();')) 'DOM selector groups must remain object-identity based.'
Assert-Contract ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado selector handoff is missing.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_jsoup_selector_group_occurrence_post_fix_contract'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'passed'
  assertions = $script:assertions
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  fixture = $FixturePath
  changedPaths = @($analyzerPath)
  impact = [pscustomobject][ordered]@{ baselineSourceCount = 458; affectedSourceOrdinals = @(97); ruleStringCount = 1; cases = 2 }
  verification = 'static_source_contract_only;runtime_regression_deferred'
  sourceHashes = [pscustomobject][ordered]@{ $analyzerPath = Get-TextHash $analyzer; $elementPath = Get-TextHash $element; $legadoPath = Get-TextHash $legado }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
