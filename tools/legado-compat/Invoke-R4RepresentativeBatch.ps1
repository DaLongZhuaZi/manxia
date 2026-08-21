[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$EvidenceDirectory = ''
)
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
  $EvidenceDirectory = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\r4-unified-validation-20260814\harness-runs'
}
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null

$runner = Join-Path $PSScriptRoot 'Invoke-LegadoV2FullSourceDeviceRunner.ps1'
$step3 = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\r4-unified-validation-20260814\step3-affected-source-set.json'
$reps = (Get-Content -LiteralPath $step3 -Encoding UTF8 -Raw | ConvertFrom-Json).representatives
$ordinals = @($reps | ForEach-Object { [int]$_.ordinal } | Sort-Object)
Write-Output ('REPRESENTATIVE_COUNT=' + $ordinals.Count)
$summary = New-Object 'System.Collections.Generic.List[object]'
foreach ($ordinal in $ordinals) {
  $output = & pwsh -NoLogo -NoProfile -NonInteractive -File $runner -HdcPath 'F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe' -Device '192.168.5.124:38491' -PythonPath (Join-Path $RepositoryRoot '.venv\Scripts\python.exe') -SourcePackagePath 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json' -StatePath (Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json') -EvidenceDirectory $EvidenceDirectory -ExecutionProfile safe_read_path -OnlyOrdinal $ordinal -RunReadinessAudit:$false -RevalidateTerminalSources 2>&1 | Out-String
  $parsed = $null
  try { $parsed = $output | ConvertFrom-Json } catch { }
  $src = if ($null -ne $parsed -and @($parsed.sources).Count -gt 0) { @($parsed.sources)[0] } else { $null }
  [void]$summary.Add([ordered]@{
    ordinal = $ordinal
    runnerStatus = if ($null -ne $parsed) { [string]$parsed.status } else { 'unparseable' }
    sourceStatus = if ($null -ne $src) { [string]$src.status } else { '' }
    outcome = if ($null -ne $src) { [string]$src.outcome } else { '' }
  })
  Write-Output ('RUN_DONE ordinal=' + $ordinal + ' runner=' + $summary[$summary.Count-1].runnerStatus + ' source=' + $summary[$summary.Count-1].sourceStatus + ' outcome=' + $summary[$summary.Count-1].outcome)
}
$ledger = [ordered]@{
  schemaVersion = 1
  kind = 'legado_r4_step4_representative_batch'
  status = 'completed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  issueId = 'ISSUE-COMPAT-244-JSOUP-HTML-ENTITY-SEMANTICS'
  baseline = [ordered]@{ sourceCount = 458; sourcePackageSha256 = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'; legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd' }
  profile = 'safe_read_path'
  revalidateTerminalSources = $true
  representativeCount = $ordinals.Count
  ordinals = $ordinals
  results = $summary.ToArray()
  runtimeActionsPerformed = @('device-driven safe read path per representative')
  semanticMatchAllowed = $false
}
$ledgerPath = Join-Path $EvidenceDirectory 'r4-representative-batch-ledger.json'
[System.IO.File]::WriteAllText($ledgerPath, ($ledger | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
Write-Output ('LEDGER written: ' + $ledgerPath)