[CmdletBinding()]
param([string]$RepositoryRoot = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$state = Get-Content -LiteralPath $statePath -Raw -Encoding utf8 | ConvertFrom-Json
$issueId = 'V2-HARNESS-023'
$existingIssue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId }) | Select-Object -First 1
$existingAttempts = if ($null -eq $existingIssue) { 0 } else { [int]$existingIssue.attempts }
$issue = [pscustomobject][ordered]@{
  id = $issueId
  taskId = 'COMPAT-006'
  status = 'in_progress'
  severity = 'P0'
  attempts = $existingAttempts
  summary = '七工作流 source evidence 投影和 source/workflow attempt 双向重建的源码契约已闭合；证据写出隔离治理已加入：默认 Hypium 批次必须写入 evidence/full-source-v2-hypium-device-run-* 独立目录，canonical full-source-v2-hypium-device 及其所有子目录仅作不可变 baseline，控制 manifest 单独位于 full-source-v2-hypium-device-control，activity 不得逃出 run directory，并以原子写入 source evidence。新增记录级异常隔离：畸形子进程结果或投影异常只结算当前 source 的七工作流 evidence，批次继续处理后续 source；若完整 source evidence 序列化或替换再次失败，则在同一 run directory 写出 source-<id>.fallback.json 最小闭合矩阵并在 activity.evidencePath 绑定，后续 source_settled activity 更新保留该路径，fallback 自身失败才记录 source_evidence_write_failed。新增 effective overlay 输出路径守卫：审计器拒绝 baseline、baseline 子目录和 evidence root 外的写出；Update-LegadoGovernanceState 允许并原子保留 in_progress 议题状态；activity writer 只在 previous runId 与当前 runId 相同的时候继承 evidencePath，禁止跨运行污染。静态合同已覆盖 baseline 隔离、run manifest/activity 路径绑定、overlay 发现与写出隔离、record exception containment、fallback evidence、activity binding persistence 和 run reuse；旧 baseline/effective audit 当前仍有历史证据缺口，fresh full_workflow 批次前不能作为全量契约通过；V2-HARNESS-023 仍等待 fresh full_workflow 证据与后置回归。'
  evidencePaths = @(
    'tools/legado-compat/evidence/contract-v2-harness-023-pre-fix-20260808.json',
    'tools/legado-compat/evidence/v2-harness-023-source-fix-20260808.json',
    'tools/legado-compat/evidence/v2-harness-023-baseline-audit-after-projection-20260808.json',
    'tools/legado-compat/fixtures/hypium-source-workflow-evidence-projection.json',
    'tools/legado-compat/fixtures/hypium-evidence-run-isolation.json',
    'tools/legado-compat/Test-LegadoV2SourceWorkflowEvidenceProjectionContract.ps1',
    'tools/legado-compat/Test-LegadoV2HypiumEvidenceRunIsolationContract.ps1',
    'tools/legado-compat/fixtures/hypium-record-exception-containment.json',
    'tools/legado-compat/Test-LegadoV2HypiumRecordExceptionContainmentContract.ps1',
    'tools/legado-compat/evidence/v2-harness-023-record-exception-containment-contract-20260808.json',
    'tools/legado-compat/evidence/v2-harness-023-record-exception-containment-source-fix-20260808.json',
    'tools/legado-compat/evidence/v2-harness-023-record-exception-fallback-source-fix-20260808.json',
    'tools/legado-compat/evidence/v2-source-workflow-evidence-projection-contract.json',
    'tools/legado-compat/evidence/v2-harness-023-source-attempt-reconciliation-20260808.json',
    'tools/legado-compat/evidence/v2-harness-023-evidence-run-isolation-contract-20260808.json',
    'tools/legado-compat/evidence/v2-harness-023-evidence-run-isolation-descendant-pre-fix-20260808.json',
    'tools/legado-compat/evidence/v2-hypium-full-source-runner-contract.json',
    'tools/legado-compat/evidence/effective-full-source-v2-hypium-device/full-source-evidence-contract-after-run-isolation.json',
    'tools/legado-compat/LegadoHypiumEvidencePaths.psm1',
    'tools/legado-compat/Test-LegadoV2HypiumFullSourceEvidence.ps1',
    'tools/legado-compat/Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1',
    'tools/legado-compat/evidence/effective-full-source-v2-hypium-device/full-source-evidence-contract-after-projection.json',
    'tools/legado-compat/fixtures/hypium-effective-overlay-write-isolation.json',
    'tools/legado-compat/Test-LegadoV2EffectiveOverlayWriteIsolationContract.ps1',
    'tools/legado-compat/evidence/v2-harness-023-effective-overlay-write-isolation-contract-20260808.json',
    'tools/legado-compat/LegadoHypiumEvidencePaths.psm1',
    'tools/legado-compat/Test-LegadoV2HypiumFullSourceEvidence.ps1',
    'tools/legado-compat/fixtures/hypium-governance-in-progress-status.json',
    'tools/legado-compat/Test-LegadoV2GovernanceInProgressStatusContract.ps1',
    'tools/legado-compat/evidence/v2-harness-023-governance-in-progress-status-pre-fix-20260808.json',
    'tools/legado-compat/evidence/v2-harness-023-governance-in-progress-status-contract-20260808.json',
    'tools/legado-compat/Update-LegadoGovernanceState.ps1',
    'tools/legado-compat/fixtures/hypium-activity-run-reuse.json',
    'tools/legado-compat/Test-LegadoV2HypiumActivityRunReuseContract.ps1',
    'tools/legado-compat/evidence/v2-harness-023-activity-run-reuse-pre-fix-20260808.json',
    'tools/legado-compat/evidence/v2-harness-023-activity-run-reuse-contract-20260808.json',
    'tools/legado-compat/Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1'
  )
  closeCondition = 'fresh full_workflow device batch writes workflowEvidence and sourceAttemptEvidence for all 458 sources into a run-scoped sibling directory without modifying canonical baseline evidence; a malformed child result or record projection exception produces closed failed evidence for only that source and later ordinals continue; if full source evidence writing fails, a same-run source-<id>.fallback.json artifact with a closed seven-workflow matrix and activity.evidencePath is produced, subsequent source_settled activity updates preserve the binding, or a second explicit source_evidence_write_failed activity is recorded; effective evidence audit rejects baseline-colliding or outside-root output paths, preserves in_progress state atomically, and activity never inherits an evidencePath from a different runId; no source/workflow binding, missing-result, record-abort or evidence-overwrite failures; then one fresh ordinal regression and document refresh pass.'
  lastUpdatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'")
}
$governance = $state.governance
$items = New-Object 'System.Collections.Generic.List[object]'
$replaced = $false
foreach ($existing in @($governance.issues)) {
  if ([string]$existing.id -eq $issueId) {
    [void]$items.Add($issue)
    $replaced = $true
  } else { [void]$items.Add($existing) }
}
if (-not $replaced) { [void]$items.Add($issue) }
$governance.issues = $items.ToArray()
$temporaryPath = "$statePath.tmp-$PID"
[System.IO.File]::WriteAllText($temporaryPath, ($state | ConvertTo-Json -Depth 24), [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::Move($temporaryPath, $statePath, $true)
$issue | ConvertTo-Json -Compress -Depth 8
