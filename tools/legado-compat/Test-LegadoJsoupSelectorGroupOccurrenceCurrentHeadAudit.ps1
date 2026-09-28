[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-selector-group-occurrence-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-selector-group-occurrence-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-selector-group-occurrence-post-fix-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/v2-jsoup-selector-group-occurrence-current-head-audit-20260810.json'
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
function Assert-Audit { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 selector-group occurrence current-head audit failed: $Message" }; $script:assertions++ }
function Get-TextHash { param([Parameter(Mandatory = $true)][string]$Text); $sha = [System.Security.Cryptography.SHA256]::Create(); try { return ([System.BitConverter]::ToString($sha.ComputeHash($strictUtf8.GetBytes($Text)))).Replace('-', '').ToUpperInvariant() } finally { $sha.Dispose() } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value); $path = Get-RepoPath $RelativePath; $directory = Split-Path -Parent $path; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temp = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temp -Destination $path -Force } finally { if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) } } }

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$contract = Read-StrictJson $PostFixContractPath
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$elementPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$analyzer = Read-StrictText $analyzerPath
$element = Read-StrictText $elementPath
$legado = Read-StrictText $legadoPath

Assert-Audit ([string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and [string]$state.governance.status -eq 'running' -and -not [bool]$state.governance.semanticMatchAllowed) '243 queue binding drifted.'
Assert-Audit ([string]$failure.status -eq 'failed' -and [string]$contract.status -eq 'passed') 'failure witness and post-fix contract must be present.'
Assert-Audit (@($failure.runtimeActionsPerformed).Count -eq 0 -and @($contract.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$contract.semanticMatchAllowed) 'audit must remain static-only.'
Assert-Audit ([string]$fixture.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and @($fixture.cases).Count -eq 2 -and @($fixture.affectedSourceSet.sourceOrdinals) -contains 97) 'selector-group fixture binding drifted.'
Assert-Audit ([string]$fixture.html -eq '<section><p>same</p><p>same</p></section>' -and [regex]::Matches([string]$fixture.html, '<p>same</p>').Count -eq 2) 'fixture must contain two distinct nodes with identical outerHTML.'
Assert-Audit ([int]$fixture.cases[0].expectedCount -eq 2 -and [int]$fixture.cases[1].expectedCount -eq 1) 'fixture must distinguish occurrence union from same-node de-duplication.'
Assert-Audit ($analyzer.Contains('mergeSelectorGroupResultsByOccurrence') -and $analyzer.Contains('seenOffsets')) 'occurrence-aware string consumer is absent.'
Assert-Audit ($analyzer.Contains('annotateStringSelectorHtml(html: string, baseOffset: number)') -and $analyzer.Contains('data-legado-occurrence-index')) 'selector-group evaluation must carry explicit source occurrence markers.'
Assert-Audit ($analyzer.Contains('findAnnotatedSelectorOccurrences(') -and $analyzer.Contains('absoluteOffset = parseInt(markerMatch[1], 10)')) 'marked selector results must be restored to source occurrences.'
Assert-Audit ($analyzer.Contains('const selectionContextHtml = needsOccurrenceMarkers') -and $analyzer.Contains('return this.stripStringSelectorOccurrenceMarker(element);')) 'large-document CSS chains must preserve and strip occurrence markers at the workflow boundary.'
Assert-Audit ($analyzer.Contains('if (html.includes(') -and $analyzer.Contains('data-legado-occurrence-index') -and $analyzer.Contains('return html;')) 'occurrence annotation must be idempotent across nested selector evaluation.'
Assert-Audit ($analyzer.Contains('originalHtml.includes(') -and $analyzer.Contains('stripStringSelectorOccurrenceMarker(markedResult)')) 'nested marked fragments must preserve absolute offsets while restoring unmarked elements.'
Assert-Audit ($element.Contains('const seen = new Set<HTMLElement>();')) 'DOM identity consumer is absent.'
Assert-Audit ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado consumer is absent.'
Assert-Audit ((Get-TextHash $analyzer).Length -eq 64 -and (Get-TextHash $element).Length -eq 64) 'current source hashes are not SHA-256.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'v2_jsoup_selector_group_occurrence_current_head_audit'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'passed'
  assertions = $script:assertions
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  sourceHashes = [pscustomobject][ordered]@{ $analyzerPath = Get-TextHash $analyzer; $elementPath = Get-TextHash $element; $legadoPath = Get-TextHash $legado }
  consumerMatrix = [pscustomobject][ordered]@{ stringFallback = $analyzerPath; dom = $elementPath; legado = $legadoPath }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_selector_group_occurrence_current_head_static_audit_only;runtime_regression_build_device_and_legado_diff_deferred'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
