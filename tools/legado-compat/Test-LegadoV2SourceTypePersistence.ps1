[CmdletBinding()]
param(
  [string]$SourceUrl = '',
  [string]$SourceName = '',
  [string]$RawSha256 = '',
  [ValidateRange(0, 4)]
  [int]$ExpectedSourceType,
  [string]$Device = '2UCUT24724009680',
  [string]$HdcPath = 'F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$remoteDatabasePath = '/data/app/el2/100/database/com.dlzz.manxia/entry/rdb/manxia_comic.db'
$sqliteCandidates = @(
  'G:\Android\Sdk\platform-tools\sqlite3.exe',
  'E:\Android_SDK\platform-tools\sqlite3.exe',
  'C:\Users\13359\AppData\Local\Android\Sdk\platform-tools\sqlite3.exe'
)
$databaseSuffixes = @('', '-wal', '-shm', '-dwr')

function Get-Sha256ForText {
  param([string]$Value)
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
  return [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes))
}

function Get-Utf8Hex {
  param([string]$Value)
  return [Convert]::ToHexString([System.Text.Encoding]::UTF8.GetBytes($Value))
}

function Get-SqlitePath {
  foreach ($candidate in $sqliteCandidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      return $candidate
    }
  }
  throw 'SOURCE_TYPE_AUDIT_SQLITE_MISSING'
}

function Write-ResultAtomically {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [void][System.IO.Directory]::CreateDirectory($directory)
  }
  $temporaryPath = $Path + '.tmp-' + [Guid]::NewGuid().ToString('N')
  try {
    [System.IO.File]::WriteAllText(
      $temporaryPath,
      [string]($Value | ConvertTo-Json -Depth 10),
      [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::Move($temporaryPath, $Path, $true)
  } finally {
    if ([System.IO.File]::Exists($temporaryPath)) {
      [System.IO.File]::Delete($temporaryPath)
    }
  }
}

if (-not (Test-Path -LiteralPath $HdcPath -PathType Leaf)) {
  throw 'SOURCE_TYPE_AUDIT_HDC_MISSING'
}
if ([string]::IsNullOrWhiteSpace($SourceUrl) -and [string]::IsNullOrWhiteSpace($SourceName) -and
  $RawSha256 -notmatch '^[0-9A-Fa-f]{64}$') {
  throw 'SOURCE_TYPE_AUDIT_IDENTITY_MISSING'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $PSScriptRoot 'evidence\source-type-persistence-audit.json'
}

$sqlitePath = Get-SqlitePath
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('manxia-legado-source-type-audit-' + [Guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($tempRoot)
$sourceId = if ($RawSha256 -match '^[0-9A-Fa-f]{64}$') {
  $RawSha256.ToUpperInvariant()
} else {
  Get-Sha256ForText -Value $SourceUrl
}
$result = [ordered]@{
  schemaVersion = 1
  status = 'failed'
  sourceId = $sourceId
  expectedSourceType = $ExpectedSourceType
  snapshotMode = 'live_read_only_with_wal_sidecars'
  rowCount = 0
  rawDatabaseRemoved = $false
}

try {
  foreach ($suffix in $databaseSuffixes) {
    $localPath = Join-Path $tempRoot ('manxia_comic.db' + $suffix)
    $null = & $HdcPath -t $Device file recv ($remoteDatabasePath + $suffix) $localPath 2>$null
    if ($suffix.Length -eq 0 -and ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $localPath -PathType Leaf))) {
      throw 'SOURCE_TYPE_AUDIT_DATABASE_COPY_FAILED'
    }
  }

  $escapedRawSha256 = $RawSha256.Replace("'", "''")
  $whereClause = if ($SourceName.Length -gt 0) {
    "hex(ns.bookSourceName) = '$(Get-Utf8Hex -Value $SourceName)'"
  } elseif ($RawSha256 -match '^[0-9A-Fa-f]{64}$') {
    "c.rawSha256 = '$escapedRawSha256'"
  } else {
    "hex(ns.bookSourceUrl) = '$(Get-Utf8Hex -Value $SourceUrl)'"
  }
  $query = @"
SELECT ns.bookSourceType AS columnType,
       json_extract(ns.configJson, '$.bookSourceType') AS configType,
       length(ns.configJson) AS configLength,
       c.rawSha256 AS rawSha256,
       json_extract(c.rawJson, '$.bookSourceType') AS rawType,
       length(c.rawJson) AS rawLength,
       c.compilerVersion AS compilerVersion,
       c.compileStatus AS compileStatus,
       c.engineMode AS engineMode
FROM novel_source AS ns
LEFT JOIN novel_source_compatibility AS c ON c.sourceUrl = ns.bookSourceUrl
WHERE $whereClause;
"@
  $databasePath = Join-Path $tempRoot 'manxia_comic.db'
  $sqliteJson = @(& $sqlitePath -readonly -json $databasePath $query 2>$null)
  if ($LASTEXITCODE -ne 0) {
    throw 'SOURCE_TYPE_AUDIT_SQLITE_QUERY_FAILED'
  }
  $rows = @()
  if (($sqliteJson -join '').Trim().Length -gt 0) {
    $parsedRows = $sqliteJson | ConvertFrom-Json -Depth 10
    $rows = @(@($parsedRows) | Where-Object { $null -ne $_ })
  }
  $result.rowCount = $rows.Count
  if ($rows.Count -ne 1) {
    $result.errorCategory = 'source_row_count_mismatch'
  } else {
    $row = $rows[0]
    $result.columnType = [int]$row.columnType
    $result.configType = [int]$row.configType
    $result.rawType = [int]$row.rawType
    $result.configLength = [int]$row.configLength
    $result.rawLength = [int]$row.rawLength
    $result.rawSha256 = [string]$row.rawSha256
    $result.compilerVersion = [int]$row.compilerVersion
    $result.compileStatus = [string]$row.compileStatus
    $result.engineMode = [string]$row.engineMode
    $result.typeConsistent = $result.columnType -eq $ExpectedSourceType -and
      $result.configType -eq $ExpectedSourceType -and
      $result.rawType -eq $ExpectedSourceType
    $result.status = if ($result.typeConsistent) { 'passed' } else { 'failed' }
    if (-not $result.typeConsistent) {
      $result.errorCategory = 'source_type_persistence_mismatch'
    }
  }
} catch {
  $message = $_.Exception.Message
  $result.errorCategory = 'source_type_persistence_audit_failed'
  $result.errorType = $_.Exception.GetType().FullName
  $safeMessage = if ($SourceUrl.Length -gt 0) { $message.Replace($SourceUrl, '<source>') } else { $message }
  $result.errorDetail = if ($SourceName.Length -gt 0) { $safeMessage.Replace($SourceName, '<source-name>') } else { $safeMessage }
  $result.errorDigest = Get-Sha256ForText -Value $message
} finally {
  foreach ($suffix in $databaseSuffixes) {
    $localPath = Join-Path $tempRoot ('manxia_comic.db' + $suffix)
    if ([System.IO.File]::Exists($localPath)) {
      [System.IO.File]::Delete($localPath)
    }
  }
  if ([System.IO.Directory]::Exists($tempRoot)) {
    [System.IO.Directory]::Delete($tempRoot, $false)
  }
  $result.rawDatabaseRemoved = -not [System.IO.Directory]::Exists($tempRoot)
  $result.generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  Write-ResultAtomically -Path $OutputPath -Value ([pscustomobject]$result)
}

Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8
if ($result.status -ne 'passed' -or -not $result.rawDatabaseRemoved) {
  exit 1
}
