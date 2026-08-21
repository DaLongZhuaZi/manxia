[CmdletBinding()]
param(
  [string]$SourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json',
  [string]$StatePath = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $PSScriptRoot 'evidence\legado-jsonpath-runtime-affected-source-set-20260807.json'
}
if ([string]::IsNullOrWhiteSpace($StatePath)) {
  $StatePath = Join-Path $PSScriptRoot 'state\full-source-validation-state.json'
}

function Get-Sha256Text {
  param([Parameter(Mandatory = $true)][string]$Value)
  $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Value)
  $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
  return ([BitConverter]::ToString($hash) -replace '-', '').ToUpperInvariant()
}

function Add-StringHit {
  param(
    [string]$Value,
    [string]$Path,
    [System.Collections.Generic.List[object]]$Hits
  )
  if ($Value -notmatch '(?i)java\.(getString|getStringList)') { return }
  $jsonPaths = [regex]::Matches($Value, '\$\.[A-Za-z0-9_$.-]+(?:\[\*\]|\[\d+\])?(?:\.[A-Za-z0-9_$.-]+|\[\*\]|\[\d+\])*') |
    ForEach-Object { $_.Value } | Select-Object -Unique
  if (@($jsonPaths).Count -eq 0) { return }
  [void]$Hits.Add([pscustomobject][ordered]@{
    path = $Path
    valueSha256 = Get-Sha256Text -Value $Value
    jsonPathPatterns = @($jsonPaths)
  })
}

function Visit-JsonValue {
  param(
    [object]$Value,
    [string]$Path,
    [System.Collections.Generic.List[object]]$Hits
  )
  if ($null -eq $Value) { return }
  if ($Value -is [string]) {
    Add-StringHit -Value ([string]$Value) -Path $Path -Hits $Hits
    return
  }
  if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
    $index = 0
    foreach ($item in $Value) {
      Visit-JsonValue -Value $item -Path "$Path[$index]" -Hits $Hits
      $index++
    }
    return
  }
  foreach ($property in @($Value.PSObject.Properties)) {
    Visit-JsonValue -Value $property.Value -Path "$Path.$($property.Name)" -Hits $Hits
  }
}

$raw = [System.IO.File]::ReadAllText($SourcePackagePath, [System.Text.UTF8Encoding]::new($false, $true))
$sources = @($raw | ConvertFrom-Json)
$state = Get-Content -LiteralPath $StatePath -Raw -Encoding utf8 | ConvertFrom-Json
$stateRecords = @($state.sources)
$records = New-Object 'System.Collections.Generic.List[object]'
for ($ordinal = 0; $ordinal -lt $sources.Count; $ordinal++) {
  $source = $sources[$ordinal]
  $hits = New-Object 'System.Collections.Generic.List[object]'
  Visit-JsonValue -Value $source -Path '$' -Hits $hits
  if ($hits.Count -le 0) { continue }
  $stateRecord = $stateRecords | Where-Object { [int]$_.ordinal -eq $ordinal } | Select-Object -First 1
  if ($null -eq $stateRecord) { throw "STATE_RECORD_MISSING:$ordinal" }
  [void]$records.Add([pscustomobject][ordered]@{
    ordinal = $ordinal
    sourceId = [string]$stateRecord.sourceId
    sourceName = [string]$source.bookSourceName
    sourceType = [int]$source.bookSourceType
    hitCount = $hits.Count
    hits = $hits.ToArray()
  })
}

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  generatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'")
  sourcePackageSha256 = Get-Sha256Text -Value $raw
  sourceCount = $sources.Count
  affectedSourceCount = $records.Count
  affectedSourceIds = @($records | ForEach-Object { $_.sourceId })
  records = $records.ToArray()
  selection = 'Any string field containing java.getString/java.getStringList and a JSONPath expression; direct Analyzer JSONPath-only rules are excluded.'
}
$directory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
$temporaryPath = "$OutputPath.tmp-$PID"
[System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::Move($temporaryPath, $OutputPath, $true)
$result | Select-Object schemaVersion,generatedAt,sourcePackageSha256,sourceCount,affectedSourceCount | ConvertTo-Json -Compress
