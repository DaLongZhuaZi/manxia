[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-governance-queue-selection-anchor-20260809.json'
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
$assertions = 0

function Get-RepoPath([string]$RelativePath) { return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictJson([string]$RelativePath) {
  $path = Get-RepoPath $RelativePath
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes) | ConvertFrom-Json
}
function Assert-Contract([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "Governance queue-selection anchor contract failed: $Message" }
  $script:assertions++
}
function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 40), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$fixture = Read-StrictJson 'tools/legado-compat/fixtures/legado-governance-queue-selection-anchor-drift.json'
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$objective = Read-StrictJson 'tools/legado-compat/state/refactor-objective.json'
Assert-Contract ([int]$state.baseline.sourceCount -eq $sourceCount) 'machine source count drifted'
Assert-Contract ([string]$state.baseline.sourcePackageSha256 -eq $sourceHash) 'machine source hash drifted'
Assert-Contract ([string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine Legado commit drifted'
Assert-Contract ([int]$objective.baseline.sourceCount -eq $sourceCount) 'objective source count drifted'
Assert-Contract ([string]$objective.baseline.sourcePackageSha256 -eq $sourceHash) 'objective source hash drifted'
Assert-Contract ([string]$objective.baseline.legadoCommit -eq $legadoCommit) 'objective Legado commit drifted'
$activeIssueId = [string]$state.governance.activeIssueId
$activeIssue = @($state.governance.issues | Where-Object { [string]$_.id -eq $activeIssueId }) | Select-Object -First 1
Assert-Contract ($activeIssueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS') 'unexpected active issue'
Assert-Contract ([string]$activeIssue.status -eq 'verifying') 'active issue must remain verifying'
$selectionGate = $objective.objective.queueSelectionGate
$queueAudit = $objective.continuationTarget.queueAudit
Assert-Contract ([string]$objective.authority.activeIssueId -eq $activeIssueId) 'objective authority drifted'
Assert-Contract ([string]$selectionGate.currentAnchor -eq $activeIssueId) 'queueSelectionGate currentAnchor drifted'
Assert-Contract ([string]$selectionGate.selectedIssue -eq $activeIssueId) 'queueSelectionGate selectedIssue drifted'
Assert-Contract (@($selectionGate.candidateIssues).Count -eq 0) 'queueSelectionGate must have no candidate'
Assert-Contract ([string]$selectionGate.candidateGateStatus -eq 'source_fix_static_closed_wait_r4') 'queueSelectionGate status drifted'
Assert-Contract ([string]$queueAudit.currentAnchor -eq $activeIssueId) 'queueAudit currentAnchor drifted'
Assert-Contract ([string]$queueAudit.selectedIssue -eq $activeIssueId) 'queueAudit selectedIssue drifted'
Assert-Contract ([string]$queueAudit.activeIssueId -eq $activeIssueId) 'queueAudit activeIssueId drifted'
Assert-Contract (@($queueAudit.candidateIssues).Count -eq 0) 'queueAudit must have no candidate'
Assert-Contract ([string]$queueAudit.status -eq 'preflight_passed_no_candidate' -and [string]$queueAudit.candidateGateStatus -eq 'no_candidate_satisfies_evidence_gate') 'queueAudit status drifted'
Assert-Contract ([string]$selectionGate.selectionRule -match 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS') 'selection rule must name the active issue'
Assert-Contract (-not ([string]$selectionGate.selectionRule).Contains('ISSUE-COMPAT-009')) 'selection rule must not use the stale issue'
Assert-Contract ([string]$fixture.expectedRule -match 'currentAnchor') 'fixture must state the anchor invariant'
$result = [ordered]@{
  schemaVersion = 1
  kind = 'legado_governance_queue_selection_anchor_contract'
  status = 'passed_static_only'
  issueId = [string]$fixture.issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  activeIssueId = $activeIssueId
  assertionCount = $assertions
  historicalProjectionPreserved = $null -ne $objective.historicalQueueSelectionProjection
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'static_document_contract_only;runtime_build_install_device_and_legado_diff_deferred'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 30
