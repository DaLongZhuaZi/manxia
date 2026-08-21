[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$EvidencePath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($RepositoryRoot.Length -eq 0) {
  $RepositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}
if ($EvidencePath.Length -eq 0) {
  $EvidencePath = Join-Path $PSScriptRoot 'evidence2-harness-030-031-readiness-contract-20260809.json'
}

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath -replace '/', '\')
}

function Read-StrictJson {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "证据文件不存在：$RelativePath"
  }
  return Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json -Depth 50
}

function Add-Assertion {
  param(
    [System.Collections.Generic.List[object]]$Assertions,
    [string]$Id,
    [bool]$Passed,
    [string]$Detail,
    [string[]]$Evidence
  )
  [void]$Assertions.Add([pscustomobject][ordered]@{
      id = $Id
      status = if ($Passed) { 'passed' } else { 'failed' }
      detail = $Detail
      evidence = @($Evidence)
    })
  if (-not $Passed) {
    throw "CONTRACT_FAILED id=$Id detail=$Detail"
  }
}

$assertions = New-Object 'System.Collections.Generic.List[object]'
$scriptRelative = 'tools/legado-compat/Invoke-LegadoFullDeviceReadinessAudit.ps1'
$scriptPath = Get-RepoPath $scriptRelative
$scriptText = Get-Content -LiteralPath $scriptPath -Raw -Encoding utf8
$stateRelative = 'tools/legado-compat/state/full-source-validation-state.json'
$state = Read-StrictJson $stateRelative
$postRelative = 'tools/legado-compat/evidence/v2-harness-030-device-readiness-single-row-20260809/post-fix-readiness-r4.json'
$post = Read-StrictJson $postRelative
$prepareRelative = 'tools/legado-compat/evidence/hypium-device-readiness/prepare-snapshot/attempt-01/result.json'
$restoreRelative = 'tools/legado-compat/evidence/hypium-device-readiness/restore-application/attempt-01/result.json'
$prepare = Read-StrictJson $prepareRelative
$restore = Read-StrictJson $restoreRelative
$preFixRelative = 'tools/legado-compat/evidence/v2-harness-030-device-readiness-single-row-20260809/pre-fix-failure.log'
$preFixPath = Get-RepoPath $preFixRelative
$preFixText = Get-Content -LiteralPath $preFixPath -Raw -Encoding utf8

Add-Assertion $assertions 'rows_outer_array' ($scriptText.Contains('$rows = @(if')) 'SQLite rows capture is wrapped by an outer array.' @($scriptRelative)
Add-Assertion $assertions 'verification_outer_array' ($scriptText.Contains('$verificationRows = @(if')) 'Verification rows capture is wrapped by an outer array.' @($scriptRelative)
Add-Assertion $assertions 'optional_error_safe_read' ($scriptText.Contains('Get-StatePropertyText -Object $attemptEvidence -Name ''error''')) 'Optional Hypium error fields use the strict-mode-safe property helper.' @($scriptRelative)
Add-Assertion $assertions 'isolated_attempt_directories' ($scriptText.Contains('(''attempt-{0:D2}'' -f $attempt)')) 'Each Hypium lifecycle retry uses an isolated attempt directory.' @($scriptRelative)
Add-Assertion $assertions 'attempt_manifest' ($scriptText.Contains('Join-Path $OutputDirectory ''attempts.json''')) 'Lifecycle attempts are persisted as a machine-readable manifest.' @($scriptRelative)
Add-Assertion $assertions 'driver_release_gate' ($scriptText.Contains('[bool]$attemptEvidence.driver_closed')) 'A lifecycle attempt cannot pass without driver_closed evidence.' @($scriptRelative)
Add-Assertion $assertions 'pre_fix_reproduction' ($preFixText.Contains("property 'Count' cannot be found")) 'The pre-fix single-row failure remains reproducible evidence.' @($preFixRelative)
Add-Assertion $assertions 'device_readiness_complete' ([int]$post.databaseRowCount -eq 458 -and [int]$post.counts.present -eq 458 -and [int]$post.counts.missing -eq 0) 'Post-fix readiness audited all 458 persisted compatibility rows.' @($postRelative)
Add-Assertion $assertions 'effective_v2_policy' ([string]$post.executionPolicy -eq 'v2_full_cutover' -and [int]$post.counts.effective_v2_enabled -eq [int]$post.counts.ready) 'Full-cutover effective V2 routing is reflected in readiness evidence.' @($postRelative)
Add-Assertion $assertions 'prepare_lifecycle_passed' ([string]$prepare.status -eq 'passed' -and [bool]$prepare.driver_closed) 'Prepare snapshot lifecycle passed and released Hypium.' @($prepareRelative)
Add-Assertion $assertions 'restore_lifecycle_passed' ([string]$restore.status -eq 'passed' -and [bool]$restore.driver_closed) 'Restore application lifecycle passed and released Hypium.' @($restoreRelative)
Add-Assertion $assertions 'active_issue_unchanged' ([string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-009') 'Harness repairs did not replace the active database migration issue.' @($stateRelative)
Add-Assertion $assertions 'baseline_fixed' ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'Machine facts remain bound to the frozen 458-source package.' @($stateRelative)

$evidence = [pscustomobject][ordered]@{
  schemaVersion = 1
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  sourcePackageSha256 = [string]$state.baseline.sourcePackageSha256
  device = '2UCUT24724009680'
  status = 'passed'
  assertionCount = $assertions.Count
  assertions = @($assertions.ToArray())
}
$evidenceDirectory = Split-Path -Parent $EvidencePath
[System.IO.Directory]::CreateDirectory($evidenceDirectory) | Out-Null
[System.IO.File]::WriteAllText($EvidencePath, ($evidence | ConvertTo-Json -Depth 20) + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
Write-Output "READINESS_HARNESS_CONTRACT_PASSED assertions=$($assertions.Count) evidence=$EvidencePath"
