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
    throw "Novel single-source search starter contract failed: $Message"
  }
}

$pagePath = Join-Path $RepositoryRoot 'entry\src\main\ets\pages\NovelSearchPage.ets'
$pageText = (Read-Utf8Text -Path $pagePath).Replace("`r`n", "`n")

$starterStart = $pageText.IndexOf("@Builder`n  buildSingleSourceSearchStarter()")
$buildStart = $pageText.IndexOf('  build() {')
$initialSurfaceStart = $pageText.IndexOf('if (this.hasSearched && !this.singleSourceId && this.sourceResults.length > 0)')

Assert-Contract ($starterStart -ge 0) 'The single-source starter builder must exist.'
Assert-Contract ($buildStart -gt $starterStart) 'The single-source starter must be declared before build().'
Assert-Contract ($initialSurfaceStart -gt $buildStart) 'The initial search surface must continue to render from the history branch.'
Assert-Contract ($pageText.Contains("import { NovelExplorePageParams } from './NovelExplorePage';")) 'Discovery navigation must use the typed NovelExplorePageParams contract.'
Assert-Contract ($pageText.Contains('const SINGLE_SOURCE_SEARCH_SUGGESTIONS: string[] =')) 'A typed set of first-search examples must be present.'
Assert-Contract ($pageText.Contains('private searchFromSuggestion(keyword: string): void')) 'Suggestion taps must have a typed handler.'
Assert-Contract ($pageText.Contains('private getSingleSourceSearchSuggestions(): string[]')) 'First-search examples must be selected through a typed presentation helper.'
Assert-Contract ($pageText.Contains('!this.searchHistory.includes(suggestion)')) 'First-search examples must avoid duplicating existing history where possible.'
Assert-Contract ($pageText.Contains('this.searchFromSuggestion(suggestion);')) 'Every first-search example must use the normal search path.'
Assert-Contract ($pageText.Contains('private currentSourceSupportsExplore(): boolean')) 'Discovery availability must be checked against the selected source.'
Assert-Contract ($pageText.Contains("this.pathStack.pushPathByName('NovelExplorePage', params);")) 'The discovery action must route through the existing NovelExplorePage.'
Assert-Contract ($pageText.Contains(".id('novel_single_source_search_starter')")) 'The first-search surface must retain a stable UI identifier for device regression.'
Assert-Contract ($pageText.Contains('SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme)')) 'The first-search surface must reuse the existing panel design system.'

$starterText = $pageText.Substring($starterStart, $buildStart - $starterStart)
Assert-Contract ($starterText.Contains('Text(this.singleSourceName')) 'The starter must explain the selected-source search scope.'
Assert-Contract ($starterText.Contains('ForEach(this.getSingleSourceSearchSuggestions()')) 'The starter must present non-duplicated first-search examples.'
Assert-Contract ($starterText.Contains('this.openCurrentSourceExplore();')) 'The starter must expose the existing source-discovery entry when available.'
Assert-Contract ($starterText.Contains('currentSourceSupportsExplore()')) 'Sources without discovery support must receive an explicit, truthful fallback.'
Assert-Contract (-not $starterText.Contains('NovelSourceExecutor')) 'The UI starter must not introduce an executor-specific compatibility path.'

$historyText = $pageText.Substring($initialSurfaceStart, $pageText.Length - $initialSurfaceStart)
Assert-Contract ($historyText.Contains("if (this.singleSourceId) {`n                this.buildSingleSourceSearchStarter()")) 'The starter must render on the single-source initial surface, including when history exists.'
Assert-Contract ($historyText.Contains('FlexAlign.SpaceBetween')) 'History and the starter must be distributed across the available initial-screen space.'

[PSCustomObject]@{
  status = 'passed'
  typedDiscoveryRoute = $true
  firstSearchExamples = $true
  selectedSourceScope = $true
  historyAwareLayout = $true
  executorIsolation = $true
} | ConvertTo-Json -Compress
