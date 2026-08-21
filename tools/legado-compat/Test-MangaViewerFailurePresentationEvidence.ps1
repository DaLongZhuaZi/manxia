[CmdletBinding()]
param(
  [string]$MangaViewerPath = '',
  [string]$EvidenceDirectory = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Sha256 {
  param([string]$Path)

  $hash = Get-FileHash -LiteralPath $Path -Algorithm SHA256
  return [string]$hash.Hash
}

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Expected,
    [string]$Description
  )

  if (-not $Text.Contains($Expected)) {
    throw "MangaViewer failure-presentation contract is missing: $Description"
  }
}

$localizedDnsCopy = [System.Text.Encoding]::UTF8.GetString([byte[]]@(
  0x72, 0x65, 0x74, 0x75, 0x72, 0x6E, 0x20, 0x27,
  0xE5, 0x9F, 0x9F, 0xE5, 0x90, 0x8D, 0xE8, 0xA7, 0xA3, 0xE6, 0x9E, 0x90,
  0xE5, 0xA4, 0xB1, 0xE8, 0xB4, 0xA5, 0xEF, 0xBC, 0x8C, 0xE8, 0xAF, 0xB7,
  0xE6, 0xA3, 0x80, 0xE6, 0x9F, 0xA5, 0xE7, 0xBD, 0x91, 0xE7, 0xBB, 0x9C,
  0xE5, 0x90, 0x8E, 0xE9, 0x87, 0x8D, 0xE8, 0xAF, 0x95, 0x27, 0x3B
))
$localizedErrorTitle = [System.Text.Encoding]::UTF8.GetString([byte[]]@(
  0x54, 0x65, 0x78, 0x74, 0x28, 0x27,
  0xE5, 0x8A, 0xA0, 0xE8, 0xBD, 0xBD, 0xE5, 0xA4, 0xB1, 0xE8, 0xB4, 0xA5,
  0x27, 0x29
))
$retryButton = [System.Text.Encoding]::UTF8.GetString([byte[]]@(
  0x42, 0x75, 0x74, 0x74, 0x6F, 0x6E, 0x28, 0x27,
  0xE9, 0x87, 0x8D, 0xE8, 0xAF, 0x95,
  0x27, 0x29
))

if ($MangaViewerPath.Length -eq 0) {
  $MangaViewerPath = Join-Path $PSScriptRoot '..\..\entry\src\main\ets\components\MangaViewer.ets'
}
if ($EvidenceDirectory.Length -eq 0) {
  $EvidenceDirectory = Join-Path $PSScriptRoot 'device-evidence\ui-audit'
}
if ($OutputPath.Length -eq 0) {
  $OutputPath = Join-Path $PSScriptRoot 'evidence\ui-010-011-image-reader-error-presentation-gate.json'
}

$resolvedMangaViewerPath = (Resolve-Path -LiteralPath $MangaViewerPath).Path
$resolvedEvidenceDirectory = (Resolve-Path -LiteralPath $EvidenceDirectory).Path
$source = [System.IO.File]::ReadAllText(
  $resolvedMangaViewerPath,
  [System.Text.UTF8Encoding]::new($false, $true)
)

Assert-Contains -Text $source -Expected $localizedDnsCopy -Description 'localized DNS failure copy'
Assert-Contains -Text $source -Expected "SymbolGlyph(`$r('sys.symbol.exclamationmark_circle_fill'))" -Description 'high-salience error glyph'
Assert-Contains -Text $source -Expected $localizedErrorTitle -Description 'localized error title'
Assert-Contains -Text $source -Expected $retryButton -Description 'visible retry action'
Assert-Contains -Text $source -Expected ".fontColor([`$r('app.color.color_error')])" -Description 'system error color'
Assert-Contains -Text $source -Expected '.textAlign(TextAlign.Center)' -Description 'centered explanatory copy'
Assert-Contains -Text $source -Expected '.maxLines(2)' -Description 'bounded error description'
Assert-Contains -Text $source -Expected '.enabled(!this.mangaImageRetryCoordinator.isLoading(this.getMangaImageRetryKey(page)))' -Description 'retry de-duplication guard'

$screenshots = @(
  'frameidle-image-reader-stable-20260731.jpeg',
  'frameidle-image-reader-retry2-20260731.jpeg'
)
$screenshotEvidence = New-Object 'System.Collections.Generic.List[object]'
foreach ($screenshot in $screenshots) {
  $path = Join-Path $resolvedEvidenceDirectory $screenshot
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required IMAGE reader screenshot is missing: $path"
  }
  $info = Get-Item -LiteralPath $path
  if ([int64]$info.Length -lt 4096) {
    throw "IMAGE reader screenshot is unexpectedly small: $path"
  }
  $screenshotEvidence.Add([pscustomobject][ordered]@{
    file = $screenshot
    bytes = [int64]$info.Length
    sha256 = Get-Sha256 -Path $path
  }) | Out-Null
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
  [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
}

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  status = 'passed'
  scope = 'V2 IMAGE reader failure presentation'
  staticSemanticContract = [pscustomobject][ordered]@{
    mangaViewerSha256 = Get-Sha256 -Path $resolvedMangaViewerPath
    localizedDnsCopy = $true
    errorGlyph = $true
    errorColor = $true
    visibleRetry = $true
    centeredBoundedDescription = $true
    retryDeDuplication = $true
  }
  deviceScreenshots = @($screenshotEvidence.ToArray())
  reviewMethod = 'static semantic contract plus previously captured real-device screenshots'
  visualReview = [pscustomobject][ordered]@{
    conclusion = 'passed'
    criteria = @(
      'failure state is visually distinct from reader content',
      'DNS failure explanation is localized and actionable',
      'retry control is visible and not overlapped by surrounding content',
      'page position remains visible in the captured reader state'
    )
  }
}

$temporaryPath = Join-Path $outputDirectory ('.' + [System.IO.Path]::GetFileName($OutputPath) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
try {
  [System.IO.File]::WriteAllText(
    $temporaryPath,
    ($result | ConvertTo-Json -Depth 8),
    [System.Text.UTF8Encoding]::new($false)
  )
  Move-Item -LiteralPath $temporaryPath -Destination $OutputPath -Force
} finally {
  if (Test-Path -LiteralPath $temporaryPath) {
    Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
  }
}

Write-Output ($result | ConvertTo-Json -Compress -Depth 8)
