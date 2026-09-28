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
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-jsoup-has-pseudo-selector.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-jsoup-has-pseudo-selector.json'
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Legado Jsoup :has pseudo selector contract failed: $Message" }
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
  $runtimePath = Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html'
  $analyzer = [System.IO.File]::ReadAllText($analyzerPath, [System.Text.UTF8Encoding]::new($false, $true))
  $element = [System.IO.File]::ReadAllText($elementPath, [System.Text.UTF8Encoding]::new($false, $true))
  $runtime = [System.IO.File]::ReadAllText($runtimePath, [System.Text.UTF8Encoding]::new($false, $true))
  $fixture = Read-Utf8Json -Path $FixturePath

  Assert-Contract ($element.Contains("pseudo.name === 'has'")) 'DOM matcher must implement :has.'
  Assert-Contract ($element.Contains('elem.querySelectorAll(argument)')) 'DOM matcher must evaluate descendant :has selectors.'
  Assert-Contract ($element.Contains("argument.startsWith('>')")) 'DOM matcher must preserve direct-child :has semantics.'
  Assert-Contract ($analyzer.Contains("pseudo.name === 'has'")) 'large-document fallback must apply :has predicates.'
  Assert-Contract ($analyzer.Contains('matchesStringHasPseudo')) 'string fallback must evaluate :has against complete element content.'
  Assert-Contract ($analyzer.Contains('findDirectChildren(innerHtml)')) 'string fallback must distinguish direct-child :has selectors.'
  Assert-Contract ($runtime.Contains("name === 'has'")) 'ArkWeb runtime must recognize Jsoup :has.'
  Assert-Contract ($runtime.Contains('relativeSelector')) 'ArkWeb runtime must convert direct-child :has to a relative selector.'
  Assert-Contract ($runtime.Contains('legadoSelectWithJsoupRegex(node')) 'ArkWeb runtime must recursively evaluate nested :has selectors.'
  Assert-Contract (@($fixture.cases).Count -eq 5) 'fixture must cover descendant, direct-child, nested pseudo, miss and wildcard :has cases.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'has_descendant' }).Count -eq 1) 'fixture must include descendant :has.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'has_direct_child' }).Count -eq 1) 'fixture must include direct-child :has.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'has_nested_pseudo' }).Count -eq 1) 'fixture must include nested pseudo :has.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'has_no_match' }).Count -eq 1) 'fixture must include a no-match :has case.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'has_wildcard' }).Count -eq 1) 'fixture must include wildcard :has.'

  $result = [pscustomobject][ordered]@{
    status = 'passed'
    contract = 'legado_jsoup_has_pseudo_selector'
    assertions = 15
    fixture = [System.IO.Path]::GetRelativePath($RepositoryRoot, $FixturePath).Replace('\\', '/')
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    verification = 'static_source_contract_only;runtime_regression_deferred'
    impact = [pscustomobject][ordered]@{
      ruleStringCount = 70
      affectedSourceCount = 5
      baselineSourceCount = 458
    }
  }
} catch {
  $result = [pscustomobject][ordered]@{
    status = 'failed'
    contract = 'legado_jsoup_has_pseudo_selector'
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
}

$directory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
[System.IO.File]::WriteAllText($ResultPath, [string]($result | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') { exit 1 }
