[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-governance-queue-audit-status-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$fixturePath = 'tools/legado-compat/fixtures/legado-governance-queue-audit-status-drift.json'
$failureWitnessPath = 'tools/legado-compat/evidence/contract-legado-governance-queue-audit-status-drift-pre-fix-20260810.json'
$registerScriptPath = 'tools/legado-compat/Register-LegadoCurrentStaticSourceCandidateGate.ps1'

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing file: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  try { return ($strictUtf8.GetString($bytes) | ConvertFrom-Json) }
  catch { throw "Invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Get-Text {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return '' }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return '' }
  return [string]$property.Value
}

function Add-ContractAssertion {
  param([System.Collections.Generic.List[object]]$Assertions, [string]$Id, [bool]$Passed, [string]$Detail)
  [void]$Assertions.Add([pscustomobject][ordered]@{ id = $Id; status = $(if ($Passed) { 'passed' } else { 'failed' }); detail = $Detail })
  if (-not $Passed) { throw "Queue audit status contract failed: $Id; $Detail" }
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

$fixture = Read-StrictJson $fixturePath
$failureWitness = Read-StrictJson $failureWitnessPath
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$objective = Read-StrictJson 'tools/legado-compat/state/refactor-objective.json'
$queueEvidencePath = [string]$state.governance.queuePreflight.evidencePath
$queue = Read-StrictJson $queueEvidencePath
$queueAudit = $objective.continuationTarget.queueAudit
$selectionGate = $objective.objective.queueSelectionGate
$registerText = [System.IO.File]::ReadAllText((Get-RepoPath $registerScriptPath), $strictUtf8)
$assertions = [System.Collections.Generic.List[object]]::new()

Add-ContractAssertion $assertions 'fixture_binding' ([string]$fixture.issueId -eq 'ISSUE-AUTO-053-GOVERNANCE-QUEUE-AUDIT-STATUS-DRIFT') 'fixture is bound to ISSUE-AUTO-053'
Add-ContractAssertion $assertions 'baseline_binding' ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq [string]$fixture.baseline.sourcePackageSha256 -and [string]$state.baseline.legadoCommit -eq [string]$fixture.baseline.legadoCommit) 'machine baseline remains frozen'
Add-ContractAssertion $assertions 'revision_binding' ([string]$objective.targetRevision -eq [string]$fixture.canonicalRevision -and [string]$queue.targetRevision -eq [string]$fixture.canonicalRevision) 'objective and queue use the canonical revision'
Add-ContractAssertion $assertions 'failure_witness' ([string]$failureWitness.status -eq 'failed' -and [string]$failureWitness.failureClass -eq 'governance_queue_audit_status_drift') 'pre-fix failure witness remains available'
Add-ContractAssertion $assertions 'queue_pointer_binding' ($queueEvidencePath.Length -gt 0 -and (Test-Path -LiteralPath (Get-RepoPath $queueEvidencePath) -PathType Leaf) -and [int]$queue.candidateCount -eq 0) 'machine pointer and queue count remain fixed'
Add-ContractAssertion $assertions 'no_candidate_status' ([string]$queueAudit.status -eq [string]$fixture.expectedAfterFix.status -and [int]$queue.candidateCount -eq [int]$fixture.expectedAfterFix.candidateCount -and [string]$queueAudit.candidateGateStatus -eq [string]$fixture.expectedAfterFix.candidateGateStatus -and [string]$queueAudit.candidateStatus -eq [string]$fixture.expectedAfterFix.candidateStatus) 'queue audit explicitly describes the no-candidate branch'
Add-ContractAssertion $assertions 'selection_gate_preserved' ([string]$selectionGate.candidateStatus -eq [string]$fixture.selectionGateInvariant.candidateStatus -and [string]$selectionGate.candidateGateStatus -eq [string]$fixture.selectionGateInvariant.candidateGateStatus) 'active-issue selection gate was not rewritten'
Add-ContractAssertion $assertions 'registerer_sets_explicit_status' $registerText.Contains("Set-PropertyValue `$queueAudit 'candidateStatus' 'no_candidate_satisfies_evidence_gate'") 'queue registration code writes the explicit no-candidate status'
Add-ContractAssertion $assertions 'runtime_locked' (@($queue.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$queue.semanticMatchAllowed -and @($state.governance.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$state.governance.semanticMatchAllowed) 'contract remains static-only'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_governance_queue_audit_status_contract'
  status = 'passed_static_only'
  issueId = [string]$fixture.issueId
  activeIssueId = [string]$fixture.activeIssueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = $fixture.baseline
  canonicalRevision = [string]$fixture.canonicalRevision
  queueEvidencePath = $queueEvidencePath
  failureWitnessPath = $failureWitnessPath
  assertionCount = $assertions.Count
  assertions = @($assertions)
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'static_governance_queue_audit_status_contract_only;runtime_build_install_device_and_legado_diff_deferred'
  closeCondition = 'Every no-candidate queue registration writes candidateStatus=no_candidate_satisfies_evidence_gate while preserving the separate active-issue selection gate.'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 60
