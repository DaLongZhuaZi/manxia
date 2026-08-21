[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-arkweb-jsoup-index-middle-compound-context.json',
  [string]$RuntimeSnapshotPath = 'entry/src/main/resources/rawfile/legado_runtime.html.bak_20260810_issue243_middle_compound_pseudo',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-index-middle-compound-pre-fix-20260810.json'
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
$sourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
$script:assertions = 0

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  return Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
}
function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  $resolved = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Get-RepoPath $Path }
  $bytes = [System.IO.File]::ReadAllBytes($resolved)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return $strictUtf8.GetString($bytes)
}
function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Read-StrictText $Path | ConvertFrom-Json -Depth 100)
}
function Get-StringValues {
  param([object]$Value)
  if ($Value -is [string]) { return ,([string]$Value) }
  if ($null -eq $Value) { return @() }
  if ($Value -is [System.Collections.IEnumerable]) {
    $items = New-Object 'System.Collections.Generic.List[string]'
    foreach ($item in $Value) { foreach ($text in @(Get-StringValues $item)) { [void]$items.Add([string]$text) } }
    return $items.ToArray()
  }
  $properties = $Value.PSObject.Properties
  if ($null -eq $properties) { return @() }
  $result = New-Object 'System.Collections.Generic.List[string]'
  foreach ($property in $properties) { foreach ($text in @(Get-StringValues $property.Value)) { [void]$result.Add([string]$text) } }
  return $result.ToArray()
}
function Assert-Witness {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "ArkWeb 243 index middle-compound failure witness failed: $Message" }
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

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$runtime = Read-StrictText $RuntimeSnapshotPath
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$legado = Read-StrictText $legadoPath
$sourceBytes = [System.IO.File]::ReadAllBytes($sourcePackagePath)
$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePackagePath).Hash.ToUpperInvariant()
$sources = @($strictUtf8.GetString($sourceBytes) | ConvertFrom-Json -Depth 100)
$sourceStrings = @(Get-StringValues $sources)
$indexPseudoStrings = @($sourceStrings | Where-Object { $_.Contains(':eq(') -or $_.Contains(':lt(') })
$middleCompoundStrings = @($indexPseudoStrings | Where-Object { [regex]::IsMatch($_, ':(?:eq|lt)\([^)]*\)\s*(?:[>+~]|\s+)\s*[A-Za-z.#]') })

Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen machine baseline drifted.'
Assert-Witness ($sourceHash -eq $baselineHash -and $sources.Count -eq 458) 'frozen source package drifted.'
Assert-Witness ([string]$fixture.issueId -eq $issueId -and [string]$fixture.contract -eq 'arkweb_legado_jsoup_index_pseudo_middle_compound_context' -and @($fixture.cases).Count -eq 4) 'middle-compound fixture identity or case count changed.'
Assert-Witness ([int]$fixture.sourcePackageScan.scannedSourceCount -eq 458 -and [int]$fixture.sourcePackageScan.indexPseudoRuleStringCount -eq $indexPseudoStrings.Count -and [int]$fixture.sourcePackageScan.middleCompoundRuleStringCount -eq $middleCompoundStrings.Count -and $middleCompoundStrings.Count -eq 0) 'frozen package scan no longer proves terminal-only eq/lt usage.'
Assert-Witness ($runtime.Contains("var siblingIndex = legadoElementSiblingIndex(node);")) 'pre-fix ArkWeb eq/lt branch no longer evaluates the terminal candidate node.'
Assert-Witness ($runtime.Contains('predicateNode = targetFound;')) 'pre-fix runtime does not expose owning-compound projection context.'
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
  sourcePackageHash = $sourceHash
  sourcePackageScan = [pscustomobject][ordered]@{ scannedSourceCount = $sources.Count; indexPseudoRuleStringCount = $indexPseudoStrings.Count; middleCompoundRuleStringCount = $middleCompoundStrings.Count; affectedSourceOrdinals = @() }
  affectedSourceSet = [pscustomobject][ordered]@{ sourceOrdinals = @(); ruleStringCount = 0; syntheticCases = $true }
  sourcePaths = @($RuntimeSnapshotPath, $legadoPath)
  runtimeSnapshotPath = $RuntimeSnapshotPath
  runtimeSnapshotSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $RuntimeSnapshotPath)).Hash.ToUpperInvariant()
  failureWitness = [pscustomobject][ordered]@{
    branch = 'legadoMatchesJsoupPseudo -> eq/lt sibling index predicate'
    observed = 'The pre-fix ArkWeb branch evaluates eq/lt against the terminal querySelectorAll candidate node. For div > p:eq(1) > a and div > p:lt(2) > a, the predicate therefore reads each a sibling index instead of the owning p compound index.'
    expected = 'Each manual eq/lt pseudo must evaluate predicateNode, the element matched by its owning compound, before the terminal a projection is returned.'
    representativeRules = @($fixture.cases | ForEach-Object { [string]$_.rule })
  }
  rootCauseCategory = '规则解析或编译'
  rootCauseDecision = 'Pinned Legado hands the full CSS selector to Jsoup, whose index evaluators retain compound ownership. ArkWeb currently retains owning context for other manual pseudos but uses node in the eq/lt branch, creating a semantic hole for non-terminal compounds.'
  currentPackageImpact = 'No frozen-package rule currently places eq/lt before a later combinator; the fixture is synthetic and protects general Legado compatibility.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_arkweb_index_middle_compound_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  assertions = $script:assertions
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
