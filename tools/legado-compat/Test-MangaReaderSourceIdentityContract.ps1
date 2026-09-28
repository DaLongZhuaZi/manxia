[CmdletBinding()]
param([string]$RepositoryRoot = '')

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
    throw "Manga reader source identity contract failed: $Message"
  }
}

function Get-Segment {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$StartMarker,
    [Parameter(Mandatory = $true)][string]$EndMarker,
    [Parameter(Mandatory = $true)][string]$Name
  )
  $start = $Text.IndexOf($StartMarker)
  Assert-Contract ($start -ge 0) "$Name start marker must exist."
  $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length)
  Assert-Contract ($end -gt $start) "$Name end marker must follow its start marker."
  return $Text.Substring($start, $end - $start)
}

function Assert-RouterFields {
  param(
    [Parameter(Mandatory = $true)][string]$Segment,
    [Parameter(Mandatory = $true)][string]$RawVariable,
    [Parameter(Mandatory = $true)][string]$Name
  )
  $fields = @(
    'sourceId', 'sourcePkg', 'sourceName', 'contentType',
    'skipDatabaseLookup', 'chapterTitle',
    'readerHostMode', 'readerInstanceId', 'readerTitle',
    'originImportId', 'originImportKind'
  )
  foreach ($field in $fields) {
    Assert-Contract ($Segment.Contains("includes('$field')")) "$Name must detect $field."
    Assert-Contract ($Segment.Contains($field + ':')) "$Name must rebuild $field."
  }
  $explicitType = $Segment.IndexOf('if (hasContentType)')
  $sourceIdFallback = $Segment.IndexOf('else if (hasSourceId)', $explicitType + 1)
  Assert-Contract ($explicitType -ge 0) "$Name must preserve explicit contentType."
  Assert-Contract ($sourceIdFallback -gt $explicitType) "$Name may infer contentType only when it is absent."
  Assert-Contract ($Segment.Contains("String($RawVariable['contentType']) as MangaReaderContentType")) "$Name must copy contentType."
  Assert-Contract ($Segment.Contains("sourcePkg: hasSourcePkg ? String($RawVariable['sourcePkg']) : undefined")) "$Name must copy sourcePkg."
}

$readerText = Read-Utf8Text (Join-Path $RepositoryRoot 'entry\src\main\ets\pages\MangaReaderPage.ets')
$abilityText = Read-Utf8Text (Join-Path $RepositoryRoot 'entry\src\main\ets\pages\MangaReaderAbilityPage.ets')
$launcherText = Read-Utf8Text (Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Reader\MangaReaderAbilityLauncher.ets')
$storeText = Read-Utf8Text (Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Reader\MangaReaderAbilityParamStore.ets')
$viewerText = Read-Utf8Text (Join-Path $RepositoryRoot 'entry\src\main\ets\components\MangaViewer.ets')
$contextText = Read-Utf8Text (Join-Path $RepositoryRoot 'entry\src\main\ets\components\MangaAssetLoadContextResolver.ets')
$factoryText = Read-Utf8Text (Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Reader\MangaAssetRequestFactory.ets')
$loaderText = Read-Utf8Text (Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Reader\MangaAssetLoader.ets')

$showRouter = Get-Segment $readerText '      if (!this.pageParams) {' '    } else if (!initializedFromIsolatedStore) {' 'onPageShow Router'
$readyRouter = Get-Segment $readerText '  private resolveParamsFromRouter(): MangaReaderPageParams | null {' '  private startReaderFlow(): void {' 'onReady Router'
Assert-RouterFields $showRouter 'rawParamsObj' 'onPageShow Router'
Assert-RouterFields $readyRouter 'raw' 'onReady Router'

$navStack = Get-Segment $readerText '  private resolveParamsFromNavStack(): MangaReaderPageParams | null {' '  private resolveParamsFromRouter(): MangaReaderPageParams | null {' 'NavStack'
Assert-Contract ($navStack.Contains("getParamByName('MangaReaderPage') as MangaReaderPageParams[]")) 'NavStack must load typed params.'
Assert-Contract ($navStack.Contains('return latest as MangaReaderPageParams;')) 'NavStack must return complete params without reconstruction.'
Assert-Contract ($launcherText.Contains("fallbackStack.pushPathByName('MangaReaderPage', params);")) 'NavStack fallback must forward complete params.'

Assert-Contract ($launcherText.Contains('const instanceId = store.register(params);')) 'Ability launch must register complete params.'
Assert-Contract ($storeText.Contains('this.paramsMap.set(instanceId, params);')) 'Ability store must retain complete params.'
Assert-Contract ($storeText.Contains('payload.params = params;')) 'Ability window payload must retain complete params.'
$abilityCopy = Get-Segment $abilityText '  private buildIsolatedReaderParams(source: MangaReaderPageParams): MangaReaderPageParams {' '  @Builder' 'Ability copy'
$readerCopy = Get-Segment $readerText '  private buildIsolatedReaderParamsFromPayload(payload: MangaReaderAbilityWindowPayload): MangaReaderPageParams {' '  private resolveHostWindowIdForIsolatedReader(): number {' 'Reader Ability copy'
foreach ($field in @('sourceId', 'sourcePkg', 'contentType')) {
  Assert-Contract ($abilityCopy.Contains("$field`: source.$field")) "Ability page must copy $field."
  Assert-Contract ($readerCopy.Contains("$field`: source.$field")) "Reader Ability payload must copy $field."
}

$identityStart = $readerText.IndexOf('const identityResult: MangaIdentityResolveResult = await MangaIdentityResolver.getInstance().resolve(identityInput);')
$pkgWrite = $readerText.IndexOf('params.sourcePkg = identityResult.sourcePkg;', $identityStart)
$currentPkgWrite = $readerText.IndexOf('this.currentSourcePkg = identityResult.sourcePkg;', $identityStart)
$mangaWrite = $readerText.IndexOf('this.applyResolvedSourceIdentityToManga(params.manga, identityResult);', $identityStart)
$rawShaRefresh = $readerText.IndexOf('await this.refreshLegadoV2ImageTraceIdentity();', $identityStart)
Assert-Contract ($identityStart -ge 0) 'Identity resolution must exist.'
Assert-Contract ($readerText.IndexOf('params.sourceId = identityResult.sourceId;', $identityStart) -gt $identityStart) 'Resolved sourceId must update params.'
Assert-Contract ($pkgWrite -gt $identityStart) 'Resolved sourcePkg must update params.'
Assert-Contract ($currentPkgWrite -gt $pkgWrite) 'Resolved sourcePkg must update currentSourcePkg.'
Assert-Contract ($readerText.IndexOf('params.sourceName = identityResult.sourceName;', $identityStart) -gt $identityStart) 'Resolved sourceName must update params.'
Assert-Contract ($mangaWrite -gt $currentPkgWrite) 'Resolved identity must update manga.sourceInfo.'
Assert-Contract ($rawShaRefresh -gt $mangaWrite) 'Raw SHA lookup must follow final identity write-back.'
foreach ($marker in @(
  'manga.sourceInfo.sourceId = String(identityResult.sourceId);',
  'manga.sourceInfo.sourcePkg = identityResult.sourcePkg;',
  'manga.sourceInfo.sourceName = identityResult.sourceName;'
)) {
  Assert-Contract ($readerText.Contains($marker)) "Manga source identity marker missing: $marker"
}

$v2Decision = Get-Segment $readerText '  private shouldUseLegadoV2ImageTransport(): boolean {' '  private applyResolvedSourceIdentityToManga(' 'V2 decision'
foreach ($marker in @('this.pageParams?.sourcePkg', 'this.currentSourcePkg', 'this.readerState.currentManga?.sourceInfo?.sourcePkg')) {
  Assert-Contract ($v2Decision.Contains($marker)) "V2 decision marker missing: $marker"
}
Assert-Contract (([regex]::Matches($v2Decision, "startsWith\('legado\.image\.'\)")).Count -eq 3) 'V2 decision must cover all three identity locations.'

$rawSha = Get-Segment $readerText '  private async refreshLegadoV2ImageTraceIdentity(): Promise<void> {' '  private appendExtraRequestHeader(' 'raw SHA'
Assert-Contract ($rawSha.Contains('this.currentSourceId > 0')) 'Raw SHA must prefer resolved sourceId.'
Assert-Contract ($rawSha.Contains('getRawSourceDocumentSha256(sourceId)')) 'Raw SHA must resolve the lossless document.'
Assert-Contract ($readerText.Contains('sourceId: this.currentSourceId > 0 ? this.currentSourceId : 0')) 'Reader must pass sourceId to MangaViewer.'
Assert-Contract ($readerText.Contains('useLegadoV2ImageTransport: this.shouldUseLegadoV2ImageTransport()')) 'Reader must pass the V2 decision.'
Assert-Contract ($readerText.Contains('legadoSourceRawSha256: this.legadoSourceRawSha256')) 'Reader must pass raw SHA.'
Assert-Contract ($viewerText.Contains('input.sourceId = this.sourceId;')) 'Viewer must pass sourceId.'
Assert-Contract ($viewerText.Contains('input.useLegadoV2ImageTransport = this.useLegadoV2ImageTransport;')) 'Viewer must pass V2 decision.'
Assert-Contract ($viewerText.Contains('input.legadoSourceRawSha256 = this.legadoSourceRawSha256;')) 'Viewer must pass raw SHA.'
Assert-Contract ($contextText.Contains('requestContext.sourceId = input.sourceId;')) 'Load context must retain sourceId.'
Assert-Contract ($contextText.Contains('requestContext.useLegadoV2ImageTransport = input.useLegadoV2ImageTransport;')) 'Load context must retain V2 decision.'
Assert-Contract ($contextText.Contains('requestContext.legadoSourceRawSha256 = input.legadoSourceRawSha256;')) 'Load context must retain raw SHA.'
Assert-Contract ($factoryText.Contains('sourceId: context.sourceId')) 'Request factory must retain sourceId.'
Assert-Contract ($factoryText.Contains('request.useLegadoV2ImageTransport = context.useLegadoV2ImageTransport;')) 'Request factory must retain V2 decision.'
Assert-Contract ($factoryText.Contains('request.legadoSourceRawSha256 = context.legadoSourceRawSha256;')) 'Request factory must retain raw SHA.'
Assert-Contract ($loaderText.Contains('if (request.useLegadoV2ImageTransport)')) 'Asset loader must select V2 transport.'
Assert-Contract ($loaderText.Contains('request.legadoSourceRawSha256,')) 'Asset trace must receive raw SHA.'
Assert-Contract ($loaderText.Contains('request.loadOptions.sourceId || 0,')) 'Asset trace must receive sourceId.'

[PSCustomObject]@{
  status = 'passed'
  entrances = @('router', 'navStack', 'isolatedAbility')
  identityFields = @('sourceId', 'sourcePkg', 'contentType')
  routerFallbacks = 2
  v2Transport = $true
  rawShaTrace = $true
} | ConvertTo-Json -Compress
