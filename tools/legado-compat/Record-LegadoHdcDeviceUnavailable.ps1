[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$HdcPath = 'F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
  [string]$EvidenceDirectory = 'tools/legado-compat/evidence/device-hdc-availability'
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
$taskId = 'COMPAT-006'
$issueId = 'ISSUE-AUTO-050-HDC-DEVICE-UNAVAILABLE'
$stateRelativePath = 'tools/legado-compat/state/full-source-validation-state.json'
$scriptRelativePath = 'tools/legado-compat/Record-LegadoHdcDeviceUnavailable.ps1'

function Get-RepoPath([string]$RelativePath) {
  if ([System.IO.Path]::IsPathRooted($RelativePath)) {
    return $RelativePath
  }
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson([string]$RelativePath) {
  $path = Get-RepoPath $RelativePath
  $bytes = [System.IO.File]::ReadAllBytes($path)
  return $strictUtf8.GetString($bytes) | ConvertFrom-Json -Depth 100
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 60), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      [System.IO.File]::Delete($temporaryPath)
    }
  }
}

function Invoke-HdcText([string[]]$Arguments) {
  $output = & $HdcPath @Arguments 2>&1 | Out-String
  return [pscustomobject][ordered]@{
    arguments = $Arguments
    exitCode = [int]$LASTEXITCODE
    output = $output.Trim()
  }
}

if (-not (Test-Path -LiteralPath $HdcPath -PathType Leaf)) {
  throw "HDC does not exist: $HdcPath"
}

$state = Read-StrictJson $stateRelativePath
$baseline = $state.baseline
if ([int]$baseline.sourceCount -ne $sourceCount -or
    [string]$baseline.sourcePackageSha256 -ne $sourceHash -or
    [string]$baseline.legadoCommit -ne $legadoCommit) {
  throw 'Frozen compatibility baseline drifted.'
}
if ([string]$state.governance.activeTaskId -ne $taskId -or
    [string]$state.governance.activeIssueId -ne 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS') {
  throw 'The active source governance boundary is not COMPAT-006/243.'
}

# Remove only the two temporary paths created while diagnosing nested
# PowerShell array binding.  Historical HDC evidence and the current probe
# are preserved; no broad evidence pruning is allowed here.
$probeIssue = @($state.governance.issues | Where-Object {
  [string]$_.id -eq $issueId
}) | Select-Object -First 1
if ($null -ne $probeIssue) {
  $temporaryEvidence = @(
    'tools/legado-compat/evidence/device-hdc-availability/test.json',
    'tools/legado-compat/evidence/device-hdc-availability/test2.json'
  )
  $probeIssue.evidencePaths = @($probeIssue.evidencePaths | Where-Object {
    $temporaryEvidence -notcontains [string]$_
  })
  Import-Module -Name (Get-RepoPath 'tools/legado-compat/LegadoFullSourceState.psm1') -Force
  Sync-LegadoStateDerivedFields -State $state
  Write-LegadoStateCheckpoint -Path (Get-RepoPath $stateRelativePath) -State $state -Depth 60
}

$checkedAt = [DateTimeOffset]::UtcNow
$version = Invoke-HdcText @('-v')
$targets = Invoke-HdcText @('list', 'targets')
$targetsVerbose = Invoke-HdcText @('list', 'targets', '-v')
$targetLines = @($targets.output -split '\r?\n' | Where-Object {
  $line = $_.Trim()
  $line.Length -gt 0 -and $line -ne '[Empty]'
})
$status = if ($targetLines.Count -eq 0) { 'blocked' } else { 'unexpected_target_visible' }

$evidenceDirectoryPath = Get-RepoPath $EvidenceDirectory
[System.IO.Directory]::CreateDirectory($evidenceDirectoryPath) | Out-Null
$stamp = $checkedAt.ToString('yyyyMMddTHHmmssfffZ')
$evidenceRelativePath = ($EvidenceDirectory.TrimEnd('/', '\') + '/hdc-unavailable-' + $stamp + '.json')
$evidence = [ordered]@{
  schemaVersion = 1
  kind = 'legado_hdc_device_availability'
  issueId = $issueId
  taskId = $taskId
  status = $status
  generatedAt = $checkedAt.ToString('o')
  baseline = [ordered]@{
    sourceCount = $sourceCount
    sourcePackageSha256 = $sourceHash
    legadoCommit = $legadoCommit
  }
  environment = [ordered]@{
    hdcPath = $HdcPath
    hdcVersion = $version.output
    currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    isAdministrator = ([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
  }
  probes = [ordered]@{
    listTargets = $targets
    listTargetsVerbose = $targetsVerbose
  }
  targetCount = $targetLines.Count
  runtimeActionsPerformed = @('hdc_version', 'hdc_list_targets', 'hdc_list_targets_verbose')
  semanticMatchAllowed = $false
  failureClass = if ($status -eq 'blocked') { 'device_unavailable' } else { 'device_state_changed_during_probe' }
  statement = if ($status -eq 'blocked') {
    'HDC 版本可执行，但 list targets 没有返回任何设备；未执行安装、启动、Hypium、数据库审计或书源工作流。'
  } else {
    'HDC 探测期间出现目标设备，未自动选择未知设备；需要按实时设备 ID重新执行受控真机门禁。'
  }
  closeCondition = 'hdc list targets 返回明确的 HarmonyOS 设备 ID 后，重新执行当前 signed HAP 安装、冷启动和 Hypium 门禁；不得使用本证据替代真机语义验证。'
  reproductionCommand = 'pwsh -NoLogo -NoProfile -NonInteractive -File tools/legado-compat/Record-LegadoHdcDeviceUnavailable.ps1'
}
Write-AtomicJson $evidenceRelativePath $evidence

$summary = if ($status -eq 'blocked') {
  'HDC 3.2.0d 可执行，但 list targets 返回 [Empty]；未执行安装、启动、Hypium 或书源工作流，真机门禁保持 blocked。'
} else {
  'HDC 探测到未指定目标，未自动选择设备；真机门禁保持 blocked，等待明确设备 ID。'
}
$closeCondition = [string]$evidence.closeCondition
$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$evidenceArgument = [string]::Join(',', @($evidenceRelativePath, $scriptRelativePath))
$updateOutput = & pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript `
  -IssueId $issueId `
  -IssueStatus blocked `
  -TaskId $taskId `
  -TaskStatus running `
  -Severity P1 `
  -Summary $summary `
  -CloseCondition $closeCondition `
  -EvidencePath $evidenceArgument `
  -CreateIfMissing 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
  throw "Governance update failed: $updateOutput"
}

[pscustomobject][ordered]@{
  status = $status
  issueId = $issueId
  evidencePath = $evidenceRelativePath
  governanceUpdate = $updateOutput.Trim()
  targetCount = $targetLines.Count
  semanticMatchAllowed = $false
} | ConvertTo-Json -Depth 20
