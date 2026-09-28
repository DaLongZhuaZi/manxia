[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-governance-queue-audit-evidence-drift-pre-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing file: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([string]$RelativePath)
  try { return (Read-StrictText $RelativePath | ConvertFrom-Json) }
  catch { throw "Invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Get-Text {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return '' }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return '' }
  return [string]$property.Value
}

function Add-WitnessAssertion {
  param([System.Collections.Generic.List[object]]$Assertions, [string]$Id, [bool]$Passed, [string]$Detail)
  [void]$Assertions.Add([pscustomobject][ordered]@{ id = $Id; passed = $Passed; detail = $Detail })
  if (-not $Passed) { throw "Failure witness could not reproduce: $Id; $Detail" }
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

$fixturePath = 'tools/legado-compat/fixtures/legado-governance-queue-audit-evidence-drift.json'
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$objective = Read-StrictJson 'tools/legado-compat/state/refactor-objective.json'
$fixture = Read-StrictJson $fixturePath
$queuePath = [string]$state.governance.queuePreflight.evidencePath
$queue = Read-StrictJson $queuePath
$queueAudit = $objective.continuationTarget.queueAudit
$assertions = [System.Collections.Generic.List[object]]::new()

Add-WitnessAssertion $assertions 'fixture_issue_binding' ([string]$fixture.issueId -eq 'ISSUE-AUTO-052-GOVERNANCE-QUEUE-AUDIT-EVIDENCE-DRIFT') 'fixture is bound to ISSUE-AUTO-052'
Add-WitnessAssertion $assertions 'baseline_frozen' ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq [string]$fixture.baseline.sourcePackageSha256 -and [string]$state.baseline.legadoCommit -eq [string]$fixture.baseline.legadoCommit) 'machine baseline matches the fixture'
Add-WitnessAssertion $assertions 'revision_frozen' ([string]$objective.targetRevision -eq [string]$fixture.canonicalRevision) 'objective target revision matches the canonical fixture revision'
Add-WitnessAssertion $assertions 'queue_pointer_binding' ($queuePath -eq [string]$fixture.queueEvidencePath -and [string]$queue.targetRevision -eq [string]$fixture.canonicalRevision) 'current queue points to r10 and canonical revision'
Add-WitnessAssertion $assertions 'no_candidate_gate' ([int]$queue.candidateCount -eq 0 -and [string]$queue.candidateGateStatus -eq 'no_candidate_satisfies_evidence_gate') 'current candidate gate is the no-candidate branch'
Add-WitnessAssertion $assertions 'active_issue_binding' ([string]$state.governance.activeIssueId -eq [string]$fixture.activeIssueId -and [string]$queue.activeIssueId -eq [string]$fixture.activeIssueId) 'machine and queue active issue are 243'
Add-WitnessAssertion $assertions 'runtime_locked' (@($queue.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$queue.semanticMatchAllowed) 'witness remains static-only'

$observed = [ordered]@{}
foreach ($field in @($fixture.staleFields)) {
  $value = Get-Text $queueAudit $field
  $observed[$field] = $value
  $expected = Get-Text $fixture.observedBeforeFix $field
  Add-WitnessAssertion $assertions ("stale_field_{0}" -f $field) ($value -eq $expected -and $value.Length -gt 0) ("queueAudit.$field=$value")
}
$historicalProjection = $queueAudit.PSObject.Properties['historicalQueueEvidenceProjection']
Add-WitnessAssertion $assertions 'historical_projection_absent_before_fix' ($null -eq $historicalProjection) 'the stale evidence has no explicit historical projection before the fix'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_governance_queue_audit_evidence_drift_failure_witness'
  status = 'failed'
  issueId = [string]$fixture.issueId
  taskId = [string]$fixture.taskId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = [string]$fixture.baseline.sourcePackageSha256; legadoCommit = [string]$fixture.baseline.legadoCommit }
  activeIssueId = [string]$fixture.activeIssueId
  queueEvidencePath = $queuePath
  observedStaleFields = $observed
  failureClass = 'governance_queue_audit_evidence_drift'
  primaryCause = 'The no-candidate queue branch updated the pointer and gate status but left candidate evidence fields from earlier issue registrations, so historical failure and source-fix paths could be consumed as current queue evidence.'
  assertionCount = $assertions.Count
  assertions = @($assertions)
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'static_governance_failure_witness_only;runtime_build_install_device_and_legado_diff_deferred'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 60
