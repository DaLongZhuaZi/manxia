[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-governance-queue-pointer-rotation-source-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-AUTO-054-GOVERNANCE-QUEUE-POINTER-ROTATION-DRIFT'
$taskId = 'COMPAT-006'
$activeIssueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$revision = '2026-08-10-actual-docs-source-refactor-jsoup-combination-r4-readiness-static-closure'
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$fixturePath = 'tools/legado-compat/fixtures/legado-governance-queue-pointer-rotation-drift.json'
$failureWitnessPath = 'tools/legado-compat/evidence/contract-legado-governance-queue-pointer-rotation-drift-pre-fix-20260810.json'
$contractPath = 'tools/legado-compat/evidence/contract-legado-governance-queue-pointer-rotation-20260810.json'
$objectiveDocumentPath = 'docs/analysis/Legado书源V2源码重构持续目标.md'

function Get-RepoPath([string]$RelativePath) {
  if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $RelativePath }
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText([string]$RelativePath) {
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing file: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson([string]$RelativePath) {
  return Read-StrictText $RelativePath | ConvertFrom-Json -Depth 100
}

function Assert-Fix([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "Governance pointer source-fix registration failed: $Message" }
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 80), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Write-AtomicText([string]$RelativePath, [string]$Value) {
  $path = Get-RepoPath $RelativePath
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, $Value, $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Replace-MarkedSection([string]$Document, [string]$StartMarker, [string]$EndMarker, [string]$Replacement) {
  $pattern = '(?s)' + [regex]::Escape($StartMarker) + '.*?(?=' + [regex]::Escape($EndMarker) + ')'
  if ([regex]::IsMatch($Document, $pattern)) {
    return [regex]::Replace($Document, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $Replacement })
  }
  $index = $Document.IndexOf($EndMarker, [System.StringComparison]::Ordinal)
  if ($index -lt 0) { throw "Document insertion marker missing: $EndMarker" }
  return $Document.Insert($index, $Replacement)
}

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$objective = Read-StrictJson 'tools/legado-compat/state/refactor-objective.json'
$fixture = Read-StrictJson $fixturePath
$failureWitness = Read-StrictJson $failureWitnessPath
$contract = Read-StrictJson $contractPath
$queuePath = [string]$state.governance.queuePreflight.evidencePath
$queue = Read-StrictJson $queuePath

Assert-Fix ([string]$fixture.issueId -eq $issueId) 'fixture issue id drifted.'
Assert-Fix ([string]$failureWitness.status -eq 'failed' -and [string]$failureWitness.failureClass -eq 'governance_queue_pointer_rotation_drift') 'pre-fix witness is missing.'
Assert-Fix ([string]$contract.status -eq 'passed_static_only' -and [int]$contract.assertionCount -eq [int](@($contract.assertions).Count) -and -not [bool]$contract.semanticMatchAllowed) 'post-fix contract is incomplete or claims semantic match.'
Assert-Fix ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline drifted.'
Assert-Fix ([string]$objective.targetRevision -eq $revision -and [string]$queue.targetRevision -eq $revision) 'canonical revision drifted.'
Assert-Fix ([string]$state.governance.activeIssueId -eq $activeIssueId -and [string]$queue.activeIssueId -eq $activeIssueId) 'active issue drifted.'
Assert-Fix ($queuePath.Length -gt 0 -and (Test-Path -LiteralPath (Get-RepoPath $queuePath) -PathType Leaf)) 'current machine queue pointer is not addressable.'
Assert-Fix ([int]$queue.evaluatedCount -eq 229 -and [int]$queue.candidateCount -eq 0 -and [string]$queue.candidateGateStatus -eq 'no_candidate_satisfies_evidence_gate') 'current queue is not the static no-candidate branch.'

$changedFiles = @(
  'tools/legado-compat/Test-LegadoGovernanceTargetRevisionContract.ps1',
  'tools/legado-compat/Test-LegadoGovernanceQueueAuditEvidenceContract.ps1',
  'tools/legado-compat/Test-LegadoGovernanceQueueAuditStatusContract.ps1',
  'tools/legado-compat/Test-LegadoGovernanceQueueCountConsistencyContract.ps1',
  'tools/legado-compat/Register-LegadoGovernanceTargetRevisionSourceFix.ps1',
  'tools/legado-compat/Register-LegadoGovernanceQueueAuditEvidenceSourceFix.ps1',
  'tools/legado-compat/Register-LegadoGovernanceQueueAuditStatusSourceFix.ps1',
  $fixturePath,
  $failureWitnessPath,
  $contractPath,
  'tools/legado-compat/fixtures/legado-governance-queue-audit-evidence-drift.json',
  'tools/legado-compat/fixtures/legado-governance-queue-audit-status-drift.json',
  'tools/legado-compat/fixtures/legado-governance-queue-count-consistency.json',
  $queuePath
)
$fileRecords = @()
foreach ($relativePath in $changedFiles) {
  $path = Get-RepoPath $relativePath
  Assert-Fix (Test-Path -LiteralPath $path -PathType Leaf) "changed file is missing: $relativePath"
  $fileRecords += [pscustomobject][ordered]@{ path = $relativePath; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant(); byteLength = [System.IO.File]::ReadAllBytes($path).Length }
}
$manifest = ($fileRecords | ForEach-Object { '{0}:{1}:{2}' -f $_.path, $_.sha256, $_.byteLength }) -join "`n"
$manifestHash = [System.Security.Cryptography.SHA256]::Create().ComputeHash([System.Text.Encoding]::UTF8.GetBytes($manifest))
$manifestSha256 = ([System.BitConverter]::ToString($manifestHash)).Replace('-', '').ToUpperInvariant()

$sourceFixEvidence = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_governance_queue_pointer_rotation_source_fix'
  status = 'passed_static_only'
  issueId = $issueId
  taskId = $taskId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  activeIssueId = $activeIssueId
  targetRevision = $revision
  fixturePath = $fixturePath
  failureWitnessPath = $failureWitnessPath
  postFixContractPath = $contractPath
  currentQueueEvidencePath = $queuePath
  changedFiles = $fileRecords
  changedFilesManifestSha256 = $manifestSha256
  primaryCause = 'Current governance contracts and one queue-count fixture treated a rotating evidence batch name as a permanent machine pointer.'
  repair = 'Contracts, fixtures and prior governance registrars now resolve governance.queuePreflight.evidencePath from full-source-validation-state.json; r8/r9/r10 remain historical provenance only.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'static_governance_source_fix_only;runtime_build_install_device_and_legado_diff_deferred'
  closeCondition = 'A new queue evidence batch can be registered without changing contract source; all current pointer contracts follow the machine fact and historical paths remain explicitly historical.'
}
Write-AtomicJson $SourceFixPath $sourceFixEvidence

$documentSection = @'
## 治理队列指针轮换漂移修复（ISSUE-AUTO-054）

队列证据从 `r10` 轮换到新的 `r11` 后，目标修订、队列审计和计数合同仍硬编码历史批次，导致当前机器指针无法通过合同。`ISSUE-AUTO-054-GOVERNANCE-QUEUE-POINTER-ROTATION-DRIFT` 已先由 4 项失败合同见证复现，再通过动态指针 post-fix 静态合同和源修复证据关闭：当前合同与旧注册器统一读取 `full-source-validation-state.json` 的 `governance.queuePreflight.evidencePath`，r8/r9/r10 只保留为历史证据。

证据：`tools/legado-compat/evidence/contract-legado-governance-queue-pointer-rotation-drift-pre-fix-20260810.json`、`tools/legado-compat/fixtures/legado-governance-queue-pointer-rotation-drift.json`、`tools/legado-compat/evidence/contract-legado-governance-queue-pointer-rotation-20260810.json` 和 `tools/legado-compat/evidence/v2-governance-queue-pointer-rotation-source-fix-20260810.json`。该治理修复只改变静态证据指针解析，不执行运行时、网络、构建、安装、设备或 Legado 差分，`semanticMatchAllowed=false`，R4 仍延期。

'@
$document = Read-StrictText $objectiveDocumentPath
$document = Replace-MarkedSection $document '## 治理队列指针轮换漂移修复（ISSUE-AUTO-054）' '## 单议题执行规则' $documentSection
Write-AtomicText $objectiveDocumentPath $document

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$summary = '治理修复 ISSUE-AUTO-054：当前治理合同、计数 fixture 和旧注册器改为读取机器 queuePreflight.evidencePath；r11 轮换不再触发 r10/r8 指针漂移，静态合同通过，保持 243 verifying。'
$closeCondition = '4 项失败合同见证、post-fix 静态合同、源修复证据和动态当前指针持续一致；历史 r8/r9/r10 仅作为 provenance，R4 运行时、构建、设备与 Legado 差分仍是独立关闭条件。'
$evidencePaths = @($fixturePath, $failureWitnessPath, $contractPath, $SourceFixPath, 'tools/legado-compat/Register-LegadoGovernanceQueuePointerRotationSourceFix.ps1', 'tools/legado-compat/Test-LegadoGovernanceQueuePointerRotationPostFixContract.ps1', $queuePath)
$evidenceArgument = $evidencePaths -join ','
& pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript -StatePath (Get-RepoPath 'tools/legado-compat/state/full-source-validation-state.json') -IssueId $issueId -IssueStatus passed -TaskId $taskId -TaskStatus running -Severity P1 -Summary $summary -CloseCondition $closeCondition -EvidencePath $evidenceArgument | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Governance state update failed.' }

[pscustomobject][ordered]@{ status = 'registered'; issueId = $issueId; currentQueueEvidencePath = $queuePath; sourceFixEvidencePath = $SourceFixPath; changedFilesManifestSha256 = $manifestSha256; runtimeActionsPerformed = @(); semanticMatchAllowed = $false } | ConvertTo-Json -Depth 30
