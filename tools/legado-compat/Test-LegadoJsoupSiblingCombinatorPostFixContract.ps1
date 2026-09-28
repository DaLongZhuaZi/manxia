[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-sibling-combinator-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-sibling-combinator-pre-fix-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-sibling-combinator-post-fix-20260810.json'
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
function Assert-Contract { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 sibling combinator post-fix contract failed: $Message" }; $script:assertions++ }
function Get-TextHash { param([Parameter(Mandatory = $true)][string]$Text); $sha = [System.Security.Cryptography.SHA256]::Create(); try { return ([System.BitConverter]::ToString($sha.ComputeHash($strictUtf8.GetBytes($Text)))).Replace('-', '').ToUpperInvariant() } finally { $sha.Dispose() } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value); $path = Get-RepoPath $RelativePath; $directory = Split-Path -Parent $path; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temp = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temp -Destination $path -Force } finally { if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) } } }

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$analyzer = Read-StrictText $analyzerPath
$legado = Read-StrictText $legadoPath
$normalizedAnalyzer = $analyzer -replace '\s+', ' '
$dispatchIndex = $analyzer.IndexOf('const siblingChain = this.splitTopLevelCssSiblingCombinatorSelector(selector);')
$classIndex = $analyzer.IndexOf('const isCssClassSelector = selector.startsWith(''.'')')
Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$state.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'frozen baseline drifted.'
Assert-Contract ([string]$failure.status -eq 'failed' -and @($failure.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed) 'failure witness must remain failed and static-only.'
Assert-Contract ([string]$fixture.contract -eq 'legado_jsoup_sibling_combinator_context' -and @($fixture.cases).Count -eq 3) 'sibling fixture must contain three cases.'
Assert-Contract ($analyzer.Contains('interface StringCssCombinatorChain')) 'sibling chain must have a named type.'
Assert-Contract ($analyzer.Contains('private splitTopLevelCssSiblingCombinatorSelector(selector: string): StringCssCombinatorChain | null')) 'top-level sibling parser must be present.'
Assert-Contract ($analyzer.Contains('private findElementsByCssCombinatorChain(')) 'sibling chain evaluator must be present.'
Assert-Contract ($analyzer.Contains('private matchesStringCombinatorRelation(')) 'sibling relation matcher must be present.'
Assert-Contract ($analyzer.Contains('combinator === ''+''') -and $analyzer.Contains('combinator === ''~''')) 'adjacent and general sibling semantics must be explicit.'
Assert-Contract ($analyzer.Contains('candidatePosition.siblingIndex === previousPosition.siblingIndex + 1')) 'adjacent sibling must use the immediate preceding element index.'
Assert-Contract ($analyzer.Contains('candidatePosition.siblingIndex > previousPosition.siblingIndex')) 'general sibling must use any preceding element index.'
Assert-Contract ($analyzer.Contains('const siblingChain = this.splitTopLevelCssSiblingCombinatorSelector(selector);') -and $dispatchIndex -ge 0 -and $classIndex -ge 0 -and $dispatchIndex -lt $classIndex) 'sibling dispatch must run before class/id short-circuiting.'
Assert-Contract ($analyzer.Contains('chain.combinators[partIndex - 1]')) 'mixed combinator chains must retain per-edge operators.'
Assert-Contract ($normalizedAnalyzer.Contains('this.findElementsBySingleSelector( effectiveContextHtml, chain.parts[partIndex], effectiveContextHtml )')) 'each sibling candidate must be evaluated against the full context.'
Assert-Contract ($analyzer.Contains('const candidateParentStart = this.findParentStartTag(contextHtml, candidate.startIndex)')) 'candidate parent context must be explicit.'
Assert-Contract ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado selector handoff must remain bound.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_jsoup_sibling_combinator_post_fix_contract'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'passed'
  assertions = $script:assertions
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  fixture = $FixturePath
  changedPaths = @($analyzerPath)
  impact = [pscustomobject][ordered]@{ baselineSourceCount = 458; cases = 3; combinators = @('+', '~', '> +') }
  verification = 'static_source_contract_only;runtime_regression_deferred'
  sourceHash = Get-TextHash $analyzer
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
