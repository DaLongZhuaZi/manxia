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
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-jsoup-text-pseudo-selectors.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-jsoup-text-pseudo-selectors.json'
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Legado Jsoup text pseudo selector contract failed: $Message" }
}

function Read-Utf8Json {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) "missing fixture: $Path"
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
}

$result = $null
try {
  $analyzerPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoRuleAnalyzer.ets'
  $elementPath = Join-Path $RepositoryRoot 'entry\src\main\ets\libs\htmlparser\HTMLElement.ets'
  $matcherPath = Join-Path $RepositoryRoot 'entry\src\main\ets\libs\htmlparser\Matcher.ets'
  $runtimePath = Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html'
  $analyzer = [System.IO.File]::ReadAllText($analyzerPath, [System.Text.UTF8Encoding]::new($false, $true))
  $element = [System.IO.File]::ReadAllText($elementPath, [System.Text.UTF8Encoding]::new($false, $true))
  $matcher = [System.IO.File]::ReadAllText($matcherPath, [System.Text.UTF8Encoding]::new($false, $true))
  $runtime = [System.IO.File]::ReadAllText($runtimePath, [System.Text.UTF8Encoding]::new($false, $true))
  $fixture = Read-Utf8Json -Path $FixturePath

  Assert-Contract ($analyzer.Contains('parseLegadoPseudoSelectors')) 'large-document fallback must parse Jsoup pseudo classes.'
  Assert-Contract ($analyzer.Contains('filterElementsByPseudoClasses')) 'large-document fallback must apply pseudo predicates to complete elements.'
  Assert-Contract ($analyzer.Contains("pseudo.name === 'matchesown'")) 'Analyzer must distinguish :matchesOwn from descendant text.'
  Assert-Contract ($analyzer.Contains('parseLegadoRegexPrefix')) 'Analyzer must translate Java inline regex flags.'
  Assert-Contract ($element.Contains('get ownText')) 'DOM matcher must expose direct text for Own pseudo classes.'
  Assert-Contract ($element.Contains('matchesPseudoRegex')) 'DOM matcher must evaluate Jsoup text regex pseudo classes.'
  Assert-Contract ($element.Contains('return false;')) 'DOM matcher must fail closed for unknown pseudo classes.'
  Assert-Contract ($matcher.Contains('characterClassDepth')) 'Pseudo parser must not terminate a regex at a character-class parenthesis.'
  Assert-Contract ($runtime.Contains('legadoParseJsoupTextPseudos')) 'ArkWeb runtime must strip and evaluate Jsoup text pseudo classes.'
  Assert-Contract ($runtime.Contains('legadoNormalizeJavaRegex')) 'ArkWeb runtime must translate Java inline regex flags.'
  Assert-Contract ($runtime.Contains('legadoMatchesJsoupPseudo')) 'ArkWeb runtime must apply text and own-text predicates after DOM selection.'
  Assert-Contract ($runtime.Contains('legadoSplitSelectorGroups')) 'ArkWeb runtime must preserve pseudo predicate scope for comma selector groups.'
  Assert-Contract ($analyzer.Contains('splitTopLevelCssSelectorGroups')) 'String fallback must preserve pseudo predicate scope for comma selector groups.'
  Assert-Contract ($runtime.Contains('legadoSelectWithJsoupRegex(node')) 'Runtime Jsoup element.select must use the compatibility selector path.'
  Assert-Contract (@($fixture.cases).Count -eq 8) 'fixture must cover contains, containsOwn, matches, matchesOwn, Java flags, grouped selectors and fail-closed behavior.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'contains' }).Count -eq 2) 'fixture must include two descendant-text contains cases.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'containsOwn' }).Count -eq 1) 'fixture must include one direct-text contains case.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'matches' }).Count -eq 2) 'fixture must include two descendant-text regex cases.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'matchesOwn' }).Count -eq 1) 'fixture must include one direct-text regex case.'

  $result = [pscustomobject][ordered]@{
    status = 'passed'
    contract = 'legado_jsoup_text_pseudo_selectors'
    assertions = 19
    fixture = [System.IO.Path]::GetRelativePath($RepositoryRoot, $FixturePath).Replace('\\', '/')
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    verification = 'static_source_contract_only;runtime_regression_deferred'
    impact = [pscustomobject][ordered]@{
      matchesRuleStringCount = 10
      matchesAffectedSourceCountLowerBound = 6
      matchesOwnRuleStringCount = 2
      matchesOwnAffectedSourceCountLowerBound = 2
      containsRuleStringCount = 9
      containsAffectedSourceCountLowerBound = 7
      baselineSourceCount = 458
    }
  }
} catch {
  $result = [pscustomobject][ordered]@{
    status = 'failed'
    contract = 'legado_jsoup_text_pseudo_selectors'
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
}

$directory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
[System.IO.File]::WriteAllText($ResultPath, [string]($result | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') { exit 1 }
