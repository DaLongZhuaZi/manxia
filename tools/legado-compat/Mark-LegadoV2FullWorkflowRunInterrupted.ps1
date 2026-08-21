[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [int]$Ordinal = 29,
  [string]$EvidenceDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
  $EvidenceDirectory = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\full-workflow-v2-hypium-device-20260807'
}

$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$activityPath = Join-Path $EvidenceDirectory 'run-activity.json'
$now = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'")
$state = Get-Content -LiteralPath $statePath -Raw -Encoding utf8 | ConvertFrom-Json
$record = @($state.sources | Where-Object { [int]$_.ordinal -eq $Ordinal })[0]
if ($null -eq $record) { throw "INTERRUPTED_RUN_SOURCE_NOT_FOUND:$Ordinal" }
if ([string]$record.status -ne 'running') { throw "INTERRUPTED_RUN_SOURCE_NOT_RUNNING:$([string]$record.status)" }

$record | Add-Member -NotePropertyName status -NotePropertyValue 'blocked' -Force
$record | Add-Member -NotePropertyName lastOutcome -NotePropertyValue 'harness_interrupted_by_user' -Force
$record | Add-Member -NotePropertyName validationProfile -NotePropertyValue 'manual_repair_pause' -Force
$record | Add-Member -NotePropertyName semanticQualification -NotePropertyValue 'unverified' -Force
$record | Add-Member -NotePropertyName lastUpdatedAt -NotePropertyValue $now -Force
$record | Add-Member -NotePropertyName lastInterruption -NotePropertyValue ([pscustomobject][ordered]@{
  reason = 'user_requested_manual_repair_phase'
  runEvidenceDirectory = [System.IO.Path]::GetRelativePath($RepositoryRoot, $EvidenceDirectory).Replace('\', '/')
  interruptedAt = $now
  ordinal = $Ordinal
}) -Force

foreach ($workflowProperty in @($record.workflows.PSObject.Properties)) {
  $workflow = $workflowProperty.Value
  if ([string]$workflow.status -ne 'running') { continue }
  $workflow | Add-Member -NotePropertyName status -NotePropertyValue 'blocked' -Force
  $workflow | Add-Member -NotePropertyName lastOutcome -NotePropertyValue 'harness_interrupted_by_user_before_terminal' -Force
  $workflow | Add-Member -NotePropertyName lastEvidenceDigest -NotePropertyValue '' -Force
  $workflow | Add-Member -NotePropertyName lastUpdatedAt -NotePropertyValue $now -Force
}

$issue = [pscustomobject][ordered]@{
  id = 'V2-HARNESS-028-MANUAL-REPAIR-PAUSE'
  taskId = 'COMPAT-006'
  status = 'blocked'
  severity = 'P3'
  attempts = 1
  summary = '2026-08-07: full_workflow batch was intentionally stopped at ordinal 29 for evidence-led joint repair. No terminal result was produced for that source; running workflows were settled as blocked/harness_interrupted_by_user_before_terminal and cannot be used as compatibility evidence.'
  evidencePaths = @(
    'tools/legado-compat/evidence/full-workflow-v2-hypium-device-20260807/run-activity.json',
    'tools/legado-compat/state/full-source-validation-state.json'
  )
  closeCondition = 'User-led post-repair validation starts a new batch with a distinct run id; the interrupted batch remains immutable and excluded from semantic conclusions.'
  lastUpdatedAt = $now
}
$issues = New-Object 'System.Collections.Generic.List[object]'
$replaced = $false
foreach ($existing in @($state.governance.issues)) {
  if ([string]$existing.id -eq $issue.id) { [void]$issues.Add($issue); $replaced = $true } else { [void]$issues.Add($existing) }
}
if (-not $replaced) { [void]$issues.Add($issue) }
$state.governance.issues = $issues.ToArray()

$activity = [pscustomobject][ordered]@{
  schemaVersion = 1
  generatedAt = $now
  runId = 'v2-hypium-full-43616-1786098190596'
  status = 'failed'
  phase = 'interrupted_by_user_manual_repair'
  executionProfile = 'full_workflow'
  ordinal = $Ordinal
  sourceId = [string]$record.sourceId
  scheduledSources = 458
  completedSources = 29
  outcome = 'harness_interrupted_by_user'
  errorDigest = 'USER_REQUESTED_MANUAL_REPAIR_PHASE'
}

function Write-Utf8JsonAtomic {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
  $temporaryPath = $Path + '.tmp-' + [Guid]::NewGuid().ToString('N')
  try {
    [System.IO.File]::WriteAllText($temporaryPath, [string]($Value | ConvertTo-Json -Depth 24), [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::Move($temporaryPath, $Path, $true)
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

Write-Utf8JsonAtomic -Path $statePath -Value $state
Write-Utf8JsonAtomic -Path $activityPath -Value $activity
[pscustomobject]@{ status = 'recorded'; ordinal = $Ordinal; sourceId = [string]$record.sourceId; interruptedAt = $now } | ConvertTo-Json -Compress
