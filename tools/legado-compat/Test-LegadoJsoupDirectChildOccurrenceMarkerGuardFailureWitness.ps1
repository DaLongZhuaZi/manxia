[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-direct-child-occurrence-marker-guard.json',
  [string]$SourcePackagePath = 'F:/Downloads-E/墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-direct-child-occurrence-marker-guard-pre-fix-20260810.json'
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
$analyzerRelativePath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$legadoRelativePath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$script:assertions = 0

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
}
function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  $resolved = Get-RepoPath $Path
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Missing text: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($resolved)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return $strictUtf8.GetString($bytes)
}
function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Read-StrictText $Path | ConvertFrom-Json -Depth 100)
}
function Assert-Witness {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "243 direct-child marker guard failure witness failed: $Message" }
  $script:assertions++
}
function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $resolved = Get-RepoPath $Path
  $directory = Split-Path -Parent $resolved
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
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
$analyzer = Read-StrictText $analyzerRelativePath
$legado = Read-StrictText $legadoRelativePath
$packageBytes = [System.IO.File]::ReadAllBytes((Get-RepoPath $SourcePackagePath))
$packageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $SourcePackagePath)).Hash.ToUpperInvariant()
$package = @($strictUtf8.GetString($packageBytes) | ConvertFrom-Json -Depth 100)

Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen machine baseline drifted.'
Assert-Witness ($package.Count -eq 458 -and $packageHash -eq $baselineHash) 'frozen source package drifted.'
Assert-Witness ([string]$fixture.issueId -eq $issueId -and [string]$fixture.contract -eq 'legado_jsoup_direct_child_occurrence_marker_guard' -and @($fixture.cases).Count -eq 2) 'fixture binding or case count changed.'
foreach ($ordinal in @($fixture.affectedSourceOrdinals)) {
  Assert-Witness ([int]$ordinal -ge 1 -and [int]$ordinal -le $package.Count) "affected ordinal is outside the frozen package: $ordinal"
}
foreach ($rule in @($fixture.representativeRules)) {
  $found = $false
  foreach ($source in $package) {
    if (($source | ConvertTo-Json -Depth 100 -Compress).Contains([string]$rule)) { $found = $true; break }
  }
  Assert-Witness $found "representative rule is missing: $rule"
}
Assert-Witness ($analyzer.Contains('private findElementsByDirectChildSelector(')) 'direct-child selector method is absent.'
$methodStart = $analyzer.IndexOf('private findElementsByDirectChildSelector(')
$methodEnd = $analyzer.IndexOf('private getElementsByRegex(', $methodStart)
Assert-Witness ($methodStart -ge 0 -and $methodEnd -gt $methodStart) 'direct-child method boundary is not stable.'
$method = $analyzer.Substring($methodStart, $methodEnd - $methodStart)
Assert-Witness ($method.Contains('if (!needsOccurrenceMarkers)')) 'pre-fix undefined marker guard is absent.'
Assert-Witness (-not $method.Contains('const needsOccurrenceMarkers')) 'the direct-child method unexpectedly declares a local marker guard.'
Assert-Witness (-not $method.Contains("needsOccurrenceMarkers: boolean")) 'the direct-child method does not receive marker state as a parameter.'
Assert-Witness ($analyzer.Contains("const needsOccurrenceMarkers = selector.includes(':')") -and $analyzer.Contains('return currentElements;')) 'outer CSS-chain marker state is present but not consumed at its return boundary.'
Assert-Witness ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado Jsoup selector handoff is missing.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'failure_witness'
  issueId = $issueId
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  sourcePackagePath = 'redacted_pinned_package'
  sourcePackageHash = $packageHash
  affectedSourceSet = [pscustomobject][ordered]@{ sourceOrdinals = @($fixture.affectedSourceOrdinals); ruleStringCount = @($fixture.representativeRules).Count }
  sourcePaths = @($analyzerRelativePath, $legadoRelativePath)
  failureWitness = [pscustomobject][ordered]@{
    branch = 'findElementsByDirectChildSelector final marker guard'
    path = 'LegadoRuleAnalyzer.getElementsByCSSChain -> findElementsBySingleSelector -> findElementsByDirectChildSelector'
    observed = 'The direct-child method references needsOccurrenceMarkers outside its scope. A direct-child pseudo selector therefore has an unbound identifier at runtime; the method also cannot safely decide whether to strip markers without receiving the chain state.'
    expected = 'Direct-child evaluation preserves internal occurrence markers while nested selector/group evaluation is active. getElementsByCSSChain strips them exactly once at its final workflow boundary.'
  }
  rootCauseCategory = '规则解析或编译'
  rootCauseDecision = 'Occurrence-marker lifetime was split between the outer CSS chain and the direct-child helper without a typed contract. The helper reads an outer local that is not in scope, and marker stripping is placed at the wrong boundary.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_direct_child_occurrence_marker_guard_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred'
  assertions = $script:assertions
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
