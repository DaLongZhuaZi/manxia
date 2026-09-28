[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-governance-target-revision-source-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-AUTO-051-GOVERNANCE-TARGET-REVISION-DRIFT'
$taskId = 'COMPAT-006'
$revision = '2026-08-10-actual-docs-source-refactor-jsoup-combination-r4-readiness-static-closure'
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$failureWitnessPath = 'tools/legado-compat/evidence/contract-legado-governance-target-revision-drift-pre-fix-20260810.json'
$contractPath = 'tools/legado-compat/evidence/contract-legado-governance-target-revision-20260810.json'
$fixturePath = 'tools/legado-compat/fixtures/legado-governance-target-revision-drift.json'
$historicalPaths = @(
  'tools/legado-compat/evidence/r3-source-queue-preflight-20260810-r8/current-static-candidate-preflight.json',
  'tools/legado-compat/evidence/r3-source-queue-preflight-20260810-r9/current-static-candidate-preflight.json'
)

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
  try { return (Read-StrictText -RelativePath $RelativePath | ConvertFrom-Json) }
  catch { throw "Invalid JSON: $RelativePath; $($_.Exception.Message)" }
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

function Assert-Fix {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Governance source-fix registration failed: $Message" }
}

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$queueEvidencePath = [string]$state.governance.queuePreflight.evidencePath
$objective = Read-StrictJson 'tools/legado-compat/state/refactor-objective.json'
$fixture = Read-StrictJson $fixturePath
$failureWitness = Read-StrictJson $failureWitnessPath
$contract = Read-StrictJson $contractPath
$queue = Read-StrictJson $queueEvidencePath
$document = Read-StrictText 'docs/analysis/Legado书源V2源码重构持续目标.md'

Assert-Fix ([string]$fixture.issueId -eq $issueId) 'fixture issue id is not ISSUE-AUTO-051.'
Assert-Fix ([string]$fixture.canonicalRevision -eq $revision) 'fixture canonical revision drifted.'
Assert-Fix ([string]$objective.targetRevision -eq $revision) 'objective target revision drifted.'
Assert-Fix ([string]$queue.targetRevision -eq $revision -and [string]$state.governance.queuePreflight.evidencePath -eq $queueEvidencePath) 'current machine queue evidence pointer is not addressable.'
Assert-Fix ([string]$contract.status -eq 'passed' -and [int]$contract.assertionCount -eq [int]$contract.passedAssertionCount -and -not [bool]$contract.semanticMatchAllowed) 'post-fix contract is incomplete or claims semantic match.'
Assert-Fix ([string]$failureWitness.status -eq 'failed' -and [string]$failureWitness.failureClass -eq 'governance_target_revision_drift') 'pre-fix drift witness is missing.'
Assert-Fix ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline drifted.'
Assert-Fix ([int]$queue.evaluatedCount -eq 229 -and [int]$queue.candidateCount -eq 0 -and [string]$queue.candidateGateStatus -eq 'no_candidate_satisfies_evidence_gate') 'current candidate gate changed.'
Assert-Fix (@($queue.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$queue.semanticMatchAllowed) 'current queue is not static-only.'
Assert-Fix ($document -match ('(?m)^当前修订：' + [regex]::Escape($revision) + '\s*$')) 'current investigation document revision is not canonical.'
foreach ($historicalPath in @('tools/legado-compat/evidence/r3-source-queue-preflight-20260810-r8/current-static-candidate-preflight.json', 'tools/legado-compat/evidence/r3-source-queue-preflight-20260810-r9/current-static-candidate-preflight.json')) {
  Assert-Fix (Test-Path -LiteralPath (Get-RepoPath $historicalPath) -PathType Leaf) "historical evidence is missing: $historicalPath"
}

$changedFiles = @(
  'tools/legado-compat/state/full-source-validation-state.json',
  'tools/legado-compat/state/refactor-objective.json',
  'docs/analysis/Legado书源V2源码重构持续目标.md',
  'tools/legado-compat/Test-LegadoGovernanceTargetRevisionContract.ps1',
  'tools/legado-compat/fixtures/legado-governance-target-revision-drift.json',
  $queueEvidencePath
)
$fileRecords = @()
foreach ($relativePath in $changedFiles) {
  $path = Get-RepoPath $relativePath
  Assert-Fix (Test-Path -LiteralPath $path -PathType Leaf) "changed file is missing: $relativePath"
  $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
  $fileRecords += [pscustomobject][ordered]@{ path = $relativePath; sha256 = $hash; byteLength = [System.IO.File]::ReadAllBytes($path).Length }
}
$manifest = ($fileRecords | ForEach-Object { '{0}:{1}:{2}' -f $_.path, $_.sha256, $_.byteLength }) -join "`n"
$manifestBytes = [System.Text.Encoding]::UTF8.GetBytes($manifest)
$manifestHash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($manifestBytes)
$manifestSha256 = ([System.BitConverter]::ToString($manifestHash)).Replace('-', '').ToUpperInvariant()

$sourceFixEvidence = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_governance_target_revision_source_fix'
  status = 'passed_static_only'
  issueId = $issueId
  taskId = $taskId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  targetRevision = $revision
  failureWitnessPath = $failureWitnessPath
  contractEvidencePath = $contractPath
  currentQueueEvidencePath = $queueEvidencePath
  historicalEvidencePaths = $historicalPaths
  fixturePath = $fixturePath
  changedFiles = $fileRecords
  changedFilesManifestSha256 = $manifestSha256
  primaryCause = 'Governance metadata was updated by successive static registrations without one canonical targetRevision shared by the objective, investigation document and current queue evidence; the queue could therefore not be proven to describe the same source-closure state.'
  repair = 'Rebased objective.targetRevision, the investigation document current-revision marker and the machine queue pointer/evidence to one canonical revision; retained r8/r9 as historical evidence and added a 21-assertion post-fix contract.'
  activeIssueIdAfterFix = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'static_governance_source_fix_only;runtime_build_install_device_and_legado_diff_deferred'
  closeCondition = 'Target revision contract, r10 queue evidence, machine state, source-fix evidence and derived documents remain atomically aligned; this governance fix does not establish book-source semantic compatibility.'
}
Write-AtomicJson -RelativePath $SourceFixPath -Value $sourceFixEvidence

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$summary = '治理修复 ISSUE-AUTO-051：统一 objective、调查文档和当前 r10 队列证据的 targetRevision；r8/r9 降为历史证据。21 项 post-fix 契约通过，保持静态策略、243 verifying、semanticMatchAllowed=false。'
$closeCondition = '目标修订号契约 21 项断言、失败见证、源修复证据、r10 队列证据、机器状态和派生文档持续一致；R4 运行时、构建、设备与 Legado 差分仍是独立关闭条件。'
$evidencePaths = @($fixturePath, $failureWitnessPath, $contractPath, $SourceFixPath, $queueEvidencePath, 'tools/legado-compat/Register-LegadoCurrentStaticSourceCandidateGate.ps1', 'tools/legado-compat/Test-LegadoGovernanceTargetRevisionContract.ps1', 'tools/legado-compat/Register-LegadoGovernanceTargetRevisionSourceFix.ps1')
$evidenceArgument = $evidencePaths -join ','
& pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript -StatePath (Get-RepoPath 'tools/legado-compat/state/full-source-validation-state.json') -IssueId $issueId -IssueStatus passed -TaskId $taskId -TaskStatus running -Severity P1 -Summary $summary -CloseCondition $closeCondition -EvidencePath $evidenceArgument -CreateIfMissing | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Governance state update failed.' }

[pscustomobject][ordered]@{ status = 'registered'; issueId = $issueId; targetRevision = $revision; sourceFixEvidencePath = $SourceFixPath; evidenceCount = $evidencePaths.Count; changedFilesManifestSha256 = $manifestSha256; runtimeActionsPerformed = @(); semanticMatchAllowed = $false } | ConvertTo-Json -Depth 30
