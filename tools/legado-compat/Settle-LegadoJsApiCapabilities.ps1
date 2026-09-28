[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$ResultPath = 'tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/semantic-settlement.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-Json {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing JSON: $RelativePath" }
  return $utf8Strict.GetString([System.IO.File]::ReadAllBytes($path)) | ConvertFrom-Json
}

function Read-Text {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing text: $RelativePath" }
  return $utf8Strict.GetString([System.IO.File]::ReadAllBytes($path))
}

function Write-AtomicJson {
  param([string]$RelativePath, [object]$Value)
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 70), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Assert-Condition {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "JS API semantic settlement blocked: $Message" }
}

$sourcePackageRelative = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
$sourcePackagePath = $sourcePackageRelative
if (-not (Test-Path -LiteralPath $sourcePackagePath -PathType Leaf)) {
  $sourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
}
Assert-Condition (Test-Path -LiteralPath $sourcePackagePath -PathType Leaf) 'frozen source package is missing.'
Assert-Condition ((Get-FileHash -LiteralPath $sourcePackagePath -Algorithm SHA256).Hash -eq $sourceHash) 'source package hash drifted.'
$sources = $utf8Strict.GetString([System.IO.File]::ReadAllBytes($sourcePackagePath)) | ConvertFrom-Json
Assert-Condition (@($sources).Count -eq 458) 'source count is not 458.'

$mappingRelative = 'tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/reference-mapping.json'
$mapping = Read-Json $mappingRelative
Assert-Condition ([string]$mapping.status -eq 'passed') 'reference mapping is not passed.'
Assert-Condition ([string]$mapping.sourcePackageSha256 -eq $sourceHash -and [int]$mapping.sourceCount -eq 458) 'reference mapping baseline drifted.'

$referenceFiles = @(
  'legado/app/src/main/java/io/legado/app/help/JsExtensions.kt',
  'legado/app/src/main/java/io/legado/app/help/JsEncodeUtils.kt',
  'legado/app/src/main/java/io/legado/app/data/entities/BaseSource.kt',
  'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeRule.kt',
  'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeUrl.kt'
)
$v2Files = @(
  'entry/src/main/resources/rawfile/legado_runtime.html',
  'entry/src/main/ets/Framework/Novel/LegadoRuntimeV2.ets',
  'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets',
  'entry/src/main/ets/Framework/Novel/LegadoJsApiContractRegistry.ets',
  'entry/src/main/ets/Framework/Novel/LegadoSourceScriptRuntime.ets',
  'entry/src/main/ets/Framework/Novel/LegadoWorkflowOrchestrator.ets',
  'entry/src/main/ets/Framework/Novel/LegadoCompatibilityCompiler.ets',
  'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
)
foreach ($relative in $referenceFiles + $v2Files) {
  Assert-Condition (Test-Path -LiteralPath (Get-RepoPath $relative) -PathType Leaf) "evidence file missing: $relative"
}
$referenceText = @($referenceFiles | ForEach-Object { Read-Text $_ }) -join "`n"
$v2Text = @($v2Files | ForEach-Object { Read-Text $_ }) -join "`n"

# The classification is deliberately explicit.  It is based on the fixed
# Legado binding surfaces, not on token presence in the V2 registry alone.
$catalog = @(
  [pscustomobject][ordered]@{ api = 'android.graphics'; state = 'NAMESPACE_OR_IMPORT'; originalSurface = 'Android package namespace only; no JsExtensions member'; originalRefs = @('external Android namespace; no matching fixed Legado JsExtensions declaration'); v2Surface = 'No android.graphics root in the default runtime'; v2Disposition = 'namespace-only; no callable capability observed'; basis = 'non-call namespace/import reference in ruleContent.imageDecode'; close = 'keep as namespace/import unless a concrete class member call is isolated' },
  [pscustomobject][ordered]@{ api = 'android.os.Build.MANUFACTURER'; state = 'STATIC_MEMBER_REFERENCE'; originalSurface = 'Android Build.MANUFACTURER static member'; originalRefs = @('Android platform class, not JsExtensions'); v2Surface = 'No android.os.Build bridge in legado_runtime.html'; v2Disposition = 'static member absent'; basis = 'non-call static member reference in loginUrl'; close = 'add an explicit device-info contract or structured rejection before runtime enablement' },
  [pscustomobject][ordered]@{ api = 'android.os.Build.MODEL'; state = 'STATIC_MEMBER_REFERENCE'; originalSurface = 'Android Build.MODEL static member'; originalRefs = @('Android platform class, not JsExtensions'); v2Surface = 'No android.os.Build bridge in legado_runtime.html'; v2Disposition = 'static member absent'; basis = 'non-call static member reference in loginUrl'; close = 'add an explicit device-info contract or structured rejection before runtime enablement' },
  [pscustomobject][ordered]@{ api = 'android.text.TextUtils.isEmpty'; state = 'UNSUPPORTED_API'; originalSurface = 'Android TextUtils.isEmpty static call'; originalRefs = @('Android platform class, not JsExtensions'); v2Surface = 'No android.text.TextUtils bridge'; v2Disposition = 'call cannot be dispatched'; basis = 'four call-like references in jsLib'; close = 'fixture plus explicit unsupported_api at the rule node, or a typed equivalent implementation' },
  [pscustomobject][ordered]@{ api = 'java.ajaxTestAll'; state = 'STATIC_MEMBER_REFERENCE'; originalSurface = 'No fixed JsExtensions/AnalyzeRule/AnalyzeUrl member'; originalRefs = @('not declared by pinned Legado sources'); v2Surface = 'not registered and not injected'; v2Disposition = 'undefined source member'; basis = 'non-call property probes in loginCheckJs'; close = 'retain as source-invalid/unsupported unless a source-local definition is proven' },
  [pscustomobject][ordered]@{ api = 'java.androidId'; state = 'UNSUPPORTED_API'; originalSurface = 'JsExtensions.androidId()'; originalRefs = @('JsExtensions.kt:981'); v2Surface = 'default legado_runtime.html has no java.androidId; diagnostic native shim uses a random placeholder'; v2Disposition = 'missing on default V2 path and non-deterministic on diagnostic shim'; basis = 'seven call-like references across header/login/search/toc rules'; close = 'stable device-scoped implementation or explicit policy_blocked/unsupported_api; never random per call' },
  [pscustomobject][ordered]@{ api = 'java.bytesToStr'; state = 'SUPPORTED'; originalSurface = 'JsExtensions.bytesToStr(ByteArray, charset?)'; originalRefs = @('JsExtensions.kt:449-453'); v2Surface = 'default runtime java.bytesToStr at legado_runtime.html:2198'; v2Disposition = 'implemented with UTF-8 conversion; charset argument is not interpreted'; basis = 'one imageDecode call-like reference'; close = 'charset-equivalence fixture required before claiming broad support' },
  [pscustomobject][ordered]@{ api = 'java.copyText'; state = 'UNSUPPORTED_API'; originalSurface = 'not declared by pinned JsExtensions or source interfaces'; originalRefs = @('no matching declaration in pinned Legado source tree'); v2Surface = 'not injected'; v2Disposition = 'call cannot be dispatched'; basis = 'nine call-like callback references'; close = 'structured unsupported_api or a separately authorized clipboard contract' },
  [pscustomobject][ordered]@{ api = 'java.digestHex'; state = 'UNSUPPORTED_API'; originalSurface = 'JsEncodeUtils.digestHex(data, algorithm)'; originalRefs = @('JsEncodeUtils.kt:438'); v2Surface = 'no java.digestHex member; runtime only exposes md5/sha wrappers'; v2Disposition = 'direct call cannot be dispatched'; basis = 'five call-like references in login/header/content rules'; close = 'typed digestHex bridge with algorithm/error semantics and fixture' },
  [pscustomobject][ordered]@{ api = 'java.getReadBookConfigMap'; state = 'UNSUPPORTED_API'; originalSurface = 'not declared by pinned Legado source tree'; originalRefs = @('no matching declaration in pinned Legado source tree'); v2Surface = 'not injected'; v2Disposition = 'call cannot be dispatched'; basis = 'two call-like jsLib references'; close = 'structured unsupported_api; do not invent reader-config semantics' },
  [pscustomobject][ordered]@{ api = 'java.getStrResponse'; state = 'UNSUPPORTED_API'; originalSurface = 'AnalyzeUrl.getStrResponse(...)'; originalRefs = @('AnalyzeUrl.kt:400-476'); v2Surface = 'no java.getStrResponse member in default runtime'; v2Disposition = 'AnalyzeUrl-only method has no V2 JS bridge'; basis = 'four call-like loginCheckJs references'; close = 'prove AnalyzeUrl binding at each call site, then add a typed response bridge or reject' },
  [pscustomobject][ordered]@{ api = 'java.getThemeConfigMap'; state = 'UNSUPPORTED_API'; originalSurface = 'not declared by pinned Legado source tree'; originalRefs = @('no matching declaration in pinned Legado source tree'); v2Surface = 'not injected'; v2Disposition = 'call cannot be dispatched'; basis = 'one call-like jsLib reference'; close = 'structured unsupported_api; no silent empty map' },
  [pscustomobject][ordered]@{ api = 'java.getUserAgent'; state = 'UNSUPPORTED_API'; originalSurface = 'AnalyzeUrl.getUserAgent()'; originalRefs = @('AnalyzeUrl.kt:656'); v2Surface = 'only java.getWebViewUA is exposed'; v2Disposition = 'AnalyzeUrl-only method absent'; basis = 'three call-like loginCheckJs references'; close = 'typed request-context UA bridge or structured rejection' },
  [pscustomobject][ordered]@{ api = 'java.head'; state = 'SUPPORTED'; originalSurface = 'JsExtensions.head(url, headers)'; originalRefs = @('JsExtensions.kt:399'); v2Surface = 'default runtime java.head at legado_runtime.html:2123'; v2Disposition = 'implemented through doHttp HEAD bridge'; basis = 'two call-like references'; close = 'request/response trace fixture for status, headers and final URL' },
  [pscustomobject][ordered]@{ api = 'java.hexEncodeToString'; state = 'SUPPORTED'; originalSurface = 'JsExtensions.hexEncodeToString'; originalRefs = @('JsExtensions.kt:505'); v2Surface = 'default runtime java.hexEncodeToString at legado_runtime.html:2245'; v2Disposition = 'implemented via UTF-8 bytes to hex'; basis = 'two call-like exploreUrl references'; close = 'Unicode byte-semantics fixture' },
  [pscustomobject][ordered]@{ api = 'java.importScript'; state = 'SUPPORTED'; originalSurface = 'JsExtensions.importScript(path)'; originalRefs = @('JsExtensions.kt:264'); v2Surface = 'default runtime java.importScript at legado_runtime.html:2415'; v2Disposition = 'implemented through cache/file bridge'; basis = 'one call-like loginUrl reference'; close = 'network and local-file policy fixture; preserve non-empty failure' },
  [pscustomobject][ordered]@{ api = 'java.initUrl'; state = 'UNSUPPORTED_API'; originalSurface = 'AnalyzeUrl.initUrl()'; originalRefs = @('AnalyzeUrl.kt:140'); v2Surface = 'not injected into default runtime'; v2Disposition = 'AnalyzeUrl-only lifecycle method absent'; basis = 'one call-like loginCheckJs reference'; close = 'typed URL planner bridge or structured rejection' },
  [pscustomobject][ordered]@{ api = 'java.io'; state = 'NAMESPACE_OR_IMPORT'; originalSurface = 'Java IO namespace import'; originalRefs = @('namespace token; no direct JsExtensions member'); v2Surface = 'no general java.io root'; v2Disposition = 'namespace-only reference'; basis = 'seven non-call namespace/import references'; close = 'retain namespace classification until a concrete class member is isolated' },
  [pscustomobject][ordered]@{ api = 'java.net'; state = 'NAMESPACE_OR_IMPORT'; originalSurface = 'Java net namespace import'; originalRefs = @('namespace token; no direct JsExtensions member'); v2Surface = 'bounded javaRoot.net only'; v2Disposition = 'namespace-only reference'; basis = 'one non-call namespace/import reference'; close = 'class-level evidence required' },
  [pscustomobject][ordered]@{ api = 'java.net.URL'; state = 'SUPPORTED'; originalSurface = 'java.net.URL constructor'; originalRefs = @('Java platform URL class'); v2Surface = 'bounded javaRoot.net.URL wrapper in legado_runtime.html'; v2Disposition = 'constructor and host/path/protocol subset implemented'; basis = 'one call-like constructor reference'; close = 'member-by-member fixture for URL methods used by the source' },
  [pscustomobject][ordered]@{ api = 'java.ocr'; state = 'UNSUPPORTED_API'; originalSurface = 'not declared by pinned Legado source tree'; originalRefs = @('no matching declaration in pinned Legado source tree'); v2Surface = 'not injected'; v2Disposition = 'call cannot be dispatched'; basis = 'one non-call property probe in loginCheckJs'; close = 'structured unsupported_api; no hidden OCR service' },
  [pscustomobject][ordered]@{ api = 'java.open'; state = 'UNSUPPORTED_API'; originalSurface = 'not declared by pinned Legado source tree'; originalRefs = @('no matching declaration in pinned Legado source tree'); v2Surface = 'not injected'; v2Disposition = 'call cannot be dispatched'; basis = 'two call-like callback references'; close = 'source-local definition or structured unsupported_api required' },
  [pscustomobject][ordered]@{ api = 'java.openUrl'; state = 'NEEDS_INTERACTION'; originalSurface = 'JsExtensions.openUrl(url, mimeType?)'; originalRefs = @('JsExtensions.kt:985-1000'); v2Surface = 'no default runtime bridge to OpenUrlConfirmActivity'; v2Disposition = 'external navigation requires user confirmation'; basis = 'one call-like jsLib reference'; close = 'explicit needs_interaction trace and safe UI handoff' },
  [pscustomobject][ordered]@{ api = 'java.readBookConfig'; state = 'UNSUPPORTED_API'; originalSurface = 'not declared by pinned Legado source tree'; originalRefs = @('no matching declaration in pinned Legado source tree'); v2Surface = 'not injected'; v2Disposition = 'call cannot be dispatched'; basis = 'one non-call property reference in loginCheckJs'; close = 'structured unsupported_api; do not return an empty config' },
  [pscustomobject][ordered]@{ api = 'java.refreshBookUrl'; state = 'UNSUPPORTED_API'; originalSurface = 'not declared by pinned AnalyzeRule/JsExtensions'; originalRefs = @('no matching declaration in pinned Legado source tree'); v2Surface = 'not injected'; v2Disposition = 'workflow mutation absent'; basis = 'one call-like ruleBookInfo.tocUrl reference'; close = 'only implement with an explicit workflow mutation contract' },
  [pscustomobject][ordered]@{ api = 'java.refreshContent'; state = 'UNSUPPORTED_API'; originalSurface = 'not declared by pinned Legado source tree'; originalRefs = @('no matching declaration in pinned Legado source tree'); v2Surface = 'not injected'; v2Disposition = 'workflow mutation absent'; basis = 'six call-like loginUrl references'; close = 'source-local definition or structured unsupported_api' },
  [pscustomobject][ordered]@{ api = 'java.refreshExplore'; state = 'UNSUPPORTED_API'; originalSurface = 'not declared by pinned Legado source tree'; originalRefs = @('no matching declaration in pinned Legado source tree'); v2Surface = 'not injected'; v2Disposition = 'workflow mutation absent'; basis = 'three call-like jsLib references'; close = 'do not confuse with WebBook UI refresh; require explicit workflow contract' },
  [pscustomobject][ordered]@{ api = 'java.refreshTocUrl'; state = 'UNSUPPORTED_API'; originalSurface = 'AnalyzeRule.refreshTocUrl(), preUpdateJs-only'; originalRefs = @('AnalyzeRule.kt:867'); v2Surface = 'no default runtime bridge or workflow mutation hook'; v2Disposition = 'call cannot be dispatched'; basis = 'eleven call-like preUpdateJs references'; close = 'implement as preUpdateJs workflow mutation with trace, or reject explicitly' },
  [pscustomobject][ordered]@{ api = 'java.ruleUrl'; state = 'UNSUPPORTED_API'; originalSurface = 'AnalyzeUrl.ruleUrl property'; originalRefs = @('AnalyzeUrl.kt:94'); v2Surface = 'no AnalyzeUrl object exposed to default runtime'; v2Disposition = 'property absent'; basis = 'four non-call loginCheckJs references'; close = 'typed URL planner projection or structured rejection' },
  [pscustomobject][ordered]@{ api = 'java.s2t'; state = 'UNSUPPORTED_API'; originalSurface = 'JsExtensions.s2t(text)'; originalRefs = @('JsExtensions.kt:551'); v2Surface = 'default legado_runtime.html exposes t2s but no java.s2t member; diagnostic Native shim is not the default path'; v2Disposition = 'call cannot be dispatched on default V2'; basis = 'four call-like search references'; close = 'add s2t to the default runtime with conversion fixture, then register it; do not rely on Native shim' },
  [pscustomobject][ordered]@{ api = 'java.searchBook'; state = 'UNSUPPORTED_API'; originalSurface = 'WebBook.searchBook is not a JsExtensions member'; originalRefs = @('WebBook.kt:34-48; not exposed as java method'); v2Surface = 'not injected'; v2Disposition = 'workflow call cannot be dispatched'; basis = 'one call-like jsLib reference'; close = 'typed Search workflow handoff or structured rejection' },
  [pscustomobject][ordered]@{ api = 'java.security'; state = 'NAMESPACE_OR_IMPORT'; originalSurface = 'Java security namespace import'; originalRefs = @('namespace token; concrete MessageDigest is separate'); v2Surface = 'bounded javaRoot.security.MessageDigest only'; v2Disposition = 'namespace-only reference'; basis = 'four non-call namespace/import references'; close = 'concrete class/member evidence required' },
  [pscustomobject][ordered]@{ api = 'java.security.interfaces'; state = 'NAMESPACE_OR_IMPORT'; originalSurface = 'Java security.interfaces namespace import'; originalRefs = @('namespace token; no direct JsExtensions member'); v2Surface = 'not exposed'; v2Disposition = 'namespace-only reference'; basis = 'four non-call namespace/import references'; close = 'retain namespace classification until concrete member is isolated' },
  [pscustomobject][ordered]@{ api = 'java.security.spec'; state = 'NAMESPACE_OR_IMPORT'; originalSurface = 'Java security.spec namespace import'; originalRefs = @('namespace token; concrete spec classes are separate'); v2Surface = 'bounded javax.crypto.spec subset, not java.security.spec'; v2Disposition = 'namespace-only reference'; basis = 'five non-call namespace/import references'; close = 'class-level evidence required' },
  [pscustomobject][ordered]@{ api = 'java.upLoginData'; state = 'UNSUPPORTED_API'; originalSurface = 'not declared by pinned Legado source tree'; originalRefs = @('no matching declaration in pinned Legado source tree'); v2Surface = 'not injected'; v2Disposition = 'login mutation cannot be dispatched'; basis = 'one call-like loginUrl reference'; close = 'explicit login state contract or needs_interaction; never silent success' },
  [pscustomobject][ordered]@{ api = 'org.jsoup.Connection.Method.PUT'; state = 'STATIC_MEMBER_REFERENCE'; originalSurface = 'Jsoup Connection.Method.PUT enum constant'; originalRefs = @('JsExtensions.kt:378-446 uses org.jsoup.Connection.Method'); v2Surface = 'Jsoup.connect().method accepts a string but no Connection.Method enum object'; v2Disposition = 'enum member projection absent'; basis = 'one non-call jsLib reference'; close = 'typed enum projection or static unsupported diagnostic' },
  [pscustomobject][ordered]@{ api = 'org.jsoup.Jsoup.connect'; state = 'SUPPORTED'; originalSurface = 'Jsoup.connect request builder'; originalRefs = @('JsExtensions.kt:378-446'); v2Surface = 'default runtime Jsoup.connect request builder'; v2Disposition = 'implemented with header/data/body/method/execute/get/post subset'; basis = 'one call-like jsLib reference'; close = 'fixture for method/body/header/final response semantics' },
  [pscustomobject][ordered]@{ api = 'org.mozilla.javascript.EvaluatorException'; state = 'NAMESPACE_OR_IMPORT'; originalSurface = 'Rhino exception type name'; originalRefs = @('comment/metadata occurrence only; no executable reference'); v2Surface = 'Rhino type is not part of ArkWeb runtime'; v2Disposition = 'metadata-only; no runtime action'; basis = 'one COMMENT_OR_METADATA occurrence'; close = 'keep excluded from executable capability counts' },
  [pscustomobject][ordered]@{ api = 'source.concat'; state = 'UNSUPPORTED_API'; originalSurface = 'no concat member on fixed BaseSource'; originalRefs = @('BaseSource.kt:59-232 has no concat'); v2Surface = 'source object has no concat member'; v2Disposition = 'call cannot be dispatched'; basis = 'two call-like loginUi references'; close = 'source-local definition or structured unsupported_api' },
  [pscustomobject][ordered]@{ api = 'source.lastUpdateTime'; state = 'STATIC_MEMBER_REFERENCE'; originalSurface = 'BookSource.lastUpdateTime data field'; originalRefs = @('BookSource.kt:75'); v2Surface = 'default runtime source projection omits lastUpdateTime'; v2Disposition = 'read-only field absent'; basis = 'six non-call jsLib/loginCheckJs references'; close = 'add typed source projection or explicit unsupported diagnostic' },
  [pscustomobject][ordered]@{ api = 'source.putConcurrent'; state = 'UNSUPPORTED_API'; originalSurface = 'no putConcurrent member on fixed BaseSource'; originalRefs = @('no matching declaration in pinned Legado source tree'); v2Surface = 'source object has no putConcurrent member'; v2Disposition = 'call cannot be dispatched'; basis = 'six call-like callback references'; close = 'do not infer concurrency mutation from the name; require source-local definition or reject' },
  [pscustomobject][ordered]@{ api = 'source.refreshExplore'; state = 'UNSUPPORTED_API'; originalSurface = 'no refreshExplore member on fixed BaseSource'; originalRefs = @('no matching declaration in pinned Legado source tree'); v2Surface = 'source object has no refreshExplore member'; v2Disposition = 'call cannot be dispatched'; basis = 'fifteen call-like loginUrl/jsLib references'; close = 'typed Explore workflow handoff or structured rejection' },
  [pscustomobject][ordered]@{ api = 'source.split'; state = 'UNSUPPORTED_API'; originalSurface = 'no split member on fixed BaseSource'; originalRefs = @('no matching declaration in pinned Legado source tree'); v2Surface = 'source object has no split member'; v2Disposition = 'call cannot be dispatched'; basis = 'one call-like content reference'; close = 'source-local definition or structured unsupported_api' },
  [pscustomobject][ordered]@{ api = 'source.variable'; state = 'STATIC_MEMBER_REFERENCE'; originalSurface = 'no variable field on fixed BookSource; getVariable/setVariable are the supported API'; originalRefs = @('BaseSource.kt:206-220'); v2Surface = 'default source projection exposes getVariable/setVariable, not variable'; v2Disposition = 'read-only member absent'; basis = 'one non-call jsLib reference'; close = 'map only if fixed Legado source proves a concrete field; otherwise structured rejection' }
)

$mappingNames = @($mapping.apiMappings.PSObject.Properties.Name | Sort-Object)
$catalogNames = @($catalog.api | Sort-Object)
Assert-Condition ($mappingNames.Count -eq 44 -and $catalogNames.Count -eq 44) 'catalog count is not 44.'
Assert-Condition (@(Compare-Object $mappingNames $catalogNames).Count -eq 0) 'catalog API names do not exactly match mapped APIs.'

$settlements = @()
foreach ($entry in $catalog) {
  $mappingEntry = $mapping.apiMappings.PSObject.Properties[$entry.api].Value
  $references = @($mappingEntry.references)
  $ordinals = @($references | Select-Object -ExpandProperty sourceOrdinal -Unique | Sort-Object)
  $prefixes = @($references | Select-Object -ExpandProperty sourceHashPrefix -Unique | Sort-Object)
  $kindCounts = [pscustomobject][ordered]@{
    executableOrRuleField = @($references | Where-Object { $_.referenceKind -eq 'EXECUTABLE_OR_RULE_FIELD' }).Count
    commentOrMetadata = @($references | Where-Object { $_.referenceKind -eq 'COMMENT_OR_METADATA' }).Count
    otherField = @($references | Where-Object { $_.referenceKind -eq 'OTHER_FIELD' }).Count
    callLike = @($references | Where-Object { [bool]$_.callLike }).Count
  }
  $settlements += [pscustomobject][ordered]@{
    api = $entry.api
    classification = $entry.state
    occurrenceCount = [int]$mappingEntry.occurrenceCount
    sourceCount = [int]$mappingEntry.sourceCount
    callLikeCount = [int]$mappingEntry.callLikeReferenceCount
    referenceKindCounts = $kindCounts
    affectedSourceOrdinals = $ordinals
    affectedSourceHashPrefixes = $prefixes
    original = [pscustomobject][ordered]@{ surface = $entry.originalSurface; evidence = @($entry.originalRefs) }
    v2 = [pscustomobject][ordered]@{ surface = $entry.v2Surface; disposition = $entry.v2Disposition; evidence = @('entry/src/main/resources/rawfile/legado_runtime.html', 'entry/src/main/ets/Framework/Novel/LegadoRuntimeV2.ets', 'entry/src/main/ets/Framework/Novel/LegadoJsApiContractRegistry.ets') }
    basis = $entry.basis
    closeCondition = $entry.close
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
  }
}

$counts = @{}
foreach ($item in $settlements) {
  if ($counts.ContainsKey($item.classification)) { $counts[$item.classification]++ } else { $counts[$item.classification] = 1 }
}
$consumerMatrix = @(
  [pscustomobject][ordered]@{ layer = 'source discovery'; paths = @('tools/legado-compat/evidence/legado-js-api-usage-matrix.json', 'tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/reference-mapping.json'); role = 'bind each token to frozen source ordinal, field path and redacted digest' },
  [pscustomobject][ordered]@{ layer = 'Analyzer and compiler'; paths = @('entry/src/main/ets/Framework/Novel/LegadoCompatibilityCompiler.ets', 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'); role = 'compile rule fields and classify JS/API capability before workflow execution' },
  [pscustomobject][ordered]@{ layer = 'default ArkWeb runtime'; paths = @('entry/src/main/resources/rawfile/legado_runtime.html', 'entry/src/main/ets/Framework/Novel/LegadoRuntimeV2.ets'); role = 'inject java/source/Jsoup objects and resolve HTTP, cookie, file and crypto bridge requests' },
  [pscustomobject][ordered]@{ layer = 'diagnostic Native JSVM'; paths = @('entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets'); role = 'secondary diagnostic shim only; not the default V2 execution path' },
  [pscustomobject][ordered]@{ layer = 'script scope and effects'; paths = @('entry/src/main/ets/Framework/Novel/LegadoSourceScriptRuntime.ets'); role = 'persist variables/login/source effects and classify errors' },
  [pscustomobject][ordered]@{ layer = 'workflow and output'; paths = @('entry/src/main/ets/Framework/Novel/LegadoWorkflowOrchestrator.ets', 'entry/src/main/ets/Framework/Novel/LegadoCompatibilityTypes.ets'); role = 'dispatch Search/Explore/BookInfo/Toc/Content/File/Review and project structured refusals' }
)

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_js_api_capability_settlement_semantic'
  status = 'passed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  targetRevision = '2026-08-09-actual-docs-source-refactor-js-api-capability-settlement-preflight-037'
  activeIssueId = 'ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH'
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  inputEvidence = [pscustomobject][ordered]@{ matrix = $mappingRelative; referenceFiles = $referenceFiles; v2Files = $v2Files; rawSourcePackageExcluded = $true }
  summary = [pscustomobject][ordered]@{
    apiCount = $settlements.Count
    occurrenceCount = [int](($settlements.occurrenceCount | Measure-Object -Sum).Sum)
    callLikeCount = [int](($settlements.callLikeCount | Measure-Object -Sum).Sum)
    classificationCounts = [pscustomobject]$counts
    namespaceOrImportCount = [int]($counts['NAMESPACE_OR_IMPORT'])
    staticMemberReferenceCount = [int]($counts['STATIC_MEMBER_REFERENCE'])
    supportedCount = [int]($counts['SUPPORTED'])
    unsupportedApiCount = [int]($counts['UNSUPPORTED_API'])
    needsInteractionCount = [int]($counts['NEEDS_INTERACTION'])
  }
  consumerMatrix = $consumerMatrix
  settlements = $settlements
  rules = @(
    'classification is static source/reference settlement, not runtime compatibility',
    'namespace/import and metadata references never become runtime failures by token presence alone',
    'unsupported_api requires a concrete call/member path or fixed-Legado exposure mismatch',
    'needs_interaction is reserved for external navigation or user-authenticated flows',
    'semanticMatchAllowed remains false and no runtime actions are performed'
  )
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  nextAction = 'Use this settlement to build a single candidate failure fixture and complete the V2 consumer contract before selecting a second root cause.'
}
Write-AtomicJson $ResultPath $result
Write-Output ('JS_API_SEMANTIC_SETTLEMENT status=passed_static_only apis={0} occurrences={1} callLike={2} unsupported={3} supported={4} evidence={5} runtimeActions=0 semanticMatchAllowed=false' -f $result.summary.apiCount, $result.summary.occurrenceCount, $result.summary.callLikeCount, $result.summary.unsupportedApiCount, $result.summary.supportedCount, $ResultPath)
