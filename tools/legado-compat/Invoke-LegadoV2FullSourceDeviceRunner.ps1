[CmdletBinding()]
param(
  [string]$HdcPath = 'F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
  [string]$Device = '',
  [string]$PythonPath = '',
  [string]$SourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json',
  [string]$StatePath = '',
  [string]$LegacyGovernancePath = '',
  [string]$LegadoRepositoryPath = 'F:\DevEcoStudioProject\manxia\legado',
  [string]$EvidenceDirectory = '',
  [string]$RunActivityPath = '',
  [string]$RunSummaryPath = '',
  [ValidateSet('safe_search_only', 'safe_read_path', 'full_workflow')]
  [string]$ExecutionProfile = 'safe_search_only',
  [ValidateRange(1, 458)]
  [int]$MaxSources = 458,
  [ValidateRange(-1, 457)]
  [int]$OnlyOrdinal = -1,
  [ValidateRange(1, 60)]
  [int]$MinRequestIntervalSeconds = 2,
  [ValidateRange(1, 60)]
  [int]$DeviceLeaseTimeoutSeconds = 15,
  [string]$SearchKeyword = '斗破苍穹',
  [bool]$RunReadinessAudit = $true,
  [bool]$RequireFreshReadiness = $true,
  [switch]$AllowIdempotentPostSearch,
  [bool]$ReferenceOnFailure = $true,
  [string]$ReferenceAdbPath = 'G:\Android\Sdk\platform-tools\adb.exe',
  [string]$ReferenceSerial = 'emulator-5560',
  [switch]$RevalidateTerminalSources
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'


if ($RunReadinessAudit) {
  Write-Warning 'V2_HYPIUM_READINESS_AUDIT_REQUIRED: the canonical readiness state is consumed; this UI runner does not perform device launch or database mutation.'
}

$implementationPath = Join-Path $PSScriptRoot 'Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1'
if (-not (Test-Path -LiteralPath $implementationPath)) {
  throw 'V2_HYPIUM_RUNNER_IMPLEMENTATION_MISSING'
}

$forward = @{
  HdcPath = $HdcPath
  Device = $Device
  PythonPath = $PythonPath
  SourcePackagePath = $SourcePackagePath
  StatePath = $StatePath
  LegacyGovernancePath = $LegacyGovernancePath
  LegadoRepositoryPath = $LegadoRepositoryPath
  EvidenceDirectory = $EvidenceDirectory
  RunActivityPath = $RunActivityPath
  ExecutionProfile = $ExecutionProfile
  MaxSources = $MaxSources
  OnlyOrdinal = $OnlyOrdinal
  MinRequestIntervalSeconds = $MinRequestIntervalSeconds
  RequireFreshReadiness = $RequireFreshReadiness
}
if ($AllowIdempotentPostSearch) { $forward.AllowIdempotentPostSearch = $true }
if ($RevalidateTerminalSources) { $forward.RevalidateTerminalSources = $true }

& $implementationPath @forward
exit $LASTEXITCODE
