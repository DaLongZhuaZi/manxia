[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$fixturePath = Join-Path $PSScriptRoot 'fixtures\explore-detail-route-contract.json'
$resolverPath = Join-Path $root 'entry\src\main\ets\Framework\Novel\LegadoExploreDetailRouteResolver.ets'
$navigatorPath = Join-Path $root 'entry\src\main\ets\Framework\Novel\LegadoExploreDetailNavigator.ets'
$tabPath = Join-Path $root 'entry\src\main\ets\Framework\Components\BookSourceTabContent.ets'
$pagePath = Join-Path $root 'entry\src\main\ets\pages\NovelExplorePage.ets'
$script:assertions = 0

function Assert-Contract {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Message
  )
  if (-not $Condition) {
    throw "Legado Explore detail route contract failed: $Message"
  }
  $script:assertions++
}

function Read-Utf8 {
  param([Parameter(Mandatory = $true)][string]$Path)
  return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Get-MethodBlock {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Marker
  )
  $start = $Text.IndexOf($Marker, [System.StringComparison]::Ordinal)
  Assert-Contract ($start -ge 0) "method marker is missing: $Marker"
  $next = $Text.IndexOf("`n  private ", $start + $Marker.Length, [System.StringComparison]::Ordinal)
  if ($next -lt 0) {
    $next = $Text.IndexOf("`n  build()", $start + $Marker.Length, [System.StringComparison]::Ordinal)
  }
  Assert-Contract ($next -gt $start) "method boundary is missing: $Marker"
  return $Text.Substring($start, $next - $start)
}

Assert-Contract (Test-Path -LiteralPath $fixturePath) 'fixture is missing'
Assert-Contract (Test-Path -LiteralPath $resolverPath) 'pure route resolver is missing'
Assert-Contract (Test-Path -LiteralPath $navigatorPath) 'shared Explore detail navigator is missing'

$fixture = Read-Utf8 -Path $fixturePath | ConvertFrom-Json
Assert-Contract ([int]$fixture.schemaVersion -eq 1) 'fixture schema version must be 1'
Assert-Contract ([string]$fixture.contract -eq 'legado_explore_detail_route') 'fixture contract identity is wrong'
Assert-Contract ($fixture.cases.Count -eq 6) 'fixture must cover six route equivalence classes'

$resolver = Read-Utf8 -Path $resolverPath
$navigator = Read-Utf8 -Path $navigatorPath
$tab = Read-Utf8 -Path $tabPath
$page = Read-Utf8 -Path $pagePath

foreach ($case in $fixture.cases) {
  Assert-Contract ($resolver.Contains("'$([string]$case.expectedRoute)'")) "route is not represented: $($case.expectedRoute)"
  Assert-Contract ($resolver.Contains("'$([string]$case.expectedReason)'")) "reason is not represented: $($case.expectedReason)"
}

Assert-Contract ($resolver.Contains('resultSourceId.length === 0')) 'empty result identity must be rejected'
Assert-Contract ($resolver.Contains('selectedSourceId.length === 0')) 'empty selected identity must be rejected'
Assert-Contract ($resolver.Contains('resultSourceId !== selectedSourceId')) 'result and selected identities must match exactly'
Assert-Contract ($resolver.Contains('source === null')) 'a missing source lookup must be rejected'
Assert-Contract ($resolver.Contains('source.bookSourceUrl !== resultSourceId')) 'the resolved source identity must match the result identity'
Assert-Contract ($resolver.Contains('source.bookSourceType === LegadoBookSourceType.IMAGE')) 'IMAGE must be selected from the persisted source type'
Assert-Contract ($resolver.Contains('source.bookSourceType < LegadoBookSourceType.TEXT') -and
  $resolver.Contains('source.bookSourceType > LegadoBookSourceType.FILE')) 'unsupported source types must be rejected'

$safeDiagnosticStart = $resolver.IndexOf('toSafeDiagnostic(', [System.StringComparison]::Ordinal)
$safeDiagnosticEnd = $resolver.IndexOf("`n  }", $safeDiagnosticStart, [System.StringComparison]::Ordinal)
Assert-Contract ($safeDiagnosticStart -ge 0 -and $safeDiagnosticEnd -gt $safeDiagnosticStart) 'safe diagnostic serializer is missing'
$safeDiagnostic = $resolver.Substring($safeDiagnosticStart, $safeDiagnosticEnd - $safeDiagnosticStart)
foreach ($forbidden in @('resultSourceId', 'selectedSourceId', 'bookSourceUrl', 'bookSourceName', 'bookUrl')) {
  Assert-Contract (-not $safeDiagnostic.Contains($forbidden)) "safe diagnostic leaks identity field: $forbidden"
}
Assert-Contract ($safeDiagnostic.Contains('identity=') -and $safeDiagnostic.Contains('sourceType=') -and
  $safeDiagnostic.Contains('route=') -and $safeDiagnostic.Contains('bridge=')) 'safe diagnostic fields are incomplete'

Assert-Contract ($navigator.Contains('getNovelSourceManager().getSource(book.sourceId)')) 'navigator must resolve the result source from the runtime manager'
Assert-Contract ($navigator.Contains('resolver.resolve(book.sourceId, selectedSourceId, source)')) 'navigator must use the pure resolver'
Assert-Contract ($navigator.Contains('LegadoExploreDetailRouteKind.REJECTED')) 'navigator must stop on structured rejection'
Assert-Contract ($navigator.Contains('LegadoExploreDetailRouteKind.MANGA')) 'navigator must own the IMAGE branch'
Assert-Contract ($navigator.Contains('ensureVirtualComicSource(source)')) 'the IMAGE branch must establish its virtual manga source'
Assert-Contract ($navigator.Contains("pushPathByName('MangaDetailPage'")) 'classic IMAGE detail must route to MangaDetailPage'
Assert-Contract ($navigator.Contains('contentType: UnifiedContentType.MANGA')) 'unified IMAGE detail must retain MANGA type'
Assert-Contract ($navigator.Contains('contentType: UnifiedContentType.NOVEL')) 'non-IMAGE detail must retain NOVEL type'
Assert-Contract ($navigator.Contains("AppStorage.setOrCreate<string>('legadoExploreDetailRouteDiagnostic'")) 'safe route evidence must be retained for runtime diagnostics'
Assert-Contract ($navigator.Contains('toSafeDiagnostic(')) 'the navigator must emit only the safe diagnostic projection'

$tabMethod = Get-MethodBlock -Text $tab -Marker 'private async openBookDetail(book: NovelSearchResult): Promise<void>'
$pageMethod = Get-MethodBlock -Text $page -Marker 'private async openBookDetail(book: NovelSearchResult): Promise<void>'
Assert-Contract ($tabMethod.Contains('openLegadoExploreDetail(this.pathStack, this.selectedBookSourceId, book)')) 'book-source tab must use the shared navigator'
Assert-Contract ($pageMethod.Contains('openLegadoExploreDetail(this.pathStack, this.selectedSourceId, book)')) 'standalone Explore page must use the shared navigator'
foreach ($method in @($tabMethod, $pageMethod)) {
  Assert-Contract (-not $method.Contains('UnifiedContentType.')) 'Explore UI methods must not duplicate content-type routing'
  Assert-Contract (-not $method.Contains('ensureVirtualComicSource')) 'Explore UI methods must not duplicate bridge routing'
  Assert-Contract ($method.Contains('LegadoExploreDetailOpenStatus.REJECTED')) 'Explore UI methods must surface structured rejection'
}

$output = [ordered]@{
  contract = 'legado_explore_detail_route'
  status = 'passed'
  assertions = $script:assertions
  cases = $fixture.cases.Count
  checkedFiles = @(
    $resolverPath.Substring($root.Length + 1),
    $navigatorPath.Substring($root.Length + 1),
    $tabPath.Substring($root.Length + 1),
    $pagePath.Substring($root.Length + 1)
  )
}
$output | ConvertTo-Json -Depth 5
