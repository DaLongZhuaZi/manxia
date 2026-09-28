[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selector-mixed-descendant-direct-child-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-mixed-descendant-direct-child-pre-fix-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-mixed-descendant-direct-child-post-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }; return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); return $strictUtf8.GetString([System.IO.File]::ReadAllBytes((Get-RepoPath $Path))) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100) }
function Assert-Contract { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 mixed-chain post-fix contract failed: $Message" }; $script:assertions++ }
function Get-TextHash { param([Parameter(Mandatory = $true)][string]$Path); return (Get-FileHash -LiteralPath (Get-RepoPath $Path) -Algorithm SHA256).Hash.ToUpperInvariant() }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temp = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temp -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) } } }

$state = Read-StrictJson -Path 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson -Path $FixturePath
$failure = Read-StrictJson -Path $FailureWitnessPath
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$runtimePath = 'entry/src/main/resources/rawfile/legado_runtime.html'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$analyzer = Read-StrictText -Path $analyzerPath
$runtime = Read-StrictText -Path $runtimePath
$legado = Read-StrictText -Path $legadoPath

Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$state.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'frozen baseline drifted.'
Assert-Contract ([string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and [string]$state.governance.status -eq 'running' -and -not [bool]$state.governance.semanticMatchAllowed) '243 is not the active static issue or semantic match was enabled.'
Assert-Contract ([string]$fixture.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and @($fixture.cases).Count -eq 2 -and @($fixture.affectedSourceSet.sourceOrdinals) -contains 97) 'mixed-chain fixture binding drifted.'
Assert-Contract ([string]$failure.status -eq 'failed' -and @($failure.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed) 'failure witness must remain failed and static-only.'
Assert-Contract ($analyzer.Contains('let currentElements = this.findElementsBySingleSelector(html, firstSelector, effectiveContextHtml);')) 'direct-child helper must evaluate the complete left selector through the single-selector dispatcher.'
Assert-Contract (-not $analyzer.Contains('let currentElements = this.findElementsBySimpleSelector(html, firstSelector, effectiveContextHtml);')) 'the lossy simple-selector handoff is still present.'
Assert-Contract ($analyzer.Contains('private findElementsByDirectChildSelector(') -and $analyzer.Contains('private splitTopLevelDirectChildSelectors(')) 'direct-child parsing path is missing.'
Assert-Contract ($runtime.Contains('querySelectorAll') -and $legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'native ArkWeb or pinned Legado selector consumer is missing.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_jsoup_standard_pseudo_selector_mixed_descendant_direct_child_post_fix_contract'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'passed'
  assertions = $script:assertions
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  fixture = $FixturePath
  changedPaths = @($analyzerPath)
  impact = [pscustomobject][ordered]@{ baselineSourceCount = 458; affectedSourceOrdinals = @(97); ruleStringCount = 1; cases = 2; selectors = @('.book_list2 .col-md-3:nth-child(n+1) > a', 'section.catalog .book_list2 > div.col-md-3:nth-child(2) > a') }
  semantics = 'The direct-child helper now evaluates the complete left operand, preserving descendant segments and pseudo classes before applying the > relation.'
  verification = 'static_source_contract_only;runtime_regression_deferred'
  sourceHashes = [pscustomobject][ordered]@{ $analyzerPath = Get-TextHash -Path $analyzerPath; $runtimePath = Get-TextHash -Path $runtimePath; $legadoPath = Get-TextHash -Path $legadoPath }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
}
Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Depth 100
