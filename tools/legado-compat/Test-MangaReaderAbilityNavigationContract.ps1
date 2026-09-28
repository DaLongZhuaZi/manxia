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
    throw "Manga reader navigation contract failed: $Message"
  }
}

$pagePath = Join-Path $RepositoryRoot 'entry\src\main\ets\pages\MangaReaderAbilityPage.ets'
$pageText = Read-Utf8Text -Path $pagePath

$aboutStart = $pageText.IndexOf('aboutToAppear(): void')
$pageShowStart = $pageText.IndexOf('onPageShow(): void')
$disappearStart = $pageText.IndexOf('aboutToDisappear(): void')
$scheduleStart = $pageText.IndexOf('private scheduleInitialReaderOpen(): void')
$payloadResolverStart = $pageText.IndexOf('private resolveReaderLaunchPayload(source: string): void')
$openReaderStart = $pageText.IndexOf('private openInitialReader(): boolean')
$paramsBuilderStart = $pageText.IndexOf('private buildIsolatedReaderParams(')
$buildStart = $pageText.IndexOf('build()')

Assert-Contract ($aboutStart -ge 0) 'aboutToAppear must exist.'
Assert-Contract ($pageShowStart -gt $aboutStart) 'onPageShow must follow aboutToAppear.'
Assert-Contract ($disappearStart -gt $pageShowStart) 'aboutToDisappear must follow onPageShow.'
Assert-Contract ($scheduleStart -gt $disappearStart) 'The frame-idle reader scheduler must follow lifecycle cleanup.'
Assert-Contract ($payloadResolverStart -gt $scheduleStart) 'The payload resolver must follow the frame-idle scheduler.'
Assert-Contract ($openReaderStart -gt $payloadResolverStart) 'The reader opener must follow the payload resolver.'
Assert-Contract ($paramsBuilderStart -gt $openReaderStart) 'The params builder must follow the reader opener.'
Assert-Contract ($buildStart -gt $payloadResolverStart) 'build must follow the payload resolver.'

$aboutText = $pageText.Substring($aboutStart, $pageShowStart - $aboutStart)
Assert-Contract ($aboutText.Contains('this.isPageActive = true;')) 'aboutToAppear must activate the launch scope.'
Assert-Contract ($aboutText.Contains("this.resolveReaderLaunchPayload('appear');")) 'aboutToAppear must consume the launch payload early.'
Assert-Contract ($aboutText.Contains('this.scheduleInitialReaderOpen();')) 'aboutToAppear must always defer Navigation mutation to frame idle.'
Assert-Contract (-not $aboutText.Contains('this.openInitialReader();')) 'aboutToAppear must never synchronously mutate the route stack.'

$pageShowText = $pageText.Substring($pageShowStart, $disappearStart - $pageShowStart)
Assert-Contract ($pageShowText.Contains('this.isPageActive = true;')) 'onPageShow must reactivate the launch scope.'
Assert-Contract ($pageShowText.Contains('if (this.hasOpenedReader)')) 'onPageShow must guard an existing destination.'
Assert-Contract ($pageShowText.Contains("this.resolveReaderLaunchPayload('page_show');")) 'onPageShow must retain delayed payload recovery.'
Assert-Contract ($pageShowText.Contains('this.scheduleInitialReaderOpen();')) 'onPageShow must route recovered payloads through the frame-idle scheduler.'
Assert-Contract (-not $pageShowText.Contains('this.openInitialReader();')) 'onPageShow must not synchronously mutate the route stack.'

$disappearText = $pageText.Substring($disappearStart, $scheduleStart - $disappearStart)
Assert-Contract ($disappearText.Contains('this.isPageActive = false;')) 'aboutToDisappear must deactivate deferred navigation.'
Assert-Contract ($disappearText.Contains('this.navigationScheduleGeneration += 1;')) 'aboutToDisappear must invalidate pending frame callbacks.'
Assert-Contract ($disappearText.Contains('this.hasScheduledInitialReaderOpen = false;')) 'aboutToDisappear must release the scheduling guard.'
Assert-Contract ($disappearText.Contains('this.scheduledFrameCallback = null;')) 'aboutToDisappear must release the retained callback.'

$scheduleText = $pageText.Substring($scheduleStart, $payloadResolverStart - $scheduleStart)
Assert-Contract ($scheduleText.Contains('!this.isPageActive')) 'The deferred scheduler must require an active page.'
Assert-Contract ($scheduleText.Contains('this.hasOpenedReader')) 'The deferred scheduler must guard an existing destination.'
Assert-Contract ($scheduleText.Contains('this.hasScheduledInitialReaderOpen')) 'The deferred scheduler must guard an already scheduled destination.'
Assert-Contract ($scheduleText.Contains('const uiContext: UIContext = this.getUIContext();')) 'The deferred scheduler must bind to the page UIContext.'
Assert-Contract ($scheduleText.Contains('new MangaReaderNavigationFrameCallback')) 'The deferred scheduler must use the official frame callback boundary.'
Assert-Contract ($scheduleText.Contains('uiContext.postFrameCallback(frameCallback);')) 'The deferred scheduler must defer to the next frame.'
Assert-Contract ($scheduleText.Contains('scheduleGeneration !== this.navigationScheduleGeneration')) 'The frame callback must reject stale schedules.'
Assert-Contract ($scheduleText.Contains('this.hasScheduledInitialReaderOpen = false;')) 'The frame callback must release its guard before opening.'
Assert-Contract ($scheduleText.Contains("this.resolveReaderLaunchPayload('frame_idle');")) 'The frame-idle callback must retry payload resolution.'
Assert-Contract ($scheduleText.Contains('this.openInitialReader();')) 'Only the frame-idle callback may open the initial destination.'
Assert-Contract (-not $scheduleText.Contains('setTimeout(')) 'Timer turns must not be treated as a render-completion boundary.'

$openReaderText = $pageText.Substring($openReaderStart, $paramsBuilderStart - $openReaderStart)
Assert-Contract ($openReaderText.Contains("this.pathStack.pushPathByName('MangaReaderPage', params, false);")) 'The stable controller must receive the initial destination without animation.'
Assert-Contract (-not $openReaderText.Contains('this.pathStack =')) 'The Navigation controller reference must never be reassigned.'
Assert-Contract ($openReaderText.IndexOf("this.pathStack.pushPathByName('MangaReaderPage', params, false);") -lt $openReaderText.IndexOf('this.hasOpenedReader = true;')) 'The open guard must be committed after the destination is pushed.'
Assert-Contract ($openReaderText.Contains('return true;')) 'A successful initial open must be observable by the scheduler.'

Assert-Contract (-not $pageText.Contains('handleNavigationAppear')) 'Navigation onAppear must not mutate the route stack.'
Assert-Contract (-not $pageText.Contains('onDidBuild(): void')) 'onDidBuild must not be treated as a safe navigation commit boundary.'
Assert-Contract ($pageText.Contains('class MangaReaderNavigationFrameCallback extends FrameCallback')) 'Delayed recovery must use a typed FrameCallback.'
Assert-Contract ($pageText.Contains('onIdle(_timeLeftInNano: number): void')) 'The delayed callback must commit at frame idle.'
Assert-Contract ($pageText.Contains('private pathStack: NavPathStack = new NavPathStack();')) 'The Navigation controller must be a stable non-State field.'
Assert-Contract (-not $pageText.Contains('@State private pathStack: NavPathStack')) 'NavPathStack must not be decorated as component state.'
Assert-Contract ($pageText.Contains('private hasScheduledInitialReaderOpen: boolean = false;')) 'The deferred route commit must have a private idempotency guard.'
Assert-Contract ($pageText.Contains('private navigationScheduleGeneration: number = 0;')) 'The deferred route commit must invalidate stale callbacks.'

$pushCount = ([regex]::Matches($pageText, "pushPathByName\('MangaReaderPage'")).Count
Assert-Contract ($pushCount -eq 1) 'Exactly one MangaReaderPage push site is allowed.'
$openCallCount = ([regex]::Matches($pageText, 'this\.openInitialReader\(\);')).Count
Assert-Contract ($openCallCount -eq 1) 'Exactly one initial-reader open call is allowed, inside the frame-idle callback.'

[PSCustomObject]@{
  status = 'passed'
  payloadResolvedBeforeBuild = $true
  stableNonStateNavPathStack = $true
  frameIdleRecovery = $true
  pageShowRecovery = $true
  mangaReaderPushSites = $pushCount
  initialReaderOpenCalls = $openCallCount
} | ConvertTo-Json -Compress
