[CmdletBinding()]
param(
  [ValidateSet('PreFix', 'PostFix')]
  [string]$Mode = 'PostFix',
  [string]$EvidencePath = '',
  [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Get-Path {
  param([Parameter(Mandatory = $true)][string]$Relative)
  return Join-Path $RepositoryRoot ($Relative.Replace('/', '\'))
}

function Read-Utf8 {
  param([Parameter(Mandatory = $true)][string]$Path)
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
}

# pre-fix 模式：目标文件映射到 r2 备份（修复前快照），其余共享文件（reference/生成数据）保持 HEAD。
# 备份不存在时回退到 HEAD，并记录 fallback。
$backupSuffix = '.bak_20260813_issue244_entity_r2'
$backupSuffixAlt = '.bak_20260813_issue244_entity'

$targets = @(
  'entry/src/main/ets/libs/htmlparser/JsoupEntityScript.ets',
  'entry/src/main/ets/libs/htmlparser/JsoupEntityData.ets',
  'entry/src/main/ets/libs/htmlparser/HtmlEntities.ets',
  'entry/src/main/ets/libs/htmlparser/Parser.ets',
  'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
  'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets',
  'entry/src/main/ets/Framework/Novel/RhinoWasmExecutor.ets',
  'entry/src/main/ets/Framework/Novel/LegadoRuntimeAssetManager.ets',
  'entry/src/main/resources/rawfile/legado_runtime.html',
  'entry/src/main/resources/rawfile/jsoup_entity_data.js',
  'entry/src/main/resources/rawfile/jsoup_entity_decoder.js',
  'entry/src/main/resources/rawfile/rhino_sandbox/index.html',
  'entry/src/main/resources/rawfile/rhino_sandbox/index_offline.html',
  'entry/src/main/resources/rawfile/rhino_sandbox/jsoup_impl.js',
  'entry/src/main/resources/rawfile/rhino_sandbox/jsoup_entity_data.js',
  'entry/src/main/resources/rawfile/rhino_sandbox/jsoup_entity_decoder.js',
  'manxia-legado-runtime/index.main.json',
  'manxia-legado-runtime/legado_runtime.html',
  'manxia-legado-runtime/rhino_sandbox/index.html',
  'manxia-legado-runtime/rhino_sandbox/index_offline.html',
  'manxia-legado-runtime/rhino_sandbox/jsoup_impl.js',
  'manxia-legado-runtime/rhino_sandbox/jsoup_entity_data.js',
  'manxia-legado-runtime/rhino_sandbox/jsoup_entity_decoder.js',
  'tools/legado-compat/Generate-LegadoJsoupEntityData.ps1'
)

$headMap = @{}
foreach ($t in $targets) {
  $headMap[$t] = Get-Path $t
}

function Resolve-ForMode {
  param([Parameter(Mandatory = $true)][string]$Relative)
  $head = $headMap[$Relative]
  if ($Mode -eq 'PreFix' -and $null -ne $head) {
    $bak = $head + $backupSuffix
    if (-not (Test-Path -LiteralPath $bak)) { $bak = $head + $backupSuffixAlt }
    if (Test-Path -LiteralPath $bak) { return @{ path = $bak; isBackup = $true } }
  }
  return @{ path = $head; isBackup = $false }
}

$results = New-Object 'System.Collections.Generic.List[object]'
$backupMapping = New-Object 'System.Collections.Generic.List[object]'

function Add-Check {
  param(
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][string]$Description,
    [Parameter(Mandatory = $true)][bool]$Passed,
    [string]$Detail = ''
  )
  [void]$results.Add([pscustomobject][ordered]@{
      id = $Id
      description = $Description
      passed = $Passed
      detail = $Detail
    })
}

# ---------- 固定参考数据 ----------
$referencePath = Join-Path $PSScriptRoot 'reference\jsoup-1.16.2-entities-packed.json'
if (-not (Test-Path -LiteralPath $referencePath)) { throw "Pinned reference missing: $referencePath" }
$reference = Get-Content -LiteralPath $referencePath -Encoding UTF8 -Raw | ConvertFrom-Json
$basePoints = [string]$reference.basePoints
$fullPoints = [string]$reference.fullPoints
$baseRecords = @($basePoints.Split('&', [System.StringSplitOptions]::RemoveEmptyEntries))
$fullRecords = @($fullPoints.Split('&', [System.StringSplitOptions]::RemoveEmptyEntries))

function Get-EntityValue {
  param([Parameter(Mandatory = $true)][string[]]$Records, [Parameter(Mandatory = $true)][string]$Name)
  foreach ($record in $Records) {
    if ($record.StartsWith($Name + '=')) {
      return $record.Substring($Name.Length + 1)
    }
  }
  return $null
}

# ---------- A. 数据完整性（固定参考） ----------
Add-Check 'ref-base-count-106' 'base 实体 106 条' ($baseRecords.Count -eq 106) "actual=$($baseRecords.Count)"
Add-Check 'ref-extended-count-2125' 'extended 实体 2125 条' ($fullRecords.Count -eq 2125) "actual=$($fullRecords.Count)"
$copyVal = Get-EntityValue -Records $baseRecords -Name 'copy'
Add-Check 'ref-copy-base' '&copy 在 base 表' ($null -ne $copyVal) "value=$copyVal"
Add-Check 'ref-copy-semicolon' '&copy; 为同一 base 记录' ($null -ne $copyVal -and $copyVal.IndexOf(';') -gt 0) "value=$copyVal"
$notEqTilde = Get-EntityValue -Records $fullRecords -Name 'NotEqualTilde'
Add-Check 'ref-not-equal-tilde-multipoint' 'NotEqualTilde 双码点' ($null -ne $notEqTilde -and $notEqTilde.Contains(',')) "value=$notEqTilde"
$fjlig = Get-EntityValue -Records $fullRecords -Name 'fjlig'
Add-Check 'ref-fjlig-multipoint' 'fjlig 双码点' ($null -ne $fjlig -and $fjlig.Contains(',')) "value=$fjlig"
function ConvertFrom-Base36 {
  param([Parameter(Mandatory = $true)][string]$Value)
  $result = 0
  foreach ($c in $Value.ToCharArray()) {
    $digit = 0
    if ($c -ge '0' -and $c -le '9') { $digit = [int]$c - 48 }
    elseif ($c -ge 'a' -and $c -le 'z') { $digit = [int]$c - 87 }
    elseif ($c -ge 'A' -and $c -le 'Z') { $digit = [int]$c - 55 }
    else { throw "Invalid base36 digit: $c" }
    $result = $result * 36 + $digit
  }
  return $result
}
$afr = Get-EntityValue -Records $fullRecords -Name 'Afr'
$afrFirst = 0
if ($null -ne $afr) {
  $afrFirst = ConvertFrom-Base36 ($afr.Substring(0, $afr.IndexOf(';')))
}
Add-Check 'ref-afr-non-bmp' 'Afr 非 BMP（码点 > 0xFFFF）' ($afrFirst -gt 0xFFFF) "codepoint=0x$($afrFirst.ToString('X'))"
$ccint = Get-EntityValue -Records $fullRecords -Name 'CounterClockwiseContourIntegral'
Add-Check 'ref-long-name-exists' 'CounterClockwiseContourIntegral 存在' ($null -ne $ccint) "value=$ccint"
Add-Check 'ref-case-sensitive-copy' 'COPY 存在而 Copy 不存在（大小写敏感）' ((Get-EntityValue -Records $baseRecords -Name 'COPY') -and (-not (Get-EntityValue -Records $baseRecords -Name 'Copy')) -and (-not (Get-EntityValue -Records $fullRecords -Name 'Copy')))
Add-Check 'ref-numeric-80-win1252' '&#x80; 属 Windows-1252 映射区（0x80..0x9F）' ($true)

# ---------- B. 单一生成源 ----------
$etsResolved = Resolve-ForMode 'entry/src/main/ets/libs/htmlparser/JsoupEntityData.ets'
$etsText = Read-Utf8 $etsResolved.path
$etsBase = [regex]::Match($etsText, "JSOUP_BASE_ENTITY_POINTS: string = '(?<v>(?:\\\\.|[^'\\\\])*)';").Groups['v'].Value
$etsFull = [regex]::Match($etsText, "JSOUP_FULL_ENTITY_POINTS: string = '(?<v>(?:\\\\.|[^'\\\\])*)';").Groups['v'].Value
Add-Check 'ets-counts-106-2125' 'JsoupEntityData.ets 计数常量正确' ($etsText.Contains('JSOUP_BASE_ENTITY_COUNT: number = 106;') -and $etsText.Contains('JSOUP_EXTENDED_ENTITY_COUNT: number = 2125;'))
Add-Check 'ets-data-matches-reference' 'JsoupEntityData.ets 数据与固定参考一致' (($etsBase.Length -gt 0 -and $etsBase -eq $basePoints) -and ($etsFull.Length -gt 0 -and $etsFull -eq $fullPoints))
Add-Check 'ets-js-decoder-constant' 'JSOUP_JS_DECODER_SCRIPT 常量存在' ($etsText.Contains('JSOUP_JS_DECODER_SCRIPT: string ='))

$scriptResolved = Resolve-ForMode 'entry/src/main/ets/libs/htmlparser/JsoupEntityScript.ets'
$scriptText = Read-Utf8 $scriptResolved.path
$scriptHasAlgorithm = $scriptText.Contains('__legadoParseEntityPoints') -or $scriptText.Contains('var __legadoDecodeHtmlEntities = function') -or $scriptText.Contains('__legadoJsoupEntityBasePoints')
Add-Check 'entity-script-forward-only' 'JsoupEntityScript.ets 只转发生成常量（无独立算法/表）' (-not $scriptHasAlgorithm)
Add-Check 'entity-script-imports-generated' 'JsoupEntityScript.ets 导入 JSOUP_JS_DECODER_SCRIPT' ($scriptText.Contains('JSOUP_JS_DECODER_SCRIPT'))
Add-Check 'entity-script-returns-constant' 'buildJsoupEntityCompatibilityScript 返回生成常量' ($scriptText.Contains('return JSOUP_JS_DECODER_SCRIPT;'))

$genResolved = Resolve-ForMode 'tools/legado-compat/Generate-LegadoJsoupEntityData.ps1'
$genText = Read-Utf8 $genResolved.path
Add-Check 'generator-local-reference' '生成器优先读取本地固定参考' ($genText.Contains('jsoup-1.16.2-entities-packed.json'))
Add-Check 'generator-single-decoder-core' '生成器只有单一 decoder 算法核心' ($genText.Contains('$decoderCore') -and ($genText | Select-String -Pattern '单一 decoder 算法核心' -Quiet))
Add-Check 'generator-both-variants' '生成器产出局部 var 版与浏览器 window 版' ($genText.Contains('local_var_scope') -and $genText.Contains('window_wrapper') -and $genText.Contains('jsvmDecoderVariant') -and $genText.Contains('browserDecoderVariant'))

# ---------- C. 生成资源形态 ----------
$dataResolved = Resolve-ForMode 'entry/src/main/resources/rawfile/jsoup_entity_data.js'
$dataText = Read-Utf8 $dataResolved.path
Add-Check 'browser-data-window-wrapper' 'jsoup_entity_data.js 使用明确 window 包装且无 globalThis' ($dataText.Contains('(function (window) {') -and $dataText.TrimEnd().EndsWith('})(window);') -and (-not $dataText.Contains('globalThis')))

$decoderResolved = Resolve-ForMode 'entry/src/main/resources/rawfile/jsoup_entity_decoder.js'
$decoderText = Read-Utf8 $decoderResolved.path
Add-Check 'browser-decoder-window-wrapper' 'jsoup_entity_decoder.js 使用明确 window 包装且无 globalThis' ($decoderText.StartsWith('(function (window) {') -and $decoderText.TrimEnd().EndsWith('})(window);') -and (-not $decoderText.Contains('globalThis')))
Add-Check 'browser-decoder-pins-data' 'decoder 校验扩展实体计数 2125' ($decoderText.Contains('extendedCount') -and $decoderText.Contains('2125'))

# ---------- D. 消费者矩阵 ----------
$parserText = Read-Utf8 (Resolve-ForMode 'entry/src/main/ets/libs/htmlparser/Parser.ets').path
Add-Check 'parser-decode-attribute' 'Parser.ets 属性解析调用 decodeAttribute' ($parserText.Contains('HtmlEntities.decodeAttribute('))

$analyzerText = Read-Utf8 (Resolve-ForMode 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets').path
Add-Check 'analyzer-decode' 'LegadoRuleAnalyzer 文本回退调用 HtmlEntities.decode' ($analyzerText.Contains('return HtmlEntities.decode(text);'))

$jsEngineResolved = Resolve-ForMode 'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets'
$jsEngineText = Read-Utf8 $jsEngineResolved.path
$nativeAttrCount = ([regex]::Matches($jsEngineText, 'return __legadoDecodeHtmlEntities\(rawAttrValue, true\);')).Count
Add-Check 'jsengine-attr-native-decoded' 'JSVM __nativeAttrFromHtml/__attrFromHtml 使用 inAttribute=true' ($nativeAttrCount -ge 3) "matches=$nativeAttrCount"
Add-Check 'jsengine-title-decoded' 'JSVM JsoupDocument.title raw 回退按文本语义解码' ($jsEngineText.Contains('this._title = __legadoDecodeHtmlEntities(titleMatch[1], false);'))
Add-Check 'jsengine-element-attr-decoded' 'JSVM JsoupElement.attr 使用 inAttribute=true' ($jsEngineText.Contains('return match ? __legadoDecodeHtmlEntities(match[1], true) : '''';'))
Add-Check 'jsengine-doc-text-decoded' 'JSVM JsoupDocument.text raw 回退按文本语义解码' ($jsEngineText.Contains('return __legadoDecodeHtmlEntities(this._html.replace(/<[^>]+>/g, ''''), false).trim();'))
Add-Check 'jsengine-element-text-decoded' 'JSVM JsoupElement.text raw 回退按文本语义解码' ($jsEngineText.Contains('return __legadoDecodeHtmlEntities(this._outerHtml.replace(/<[^>]+>/g, ''''), false).trim();'))
Add-Check 'jsengine-no-double-decode' 'JSVM 无 __legadoDecodeHtmlEntities 嵌套二次解码' (-not $jsEngineText.Contains('__legadoDecodeHtmlEntities(__legadoDecodeHtmlEntities'))

$rhinoResolved = Resolve-ForMode 'entry/src/main/ets/Framework/Novel/RhinoWasmExecutor.ets'
$rhinoText = Read-Utf8 $rhinoResolved.path
$rhinoTitleDecoded = $rhinoText.Contains('return m ? __legadoDecodeHtmlEntities(m[1], false) : '''';')
Add-Check 'rhino-title-decoded' 'Rhino raw title fallback 按文本语义解码' $rhinoTitleDecoded
$q = [string][char]39
$rhinoNeedleA = '__legadoDecodeHtmlEntities(this._html.replace(/<[^>]+>/g, ' + $q + $q + '), false)'
$rhinoNeedleB = '__legadoDecodeHtmlEntities(this.html.replace(/<[^>]+>/g, ' + $q + $q + '), false)'
$rhinoTextDecoded = 0
if ($rhinoText.Contains($rhinoNeedleA)) { $rhinoTextDecoded++ }
if ($rhinoText.Contains($rhinoNeedleB)) { $rhinoTextDecoded++ }
Add-Check 'rhino-text-fallback-decoded' 'Rhino raw text fallback 按文本语义解码（两处）' ($rhinoTextDecoded -ge 2) "matches=$rhinoTextDecoded"
Add-Check 'rhino-no-double-decode' 'Rhino 无嵌套二次解码' (-not $rhinoText.Contains('__legadoDecodeHtmlEntities(__legadoDecodeHtmlEntities'))

$implResolved = Resolve-ForMode 'entry/src/main/resources/rawfile/rhino_sandbox/jsoup_impl.js'
$implText = Read-Utf8 $implResolved.path
Add-Check 'jsoup-impl-shared-decoder' 'jsoup_impl.js parserless fallback 使用共享 decoder' ($implText.Contains('__legadoDecodeHtmlEntities'))
Add-Check 'jsoup-impl-window-wrapper' 'jsoup_impl.js 使用明确 window 包装' ($implText.TrimEnd().EndsWith('})(window);'))

$legadoRuntimeResolved = Resolve-ForMode 'entry/src/main/resources/rawfile/legado_runtime.html'
$legadoRuntimeText = Read-Utf8 $legadoRuntimeResolved.path
Add-Check 'legado-runtime-uses-shared-decoder' 'legado_runtime.html 使用 window.__legadoDecodeHtmlEntities' ($legadoRuntimeText.Contains('window.__legadoDecodeHtmlEntities'))
Add-Check 'legado-runtime-load-order' 'legado_runtime.html 先加载 data 再加载 decoder' (($legadoRuntimeText.IndexOf('jsoup_entity_data.js') -ge 0) -and ($legadoRuntimeText.IndexOf('jsoup_entity_data.js') -lt $legadoRuntimeText.IndexOf('jsoup_entity_decoder.js')))

# ---------- E. 资源顺序 ----------
function Test-LoadOrder {
  param([Parameter(Mandatory = $true)][string]$Text)
  $srcs = @([regex]::Matches($Text, '<script\s+src="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
  $order = @('jsoup_entity_data.js', 'jsoup_entity_decoder.js', 'jsoup_impl.js', 'rhino_offline.js')
  $lastIndex = -1
  foreach ($o in $order) {
    $idx = [Array]::IndexOf($srcs, $o)
    if ($idx -lt 0 -or $idx -le $lastIndex) { return $false }
    $lastIndex = $idx
  }
  return $true
}
$offlineResolved = Resolve-ForMode 'entry/src/main/resources/rawfile/rhino_sandbox/index_offline.html'
$offlineText = Read-Utf8 $offlineResolved.path
Add-Check 'index-offline-load-order' 'index_offline.html 顺序：data → decoder → jsoup_impl → rhino_offline' (Test-LoadOrder $offlineText)
$indexResolved = Resolve-ForMode 'entry/src/main/resources/rawfile/rhino_sandbox/index.html'
$indexText = Read-Utf8 $indexResolved.path
Add-Check 'index-html-load-order' 'index.html 顺序：data → decoder → jsoup_impl → rhino_offline' (Test-LoadOrder $indexText)

# ---------- F. 本地/远端镜像一致 ----------
$mirrorPairs = @(
  @('entry/src/main/resources/rawfile/rhino_sandbox/jsoup_impl.js', 'manxia-legado-runtime/rhino_sandbox/jsoup_impl.js'),
  @('entry/src/main/resources/rawfile/rhino_sandbox/index_offline.html', 'manxia-legado-runtime/rhino_sandbox/index_offline.html'),
  @('entry/src/main/resources/rawfile/rhino_sandbox/index.html', 'manxia-legado-runtime/rhino_sandbox/index.html'),
  @('entry/src/main/resources/rawfile/legado_runtime.html', 'manxia-legado-runtime/legado_runtime.html'),
  @('entry/src/main/resources/rawfile/jsoup_entity_data.js', 'manxia-legado-runtime/jsoup_entity_data.js'),
  @('entry/src/main/resources/rawfile/jsoup_entity_decoder.js', 'manxia-legado-runtime/jsoup_entity_decoder.js'),
  @('entry/src/main/resources/rawfile/jsoup_entity_data.js', 'manxia-legado-runtime/rhino_sandbox/jsoup_entity_data.js'),
  @('entry/src/main/resources/rawfile/jsoup_entity_decoder.js', 'manxia-legado-runtime/rhino_sandbox/jsoup_entity_decoder.js')
)
foreach ($pair in $mirrorPairs) {
  $h1 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-Path $pair[0])).Hash
  $h2 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-Path $pair[1])).Hash
  Add-Check ('mirror-' + ($pair[0] -replace '[^A-Za-z0-9]', '-')) '本地/远端资源镜像一致' ($h1 -eq $h2) "$h1 vs $h2"
}

# ---------- G. 清单完整性 ----------
$manifestResolved = Resolve-ForMode 'manxia-legado-runtime/index.main.json'
$manifestPath = $manifestResolved.path
$manifest = Get-Content -LiteralPath $manifestPath -Encoding UTF8 -Raw | ConvertFrom-Json
Add-Check 'manifest-runtime-api-3' '清单 runtimeApi=3' ([int]$manifest.runtimeApi -eq 3) "actual=$($manifest.runtimeApi)"
Add-Check 'manifest-code-version' '清单 code/version 已更新' ([int]$manifest.code -eq 3 -and [string]$manifest.version -eq '0.1.2') "code=$($manifest.code) version=$($manifest.version)"
$requiredEntities = @($manifest.files | Where-Object { $_.path -in @('jsoup_entity_data.js', 'jsoup_entity_decoder.js', 'rhino_sandbox/jsoup_entity_data.js', 'rhino_sandbox/jsoup_entity_decoder.js') -and $_.required })
Add-Check 'manifest-entity-files-required' '清单新增 4 个 required 实体文件条目' ($requiredEntities.Count -eq 4) "found=$($requiredEntities.Count)"
$manifestMatches = $true
$manifestMismatchDetail = ''
foreach ($file in @($manifest.files)) {
  $fp = Join-Path (Join-Path $RepositoryRoot 'manxia-legado-runtime') (([string]$file.path).Replace('/', '\'))
  if (-not (Test-Path -LiteralPath $fp)) { $manifestMatches = $false; $manifestMismatchDetail = "missing $($file.path)"; break }
  $actualHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $fp).Hash
  $actualSize = (Get-Item -LiteralPath $fp).Length
  if ($actualHash -ne [string]$file.sha256 -or $actualSize -ne [int]$file.size) {
    $manifestMatches = $false
    $manifestMismatchDetail = "mismatch $($file.path): manifest=$($file.sha256)/$($file.size) actual=$actualHash/$actualSize"
    break
  }
}
Add-Check 'manifest-sha-size-match' '清单 SHA-256/size 与文件一致' $manifestMatches $manifestMismatchDetail

# ---------- H. API 常量 ----------
$managerText = Read-Utf8 (Resolve-ForMode 'entry/src/main/ets/Framework/Novel/LegadoRuntimeAssetManager.ets').path
Add-Check 'runtime-manager-api-3' 'LegadoRuntimeAssetManager minimum/supported API=3' ($managerText.Contains('const LEGADO_RUNTIME_MINIMUM_API = 3;') -and $managerText.Contains('const LEGADO_RUNTIME_SUPPORTED_API = 3;'))

# ---------- I. 无 globalThis ----------
$noGlobalThisFiles = @(
  'entry/src/main/ets/libs/htmlparser/JsoupEntityData.ets',
  'entry/src/main/ets/libs/htmlparser/JsoupEntityScript.ets',
  'entry/src/main/resources/rawfile/jsoup_entity_data.js',
  'entry/src/main/resources/rawfile/jsoup_entity_decoder.js',
  'entry/src/main/resources/rawfile/rhino_sandbox/jsoup_entity_data.js',
  'entry/src/main/resources/rawfile/rhino_sandbox/jsoup_entity_decoder.js',
  'entry/src/main/resources/rawfile/rhino_sandbox/jsoup_impl.js',
  'entry/src/main/resources/rawfile/rhino_sandbox/index.html',
  'entry/src/main/resources/rawfile/rhino_sandbox/index_offline.html',
  'entry/src/main/resources/rawfile/legado_runtime.html',
  'manxia-legado-runtime/jsoup_entity_data.js',
  'manxia-legado-runtime/jsoup_entity_decoder.js',
  'manxia-legado-runtime/rhino_sandbox/jsoup_entity_data.js',
  'manxia-legado-runtime/rhino_sandbox/jsoup_entity_decoder.js',
  'manxia-legado-runtime/rhino_sandbox/jsoup_impl.js',
  'manxia-legado-runtime/rhino_sandbox/index.html',
  'manxia-legado-runtime/rhino_sandbox/index_offline.html',
  'manxia-legado-runtime/legado_runtime.html',
  'tools/legado-compat/Generate-LegadoJsoupEntityData.ps1'
)
$globalThisFound = ''
foreach ($f in $noGlobalThisFiles) {
  $p = Get-Path $f
  if (-not (Test-Path -LiteralPath $p)) { continue }
  if ($f -eq 'tools/legado-compat/Generate-LegadoJsoupEntityData.ps1') { continue }
  $content = Read-Utf8 $p
  if ($content -match '\bglobalThis\b') { $globalThisFound = $f; break }
}
Add-Check 'no-globalthis-targets' '全部生成文件/消费者无 globalThis' ($globalThisFound.Length -eq 0) "found=$globalThisFound"
$genGlobalThisLines = @(($genText -split "\r?\n") | Where-Object { $_ -match '\bglobalThis\b' })
$genGuardOk = ($genGlobalThisLines.Count -eq 1) -and ($genGlobalThisLines[0] -match '\$forbiddenToken = ''globalThis''')
Add-Check 'generator-globalthis-single-guard' '生成器仅以单点守卫引用 globalThis' $genGuardOk "lines=$($genGlobalThisLines -join ' | ')"

# ---------- 汇总 ----------
$failed = @($results | Where-Object { -not $_.passed })
$passed = @($results | Where-Object { $_.passed })
$evidence = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_244_jsoup_entity_static_contract'
  issueId = 'ISSUE-COMPAT-244-JSOUP-HTML-ENTITY-SEMANTICS'
  mode = $Mode
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  repositoryRoot = $RepositoryRoot
  baseline = [pscustomobject][ordered]@{
    sourceCount = 458
    sourcePackageSha256 = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
    legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
    jsoupVersion = '1.16.2'
    entitiesDataJavaSha256 = '5D2D6726A607FCA5D0F9393AA6D5DC0882E780507DFB35371CD4D17E7E1E63F9'
    pinnedJarSha256 = 'A73A1EB5D02B51490547C46485E30F4F14E68AF3624840B57ABE8C4580A00B83'
  }
  passedCount = $passed.Count
  failedCount = $failed.Count
  checks = $results.ToArray()
  failures = @($failed)
  semanticMatchAllowed = $false
  runtimeActionsPerformed = @()
}

if ($EvidencePath.Length -gt 0) {
  $absoluteEvidence = if ([System.IO.Path]::IsPathRooted($EvidencePath)) { $EvidencePath } else { Join-Path $RepositoryRoot ($EvidencePath.Replace('/', '\')) }
  $directory = Split-Path -Parent $absoluteEvidence
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  [System.IO.File]::WriteAllText($absoluteEvidence, ($evidence | ConvertTo-Json -Depth 20), $utf8)
}

$evidence | ConvertTo-Json -Depth 20

if ($failed.Count -gt 0 -and $Mode -eq 'PostFix') {
  throw "244 post-fix static contract failed: $($failed.Count) check(s) not passing"
}
