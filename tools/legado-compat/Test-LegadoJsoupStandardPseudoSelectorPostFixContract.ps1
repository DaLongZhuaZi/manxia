[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selectors.json',
  [string]$PreFixEvidencePath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selectors-pre-fix-20260809.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selectors-post-fix-20260809.json',
  [string]$SourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required file is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return (Read-StrictText -RelativePath $RelativePath | ConvertFrom-Json -Depth 100)
}

function Get-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Assert-Contract {
  param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @())
  if (-not $Condition) { throw "243 post-fix contract failed: $Detail" }
  $script:assertions++
  [void]$script:checks.Add([pscustomobject][ordered]@{
      id = $Id
      status = 'passed'
      detail = $Detail
      evidencePaths = @($Evidence)
    })
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value)
  $path = Get-RepoPath -RelativePath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 80), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$result = $null
$exitCode = 0
try {
  $fixture = Read-StrictJson -RelativePath $FixturePath
  $preFix = Read-StrictJson -RelativePath $PreFixEvidencePath
  $state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
  $sourcePackageBytes = [System.IO.File]::ReadAllBytes($SourcePackagePath)
  $sourcePackageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourcePackagePath).Hash.ToUpperInvariant()
  $sourceObjects = @($strictUtf8.GetString($sourcePackageBytes) | ConvertFrom-Json -Depth 100)
  $analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
  $elementPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
  $runtimePath = 'entry/src/main/resources/rawfile/legado_runtime.html'
  $legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
  $analyzer = Read-StrictText -RelativePath $analyzerPath
  $element = Read-StrictText -RelativePath $elementPath
  $runtime = Read-StrictText -RelativePath $runtimePath
  $legado = Read-StrictText -RelativePath $legadoPath

  Assert-Contract ([int]$fixture.baseline.sourceCount -eq 458 -and [string]$fixture.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$fixture.baseline.legadoCommit -eq $legadoCommit) 'fixture_baseline' 'fixture is bound to the frozen 458-source and Legado baselines.' @($FixturePath)
  Assert-Contract ($sourcePackageHash -eq $baselineHash -and $sourceObjects.Count -eq 458) 'source_package_baseline' 'the raw source package hash and count remain frozen.' @($SourcePackagePath)
  Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine_baseline' 'machine fact baseline is unchanged.' @('tools/legado-compat/state/full-source-validation-state.json')
  Assert-Contract ((& git -C (Get-RepoPath -RelativePath 'legado') rev-parse HEAD 2>$null | Out-String).Trim() -eq $legadoCommit) 'legado_head' 'the local Legado checkout is pinned to the reference commit.' @($legadoPath)
  Assert-Contract ([string]$preFix.status -eq 'failed' -and [string]$preFix.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and -not [bool]$preFix.semanticMatchAllowed -and @($preFix.runtimeActionsPerformed).Count -eq 0) 'failure_witness_preserved' 'the pre-fix failure witness remains failed and static-only.' @($PreFixEvidencePath)
  Assert-Contract (@($fixture.cases).Count -eq 6 -and [int]$fixture.pseudoCounts.total -eq 52 -and @($fixture.affectedSourceOrdinals).Count -eq 21) 'fixture_shape' 'six deterministic cases and the 52-rule/21-source impact set remain bound.' @($FixturePath)

  $actualOrdinals = New-Object 'System.Collections.Generic.HashSet[int]'
  foreach ($pseudoName in @('first-child', 'last-child', 'nth-child', 'only-child')) {
    $count = 0
    foreach ($sourceObject in $sourceObjects) {
      $sourceJson = $sourceObject | ConvertTo-Json -Depth 100 -Compress
      $matches = [regex]::Matches($sourceJson, [regex]::Escape(':' + $pseudoName))
      if ($matches.Count -gt 0) { [void]$actualOrdinals.Add([array]::IndexOf($sourceObjects, $sourceObject) + 1) }
      $count += $matches.Count
    }
    $expected = [int](Get-PropertyValue -Object $fixture.pseudoCounts -Name $pseudoName -Default 0)
    Assert-Contract ($count -eq $expected) "$pseudoName`_impact" ("frozen package count for :$pseudoName is $expected.") @($FixturePath)
  }
  $expectedOrdinals = @($fixture.affectedSourceOrdinals | ForEach-Object { [int]$_ } | Sort-Object)
  Assert-Contract (($actualOrdinals | Sort-Object) -join ',' -eq ($expectedOrdinals -join ',') -and $actualOrdinals.Count -eq 21) 'affected_ordinals' 'the frozen affected ordinal set is unchanged.' @($FixturePath)
  Assert-Contract ([int]$fixture.largeDocument.thresholdBytesExclusive -eq 50000 -and [int]$fixture.largeDocument.fillerRepeat -gt 1000) 'large_fixture' 'the fixture remains above the analyzer string-fallback threshold.' @($FixturePath)

  Assert-Contract ($analyzer.Contains('const HTML_SIZE_THRESHOLD = 50000') -and $analyzer.Contains('return this.getElementsByCSSChain(selector);')) 'large_document_path' 'large responses still enter the deterministic string fallback.' @($analyzerPath)
  Assert-Contract ($analyzer.Contains('private filterElementsByStandardChildPseudo(') -and $analyzer.Contains('StringElementSiblingPosition') -and $analyzer.Contains('siblingCount: number')) 'standard_helper_shape' 'the string fallback has a typed standard-child helper and sibling-count context.' @($analyzerPath)
  Assert-Contract ($analyzer.Contains("pseudo.name === 'first-child'") -and $analyzer.Contains("pseudo.name === 'last-child'") -and $analyzer.Contains("pseudo.name === 'nth-child'") -and $analyzer.Contains("pseudo.name === 'only-child'")) 'standard_dispatch' 'all four standard child pseudo names dispatch before the unknown-pseudo fail-closed branch.' @($analyzerPath)
  Assert-Contract ($analyzer.Contains('this.filterElementsByStandardChildPseudo(filtered, pseudo.name, contextHtml, argument)')) 'standard_dispatch_context' 'dispatch passes the original HTML context and normalized argument.' @($analyzerPath)
  Assert-Contract ($analyzer.Contains('siblingPosition.siblingIndex === 0') -and $analyzer.Contains('siblingPosition.siblingIndex === siblingPosition.siblingCount - 1') -and $analyzer.Contains('siblingPosition.siblingCount === 1')) 'first_last_only_semantics' 'first-child, last-child and only-child use element-child positions.' @($analyzerPath)
  Assert-Contract ($analyzer.Contains("pseudoName === 'nth-child' && argument.length === 0") -and $analyzer.Contains('siblingPosition.siblingIndex + 1') -and $analyzer.Contains('matchIndexPseudoExpression')) 'nth_child_semantics' 'nth-child is 1-based an+b and empty arguments fail closed.' @($analyzerPath)
  Assert-Contract ($analyzer.Contains('mapStringElementOccurrences(contextHtml, elements)') -and $analyzer.Contains('getStringElementSiblingPosition(contextHtml, occurrence)') -and $analyzer.Contains('findDirectChildOccurrences')) 'sibling_context_semantics' 'string fallback derives direct element-child context rather than counting text nodes.' @($analyzerPath)
  Assert-Contract ($analyzer.Contains('Do not silently widen selectors when a Jsoup pseudo class is unknown.') -and $analyzer.Contains('return [];')) 'unknown_pseudo_fail_closed' 'unknown pseudo classes remain explicit fail-closed results.' @($analyzerPath)

  foreach ($name in @('first-child', 'last-child', 'nth-child', 'only-child')) {
    Assert-Contract ($element.Contains("pseudo.name === '$name'")) ("dom_$name") ("DOM matcher contains the :$name branch.") @($elementPath)
  }
  Assert-Contract ($element.Contains('parent.children[0] === elem') -and $element.Contains('parent.children.length === 1') -and $element.Contains('matchNthChild(elem, parent, pseudo.argument)')) 'dom_standard_semantics' 'DOM matcher uses element children and 1-based nth-child evaluation.' @($elementPath)

  $pseudoParserStart = $runtime.IndexOf('var legadoParseJsoupTextPseudos = function')
  $pseudoParserEnd = $runtime.IndexOf('var legadoPseudoArgument = function', $pseudoParserStart)
  Assert-Contract ($pseudoParserStart -ge 0 -and $pseudoParserEnd -gt $pseudoParserStart) 'arkweb_parser_boundary' 'ArkWeb pseudo parser boundary is present.' @($runtimePath)
  $pseudoParser = $runtime.Substring($pseudoParserStart, $pseudoParserEnd - $pseudoParserStart)
  Assert-Contract ($pseudoParser.Contains("name === 'contains'") -and -not $pseudoParser.Contains("name === 'first-child'") -and -not $pseudoParser.Contains("name === 'last-child'") -and -not $pseudoParser.Contains("name === 'nth-child'") -and -not $pseudoParser.Contains("name === 'only-child'")) 'arkweb_native_standard_css' 'ArkWeb leaves standard CSS child pseudos in the browser selector.' @($runtimePath)
  Assert-Contract ($runtime.Contains('root.querySelectorAll(browserSelector)') -and $runtime.Contains('var browserSelector = parsed.selector.trim() ||') -and $runtime.Contains('legadoSelectWithJsoupRegex')) 'arkweb_selector_path' 'ArkWeb evaluates standard child pseudos through native querySelectorAll while retaining Jsoup-specific predicates.' @($runtimePath)
  Assert-Contract ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('getStringList')) 'legado_jsoup_consumer' 'fixed Legado delegates CSS selection to Jsoup Element.select.' @($legadoPath)

  foreach ($rule in @($fixture.representativeRules)) {
    $found = $false
    foreach ($sourceObject in $sourceObjects) {
      if (($sourceObject | ConvertTo-Json -Depth 100 -Compress).Contains([string]$rule)) { $found = $true; break }
    }
    Assert-Contract $found ("representative_" + ([regex]::Replace([string]$rule, '[^A-Za-z0-9]+', '_'))) ("representative rule is present: $rule") @($SourcePackagePath)
  }

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    evidenceType = 'post_fix_static_contract'
    issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
    status = 'passed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
    fixturePath = $FixturePath
    preFixEvidencePath = $PreFixEvidencePath
    changedPaths = @($analyzerPath, $elementPath, $runtimePath)
    impact = [pscustomobject][ordered]@{ ruleStringCount = 52; affectedSourceCount = 21; pseudoCounts = $fixture.pseudoCounts; affectedSourceOrdinals = $expectedOrdinals }
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_post_fix_static_contract_only;runtime_build_device_and_legado_diff_deferred_to_R4'
    closeCondition = 'R4 must execute all six selector cases, the 52-rule/21-source affected set, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    evidenceType = 'post_fix_static_contract'
    issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_post_fix_static_contract_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  }
}

Write-AtomicJson -RelativePath $ResultPath -Value $result
$result | ConvertTo-Json -Depth 80
if ($exitCode -ne 0) { exit $exitCode }
