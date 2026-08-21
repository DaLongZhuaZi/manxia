[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-has-direct-child-relative-selector-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-has-direct-child-relative-selector-pre-fix-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-has-direct-child-relative-selector-post-fix-20260810.json'
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
function Assert-Contract { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 :has direct-child relative selector post-fix contract failed: $Message" }; $script:assertions++ }
function Get-TextHash { param([Parameter(Mandatory = $true)][string]$Text); $sha = [System.Security.Cryptography.SHA256]::Create(); try { return ([System.BitConverter]::ToString($sha.ComputeHash($strictUtf8.GetBytes($Text)))).Replace('-', '').ToUpperInvariant() } finally { $sha.Dispose() } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value); $path = Get-RepoPath $RelativePath; $directory = Split-Path -Parent $path; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $path -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$analyzer = Read-StrictText $analyzerPath
$legado = Read-StrictText $legadoPath

Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$state.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'frozen baseline drifted.'
Assert-Contract ([string]$failure.status -eq 'failed' -and @($failure.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed) 'failure witness must remain static-only and failed.'
Assert-Contract ([string]$fixture.contract -eq 'legado_jsoup_has_direct_child_relative_selector_context' -and @($fixture.cases).Count -eq 4) 'fixture must contain four direct-child relative-selector cases.'
Assert-Contract ($analyzer.Contains('const subjectSelector = this.extractTopLevelSelectorSubject(childSelector);')) 'string fallback must derive the direct-child subject selector.'
Assert-Contract ($analyzer.Contains('const wrapperOpeningEnd = this.findHtmlTagEnd(wrapper, 0);')) 'string fallback must compute the synthetic-root boundary.'
Assert-Contract ($analyzer.Contains('this.matchesStringSelectorAtElementStart(wrapper, subjectSelector, wrapperOpeningEnd + 1)')) 'string fallback must require the subject selector to match the direct child start.'
Assert-Contract ($analyzer.Contains('private extractTopLevelSelectorSubject(selector: string): string {')) 'top-level selector subject helper must exist.'
Assert-Contract ($analyzer.Contains('private matchesStringSelectorAtElementStart(') -and $analyzer.Contains('expectedStart: number') -and $analyzer.Contains('): boolean {')) 'root-position selector matcher helper must exist.'
Assert-Contract ($analyzer.Contains('const directChildParts = this.splitTopLevelDirectChildSelectors(selector);')) 'subject extraction must account for top-level direct-child combinators.'
Assert-Contract ($analyzer.Contains('const siblingChain = this.splitTopLevelCssSiblingCombinatorSelector(selector);')) 'subject extraction must account for top-level sibling combinators.'
Assert-Contract ($analyzer.Contains('if (matches.some((match: string): boolean => match !== wrapper))')) 'relative selectors may still continue below a verified direct child.'
Assert-Contract ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado Jsoup selector handoff must remain bound.'
Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'relative_selector_subject_must_be_direct_child' }).Count -eq 1) 'fixture must include direct-child acceptance.'
Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -match 'must_not_accept' }).Count -eq 2) 'fixture must include both nested rejection cases.'
Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'relative_selector_leading_compound_is_direct_child_and_remainder_is_descendant' }).Count -eq 1) 'fixture must retain descendant continuation coverage.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_jsoup_has_direct_child_relative_selector_post_fix_contract'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'passed'
  assertions = $script:assertions
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  fixture = $FixturePath
  changedPaths = @($analyzerPath)
  sourceHashes = [pscustomobject][ordered]@{ $analyzerPath = Get-TextHash $analyzer; $legadoPath = Get-TextHash $legado }
  verification = 'static_source_contract_only;runtime_regression_deferred'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
