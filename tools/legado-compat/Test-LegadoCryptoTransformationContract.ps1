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

function Read-Utf8Json {
  param([string]$Path)
  return (Read-Utf8Text -Path $Path) | ConvertFrom-Json
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "CRYPTO_CONTRACT_FAILED:$Message"
  }
}

if ($RepositoryRoot.Length -eq 0) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
} else {
  $RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
}
if ($OutputPath.Length -eq 0) {
  $OutputPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-crypto-002-static-contract-20260808.json'
}

$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\v2-crypto-002-transformation-matrix.json'
$enginePath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoJsEngine.ets'
$runtimePath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoRuntimeV2.ets'
$rawRuntimePath = Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html'
$registryPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoJsApiContractRegistry.ets'

$result = $null
try {
  $fixture = Read-Utf8Json -Path $fixturePath
  $engine = Read-Utf8Text -Path $enginePath
  $runtime = Read-Utf8Text -Path $runtimePath
  $rawRuntime = Read-Utf8Text -Path $rawRuntimePath
  $registry = Read-Utf8Text -Path $registryPath
  $assertions = 0
  $cases = @($fixture.transformations)

  Assert-Contract ([string]$fixture.issueId -eq 'ISSUE-COMPAT-CRYPTO-002') 'fixture issue id must remain bound to the active issue'; $assertions++
  Assert-Contract ([bool]$fixture.semanticMatchAllowed -eq $false) 'static crypto contract must not authorize semantic_match'; $assertions++
  Assert-Contract ($cases.Count -eq 8) 'fixture must cover supported, malformed and unknown transformation classes'; $assertions++
  Assert-Contract ([string]$fixture.keySemantics.stringKeyEncoding -eq 'UTF-8') 'string keys must use UTF-8 bytes'; $assertions++
  Assert-Contract ([string]$fixture.keySemantics.plaintextFallback -eq 'forbidden') 'plaintext fallback is forbidden'; $assertions++

  $engineCryptoBlocks = ([regex]::Matches($engine, 'var __createSymmetricCrypto = function\(transformation, keyValue, ivValue\)')).Count
  Assert-Contract ($engineCryptoBlocks -eq 2) 'standard and native JSVM must each own one crypto implementation'; $assertions++
  Assert-Contract ($engine.Contains('UNSUPPORTED_SYMMETRIC_TRANSFORMATION')) 'embedded runtime must reject transformations with extra segments'; $assertions++
  Assert-Contract ($engine.Contains("algorithmToken === 'DESEDE' || algorithmToken === '3DES'")) 'embedded runtime must recognize DESede/3DES explicitly'; $assertions++
  Assert-Contract ($engine.Contains("? 'TripleDES'")) 'embedded runtime must map DESede to CryptoJS TripleDES'; $assertions++
  Assert-Contract ($engine.Contains('UNSUPPORTED_SYMMETRIC_ALGORITHM')) 'embedded runtime must classify unknown algorithms'; $assertions++
  Assert-Contract ($engine.Contains('UNSUPPORTED_SYMMETRIC_MODE')) 'embedded runtime must classify unknown modes'; $assertions++
  Assert-Contract ($engine.Contains('UNSUPPORTED_SYMMETRIC_PADDING')) 'embedded runtime must classify unknown paddings'; $assertions++
  Assert-Contract ($engine.Contains('__decodeSymmetricCryptoInput')) 'embedded runtime must separate string-key encoding from decrypt input decoding'; $assertions++
  Assert-Contract (([regex]::Matches($engine, 'INVALID_SYMMETRIC_BLOCK_LENGTH')).Count -eq 2) 'NoPadding must reject non-block-aligned input in both embedded runtimes'; $assertions++
  Assert-Contract (-not $engine.Contains("upper.indexOf('DES') >= 0 && upper.indexOf('AES') < 0 ? 'DES' : 'AES'")) 'legacy DES/AES classifier must be removed'; $assertions++
  Assert-Contract (-not $engine.Contains('var fallbackBytes = function(input, encrypted)')) 'plaintext fallback helper must be removed'; $assertions++
  Assert-Contract (-not $engine.Contains('return fallbackBytes(input, false)')) 'encrypt failures must not return input bytes'; $assertions++
  Assert-Contract (-not $engine.Contains('return fallbackBytes(input, true)')) 'decrypt failures must not return input bytes'; $assertions++

  Assert-Contract ($runtime.Contains('parts.length > 3')) 'native bridge must reject extra transformation segments'; $assertions++
  Assert-Contract ($runtime.Contains("keyAlgorithm = '3DES192'")) 'native bridge must retain explicit 3DES key mapping'; $assertions++
  Assert-Contract ($runtime.Contains('UNSUPPORTED_SYMMETRIC_ALGORITHM')) 'native bridge must reject unsupported algorithms'; $assertions++
  Assert-Contract ($rawRuntime.Contains("throw new Error(response.error || 'CRYPTO_SYMMETRIC_FAILED');")) 'ArkWeb bridge must propagate structured crypto failure'; $assertions++
  Assert-Contract ($registry.Contains('AES、DES64、3DES192')) 'registry must expose the bounded symmetric capability matrix'; $assertions++
  Assert-Contract ($registry.Contains('其他 transformation') -and $registry.Contains('CRYPTO_SYMMETRIC_FAILED')) 'registry must describe explicit rejection of unsupported transformations'; $assertions++

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    issueId = [string]$fixture.issueId
    status = 'passed'
    verificationPolicy = [string]$fixture.verificationPolicy
    semanticMatchAllowed = [bool]$fixture.semanticMatchAllowed
    assertions = $assertions
    cryptoBlocks = $engineCryptoBlocks
    fixtureCases = $cases.Count
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    issueId = 'ISSUE-COMPAT-CRYPTO-002'
    status = 'failed'
    verificationPolicy = 'static_source_contract_only;runtime_regression_deferred_to_R4'
    semanticMatchAllowed = $false
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
  [string]($result | ConvertTo-Json -Depth 8),
  [System.Text.UTF8Encoding]::new($false)
)
$result | ConvertTo-Json -Depth 8
if ($result.status -ne 'passed') {
  exit 1
}
