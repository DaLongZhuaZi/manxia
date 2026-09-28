[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-url-attribute-duplicate-post-fix-011-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$sourceCount = 458
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-011'

function Get-RepositoryPath([string]$RelativePath) {
  if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $RelativePath }
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText([string]$RelativePath, [switch]$AllowBom) {
  $path = Get-RepositoryPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing input: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    if (-not $AllowBom) { throw "UTF-8 BOM is not allowed: $RelativePath" }
    return $strictUtf8.GetString($bytes).Substring(1)
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson([string]$RelativePath) {
  return (Read-StrictText $RelativePath | ConvertFrom-Json)
}

function Get-FileSha256([string]$RelativePath) {
  return (Get-FileHash -LiteralPath (Get-RepositoryPath $RelativePath) -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-Contract([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "ISSUE011_POST_FIX_FAILED:$Message" }
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepositoryPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 60), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

$fixturePath = 'tools/legado-compat/fixtures/legado-url-attribute-duplicate-011.json'
$failurePath = 'tools/legado-compat/evidence/contract-legado-url-attribute-duplicate-pre-fix-011-20260809.json'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$legadoVersionPath = 'legado/gradle/libs.versions.toml'
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$jsEnginePath = 'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets'
$runtimePath = 'entry/src/main/resources/rawfile/legado_runtime.html'
$rhinoPath = 'entry/src/main/ets/Framework/Novel/RhinoWasmExecutor.ets'

$fixture = Read-StrictJson $fixturePath
$failure = Read-StrictJson $failurePath
$legado = Read-StrictText $legadoPath
$legadoVersions = Read-StrictText $legadoVersionPath
$analyzer = Read-StrictText $analyzerPath
$jsEngine = Read-StrictText $jsEnginePath
$runtime = Read-StrictText $runtimePath
$rhino = Read-StrictText $rhinoPath -AllowBom
$case = @($fixture.cases) | Select-Object -First 1
$assertions = 0

function Assert-AndCount([bool]$Condition, [string]$Message) {
  Assert-Contract $Condition $Message
  $script:assertions++
}

Assert-AndCount ([int]$fixture.baseline.sourceCount -eq $sourceCount) 'fixture source count drifted'
Assert-AndCount ([string]$fixture.baseline.sourcePackageSha256 -eq $sourceHash) 'fixture source hash drifted'
Assert-AndCount ([string]$fixture.baseline.legadoCommit -eq $legadoCommit) 'fixture Legado commit drifted'
Assert-AndCount ([string]$failure.status -eq 'failed_static_only') 'pre-fix failure witness must remain immutable'
Assert-AndCount ([string]$failure.issueId -eq $issueId) 'pre-fix failure witness issue drifted'
Assert-AndCount ([string]$legadoVersions -match '(?m)^jsoup\s*=\s*"1\.16\.2"') 'fixed Legado Jsoup version is not 1.16.2'
Assert-AndCount ($legado.Contains('if (url.isBlank() || textS.contains(url)) continue')) 'Legado value-level deduplication marker is missing'

$analyzerBoundaryStart = $analyzer.IndexOf('private getResultByLastRule(')
$analyzerBoundaryEnd = $analyzer.IndexOf('private isGenericCssAttributeName(', $analyzerBoundaryStart)
Assert-AndCount ($analyzerBoundaryStart -ge 0 -and $analyzerBoundaryEnd -gt $analyzerBoundaryStart) 'Analyzer terminal projection boundary missing'
$analyzerBoundary = $analyzer.Substring($analyzerBoundaryStart, $analyzerBoundaryEnd - $analyzerBoundaryStart)
Assert-AndCount ($analyzerBoundary.Contains('this.shouldDeduplicateLegadoAttributeValues(lowerRule)')) 'Analyzer terminal deduplication call missing'
Assert-AndCount ($analyzerBoundary.Contains('this.deduplicateLegadoAttributeValues(results)')) 'Analyzer terminal deduplication helper call missing'
Assert-AndCount ($analyzer.Contains('const values: string[] = elements.map((el: string): string => this.extractAttribute(el, result.attr));')) 'Analyzer list projection marker missing'
Assert-AndCount ($analyzer.Contains('this.shouldDeduplicateLegadoAttributeValues(result.attr)')) 'Analyzer list projection deduplication call missing'
Assert-AndCount ($analyzer.Contains('private deduplicateLegadoAttributeValues(values: string[]): string[]')) 'Analyzer shared deduplication helper missing'
Assert-AndCount ($analyzer.Contains('from Elements.eachAttr(), whose Jsoup 1.16.2 contract preserves order and')) 'Analyzer direct eachAttr boundary documentation missing'

$standardHelperCount = ([regex]::Matches($jsEngine, '__deduplicateLegadoAttributeValues\s*=\s*function')).Count
$nativeHelperCount = ([regex]::Matches($jsEngine, '__nativeDeduplicateLegadoAttributeValues\s*=\s*function')).Count
Assert-AndCount ($standardHelperCount -ge 1) 'standard JSVM deduplication helper missing'
Assert-AndCount ($nativeHelperCount -ge 2) 'all Native JSVM list projection helpers are not closed'
Assert-AndCount ($jsEngine.Contains('rawValues = __deduplicateLegadoAttributeValues(rawValues, split.attr);')) 'standard JSVM list projection call missing'
Assert-AndCount ($jsEngine.Contains('rawValues = __nativeDeduplicateLegadoAttributeValues(rawValues, split.attr);')) 'Native JSVM list projection call missing'
Assert-AndCount ($jsEngine.Contains('return __nativeDeduplicateLegadoAttributeValues(elements.eachAttr(split.attr), split.attr);')) 'embedded Native JSVM selector-list boundary missing'

$runtimeHelperCount = ([regex]::Matches($runtime, 'legadoDeduplicateAttributeValues\s*=\s*function')).Count
Assert-AndCount ($runtimeHelperCount -eq 1) 'ArkWeb runtime deduplication helper count drifted'
Assert-AndCount ($runtime.Contains('return legadoDeduplicateAttributeValues(values, attr);')) 'ArkWeb runtime list projection call missing'
Assert-AndCount ($runtime.Contains('eachAttr: function (name) {')) 'ArkWeb direct eachAttr API marker missing'
Assert-AndCount (-not $runtime.Contains('eachAttr: function (name) {\r\n          var attrs = [];\r\n          for (var i = 0; i < elements.length; i++) {\r\n            var val = elements[i].attr(name);\r\n            if (val) attrs.push(val);\r\n          }\r\n          return legadoDeduplicateAttributeValues')) 'ArkWeb direct eachAttr was incorrectly changed to deduplicate'
Assert-AndCount ($rhino.Contains('eachAttr(name)')) 'Rhino direct eachAttr API marker missing'
Assert-AndCount (-not $rhino.Contains('deduplicateLegadoAttributeValues')) 'Rhino direct eachAttr must not silently acquire list semantics'

$preFixValues = @($case.expectedV2PreFixSelectorValues)
$fixedValues = [System.Collections.Generic.List[string]]::new()
$seenValues = [System.Collections.Generic.HashSet[string]]::new()
foreach ($value in $preFixValues) {
  $text = [string]$value
  if ([string]::IsNullOrWhiteSpace($text) -or $seenValues.Contains($text)) { continue }
  $seenValues.Add($text) | Out-Null
  $fixedValues.Add($text)
}
$fixedString = [string]::Join("`n", $fixedValues)
Assert-AndCount ($fixedString -eq [string]$case.expectedLegadoString) 'deterministic post-fix projection does not match Legado'
Assert-AndCount (@($fixedValues).Count -eq @($case.expectedLegadoSelectorValues).Count) 'post-fix value count does not match Legado'

$jsoupJar = Get-ChildItem -Path (Get-RepositoryPath 'legado/.manxia-gradle-harness') -Filter 'jsoup-1.16.2.jar' -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
Assert-AndCount ($null -ne $jsoupJar) 'Jsoup 1.16.2 reference jar is missing from the fixed Legado harness cache'
$javap = Get-Command javap -ErrorAction SilentlyContinue
Assert-AndCount ($null -ne $javap) 'javap is required to verify Elements.eachAttr semantics'
$javapOutput = (& $javap.Source -classpath $jsoupJar.FullName -c -p org.jsoup.select.Elements 2>&1 | Out-String)
$eachAttrStart = $javapOutput.IndexOf('public java.util.List<java.lang.String> eachAttr(java.lang.String);')
$nextMethod = $javapOutput.IndexOf('public org.jsoup.select.Elements attr(', $eachAttrStart)
Assert-AndCount ($eachAttrStart -ge 0 -and $nextMethod -gt $eachAttrStart) 'Elements.eachAttr bytecode boundary missing'
$eachAttrBytecode = $javapOutput.Substring($eachAttrStart, $nextMethod - $eachAttrStart)
Assert-AndCount ($eachAttrBytecode.Contains('Method org/jsoup/nodes/Element.hasAttr')) 'Elements.eachAttr does not prove present-attribute handling'
Assert-AndCount ($eachAttrBytecode.Contains('Method java/util/List.add')) 'Elements.eachAttr does not prove ordered list append'
Assert-AndCount (-not $eachAttrBytecode.Contains('HashSet') -and -not $eachAttrBytecode.Contains('distinct')) 'Elements.eachAttr unexpectedly deduplicates direct callers'

$sourceFix = [ordered]@{
  analyzer = [ordered]@{ path = $analyzerPath; sha256 = Get-FileSha256 $analyzerPath; boundary = 'getResultByLastRule/getStringListByCSS'; status = 'source_fixed_static_only' }
  jsEngine = [ordered]@{ path = $jsEnginePath; sha256 = Get-FileSha256 $jsEnginePath; boundary = 'standard/native selector-list projection'; status = 'source_fixed_static_only' }
  arkWebRuntime = [ordered]@{ path = $runtimePath; sha256 = Get-FileSha256 $runtimePath; boundary = 'legadoGetStringListSingle'; status = 'source_fixed_static_only' }
  directJsoupApi = [ordered]@{ path = $rhinoPath; sha256 = Get-FileSha256 $rhinoPath; boundary = 'eachAttr remains duplicate-preserving'; status = 'contract_preserved' }
}

$evidence = [ordered]@{
  schemaVersion = 1
  kind = 'legado_issue_011_url_attribute_duplicate_post_fix_contract'
  status = 'passed_static_only'
  issueId = $issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  fixturePath = $fixturePath
  failureWitnessPath = $failurePath
  failureWitnessPreserved = $true
  deterministicProjection = [ordered]@{
    rule = [string]$case.rule
    preFixValues = $preFixValues
    postFixValues = @($fixedValues)
    expectedLegadoValues = @($case.expectedLegadoSelectorValues)
    postFixString = $fixedString
    expectedLegadoString = [string]$case.expectedLegadoString
    runtimeActionsPerformed = @()
  }
  referenceEachAttr = [ordered]@{
    version = '1.16.2'
    jarPath = $jsoupJar.FullName.Substring($RepositoryRoot.Length + 1).Replace('\', '/')
    jarSha256 = (Get-FileHash -LiteralPath $jsoupJar.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
    verification = 'javap bytecode shows hasAttr plus ordered List.add and no distinct/HashSet; direct eachAttr preserves duplicates and present empty attributes'
    bytecodeExcerpt = $eachAttrBytecode.Trim()
  }
  sourceFix = $sourceFix
  assertions = $assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_static_source_fix_and_contract_only;R4_runtime_build_device_and_legado_diff_deferred'
  reproductionCommand = 'pwsh -NoLogo -NoProfile -NonInteractive -File tools/legado-compat/Test-LegadoIssue011PostFixContract.ps1'
  closeCondition = 'R4 must execute the affected source equivalence class, deterministic Harness, same-input Legado differential, build and device gates before 011 can become passed or semantic_match.'
}
Write-AtomicJson $OutputPath $evidence
$evidence | ConvertTo-Json -Depth 60
