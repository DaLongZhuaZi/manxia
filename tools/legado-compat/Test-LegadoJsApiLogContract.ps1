[CmdletBinding()]
param([string]$RepoRoot = '', [string]$ResultPath = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Legado JS log contract failed: $Message" }
}

function Read-Utf8Text {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) "missing file: $Path"
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

if ($RepoRoot.Length -eq 0) {
  $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}
if ($ResultPath.Length -eq 0) {
  $ResultPath = Join-Path $RepoRoot 'tools\legado-compat\evidence\legado-js-api-log-contract.json'
}

$registryPath = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Novel\LegadoJsApiContractRegistry.ets'
$enginePath = Join-Path $RepoRoot 'entry\src\main\ets\Framework\Novel\LegadoJsEngine.ets'

try {
  $registry = Read-Utf8Text -Path $registryPath
  $engine = Read-Utf8Text -Path $enginePath
  Assert-Contract ($registry.Contains("this.add('java.log', LegadoJsApiStatus.SUPPORTED")) 'java.log must be declared as supported'
  Assert-Contract ($engine.Contains("log: function(msg) { console.log('[JS]', msg); return msg; }")) 'WebView JS runtime must implement java.log'
  Assert-Contract ($engine.Contains('log: function(msg) { return msg; }')) 'native JS runtime must implement java.log'
  $result = [pscustomobject][ordered]@{ status = 'passed'; assertions = 3; generatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
} catch {
  $result = [pscustomobject][ordered]@{ status = 'failed'; error = $_.Exception.Message; generatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
}

$directory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
[System.IO.File]::WriteAllText($ResultPath, [string]($result | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Depth 5
if ($result.status -ne 'passed') { exit 1 }
