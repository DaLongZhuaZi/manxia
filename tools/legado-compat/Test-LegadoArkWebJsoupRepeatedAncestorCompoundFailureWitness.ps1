[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-arkweb-jsoup-repeated-ancestor-compound-context.json',
  [string]$RuntimeSnapshotPath = 'entry/src/main/resources/rawfile/legado_runtime.html.bak_20260810_issue243_repeated_ancestor_compound',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-repeated-ancestor-compound-pre-fix-20260810.json'
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
$script:assertions = 0

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  return Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
}
function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  $resolved = Get-RepoPath $Path
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
  if (-not $Condition) { throw "ArkWeb 243 repeated ancestor compound failure witness failed: $Message" }
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
$sourcePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToUpperInvariant()
$sources = @($strictUtf8.GetString([System.IO.File]::ReadAllBytes($sourcePath)) | ConvertFrom-Json -Depth 100)
$ordinal21 = $sources[20]
$coverRule = [string]$ordinal21.ruleBookInfo.coverUrl
$introRule = [string]$ordinal21.ruleBookInfo.intro

Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen machine baseline drifted.'
Assert-Witness ($sourceHash -eq $baselineHash -and $sources.Count -eq 458) 'frozen source package drifted.'
Assert-Witness ([string]$fixture.issueId -eq $issueId -and [string]$fixture.contract -eq 'arkweb_legado_jsoup_repeated_ancestor_compound_context' -and @($fixture.cases).Count -eq 3) 'repeated-ancestor fixture identity or case count changed.'
Assert-Witness (@($fixture.affectedSourceSet.sourceOrdinals) -contains 21 -and [int]$fixture.affectedSourceSet.ruleStringCount -eq 2) 'affected ordinal 21 is not bound to the fixture.'
Assert-Witness ($coverRule.Contains('tr:nth-of-type(3) table tr td:nth-of-type(2)') -and $introRule.Contains('tr:nth-of-type(3) table tr td:nth-of-type(2)')) 'ordinal-21 frozen source rules are missing.'
Assert-Witness ($runtime.Contains('var targetSelector = legadoSelectorCompoundBefore(normalized, normalized.length);')) 'pre-fix parser does not expose manual pseudo target selectors.'
Assert-Witness (-not $runtime.Contains('targetOccurrenceFromRight')) 'pre-fix runtime already contains duplicate-compound occurrence binding.'
Assert-Witness ($runtime.Contains('while (ancestor)') -and $runtime.Contains('ancestor.matches && ancestor.matches(pseudo.targetSelector)')) 'pre-fix nearest-ancestor projection is missing.'
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
  affectedSourceSet = [pscustomobject][ordered]@{ sourceOrdinals = @($fixture.affectedSourceSet.sourceOrdinals); ruleStringCount = [int]$fixture.affectedSourceSet.ruleStringCount; ruleStrings = @($fixture.affectedSourceSet.ruleStrings) }
  sourcePaths = @($RuntimeSnapshotPath, $legadoPath)
  runtimeSnapshotPath = $RuntimeSnapshotPath
  runtimeSnapshotSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $RuntimeSnapshotPath)).Hash.ToUpperInvariant()
  failureWitness = [pscustomobject][ordered]@{
    branch = 'legadoParseJsoupTextPseudos -> browser querySelectorAll -> legadoMatchesJsoupPseudo'
    observed = 'The pre-fix ArkWeb matcher stores only targetSelector and chooses the nearest ancestor matching that selector. When two compounds share the same selector text, an outer pseudo such as tr:nth-of-type(3) is evaluated on the inner tr instead of its own compound.'
    expected = 'Each manual pseudo must retain its owning compound occurrence from the right and select the matching ancestor at that occurrence before evaluating the predicate.'
    representativeRules = @($fixture.affectedSourceSet.ruleStrings)
  }
  rootCauseCategory = '规则解析或编译'
  rootCauseDecision = 'Pinned Legado keeps evaluator and element identity for every selector compound. ArkWeb collapses all manual pseudos onto a targetSelector string and nearest ancestor, losing occurrence identity for repeated ancestor compounds.'
  currentPackageImpact = 'Frozen ordinal 21 contains two BookInfo rules with repeated tr compounds; the outer nth-of-type predicate is a real affected rule shape.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_arkweb_repeated_ancestor_compound_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  assertions = $script:assertions
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
