[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Read-Utf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

function Assert-Contract {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Message
  )
  if (-not $Condition) {
    throw "Legado dynamic eval diagnostic contract failed: $Message"
  }
}

$runtime = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html')
Assert-Contract ($runtime.Contains('buildRuntimeFailureDiagnostic')) 'Runtime must expose structural failure diagnostics.'

$node = Get-Command node -ErrorAction SilentlyContinue
Assert-Contract ($null -ne $node) 'Node.js is required for the deterministic eval fixture.'
$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\Test-LegadoDynamicEvalWithDiagnosticFixture.mjs'
$fixtureOutput = (& $node.Source $fixturePath 2>&1 | Out-String).Trim()
Assert-Contract ($LASTEXITCODE -eq 0) "Fixture process failed: $fixtureOutput"
$fixtureJsonLine = @($fixtureOutput -split "`r?`n" | Where-Object { $_.Trim().StartsWith('{') } | Select-Object -Last 1)
Assert-Contract ($fixtureJsonLine.Count -eq 1) "Fixture did not emit a JSON result: $fixtureOutput"
$fixtureJson = $fixtureJsonLine[0] | ConvertFrom-Json
Assert-Contract ([string]$fixtureJson.status -eq 'fixture_failed_as_expected') 'Fixture must reproduce an inner dynamic-eval TypeError.'

# The fields below are deliberately required before any runtime change.  The
# current implementation only reports operation=eval, which is insufficient
# to distinguish outer eval invocation from source-comment execution.
$diagnostic = [string]$fixtureJson.diagnostic
Assert-Contract ($diagnostic -match 'evalPhase=') 'Diagnostic must identify the dynamic-eval phase.'
Assert-Contract ($diagnostic -match 'evalBinding=source_comment') 'Diagnostic must identify source.bookSourceComment binding.'
Assert-Contract ($diagnostic -match 'evalCodeLength=\d+') 'Diagnostic must expose only the evaluated code length.'

[pscustomobject]@{
  status = 'passed'
  contract = 'dynamic_eval_source_comment_diagnostic'
  fixture = $fixtureJson
} | ConvertTo-Json -Compress
