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
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-image-request-header-carrier.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-image-request-header-carrier.json'
}

$assertions = 0
function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Legado IMAGE request header carrier contract failed: $Message" }
  $script:assertions++
}

function Read-Utf8Text {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) "missing file: $Path"
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

function Write-Result {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) {
    [void][System.IO.Directory]::CreateDirectory($directory)
  }
  $temporaryPath = "$Path.tmp-$PID"
  [System.IO.File]::WriteAllText($temporaryPath, [string]($Value | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

$result = $null
try {
  $fixture = (Read-Utf8Text -Path $FixturePath) | ConvertFrom-Json
  $reference = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'legado\app\src\main\java\io\legado\app\model\analyzeRule\AnalyzeUrl.kt')
  $headerContract = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Reader\MangaRequestHeaderContract.ets')
  $assetLoader = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Reader\MangaAssetLoader.ets')
  $imageCache = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Cache\ImageCacheManager.ets')
  $onlineLoader = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Cache\OnlineImageLoader.ets')
  $preload = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Preload\ChapterPreloadManager.ets')

  Assert-Contract ([string]$fixture.contract -eq 'legado_v2_image_request_header_carrier') 'fixture contract must identify IMAGE request headers.'
  Assert-Contract ([int]$fixture.baseline.sourceCount -eq 458) 'fixture baseline source count must remain 458.'
  Assert-Contract ([string]$fixture.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'fixture must bind the fixed Legado commit.'
  Assert-Contract ($reference.Contains('headerMap.putAll(it)')) 'Legado AnalyzeUrl must merge source/login headers before URL options.'
  Assert-Contract ($reference.Contains('headerMap[entry.key.toString()] = entry.value.toString()')) 'Legado URL option headers must override the base header map.'
  Assert-Contract ($reference.Contains('mergeCookies(cookie, headerMap["Cookie"])')) 'Legado must merge CookieStore with explicit Cookie.'
  Assert-Contract ($reference.Contains('return GlideUrl(url, GlideHeaders(headerMap))')) 'Legado must hand the effective header map to the image consumer.'
  Assert-Contract ($headerContract.Contains('public static apply')) 'V2 must expose the shared header normalization contract.'
  Assert-Contract ($headerContract.Contains("case 'authorization':")) 'shared contract must classify Authorization as standard.'
  Assert-Contract ($headerContract.Contains("case 'sec-fetch-dest':")) 'shared contract must classify Sec-Fetch-Dest as standard.'
  Assert-Contract ($assetLoader.Contains('convertToOnlineHeaders(request.loadOptions.headers)')) 'visible IMAGE requests must use the OnlineImageLoader header projection.'
  Assert-Contract ($assetLoader.Contains('target.authorization = headers.authorization')) 'visible requests must preserve Authorization.'
  Assert-Contract ($assetLoader.Contains('target.secFetchDest = headers.secFetchDest')) 'visible requests must preserve Sec-Fetch-Dest.'
  Assert-Contract ($imageCache.Contains('private buildOnlineHeaders(headers?: RequestHeaders): OnlineRequestHeaders | undefined')) 'ImageCacheManager must own one canonical OnlineImageLoader projection.'
  Assert-Contract ($imageCache.Contains('this.buildOnlineHeaders(options?.headers)')) 'preloadImage must reuse the canonical projection instead of a partial copy.'
  Assert-Contract ($imageCache.Contains('skipFailureTtl: options?.skipFailureTtl')) 'preloadImage must preserve failure policy.'
  Assert-Contract ($imageCache.Contains('forceRefresh: options?.forceRefresh')) 'preloadImage must preserve refresh policy.'
  Assert-Contract ($imageCache.Contains('cachePartition: headers.cachePartition')) 'preload projection must preserve cache partition identity.'
  Assert-Contract ($imageCache.Contains('extraHeaders: this.cloneRequestHeaderEntries(headers.extraHeaders)')) 'preload projection must preserve extension headers.'
  Assert-Contract ($onlineLoader.Contains('secFetchDest: secFetchDest')) 'OnlineImageLoader transport must materialize standard fetch headers.'
  Assert-Contract ($onlineLoader.Contains('extraHeaders: this.cloneHeaderEntries(options.headers?.extraHeaders)')) 'OnlineImageLoader transport must retain extension headers.'
  Assert-Contract ($preload.Contains('MangaRequestHeaderContract.apply')) 'ChapterPreloadManager must normalize configured headers before preload.'
  Assert-Contract ($preload.Contains('options.sourceId = this.currentSourceId')) 'preload requests must retain source identity for Cookie and trace policy.'

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'passed'
    contract = [string]$fixture.contract
    assertions = $assertions
    fixture = [System.IO.Path]::GetRelativePath($RepositoryRoot, $FixturePath).Replace('\', '/')
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'failed'
    contract = 'legado_v2_image_request_header_carrier'
    assertions = $assertions
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
}

Write-Result -Path $ResultPath -Value $result
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') { exit 1 }
