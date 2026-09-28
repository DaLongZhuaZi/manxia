[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selectors.json',
  [string]$CandidateEvidencePath = 'tools/legado-compat/evidence/r3-jsoup-standard-pseudo-selectors-candidate-20260809.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selectors-pre-fix-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "required file is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100)
}

function Assert-Witness {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "243 pre-fix witness failed: $Message" }
  $script:assertions++
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 60), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$resultPath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot ($ResultPath.Replace('/', '\'))))
$evidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).TrimEnd('\') + '\'
if (-not $resultPath.StartsWith($evidenceRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'failure witness must remain under the evidence directory.' }

$fixture = Read-StrictJson -Path (Get-RepoPath -RelativePath $FixturePath)
$candidate = Read-StrictJson -Path (Get-RepoPath -RelativePath $CandidateEvidencePath)
$state = Read-StrictJson -Path (Get-RepoPath -RelativePath 'tools/legado-compat/state/full-source-validation-state.json')
$analyzerPath = Get-RepoPath -RelativePath 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$elementPath = Get-RepoPath -RelativePath 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$runtimePath = Get-RepoPath -RelativePath 'entry/src/main/resources/rawfile/legado_runtime.html'
$legadoPath = Get-RepoPath -RelativePath 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$analyzer = Read-StrictText -Path $analyzerPath
$element = Read-StrictText -Path $elementPath
$runtime = Read-StrictText -Path $runtimePath
$legado = Read-StrictText -Path $legadoPath

Assert-Witness ([string]$candidate.status -eq 'candidate_observed_static_only' -and [string]$candidate.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS') 'candidate audit is not the expected static observation.'
Assert-Witness ([int]$candidate.impact.ruleStringCount -eq [int]$fixture.pseudoCounts.total -and [int]$candidate.impact.affectedSourceCount -eq @($fixture.affectedSourceOrdinals).Count) 'candidate impact is not bound to the fixture.'
Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline drifted.'
Assert-Witness ($analyzer.Contains('const HTML_SIZE_THRESHOLD = 50000') -and $analyzer.Contains('return this.getElementsByCSSChain(selector);')) 'large-document string fallback is not proven.'
$filterStart = $analyzer.IndexOf('private filterElementsByPseudoClasses(')
$filterEnd = $analyzer.IndexOf('private filterElementsByIndexPseudo(', $filterStart)
Assert-Witness ($filterStart -ge 0 -and $filterEnd -gt $filterStart) 'string pseudo filter boundary is missing.'
$filterBody = $analyzer.Substring($filterStart, $filterEnd - $filterStart)
foreach ($name in @('first-child', 'last-child', 'nth-child', 'only-child')) {
  Assert-Witness (-not $filterBody.Contains("pseudo.name === '$name'")) "current string fallback unexpectedly contains $name support."
}
Assert-Witness ($filterBody.Contains('Do not silently widen selectors when a Jsoup pseudo class is unknown.') -and $filterBody.Contains('return [];')) 'unknown pseudo classes do not fail closed in the observed path.'
foreach ($name in @('first-child', 'last-child', 'nth-child', 'only-child')) {
  Assert-Witness ($element.Contains("pseudo.name === '$name'")) "DOM support evidence missing for $name."
}
Assert-Witness ($runtime.Contains('root.querySelectorAll(browserSelector)') -and $runtime.Contains('legadoParseJsoupTextPseudos')) 'ArkWeb native CSS path evidence missing.'
Assert-Witness ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('getStringList')) 'Legado Jsoup delegation evidence missing.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'failure_witness'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  failureClass = 'v2_large_document_string_fallback_standard_css_pseudo_fail_closed'
  semantics = [pscustomobject][ordered]@{ standardPseudos = @('first-child', 'last-child', 'nth-child', 'only-child'); indexing = 'element children only; nth-child is 1-based an+b' }
  fixturePath = $FixturePath
  candidateEvidencePath = $CandidateEvidencePath
  sourcePaths = @($analyzerPath.Replace($RepositoryRoot + '\', '').Replace('\', '/'), $elementPath.Replace($RepositoryRoot + '\', '').Replace('\', '/'), $runtimePath.Replace($RepositoryRoot + '\', '').Replace('\', '/'), $legadoPath.Replace($RepositoryRoot + '\', '').Replace('\', '/'))
  impact = $candidate.impact
  failureWitness = [pscustomobject][ordered]@{ branch = 'content.length > 50000'; path = 'getElementsByCSSWithBridge -> getElementsByCSSChain -> findElementsBySimpleSelector -> filterElementsByPseudoClasses'; observed = 'standard pseudo names are extracted, then hit the unknown-pseudo return [] branch'; expected = 'Jsoup Element.select must evaluate standard CSS child pseudo classes' }
  assertions = $script:assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred'
}
Write-AtomicJson -Path $resultPath -Value $result
$result | ConvertTo-Json -Depth 60
