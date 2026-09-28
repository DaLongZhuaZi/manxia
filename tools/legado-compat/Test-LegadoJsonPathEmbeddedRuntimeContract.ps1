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
  $OutputPath = Join-Path $PSScriptRoot 'evidence\legado-jsonpath-embedded-runtime-contract-20260807.json'
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
    throw "Legado embedded JSONPath contract failed: $Message"
  }
}

$enginePath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoJsEngine.ets'
$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-jsonpath-embedded-runtime.json'
$engine = Read-Utf8Text -Path $enginePath
$fixture = (Read-Utf8Text -Path $fixturePath) | ConvertFrom-Json

Assert-Contract ($fixture.contract -eq 'legado_jsonpath_embedded_runtime') 'fixture contract id changed'
Assert-Contract ($fixture.cases.Count -eq 4) 'fixture must keep four traversal witnesses'
Assert-Contract (@($fixture.requiredPaths | Where-Object { $_ -eq 'buildScript' }).Count -eq 1) 'standard path witness missing'
Assert-Contract (@($fixture.requiredPaths | Where-Object { $_ -eq 'buildNativeScript' }).Count -eq 1) 'native path witness missing'

$standardStart = $engine.IndexOf('var __applyJsonPathTokens = function', [System.StringComparison]::Ordinal)
$nativeStart = $engine.IndexOf('var __nativeApplyJsonPathTokens = function', [System.StringComparison]::Ordinal)
$standardEnd = if ($standardStart -ge 0) { $engine.IndexOf('var __getJsonPathValues = function', $standardStart, [System.StringComparison]::Ordinal) } else { -1 }
$nativeEnd = if ($nativeStart -ge 0) { $engine.IndexOf('var __nativeJsonPathValues = function', $nativeStart, [System.StringComparison]::Ordinal) } else { -1 }
Assert-Contract ($standardStart -ge 0 -and $standardEnd -gt $standardStart) 'standard JSONPath helper boundaries missing'
Assert-Contract ($nativeStart -ge 0 -and $nativeEnd -gt $nativeStart) 'native JSONPath helper boundaries missing'

$standardBody = $engine.Substring($standardStart, $standardEnd - $standardStart)
$nativeBody = $engine.Substring($nativeStart, $nativeEnd - $nativeStart)

Assert-Contract ($standardBody.Contains("remaining.indexOf('..') === 0")) 'standard path must support nested recursive descent'
Assert-Contract ($nativeBody.Contains("remaining.indexOf('..') === 0")) 'native path must support nested recursive descent'
Assert-Contract ($standardBody.Contains('sliceStep') -and $standardBody.Contains('sliceParts')) 'standard path must support array slices'
Assert-Contract ($nativeBody.Contains('sliceStep') -and $nativeBody.Contains('sliceParts')) 'native path must support array slices'
Assert-Contract ($standardBody.Contains('Object.keys(value).forEach')) 'standard wildcard must enumerate object values'
Assert-Contract ($nativeBody.Contains('Object.keys(currentValue).forEach')) 'native wildcard must enumerate object values'

$result = [ordered]@{
  schemaVersion = 1
  generatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'")
  status = 'passed'
  contract = [string]$fixture.contract
  assertions = 12
  engineSha256 = (Get-FileHash -LiteralPath $enginePath -Algorithm SHA256).Hash.ToUpperInvariant()
  fixtureSha256 = (Get-FileHash -LiteralPath $fixturePath -Algorithm SHA256).Hash.ToUpperInvariant()
  paths = @('buildScript', 'buildNativeScript')
  cases = @($fixture.cases | ForEach-Object { [string]$_.rule })
  reproduction = 'pwsh -File tools/legado-compat/Test-LegadoJsonPathEmbeddedRuntimeContract.ps1'
}

$directory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $directory)) {
  [void][System.IO.Directory]::CreateDirectory($directory)
}
$temporaryPath = "$OutputPath.tmp-$PID"
[System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::Move($temporaryPath, $OutputPath, $true)
$result | ConvertTo-Json -Compress
