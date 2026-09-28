[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-arkweb-jsoup-compound-pseudo-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-compound-pseudo-pre-fix-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-compound-pseudo-post-fix-20260810.json'
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
  if (-not $Condition) { throw "ArkWeb 243 compound pseudo post-fix contract failed: $Detail" }
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
Assert-Contract ([string]$fixture.issueId -eq $issueId -and [string]$fixture.contract -eq 'arkweb_legado_jsoup_compound_pseudo_context' -and @($fixture.cases).Count -eq 4) 'fixture' 'compound pseudo fixture retains four owning-compound cases.' @($FixturePath)
Assert-Contract (@($fixture.affectedSourceOrdinals).Count -eq 2 -and @($fixture.affectedSourceOrdinals) -contains 112 -and @($fixture.affectedSourceOrdinals) -contains 207) 'affected_sources' 'the frozen affected set retains ordinals 112 and 207.' @($FixturePath)
Assert-Contract ([string]$failure.status -eq 'failed' -and @($failure.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed) 'failure_witness' 'pre-fix witness remains failed and static-only.' @($FailureWitnessPath)
Assert-Contract ($runtime.Contains('var legadoSelectorCompoundBefore = function') -and $runtime.Contains('legadoSelectorCompoundBefore(normalized, normalized.length)')) 'compound_parser' 'the compiler extracts the owning compound before removing a manual pseudo.' @($runtimePath)
Assert-Contract ($runtime.Contains('var isDocumentPseudo = extractStandardDocumentPseudos === true') -and $runtime.Contains('var isManualPseudo = name ===')) 'manual_registry' 'standard Document pseudos and Jsoup extension pseudos share a typed manual dispatch gate.' @($runtimePath)
Assert-Contract ($runtime.Contains("targetScope: isStandardDocumentPseudo ? 'first-compound' : (isManualPseudo ? 'compound' : '')") -and $runtime.Contains('targetSelector: targetSelector')) 'target_metadata' 'each extracted pseudo records its owning compound instead of defaulting to the terminal node.' @($runtimePath)
Assert-Contract ($runtime.Contains("pseudo.targetScope === 'first-compound' || pseudo.targetScope === 'compound'") -and $runtime.Contains('predicateNode = targetFound')) 'target_resolution' 'the matcher resolves the compound target through the candidate ancestry.' @($runtimePath)
Assert-Contract ($runtime.Contains('legadoMatchesAnyJsoupSelector(predicateNode, argument, documentRoot)') -and $runtime.Contains('legadoSelectWithJsoupRegex(predicateNode, relativeSelector, null)')) 'nested_predicates' ':not and :has evaluate against the owning compound context.' @($runtimePath)
Assert-Contract ($runtime.Contains('? legadoOwnText(predicateNode)') -and $runtime.Contains(': legadoText(predicateNode);')) 'text_predicates' 'contains and matches predicates read the owning compound node.' @($runtimePath)
Assert-Contract ($runtime.Contains('legadoElementTypeIndex(predicateNode)') -and $runtime.Contains('legadoMatchNthExpression(typeIndex, argument)')) 'position_predicates' 'nth-of-type remains evaluated on the owning compound node.' @($runtimePath)
Assert-Contract ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'legado_consumer' 'the pinned Legado consumer remains the Jsoup CSS-selection reference.' @($legadoPath)

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
  affectedSourceOrdinals = @($fixture.affectedSourceOrdinals)
  cases = @($fixture.cases).Count
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_arkweb_compound_pseudo_post_fix_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  closeCondition = 'R4 must execute all four compound-context cases, ordinals 112 and 207, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
