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
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-image-cached-identity.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-image-cached-identity.json'
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Legado IMAGE cached identity contract failed: $Message" }
}

$result = $null
try {
  $resolverPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Reader\MangaIdentityResolver.ets'
  $resolver = [System.IO.File]::ReadAllText($resolverPath, [System.Text.UTF8Encoding]::new($false, $true))
  $fixture = [System.IO.File]::ReadAllText($FixturePath, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
  Assert-Contract ([int]$fixture.schemaVersion -eq 1) 'fixture schema version must be 1'
  Assert-Contract ([string]$fixture.contract -eq 'legado_image_cached_identity') 'fixture contract identity is wrong'
  Assert-Contract ($fixture.cases.Count -eq 3) 'fixture must contain three cache identity cases'

  # The first execution fails until direct cache lookups honor the caller's
  # V2 package/source-ID pair instead of accepting a neighboring source.
  Assert-Contract ($resolver.Contains('requiresStrictOnlineSourceIdentity')) 'V2 IMAGE strict cache mode is missing'
  Assert-Contract ($resolver.Contains("result.sourcePkg.startsWith('legado.image.')")) 'V2 IMAGE package mode must be explicit'
  Assert-Contract ($resolver.Contains('matchesExpectedOnlineSource')) 'online cache identity matcher is missing'
  Assert-Contract ($resolver.Contains('direct online manga identity mismatch')) 'direct manga cache mismatch must be rejected'
  Assert-Contract ($resolver.Contains('direct online chapter identity mismatch')) 'direct chapter cache mismatch must be rejected'
  Assert-Contract ($resolver.Contains('comic.sourcePkg !== result.sourcePkg')) 'cached package must equal requested package'
  Assert-Contract ($resolver.Contains('String(comic.sourceId) !== String(result.sourceId)')) 'cached numeric source ID must equal requested source ID'
  Assert-Contract ($resolver.Contains('if (this.requiresStrictOnlineSourceIdentity(result))')) 'strict IMAGE mode must bypass local-cache fallback'

  $result = [pscustomobject][ordered]@{
    status = 'passed'
    contract = 'legado_image_cached_identity'
    assertions = 10
    cases = $fixture.cases.Count
    fixture = [System.IO.Path]::GetRelativePath($RepositoryRoot, $FixturePath).Replace('\\', '/')
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
} catch {
  $result = [pscustomobject][ordered]@{
    status = 'failed'
    contract = 'legado_image_cached_identity'
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
}

$directory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
[System.IO.File]::WriteAllText($ResultPath, [string]($result | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') { exit 1 }
