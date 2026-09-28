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
    throw "Legado V2 source-header ajax contract failed: $Message"
  }
}

$runtimePath = Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html'
$runtime = Read-Utf8Text -Path $runtimePath

# This fixture models the Legado contract used by source 9EE056...: a dynamic
# source.header produces a bearer header, java.ajax() inherits it, and an
# explicit URL option can override the same header name.
Assert-Contract ($runtime.Contains('function resolveSourceHeaders')) 'Runtime must expose one source-scoped header resolver.'
Assert-Contract ($runtime.Contains('var sourceHeaderCache')) 'Runtime must cache the resolved source header within one workflow execution.'
Assert-Contract ($runtime.Contains('resolveSourceHeaders(sourceSnapshot, source, runtimeObjectsRef')) 'Source header resolver must execute against the current source scope.'
Assert-Contract ($runtime.Contains('Object.keys(sourceHeaders || {}).forEach(function (key) { actualHeaders[key] = sourceHeaders[key]; });')) 'java.ajax transport must inherit resolved source headers before URL-option headers.'
Assert-Contract ($runtime.Contains('function doHttp(url, method, body, headers)')) 'HTTP bridge must keep a single merge point for ajax/connect/post/head.'
Assert-Contract ($runtime.Contains('sourceHeaderCache')) 'Header resolution must be reused by every java.ajax call in the workflow.'

$node = Get-Command node -ErrorAction SilentlyContinue
Assert-Contract ($null -ne $node) 'Node.js is required to run the deterministic ArkWeb runtime fixture.'
$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\Test-LegadoV2SourceHeaderAjaxFixture.mjs'
$fixtureOutput = (& $node.Source $fixturePath 2>&1 | Out-String).Trim()
Assert-Contract ($LASTEXITCODE -eq 0) "Runtime fixture failed: $fixtureOutput"
Assert-Contract ($fixtureOutput.Contains('"status":"passed"')) 'Runtime fixture did not report a passed source-header/ajax contract.'

[pscustomobject]@{
  status = 'passed'
  contract = 'dynamic_source_header_inherited_by_java_ajax'
  precedence = 'explicit_url_option_overrides_source_header'
  scope = 'workflow'
  fixtureSource = '9EE05687402AA864A236E7C05A569CFB1A2AD6B41DBC53EBB158AE857F799ED1'
} | ConvertTo-Json -Compress
