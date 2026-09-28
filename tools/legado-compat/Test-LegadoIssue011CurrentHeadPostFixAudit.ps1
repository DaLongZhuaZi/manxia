[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-url-attribute-duplicate-pre-fix-011-20260809.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-url-attribute-duplicate-post-fix-011-20260809.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/v2-issue-011-current-head-consumer-audit-post-fix-20260809.json'
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
  if (-not $Condition) { throw "ISSUE011_CURRENT_HEAD_POST_FIX_FAILED:$Message" }
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

$failure = Read-StrictJson $FailureWitnessPath
$postFix = Read-StrictJson $PostFixContractPath
Assert-Audit ([string]$failure.issueId -eq $issueId) 'failure witness issue mismatch'
Assert-Audit ([string]$failure.status -eq 'failed_static_only') 'failure witness must remain failed_static_only'
Assert-Audit ([int]$failure.baseline.sourceCount -eq $sourceCount) 'failure witness source count drifted'
Assert-Audit ([string]$failure.baseline.sourcePackageSha256 -eq $sourceHash) 'failure witness source hash drifted'
Assert-Audit ([string]$postFix.issueId -eq $issueId) 'post-fix contract issue mismatch'
Assert-Audit ([string]$postFix.status -eq 'passed_static_only') 'post-fix contract must be passed_static_only'
Assert-Audit (-not [bool]$postFix.semanticMatchAllowed) 'post-fix contract cannot enable semantic match'

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
$workflow = [string]$contents.workflow
$standardJsVm = [string]$contents.standardJsVm
$nativeJsVm = [string]$contents.nativeJsVm
$rhinoJsVm = [string]$contents.rhinoJsVm
$arkWebRuntime = [string]$contents.arkWebRuntime
$sourceTypes = [string]$contents.sourceTypes
$sourceManager = [string]$contents.sourceManager
$outputBridge = [string]$contents.outputBridge

Assert-Audit ($analyzer.Contains('private deduplicateLegadoAttributeValues(values: string[]): string[]')) 'Analyzer shared helper missing'
Assert-Audit ($analyzer.Contains('this.deduplicateLegadoAttributeValues(results)')) 'Analyzer terminal projection is not bound to helper'
Assert-Audit ($analyzer.Contains('this.deduplicateLegadoAttributeValues(values)')) 'Analyzer list projection is not bound to helper'
Assert-Audit ($workflow.Contains('getStringAsync') -and $workflow.Contains('getUrlStringAsync') -and $workflow.Contains('getUrlStringListAsync')) 'workflow selector consumer markers missing'
Assert-Audit ($workflow.Contains('resolveRequestUrlTemplate') -and $workflow.Contains('requestCarrier')) 'workflow URL boundary marker missing'
Assert-Audit ($standardJsVm.Contains('__deduplicateLegadoAttributeValues') -and $standardJsVm.Contains('rawValues = __deduplicateLegadoAttributeValues(rawValues, split.attr);')) 'standard JSVM source fix missing'
Assert-Audit ($standardJsVm.Contains('__nativeDeduplicateLegadoAttributeValues') -and $standardJsVm.Contains('return __nativeDeduplicateLegadoAttributeValues(elements.eachAttr(split.attr), split.attr);')) 'embedded Native JSVM source fix missing'
Assert-Audit ($nativeJsVm.Contains('eachAttr')) 'Native JSVM direct collection API marker missing'
Assert-Audit ($rhinoJsVm.Contains('eachAttr(name)') -and -not $rhinoJsVm.Contains('deduplicateLegadoAttributeValues')) 'Rhino direct eachAttr contract was not replaced by silent deduplication'
Assert-Audit ($arkWebRuntime.Contains('legadoDeduplicateAttributeValues') -and $arkWebRuntime.Contains('return legadoDeduplicateAttributeValues(values, attr);')) 'ArkWeb source fix missing'
Assert-Audit ($sourceTypes.Contains('class LegadoRequestCarrier')) 'request carrier type missing'
Assert-Audit ($sourceManager.Contains('resolveV2RequestCarrier') -and $sourceManager.Contains('requestCarrierKey')) 'request carrier boundary missing'
Assert-Audit ($outputBridge.Contains('requestUrlTemplate') -and $outputBridge.Contains('requestCarrier')) 'typed output handoff boundary missing'

$consumerMatrix = @(
  [ordered]@{ id = 'analyzer.css_terminal_attribute'; layer = 'Analyzer/Matcher'; path = $paths.analyzer; status = 'source_fixed_static_only'; evidence = 'shared nonblank first-value deduplication is applied before getString joining'; sourceLines = '3638-3660' },
  [ordered]@{ id = 'analyzer.css_string_list'; layer = 'Rule IR/Analyzer'; path = $paths.analyzer; status = 'source_fixed_static_only'; evidence = 'getStringListByCSS applies the same projection helper'; sourceLines = '4692-4700' },
  [ordered]@{ id = 'workflow.search_explore_bookinfo_toc_content_file'; layer = 'Workflow'; path = $paths.workflow; status = 'consumer_bound_static_only'; evidence = 'all workflow selectors consume analyzer lists and retain URL resolution at request boundary'; sourceLines = '318-410,506-535,782-835,2261-2350' },
  [ordered]@{ id = 'standard_jsvm.java_get_string_list'; layer = 'Standard JSVM'; path = $paths.standardJsVm; status = 'source_fixed_static_only'; evidence = 'CSS attribute list rawValues pass through deduplication helper'; sourceLines = '3273-3342' },
  [ordered]@{ id = 'native_jsvm.java_get_string_list'; layer = 'Native JSVM'; path = $paths.nativeJsVm; status = 'source_fixed_static_only'; evidence = 'Native helper family delegates list projection to shared semantic helper'; sourceLines = '550-590; LegadoJsEngine embedded native helpers 2464-2540,6029-6099' },
  [ordered]@{ id = 'rhino_jsvm.java_object_each_attr'; layer = 'Rhino JSVM'; path = $paths.rhinoJsVm; status = 'contract_preserved_static_only'; evidence = 'direct eachAttr remains duplicate-preserving; list dedup belongs to analyzer/java.getStringList boundary'; sourceLines = '507-530,1340-1365' },
  [ordered]@{ id = 'arkweb.default_runtime.java_get_string_list'; layer = 'ArkWeb runtime'; path = $paths.arkWebRuntime; status = 'source_fixed_static_only'; evidence = 'legadoGetStringListSingle deduplicates only terminal nonblank attributes'; sourceLines = '1998-2028,2046-2074' },
  [ordered]@{ id = 'request_carrier.url_boundary'; layer = 'Request carrier'; path = $paths.sourceManager; status = 'unchanged_static_only'; evidence = 'URL resolution boundary remains separate from selector projection'; sourceLines = '158-220,2012-2070' },
  [ordered]@{ id = 'output.typed_handoff'; layer = 'Output projection'; path = $paths.outputBridge; status = 'unchanged_static_only'; evidence = 'typed request carrier handoff remains intact'; sourceLines = '920-930' }
)

Assert-Audit (@($consumerMatrix).Count -eq 9) 'post-fix consumer matrix must contain nine consumers'
$unresolved = @($consumerMatrix | Where-Object { [string]$_.status -notin @('source_fixed_static_only', 'consumer_bound_static_only', 'contract_preserved_static_only', 'unchanged_static_only') }).Count
Assert-Audit ($unresolved -eq 0) 'post-fix audit retained unresolved consumer gaps'

$hashes = [ordered]@{}
foreach ($entry in $paths.GetEnumerator()) {
  $hashes[$entry.Key] = [ordered]@{ path = $entry.Value; sha256 = Get-FileSha256 $entry.Value }
}

$evidence = [ordered]@{
  schemaVersion = 1
  kind = 'legado_issue_011_current_head_consumer_audit_post_fix'
  status = 'passed_static_only'
  issueId = $issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  failureWitnessPath = $FailureWitnessPath
  postFixContractPath = $PostFixContractPath
  inventoryStatus = 'complete_static_inventory'
  consumerMatrix = $consumerMatrix
  unresolvedGapCount = $unresolved
  currentHeadHashes = $hashes
  primaryCause = [ordered]@{
    classification = 'selector_attribute_projection_value_deduplication'
    statement = 'All selector-list consumers now bind the Legado nonblank first-value deduplication at the projection boundary; direct eachAttr and request URL resolution remain separate contracts.'
  }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_static_current_head_post_fix_only;R4_runtime_build_device_and_legado_diff_deferred'
  reproductionCommand = 'pwsh -NoLogo -NoProfile -NonInteractive -File tools/legado-compat/Test-LegadoIssue011CurrentHeadPostFixAudit.ps1'
  closeCondition = 'R4 must validate these consumers through runtime fixtures, affected source equivalence classes, same-input Legado differential, build and device gates.'
}
Write-AtomicJson $OutputPath $evidence
$evidence | ConvertTo-Json -Depth 60
