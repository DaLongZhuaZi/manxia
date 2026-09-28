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
    throw "Legado V2 bridge failure trace contract failed: $Message"
  }
}

$runtimePath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoRuntimeV2.ets'
$runtime = Read-Utf8Text -Path $runtimePath
$sourceRuntime = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoSourceScriptRuntime.ets')
$traceTypes = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoCompatibilityTypes.ets')
$serializer = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoTraceSerializer.ets')

Assert-Contract ($runtime.Contains('private buildBridgeTraces') -and $runtime.Contains('bridgeTraces: this.buildBridgeTraces(state)')) 'Runtime must return nested bridge traces for both successful and failed JS envelopes.'
Assert-Contract ($runtime.Contains('method?: string') -and $runtime.Contains('headerNames?: string[]')) 'Bridge responses must retain method and header-name metadata without values.'
Assert-Contract ($sourceRuntime.Contains('hasTransportFailure') -and $sourceRuntime.Contains('SCRIPT_NETWORK')) 'Source script classification must promote code-0 HTTP bridge failures to network evidence.'
Assert-Contract ($traceTypes.Contains('class LegadoBridgeTrace') -and $traceTypes.Contains('isTransportFailure')) 'Trace types must distinguish transport failure from received HTTP status.'
Assert-Contract ($serializer.Contains('class RedactedBridgeTrace') -and $serializer.Contains('trace.bridgeTraces')) 'Redacted trace serialization must include nested bridge evidence.'

$node = Get-Command node -ErrorAction SilentlyContinue
Assert-Contract ($null -ne $node) 'Node.js is required to run the deterministic bridge failure fixture.'
$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\Test-LegadoV2BridgeFailureTraceFixture.mjs'
$fixtureOutput = (& $node.Source $fixturePath 2>&1 | Out-String).Trim()
Assert-Contract ($LASTEXITCODE -eq 0) "Bridge failure fixture failed: $fixtureOutput"
Assert-Contract ($fixtureOutput.Contains('"status":"passed"')) 'Bridge failure fixture did not report passed.'

[pscustomobject]@{
  status = 'passed'
  contract = 'nested_bridge_failure_and_http_status_body'
  fixtureOutput = $fixtureOutput
} | ConvertTo-Json -Compress
