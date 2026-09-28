[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-Utf8Text {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing input: $Path" }
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Legado timeFormat contract failed: $Message" }
  $script:assertions++
}

if ($RepositoryRoot.Length -eq 0) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
} else {
  $RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
}
if ($OutputPath.Length -eq 0) {
  $OutputPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\legado-time-format-runtime-contract.json'
}

$script:assertions = 0
try {
  $original = Read-Utf8Text (Join-Path $RepositoryRoot 'legado\app\src\main\java\io\legado\app\constant\AppConst.kt')
  $extensions = Read-Utf8Text (Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoJsExtensions.ets')
  $runtime = Read-Utf8Text (Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html')
  $engine = Read-Utf8Text (Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoJsEngine.ets')
  $registry = Read-Utf8Text (Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoJsApiContractRegistry.ets')
  $fixture = Read-Utf8Text (Join-Path $RepositoryRoot 'entry\src\main\ets\pages\LegadoArkWebConformancePage.ets')
  $runner = Read-Utf8Text (Join-Path $RepositoryRoot 'tools\legado-compat\Invoke-LegadoCompatibility.ps1')

  Assert-Contract ($original.Contains('FastDateFormat.getInstance("yyyy/MM/dd HH:mm")')) 'pinned original default format must be yyyy/MM/dd HH:mm'
  Assert-Contract ($extensions.Contains("this.formatJavaDate(date, 'yyyy/MM/dd HH:mm', false)")) 'ArkTS extension must use the original default format'
  Assert-Contract ($extensions.Contains('const date = new Date(time + offset);')) 'ArkTS UTC offset must preserve SimpleTimeZone millisecond semantics'
  Assert-Contract ($runtime.Contains("formatDate(new Date(n), 'yyyy/MM/dd HH:mm'")) 'raw runtime must not use locale-dependent/default ISO format'
  Assert-Contract ($engine.Contains("this.__formatLegadoDate(time, 'yyyy/MM/dd HH:mm', false, 0)")) 'LegadoJsEngine primary bridge must use the original default format'
  Assert-Contract ($registry.Contains("this.add('java.timeFormat', LegadoJsApiStatus.SUPPORTED")) 'timeFormat must be visible as a supported contract only after fixture coverage'
  Assert-Contract ($fixture.Contains('java.timeFormat(0)') -and $fixture.Contains('1970-01-01 00:00')) 'ArkWeb fixture must verify deterministic UTC and local format shape'
  Assert-Contract ($runner.Contains('get-encodeURI-md5-source-fields-time-format')) 'full gate must require the time-format marker'

  $result = [pscustomobject][ordered]@{
    status = 'passed'
    assertions = $script:assertions
    generatedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    defaultPattern = 'yyyy/MM/dd HH:mm'
    utcOffsetUnit = 'milliseconds'
  }
} catch {
  $result = [pscustomobject][ordered]@{
    status = 'failed'
    assertions = $script:assertions
    error = $_.Exception.Message
    generatedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
  }
}

$directory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
[System.IO.File]::WriteAllText($OutputPath, [string]($result | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Depth 6
if ($result.status -ne 'passed') { exit 1 }
