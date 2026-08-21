[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $PSScriptRoot 'evidence\legado-jsonpath-runtime-extended-execution-20260807.json'
}

$node = Get-Command node -ErrorAction Stop
$scriptPath = Join-Path $PSScriptRoot 'Test-LegadoJsonPathRuntimeExtendedFixture.mjs'
$runtimePath = Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html'
$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-jsonpath-bridge.json'
$output = & $node.Source $scriptPath
if ($LASTEXITCODE -ne 0) {
  throw "Legado JSONPath extended Runtime fixture failed with exit code $LASTEXITCODE"
}
$jsonLine = @($output | Where-Object { $_ -match '^\{"status":"passed"' } | Select-Object -Last 1)
if ($jsonLine.Count -ne 1) { throw 'Legado JSONPath extended Runtime fixture did not emit a machine-readable pass result' }
$fixtureResult = $jsonLine[0] | ConvertFrom-Json
if ([string]$fixtureResult.contract -ne 'legado_jsonpath_runtime_extended_execution') {
  throw 'Unexpected JSONPath extended Runtime fixture contract identifier'
}
$result = [ordered]@{
  schemaVersion = 1
  generatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'")
  status = 'passed'
  contract = [string]$fixtureResult.contract
  assertions = [int]$fixtureResult.assertions
  runtimeSha256 = (Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash.ToUpperInvariant()
  fixtureSha256 = (Get-FileHash -LiteralPath $fixturePath -Algorithm SHA256).Hash.ToUpperInvariant()
  nodeVersion = (& $node.Source '--version').Trim()
  result = $fixtureResult.result
  fixture = 'tools/legado-compat/fixtures/legado-jsonpath-bridge.json'
  legadoReferenceBasis = @(
    'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSonPath.kt',
    'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeRule.kt'
  )
  referenceInstrumentation = 'pending_fresh_androidtest_apk'
  reproduction = 'node tools/legado-compat/Test-LegadoJsonPathRuntimeExtendedFixture.mjs'
}
$directory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
$temporaryPath = "$OutputPath.tmp-$PID"
[System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::Move($temporaryPath, $OutputPath, $true)
$result | ConvertTo-Json -Compress
