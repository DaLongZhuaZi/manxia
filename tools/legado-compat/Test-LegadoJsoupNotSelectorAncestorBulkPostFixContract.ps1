[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-not-selector-ancestor-context.json',
  [string]$AncestorFailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-not-selector-ancestor-pre-fix-20260810.json',
  [string]$BulkFailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-not-selector-ancestor-bulk-pre-fix-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-not-selector-ancestor-bulk-post-fix-20260810.json'
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
function Assert-Contract { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 :not ancestor bulk post-fix contract failed: $Message" }; $script:assertions++ }
function Get-TextHash { param([Parameter(Mandatory = $true)][string]$Text); $sha = [System.Security.Cryptography.SHA256]::Create(); try { return ([System.BitConverter]::ToString($sha.ComputeHash($strictUtf8.GetBytes($Text)))).Replace('-', '').ToUpperInvariant() } finally { $sha.Dispose() } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value); $path = Get-RepoPath $RelativePath; $directory = Split-Path -Parent $path; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temp = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temp -Destination $path -Force } finally { if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) } } }

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$ancestorFailure = Read-StrictJson $AncestorFailureWitnessPath
$bulkFailure = Read-StrictJson $BulkFailureWitnessPath
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$analyzer = Read-StrictText $analyzerPath
$legado = Read-StrictText $legadoPath
Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$state.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'frozen baseline drifted.'
Assert-Contract ([string]$ancestorFailure.status -eq 'failed' -and [string]$bulkFailure.status -eq 'failed') 'both static failure witnesses must remain failed.'
Assert-Contract (@($ancestorFailure.runtimeActionsPerformed).Count -eq 0 -and @($bulkFailure.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$ancestorFailure.semanticMatchAllowed -and -not [bool]$bulkFailure.semanticMatchAllowed) 'failure witnesses must remain static-only.'
Assert-Contract ([string]$fixture.contract -eq 'legado_jsoup_not_selector_ancestor_context' -and @($fixture.cases).Count -eq 3) 'fixture must contain three ancestor-context cases.'
Assert-Contract ($analyzer.Contains('const contextOccurrences = this.mapStringElementOccurrences(contextHtml, filtered)')) 'candidate occurrences must be mapped once.'
Assert-Contract ($analyzer.Contains('const matchedOffsets = this.collectNestedSelectorMatchOffsets(contextHtml, argument);')) 'complete-context :not must use bulk offset collection.'
Assert-Contract ($analyzer.Contains('private collectNestedSelectorMatchOffsets(contextHtml: string, selector: string): Set<number>')) 'bulk offset collector must be typed.'
Assert-Contract ($analyzer.Contains('const selectorGroups = this.splitTopLevelCssSelectorGroups(selector);')) 'selector lists must be evaluated as independent groups.'
Assert-Contract ($analyzer.Contains('this.findElementsBySingleSelector(contextHtml, selectorGroup, contextHtml)')) 'each selector group must be evaluated against the full context.'
Assert-Contract ($analyzer.Contains('matchedOffsets.add(occurrence.startIndex)')) 'bulk projection must retain occurrence offsets.'
Assert-Contract (-not $analyzer.Contains('this.matchesStringNestedSelectorAtOccurrence(element, argument, contextHtml, occurrence.startIndex)')) 'complete-context branch must not rescan the document per candidate.'
Assert-Contract ($analyzer.Contains('this.matchesStringNestedSelector(element, argument, contextHtml)')) 'incomplete mapping must retain an explicit safe fallback.'
Assert-Contract ($analyzer.Contains('const wrapper = `<legado-not-root>${contextHtml}</legado-not-root>`')) 'full ancestor synthetic context remains present.'
Assert-Contract ($analyzer.Contains('const targetRelativeStart = wrapperOpeningEnd + 1 + candidateStartIndex')) 'occurrence projection remains available for fallback evaluation.'
Assert-Contract (-not $analyzer.Contains('const wrapper = `<legado-not-root>${parentElement}</legado-not-root>`')) 'parent-only wrapper remains removed.'
Assert-Contract ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado selector handoff remains bound.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_jsoup_not_selector_ancestor_bulk_post_fix_contract'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'passed'
  assertions = $script:assertions
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  fixture = $FixturePath
  changedPaths = @($analyzerPath)
  impact = [pscustomobject][ordered]@{ baselineSourceCount = 458; standardPseudoAffectedSourceCount = 21; ancestorContextCases = 3; projection = 'one full-context evaluation per selector group' }
  verification = 'static_source_contract_only;runtime_regression_deferred'
  sourceHash = Get-TextHash $analyzer
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
