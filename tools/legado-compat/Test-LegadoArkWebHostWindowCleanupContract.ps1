[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Assert-Contract {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Message
  )
  if (-not $Condition) {
    throw "Legado ArkWeb host-window cleanup contract failed: $Message"
  }
}

$node = Get-Command node -ErrorAction SilentlyContinue
Assert-Contract ($null -ne $node) 'Node.js is required for the host-window fixture.'
$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\Test-LegadoDynamicExploreOnehuFailureFixture.mjs'
$previousMode = $env:LEGADO_HOST_WINDOW_MODE
try {
  $env:LEGADO_HOST_WINDOW_MODE = 'throw'
  $fixtureOutput = (& $node.Source $fixturePath 2>&1 | Out-String).Trim()
} finally {
  if ($null -eq $previousMode) {
    Remove-Item Env:LEGADO_HOST_WINDOW_MODE -ErrorAction SilentlyContinue
  } else {
    $env:LEGADO_HOST_WINDOW_MODE = $previousMode
  }
}
$fixtureJsonLine = @($fixtureOutput -split "`r?`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
Assert-Contract ($fixtureJsonLine.Count -eq 1) "Fixture did not emit a JSON result: $fixtureOutput"
$fixtureJson = $fixtureJsonLine[0] | ConvertFrom-Json
Assert-Contract ([string]$fixtureJson.status -eq 'deterministic_success') 'Runtime cleanup must tolerate ArkWeb host-window Object.keys behavior.'

[pscustomobject]@{
  status = 'passed'
  contract = 'arkweb_host_window_cleanup'
  fixture = $fixtureJson
} | ConvertTo-Json -Compress
