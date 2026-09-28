[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-governance-queue-pointer-rotation-drift.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-governance-queue-pointer-rotation-drift-pre-fix-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-governance-queue-pointer-rotation-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-AUTO-054-GOVERNANCE-QUEUE-POINTER-ROTATION-DRIFT'
$activeIssueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$revision = '2026-08-10-actual-docs-source-refactor-jsoup-combination-r4-readiness-static-closure'
$assertions = New-Object 'System.Collections.Generic.List[object]'

function Get-RepoPath([string]$RelativePath) {
  if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $RelativePath }
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText([string]$RelativePath) {
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing file: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson([string]$RelativePath) {
  return Read-StrictText $RelativePath | ConvertFrom-Json -Depth 100
}

function Add-Assertion([string]$Id, [bool]$Passed, [string]$Detail) {
  [void]$assertions.Add([pscustomobject][ordered]@{ id = $Id; status = $(if ($Passed) { 'passed' } else { 'failed' }); detail = $Detail })
  if (-not $Passed) { throw "Queue pointer rotation contract failed: $Id; $Detail" }
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 80), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

$fixture = Read-StrictJson $FixturePath
$failureWitness = Read-StrictJson $FailureWitnessPath
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$objective = Read-StrictJson 'tools/legado-compat/state/refactor-objective.json'
$queuePath = [string]$state.governance.queuePreflight.evidencePath
$queue = Read-StrictJson $queuePath
$contractPaths = @(
  'tools/legado-compat/Test-LegadoGovernanceTargetRevisionContract.ps1',
  'tools/legado-compat/Test-LegadoGovernanceQueueAuditEvidenceContract.ps1',
  'tools/legado-compat/Test-LegadoGovernanceQueueAuditStatusContract.ps1',
  'tools/legado-compat/Test-LegadoGovernanceQueueCountConsistencyContract.ps1',
  'tools/legado-compat/Register-LegadoGovernanceTargetRevisionSourceFix.ps1',
  'tools/legado-compat/Register-LegadoGovernanceQueueAuditEvidenceSourceFix.ps1',
  'tools/legado-compat/Register-LegadoGovernanceQueueAuditStatusSourceFix.ps1'
)
$contractText = ($contractPaths | ForEach-Object { Read-StrictText $_ }) -join "`n"

Add-Assertion 'fixture_binding' ([string]$fixture.issueId -eq $issueId -and [string]$fixture.currentQueueEvidenceSource -match 'full-source-validation-state') 'fixture binds the pointer source to machine facts'
Add-Assertion 'failure_witness_retained' ([string]$failureWitness.status -eq 'failed' -and [string]$failureWitness.failureClass -eq 'governance_queue_pointer_rotation_drift') 'pre-fix failure witness remains immutable and addressable'
Add-Assertion 'baseline_binding' ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline remains frozen'
Add-Assertion 'objective_revision_binding' ([string]$objective.targetRevision -eq $revision -and [string]$queue.targetRevision -eq $revision) 'objective and current queue share the canonical revision'
Add-Assertion 'active_issue_binding' ([string]$state.governance.activeIssueId -eq $activeIssueId -and [string]$queue.activeIssueId -eq $activeIssueId) 'active issue remains 243'
Add-Assertion 'current_pointer_exists' ($queuePath.Length -gt 0 -and (Test-Path -LiteralPath (Get-RepoPath $queuePath) -PathType Leaf)) 'machine queue pointer resolves to an existing evidence file'
Add-Assertion 'current_pointer_is_not_historical' ($queuePath -notin @($fixture.staleContractPointers)) 'current pointer is not one of the historical r8/r9/r10 paths'
Add-Assertion 'queue_no_candidate' ([int]$queue.candidateCount -eq 0 -and [int]$queue.evaluatedCount -eq 229 -and [string]$queue.candidateGateStatus -eq 'no_candidate_satisfies_evidence_gate') 'current queue remains the static 229/0 no-candidate branch'
Add-Assertion 'runtime_locked' (@($queue.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$queue.semanticMatchAllowed -and @($state.governance.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$state.governance.semanticMatchAllowed) 'pointer contract remains static-only'
Add-Assertion 'no_current_r10_literal' ($contractText -notmatch 'r3-source-queue-preflight-20260810-r10/current-static-candidate-preflight\.json') 'current contracts and registrars do not hardcode r10'
Add-Assertion 'no_fixture_gate_literal' ((Read-StrictText 'tools/legado-compat/Test-LegadoGovernanceQueueCountConsistencyContract.ps1') -notmatch 'fixture\.currentGatePath') 'count contract resolves its gate from machine facts'
Add-Assertion 'queue_audit_pointer_sync' ([string]$objective.continuationTarget.queueAudit.auditEvidencePath -eq $queuePath) 'objective queue audit follows the machine pointer'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_governance_queue_pointer_rotation_contract'
  status = 'passed_static_only'
  issueId = $issueId
  activeIssueId = $activeIssueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  targetRevision = $revision
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  currentQueueEvidencePath = $queuePath
  assertionCount = $assertions.Count
  assertions = $assertions.ToArray()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'static_governance_pointer_rotation_contract_only;runtime_build_install_device_and_legado_diff_deferred'
  closeCondition = 'Current queue contracts and registrars resolve the evidence path from the machine fact state; historical batch paths remain provenance-only.'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 80
