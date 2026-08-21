[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-governance-queue-selection-anchor-drift-pre-fix-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$sourceCount = 458
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'

function Get-RepoPath([string]$RelativePath) {
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson([string]$RelativePath) {
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing JSON: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes) | ConvertFrom-Json
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 30), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Get-Text([object]$Object, [string]$Name) {
  if ($null -eq $Object) { return '' }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return '' }
  return [string]$property.Value
}

$fixture = Read-StrictJson 'tools/legado-compat/fixtures/legado-governance-queue-selection-anchor-drift.json'
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$objective = Read-StrictJson 'tools/legado-compat/state/refactor-objective.json'
if ([int]$state.baseline.sourceCount -ne $sourceCount -or [string]$state.baseline.sourcePackageSha256 -ne $sourceHash -or [string]$state.baseline.legadoCommit -ne $legadoCommit) { throw 'Machine baseline drifted.' }
if ([int]$objective.baseline.sourceCount -ne $sourceCount -or [string]$objective.baseline.sourcePackageSha256 -ne $sourceHash -or [string]$objective.baseline.legadoCommit -ne $legadoCommit) { throw 'Objective baseline drifted.' }

$activeIssueId = [string]$state.governance.activeIssueId
$selectionGate = $objective.objective.queueSelectionGate
$queueAudit = $objective.continuationTarget.queueAudit
$observed = [ordered]@{
  activeIssueId = $activeIssueId
  activeIssueStatus = [string](@($state.governance.issues | Where-Object { [string]$_.id -eq $activeIssueId })[0].status)
  queueSelectionCurrentAnchor = (Get-Text $selectionGate 'currentAnchor')
  queueSelectionSelectedIssue = (Get-Text $selectionGate 'selectedIssue')
  queueAuditCurrentAnchor = (Get-Text $queueAudit 'currentAnchor')
  queueAuditSelectedIssue = (Get-Text $queueAudit 'selectedIssue')
  staleValue = [string]$fixture.staleValue
}
$staleFields = @(
  if ($observed.queueSelectionCurrentAnchor -ne $activeIssueId) { 'objective.objective.queueSelectionGate.currentAnchor' }
  if ($observed.queueSelectionSelectedIssue -ne $activeIssueId) { 'objective.objective.queueSelectionGate.selectedIssue' }
  if ($observed.queueAuditCurrentAnchor -ne $activeIssueId) { 'objective.continuationTarget.queueAudit.currentAnchor' }
  if ($observed.queueAuditSelectedIssue -ne $activeIssueId) { 'objective.continuationTarget.queueAudit.selectedIssue' }
)
if ($staleFields.Count -eq 0) { throw 'Expected pre-fix queue selection anchor drift is no longer present.' }
$failure = [ordered]@{
  schemaVersion = 1
  kind = 'legado_governance_queue_selection_anchor_drift_failure_witness'
  status = 'failed_static_only'
  issueId = [string]$fixture.issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  sourceOfTruth = [string]$fixture.sourceOfTruth
  objectivePath = [string]$fixture.objectivePath
  observed = $observed
  staleFields = $staleFields
  failure = 'The objective queue projections still named a historical source issue after full-source-validation-state.json selected the current issue.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  runtimeRegression = 'not_run'
  deviceRegression = 'not_run'
}
Write-AtomicJson $OutputPath $failure
$failure | ConvertTo-Json -Depth 30
