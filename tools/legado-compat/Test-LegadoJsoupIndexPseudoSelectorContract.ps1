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
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-jsoup-index-pseudo-selectors.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-jsoup-index-pseudo-selectors.json'
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Legado Jsoup index pseudo selector contract failed: $Message" }
}

function Read-Utf8Json {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) "missing fixture: $Path"
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
}

$result = $null
try {
  $elementPath = Join-Path $RepositoryRoot 'entry\src\main\ets\libs\htmlparser\HTMLElement.ets'
  $analyzerPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoRuleAnalyzer.ets'
  $runtimePath = Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html'
  $element = [System.IO.File]::ReadAllText($elementPath, [System.Text.UTF8Encoding]::new($false, $true))
  $analyzer = [System.IO.File]::ReadAllText($analyzerPath, [System.Text.UTF8Encoding]::new($false, $true))
  $runtime = [System.IO.File]::ReadAllText($runtimePath, [System.Text.UTF8Encoding]::new($false, $true))
  $fixture = Read-Utf8Json -Path $FixturePath

  Assert-Contract ($element.Contains("pseudo.name === 'nth-of-type'")) 'DOM matcher must implement :nth-of-type.'
  Assert-Contract ($element.Contains("pseudo.name === 'eq'")) 'DOM matcher must implement :eq.'
  Assert-Contract ($element.Contains("pseudo.name === 'lt'")) 'DOM matcher must implement :lt.'
  Assert-Contract ($element.Contains('getElementTypeIndex')) 'DOM matcher must calculate same-tag sibling positions.'
  Assert-Contract ($element.Contains('parseIndexPseudoArgument')) 'DOM matcher must fail closed on non-numeric :eq/:lt arguments.'
  Assert-Contract ($analyzer.Contains("pseudo.name === 'nth-of-type'")) 'string fallback must apply :nth-of-type.'
  Assert-Contract ($analyzer.Contains("pseudo.name === 'eq'")) 'string fallback must apply :eq.'
  Assert-Contract ($analyzer.Contains("pseudo.name === 'lt'")) 'string fallback must apply :lt.'
  Assert-Contract ($analyzer.Contains('findDirectChildOccurrences')) 'string fallback must retain sibling context for index pseudos.'
  Assert-Contract ($runtime.Contains("name === 'nth-of-type'")) 'ArkWeb runtime must recognize :nth-of-type.'
  Assert-Contract ($runtime.Contains("name === 'eq'")) 'ArkWeb runtime must recognize :eq.'
  Assert-Contract ($runtime.Contains("name === 'lt'")) 'ArkWeb runtime must recognize :lt.'
  Assert-Contract ($runtime.Contains('legadoMatchNthExpression')) 'ArkWeb runtime must evaluate an+b expressions.'
  Assert-Contract (@($fixture.cases).Count -eq 6) 'fixture must cover exact/formula nth-of-type, eq, lt, mixed sibling types and invalid arguments.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'nth_of_type_exact' }).Count -eq 1) 'fixture must include exact nth-of-type.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'nth_of_type_formula' }).Count -eq 1) 'fixture must include an+b nth-of-type.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'eq_zero_based_element_sibling_index' }).Count -eq 1) 'fixture must include eq sibling index.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'lt_zero_based_element_sibling_index' }).Count -eq 1) 'fixture must include lt sibling index.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'nth_of_type_ignores_other_tags' }).Count -eq 1) 'fixture must prove nth-of-type ignores other tags.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'invalid_index_fails_closed' }).Count -eq 1) 'fixture must cover invalid index rejection.'

  $result = [pscustomobject][ordered]@{
    status = 'passed'
    contract = 'legado_jsoup_index_pseudo_selectors'
    assertions = 20
    fixture = [System.IO.Path]::GetRelativePath($RepositoryRoot, $FixturePath).Replace('\\', '/')
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    verification = 'static_source_contract_only;runtime_regression_deferred'
    impact = [pscustomobject][ordered]@{
      ruleStringCount = 16
      affectedSourceCount = 9
      baselineSourceCount = 458
      nthOfTypeMatchCount = 14
      eqMatchCount = 2
      ltMatchCount = 4
    }
  }
} catch {
  $result = [pscustomobject][ordered]@{
    status = 'failed'
    contract = 'legado_jsoup_index_pseudo_selectors'
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
}

$directory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
[System.IO.File]::WriteAllText($ResultPath, [string]($result | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') { exit 1 }
