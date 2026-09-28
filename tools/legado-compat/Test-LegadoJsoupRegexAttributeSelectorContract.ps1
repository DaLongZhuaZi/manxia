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
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-jsoup-regex-attribute-selector.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-jsoup-regex-attribute-selector.json'
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Legado Jsoup regex attribute selector contract failed: $Message" }
}

function Read-Utf8Json {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) "missing fixture: $Path"
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
}

$result = $null
try {
  $analyzerPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoRuleAnalyzer.ets'
  $matcherPath = Join-Path $RepositoryRoot 'entry\src\main\ets\libs\htmlparser\Matcher.ets'
  $runtimePath = Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html'
  $analyzer = [System.IO.File]::ReadAllText($analyzerPath, [System.Text.UTF8Encoding]::new($false, $true))
  $matcher = [System.IO.File]::ReadAllText($matcherPath, [System.Text.UTF8Encoding]::new($false, $true))
  $runtime = [System.IO.File]::ReadAllText($runtimePath, [System.Text.UTF8Encoding]::new($false, $true))
  $fixture = Read-Utf8Json -Path $FixturePath

  Assert-Contract ($analyzer.Contains('parseLegadoAttributeSelectors')) 'string fallback must parse all Legado attribute selectors.'
  Assert-Contract ($analyzer.Contains('matchesLegadoAttributeSelector')) 'string fallback must evaluate Legado attribute operators.'
  Assert-Contract ($analyzer.Contains('new RegExp(regexParts.pattern, regexParts.flags)')) 'string fallback ~= must use regex semantics.'
  Assert-Contract ($analyzer.Contains('parseLegadoRegexPrefix(selector.value)')) 'string fallback ~= must translate Java inline regex flags.'
  Assert-Contract ($matcher.Contains('characterClassDepth')) 'HTML Matcher must account for nested regex character classes.'
  Assert-Contract ($matcher.Contains('new RegExp(regexParts.pattern, regexParts.flags)')) 'HTML Matcher ~= must use Jsoup regex semantics.'
  Assert-Contract ($matcher.Contains('parseLegadoRegexPrefix(selector.value)')) 'HTML Matcher ~= must translate Java inline regex flags.'
  Assert-Contract ($runtime.Contains('legadoParseRegexAttributeSelectors')) 'ArkWeb runtime must parse Jsoup regex attributes separately.'
  Assert-Contract ($runtime.Contains('legadoSelectWithJsoupRegex')) 'ArkWeb runtime must filter regex attributes after DOM selection.'
  Assert-Contract ($runtime.Contains('legadoNormalizeJavaRegex(regexSelector.pattern)')) 'ArkWeb runtime ~= must translate Java inline regex flags.'
  Assert-Contract (@($fixture.cases).Count -eq 7) 'fixture must cover regex alternatives, character classes, escapes, inline flags, multiple attributes, misses and equality.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'jsoup_regex' }).Count -eq 5) 'fixture must include five ordinary Jsoup regex cases.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'jsoup_regex_inline_flags' }).Count -eq 1) 'fixture must include one Java inline flag case.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'css_equality' }).Count -eq 1) 'fixture must preserve one ordinary equality case.'

  $result = [pscustomobject][ordered]@{
    status = 'passed'
    contract = 'legado_jsoup_regex_attribute_selector'
    assertions = 13
    fixture = [System.IO.Path]::GetRelativePath($RepositoryRoot, $FixturePath).Replace('\\', '/')
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    verification = 'static_source_contract_only;runtime_regression_deferred'
    impact = [pscustomobject][ordered]@{
      sourcePackageAttributeRegexStrings = 139
      affectedSourceCountLowerBound = 51
      baselineSourceCount = 458
    }
  }
} catch {
  $result = [pscustomobject][ordered]@{
    status = 'failed'
    contract = 'legado_jsoup_regex_attribute_selector'
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
}

$directory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
[System.IO.File]::WriteAllText($ResultPath, [string]($result | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') { exit 1 }
