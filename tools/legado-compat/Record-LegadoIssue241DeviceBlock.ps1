[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$ColdStartResultPath = 'tmp/hypium-driver-r4-cold-start-20260809-retry/result.json',
  [string]$EvidencePath = 'tools/legado-compat/evidence/r4-build-device-20260809-r2/issue-241-device-block.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$utf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-COMPAT-241-ARKTS-INLINE-OBJECT-TYPES'
$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$sourceCount = 458
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'

function Get-RepositoryPath([string]$RelativePath) {
  if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $RelativePath }
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}
function Read-StrictJson([string]$RelativePath) {
  $bytes = [System.IO.File]::ReadAllBytes((Get-RepositoryPath $RelativePath))
  return $utf8.GetString($bytes) | ConvertFrom-Json
}
function Set-PropertyValue([object]$Object, [string]$Name, [object]$Value) {
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
  else { $property.Value = $Value }
}
function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepositoryPath $RelativePath
  [System.IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 80), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

$state = Read-StrictJson $statePath
$objective = Read-StrictJson $objectivePath
$result = Read-StrictJson $ColdStartResultPath
if ([int]$state.baseline.sourceCount -ne $sourceCount -or [string]$state.baseline.sourcePackageSha256 -ne $sourceHash -or [string]$state.baseline.legadoCommit -ne $legadoCommit) { throw 'ISSUE241_DEVICE_BLOCKED: frozen baseline drifted.' }
$errorText = [string]$result.error
if ($errorText -notmatch '10106102|screen is locked|screen.*locked') { throw 'ISSUE241_DEVICE_BLOCKED: evidence is not a lock-screen interaction block.' }

$evidence = [ordered]@{
  schemaVersion = 1
  kind = 'legado_issue_241_device_needs_interaction'
  status = 'needs_interaction'
  issueId = $issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  device = [ordered]@{ deviceSn = [string]$result.device_sn; deviceClass = 'harmony_real_device'; package = [string]$result.package; ability = [string]$result.ability }
  failureClass = 'needs_interaction'
  errorCode = '10106102'
  statement = '真机处于指纹锁屏，Hypium 无法在开发者模式下自动解锁；未执行应用启动、迁移或 UI 断言。禁止将该次运行计为通过。'
  sourceResultPath = $ColdStartResultPath
  screenshotPath = [string]$result.screenshots.failure
  runtimeActionsPerformed = @('hdc_install_signed_hap')
  semanticMatchAllowed = $false
  nextAction = '用户解锁设备后，从冷启动 smoke 重新开始；不重跑构建。'
}
Write-AtomicJson $EvidencePath $evidence

$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId }) | Select-Object -First 1
if ($null -eq $issue) { throw 'ISSUE241_DEVICE_BLOCKED: issue missing.' }
Set-PropertyValue $issue 'status' 'needs_interaction'
Set-PropertyValue $issue 'summary' 'debug 构建已通过并完成 signed HAP 安装；真机冷启动尚未执行，设备处于指纹锁屏，等待用户解锁后继续。'
Set-PropertyValue $issue 'evidencePaths' (@($issue.evidencePaths) + @($EvidencePath, $ColdStartResultPath))
Set-PropertyValue $issue 'lastUpdatedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue $state.governance 'activeIssueId' $issueId
Set-PropertyValue $state.governance 'status' 'blocked'
Set-PropertyValue $state.governance 'currentSourceClosureBoundary' $issueId
Set-PropertyValue $state.governance 'semanticMatchAllowed' $false
Set-PropertyValue $state 'updatedAt' ([DateTimeOffset]::UtcNow.ToString('o'))

$objective.targetRevision = '2026-08-09-r4-issue241-device-needs-interaction'
Set-PropertyValue $objective 'lastReviewedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue $objective 'nextAction' '等待用户解锁 HarmonyOS 真机；解锁后继续冷启动、数据库迁移和书源管理 smoke。'
Set-PropertyValue $objective.continuationTarget 'activeBoundary' "$issueId 状态为 needs_interaction：真机锁屏阻断，源码和构建保持已通过证据。"
Set-PropertyValue $objective.continuationTarget 'nextTransition' '设备解锁后恢复 Hypium Driver 冷启动 smoke。'
Set-PropertyValue $objective.continuationTarget.queueAudit 'status' 'r4_device_needs_interaction'
Set-PropertyValue $objective.continuationTarget.queueAudit 'currentAnchor' $issueId
Set-PropertyValue $objective.continuationTarget.queueAudit 'candidateStatus' 'device_needs_interaction'
Set-PropertyValue $objective.continuationTarget.queueAudit 'candidateFailureWitnessPath' $EvidencePath

Import-Module -Name (Get-RepositoryPath 'tools/legado-compat/LegadoFullSourceState.psm1') -Force
Sync-LegadoStateDerivedFields -State $state
Write-LegadoStateCheckpoint -Path (Get-RepositoryPath $statePath) -State $state -Depth 80
Write-AtomicJson $objectivePath $objective
& pwsh -NoLogo -NoProfile -NonInteractive -File (Get-RepositoryPath 'tools/legado-compat/Invoke-LegadoCompatibility.ps1') -RefreshDocumentsOnly | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Issue 241 device block document refresh failed.' }
$evidence | ConvertTo-Json -Depth 20
