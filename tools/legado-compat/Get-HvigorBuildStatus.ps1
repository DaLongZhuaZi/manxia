[CmdletBinding()]
param(
  [string]$EvidenceDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($EvidenceDirectory.Length -eq 0) {
  $EvidenceDirectory = Join-Path $PSScriptRoot 'evidence\hvigor-detached-build'
}
$manifestPath = Join-Path $EvidenceDirectory 'build-manifest.json'
$stdoutPath = Join-Path $EvidenceDirectory 'build.stdout.log'
$stderrPath = Join-Path $EvidenceDirectory 'build.stderr.log'
$manifest = $null
if (Test-Path -LiteralPath $manifestPath) {
  $manifest = [System.IO.File]::ReadAllText($manifestPath, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
}
$running = $false
if ($null -ne $manifest -and $null -ne $manifest.PSObject.Properties['processId']) {
  $running = $null -ne (Get-Process -Id ([int]$manifest.processId) -ErrorAction SilentlyContinue)
}
function Get-HvigorLogTail {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return @() }
  $stream = $null
  $reader = $null
  try {
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    $reader = [System.IO.StreamReader]::new($stream, [System.Text.UTF8Encoding]::new($false, $false), $true)
    return @($reader.ReadToEnd() -split "`r?`n" | Select-Object -Last 40)
  } finally {
    if ($null -ne $reader) { $reader.Dispose() }
    elseif ($null -ne $stream) { $stream.Dispose() }
  }
}
[pscustomobject][ordered]@{
  processRunning = $running
  manifest = $manifest
  stdoutTail = Get-HvigorLogTail -Path $stdoutPath
  stderrTail = Get-HvigorLogTail -Path $stderrPath
} | ConvertTo-Json -Depth 12
