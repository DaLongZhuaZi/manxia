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
    throw "Legado dynamic explore Jsoup contract failed: $Message"
  }
}

$runtime = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html')
Assert-Contract ($runtime.Contains('function createRuntimeJsoupElements')) 'Runtime must expose the indexed Jsoup element list.'
Assert-Contract ($runtime.Contains('Object.defineProperty')) 'Jsoup helper methods must be non-enumerable.'
Assert-Contract ($runtime.Contains("ajax: function (url)")) 'java.ajax must be available to dynamic explore scripts.'

$node = Get-Command node -ErrorAction SilentlyContinue
Assert-Contract ($null -ne $node) 'Node.js is required for the deterministic runtime fixture.'
$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\Test-LegadoDynamicExploreJsoupFixture.mjs'
$fixtureOutput = (& $node.Source $fixturePath 2>&1 | Out-String).Trim()
Assert-Contract ($LASTEXITCODE -eq 0) "Runtime fixture failed: $fixtureOutput"
Assert-Contract ($fixtureOutput.Contains('"status":"passed"')) 'Runtime fixture did not report passed.'

[pscustomobject]@{
  status = 'passed'
  contract = 'dynamic_explore_jsoup_ajax_for_in_attr'
  fixtureOutput = $fixtureOutput
} | ConvertTo-Json -Compress
