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
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-image-virtual-source-identity.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-image-virtual-source-identity.json'
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Legado IMAGE virtual-source identity contract failed: $Message" }
}

function Read-Utf8Json {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) "missing fixture: $Path"
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
}

$result = $null
try {
  $bridgePath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoMangaSourceBridge.ets'
  $bridge = [System.IO.File]::ReadAllText($bridgePath, [System.Text.UTF8Encoding]::new($false, $true))
  $fixture = Read-Utf8Json -Path $FixturePath
  Assert-Contract ([int]$fixture.schemaVersion -eq 1) 'fixture schema version must be 1'
  Assert-Contract ([string]$fixture.contract -eq 'legado_image_virtual_source_identity') 'fixture contract identity is wrong'
  Assert-Contract ($fixture.cases.Count -eq 6) 'fixture must contain six identity cases'

  # This marker is intentionally required before production changes: the first run
  # must fail if the bridge still resolves a source by numeric ID alone.
  Assert-Contract ($bridge.Contains('validateVirtualComicSourceIdentity')) 'strict identity validator is missing'
  Assert-Contract ($bridge.Contains('metadata.bookSourceType !== LegadoBookSourceType.IMAGE')) 'metadata source type must be checked'
  Assert-Contract ($bridge.Contains('metadata.bookSourceUrl !== expectedSource.bookSourceUrl')) 'metadata URL must be checked against the expected source'
  Assert-Contract ($bridge.Contains('metadata.id !== expectedPkg')) 'metadata package identity must be checked'
  Assert-Contract ($bridge.Contains('record.pkg !== expectedPkg')) 'database package identity must be checked'
  Assert-Contract ($bridge.Contains('metadata.adapter !== LEGADO_MANGA_ADAPTER')) 'metadata adapter must be checked'
  Assert-Contract ($bridge.Contains('workflows.adapter !== LEGADO_MANGA_ADAPTER')) 'workflow adapter must be checked'
  Assert-Contract ($bridge.Contains('synchronizeVirtualComicSource(pkg, source)')) 'ensure path must synchronize the expected package'
  Assert-Contract ($bridge.Contains('validateVirtualComicSourceIdentity(sourceRecord, pkg, source)')) 'ensure path must validate the post-import record'
  Assert-Contract ($bridge.Contains('validateVirtualComicSourceIdentity(record, record.pkg, source)')) 'numeric-ID resolution must validate the persisted record'

  $result = [pscustomobject][ordered]@{
    status = 'passed'
    contract = 'legado_image_virtual_source_identity'
    assertions = 10
    cases = $fixture.cases.Count
    fixture = [System.IO.Path]::GetRelativePath($RepositoryRoot, $FixturePath).Replace('\\', '/')
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
} catch {
  $result = [pscustomobject][ordered]@{
    status = 'failed'
    contract = 'legado_image_virtual_source_identity'
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
}

$directory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
[System.IO.File]::WriteAllText($ResultPath, [string]($result | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') { exit 1 }
