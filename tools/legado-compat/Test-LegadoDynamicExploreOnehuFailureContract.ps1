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
    throw "Legado exact Onehu source contract failed: $Message"
  }
}

$node = Get-Command node -ErrorAction SilentlyContinue
Assert-Contract ($null -ne $node) 'Node.js is required for the deterministic source fixture.'
$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\Test-LegadoDynamicExploreOnehuFailureFixture.mjs'
$fixtureOutput = (& $node.Source $fixturePath 2>&1 | Out-String).Trim()
$fixtureJsonLine = @($fixtureOutput -split "`r?`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
Assert-Contract ($fixtureJsonLine.Count -eq 1) "Fixture did not emit a JSON result: $fixtureOutput"
$fixtureJson = $fixtureJsonLine[0] | ConvertFrom-Json
Assert-Contract ($LASTEXITCODE -eq 0) "Fixture process failed: $fixtureOutput"
Assert-Contract ([string]$fixtureJson.status -eq 'deterministic_success') 'The exact source fixture must remain executable in the deterministic runtime.'

[pscustomobject]@{
  status = 'passed'
  contract = 'dynamic_explore_onehu_exact_source_fixture'
  fixture = $fixtureJson
} | ConvertTo-Json -Compress
