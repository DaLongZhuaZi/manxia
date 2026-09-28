[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-url-attribute-duplicate-pre-fix-011-20260809.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/v2-issue-011-current-head-consumer-audit-pre-fix-20260809.json'
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

function Assert-Audit([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "ISSUE011_CURRENT_HEAD_AUDIT_FAILED:$Message" }
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepositoryPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 50), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

$failureWitness = Read-StrictJson $FailureWitnessPath
Assert-Audit ([string]$failureWitness.issueId -eq $issueId) 'failure witness issue mismatch'
Assert-Audit ([string]$failureWitness.status -eq 'failed_static_only') 'failure witness must remain failed_static_only'
Assert-Audit ([int]$failureWitness.baseline.sourceCount -eq $sourceCount) 'failure witness source count drifted'
Assert-Audit ([string]$failureWitness.baseline.sourcePackageSha256 -eq $sourceHash) 'failure witness hash drifted'

$paths = [ordered]@{
  analyzer = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
  workflow = 'entry/src/main/ets/Framework/Novel/LegadoWorkflowOrchestrator.ets'
  standardJsVm = 'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets'
  nativeJsVm = 'entry/src/main/ets/Framework/Novel/NativeJsEngine.ets'
  rhinoJsVm = 'entry/src/main/ets/Framework/Novel/RhinoWasmExecutor.ets'
  arkWebRuntime = 'entry/src/main/resources/rawfile/legado_runtime.html'
  sourceTypes = 'entry/src/main/ets/Framework/Novel/LegadoSourceTypes.ets'
  sourceManager = 'entry/src/main/ets/Framework/Novel/NovelSourceManager.ets'
  outputBridge = 'entry/src/main/ets/Framework/Novel/LegadoMangaSourceBridge.ets'
}
$contents = [ordered]@{}
foreach ($entry in $paths.GetEnumerator()) {
  $contents[$entry.Key] = if ($entry.Key -in @('rhinoJsVm', 'sourceTypes', 'sourceManager')) { Read-StrictText $entry.Value -AllowBom } else { Read-StrictText $entry.Value }
}

$analyzer = [string]$contents.analyzer
$analyzerFunctionStart = $analyzer.IndexOf('private getResultByLastRule(')
$analyzerFunctionEnd = $analyzer.IndexOf('private isGenericCssAttributeName(', $analyzerFunctionStart)
Assert-Audit ($analyzerFunctionStart -ge 0 -and $analyzerFunctionEnd -gt $analyzerFunctionStart) 'analyzer projection function boundary missing'
$analyzerProjection = $analyzer.Substring($analyzerFunctionStart, $analyzerFunctionEnd - $analyzerFunctionStart)
Assert-Audit ($analyzerProjection.Contains('results.push(text);')) 'analyzer projection push marker missing'
Assert-Audit (-not $analyzerProjection.Contains('results.includes(text)')) 'pre-fix analyzer already deduplicates values'

$listFunctionStart = $analyzer.IndexOf('private getStringListByCSS(selector: string): string[]')
Assert-Audit ($listFunctionStart -ge 0) 'analyzer list projection function missing'
$listFunctionEnd = $analyzer.IndexOf('private getElementsByCSS(', $listFunctionStart)
Assert-Audit ($listFunctionEnd -gt $listFunctionStart) 'analyzer list projection boundary missing'
$listProjection = $analyzer.Substring($listFunctionStart, $listFunctionEnd - $listFunctionStart)
Assert-Audit ($listProjection.Contains('elements.map((el: string): string => this.extractAttribute(el, result.attr))')) 'analyzer list projection marker missing'

$workflow = [string]$contents.workflow
Assert-Audit ($workflow.Contains('getStringAsync') -and $workflow.Contains('getUrlStringAsync') -and $workflow.Contains('getUrlStringListAsync')) 'workflow selector consumer markers missing'
Assert-Audit ($workflow.Contains('resolveRequestUrlTemplate')) 'workflow URL boundary marker missing'

$standardJsVm = [string]$contents.standardJsVm
$nativeJsVm = [string]$contents.nativeJsVm
$rhinoJsVm = [string]$contents.rhinoJsVm
$arkWebRuntime = [string]$contents.arkWebRuntime
Assert-Audit ($standardJsVm.Contains('__getStringListFromContent') -and $standardJsVm.Contains('eachAttr')) 'standard JSVM list consumer markers missing'
Assert-Audit ($nativeJsVm.Contains('eachAttr')) 'Native JSVM attribute-list consumer marker missing'
Assert-Audit ($rhinoJsVm.Contains('eachAttr')) 'Rhino JSVM list consumer marker missing'
Assert-Audit ($arkWebRuntime.Contains('getStringList: function') -and $arkWebRuntime.Contains('eachAttr')) 'ArkWeb runtime list consumer markers missing'

$sourceTypes = [string]$contents.sourceTypes
$sourceManager = [string]$contents.sourceManager
$outputBridge = [string]$contents.outputBridge
Assert-Audit ($sourceTypes.Contains('class LegadoRequestCarrier')) 'request carrier type is missing'
Assert-Audit ($sourceManager.Contains('resolveV2RequestCarrier') -and $sourceManager.Contains('requestCarrierKey')) 'request carrier manager boundary is missing'
Assert-Audit ($outputBridge.Contains('requestUrlTemplate') -and $outputBridge.Contains('requestCarrier')) 'output carrier handoff marker is missing'

$consumerMatrix = @(
  [ordered]@{ id = 'analyzer.css_terminal_attribute'; layer = 'Analyzer/Matcher'; path = $paths.analyzer; status = 'failed_static_only'; gap = 'getResultByLastRule pushes duplicate nonblank attributes; no value-level deduplication before string join.'; sourceLines = '3638-3660' },
  [ordered]@{ id = 'analyzer.css_string_list'; layer = 'Rule IR/Analyzer'; path = $paths.analyzer; status = 'failed_static_only'; gap = 'getStringListByCSS maps raw attributes without the Legado getResultLast deduplication boundary.'; sourceLines = '4663-4667' },
  [ordered]@{ id = 'workflow.search_explore_bookinfo_toc_content_file'; layer = 'Workflow'; path = $paths.workflow; status = 'inherits_analyzer_gap'; gap = 'Search/Explore/BookInfo/Toc/Content/File consume analyzer lists; no independent deduplication boundary is present.'; sourceLines = '318-410,506-535,782-835,2261-2350' },
  [ordered]@{ id = 'standard_jsvm.java_get_string_list'; layer = 'Standard JSVM'; path = $paths.standardJsVm; status = 'inherits_analyzer_gap'; gap = 'java.getStringList CSS path uses eachAttr/raw list projection without a Legado value-level deduplication helper.'; sourceLines = '3265-3330,4755-4760' },
  [ordered]@{ id = 'native_jsvm.java_get_string_list'; layer = 'Native JSVM'; path = $paths.nativeJsVm; status = 'inherits_analyzer_gap'; gap = 'Native JSVM exposes eachAttr/getStringList without a shared deduplication contract.'; sourceLines = '550-590' },
  [ordered]@{ id = 'rhino_jsvm.java_get_string_list'; layer = 'Rhino JSVM'; path = $paths.rhinoJsVm; status = 'inherits_analyzer_gap'; gap = 'Rhino-compatible eachAttr projection is not bound to the Legado deduplication contract.'; sourceLines = '507-530,1340-1365' },
  [ordered]@{ id = 'arkweb.default_runtime.java_get_string_list'; layer = 'ArkWeb runtime'; path = $paths.arkWebRuntime; status = 'inherits_analyzer_gap'; gap = 'legado_runtime.html returns raw eachAttr values and has no value-level deduplication helper.'; sourceLines = '2253-2265,2511-2549' },
  [ordered]@{ id = 'request_carrier.url_boundary'; layer = 'Request carrier'; path = $paths.sourceManager; status = 'mapped_static_only'; gap = ''; sourceLines = '158-220,2012-2070' },
  [ordered]@{ id = 'output.typed_handoff'; layer = 'Output projection'; path = $paths.outputBridge; status = 'mapped_static_only'; gap = ''; sourceLines = '920-930' }
)

$hashes = [ordered]@{}
foreach ($entry in $paths.GetEnumerator()) {
  $hashes[$entry.Key] = [ordered]@{ path = $entry.Value; sha256 = Get-FileSha256 $entry.Value }
}

$evidence = [ordered]@{
  schemaVersion = 1
  kind = 'legado_issue_011_current_head_consumer_audit_pre_fix'
  status = 'failed_static_only'
  issueId = $issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  failureWitnessPath = $FailureWitnessPath
  inventoryStatus = 'complete_static_inventory'
  consumerMatrix = $consumerMatrix
  unresolvedGapCount = @($consumerMatrix | Where-Object { [string]$_.status -in @('failed_static_only', 'inherits_analyzer_gap') }).Count
  currentHeadHashes = $hashes
  sourceEncodingObservations = [ordered]@{
    rhinoJsVm = 'utf8_bom_present_stripped_for_read_only_audit;source_not_modified'
    sourceTypes = 'utf8_bom_present_stripped_for_read_only_audit;source_not_modified'
    sourceManager = 'utf8_bom_present_stripped_for_read_only_audit;source_not_modified'
  }
  primaryCause = [ordered]@{
    classification = 'selector_extraction_vs_url_resolution_boundary'
    statement = 'The V2 source paths that project selector attribute lists do not share Legado AnalyzeByJSoup value-level deduplication. The workflow and carrier layers preserve the distinction but inherit the projection gap.'
  }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_static_consumer_inventory_only;source_fix_required_before_post_fix_contract;runtime_build_device_and_legado_diff_deferred'
  reproductionCommand = "pwsh -NoLogo -NoProfile -NonInteractive -File tools/legado-compat/Test-LegadoIssue011CurrentHeadConsumerAudit.ps1"
  closeCondition = 'Unify value-level deduplication at the shared V2 selector-list projection boundary, prove all listed consumers use it, then generate post-fix/current-head evidence; R4 remains the only runtime semantic closure gate.'
}
Write-AtomicJson $OutputPath $evidence
$evidence | ConvertTo-Json -Depth 50
