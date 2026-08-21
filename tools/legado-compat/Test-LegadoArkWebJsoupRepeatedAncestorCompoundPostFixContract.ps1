[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-arkweb-jsoup-repeated-ancestor-compound-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-repeated-ancestor-compound-pre-fix-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-repeated-ancestor-compound-post-fix-20260810.json'
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
$script:checks = New-Object 'System.Collections.Generic.List[object]'

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
function Assert-Contract {
  param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @())
  if (-not $Condition) { throw "ArkWeb 243 repeated ancestor compound post-fix contract failed: $Detail" }
  $script:assertions++
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) })
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
$failure = Read-StrictJson $FailureWitnessPath
$runtimePath = 'entry/src/main/resources/rawfile/legado_runtime.html'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$runtime = Read-StrictText $runtimePath
$legado = Read-StrictText $legadoPath

Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'frozen machine baseline is unchanged.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Contract ([string]$fixture.issueId -eq $issueId -and [string]$fixture.contract -eq 'arkweb_legado_jsoup_repeated_ancestor_compound_context' -and @($fixture.cases).Count -eq 3) 'fixture' 'repeated-ancestor fixture retains three occurrence-binding cases.' @($FixturePath)
Assert-Contract (@($fixture.affectedSourceSet.sourceOrdinals) -contains 21 -and [int]$fixture.affectedSourceSet.ruleStringCount -eq 2) 'affected_source' 'frozen ordinal 21 remains bound to two repeated-tr BookInfo rules.' @($FixturePath)
Assert-Contract ([string]$failure.status -eq 'failed' -and @($failure.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed) 'failure_witness' 'pre-fix witness remains failed and static-only.' @($FailureWitnessPath)
Assert-Contract ($runtime.Contains('var legadoSelectorCompoundParts = function (selector)')) 'compound_parts' 'runtime now tokenizes top-level selector compounds without splitting nested arguments.' @($runtimePath)
Assert-Contract ($runtime.Contains('var legadoSelectorCompoundIndexAt = function (selector, endIndex)')) 'compound_index' 'parser records the owning compound index at each pseudo source position.' @($runtimePath)
Assert-Contract ($runtime.Contains('targetCompoundIndex: legadoSelectorCompoundIndexAt(text, cursor)')) 'target_index' 'each manual pseudo retains its owning compound index.' @($runtimePath)
Assert-Contract ($runtime.Contains('targetOccurrenceFromRight: 0') -and $runtime.Contains('pseudo.targetOccurrenceFromRight = occurrenceFromRight;')) 'target_occurrence' 'each pseudo is assigned the occurrence of its equal compound from the right.' @($runtimePath)
Assert-Contract ($runtime.Contains('var matchingAncestors = [];') -and $runtime.Contains('predicateNode = matchingAncestors[targetOccurrence];')) 'owner_projection' 'matcher projects the predicate onto the occurrence-specific ancestor instead of always choosing the nearest one.' @($runtimePath)
Assert-Contract ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'legado_consumer' 'the pinned Legado selector handoff remains the reference.' @($legadoPath)

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'post_fix_static_contract'
  issueId = $issueId
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  failureWitnessPath = $FailureWitnessPath
  changedPaths = @($runtimePath)
  affectedSourceOrdinals = @($fixture.affectedSourceSet.sourceOrdinals)
  affectedRuleStringCount = [int]$fixture.affectedSourceSet.ruleStringCount
  syntheticCases = @($fixture.cases).Count
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_arkweb_repeated_ancestor_compound_post_fix_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  closeCondition = 'R4 must execute all three occurrence-binding cases, both ordinal-21 rules, the existing 243 pseudo fixtures, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
