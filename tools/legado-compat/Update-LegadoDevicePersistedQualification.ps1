[CmdletBinding()]
param(
  [string]$StatePath = '',
  [Parameter(Mandatory = $true)]
  [string]$ProbeResultPath,
  [string]$RepositoryRoot = '',
  [switch]$SkipDocumentRefresh
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-RequiredPropertyValue {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) {
    throw "Missing probe result object for property: $Name"
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) {
    throw "Missing probe result property: $Name"
  }
  return $property.Value
}

function Get-Utf8Json {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Required JSON evidence is missing: $Path"
  }
  $text = [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
  return $text | ConvertFrom-Json
}

function Convert-ToRepositoryRelativePath {
  param([string]$Path, [string]$Root)
  $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
  $resolvedRoot = (Resolve-Path -LiteralPath $Root).Path.TrimEnd('\\')
  if (-not $resolvedPath.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Probe evidence must be stored under the repository root.'
  }
  return $resolvedPath.Substring($resolvedRoot.Length).TrimStart('\\').Replace('\\', '/')
}

if ($RepositoryRoot.Length -eq 0) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\\..')).Path
}
if ($StatePath.Length -eq 0) {
  $StatePath = Join-Path $PSScriptRoot 'state\\full-source-validation-state.json'
}

$modulePath = Join-Path $PSScriptRoot 'LegadoFullSourceState.psm1'
Import-Module -Name $modulePath -Force
$state = Read-LegadoJsonFile -Path $StatePath
if ($null -eq $state) {
  throw "Machine fact state cannot be read: $StatePath"
}
$probe = Get-Utf8Json -Path $ProbeResultPath
if ([string](Get-RequiredPropertyValue -Object $probe -Name 'status') -ne 'passed') {
  throw 'Device-persisted qualification cannot use a failed or incomplete management probe.'
}
if (-not [bool](Get-RequiredPropertyValue -Object $probe -Name 'driver_closed')) {
  throw 'Device-persisted qualification requires a probe that released UiDriver.'
}

$baseline = Get-RequiredPropertyValue -Object $state -Name 'baseline'
$expectedSourceCount = [int](Get-RequiredPropertyValue -Object $baseline -Name 'sourceCount')
$totalText = ([string](Get-RequiredPropertyValue -Object $probe -Name 'total_count_text')).Trim()
$verifiedText = ([string](Get-RequiredPropertyValue -Object $probe -Name 'verified_count_text')).Trim()
$policyText = [string](Get-RequiredPropertyValue -Object $probe -Name 'policy_summary_text')
if ($totalText -notmatch '^\d+$') {
  throw 'Management total count is not an integer.'
}
if ($verifiedText -notmatch '^(?<verified>\d+)\/(?<denominator>\d+)$') {
  throw 'Management complete-verification count must use verified/total format.'
}
$displayedTotal = [int]$totalText
$verifiedCount = [int]$Matches.verified
$verificationDenominator = [int]$Matches.denominator
if ($displayedTotal -ne $expectedSourceCount -or $verificationDenominator -ne $expectedSourceCount) {
  throw "Management aggregate denominator mismatch: baseline=$expectedSourceCount displayed=$displayedTotal verifiedDenominator=$verificationDenominator"
}
if ($verifiedCount -gt $expectedSourceCount) {
  throw 'Management verified count exceeds the immutable source baseline.'
}
if (-not $policyText.Contains('V2 全量切换')) {
  throw 'Management probe does not prove the required V2 full-cutover policy.'
}
$packageName = [string](Get-RequiredPropertyValue -Object $probe -Name 'package')
if ($packageName -ne 'com.dlzz.manxia') {
  throw "Unexpected management probe package: $packageName"
}

$relativeEvidencePath = Convert-ToRepositoryRelativePath -Path $ProbeResultPath -Root $RepositoryRoot
$evidenceSha256 = [string](Get-FileHash -LiteralPath $ProbeResultPath -Algorithm SHA256).Hash.ToLowerInvariant()
$deviceId = [string](Get-RequiredPropertyValue -Object $probe -Name 'device_sn')
$deviceIdSha256 = (Get-LegadoSha256ForText -Value $deviceId).ToLowerInvariant()
$qualification = [pscustomobject][ordered]@{
  schemaVersion = 1
  observationStatus = if ($verifiedCount -eq $expectedSourceCount) { 'fully_verified' } else { 'observed_incomplete' }
  observationKind = 'management_summary_aggregate'
  totalSourceCount = $displayedTotal
  verificationRows = $verifiedCount
  completeVerificationCount = $verifiedCount
  verificationDenominator = $verificationDenominator
  executionPolicy = 'v2_full_cutover'
  sourceIdentityCoverage = 'aggregate_only'
  evidencePath = $relativeEvidencePath
  evidenceSha256 = $evidenceSha256
  deviceIdSha256 = $deviceIdSha256
  clockStatus = 'host_wall_clock_untrusted'
  observedAtUtc = ''
}
$state | Add-Member -NotePropertyName 'devicePersistedQualification' -NotePropertyValue $qualification -Force
Sync-LegadoStateDerivedFields -State $state
Write-LegadoStateCheckpoint -Path $StatePath -State $state -Depth 30

if (-not $SkipDocumentRefresh) {
  $compatibilityScript = Join-Path $PSScriptRoot 'Invoke-LegadoCompatibility.ps1'
  & $compatibilityScript -RefreshDocumentsOnly
  if ($LASTEXITCODE -ne 0) {
    throw 'Compatibility document refresh failed after device qualification update.'
  }
}

[pscustomobject][ordered]@{
  status = 'passed'
  statePath = $StatePath
  observationStatus = $qualification.observationStatus
  totalSourceCount = $qualification.totalSourceCount
  completeVerificationCount = $qualification.completeVerificationCount
  verificationDenominator = $qualification.verificationDenominator
  executionPolicy = $qualification.executionPolicy
  evidencePath = $qualification.evidencePath
} | ConvertTo-Json -Compress
