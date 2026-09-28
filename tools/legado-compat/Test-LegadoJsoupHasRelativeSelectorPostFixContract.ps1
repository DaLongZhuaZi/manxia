[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-has-relative-selector-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-has-relative-selector-pre-fix-20260809.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-has-relative-selector-post-fix-20260809.json'
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
function Assert-Contract { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 :has relative selector post-fix contract failed: $Message" }; $script:assertions++ }
function Get-TextHash { param([Parameter(Mandatory = $true)][string]$Text); $sha = [System.Security.Cryptography.SHA256]::Create(); try { return ([System.BitConverter]::ToString($sha.ComputeHash($strictUtf8.GetBytes($Text)))).Replace('-', '').ToUpperInvariant() } finally { $sha.Dispose() } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value); $path = Get-RepoPath $RelativePath; $directory = Split-Path -Parent $path; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temp = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temp -Destination $path -Force } finally { if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) } } }

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$elementPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$runtimePath = 'entry/src/main/resources/rawfile/legado_runtime.html'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$analyzer = Read-StrictText $analyzerPath
$element = Read-StrictText $elementPath
$runtime = Read-StrictText $runtimePath
$legado = Read-StrictText $legadoPath

Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$state.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'frozen baseline drifted.'
Assert-Contract ([string]$failure.status -eq 'failed' -and @($failure.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed) 'failure witness must remain static-only and failed.'
Assert-Contract ([string]$fixture.contract -eq 'legado_jsoup_has_relative_selector_context' -and @($fixture.cases).Count -eq 4) 'fixture must contain four relative-selector cases.'
Assert-Contract ($analyzer.Contains('matches.some((match: string): boolean => match !== wrapper)')) 'string fallback must accept descendant matches below the direct child.'
Assert-Contract (-not $analyzer.Contains('matches.some((match: string): boolean => match === child)')) 'string fallback must not retain the equality-only guard.'
Assert-Contract ($element.Contains('matchesHasDirectChildRelativeSelector(elem, childSelector)')) 'DOM matcher must dispatch direct-child :has to the relative-selector helper.'
Assert-Contract ($element.Contains('elem.querySelectorAll(selector)')) 'DOM helper must evaluate the complete relative selector.'
Assert-Contract ($element.Contains('if (parentNode === elem)')) 'DOM helper must verify that the matched node belongs to a direct child subtree.'
Assert-Contract (-not $element.Contains('if (child.matches(childSelector))')) 'DOM matcher must not use the single-part child.matches shortcut.'
Assert-Contract ($runtime.Contains("var relativeSelector = argument.indexOf('>') === 0 ? ':scope ' + argument : argument;")) 'ArkWeb :scope relative-selector projection must remain present.'
Assert-Contract ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado Jsoup selector handoff must remain bound.'
Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'relative_selector_continues_below_direct_child' }).Count -eq 1) 'fixture must include descendant continuation.'
Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'relative_selector_keeps_direct_child_and_nested_child_constraints' }).Count -eq 1) 'fixture must include nested direct-child constraint.'
Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'relative_selector_must_not_accept_span_under_nonmatching_direct_child' }).Count -eq 1) 'fixture must include indirect-ancestor rejection.'
Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'nested_has_preserves_direct_child_relative_context' }).Count -eq 1) 'fixture must include nested :has relative context.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_jsoup_has_relative_selector_post_fix_contract'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'passed'
  assertions = $script:assertions
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  fixture = $FixturePath
  impact = [pscustomobject][ordered]@{ baselineSourceCount = 458; affectedSourceCount = 21; knownRuleStringCount = 52 }
  changedPaths = @($analyzerPath, $elementPath)
  verification = 'static_source_contract_only;runtime_regression_deferred'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  sourceHashes = [pscustomobject][ordered]@{ $analyzerPath = Get-TextHash $analyzer; $elementPath = Get-TextHash $element }
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
