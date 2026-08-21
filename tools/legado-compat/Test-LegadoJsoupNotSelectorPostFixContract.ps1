[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-not-selector-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-not-selector-pre-fix-20260809.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-not-selector-post-fix-20260809.json'
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
function Assert-Contract { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 :not selector post-fix contract failed: $Message" }; $script:assertions++ }
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
Assert-Contract ([string]$fixture.contract -eq 'legado_jsoup_not_selector_context' -and @($fixture.cases).Count -eq 3) 'fixture must contain three :not context cases.'
Assert-Contract ($analyzer.Contains('matchesStringNestedSelector(element, argument, contextHtml)')) 'the :not consumer must pass full context HTML.'
$analyzer.Contains('contextHtml: string')
Assert-Contract ($analyzer.Contains('findParentStartTag(contextHtml, target.startIndex)')) 'context-aware :not must recover the candidate parent.'
Assert-Contract ($analyzer.Contains('const matchedOccurrences = this.mapStringElementOccurrences(wrapper, matches)')) 'context-aware :not must compare occurrence offsets, not only HTML equality.'
Assert-Contract (($analyzer.Contains('targetRelativeStart = wrapperOpeningEnd + 1 + (target.startIndex - parentStart)') -or $analyzer.Contains('targetRelativeStart = wrapperOpeningEnd + 1 + candidateStartIndex'))) 'context-aware :not must bind the candidate occurrence inside the synthetic document.'
Assert-Contract ($analyzer.Contains('matchesStringNestedSelectorWithoutContext')) 'top-level fallback must remain explicit.'
Assert-Contract (-not $analyzer.Contains('private matchesStringNestedSelector(element: string, selector: string): boolean')) 'candidate-only :not signature must not remain.'
Assert-Contract ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado Jsoup selector handoff must remain bound.'
Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'not_must_evaluate_candidate_with_ancestor_context' }).Count -eq 1) 'fixture must include ancestor-dependent :not.'
Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'not_must_preserve_parent_and_child_combinator_context' }).Count -eq 1) 'fixture must include parent/child combinator :not.'
Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'not_selector_list_is_logical_or_in_jsoup' }).Count -eq 1) 'fixture must include selector-list :not.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_jsoup_not_selector_post_fix_contract'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'passed'
  assertions = $script:assertions
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  fixture = $FixturePath
  changedPaths = @($analyzerPath)
  impact = [pscustomobject][ordered]@{ baselineSourceCount = 458; standardPseudoAffectedSourceCount = 21; notContextCases = 3 }
  verification = 'static_source_contract_only;runtime_regression_deferred'
  sourceHash = Get-TextHash $analyzer
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
