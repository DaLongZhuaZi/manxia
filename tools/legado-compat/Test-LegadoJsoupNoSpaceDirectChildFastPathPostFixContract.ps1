[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-no-space-direct-child-fast-path-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-no-space-direct-child-fast-path-pre-fix-20260810.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-no-space-direct-child-fast-path-post-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$assertions = 0
$checks = [System.Collections.Generic.List[object]]::new()

function Get-RepoPath([string]$RelativePath) { return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictText([string]$RelativePath) {
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing file: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}
function Read-StrictJson([string]$RelativePath) { return Read-StrictText $RelativePath | ConvertFrom-Json -Depth 100 }
function Assert-Contract([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @()) {
  if (-not $Condition) { throw "243 no-space direct-child post-fix contract failed: $Detail" }
  $script:assertions++
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) })
}
function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepoPath $RelativePath
  $temp = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try { [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temp -Destination $path -Force }
  finally { if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) } }
}

$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$sourceRelativePath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$source = Read-StrictText $sourceRelativePath
Assert-Contract ([int]$fixture.baseline.sourceCount -eq 458 -and [string]$fixture.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$fixture.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'fixture remains bound to the frozen package and pinned Legado commit.' @($FixturePath)
Assert-Contract ([string]$failure.status -eq 'failed' -and -not [bool]$failure.semanticMatchAllowed -and @($failure.runtimeActionsPerformed).Count -eq 0) 'failure_witness' 'the pre-fix witness remains failed and static-only.' @($FailureWitnessPath)
Assert-Contract (@($fixture.cases).Count -eq 5 -and @($fixture.affectedSourceOrdinals).Count -eq 18 -and [int]$fixture.affectedRuleStringCount -eq 30) 'fixture_scope' 'all five cases and the frozen 18-source/30-rule affected set are registered.' @($FixturePath)
Assert-Contract ($source.Contains('const hasTopLevelDirectChildCombinator = this.splitTopLevelDirectChildSelectors(selector).length > 1;')) 'guard_declared' 'the fast path computes a top-level direct-child guard.' @($sourceRelativePath)
Assert-Contract ($source.Contains('&& !hasTopLevelDirectChildCombinator)')) 'guard_consumed' 'class/id fast-path dispatch is disabled for no-space top-level child chains.' @($sourceRelativePath)
Assert-Contract ($source.Contains('const directChildParts = this.splitTopLevelDirectChildSelectors(selector);') -and $source.Contains('findElementsByDirectChildSelector(html, selector, effectiveContextHtml)')) 'direct_child_consumer' 'guarded selectors still reach the existing direct-child evaluator.' @($sourceRelativePath)
Assert-Contract ($source.Contains("character === '>' && parenthesisDepth === 0 && bracketDepth === 0")) 'nested_context_preserved' 'the top-level splitter still ignores nested pseudo and attribute greater-than characters.' @($sourceRelativePath)

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'post_fix_static_contract'
  issueId = $issueId
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  failureWitnessPath = $FailureWitnessPath
  changedPaths = @($sourceRelativePath)
  currentHeadHashes = [pscustomobject][ordered]@{ $sourceRelativePath = (Get-FileHash -LiteralPath (Get-RepoPath $sourceRelativePath) -Algorithm SHA256).Hash.ToUpperInvariant() }
  assertions = $assertions
  checks = $checks.ToArray()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_source_fix_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  closeCondition = 'R4 must execute all five no-space cases, the 18-source/30-rule affected set, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $ResultPath $result
$result | ConvertTo-Json -Depth 80
