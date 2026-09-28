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
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-image-request-header-fallback-carrier.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-image-request-header-fallback-carrier.json'
}

$assertions = 0
function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Legado IMAGE fallback header carrier contract failed: $Message" }
  $script:assertions++
}

function Read-Utf8Text {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) "missing file: $Path"
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  Assert-Contract (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) "UTF-8 BOM is not allowed: $Path"
  return [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
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
  $onlineLoaderPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Cache\OnlineImageLoader.ets'
  $onlineLoader = Read-Utf8Text -Path $onlineLoaderPath
  $referencePath = Join-Path $RepositoryRoot 'legado\app\src\main\java\io\legado\app\model\analyzeRule\AnalyzeUrl.kt'
  $reference = Read-Utf8Text -Path $referencePath

  Assert-Contract ([string]$fixture.contract -eq 'legado_v2_image_request_header_fallback_carrier') 'fixture contract must identify IMAGE fallback headers.'
  Assert-Contract ([int]$fixture.baseline.sourceCount -eq 458) 'fixture baseline source count must remain 458.'
  Assert-Contract ([string]$fixture.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'fixture must bind the fixed source hash.'
  Assert-Contract ([string]$fixture.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'fixture must bind the fixed Legado commit.'
  Assert-Contract ($reference.Contains('return GlideUrl(url, GlideHeaders(headerMap))')) 'Legado must pass one effective header carrier to the image consumer.'
  Assert-Contract ($onlineLoader.Contains('private buildRelaxed403RetryOptions(options: OnlineLoadOptions): OnlineLoadOptions')) 'V2 must have an explicit 403 retry projection.'
  Assert-Contract ($onlineLoader.Contains('return await this.doHttpRequest(url, this.buildRelaxed403RetryOptions(options))')) '403 path must use the explicit retry projection.'

  $requiredHeaderAssignments = @(
    'relaxedHeaders.userAgent = String(headers.userAgent)',
    'relaxedHeaders.accept = String(headers.accept)',
    'relaxedHeaders.referer = String(headers.referer)',
    'relaxedHeaders.origin = String(headers.origin)',
    'relaxedHeaders.cookie = String(headers.cookie)',
    'relaxedHeaders.authorization = String(headers.authorization)',
    'relaxedHeaders.acceptLanguage = String(headers.acceptLanguage)',
    'relaxedHeaders.cacheControl = String(headers.cacheControl)',
    'relaxedHeaders.pragma = String(headers.pragma)',
    'relaxedHeaders.secFetchDest = String(headers.secFetchDest)',
    'relaxedHeaders.secFetchMode = String(headers.secFetchMode)',
    'relaxedHeaders.secFetchSite = String(headers.secFetchSite)'
  )
  foreach ($assignment in $requiredHeaderAssignments) {
    Assert-Contract ($onlineLoader.Contains($assignment)) "403 retry projection must preserve $assignment."
  }
  Assert-Contract ($onlineLoader.Contains('relaxedHeaders.extraHeaders = this.cloneHeaderEntries(headers.extraHeaders)')) '403 retry projection must preserve extension headers.'
  Assert-Contract ($onlineLoader.Contains('skipFailureTtl: options.skipFailureTtl')) '403 retry projection must preserve failure policy.'
  Assert-Contract ($onlineLoader.Contains('forceRefresh: options.forceRefresh')) '403 retry projection must preserve refresh policy.'
  Assert-Contract ($onlineLoader.Contains('legadoImageTrace: options.legadoImageTrace')) '403 retry projection must preserve trace context.'

  Assert-Contract ($onlineLoader.Contains('const headers = await this.buildHeaders(url, options)')) 'WebView fallbacks must use the canonical effective header builder.'
  Assert-Contract ($onlineLoader.Contains("['Origin', headers.origin]")) 'WebView fallbacks must receive Origin when present.'
  Assert-Contract ($onlineLoader.Contains("['Cache-Control', headers.cacheControl]")) 'WebView fallbacks must receive Cache-Control when present.'
  Assert-Contract ($onlineLoader.Contains("['Sec-Fetch-Site', headers.secFetchSite]")) 'WebView fallbacks must receive Sec-Fetch-Site when present.'

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'passed'
    contract = [string]$fixture.contract
    assertions = $assertions
    fixture = [System.IO.Path]::GetRelativePath($RepositoryRoot, $FixturePath).Replace('\', '/')
    implementation = [System.IO.Path]::GetRelativePath($RepositoryRoot, $onlineLoaderPath).Replace('\', '/')
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    verificationPolicy = 'static_source_contract_only;runtime_regression_deferred_to_R4'
    semanticMatchAllowed = $false
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'failed'
    contract = 'legado_v2_image_request_header_fallback_carrier'
    assertions = $assertions
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    verificationPolicy = 'static_source_contract_only;runtime_regression_deferred_to_R4'
    semanticMatchAllowed = $false
  }
}

Write-Result -Path $ResultPath -Value $result
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') { exit 1 }
