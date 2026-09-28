[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-not-selector-ancestor-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-not-selector-ancestor-pre-fix-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-not-selector-ancestor-post-fix-20260810.json'
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
function Assert-Contract { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 :not ancestor post-fix contract failed: $Message" }; $script:assertions++ }
function Get-TextHash { param([Parameter(Mandatory = $true)][string]$Text); $sha = [System.Security.Cryptography.SHA256]::Create(); try { return ([System.BitConverter]::ToString($sha.ComputeHash($strictUtf8.GetBytes($Text)))).Replace('-', '').ToUpperInvariant() } finally { $sha.Dispose() } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value); $path = Get-RepoPath $RelativePath; $directory = Split-Path -Parent $path; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temp = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temp -Destination $path -Force } finally { if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) } } }

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$analyzer = Read-StrictText $analyzerPath
$legado = Read-StrictText $legadoPath
Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$state.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'frozen baseline drifted.'
Assert-Contract ([string]$failure.status -eq 'failed' -and @($failure.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed) 'failure witness must remain failed and static-only.'
Assert-Contract ([string]$fixture.contract -eq 'legado_jsoup_not_selector_ancestor_context' -and @($fixture.cases).Count -eq 3) 'fixture must contain three ancestor-context cases.'
Assert-Contract ($analyzer.Contains('const selectionContextHtml = needsOccurrenceMarkers') -and $analyzer.Contains('const found = this.findElementsBySingleSelector(element, part, selectionContextHtml);')) 'CSS chain must provide the complete response context, including occurrence markers when required.'
Assert-Contract ($analyzer.Contains('selectorContextHtml: string =')) 'single-selector API must carry a typed context parameter.'
Assert-Contract ($analyzer.Contains('const effectiveContextHtml = selectorContextHtml.length > 0 ? selectorContextHtml : html;')) 'selector context must have a local fallback.'
Assert-Contract ($analyzer.Contains('findElementsBySimpleSelector(element, part, effectiveContextHtml)')) 'descendant selector parts must retain the root context.'
Assert-Contract ($analyzer.Contains('findElementsByDirectChildSelector(html, selector, effectiveContextHtml)')) 'direct-child selector path must retain the root context.'
Assert-Contract ($analyzer.Contains('matchesStringNestedSelectorAtOccurrence')) 'the :not path must expose occurrence-aware evaluation.'
Assert-Contract ($analyzer.Contains('const contextOccurrences = this.mapStringElementOccurrences(contextHtml, filtered)')) 'the :not filter must map the complete candidate set before evaluation.'
Assert-Contract ($analyzer.Contains('const wrapper = `<legado-not-root>${contextHtml}</legado-not-root>`')) 'the synthetic document must contain the full selector context.'
Assert-Contract ($analyzer.Contains('const targetRelativeStart = wrapperOpeningEnd + 1 + candidateStartIndex')) 'candidate identity must be projected by occurrence offset.'
Assert-Contract (-not $analyzer.Contains('const wrapper = `<legado-not-root>${parentElement}</legado-not-root>`')) 'the parent-only wrapper must be removed.'
Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'not_must_evaluate_candidate_with_full_ancestor_context' }).Count -eq 1) 'fixture must include deep ancestor context.'
Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'not_must_preserve_multi_level_child_combinator_context' }).Count -eq 1) 'fixture must include multi-level child combinator context.'
Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'not_must_bind_duplicate_html_to_its_occurrence_offset' }).Count -eq 1) 'fixture must include duplicate occurrence identity.'
Assert-Contract ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado selector handoff must remain bound.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_jsoup_not_selector_ancestor_post_fix_contract'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'passed'
  assertions = $script:assertions
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  fixture = $FixturePath
  changedPaths = @($analyzerPath)
  impact = [pscustomobject][ordered]@{ baselineSourceCount = 458; standardPseudoAffectedSourceCount = 21; ancestorContextCases = 3 }
  verification = 'static_source_contract_only;runtime_regression_deferred'
  sourceHash = Get-TextHash $analyzer
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
