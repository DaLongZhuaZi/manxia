[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-nth-last-child-context.json',
  [string]$SourcePackagePath = 'F:/Downloads-E/墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-nth-last-child-pre-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
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
$analyzerBackupPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets.bak_20260810_issue243_nth_last_child'
$elementBackupPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets.bak_20260810_issue243_nth_last_child'
$runtimeBackupPath = 'entry/src/main/resources/rawfile/legado_runtime.html.bak_20260810_issue243_nth_last_child'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
}
function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  $resolved = Get-RepoPath $Path
  $bytes = [System.IO.File]::ReadAllBytes($resolved)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes)
}
function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Read-StrictText $Path | ConvertFrom-Json -Depth 100)
}
function Get-Sha256 {
  param([Parameter(Mandatory = $true)][byte[]]$Bytes)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToUpperInvariant()
  } finally {
    $sha.Dispose()
  }
}
function Assert-Witness {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "243 nth-last-child failure witness failed: $Message" }
}
function Write-AtomicJson {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][object]$Value
  )
  $resolved = Get-RepoPath $Path
  $directory = Split-Path -Parent $resolved
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $resolved -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

$fixture = Read-StrictJson $FixturePath
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$packagePath = Get-RepoPath $SourcePackagePath
$packageBytes = [System.IO.File]::ReadAllBytes($packagePath)
$packageHash = Get-Sha256 $packageBytes
$package = $strictUtf8.GetString($packageBytes) | ConvertFrom-Json -Depth 100
$nthLastChildRuleStringCount = 0
$affectedOrdinals = New-Object 'System.Collections.Generic.List[int]'
for ($index = 0; $index -lt @($package).Count; $index++) {
  $sourceText = $package[$index] | ConvertTo-Json -Depth 100 -Compress
  $count = ([regex]::Matches($sourceText, '(?i):nth-last-child\s*\(')).Count
  if ($count -gt 0) {
    $nthLastChildRuleStringCount += $count
    [void]$affectedOrdinals.Add($index + 1)
  }
}
$analyzer = Read-StrictText $analyzerBackupPath
$element = Read-StrictText $elementBackupPath
$runtime = Read-StrictText $runtimeBackupPath
$legado = Read-StrictText $legadoPath

Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen machine baseline drifted.'
Assert-Witness (@($package).Count -eq 458 -and $packageHash -eq $baselineHash) 'pinned source package count or hash drifted.'
Assert-Witness ([string]$fixture.issueId -eq $issueId -and [string]$fixture.contract -eq 'legado_jsoup_nth_last_child_context' -and @($fixture.htmlCases).Count -eq 3 -and @($fixture.syntheticDocumentCases).Count -eq 1) 'fixture binding or case count changed.'
Assert-Witness ($nthLastChildRuleStringCount -eq 0 -and $affectedOrdinals.Count -eq 0) 'the frozen package unexpectedly contains nth-last-child rules.'
Assert-Witness (-not $analyzer.Contains("pseudo.name === 'nth-last-child'") -and -not $element.Contains("pseudo.name === 'nth-last-child'") -and -not $runtime.Contains("pseudoName === 'nth-last-child'")) 'pre-fix backups already contain the missing nth-last-child consumers.'
Assert-Witness ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado selector handoff is missing.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'failure_witness'
  issueId = $issueId
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  failureClass = 'v2_nth_last_child_missing_in_synthetic_document_dom_and_string_consumers'
  fixturePath = $FixturePath
  sourcePackagePath = 'redacted_pinned_package'
  sourcePackageHash = $packageHash
  sourcePackageScan = [pscustomobject][ordered]@{ scannedSourceCount = @($package).Count; nthLastChildRuleStringCount = $nthLastChildRuleStringCount; affectedSourceOrdinals = $affectedOrdinals.ToArray() }
  sourcePaths = @($analyzerPath, $elementPath, $runtimePath, $legadoPath)
  preFixBackupPaths = @($analyzerBackupPath, $elementBackupPath, $runtimeBackupPath)
  failureWitness = [pscustomobject][ordered]@{
    branch = 'synthetic Document extraction or large-document string fallback'
    path = 'LegadoRuleAnalyzer.filterElementsByPseudoClasses -> filterElementsByStandardChildPseudo; HTMLElement.matchesPseudoClass; legadoMatchesJsoupPseudo'
    observed = 'The parser advertises nth-last-child as a standard Document pseudo, but all three V2 consumers lack a branch and therefore either fail closed or cannot reproduce Jsoup reverse element-sibling position.'
    expected = 'Jsoup counts every element sibling and evaluates an+b against the one-based position from the end; top-level Document children remain rejected by the existing boundary rule.'
  }
  rootCauseDecision = 'The pinned Legado selector contract includes nth-last-child semantics, while the V2 consumer matrix has no typed reverse child-position implementation. The frozen source package has zero occurrences, so this is a general compatibility gap rather than a source-specific failure.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_nth_last_child_failure_witness_static_only;runtime_regression_build_device_and_legado_diff_deferred'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
