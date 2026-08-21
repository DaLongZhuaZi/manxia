[CmdletBinding()]
param(
  [string]$Device = '2UCUT24724009680',
  [string]$HdcPath = 'F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
  [int]$ExpectedCount = 458,
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

function Get-SqlitePath {
  foreach ($candidate in $sqliteCandidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      return $candidate
    }
  }
  throw '只读数据库审计未找到 sqlite3。'
}

function Resolve-Device {
  param([string]$RequestedDevice)
  if (-not [string]::IsNullOrWhiteSpace($RequestedDevice)) {
    return $RequestedDevice
  }
  $targets = @(& $HdcPath list targets 2>$null | ForEach-Object { $_.Trim() } | Where-Object { $_.Length -gt 0 })
  if ($targets.Count -eq 0) {
    throw '没有连接 HarmonyOS 设备。'
  }
  return [string]$targets[0]
}

function Write-Result {
  param(
    [string]$Path,
    [object]$Value
  )
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $json = $Value | ConvertTo-Json -Depth 20
  [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

if (-not (Test-Path -LiteralPath $HdcPath -PathType Leaf)) {
  throw "HDC 不存在：$HdcPath"
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $PSScriptRoot 'evidence\v2-import-persistence-20260804.json'
}

$resolvedDevice = Resolve-Device -RequestedDevice $Device
$sqlitePath = Get-SqlitePath
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('manxia-v2-import-persistence-' + [guid]::NewGuid().ToString('N'))
[System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null
$result = [ordered]@{
  schemaVersion = 1
  status = 'failed'
  device = $resolvedDevice
  snapshotMode = 'live_read_only_with_wal_sidecars'
  expectedCount = $ExpectedCount
  rawDatabaseStoredOutsideEvidence = $true
  rawDatabaseRemoved = $false
  sourceRows = 0
  compatibilityRows = 0
  verificationRows = 0
}

try {
  foreach ($suffix in @('', '-wal', '-shm', '-dwr')) {
    $localPath = Join-Path $tempRoot ('manxia_comic.db' + $suffix)
    $null = & $HdcPath -t $resolvedDevice file recv ($remoteDatabasePath + $suffix) $localPath 2>$null
    if ($suffix.Length -eq 0 -and ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $localPath -PathType Leaf))) {
      throw '无法只读复制真机主数据库。'
    }
  }

  $databasePath = Join-Path $tempRoot 'manxia_comic.db'
  $query = 'SELECT (SELECT COUNT(*) FROM novel_source) AS sourceRows, (SELECT COUNT(*) FROM novel_source_compatibility) AS compatibilityRows, (SELECT COUNT(*) FROM novel_source_compatibility_verification) AS verificationRows;'
  $sqliteJson = @(& $sqlitePath -readonly -json $databasePath $query 2>$null)
  if ($LASTEXITCODE -ne 0 -or $sqliteJson.Count -eq 0) {
    throw 'SQLite 聚合查询失败。'
  }
  $row = @($sqliteJson | ConvertFrom-Json -Depth 10)[0]
  $result.sourceRows = [int]$row.sourceRows
  $result.compatibilityRows = [int]$row.compatibilityRows
  $result.verificationRows = [int]$row.verificationRows
  $result.databaseSha256 = (Get-FileHash -LiteralPath $databasePath -Algorithm SHA256).Hash
  $result.status = if ($result.sourceRows -eq $ExpectedCount -and $result.compatibilityRows -eq $ExpectedCount) { 'passed' } else { 'failed' }
  if ($result.status -ne 'passed') {
    $result.error = 'Database row counts do not match the frozen import count.'
  }
} catch {
  $result.error = $_.Exception.Message
} finally {
  foreach ($suffix in @('', '-wal', '-shm', '-dwr')) {
    $localPath = Join-Path $tempRoot ('manxia_comic.db' + $suffix)
    if ([System.IO.File]::Exists($localPath)) {
      [System.IO.File]::Delete($localPath)
    }
  }
  if ([System.IO.Directory]::Exists($tempRoot)) {
    [System.IO.Directory]::Delete($tempRoot, $false)
  }
  $result.rawDatabaseRemoved = -not [System.IO.Directory]::Exists($tempRoot)
  Write-Result -Path $OutputPath -Value ([pscustomobject]$result)
}

Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8
if ($result.status -ne 'passed' -or -not $result.rawDatabaseRemoved) {
  exit 1
}
