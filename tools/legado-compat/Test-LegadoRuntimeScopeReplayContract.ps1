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
    throw "Legado runtime scope replay contract failed: $Message"
  }
}

$node = Get-Command node -ErrorAction SilentlyContinue
Assert-Contract ($null -ne $node) 'Node.js is required for the scope replay fixture.'
$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\Test-LegadoRuntimeScopeReplayFixture.mjs'
$fixtureOutput = (& $node.Source $fixturePath 2>&1 | Out-String).Trim()
Assert-Contract ($LASTEXITCODE -eq 0) "Scope replay fixture failed: $fixtureOutput"
Assert-Contract ($fixtureOutput.Contains('"status":"passed"')) 'Scope replay fixture did not pass.'

[pscustomobject]@{
  status = 'passed'
  contract = 'source_scoped_rule_assignment_isolation'
  fixtureOutput = $fixtureOutput
} | ConvertTo-Json -Compress
