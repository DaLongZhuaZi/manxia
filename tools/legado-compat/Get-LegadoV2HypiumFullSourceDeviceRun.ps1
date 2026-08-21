[CmdletBinding()]
param(
  [string]$EvidenceDirectory = '',
  [string]$ControlDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($EvidenceDirectory.Length -eq 0) {
  $EvidenceDirectory = Join-Path $PSScriptRoot 'evidence\full-source-v2-hypium-device'
}
if ($ControlDirectory.Length -eq 0) {
  $ControlDirectory = Join-Path $PSScriptRoot 'evidence\full-source-v2-hypium-device-control'
}
$manifestPath = Join-Path $ControlDirectory 'detached-run.json'
$legacyManifestPath = Join-Path $EvidenceDirectory 'detached-run.json'
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$logUtf8 = [System.Text.UTF8Encoding]::new($false, $false)
function Get-LegadoDetachedLogTail {
  param([string]$Path, [int]$MaximumLines = 20)
  if (-not (Test-Path -LiteralPath $Path)) {
    return @()
  }
  $stream = $null
  $reader = $null
  try {
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $reader = [System.IO.StreamReader]::new($stream, $logUtf8, $true)
    $text = $reader.ReadToEnd()
    return @($text -split "`r?`n" | Select-Object -Last $MaximumLines)
  } finally {
    if ($null -ne $reader) { $reader.Dispose() }
    elseif ($null -ne $stream) { $stream.Dispose() }
  }
}
$manifest = $null
if (Test-Path -LiteralPath $manifestPath) {
  $manifest = [System.IO.File]::ReadAllText($manifestPath, $strictUtf8) | ConvertFrom-Json
} elseif (Test-Path -LiteralPath $legacyManifestPath) {
  # Read-only compatibility with manifests written before control artifacts
  # were separated from the immutable source-evidence baseline.
  $manifestPath = $legacyManifestPath
  $manifest = [System.IO.File]::ReadAllText($manifestPath, $strictUtf8) | ConvertFrom-Json
}
$evidenceRoot = Split-Path -Parent $EvidenceDirectory
$runEvidenceDirectory = $EvidenceDirectory
if ($null -ne $manifest) {
  $runEvidenceProperty = $manifest.PSObject.Properties['runEvidenceDirectory']
  if ($null -ne $runEvidenceProperty -and -not [string]::IsNullOrWhiteSpace([string]$runEvidenceProperty.Value)) {
    $runEvidenceDirectory = [System.IO.Path]::GetFullPath((Join-Path $evidenceRoot ([string]$runEvidenceProperty.Value)))
  }
}
$activityPath = Join-Path $runEvidenceDirectory 'run-activity.json'
$activity = $null
if (Test-Path -LiteralPath $activityPath) {
  $activity = [System.IO.File]::ReadAllText($activityPath, $strictUtf8) | ConvertFrom-Json
}
$processRunning = $false
if ($null -ne $manifest -and $null -ne $manifest.PSObject.Properties['processId']) {
  $processRunning = $null -ne (Get-Process -Id ([int]$manifest.processId) -ErrorAction SilentlyContinue)
}
[pscustomobject][ordered]@{
  processRunning = $processRunning
  controlDirectory = $ControlDirectory
  manifestPath = $manifestPath
  manifest = $manifest
  runEvidenceDirectory = $runEvidenceDirectory
  activity = $activity
  # Child-process logs are diagnostic payloads rather than state documents.
  # Decode them explicitly as UTF-8 with replacement so one non-UTF-8 line
  # cannot hide a valid JSON activity checkpoint.
  stdoutTail = Get-LegadoDetachedLogTail -Path (Join-Path $runEvidenceDirectory 'detached-run.stdout.log')
  stderrTail = Get-LegadoDetachedLogTail -Path (Join-Path $runEvidenceDirectory 'detached-run.stderr.log')
} | ConvertTo-Json -Depth 12
