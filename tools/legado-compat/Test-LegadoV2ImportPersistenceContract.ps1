[CmdletBinding()]
param([string]$RepositoryRoot = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
$scriptPath = Join-Path $RepositoryRoot 'tools\legado-compat\Test-LegadoV2ImportPersistence.ps1'
$text = [System.IO.File]::ReadAllText($scriptPath, [System.Text.UTF8Encoding]::new($false, $true))
$required = @(
  'novel_source',
  'novel_source_compatibility',
  'novel_source_compatibility_verification',
  'snapshotMode = ''live_read_only_with_wal_sidecars''',
  'databaseSha256',
  'rawDatabaseRemoved',
  '[System.IO.File]::Delete',
  '[System.IO.Directory]::Delete'
)
foreach ($item in $required) {
  if (-not $text.Contains($item)) {
    throw "Persistence audit contract failed: missing '$item'."
  }
}
foreach ($forbidden in @('rawJson', 'cookie', 'body')) {
  if ($text.Contains($forbidden)) {
    throw "Persistence audit contract failed: forbidden raw field '$forbidden'."
  }
}
[pscustomobject]@{
  status = 'passed'
  script = 'tools/legado-compat/Test-LegadoV2ImportPersistence.ps1'
  rawPayloadFieldsExcluded = $true
  walSidecarsIncluded = $true
  cleanupRequired = $true
} | ConvertTo-Json -Compress
