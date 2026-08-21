[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$evDir = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\r4-unified-validation-20260814'
$runner = Join-Path $PSScriptRoot 'Invoke-LegadoV2FullSourceDeviceRunner.ps1'
# 全量 458：一次调度（MaxSources=458, RevalidateTerminalSources 重验全部状态）
Write-Output ('FULL_BATCH_START at=' + [DateTimeOffset]::UtcNow.ToString('o'))
$output = & pwsh -NoLogo -NoProfile -NonInteractive -File $runner -HdcPath 'F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' -Device '192.168.5.124:38491' -PythonPath (Join-Path $RepositoryRoot '.venv\Scripts\python.exe') -SourcePackagePath 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json' -StatePath (Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json') -EvidenceDirectory (Join-Path $evDir 'harness-runs-full') -ExecutionProfile safe_read_path -MaxSources 458 -RunReadinessAudit:$false -RevalidateTerminalSources 2>&1 | Out-String
$fullLog = Join-Path $evDir 'harness-runs-full\full-batch.stdout.log'
New-Item -ItemType Directory -Path (Split-Path -Parent $fullLog) -Force | Out-Null
[System.IO.File]::WriteAllText($fullLog, $output, [System.Text.UTF8Encoding]::new($false))
$parsed = $null
try { $parsed = $output | ConvertFrom-Json } catch { }
$summary = [ordered]@{
  schemaVersion = 1
  kind = 'legado_r4_step4_full_458_harness_batch'
  status = if ($null -ne $parsed -and [string]$parsed.status -eq 'passed') { 'completed' } else { 'failed' }
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  issueId = 'ISSUE-COMPAT-244-JSOUP-HTML-ENTITY-SEMANTICS'
  baseline = [ordered]@{ sourceCount = 458; sourcePackageSha256 = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'; legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd' }
  profile = 'safe_read_path'
  revalidateTerminalSources = $true
  runnerStatus = if ($null -ne $parsed) { [string]$parsed.status } else { 'unparseable' }
  runnerOutput = $output
  log = 'tools/legado-compat/evidence/r4-unified-validation-20260814/harness-runs-full/full-batch.stdout.log'
  runtimeActionsPerformed = @('full 458-source device-driven safe read path revalidation')
  semanticMatchAllowed = $false
}
$ledgerPath = Join-Path $evDir 'harness-runs-full\full-batch-ledger.json'
[System.IO.File]::WriteAllText($ledgerPath, ($summary | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
Write-Output ('FULL_BATCH_END status=' + $summary.status + ' at=' + [DateTimeOffset]::UtcNow.ToString('o'))