[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selector-of-type-context.json',
  [string]$SourcePackagePath = 'F:/Downloads-E/墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-of-type-pre-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$elementPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$runtimePath = 'entry/src/main/resources/rawfile/legado_runtime.html'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $RelativePath }
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  $resolved = Get-RepoPath $Path
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Missing text: $Path" }
  return $strictUtf8.GetString([System.IO.File]::ReadAllBytes($resolved))
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Read-StrictText $Path | ConvertFrom-Json -Depth 100)
}

function Assert-Witness {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "243 of-type failure witness failed: $Message" }
}

function Get-TextHash {
  param([Parameter(Mandatory = $true)][string]$Text)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { return ([System.BitConverter]::ToString($sha.ComputeHash($strictUtf8.GetBytes($Text)))).Replace('-', '').ToUpperInvariant() }
  finally { $sha.Dispose() }
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value)
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temp = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8)
    Move-Item -LiteralPath $temp -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) }
  }
}

$fixture = Read-StrictJson $FixturePath
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$analyzer = Read-StrictText $analyzerPath
$element = Read-StrictText $elementPath
$runtime = Read-StrictText $runtimePath
$legado = Read-StrictText $legadoPath
$packageBytes = [System.IO.File]::ReadAllBytes((Get-RepoPath $SourcePackagePath))
$packageHash = ([System.BitConverter]::ToString(([System.Security.Cryptography.SHA256]::Create()).ComputeHash($packageBytes))).Replace('-', '').ToUpperInvariant()
$package = $strictUtf8.GetString($packageBytes) | ConvertFrom-Json -Depth 100
$target = @($package)[227]
$targetExploreBookList = [string]$target.ruleExplore.bookList

Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen machine baseline drifted.'
Assert-Witness ([int]@($package).Count -eq 458 -and $packageHash -eq $baselineHash) 'pinned source package count or hash drifted.'
Assert-Witness ([string]$fixture.issueId -eq $issueId -and [string]$fixture.contract -eq 'legado_jsoup_standard_pseudo_selector_of_type_context' -and @($fixture.cases).Count -eq 5) 'fixture binding or case count changed.'
Assert-Witness ($targetExploreBookList -match ':last-of-type' -and $targetExploreBookList -match 'container:last-of-type') 'affected ordinal 228 selector evidence is missing.'
Assert-Witness (-not $analyzer.Contains("pseudo.name === 'first-of-type'") -and -not $analyzer.Contains("pseudo.name === 'last-of-type'") -and -not $analyzer.Contains("pseudo.name === 'only-of-type'") -and -not $analyzer.Contains("pseudo.name === 'nth-last-of-type'") ) 'pre-fix Analyzer already contains the of-type branches.'
Assert-Witness (-not $element.Contains("pseudo.name === 'first-of-type'") -and -not $element.Contains("pseudo.name === 'last-of-type'") -and -not $element.Contains("pseudo.name === 'only-of-type'") -and -not $element.Contains("pseudo.name === 'nth-last-of-type'") ) 'pre-fix DOM matcher already contains the of-type branches.'
Assert-Witness ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado selector handoff is missing.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'failure_witness'
  issueId = $issueId
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  failureClass = 'v2_large_document_string_fallback_missing_of_type_pseudo_classes'
  fixturePath = $FixturePath
  sourcePackagePath = 'redacted_pinned_package'
  sourcePackageHash = $packageHash
  affectedSourceSet = [pscustomobject][ordered]@{ sourceOrdinals = @(228); ruleStringCount = 1; rulePaths = @('$[227].ruleExplore.bookList') }
  sourcePaths = @($analyzerPath, $elementPath, $runtimePath, $legadoPath)
  failureWitness = [pscustomobject][ordered]@{
    branch = 'content.length > 50000'
    path = 'LegadoRuleAnalyzer.getElementsByCSSWithBridge -> getElementsByCSSChain -> findElementsBySimpleSelector -> filterElementsByPseudoClasses'
    observed = 'first-of-type, last-of-type, only-of-type and nth-last-of-type are not consumed by the V2 string fallback or DOM matcher and therefore fail closed at the unknown-pseudo branch.'
    expected = 'Jsoup Element.select must count only same-tag element siblings for of-type selectors and evaluate nth-last-of-type from the end.'
  }
  rootCauseDecision = 'The pinned Legado selector contract has same-tag type-position evaluators, while V2 only implements nth-of-type/eq/lt in the non-DOM fallback and lacks all of-type branches in HTMLElement.matchesPseudoClass.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_of_type_failure_witness_static_only;runtime_regression_build_device_and_legado_diff_deferred'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
