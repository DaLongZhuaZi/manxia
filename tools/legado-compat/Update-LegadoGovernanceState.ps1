[CmdletBinding()]
param(
  [string]$StatePath = '',
  [Parameter(Mandatory = $true)]
  [string]$IssueId,
  [ValidateSet('planned', 'running', 'in_progress', 'verifying', 'passed', 'failed', 'expected_external', 'needs_interaction', 'policy_blocked', 'blocked')]
  [string]$IssueStatus = 'running',
  [string]$TaskId = '',
  [ValidateSet('', 'planned', 'running', 'in_progress', 'verifying', 'passed', 'failed', 'expected_external', 'needs_interaction', 'policy_blocked', 'blocked')]
  [string]$TaskStatus = '',
  [ValidateSet('', 'P0', 'P1', 'P2', 'P3')]
  [string]$Severity = '',
  [string]$Summary = '',
  [string]$CloseCondition = '',
  [string[]]$EvidencePath = @(),
  [int]$SourceOrdinal = -1,
  [string]$SourceId = '',
  [switch]$AppendSourceIssue,
  [switch]$CreateIfMissing,
  [switch]$CreateTaskIfMissing,
  [switch]$IncrementAttempt
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PropertyValue {
  param(
    [object]$Object,
    [string]$Name
  )
  if ($null -eq $Object) {
    return $null
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }
  return $property.Value
}

function Get-FirstMatch {
  param(
    [object[]]$Items,
    [string]$Id
  )
  foreach ($item in $Items) {
    if ([string](Get-PropertyValue -Object $item -Name 'id') -eq $Id) {
      return $item
    }
  }
  return $null
}

if ($StatePath.Length -eq 0) {
  $StatePath = Join-Path $PSScriptRoot 'state\full-source-validation-state.json'
}
$modulePath = Join-Path $PSScriptRoot 'LegadoFullSourceState.psm1'
Import-Module -Name $modulePath -Force

if (-not (Test-Path -LiteralPath $StatePath)) {
  throw "Machine fact state is missing: $StatePath"
}
$state = Read-LegadoJsonFile -Path $StatePath
if ($null -eq $state) {
  throw "Machine fact state cannot be parsed: $StatePath"
}
$governance = Get-PropertyValue -Object $state -Name 'governance'
if ($null -eq $governance) {
  throw 'Machine fact state has no governance section.'
}
$issues = @((Get-PropertyValue -Object $governance -Name 'issues'))
$tasks = @((Get-PropertyValue -Object $governance -Name 'tasks'))
$issue = Get-FirstMatch -Items $issues -Id $IssueId
if ($null -eq $issue) {
  if (-not $CreateIfMissing) {
    throw "Governance issue does not exist: $IssueId"
  }
  if ($TaskId.Length -eq 0) {
    throw 'TaskId is required when creating a governance issue.'
  }
  $issue = [pscustomobject][ordered]@{
    id = $IssueId
    taskId = $TaskId
    status = $IssueStatus
    severity = if ($Severity.Length -gt 0) { $Severity } else { 'P1' }
    attempts = 0
  }
  $issues = @($issues) + @($issue)
  $governance | Add-Member -NotePropertyName 'issues' -NotePropertyValue $issues -Force
}

$effectiveTaskId = $TaskId
if ($effectiveTaskId.Length -eq 0) {
  $effectiveTaskId = [string](Get-PropertyValue -Object $issue -Name 'taskId')
}
if ($effectiveTaskId.Length -gt 0) {
  $issue | Add-Member -NotePropertyName 'taskId' -NotePropertyValue $effectiveTaskId -Force
}
$issue | Add-Member -NotePropertyName 'status' -NotePropertyValue $IssueStatus -Force
if ($Severity.Length -gt 0) {
  $issue | Add-Member -NotePropertyName 'severity' -NotePropertyValue $Severity -Force
}
if ($IncrementAttempt) {
  $attempts = [int](Get-PropertyValue -Object $issue -Name 'attempts')
  $issue | Add-Member -NotePropertyName 'attempts' -NotePropertyValue ($attempts + 1) -Force
}
if ($Summary.Length -gt 0) {
  $issue | Add-Member -NotePropertyName 'summary' -NotePropertyValue $Summary -Force
}
if ($CloseCondition.Length -gt 0) {
  $issue | Add-Member -NotePropertyName 'closeCondition' -NotePropertyValue $CloseCondition -Force
}
if ($EvidencePath.Count -gt 0) {
  $normalizedEvidence = New-Object 'System.Collections.Generic.List[string]'
  $rawEvidenceValues = New-Object 'System.Collections.Generic.List[string]'
  $existingEvidenceProperty = $issue.PSObject.Properties['evidencePaths']
  if ($null -ne $existingEvidenceProperty -and $null -ne $existingEvidenceProperty.Value) {
    foreach ($existingEvidence in @($existingEvidenceProperty.Value)) {
      [void]$rawEvidenceValues.Add([string]$existingEvidence)
    }
  }
  foreach ($rawEvidence in $EvidencePath) {
    [void]$rawEvidenceValues.Add([string]$rawEvidence)
  }
  foreach ($rawEvidence in $rawEvidenceValues.ToArray()) {
    # PowerShell's -File invocation serializes a string[] supplied by an
    # outer automation process as one comma-delimited argument. Normalize it
    # here so the machine-fact state always contains distinct evidence paths,
    # while retaining evidence already recorded for this issue.
    foreach ($fragment in @(([string]$rawEvidence -split ','))) {
      $normalized = $fragment.Trim().Trim("'").Trim('"')
      if ($normalized.Length -gt 0 -and -not $normalizedEvidence.Contains($normalized)) {
        [void]$normalizedEvidence.Add($normalized)
      }
    }
  }
  $uniqueEvidence = @(
    $normalizedEvidence.ToArray() |
      Where-Object { $_.Length -gt 0 } |
      Select-Object -Unique
  )
  $issue | Add-Member -NotePropertyName 'evidencePaths' -NotePropertyValue $uniqueEvidence -Force
}
$issue | Add-Member -NotePropertyName 'lastUpdatedAt' -NotePropertyValue ([DateTimeOffset]::UtcNow.ToString('o')) -Force

if ($effectiveTaskId.Length -gt 0 -and $TaskStatus.Length -gt 0) {
  $task = Get-FirstMatch -Items $tasks -Id $effectiveTaskId
  if ($null -eq $task) {
    if (-not $CreateTaskIfMissing) {
      throw "Governance task does not exist: $effectiveTaskId"
    }
    $task = [pscustomobject][ordered]@{
      id = $effectiveTaskId
      status = 'planned'
      attempts = 0
    }
    $tasks = @($tasks) + @($task)
    $governance | Add-Member -NotePropertyName 'tasks' -NotePropertyValue $tasks -Force
  }
  $task | Add-Member -NotePropertyName 'status' -NotePropertyValue $TaskStatus -Force
  if ($IncrementAttempt) {
    $attempts = [int](Get-PropertyValue -Object $task -Name 'attempts')
    $task | Add-Member -NotePropertyName 'attempts' -NotePropertyValue ($attempts + 1) -Force
  }
  $task | Add-Member -NotePropertyName 'lastUpdatedAt' -NotePropertyValue ([DateTimeOffset]::UtcNow.ToString('o')) -Force
}

if ($AppendSourceIssue) {
  if ($SourceOrdinal -lt 0 -and $SourceId.Length -eq 0) {
    throw 'SourceOrdinal or SourceId is required when AppendSourceIssue is used.'
  }
  $sourceRecords = @((Get-PropertyValue -Object $state -Name 'sources'))
  $sourceRecord = $null
  foreach ($candidate in $sourceRecords) {
    $candidateId = [string](Get-PropertyValue -Object $candidate -Name 'sourceId')
    $candidateOrdinalText = [string](Get-PropertyValue -Object $candidate -Name 'ordinal')
    $ordinalMatches = $SourceOrdinal -ge 0 -and $candidateOrdinalText -eq [string]$SourceOrdinal
    $idMatches = $SourceId.Length -gt 0 -and $candidateId -eq $SourceId
    if (($SourceOrdinal -ge 0 -and $SourceId.Length -gt 0 -and $ordinalMatches -and $idMatches) -or
      ($SourceOrdinal -ge 0 -and $SourceId.Length -eq 0 -and $ordinalMatches) -or
      ($SourceOrdinal -lt 0 -and $SourceId.Length -gt 0 -and $idMatches)) {
      $sourceRecord = $candidate
      break
    }
  }
  if ($null -eq $sourceRecord) {
    throw ('Source record not found for ordinal={0}; sourceId={1}' -f $SourceOrdinal, $SourceId)
  }
  $issueIdsProperty = $sourceRecord.PSObject.Properties['issueIds']
  $existingIssueIds = if ($null -eq $issueIdsProperty -or $null -eq $issueIdsProperty.Value) {
    @()
  } else {
    @($issueIdsProperty.Value | ForEach-Object { [string]$_ })
  }
  if ($existingIssueIds -notcontains $IssueId) {
    $sourceRecord | Add-Member -NotePropertyName 'issueIds' -NotePropertyValue (@($existingIssueIds) + @($IssueId)) -Force
  }
}

$activeTask = @(
  $tasks |
    Where-Object { [string](Get-PropertyValue -Object $_ -Name 'status') -in @('running', 'verifying') } |
    Select-Object -First 1
)
if ($activeTask.Count -gt 0) {
  $governance | Add-Member -NotePropertyName 'status' -NotePropertyValue 'running' -Force
  $governance | Add-Member -NotePropertyName 'activeTaskId' -NotePropertyValue ([string](Get-PropertyValue -Object $activeTask[0] -Name 'id')) -Force
} else {
  $governance | Add-Member -NotePropertyName 'status' -NotePropertyValue 'planned' -Force
  $governance | Add-Member -NotePropertyName 'activeTaskId' -NotePropertyValue '' -Force
}

Sync-LegadoStateDerivedFields -State $state
Write-LegadoStateCheckpoint -Path $StatePath -State $state -Depth 30

$compatibilityScript = Join-Path $PSScriptRoot 'Invoke-LegadoCompatibility.ps1'
if (-not (Test-Path -LiteralPath $compatibilityScript)) {
  throw 'Compatibility document refresh script is missing.'
}
& $compatibilityScript -RefreshDocumentsOnly
if ($LASTEXITCODE -ne 0) {
  throw 'Compatibility document refresh failed.'
}

Write-Output ('GOVERNANCE_STATE_UPDATED issue={0} status={1} task={2}' -f $IssueId, $IssueStatus, $effectiveTaskId)
