[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-governance-queue-audit-evidence-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-AUTO-052-GOVERNANCE-QUEUE-AUDIT-EVIDENCE-DRIFT'
$activeIssueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$revision = '2026-08-10-actual-docs-source-refactor-jsoup-combination-r4-readiness-static-closure'
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$fixturePath = 'tools/legado-compat/fixtures/legado-governance-queue-audit-evidence-drift.json'
$failureWitnessPath = 'tools/legado-compat/evidence/contract-legado-governance-queue-audit-evidence-drift-pre-fix-20260810.json'

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

function Add-ContractAssertion {
  param([System.Collections.Generic.List[object]]$Assertions, [string]$Id, [bool]$Passed, [string]$Detail)
  [void]$Assertions.Add([pscustomobject][ordered]@{ id = $Id; status = $(if ($Passed) { 'passed' } else { 'failed' }); detail = $Detail })
  if (-not $Passed) { throw "Queue audit evidence contract failed: $Id; $Detail" }
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
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$objective = Read-StrictJson 'tools/legado-compat/state/refactor-objective.json'
$queueEvidencePath = [string]$state.governance.queuePreflight.evidencePath
$queue = Read-StrictJson $queueEvidencePath
$queueAudit = $objective.continuationTarget.queueAudit
$assertions = [System.Collections.Generic.List[object]]::new()
$queueFields = @($fixture.staleFields) + @('candidateTargetEvidencePath', 'candidateFailureWitnessPath', 'candidateCurrentHeadAuditEvidencePath')

Add-ContractAssertion $assertions 'fixture_binding' ([string]$fixture.issueId -eq $issueId -and [string]$fixture.activeIssueId -eq $activeIssueId) 'fixture is bound to ISSUE-AUTO-052 and active issue 243'
Add-ContractAssertion $assertions 'baseline_binding' ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline remains frozen'
Add-ContractAssertion $assertions 'revision_binding' ([string]$objective.targetRevision -eq $revision -and [string]$queue.targetRevision -eq $revision) 'objective and current machine queue use the canonical revision'
Add-ContractAssertion $assertions 'queue_pointer_binding' ($queueEvidencePath.Length -gt 0 -and (Test-Path -LiteralPath (Get-RepoPath $queueEvidencePath) -PathType Leaf)) 'machine pointer resolves to an existing current queue evidence file'
Add-ContractAssertion $assertions 'no_candidate_gate' ([int]$queue.candidateCount -eq 0 -and [string]$queue.candidateGateStatus -eq 'no_candidate_satisfies_evidence_gate' -and [int]$queue.evaluatedCount -eq 229) 'no-candidate gate remains 229/0'
Add-ContractAssertion $assertions 'active_issue_binding' ([string]$state.governance.activeIssueId -eq $activeIssueId -and [string]$queue.activeIssueId -eq $activeIssueId) 'machine and queue remain bound to 243'
Add-ContractAssertion $assertions 'runtime_locked' (@($queue.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$queue.semanticMatchAllowed -and @($state.governance.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$state.governance.semanticMatchAllowed) 'no runtime action or semantic match is enabled'

$historicalProjection = $queueAudit.PSObject.Properties['historicalQueueEvidenceProjection']
Add-ContractAssertion $assertions 'historical_projection_present' ($null -ne $historicalProjection) 'old paths have an explicit historical projection'
$historicalFields = if ($null -eq $historicalProjection) { $null } else { $historicalProjection.Value.fields }
foreach ($field in @($fixture.staleFields)) {
  $currentValue = Get-Text $queueAudit $field
  $historicalValue = Get-Text $historicalFields $field
  $expectedValue = Get-Text $fixture.observedBeforeFix $field
  Add-ContractAssertion $assertions ("current_field_empty_{0}" -f $field) ($currentValue.Length -eq 0) ("queueAudit.$field is empty")
  Add-ContractAssertion $assertions ("historical_field_retained_{0}" -f $field) ($historicalValue -eq $expectedValue -and $historicalValue.Length -gt 0) ("historical projection retains $field")
}
foreach ($field in @('candidateTargetEvidencePath', 'candidateFailureWitnessPath', 'candidateCurrentHeadAuditEvidencePath')) {
  Add-ContractAssertion $assertions ("candidate_field_empty_{0}" -f $field) ((Get-Text $queueAudit $field).Length -eq 0) ("queueAudit.$field is empty")
}
Add-ContractAssertion $assertions 'prior_issue_history_preserved' ((Get-Text $queueAudit 'priorActiveIssueId') -eq 'ISSUE-COMPAT-242-TRACE-BRIDGE-PRESERVATION') 'prior active issue remains explicit provenance, not current evidence'
Add-ContractAssertion $assertions 'failure_witness_retained' (Test-Path -LiteralPath (Get-RepoPath $failureWitnessPath) -PathType Leaf) 'pre-fix witness remains available'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_governance_queue_audit_evidence_contract'
  status = 'passed_static_only'
  issueId = $issueId
  activeIssueId = $activeIssueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  targetRevision = $revision
  queueEvidencePath = $queueEvidencePath
  failureWitnessPath = $failureWitnessPath
  assertionCount = $assertions.Count
  assertions = @($assertions)
  historicalProjectionFields = @($fixture.staleFields)
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'static_governance_queue_audit_contract_only;runtime_build_install_device_and_legado_diff_deferred'
  closeCondition = 'No-candidate queue branches keep all current candidate evidence fields empty, retain old paths only under an explicit historical projection, and remain synchronized with the machine queue pointer.'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 60
