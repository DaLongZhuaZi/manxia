[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-Utf8Text {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Missing contract input: $Path"
  }
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "Legado HMAC runtime contract failed: $Message"
  }
}

if ($RepositoryRoot.Length -eq 0) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
} else {
  $RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
}
if ($OutputPath.Length -eq 0) {
  $OutputPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\legado-hmac-runtime-contract.json'
}

try {
  $runtime = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html')
  $runtimeV2 = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoRuntimeV2.ets')
  $registry = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoJsApiContractRegistry.ets')
  $fixture = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'entry\src\main\ets\pages\LegadoArkWebConformancePage.ets')
  $runner = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'tools\legado-compat\Invoke-LegadoCompatibility.ps1')

  Assert-Contract ($runtime.Contains('HMacHex: function (data, algorithm, key)')) 'runtime must preserve Legado HMacHex(data, algorithm, key) argument order'
  Assert-Contract ($runtime.Contains("return doHmac(data, key, algorithm || 'HmacMD5');")) 'runtime must pass algorithm and key to the native bridge without swapping them'
  Assert-Contract ($runtime.Contains("throw new Error(response.error || 'CRYPTO_HMAC_FAILED');")) 'runtime must not synthesize pseudo HMAC output after a native bridge failure'
  Assert-Contract ($runtimeV2.Contains("if (upper === 'HMACMD5')")) 'native HMAC bridge must declare HmacMD5 explicitly'
  Assert-Contract ($runtimeV2.Contains("if (upper === 'HMACSHA256')")) 'native HMAC bridge must declare HmacSHA256 explicitly'
  Assert-Contract ($runtimeV2.Contains('UNSUPPORTED_HMAC_ALGORITHM')) 'unknown HMAC algorithms must be structured failures instead of MD5 fallback'
  Assert-Contract ($registry.Contains("this.add('java.HMacHex', LegadoJsApiStatus.SUPPORTED")) 'Registry must permit HMacHex only after native standard-vector evidence exists'
  Assert-Contract ($fixture.Contains('80070713463e7749b90c2dc24911e275')) 'fixture must contain the standard HmacMD5 vector'
  Assert-Contract ($fixture.Contains('f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8')) 'fixture must contain the standard HmacSHA256 vector'
  Assert-Contract ($runner.Contains('fixture-runtime-hmac-contract')) 'full runner must require the real-device HMAC marker'
  $result = [pscustomobject][ordered]@{
    status = 'passed'
    assertions = 10
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
} catch {
  $result = [pscustomobject][ordered]@{
    status = 'failed'
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
}

$directory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $directory)) {
  [void][System.IO.Directory]::CreateDirectory($directory)
}
[System.IO.File]::WriteAllText(
  $OutputPath,
  [string]($result | ConvertTo-Json -Depth 5),
  [System.Text.UTF8Encoding]::new($false)
)
$result | ConvertTo-Json -Depth 5
if ($result.status -ne 'passed') {
  exit 1
}
