[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = '',
  [string]$OutputPath = ''
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
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-jsoup-regex-attribute-nested-predicate-pre-fix-20260809.json'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Missing file: $Path"
  }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  try {
    return (Read-StrictText -Path $Path) | ConvertFrom-Json
  } catch {
    throw "Invalid JSON: $Path; $($_.Exception.Message)"
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
  [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 24), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Assert-Witness {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "Nested Jsoup regex predicate pre-fix witness failed: $Message"
  }
}

function Visit-StringValues {
  param(
    [Parameter(Mandatory = $true)][object]$Value,
    [Parameter(Mandatory = $true)][int]$SourceOrdinal,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$CandidateRecords
  )
  if ($null -eq $Value) {
    return
  }
  if ($Value -is [string]) {
    $text = [string]$Value
    if ($text.Contains('~=') -and $text -match '(?i):not\s*\(|:has\s*\(|:matches(?:Own)?\s*\(') {
      $CandidateRecords.Add([pscustomobject][ordered]@{
        sourceOrdinal = $SourceOrdinal
        textLength = $text.Length
        tokenFingerprint = ([BitConverter]::ToString(([Security.Cryptography.SHA256]::Create()).ComputeHash($strictUtf8.GetBytes($text)))).Replace('-', '').ToUpperInvariant().Substring(0, 16)
      })
    }
    return
  }
  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [System.Collections.IDictionary])) {
    foreach ($item in $Value) {
      Visit-StringValues -Value $item -SourceOrdinal $SourceOrdinal -CandidateRecords $CandidateRecords
    }
    return
  }
  foreach ($property in $Value.PSObject.Properties) {
    Visit-StringValues -Value $property.Value -SourceOrdinal $SourceOrdinal -CandidateRecords $CandidateRecords
  }
}

$result = $null
$exitCode = 1
try {
  $statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
  $packagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
  $legadoPath = Join-Path $RepositoryRoot 'legado\app\src\main\java\io\legado\app\model\analyzeRule\AnalyzeByJSoup.kt'
  $matcherPath = Join-Path $RepositoryRoot 'entry\src\main\ets\libs\htmlparser\Matcher.ets'
  $elementPath = Join-Path $RepositoryRoot 'entry\src\main\ets\libs\htmlparser\HTMLElement.ets'
  $analyzerPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoRuleAnalyzer.ets'
  $runtimePath = Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html'

  $state = Read-StrictJson -Path $statePath
  $fixture = Read-StrictJson -Path $FixturePath
  $package = Read-StrictJson -Path $packagePath
  Assert-Witness ([int]$state.baseline.sourceCount -eq 458) 'machine baseline source count drifted.'
  Assert-Witness ([string]$state.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'machine source hash drifted.'
  Assert-Witness ([string]$state.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine Legado commit drifted.'
  Assert-Witness ([string]$fixture.contract -eq 'legado_jsoup_regex_attribute_nested_predicate') 'nested predicate fixture contract changed.'
  Assert-Witness (@($fixture.cases).Count -eq 7) 'nested predicate fixture must contain seven cases.'
  Assert-Witness (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'jsoup_regex_nested_not' }).Count -eq 2) 'fixture must contain two :not regex cases.'
  Assert-Witness (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'jsoup_nested_has_not' }).Count -eq 1) 'fixture must contain one :has/:not composition.'
  Assert-Witness (@($fixture.cases | Where-Object { [string]$_.semantics -eq 'jsoup_invalid_regex_nested_not' }).Count -eq 1) 'fixture must contain one invalid-regex case.'

  $legado = Read-StrictText -Path $legadoPath
  $matcher = Read-StrictText -Path $matcherPath
  $element = Read-StrictText -Path $elementPath
  $analyzer = Read-StrictText -Path $analyzerPath
  $runtime = Read-StrictText -Path $runtimePath

  Assert-Witness ($legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'fixed Legado AnalyzeByJSoup selector handoff is missing.'
  Assert-Witness ($matcher.Contains('parsePseudoClass(selector, i)')) 'DOM Matcher pseudo parser path is missing.'
  Assert-Witness ($element.Contains("pseudo.name === 'has'")) 'DOM Matcher :has path is missing.'
  Assert-Witness (-not $element.Contains("pseudo.name === 'not'")) 'current DOM Matcher already contains a :not implementation; witness must be regenerated after a source change.'
  Assert-Witness ($analyzer.Contains('attributes.push(parsed.selector)')) 'string fallback attribute extraction path is missing.'
  Assert-Witness ($analyzer.Contains("pseudo.name === 'has'")) 'string fallback pseudo path is missing.'
  Assert-Witness (-not $analyzer.Contains("pseudo.name === 'not'")) 'current string fallback already contains a :not implementation; witness must be regenerated after a source change.'
  Assert-Witness ($runtime.Contains('regexSelectors.push({ name: name.toLowerCase(), pattern: value.trim() })')) 'ArkWeb regex attribute extraction path is missing.'
  Assert-Witness ($runtime.Contains("var browserSelector = parsed.selector.trim() || '*';")) 'ArkWeb browser selector fallback path is missing.'
  Assert-Witness (-not $runtime.Contains("pseudo.name === 'not'")) 'current ArkWeb runtime already contains a :not implementation; witness must be regenerated after a source change.'

  $candidateRecords = New-Object 'System.Collections.Generic.List[object]'
  $ordinal = 0
  foreach ($source in $package) {
    Visit-StringValues -Value $source -SourceOrdinal $ordinal -CandidateRecords $candidateRecords
    $ordinal++
  }
  $affectedOrdinals = @($candidateRecords | ForEach-Object { [int]$_.sourceOrdinal } | Select-Object -Unique)
  Assert-Witness ($candidateRecords.Count -ge 6) 'frozen package nested regex candidate count is unexpectedly small.'
  Assert-Witness ($affectedOrdinals.Count -ge 2) 'frozen package nested regex affected source count is unexpectedly small.'

  $sourceHashes = [ordered]@{}
  foreach ($path in @($matcherPath, $elementPath, $analyzerPath, $runtimePath)) {
    $sourceHashes[(Resolve-Path -LiteralPath $path).Path.Replace($RepositoryRoot + '\', '').Replace('\', '/')] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
  }
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_jsoup_regex_attribute_nested_predicate_pre_fix_contract'
    issueId = 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    classification = 'v2_nested_regex_attribute_predicate_context_not_preserved'
    baseline = [pscustomobject][ordered]@{
      sourceCount = [int]$state.baseline.sourceCount
      sourcePackageSha256 = [string]$state.baseline.sourcePackageSha256
      legadoCommit = [string]$state.baseline.legadoCommit
    }
    fixture = 'tools/legado-compat/fixtures/legado-jsoup-regex-attribute-nested-predicate.json'
    affectedNestedCandidateStringCount = $candidateRecords.Count
    affectedNestedCandidateSourceCountLowerBound = $affectedOrdinals.Count
    frozenLegadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
    staticWitnesses = @(
      [pscustomobject][ordered]@{ path = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'; finding = 'unknown pseudo classes fail closed and no :not branch is present; nested attribute selectors are not evaluated as a negated selector.' },
      [pscustomobject][ordered]@{ path = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'; finding = 'parseLegadoAttributeSelectors removes nested [attr~=regex] before pseudo parsing, leaving :not() or :has() argument context without the predicate.' },
      [pscustomobject][ordered]@{ path = 'entry/src/main/resources/rawfile/legado_runtime.html'; finding = 'legadoParseRegexAttributeSelectors removes nested regex attributes before browserSelector is passed to querySelectorAll; :not is not collected as a Jsoup pseudo.' }
    )
    currentHeadHashes = $sourceHashes
    rootCauseDecision = 'pending_failure_contract; keep under ISSUE-COMPAT-234 unless the three path witnesses prove a distinct primary cause.'
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_nested_predicate_pre_fix_witness_only;source_fix_and_runtime_regression_deferred'
    fixtureSha256 = (Get-FileHash -LiteralPath $FixturePath -Algorithm SHA256).Hash.ToUpperInvariant()
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_jsoup_regex_attribute_nested_predicate_pre_fix_contract'
    issueId = 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
    status = 'contract_error'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    error = $_.Exception.Message
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_nested_predicate_pre_fix_witness_only;source_fix_and_runtime_regression_deferred'
  }
}

Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Compress
exit $exitCode
