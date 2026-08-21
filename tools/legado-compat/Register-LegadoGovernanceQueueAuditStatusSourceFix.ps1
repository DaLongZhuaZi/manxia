[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-governance-queue-audit-status-source-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-AUTO-053-GOVERNANCE-QUEUE-AUDIT-STATUS-DRIFT'
$taskId = 'COMPAT-006'
$revision = '2026-08-10-actual-docs-source-refactor-jsoup-combination-r4-readiness-static-closure'
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$activeIssueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$fixturePath = 'tools/legado-compat/fixtures/legado-governance-queue-audit-status-drift.json'
$failureWitnessPath = 'tools/legado-compat/evidence/contract-legado-governance-queue-audit-status-drift-pre-fix-20260810.json'
$contractPath = 'tools/legado-compat/evidence/contract-legado-governance-queue-audit-status-20260810.json'
$registerScriptPath = 'tools/legado-compat/Register-LegadoCurrentStaticSourceCandidateGate.ps1'

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

function Get-Text {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return '' }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return '' }
  return [string]$property.Value
}

function Assert-Fix {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Governance status source-fix registration failed: $Message" }
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

function Write-AtomicText {
  param([string]$RelativePath, [string]$Value)
  $path = Get-RepoPath $RelativePath
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, $Value, $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Replace-MarkedSection {
  param([string]$Document, [string]$StartMarker, [string]$EndMarker, [string]$Replacement)
  $pattern = '(?s)' + [regex]::Escape($StartMarker) + '.*?(?=' + [regex]::Escape($EndMarker) + ')'
  if ([regex]::IsMatch($Document, $pattern)) {
    return [regex]::Replace($Document, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $Replacement })
  }
  $index = $Document.IndexOf($EndMarker, [System.StringComparison]::Ordinal)
  if ($index -lt 0) { throw "Document insertion marker missing: $EndMarker" }
  return $Document.Insert($index, $Replacement)
}

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$queueEvidencePath = [string]$state.governance.queuePreflight.evidencePath
$objective = Read-StrictJson 'tools/legado-compat/state/refactor-objective.json'
$fixture = Read-StrictJson $fixturePath
$failureWitness = Read-StrictJson $failureWitnessPath
$contract = Read-StrictJson $contractPath
$queue = Read-StrictJson $queueEvidencePath
$queueAudit = $objective.continuationTarget.queueAudit
$selectionGate = $objective.objective.queueSelectionGate
$registerText = Read-StrictText $registerScriptPath

Assert-Fix ([string]$fixture.issueId -eq $issueId) 'fixture issue id is not ISSUE-AUTO-053.'
Assert-Fix ([string]$objective.targetRevision -eq $revision -and [string]$queue.targetRevision -eq $revision) 'canonical target revision drifted.'
Assert-Fix ([string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and [int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline drifted.'
Assert-Fix ([string]$state.governance.activeIssueId -eq $activeIssueId -and [string]$queue.activeIssueId -eq $activeIssueId) 'active issue is not 243.'
Assert-Fix ([string]$failureWitness.status -eq 'failed' -and [string]$failureWitness.failureClass -eq 'governance_queue_audit_status_drift') 'pre-fix failure witness is missing.'
Assert-Fix ([string]$contract.status -eq 'passed_static_only' -and [int]$contract.assertionCount -eq [int](@($contract.assertions).Count) -and -not [bool]$contract.semanticMatchAllowed) 'post-fix contract is incomplete or claims semantic match.'
Assert-Fix ([int]$queue.candidateCount -eq 0 -and [string]$queue.candidateGateStatus -eq 'no_candidate_satisfies_evidence_gate' -and @($queue.runtimeActionsPerformed).Count -eq 0) 'queue is no longer the static no-candidate branch.'
Assert-Fix ([string]$queueAudit.status -eq 'preflight_passed_no_candidate' -and [string]$queueAudit.candidateGateStatus -eq 'no_candidate_satisfies_evidence_gate' -and [string]$queueAudit.candidateStatus -eq 'no_candidate_satisfies_evidence_gate') 'queueAudit no-candidate status is not explicit.'
Assert-Fix ([string]$selectionGate.candidateStatus -eq 'source_fix_static_closed' -and [string]$selectionGate.candidateGateStatus -eq 'source_fix_static_closed_wait_r4') 'queueSelectionGate was incorrectly rewritten.'
Assert-Fix $registerText.Contains("Set-PropertyValue `$queueAudit 'candidateStatus' 'no_candidate_satisfies_evidence_gate'") 'registration script does not write the explicit no-candidate status.'

$changedFiles = @(
  $registerScriptPath,
  'tools/legado-compat/Test-LegadoR3StaticConvergenceGate.ps1',
  'tools/legado-compat/Test-LegadoGovernanceQueueAuditStatusDriftFailureWitness.ps1',
  'tools/legado-compat/Test-LegadoGovernanceQueueAuditStatusContract.ps1',
  $fixturePath,
  $failureWitnessPath,
  $contractPath,
  'tools/legado-compat/state/full-source-validation-state.json',
  'tools/legado-compat/state/refactor-objective.json',
  $queueEvidencePath
)
$fileRecords = @()
foreach ($relativePath in $changedFiles) {
  $path = Get-RepoPath $relativePath
  Assert-Fix (Test-Path -LiteralPath $path -PathType Leaf) "changed file is missing: $relativePath"
  $fileRecords += [pscustomobject][ordered]@{ path = $relativePath; sha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant(); byteLength = [System.IO.File]::ReadAllBytes($path).Length }
}
$manifest = ($fileRecords | ForEach-Object { '{0}:{1}:{2}' -f $_.path, $_.sha256, $_.byteLength }) -join "`n"
$manifestBytes = [System.Text.Encoding]::UTF8.GetBytes($manifest)
$manifestHash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($manifestBytes)
$manifestSha256 = ([System.BitConverter]::ToString($manifestHash)).Replace('-', '').ToUpperInvariant()

$sourceFixEvidence = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_governance_queue_audit_status_source_fix'
  status = 'passed_static_only'
  issueId = $issueId
  taskId = $taskId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  canonicalRevision = $revision
  activeIssueId = $activeIssueId
  fixturePath = $fixturePath
  failureWitnessPath = $failureWitnessPath
  postFixContractPath = $contractPath
  queueEvidencePath = $queueEvidencePath
  changedFiles = $fileRecords
  changedFilesManifestSha256 = $manifestSha256
  primaryCause = 'The no-candidate queue registration synchronized status and candidateGateStatus but left candidateStatus=source_fix_static_closed, falsely implying that a candidate source fix had been statically closed even though candidateCount was zero.'
  repair = 'The registration now writes candidateStatus=no_candidate_satisfies_evidence_gate in the queueAudit projection while leaving objective.queueSelectionGate candidateStatus=source_fix_static_closed as the separate active-issue anchor.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'static_governance_source_fix_only;runtime_build_install_device_and_legado_diff_deferred'
  closeCondition = 'Every no-candidate queue registration keeps status, candidateGateStatus and candidateStatus mutually consistent; the separate active-issue selection gate remains unchanged and all static contracts stay aligned.'
}
Write-AtomicJson -RelativePath $SourceFixPath -Value $sourceFixEvidence

$documentRelative = 'docs/analysis/Legado书源V2源码重构持续目标.md'
$documentSection = @'
## 治理队列审计状态漂移修复（ISSUE-AUTO-053）

无候选队列审计曾将 `status=preflight_passed_no_candidate` 与 `candidateGateStatus=no_candidate_satisfies_evidence_gate` 写入 `queueAudit`，却残留 `candidateStatus=source_fix_static_closed`；这把“没有候选”误报为“候选源码修复已闭合”。`ISSUE-AUTO-053-GOVERNANCE-QUEUE-AUDIT-STATUS-DRIFT` 已由 10 项失败见证复现，再通过 9 项 post-fix 静态契约关闭：`queueAudit.candidateStatus` 现在明确为 `no_candidate_satisfies_evidence_gate`，而 `objective.queueSelectionGate` 的活动议题状态保持独立不变。

证据：`tools/legado-compat/evidence/contract-legado-governance-queue-audit-status-drift-pre-fix-20260810.json`、`tools/legado-compat/fixtures/legado-governance-queue-audit-status-drift.json`、`tools/legado-compat/evidence/contract-legado-governance-queue-audit-status-20260810.json` 和 `tools/legado-compat/evidence/v2-governance-queue-audit-status-source-fix-20260810.json`。本治理修复只改变静态队列状态投影，不执行运行时、网络、构建、安装、设备或 Legado 差分，`semanticMatchAllowed=false`，R4 仍延期。

'@
$document = Read-StrictText $documentRelative
$document = Replace-MarkedSection -Document $document -StartMarker '## 治理队列审计状态漂移修复（ISSUE-AUTO-053）' -EndMarker '## 单议题执行规则' -Replacement $documentSection
Write-AtomicText -RelativePath $documentRelative -Value $document

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$summary = '治理修复 ISSUE-AUTO-053：无候选 queueAudit 的 candidateStatus 现在明确为 no_candidate_satisfies_evidence_gate；9 项 post-fix 契约通过，保持 243 verifying、semanticMatchAllowed=false。'
$closeCondition = '10 项失败见证、9 项 post-fix 契约、源修复证据、队列状态、活动议题选择门禁和派生文档持续一致；R4 运行时、构建、设备与 Legado 差分仍是独立关闭条件。'
$evidencePaths = @($fixturePath, $failureWitnessPath, $contractPath, $SourceFixPath, $registerScriptPath, 'tools/legado-compat/Test-LegadoGovernanceQueueAuditStatusDriftFailureWitness.ps1', 'tools/legado-compat/Test-LegadoGovernanceQueueAuditStatusContract.ps1', 'tools/legado-compat/Test-LegadoR3StaticConvergenceGate.ps1', $queueEvidencePath)
$evidenceArgument = $evidencePaths -join ','
& pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript -StatePath (Get-RepoPath 'tools/legado-compat/state/full-source-validation-state.json') -IssueId $issueId -IssueStatus passed -TaskId $taskId -TaskStatus running -Severity P1 -Summary $summary -CloseCondition $closeCondition -EvidencePath $evidenceArgument -CreateIfMissing | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Governance state update failed.' }

[pscustomobject][ordered]@{
  status = 'registered'
  issueId = $issueId
  activeIssueId = $activeIssueId
  sourceFixEvidencePath = $SourceFixPath
  changedFilesManifestSha256 = $manifestSha256
  evidenceCount = $evidencePaths.Count
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
} | ConvertTo-Json -Depth 30
