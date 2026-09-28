[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-governance-target-revision-drift-pre-fix-20260810.json'
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
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing text: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  try { return (Read-StrictText -RelativePath $RelativePath | ConvertFrom-Json) }
  catch { throw "Invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Write-AtomicJson {
  param(
    [Parameter(Mandatory = $true)][string]$RelativePath,
    [Parameter(Mandatory = $true)][object]$Value
  )
  $path = Get-RepoPath -RelativePath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 40), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Assert-Witness {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Target revision drift witness failed to reproduce: $Message" }
}

$fixture = Read-StrictJson -RelativePath 'tools/legado-compat/fixtures/legado-governance-target-revision-drift.json'
$state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$objective = Read-StrictJson -RelativePath 'tools/legado-compat/state/refactor-objective.json'
$document = Read-StrictText -RelativePath 'docs/analysis/Legado书源V2源码重构持续目标.md'
$queueEvidencePath = [string]$state.governance.queuePreflight.evidencePath
$queueEvidence = Read-StrictJson -RelativePath $queueEvidencePath
$revisionMatch = [regex]::Match($document, '(?m)^当前修订：(?<revision>\S+)')
Assert-Witness $revisionMatch.Success 'current document revision marker is missing.'

$stateBaseline = $state.baseline
$objectiveBaseline = $objective.baseline
$fixtureBaseline = $fixture.baseline
Assert-Witness ([int]$stateBaseline.sourceCount -eq [int]$fixtureBaseline.sourceCount) 'machine source count drifted.'
Assert-Witness ([string]$stateBaseline.sourcePackageSha256 -eq [string]$fixtureBaseline.sourcePackageSha256) 'machine source hash drifted.'
Assert-Witness ([string]$stateBaseline.legadoCommit -eq [string]$fixtureBaseline.legadoCommit) 'machine Legado commit drifted.'
Assert-Witness ([int]$objectiveBaseline.sourceCount -eq [int]$fixtureBaseline.sourceCount) 'objective source count drifted.'
Assert-Witness ([string]$objectiveBaseline.sourcePackageSha256 -eq [string]$fixtureBaseline.sourcePackageSha256) 'objective source hash drifted.'
Assert-Witness ([string]$objectiveBaseline.legadoCommit -eq [string]$fixtureBaseline.legadoCommit) 'objective Legado commit drifted.'
Assert-Witness ([string]$state.governance.activeIssueId -eq [string]$fixture.activeIssueId) 'active issue drifted.'
Assert-Witness ([string]$objective.authority.activeIssueId -eq [string]$fixture.activeIssueId) 'objective active issue drifted.'

$objectiveRevision = [string]$objective.targetRevision
$documentRevision = [string]$revisionMatch.Groups['revision'].Value
$queueRevision = [string]$queueEvidence.targetRevision
$r9 = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/r3-source-queue-preflight-20260810-r9/current-static-candidate-preflight.json'
$r9Revision = [string]$r9.targetRevision
Assert-Witness ($objectiveRevision -eq [string]$fixture.observedBeforeFix.objectiveTargetRevision) 'objective revision no longer matches the frozen failure witness.'
Assert-Witness ($documentRevision -eq [string]$fixture.observedBeforeFix.documentCurrentRevision) 'document revision no longer matches the frozen failure witness.'
Assert-Witness ($queueRevision -eq [string]$fixture.observedBeforeFix.queueEvidenceRevisions.r8) 'registered queue evidence revision no longer matches the frozen failure witness.'
Assert-Witness ($r9Revision -eq [string]$fixture.observedBeforeFix.queueEvidenceRevisions.r9) 'newer unregistered queue evidence revision no longer matches the frozen failure witness.'
Assert-Witness ($objectiveRevision -ne $documentRevision) 'objective and document revisions unexpectedly agree.'
Assert-Witness ($objectiveRevision -ne $queueRevision) 'objective and registered queue evidence revisions unexpectedly agree.'
Assert-Witness ($documentRevision -ne $queueRevision) 'document and registered queue evidence revisions unexpectedly agree.'
Assert-Witness ($r9Revision -ne $objectiveRevision) 'newer queue evidence unexpectedly agrees with objective.'

$result = [ordered]@{
  schemaVersion = 1
  kind = 'legado_governance_target_revision_drift_failure_witness'
  status = 'failed'
  issueId = [string]$fixture.issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{
    sourceCount = [int]$fixtureBaseline.sourceCount
    sourcePackageSha256 = [string]$fixtureBaseline.sourcePackageSha256
    legadoCommit = [string]$fixtureBaseline.legadoCommit
  }
  activeIssueId = [string]$fixture.activeIssueId
  registeredQueueEvidencePath = $queueEvidencePath
  observedRevisions = [ordered]@{
    objective = $objectiveRevision
    document = $documentRevision
    registeredQueueEvidence = $queueRevision
    newerUnregisteredQueueEvidence = $r9Revision
  }
  failureClass = 'governance_target_revision_drift'
  primaryCause = 'objective, document and queue evidence used different static targetRevision identifiers, so current evidence could not be proven to describe the same source-closure state.'
  assertionCount = 18
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'static_governance_failure_witness_only;runtime_build_install_device_and_legado_diff_deferred'
}
Write-AtomicJson -RelativePath $OutputPath -Value $result
$result | ConvertTo-Json -Depth 30
