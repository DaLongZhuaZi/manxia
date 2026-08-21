[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selector-mixed-descendant-direct-child-context.json',
  [string]$SourcePackagePath = 'F:/Downloads-E/墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-mixed-descendant-direct-child-pre-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }; return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; return $strictUtf8.GetString([System.IO.File]::ReadAllBytes($resolved)) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText $Path | ConvertFrom-Json -Depth 100) }
function Assert-Witness { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 mixed-chain failure witness failed: $Message" } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temp = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temp -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) } } }

$fixture = Read-StrictJson -Path $FixturePath
$state = Read-StrictJson -Path 'tools/legado-compat/state/full-source-validation-state.json'
$analyzer = Read-StrictText -Path $analyzerPath
$packagePath = Get-RepoPath $SourcePackagePath
$packageBytes = [System.IO.File]::ReadAllBytes($packagePath)
$packageHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToUpperInvariant()
$package = $strictUtf8.GetString($packageBytes) | ConvertFrom-Json -Depth 100
$target = @($package)[96]
$targetRule = [string]$target.ruleToc.chapterList

Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen machine baseline drifted.'
Assert-Witness (@($package).Count -eq 458 -and $packageHash -eq $sourceHash) 'pinned source package count or hash drifted.'
Assert-Witness ([string]$fixture.issueId -eq $issueId -and [string]$fixture.contract -eq 'legado_jsoup_standard_pseudo_selector_mixed_descendant_direct_child_context' -and @($fixture.cases).Count -eq 2) 'fixture binding or case count changed.'
Assert-Witness ($targetRule -eq '.book_list2 .col-md-3:nth-child(n+1) > a') 'affected ordinal 97 selector evidence is missing.'
Assert-Witness ($analyzer.Contains('let currentElements = this.findElementsBySimpleSelector(html, firstSelector, effectiveContextHtml);')) 'pre-fix direct-child helper no longer contains the simple-selector handoff.'
Assert-Witness (-not $analyzer.Contains('let currentElements = this.findElementsBySingleSelector(html, firstSelector, effectiveContextHtml);')) 'source already contains the mixed-chain fix.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'failure_witness'
  issueId = $issueId
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  failureClass = 'v2_direct_child_chain_drops_descendant_left_operand'
  fixturePath = $FixturePath
  sourcePackagePath = 'redacted_pinned_package'
  sourcePackageHash = $packageHash
  affectedSourceSet = [pscustomobject][ordered]@{ sourceOrdinals = @(97); ruleStringCount = 1; rulePaths = @('$[96].ruleToc.chapterList') }
  sourcePaths = @($analyzerPath, 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt')
  failureWitness = [pscustomobject][ordered]@{
    branch = 'LegadoRuleAnalyzer.findElementsByDirectChildSelector'
    path = 'getElementsByCSSWithBridge -> getElementsByCSSChain -> findElementsBySingleSelector -> findElementsByDirectChildSelector'
    observed = 'The left operand before a top-level > is sent to findElementsBySimpleSelector. A mixed selector such as .book_list2 .col-md-3:nth-child(n+1) > a is reduced to the first class token, so the descendant segment and nth-child predicate are not evaluated.'
    expected = 'Jsoup Element.select evaluates the complete left operand as a descendant selector before applying the direct-child relation to a.'
  }
  rootCauseDecision = 'The direct-child dispatcher separates top-level > correctly but invokes a simple-selector parser for the left segment, which cannot consume descendant combinators or the pseudo selector embedded in that segment.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_mixed_descendant_direct_child_failure_witness_static_only;runtime_regression_build_device_and_legado_diff_deferred'
}
Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Depth 100
