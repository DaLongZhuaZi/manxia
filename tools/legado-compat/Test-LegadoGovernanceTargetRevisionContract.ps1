[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-governance-target-revision-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)

$expectedRevision = '2026-08-10-actual-docs-source-refactor-jsoup-combination-r4-readiness-static-closure'
$expectedIssue = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$historicalEvidence = @(
  'tools/legado-compat/evidence/r3-source-queue-preflight-20260810-r8/current-static-candidate-preflight.json',
  'tools/legado-compat/evidence/r3-source-queue-preflight-20260810-r9/current-static-candidate-preflight.json'
)
$expectedSourceCount = 458
$expectedSourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$expectedLegadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing file: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([string]$RelativePath)
  try { return (Read-StrictText -RelativePath $RelativePath | ConvertFrom-Json) }
  catch { throw "Invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Get-Text {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return '' }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return '' }
  return [string]$property.Value
}

function Get-Count {
  param([object]$Value)
  if ($null -eq $Value) { return 0 }
  return @($Value).Count
}

function Add-Assertion {
  param([System.Collections.Generic.List[object]]$Assertions, [string]$Id, [bool]$Passed, [string]$Detail)
  $Assertions.Add([pscustomobject][ordered]@{ id = $Id; status = $(if ($Passed) { 'passed' } else { 'failed' }); detail = $Detail })
  if (-not $Passed) { throw "Assertion failed: $Id; $Detail" }
}

function Write-AtomicJson {
  param([string]$RelativePath, [object]$Value)
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 60), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$assertions = [System.Collections.Generic.List[object]]::new()
$status = 'passed'
$failure = ''
$now = [DateTimeOffset]::UtcNow.ToString('o')

try {
  $stateRelative = 'tools/legado-compat/state/full-source-validation-state.json'
  $objectiveRelative = 'tools/legado-compat/state/refactor-objective.json'
  $documentRelative = 'docs/analysis/Legado书源V2源码重构持续目标.md'
  $state = Read-StrictJson $stateRelative
  $objective = Read-StrictJson $objectiveRelative
  $document = Read-StrictText $documentRelative
  $queueRelative = Get-Text $state.governance.queuePreflight 'evidencePath'
  $queue = Read-StrictJson $queueRelative
  $r8 = Read-StrictJson $historicalEvidence[0]
  $r9 = Read-StrictJson $historicalEvidence[1]

  Add-Assertion $assertions 'objective_target_revision_canonical' ((Get-Text $objective 'targetRevision') -eq $expectedRevision) "objective.targetRevision=$(Get-Text $objective 'targetRevision')"
  Add-Assertion $assertions 'document_revision_canonical' ($document -match ('(?m)^当前修订：' + [regex]::Escape($expectedRevision) + '\s*$')) 'document current revision matches canonical revision'
  Add-Assertion $assertions 'queue_pointer_is_current_machine_fact' ($queueRelative.Length -gt 0 -and $queueRelative -notin $historicalEvidence -and (Test-Path -LiteralPath (Get-RepoPath $queueRelative) -PathType Leaf)) "queuePreflight.evidencePath=$queueRelative"
  Add-Assertion $assertions 'queue_evidence_target_revision_canonical' ((Get-Text $queue 'targetRevision') -eq $expectedRevision) "queue.targetRevision=$(Get-Text $queue 'targetRevision')"
  Add-Assertion $assertions 'queue_target_matches_objective' ((Get-Text $queue 'targetRevision') -eq (Get-Text $objective 'targetRevision')) 'queue and objective target revisions match'
  Add-Assertion $assertions 'queue_target_matches_document' ($document -match [regex]::Escape((Get-Text $queue 'targetRevision'))) 'queue target revision is present in current document'
  Add-Assertion $assertions 'queue_issue_matches_active_issue' ((Get-Text $queue 'activeIssueId') -eq $expectedIssue -and (Get-Text $state.governance 'activeIssueId') -eq $expectedIssue) 'queue and governance use ISSUE-COMPAT-243 as the active issue'
  Add-Assertion $assertions 'queue_status_passed' ((Get-Text $queue 'status') -eq 'passed') "queue.status=$(Get-Text $queue 'status')"
  Add-Assertion $assertions 'queue_no_candidate' ([int]$queue.candidateCount -eq 0 -and [int]$queue.evaluatedCount -eq 229 -and (Get-Text $queue 'candidateGateStatus') -eq 'no_candidate_satisfies_evidence_gate') '229 evaluated, zero candidates, static gate remains closed'
  Add-Assertion $assertions 'queue_runtime_locked' ((Get-Count $queue.runtimeActionsPerformed) -eq 0 -and -not [bool]$queue.semanticMatchAllowed) 'queue has no runtime actions and semantic matching is disabled'
  Add-Assertion $assertions 'state_runtime_locked' ((Get-Count $state.governance.runtimeActionsPerformed) -eq 0 -and -not [bool]$state.governance.semanticMatchAllowed) 'machine governance state has no runtime actions and semantic matching is disabled'
  Add-Assertion $assertions 'active_issue_verifying' ((Get-Text $state.governance 'status') -eq 'running' -and ((@($state.governance.issues) | Where-Object { (Get-Text $_ 'id') -eq $expectedIssue } | Select-Object -First 1 | ForEach-Object { Get-Text $_ 'status' }) -eq 'verifying')) 'active issue remains verifying under static-only policy'
  Add-Assertion $assertions 'queue_baseline_frozen' ([int]$queue.baseline.sourceCount -eq $expectedSourceCount -and (Get-Text $queue.baseline 'sourcePackageSha256') -eq $expectedSourceHash -and (Get-Text $queue.baseline 'legadoCommit') -eq $expectedLegadoCommit) 'queue baseline matches 458/hash/Legado commit'
  Add-Assertion $assertions 'state_baseline_frozen' ([int]$state.baseline.sourceCount -eq $expectedSourceCount -and (Get-Text $state.baseline 'sourcePackageSha256') -eq $expectedSourceHash -and (Get-Text $state.baseline 'legadoCommit') -eq $expectedLegadoCommit) 'state baseline matches 458/hash/Legado commit'
  Add-Assertion $assertions 'historical_r8_excluded' ((Get-Text $r8 'targetRevision') -ne $expectedRevision -and $queueRelative -ne $historicalEvidence[0]) 'r8 is historical evidence only'
  Add-Assertion $assertions 'historical_r9_excluded' ((Get-Text $r9 'targetRevision') -ne $expectedRevision -and $queueRelative -ne $historicalEvidence[1]) 'r9 is historical evidence only'
  Add-Assertion $assertions 'pre_fix_witness_retained' ((Test-Path -LiteralPath (Get-RepoPath 'tools/legado-compat/evidence/contract-legado-governance-target-revision-drift-pre-fix-20260810.json') -PathType Leaf)) 'pre-fix drift witness remains available'
  Add-Assertion $assertions 'current_queue_evidence_exists' ((Test-Path -LiteralPath (Get-RepoPath $queueRelative) -PathType Leaf)) 'current machine queue evidence is registered and addressable'
  Add-Assertion $assertions 'static_policy_documented' ($document -match 'R4 运行时、458 条 Harness、Legado 差分、构建和真机验证继续延期') 'document retains the static-only/R4-deferred policy'
  Add-Assertion $assertions 'current_pointer_is_machine_fact' ($queueRelative -eq (Get-Text $objective.continuationTarget.queueAudit 'auditEvidencePath')) 'objective queue audit points to the same machine evidence'
  Add-Assertion $assertions 'no_legacy_revision_alias' ((Get-Text $objective 'targetRevision') -notmatch 'empty-pseudo|nested-descendant|regex-contains') 'objective does not use superseded revision aliases'
} catch {
  $status = 'failed'
  $failure = $_.Exception.Message
}

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_governance_target_revision_contract'
  status = $status
  generatedAt = $now
  targetRevision = $expectedRevision
  activeIssueId = $expectedIssue
  baseline = [pscustomobject][ordered]@{ sourceCount = $expectedSourceCount; sourcePackageSha256 = $expectedSourceHash; legadoCommit = $expectedLegadoCommit }
  currentQueueEvidencePath = $queueRelative
  historicalEvidencePaths = $historicalEvidence
  assertionCount = $assertions.Count
  passedAssertionCount = @($assertions | Where-Object { $_.status -eq 'passed' }).Count
  assertions = @($assertions)
  failure = $failure
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'static_governance_revision_contract_only;runtime_build_install_device_and_legado_diff_deferred'
}
Write-AtomicJson -RelativePath $OutputPath -Value $result
if ($status -ne 'passed') { throw $failure }
$result | ConvertTo-Json -Depth 60
