[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-governance-queue-audit-evidence-source-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-AUTO-052-GOVERNANCE-QUEUE-AUDIT-EVIDENCE-DRIFT'
$taskId = 'COMPAT-006'
$activeIssueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$revision = '2026-08-10-actual-docs-source-refactor-jsoup-combination-r4-readiness-static-closure'
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$fixturePath = 'tools/legado-compat/fixtures/legado-governance-queue-audit-evidence-drift.json'
$failureWitnessPath = 'tools/legado-compat/evidence/contract-legado-governance-queue-audit-evidence-drift-pre-fix-20260810.json'
$contractPath = 'tools/legado-compat/evidence/contract-legado-governance-queue-audit-evidence-20260810.json'
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
  try { return (Read-StrictText $RelativePath | ConvertFrom-Json) }
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
  if (-not $Condition) { throw "Queue audit source-fix registration failed: $Message" }
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
$registerText = Read-StrictText $registerScriptPath

Assert-Fix ([string]$fixture.issueId -eq $issueId) 'fixture issue id is not ISSUE-AUTO-052.'
Assert-Fix ([string]$objective.targetRevision -eq $revision -and [string]$queue.targetRevision -eq $revision) 'canonical target revision drifted.'
Assert-Fix ([string]$state.governance.activeIssueId -eq $activeIssueId -and [string]$queue.activeIssueId -eq $activeIssueId) 'active issue is not 243.'
Assert-Fix ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline drifted.'
Assert-Fix ([string]$failureWitness.status -eq 'failed' -and [string]$failureWitness.failureClass -eq 'governance_queue_audit_evidence_drift') 'pre-fix failure witness is missing.'
Assert-Fix ([string]$contract.status -eq 'passed_static_only' -and [int]$contract.assertionCount -eq [int](@($contract.assertions).Count) -and -not [bool]$contract.semanticMatchAllowed) 'post-fix contract is incomplete or claims semantic match.'
Assert-Fix ([int]$queue.candidateCount -eq 0 -and [string]$queue.candidateGateStatus -eq 'no_candidate_satisfies_evidence_gate' -and @($queue.runtimeActionsPerformed).Count -eq 0) 'queue is no longer the static no-candidate branch.'
Assert-Fix ($registerText -match 'historicalQueueEvidenceProjection' -and $registerText -match 'queueAuditEvidenceFields' -and $registerText -match 'Set-PropertyValue.*queueAudit.*field') 'registration script does not implement historical snapshot and clearing.'

$docRelative = 'docs/analysis/Legado书源V2源码重构持续目标.md'
$document = Read-StrictText $docRelative
$docSection = @'
## 治理队列审计证据漂移修复（ISSUE-AUTO-052）

无候选队列的注册器曾只更新 `auditEvidencePath` 和门禁状态，却保留上一议题的 `failureWitnessPath`、`sourceFixEvidencePath`、`postFixContractEvidencePath` 等活动字段；这会把历史 011/243 证据误投影为当前候选。`ISSUE-AUTO-052-GOVERNANCE-QUEUE-AUDIT-EVIDENCE-DRIFT` 已先由 16 项失败见证复现，再通过 29 项 post-fix 静态契约关闭：当前候选证据字段全部为空，旧路径仅保留在 `historicalQueueEvidenceProjection`，`priorActiveIssueId` 继续作为明确历史来源。

证据：`tools/legado-compat/evidence/contract-legado-governance-queue-audit-evidence-drift-pre-fix-20260810.json`、`tools/legado-compat/fixtures/legado-governance-queue-audit-evidence-drift.json`、`tools/legado-compat/evidence/contract-legado-governance-queue-audit-evidence-20260810.json` 和 `tools/legado-compat/evidence/v2-governance-queue-audit-evidence-source-fix-20260810.json`。该治理修复只改变静态队列证据投影，不执行运行时、网络、构建、安装、设备或 Legado 差分，`semanticMatchAllowed=false`，R4 仍延期。

'@
$document = Replace-MarkedSection -Document $document -StartMarker '## 治理队列审计证据漂移修复（ISSUE-AUTO-052）' -EndMarker '## 单议题执行规则' -Replacement $docSection
Write-AtomicText -RelativePath $docRelative -Value $document

$changedFiles = @(
  $registerScriptPath,
  $fixturePath,
  'tools/legado-compat/Test-LegadoGovernanceQueueAuditEvidenceDriftFailureWitness.ps1',
  'tools/legado-compat/Test-LegadoGovernanceQueueAuditEvidenceContract.ps1',
  'tools/legado-compat/state/full-source-validation-state.json',
  'tools/legado-compat/state/refactor-objective.json',
  $docRelative,
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
  kind = 'legado_governance_queue_audit_evidence_source_fix'
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
  queueEvidencePath = $queueEvidencePath
  changedFiles = $fileRecords
  changedFilesManifestSha256 = $manifestSha256
  primaryCause = 'The no-candidate queue registration updated the gate pointer but did not clear prior candidate evidence fields, allowing historical issue paths to remain addressable as current queue evidence.'
  repair = 'The registration now snapshots non-empty candidate fields under historicalQueueEvidenceProjection and clears all current candidate evidence fields atomically before updating the no-candidate queue state.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'static_governance_source_fix_only;runtime_build_install_device_and_legado_diff_deferred'
  closeCondition = 'Every no-candidate queue registration leaves current candidate evidence fields empty, preserves prior paths only in an explicit historical projection, and keeps the machine pointer, active issue and canonical revision aligned.'
}
Write-AtomicJson $SourceFixPath $sourceFixEvidence

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$summary = '治理修复 ISSUE-AUTO-052：无候选队列注册器现在将旧候选证据快照到 historicalQueueEvidenceProjection，并清空当前候选字段；29 项 post-fix 契约通过，保持 243 verifying、semanticMatchAllowed=false。'
$closeCondition = '16 项失败见证、29 项 post-fix 契约、源修复证据和派生文档持续一致；当前候选字段不得残留历史路径，R4 运行时、构建、设备与 Legado 差分仍是独立关闭条件。'
$evidencePaths = @($fixturePath, $failureWitnessPath, $contractPath, $SourceFixPath, $registerScriptPath, 'tools/legado-compat/Test-LegadoGovernanceQueueAuditEvidenceDriftFailureWitness.ps1', 'tools/legado-compat/Test-LegadoGovernanceQueueAuditEvidenceContract.ps1', $queueEvidencePath)
$evidenceArgument = $evidencePaths -join ','
& pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript -StatePath (Get-RepoPath 'tools/legado-compat/state/full-source-validation-state.json') -IssueId $issueId -IssueStatus passed -TaskId $taskId -TaskStatus running -Severity P1 -Summary $summary -CloseCondition $closeCondition -EvidencePath $evidenceArgument -CreateIfMissing | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Governance state update failed.' }

[pscustomobject][ordered]@{ status = 'registered'; issueId = $issueId; targetRevision = $revision; sourceFixEvidencePath = $SourceFixPath; changedFilesManifestSha256 = $manifestSha256; evidenceCount = $evidencePaths.Count; runtimeActionsPerformed = @(); semanticMatchAllowed = $false } | ConvertTo-Json -Depth 30
