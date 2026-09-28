[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Read-Utf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
  return [System.IO.File]::ReadAllText($Path, $utf8)
}

function Assert-Contract {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Message
  )
  if (-not $Condition) {
    throw "Network failure governance contract failed: $Message"
  }
}

$coordinatorPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Network\NetworkTransportFailureCoordinator.ets'
$onlineLoaderPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Cache\OnlineImageLoader.ets'
$retryPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Reader\MangaImageRetryCoordinator.ets'
$viewerPath = Join-Path $RepositoryRoot 'entry\src\main\ets\components\MangaViewer.ets'
$errorMonitorPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Debug\ErrorMonitorService.ets'
$errorRecordsPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Debug\ErrorRecordManager.ets'
$downloadMonitorPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Download\DownloadCacheFlowMonitor.ets'
$readMonitorPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Reader\MangaReadFlowMonitor.ets'
$deviceTestPath = Join-Path $RepositoryRoot 'entry\src\ohosTest\ets\test\NetworkTransportFailureGovernance.test.ets'

$coordinatorText = Read-Utf8Text -Path $coordinatorPath
$onlineLoaderText = Read-Utf8Text -Path $onlineLoaderPath
$retryText = Read-Utf8Text -Path $retryPath
$viewerText = Read-Utf8Text -Path $viewerPath
$errorMonitorText = Read-Utf8Text -Path $errorMonitorPath
$errorRecordsText = Read-Utf8Text -Path $errorRecordsPath
$downloadMonitorText = Read-Utf8Text -Path $downloadMonitorPath
$readMonitorText = Read-Utf8Text -Path $readMonitorPath
$deviceTestText = Read-Utf8Text -Path $deviceTestPath

Assert-Contract ($coordinatorText.Contains('return `network_transport|${kind}|${hostPart}|${codePart}`;')) `
  'Fingerprint must omit URL paths and request data.'
Assert-Contract ($coordinatorText.Contains('if (!backgroundRequest || userInitiated)')) `
  'Visible and user-initiated requests must bypass the circuit.'
Assert-Contract ($coordinatorText.Contains('DNS_CIRCUIT_TTL_MS: number = 20 * 1000')) `
  'DNS circuit must remain short-lived.'
Assert-Contract ($coordinatorText.Contains('TLS_CIRCUIT_TTL_MS: number = 45 * 1000')) `
  'TLS circuit must remain short-lived.'
Assert-Contract (([regex]::Matches($onlineLoaderText, 'transportFailureCoordinator\.shouldSuppress\(')).Count -ge 2) `
  'Online loader must guard both enqueue and already queued background work.'
Assert-Contract (([regex]::Matches($onlineLoaderText, 'LegadoImageTransportTrace\.recordTransportFailure\(')).Count -ge 3) `
  'Suppressed background requests and executed transport failures must all remain traceable.'
Assert-Contract ($onlineLoaderText.Contains('request.retryCount < this.MAX_RETRIES && !stopBackgroundRetry')) `
  'Background DNS/TLS failures must not enter the per-page retry loop.'
Assert-Contract ($retryText.Contains('allowAutomaticRetry: boolean = true')) `
  'Retry coordinator must expose an explicit automatic-retry policy.'
Assert-Contract ($viewerText.Contains('this.isPageCurrentlyVisible(page)')) `
  'Viewer must make automatic retry eligibility visibility-aware.'
Assert-Contract ($errorMonitorText.Contains('claimLedgerRecord(entry.message, now)')) `
  'Error monitor must aggregate canonical transport fingerprints.'
Assert-Contract ($errorRecordsText.Contains('findRecentNetworkRecord(message, now)')) `
  'Persistent network records must dedupe the same canonical fingerprint.'
Assert-Contract ($downloadMonitorText.Contains('transportFailureCoordinator.isRecognizedFailureMessage(event.errorMessage)')) `
  'Download flow must retain expected transport failures below ERROR.'
Assert-Contract ($readMonitorText.Contains('transportFailureCoordinator.isRecognizedFailureMessage(event.errorMessage)')) `
  'Read flow must retain expected transport failures below ERROR.'
Assert-Contract ($deviceTestText.Contains('suppressesOnlyBackgroundRequestsWhileCircuitIsOpen')) `
  'Device conformance must cover background-only circuit behavior.'
Assert-Contract ($deviceTestText.Contains("fingerprint.includes('/chapter/')")) `
  'Device conformance must prove URL paths are absent from fingerprints.'
Assert-Contract ($deviceTestText.Contains('classifiesLocalizedReaderTimeoutForPresentation')) `
  'Device conformance must cover the reader-generated localized timeout message.'

$localizedMethodStart = $viewerText.IndexOf('private getLocalizedImageFailureMessage(')
$overlayStart = $viewerText.IndexOf('private buildImageFailureOverlay(', $localizedMethodStart + 1)
$overlayEnd = $viewerText.IndexOf('buildContinuousPageImage(', $overlayStart + 1)
Assert-Contract ($localizedMethodStart -ge 0 -and $overlayStart -gt $localizedMethodStart) `
  'Viewer must expose one centralized localized image-failure presenter.'
Assert-Contract ($overlayEnd -gt $overlayStart) `
  'Viewer image-failure overlay boundary must be detectable.'
$localizedMethodText = $viewerText.Substring($localizedMethodStart, $overlayStart - $localizedMethodStart)
$overlayText = $viewerText.Substring($overlayStart, $overlayEnd - $overlayStart)

Assert-Contract ($localizedMethodText.Contains('transportFailureCoordinator.describe(')) `
  'Viewer presentation must consume the shared transport classifier.'
Assert-Contract ($localizedMethodText.Contains("return '域名解析失败，请检查网络后重试';")) `
  'Viewer must localize DNS failures.'
Assert-Contract ($localizedMethodText.Contains("return '安全连接失败，请稍后重试';")) `
  'Viewer must localize TLS failures.'
Assert-Contract ($localizedMethodText.Contains("return '请求超时，请稍后重试';")) `
  'Viewer must localize timeout failures.'
Assert-Contract ($localizedMethodText.Contains("return '图片服务返回错误，请稍后重试';")) `
  'Viewer must localize HTTP failures.'
Assert-Contract ($localizedMethodText.Contains("return '网络连接失败，请检查网络后重试';")) `
  'Viewer must localize generic network failures.'
Assert-Contract ($overlayText.Contains('SymbolGlyph($r(''sys.symbol.exclamationmark_circle_fill''))')) `
  'Viewer failure icon must use SymbolGlyph for a system symbol resource.'
Assert-Contract (-not $overlayText.Contains('Image($r(''sys.symbol.exclamationmark_circle_fill''))')) `
  'Viewer failure icon must not pass a system symbol resource to Image.'
Assert-Contract ($overlayText.Contains('Text(this.getLocalizedImageFailureMessage(page))')) `
  'Viewer overlay must render only the localized presentation message.'
Assert-Contract (-not $overlayText.Contains('getPageLoadState(page)?.error')) `
  'Viewer overlay must not expose the raw transport or pipeline error.'
Assert-Contract ($overlayText.Contains('.fontColor($r(''app.color.reader_text_primary''))') -and `
  $overlayText.Contains('.fontColor($r(''app.color.reader_text_secondary''))')) `
  'Viewer failure title and reason must use the theme-independent reader contrast palette.'
Assert-Contract ($overlayText.Contains('Button(''重试'')') -and `
  $overlayText.Contains('.backgroundColor($r(''app.color.accent''))') -and `
  $overlayText.Contains('.enabled(!this.mangaImageRetryCoordinator.isLoading(') -and `
  $overlayText.Contains('this.retryLoadPage(page);')) `
  'Viewer failure overlay must retain an actionable, state-aware retry command.'
Assert-Contract ($overlayText.Contains('.maxLines(2)') -and `
  $overlayText.Contains('.textOverflow({ overflow: TextOverflow.Ellipsis })')) `
  'Viewer failure reason must remain bounded to two ellipsized lines.'
Assert-Contract (-not [regex]::IsMatch($localizedMethodText + $overlayText, '\b(any|unknown|ESObject)\b')) `
  'Viewer failure presentation must obey strict ArkTS type rules.'

$strictFiles = @($coordinatorPath, $deviceTestPath)
foreach ($strictFile in $strictFiles) {
  $strictText = Read-Utf8Text -Path $strictFile
  Assert-Contract (-not [regex]::IsMatch($strictText, '\b(any|unknown|ESObject)\b')) `
    "Strict ArkTS forbidden type found in $strictFile."
}

[PSCustomObject]@{
  status = 'passed'
  fingerprint = 'network_transport|kind|host|code'
  dnsCircuitMs = 20000
  tlsCircuitMs = 45000
  visibleBypass = $true
  manualBypass = $true
  deviceContracts = 5
  localizedImageFailureKinds = @('dns', 'tls', 'timeout', 'http', 'network')
} | ConvertTo-Json -Compress
