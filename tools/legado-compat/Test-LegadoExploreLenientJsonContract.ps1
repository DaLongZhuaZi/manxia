[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = '',
  [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
if ([string]::IsNullOrWhiteSpace($FixturePath)) {
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-explore-lenient-json.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-explore-lenient-json.json'
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "LEGADO_EXPLORE_LENIENT_JSON_CONTRACT_FAILED:$Message" }
}

function Normalize-ExploreJsonControls {
  param([string]$Value)
  $builder = [System.Text.StringBuilder]::new()
  $inString = $false
  $escaping = $false
  for ($index = 0; $index -lt $Value.Length; $index++) {
    $character = $Value[$index]
    if (-not $inString) {
      [void]$builder.Append($character)
      if ($character -eq '"') { $inString = $true }
      continue
    }
    if ($escaping) {
      [void]$builder.Append($character)
      $escaping = $false
      continue
    }
    if ($character -eq '\') {
      [void]$builder.Append($character)
      $escaping = $true
      continue
    }
    if ($character -eq '"') {
      [void]$builder.Append($character)
      $inString = $false
      continue
    }
    $code = [int][char]$character
    if ($code -ge 0x20) {
      [void]$builder.Append($character)
    } elseif ($character -eq "`n") {
      [void]$builder.Append('\n')
    } elseif ($character -eq "`r") {
      [void]$builder.Append('\r')
    } elseif ($character -eq "`t") {
      [void]$builder.Append('\t')
    } elseif ($character -eq [char]8) {
      [void]$builder.Append('\b')
    } elseif ($character -eq [char]12) {
      [void]$builder.Append('\f')
    } else {
      [void]$builder.Append(('\u{0:x4}' -f $code))
    }
  }
  return $builder.ToString()
}

function Write-Result {
  param([object]$Value)
  $directory = Split-Path -Parent $ResultPath
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [void][System.IO.Directory]::CreateDirectory($directory) }
  $temporaryPath = $ResultPath + '.tmp-' + [Guid]::NewGuid().ToString('N')
  try {
    [System.IO.File]::WriteAllText($temporaryPath, [string]($Value | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
    [System.IO.File]::Move($temporaryPath, $ResultPath, $true)
  } finally {
    if ([System.IO.File]::Exists($temporaryPath)) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$assertions = 0
try {
  $parserPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoSourceParser.ets'
  Assert-Contract (Test-Path -LiteralPath $FixturePath -PathType Leaf) 'fixture is missing'; $assertions++
  Assert-Contract (Test-Path -LiteralPath $parserPath -PathType Leaf) 'parser is missing'; $assertions++
  $fixture = [System.IO.File]::ReadAllText($FixturePath, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
  $implementation = [System.IO.File]::ReadAllText($parserPath, [System.Text.UTF8Encoding]::new($false, $true))
  Assert-Contract ([int]$fixture.schemaVersion -eq 1) 'fixture schema version must be 1'; $assertions++
  Assert-Contract ([string]$fixture.contract -eq 'legado_explore_lenient_json_controls') 'fixture contract is wrong'; $assertions++
  Assert-Contract ($implementation.Contains('normalizeExploreKindsJson')) 'parser must normalize lenient Explore JSON'; $assertions++
  Assert-Contract ($implementation.Contains('LEGADO_EXPLORE_KINDS_JSON_PARSE_FAILED')) 'parser must emit a classified JSON parse failure'; $assertions++
  Assert-Contract ($implementation.Contains('character === ''\n''')) 'parser must normalize literal line feeds inside strings'; $assertions++
  Assert-Contract ($implementation.Contains('character === ''\t''')) 'parser must normalize literal tabs inside strings'; $assertions++
  $raw = [string]$fixture.rawExploreKinds
  $strictRejected = $false
  try { [void][System.Text.Json.JsonDocument]::Parse($raw) } catch { $strictRejected = $true }
  Assert-Contract $strictRejected 'fixture must be invalid strict JSON before normalization'; $assertions++
  $normalized = Normalize-ExploreJsonControls -Value $raw
  $parsed = [System.Text.Json.JsonDocument]::Parse($normalized)
  $root = $parsed.RootElement
  Assert-Contract ($root.GetArrayLength() -eq [int]$fixture.expected.kindCount) 'normalized array count differs'; $assertions++
  Assert-Contract ($root[0].GetProperty('title').GetString() -eq [string]$fixture.expected.firstTitle) 'first title differs'; $assertions++
  Assert-Contract ($root[0].GetProperty('url').GetString().Contains([string]$fixture.expected.firstUrlContains)) 'POST URL option was not preserved'; $assertions++
  Assert-Contract ($root[0].GetProperty('style').GetProperty('layout_flexGrow').GetInt32() -eq [int]$fixture.expected.firstStyleFlexGrow) 'style was not preserved'; $assertions++
  Assert-Contract ($root[1].GetProperty('url').GetString() -eq [string]$fixture.expected.secondUrl) 'decorative empty URL was not preserved'; $assertions++
  $parsed.Dispose()
  $result = [ordered]@{ status = 'passed'; contract = [string]$fixture.contract; assertions = $assertions; generatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
  Write-Result -Value $result
  $result | ConvertTo-Json -Depth 8
} catch {
  $result = [ordered]@{ status = 'failed'; contract = 'legado_explore_lenient_json_controls'; assertions = $assertions; error = $_.Exception.Message; generatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
  Write-Result -Value $result
  $result | ConvertTo-Json -Depth 8
  exit 1
}
