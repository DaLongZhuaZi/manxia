[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selector-of-type-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-of-type-pre-fix-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-of-type-post-fix-20260810.json'
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
function Assert-Contract { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 of-type post-fix contract failed: $Message" }; $script:assertions++ }
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
Assert-Contract ([string]$failure.status -eq 'failed' -and @($failure.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed) 'failure witness must remain failed and static-only.'
Assert-Contract ([string]$fixture.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and @($fixture.cases).Count -eq 5 -and @($fixture.affectedSourceSet.sourceOrdinals).Count -eq 1) 'of-type fixture binding drifted.'
Assert-Contract ($analyzer.Contains('typeCount: number') -and $analyzer.Contains("pseudo.name === 'first-of-type'") -and $analyzer.Contains("pseudo.name === 'last-of-type'") -and $analyzer.Contains("pseudo.name === 'only-of-type'") -and $analyzer.Contains("pseudo.name === 'nth-last-of-type'")) 'string fallback of-type dispatch is absent.'
Assert-Contract ($analyzer.Contains('const isTypeExpression = pseudoName === ''nth-of-type'' || pseudoName === ''nth-last-of-type'';')) 'nth-last-of-type must use an expression path rather than a numeric-only parser.'
Assert-Contract ($analyzer.Contains('siblingPosition.typeIndex === siblingPosition.typeCount') -and $analyzer.Contains('siblingPosition.typeCount === 1')) 'last-of-type and only-of-type must count same-tag siblings.'
Assert-Contract ($analyzer.Contains('const typeIndexFromEnd = siblingPosition.typeCount - siblingPosition.typeIndex + 1;')) 'nth-last-of-type must count from the end.'
Assert-Contract ($element.Contains("pseudo.name === 'first-of-type'") -and $element.Contains("pseudo.name === 'last-of-type'") -and $element.Contains("pseudo.name === 'only-of-type'") -and $element.Contains("pseudo.name === 'nth-last-of-type'")) 'DOM Matcher of-type branches are absent.'
Assert-Contract ($element.Contains('private getElementTypeCount(elem: HTMLElement, parent: HTMLElement): number')) 'DOM Matcher must have a typed same-tag counter.'
Assert-Contract ($runtime.Contains('querySelectorAll') -and $runtime.Contains("name === 'nth-of-type'")) 'ArkWeb native CSS consumer is not bound.'
Assert-Contract (-not $runtime.Contains("name === 'first-of-type'") -and -not $runtime.Contains("name === 'last-of-type'")) 'ArkWeb must not replace native first/last-of-type CSS with a divergent custom branch.'
Assert-Contract ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado selector handoff is missing.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_jsoup_standard_pseudo_selector_of_type_post_fix_contract'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'passed'
  assertions = $script:assertions
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  fixture = $FixturePath
  changedPaths = @($analyzerPath, $elementPath)
  impact = [pscustomobject][ordered]@{ baselineSourceCount = 458; affectedSourceOrdinals = @(228); ruleStringCount = 1; cases = 5; pseudos = @('first-of-type', 'last-of-type', 'only-of-type', 'nth-of-type', 'nth-last-of-type') }
  verification = 'static_source_contract_only;runtime_regression_deferred'
  sourceHashes = [pscustomobject][ordered]@{ $analyzerPath = Get-TextHash $analyzer; $elementPath = Get-TextHash $element; $runtimePath = Get-TextHash $runtime; $legadoPath = Get-TextHash $legado }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
