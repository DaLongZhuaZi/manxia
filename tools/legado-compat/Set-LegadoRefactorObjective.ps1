[CmdletBinding()]
param(
  [string]$StatePath = '',
  [string]$ObjectivePath = '',
  [string]$ActiveIssueId = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($StatePath.Length -eq 0) {
  $StatePath = Join-Path $PSScriptRoot 'state\full-source-validation-state.json'
}
if ($ObjectivePath.Length -eq 0) {
  $ObjectivePath = Join-Path $PSScriptRoot 'state\refactor-objective.json'
}

$modulePath = Join-Path $PSScriptRoot 'LegadoFullSourceState.psm1'
Import-Module -Name $modulePath -Force
$state = Read-LegadoJsonFile -Path $StatePath
$objective = Read-LegadoJsonFile -Path $ObjectivePath
if ($null -eq $state -or $null -eq $objective) {
  throw 'State or refactor objective is missing or invalid.'
}

$baseline = $state.baseline
$objectiveBaseline = $objective.baseline
if ([string]$baseline.sourcePackageSha256 -ne [string]$objectiveBaseline.sourcePackageSha256 -or
    [int]$baseline.sourceCount -ne [int]$objectiveBaseline.sourceCount -or
    [string]$baseline.legadoCommit -ne [string]$objectiveBaseline.legadoCommit) {
  throw 'Refactor objective baseline does not match the canonical machine state.'
}

$governance = $state.governance
$governance | Add-Member -NotePropertyName 'refactorObjective' -NotePropertyValue $objective -Force
$governance | Add-Member -NotePropertyName 'refactorObjectivePath' -NotePropertyValue 'tools/legado-compat/state/refactor-objective.json' -Force
if ($ActiveIssueId.Length -gt 0) {
  $governance | Add-Member -NotePropertyName 'activeIssueId' -NotePropertyValue $ActiveIssueId -Force
}

Write-LegadoStateCheckpoint -Path $StatePath -State $state -Depth 40
Write-Output ('REFACTOR_OBJECTIVE_ATTACHED objectiveId={0} state={1}' -f $objective.objectiveId, $StatePath)
