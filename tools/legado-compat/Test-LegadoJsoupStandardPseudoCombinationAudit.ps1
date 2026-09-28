[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$SourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-combination-audit-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$script:assertions = 0

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing file: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100)
}

function Assert-Audit {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "243 combination audit failed: $Message" }
  $script:assertions++
}

function Write-AtomicJson {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][object]$Value
  )
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Get-CombinationFlags {
  param(
    [Parameter(Mandatory = $true)][string]$Rule,
    [Parameter(Mandatory = $true)][string]$PseudoName
  )
  $flags = New-Object 'System.Collections.Generic.List[string]'
  if ($Rule -match '(?is):has\(') { [void]$flags.Add('has') }
  if ($Rule -match '(?is):not\(') { [void]$flags.Add('not') }
  if ($Rule -match '(?is):(?:contains|containsown|matches|matchesown)\(') { [void]$flags.Add('text-pseudo') }
  if ($Rule.Contains('~=')) { [void]$flags.Add('regex-attribute') }
  if ($Rule.Contains('>')) { [void]$flags.Add('direct-child') }
  if ($Rule.Contains(',')) { [void]$flags.Add('selector-group') }
  if ($Rule.Contains('@')) { [void]$flags.Add('result-projection') }
  if ($Rule -match '&&|\|\||%%') { [void]$flags.Add('rule-composition') }
  if ($Rule -match '(?is)(?:^|[>+~\s,]):(?:first-child|last-child|nth-child|only-child|first-of-type|last-of-type|only-of-type|nth-of-type|nth-last-of-type)') {
    [void]$flags.Add('pseudo-only-compound')
  }
  if ($Rule -match "(?is):has\([^)]*>[^)]*:$( [regex]::Escape($PseudoName) )") {
    [void]$flags.Add('nested-standard-in-has')
  }
  if ($flags.Count -eq 0) { [void]$flags.Add('standalone') }
  return @($flags | Sort-Object)
}

function Visit-SourceValue {
  param(
    [object]$Value,
    [string]$Path,
    [int]$Ordinal,
    [System.Collections.Generic.List[object]]$Hits
  )
  if ($null -eq $Value) { return }
  if ($Value -is [string]) {
    if ($Path -notmatch '(?i)\.(rule[A-Za-z0-9_]*|searchUrl|exploreUrl|loginUrl)(?:\.|\[|$)') { return }
    $pattern = '(?i):(?<name>first-child|last-child|nth-child|only-child|first-of-type|last-of-type|only-of-type|nth-of-type|nth-last-of-type)(?=\(|[\s>@,\)\]:]|$)'
    foreach ($match in [regex]::Matches($Value, $pattern)) {
      $name = $match.Groups['name'].Value.ToLowerInvariant()
      $start = [Math]::Max(0, $match.Index - 110)
      $length = [Math]::Min(260, $Value.Length - $start)
      $snippet = $Value.Substring($start, $length).Replace("`r", ' ').Replace("`n", ' ')
      [void]$Hits.Add([pscustomobject][ordered]@{
          ordinal = $Ordinal
          path = $Path
          name = $name
          flags = @(Get-CombinationFlags -Rule $Value -PseudoName $name)
          snippet = $snippet
        })
    }
    return
  }
  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
    $index = 0
    foreach ($item in $Value) {
      Visit-SourceValue -Value $item -Path "$Path[$index]" -Ordinal $Ordinal -Hits $Hits
      $index++
    }
    return
  }
  foreach ($property in $Value.PSObject.Properties) {
    Visit-SourceValue -Value $property.Value -Path "$Path.$($property.Name)" -Ordinal $Ordinal -Hits $Hits
  }
}

$resultFullPath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot ($ResultPath.Replace('/', '\'))))
$evidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).TrimEnd('\') + '\'
if (-not $resultFullPath.StartsWith($evidenceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Combination evidence must remain under the evidence directory.'
}

$state = Read-StrictJson -Path (Get-RepoPath 'tools/legado-compat/state/full-source-validation-state.json')
$sources = @((Read-StrictText -Path $SourcePackagePath) | ConvertFrom-Json -Depth 100)
$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourcePackagePath).Hash.ToUpperInvariant()
Assert-Audit ($sourceHash -eq $baselineHash) 'frozen source package hash drifted.'
Assert-Audit ($sources.Count -eq 458) 'frozen source package count drifted.'
Assert-Audit ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline drifted.'
Assert-Audit ([string]$state.governance.activeIssueId -eq $issueId -and [string]$state.governance.status -eq 'running') '243 is not the active source issue.'
Assert-Audit ((& git -C (Get-RepoPath 'legado') rev-parse HEAD 2>$null | Out-String).Trim() -eq $legadoCommit) 'Legado checkout is not pinned.'

$hits = New-Object 'System.Collections.Generic.List[object]'
for ($index = 0; $index -lt $sources.Count; $index++) {
  Visit-SourceValue -Value $sources[$index] -Path ('$[' + ($index + 1) + ']') -Ordinal ($index + 1) -Hits $hits
}

$expectedCounts = [ordered]@{
  'first-child' = 4
  'last-child' = 3
  'nth-child' = 40
  'only-child' = 5
  'first-of-type' = 0
  'last-of-type' = 1
  'only-of-type' = 0
  'nth-of-type' = 14
  'nth-last-of-type' = 0
}
$counts = [ordered]@{}
foreach ($name in $expectedCounts.Keys) {
  $counts[$name] = @($hits | Where-Object { $_.name -eq $name }).Count
  Assert-Audit ($counts[$name] -eq [int]$expectedCounts[$name]) "frozen count drifted for :$name."
}
Assert-Audit ((($counts.Values | Measure-Object -Sum).Sum) -eq 67) 'standard pseudo total drifted from 67.'
$expectedOrdinals = @(21, 26, 70, 97, 112, 123, 144, 145, 147, 158, 195, 201, 223, 228, 231, 233, 251, 255, 278, 283, 284, 357, 402, 408, 452)
$actualOrdinals = @($hits | Select-Object -ExpandProperty ordinal -Unique | Sort-Object)
Assert-Audit (($actualOrdinals -join ',') -eq ($expectedOrdinals -join ',')) 'standard pseudo affected-source set drifted.'

$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$elementPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$matcherPath = 'entry/src/main/ets/libs/htmlparser/Matcher.ets'
$runtimePath = 'entry/src/main/resources/rawfile/legado_runtime.html'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$analyzer = Read-StrictText -Path (Get-RepoPath $analyzerPath)
$element = Read-StrictText -Path (Get-RepoPath $elementPath)
$matcher = Read-StrictText -Path (Get-RepoPath $matcherPath)
$runtime = Read-StrictText -Path (Get-RepoPath $runtimePath)
$legado = Read-StrictText -Path (Get-RepoPath $legadoPath)
Assert-Audit ($analyzer.Contains('matchesStringHasPseudo') -and $analyzer.Contains('filterElementsByStandardChildPseudo') -and $analyzer.Contains('filterElementsByIndexPseudo')) 'string fallback nested/standard consumers are missing.'
Assert-Audit ($element.Contains('matchesHasDirectChildRelativeSelector') -and $element.Contains('matchesSelectorChainAtElement') -and $element.Contains('matchesJsoupEmptyPseudo')) 'DOM nested/standard consumers are missing.'
Assert-Audit ($matcher.Contains('parseSelector') -and $matcher.Contains('parsePseudoClass') -and $matcher.Contains('parseAttributeSelector')) 'DOM selector parser is incomplete.'
Assert-Audit ($runtime.Contains('legadoSelectWithJsoupRegex') -and $runtime.Contains('legadoMatchesJsoupPseudo') -and $runtime.Contains("targetSelector = '*';")) 'ArkWeb owning-compound consumer is incomplete.'
Assert-Audit ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado selector consumer is missing.'

$complexNested = @($hits | Where-Object {
    $_.name -eq 'only-child' -and $_.ordinal -in @(357, 402) -and
    $_.flags -contains 'has' -and $_.flags -contains 'text-pseudo' -and $_.flags -contains 'regex-attribute'
  })
$coverageMatrix = @(
  [pscustomobject][ordered]@{
    id = 'standard-child-position'
    observedOccurrences = 52
    status = 'covered_by_existing_static_fixtures'
    evidencePaths = @('tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selectors.json', 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selectors-post-fix-20260809.json')
  }
  [pscustomobject][ordered]@{
    id = 'standard-of-type-position'
    observedOccurrences = 15
    status = 'covered_by_existing_static_fixtures'
    evidencePaths = @('tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selector-of-type-context.json', 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-of-type-post-fix-20260810.json')
  }
  [pscustomobject][ordered]@{
    id = 'direct-child-descendant-and-sibling'
    observedOccurrences = @($hits | Where-Object { $_.flags -contains 'direct-child' }).Count
    status = 'covered_by_existing_static_fixtures'
    evidencePaths = @('tools/legado-compat/fixtures/legado-jsoup-nested-descendant-pseudo-direct-child-context.json', 'tools/legado-compat/fixtures/legado-jsoup-sibling-combinator-context.json', 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selector-direct-child-split-context.json')
  }
  [pscustomobject][ordered]@{
    id = 'owning-compound-regex-and-text'
    observedOccurrences = @($hits | Where-Object { $_.flags -contains 'regex-attribute' -and $_.flags -contains 'text-pseudo' }).Count
    status = 'covered_by_existing_static_fixtures'
    evidencePaths = @('tools/legado-compat/fixtures/legado-arkweb-jsoup-regex-contains-composition-context.json', 'tools/legado-compat/fixtures/legado-arkweb-jsoup-compound-pseudo-context.json')
  }
  [pscustomobject][ordered]@{
    id = 'pseudo_only_compound_and_root_projection'
    observedOccurrences = @($hits | Where-Object { $_.flags -contains 'pseudo-only-compound' }).Count
    status = 'covered_by_existing_static_fixtures'
    evidencePaths = @('tools/legado-compat/fixtures/legado-arkweb-jsoup-empty-compound-pseudo-context.json', 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-empty-compound-post-fix-20260810.json')
  }
  [pscustomobject][ordered]@{
    id = 'real_nested_only_child_has_text_regex_composition'
    observedOccurrences = $complexNested.Count
    status = 'r4_exact_fixture_required_no_static_root_cause'
    evidencePaths = @('tools/legado-compat/fixtures/legado-arkweb-jsoup-empty-compound-pseudo-context.json', 'tools/legado-compat/fixtures/legado-jsoup-has-direct-child-relative-selector-context.json')
    note = 'Ordinals 357 and 402 contain the exact nested combination. Existing fixtures cover each constituent contract, but no static evidence can claim the complete conjunction is runtime-equivalent.'
  }
)

$currentHeadHashes = [ordered]@{}
foreach ($path in @($analyzerPath, $elementPath, $matcherPath, $runtimePath, $legadoPath)) {
  $currentHeadHashes[$path] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $path)).Hash.ToUpperInvariant()
}
$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_combination_coverage_audit'
  issueId = $issueId
  status = 'passed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  observedStandardPseudoCounts = $counts
  observedStandardPseudoOccurrenceCount = $hits.Count
  affectedSourceOrdinals = $actualOrdinals
  combinationFlagCounts = [ordered]@{
    directChild = @($hits | Where-Object { $_.flags -contains 'direct-child' }).Count
    selectorGroup = @($hits | Where-Object { $_.flags -contains 'selector-group' }).Count
    ruleComposition = @($hits | Where-Object { $_.flags -contains 'rule-composition' }).Count
    regexAndText = @($hits | Where-Object { $_.flags -contains 'regex-attribute' -and $_.flags -contains 'text-pseudo' }).Count
    pseudoOnlyCompound = @($hits | Where-Object { $_.flags -contains 'pseudo-only-compound' }).Count
    nestedOnlyChildHas = $complexNested.Count
  }
  complexNestedOccurrences = $complexNested
  coverageMatrix = $coverageMatrix
  consumerMatrix = @(
    [pscustomobject][ordered]@{ id = 'string_fallback'; path = $analyzerPath; status = 'static_consumer_present' }
    [pscustomobject][ordered]@{ id = 'dom_matcher'; path = $elementPath; status = 'static_consumer_present' }
    [pscustomobject][ordered]@{ id = 'selector_parser'; path = $matcherPath; status = 'nested_parser_present' }
    [pscustomobject][ordered]@{ id = 'arkweb_runtime'; path = $runtimePath; status = 'owning_compound_consumer_present' }
    [pscustomobject][ordered]@{ id = 'legado_reference'; path = $legadoPath; status = 'jsoup_select_reference_present' }
  )
  currentHeadHashes = $currentHeadHashes
  newRootCauseFound = $false
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_read_only_combination_audit;exact_nested_fixture_and_runtime_legado_diff_deferred_to_R4'
  nextAction = 'Keep ISSUE-COMPAT-243 verifying. Add the exact ordinal 357/402 nested combination to the R4 fixture matrix before runtime qualification; do not patch production code from this static coverage gap alone.'
  assertions = $script:assertions
}
Write-AtomicJson -Path $resultFullPath -Value $result
$result | ConvertTo-Json -Depth 100
