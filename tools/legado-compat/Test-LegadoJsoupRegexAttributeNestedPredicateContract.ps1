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
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if ([string]::IsNullOrWhiteSpace($FixturePath)) {
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-jsoup-regex-attribute-nested-predicate.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-jsoup-regex-attribute-nested-predicate-20260809.json'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$assertions = 0

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "Nested Jsoup regex predicate contract failed: $Message"
  }
  $script:assertions++
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) "missing file: $Path"
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  Assert-Contract (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) "UTF-8 BOM is forbidden: $Path"
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  try {
    return (Read-StrictText -Path $Path) | ConvertFrom-Json
  } catch {
    throw "invalid JSON: $Path; $($_.Exception.Message)"
  }
}

function Write-AtomicJson {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][object]$Value
  )
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

$result = $null
try {
  $state = Read-StrictJson -Path (Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json')
  $fixture = Read-StrictJson -Path $FixturePath
  Assert-Contract ([int]$state.baseline.sourceCount -eq 458) 'baseline source count must remain 458.'
  Assert-Contract ([string]$state.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'source package hash drifted.'
  Assert-Contract ([string]$state.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'Legado commit drifted.'
  Assert-Contract ([string]$fixture.contract -eq 'legado_jsoup_regex_attribute_nested_predicate') 'fixture contract changed.'
  Assert-Contract (@($fixture.cases).Count -eq 7) 'fixture case count changed.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.expectedOutcome -eq 'matched' }).Count -eq 6) 'matched case count changed.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.expectedOutcome -eq 'selector_error_or_fail_closed' }).Count -eq 1) 'invalid-regex case classification changed.'

  $paths = [ordered]@{
    matcher = Join-Path $RepositoryRoot 'entry\src\main\ets\libs\htmlparser\Matcher.ets'
    element = Join-Path $RepositoryRoot 'entry\src\main\ets\libs\htmlparser\HTMLElement.ets'
    analyzer = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoRuleAnalyzer.ets'
    runtime = Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html'
    legado = Join-Path $RepositoryRoot 'legado\app\src\main\java\io\legado\app\model\analyzeRule\AnalyzeByJSoup.kt'
  }
  $texts = [ordered]@{}
  foreach ($entry in $paths.GetEnumerator()) {
    $texts[$entry.Key] = Read-StrictText -Path $entry.Value
  }

  Assert-Contract ($texts.matcher.Contains('parsePseudoClass(selector, i)')) 'Matcher pseudo parser must remain the shared DOM entry.'
  Assert-Contract ($texts.matcher.Contains('characterClassDepth')) 'Matcher must retain nested regex character-class parsing.'
  Assert-Contract ($texts.matcher.Contains('isValidLegadoAttributeSelector')) 'Matcher must expose invalid ~= regex validation for nested :not fail-closed semantics.'
  Assert-Contract ($texts.element.Contains("pseudo.name === 'not'")) 'DOM matcher must implement :not.'
  Assert-Contract ($texts.element.Contains('matchesSelectorChainAtElement')) 'DOM :not must evaluate nested selector chains against the current element.'
  Assert-Contract ($texts.element.Contains('Matcher.parseSelector(argument)')) 'DOM :not must support selector lists through Matcher.'
  Assert-Contract ($texts.analyzer.Contains('let parenthesisDepth = 0')) 'string fallback attribute extraction must track pseudo argument depth.'
  Assert-Contract ($texts.analyzer.Contains('if (parenthesisDepth === 0 && bracketDepth === 0)')) 'string fallback must extract ~= only at selector top level.'
  Assert-Contract ($texts.analyzer.Contains("pseudo.name === 'not'")) 'string fallback must implement :not.'
  Assert-Contract ($texts.analyzer.Contains('matchesStringNestedSelector')) 'string fallback :not must evaluate the current element, not only descendants.'
  Assert-Contract ($texts.runtime.Contains('var parenthesisDepth = 0')) 'ArkWeb attribute extraction must track pseudo argument depth.'
  Assert-Contract ($texts.runtime.Contains('if (parenthesisDepth > 0 || bracketDepth > 0)')) 'ArkWeb must preserve nested attribute predicates.'
  Assert-Contract ($texts.runtime.Contains("name === 'not'")) 'ArkWeb pseudo parser must collect :not.'
  Assert-Contract ($texts.runtime.Contains('legadoMatchesJsoupSelector')) 'ArkWeb must evaluate nested selectors against the current node.'
  Assert-Contract ($texts.runtime.Contains('legadoMatchesAnyJsoupSelector')) 'ArkWeb must support selector lists inside :not.'
  Assert-Contract ($texts.runtime.Contains('legadoSelectorHasInvalidRegexAttribute')) 'ArkWeb must reject invalid nested ~= regex instead of widening :not.'
  Assert-Contract ($texts.legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'Legado AnalyzeByJSoup selector handoff must remain bound.'

  $currentHeadHashes = [ordered]@{}
  foreach ($entry in $paths.GetEnumerator()) {
    $relative = [System.IO.Path]::GetRelativePath($RepositoryRoot, $entry.Value).Replace('\', '/')
    $currentHeadHashes[$relative] = (Get-FileHash -LiteralPath $entry.Value -Algorithm SHA256).Hash.ToUpperInvariant()
  }
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_jsoup_regex_attribute_nested_predicate_contract'
    issueId = 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
    status = 'passed'
    assertions = $assertions
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    fixture = [System.IO.Path]::GetRelativePath($RepositoryRoot, $FixturePath).Replace('\', '/')
    verification = 'static_source_contract_only;runtime_regression_and_legado_differential_deferred'
    semantics = [pscustomobject][ordered]@{
      not = 'negates the complete nested selector; selector lists are OR inside :not.'
      regexAttribute = 'Jsoup ~= remains regular-expression matching, including Java inline flags.'
      missingAttribute = 'missing attributes do not match the nested attribute selector, so :not keeps the element.'
      invalidRegex = 'must fail closed or produce a structured selector error; it must not silently widen the result.'
    }
    impact = [pscustomobject][ordered]@{
      baselineSourceCount = 458
      nestedCandidateStringCountLowerBound = 6
      nestedCandidateSourceCountLowerBound = 2
    }
    currentHeadHashes = $currentHeadHashes
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_jsoup_regex_attribute_nested_predicate_contract'
    issueId = 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    error = $_.Exception.Message
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
  }
}

Write-AtomicJson -Path $ResultPath -Value $result
$result | ConvertTo-Json -Compress
if ([string]$result.status -ne 'passed') { exit 1 }
exit 0
