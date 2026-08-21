[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [Parameter(Mandatory = $true)]
  [string]$EvidenceDirectory,
  [Parameter(Mandatory = $true)]
  [int]$Ordinal,
  [string]$RunId = '',
  [string]$Reason = 'user_requested_manual_repair_phase'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$activityPath = Join-Path $EvidenceDirectory 'run-activity.json'
$now = [DateTimeOffset]::UtcNow.ToString('o')
$modulePath = Join-Path $PSScriptRoot 'LegadoFullSourceState.psm1'
Import-Module -Name $modulePath -Force

if (-not (Test-Path -LiteralPath $statePath)) {
  throw "INTERRUPTED_RUN_STATE_MISSING:$statePath"
}
if (-not (Test-Path -LiteralPath $EvidenceDirectory)) {
  throw "INTERRUPTED_RUN_EVIDENCE_MISSING:$EvidenceDirectory"
}

$state = Read-LegadoJsonFile -Path $statePath
$record = @($state.sources | Where-Object { [int]$_.ordinal -eq $Ordinal })[0]
if ($null -eq $record) {
  throw "INTERRUPTED_RUN_SOURCE_NOT_FOUND:$Ordinal"
}
if ([string]$record.status -ne 'running') {
  throw "INTERRUPTED_RUN_SOURCE_NOT_RUNNING:$([string]$record.status)"
}

$record.status = 'blocked'
$record.lastOutcome = 'harness_interrupted_before_terminal'
$record.validationProfile = 'manual_repair_pause'
$record.semanticQualification = 'unverified'
$record.lastUpdatedAt = $now
$record | Add-Member -NotePropertyName lastInterruption -NotePropertyValue ([pscustomobject][ordered]@{
  reason = $Reason
  runEvidenceDirectory = [System.IO.Path]::GetRelativePath($RepositoryRoot, $EvidenceDirectory).Replace('\', '/')
  interruptedAt = $now
  ordinal = $Ordinal
}) -Force

foreach ($property in @($record.workflows.PSObject.Properties)) {
  $workflow = $property.Value
  if ([string]$workflow.status -ne 'running') { continue }
  $workflow.status = 'blocked'
  $workflow.lastOutcome = 'harness_interrupted_before_terminal'
  $workflow.lastEvidenceDigest = ''
  $workflow.lastUpdatedAt = $now
}

$matchingIssues = @($state.governance.issues | Where-Object { [string]$_.id -eq 'V2-HARNESS-029-CURRENT-RUN-INTERRUPTION' })
$existingIssue = if ($matchingIssues.Count -gt 0) { $matchingIssues[0] } else { $null }
$issue = [pscustomobject][ordered]@{
  id = 'V2-HARNESS-029-CURRENT-RUN-INTERRUPTION'
  taskId = 'COMPAT-006'
  status = 'blocked'
  severity = 'P2'
  attempts = if ($null -eq $existingIssue) { 1 } else { [int]$existingIssue.attempts + 1 }
  summary = "当前 full_workflow 批次在 ordinal $Ordinal 被停止；运行中的工作流已结算为 blocked，不能作为兼容通过或语义差分证据。"
  evidencePaths = @(
    ([System.IO.Path]::GetRelativePath($RepositoryRoot, $activityPath).Replace('\', '/')),
    ([System.IO.Path]::GetRelativePath($RepositoryRoot, $statePath).Replace('\', '/'))
  )
  closeCondition = '启动具有新 runId 的修复后批次；中断批次保持不可变并从语义结论中排除。'
  lastUpdatedAt = $now
}
$issues = New-Object 'System.Collections.Generic.List[object]'
foreach ($candidate in @($state.governance.issues)) {
  if ([string]$candidate.id -eq $issue.id) {
    [void]$issues.Add($issue)
  } else {
    [void]$issues.Add($candidate)
  }
}
if ($null -eq $existingIssue) { [void]$issues.Add($issue) }
$state.governance.issues = $issues.ToArray()

if ([string]::IsNullOrWhiteSpace($RunId)) {
  if ($null -ne $activityPath -and (Test-Path -LiteralPath $activityPath)) {
    $oldActivity = Get-Content -LiteralPath $activityPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $RunId = [string]$oldActivity.runId
  }
}
if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = "v2-hypium-full-interrupted-$Ordinal" }
$activity = [pscustomobject][ordered]@{
  schemaVersion = 1
  generatedAt = $now
  runId = $RunId
  status = 'blocked'
  phase = 'interrupted_before_terminal_manual_repair'
  executionProfile = 'full_workflow'
  ordinal = $Ordinal
  sourceId = [string]$record.sourceId
  scheduledSources = [int]$state.baseline.sourceCount
  completedSources = [Math]::Max(0, $Ordinal - 1)
  outcome = 'harness_interrupted_before_terminal'
  errorDigest = 'USER_REQUESTED_MANUAL_REPAIR_PHASE'
  evidencePath = [System.IO.Path]::GetRelativePath($RepositoryRoot, $activityPath).Replace('\', '/')
}

function Write-Utf8Atomic {
  param([string]$Path, [string]$Content)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
  $temporaryPath = "$Path.tmp.$PID.$([Guid]::NewGuid().ToString('N'))"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, $Content, [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::Move($temporaryPath, $Path, $true)
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

Sync-LegadoStateDerivedFields -State $state
Write-LegadoStateCheckpoint -Path $statePath -State $state -Depth 30
Write-Utf8Atomic -Path $activityPath -Content ([string]($activity | ConvertTo-Json -Depth 20))

$refreshScript = Join-Path $PSScriptRoot 'Invoke-LegadoCompatibility.ps1'
& $refreshScript -RefreshDocumentsOnly
if ($LASTEXITCODE -ne 0) { throw 'INTERRUPTED_RUN_DOCUMENT_REFRESH_FAILED' }

[pscustomobject]@{
  status = 'recorded'
  ordinal = $Ordinal
  sourceId = [string]$record.sourceId
  runId = $RunId
  interruptedAt = $now
} | ConvertTo-Json -Compress
