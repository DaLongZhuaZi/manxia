[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  # 本地固定参考数据（优先）。内容来自固定 Jsoup 1.16.2 EntitiesData.java 的
  # basePoints/fullPoints 打包串，绑定 EntitiesData.java SHA-256 与固定 jar 交叉验证。
  [string]$ReferenceJsonPath = '',
  # 在线刷新路径：仅在本地参考文件缺失时使用，必须命中固定 SHA-256。
  [string]$EntitiesDataUrl = 'https://raw.githubusercontent.com/jhy/jsoup/jsoup-1.16.2/src/main/java/org/jsoup/nodes/EntitiesData.java',
  [string]$ExpectedEntitiesDataSha256 = '5D2D6726A607FCA5D0F9393AA6D5DC0882E780507DFB35371CD4D17E7E1E63F9'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$utf8 = [System.Text.UTF8Encoding]::new($false)

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  return Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
}

function Write-Utf8NoBom {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Text)
  $resolved = Get-RepoPath -Path $Path
  $directory = Split-Path -Parent $resolved
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, $Text, $utf8)
    Move-Item -LiteralPath $temporary -Destination $resolved -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Escape-ArkTsString {
  param([Parameter(Mandatory = $true)][string]$Value)
  return $Value.Replace('\', '\\').Replace("'", "\'").Replace([string][char]13, '\r').Replace([string][char]10, '\n')
}

function Escape-JsString {
  param([Parameter(Mandatory = $true)][string]$Value)
  return $Value.Replace('\', '\\').Replace("'", "\'").Replace([string][char]13, '\r').Replace([string][char]10, '\n')
}

function Get-EntityCount {
  param([Parameter(Mandatory = $true)][string]$Packed)
  if ($Packed.Length -eq 0) { return 0 }
  return @($Packed.Split('&', [System.StringSplitOptions]::RemoveEmptyEntries)).Count
}

# ===================== 数据来源 =====================
# 单一生成源：优先读取本地固定参考 JSON（由固定 EntitiesData.java 生成并绑定 SHA-256，
# 且与固定 jsoup-1.16.2.jar 内 EntitiesData.class 常量池交叉验证一致）。
$dataSource = 'local_pinned_reference'
$basePoints = ''
$fullPoints = ''
if ([string]::IsNullOrWhiteSpace($ReferenceJsonPath)) {
  $ReferenceJsonPath = Join-Path $PSScriptRoot 'reference\jsoup-1.16.2-entities-packed.json'
}
if (Test-Path -LiteralPath $ReferenceJsonPath) {
  $reference = Get-Content -LiteralPath $ReferenceJsonPath -Encoding UTF8 -Raw | ConvertFrom-Json
  if ([string]$reference.entitiesDataJavaSha256 -ne $ExpectedEntitiesDataSha256) {
    throw "Pinned reference EntitiesData.java hash drifted: actual=$([string]$reference.entitiesDataJavaSha256) expected=$ExpectedEntitiesDataSha256"
  }
  $basePoints = [string]$reference.basePoints
  $fullPoints = [string]$reference.fullPoints
  if ($basePoints.Length -eq 0 -or $fullPoints.Length -eq 0) {
    throw 'Pinned reference JSON is missing basePoints/fullPoints.'
  }
} else {
  # 在线回退：从固定 tag 下载 EntitiesData.java 并校验 SHA-256。
  $dataSource = 'online_entities_data_java'
  $response = Invoke-WebRequest -Uri $EntitiesDataUrl -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
  $source = [string]$response.Content
  $sourceSha256 = [Convert]::ToHexString(
    [System.Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($source))
  )
  if ($sourceSha256 -ne $ExpectedEntitiesDataSha256) {
    throw "Pinned EntitiesData.java hash drifted: actual=$sourceSha256 expected=$ExpectedEntitiesDataSha256"
  }
  $baseMatch = [regex]::Match($source, 'basePoints\s*=\s*"(?<value>(?:\\.|[^"\\])*)";')
  $fullMatch = [regex]::Match($source, 'fullPoints\s*=\s*"(?<value>(?:\\.|[^"\\])*)";')
  if (-not $baseMatch.Success -or -not $fullMatch.Success) {
    throw 'Unable to extract Jsoup basePoints/fullPoints from pinned EntitiesData.java.'
  }
  $basePoints = [regex]::Unescape($baseMatch.Groups['value'].Value)
  $fullPoints = [regex]::Unescape($fullMatch.Groups['value'].Value)
}

$baseCount = Get-EntityCount -Packed $basePoints
$fullCount = Get-EntityCount -Packed $fullPoints
if ($baseCount -ne 106 -or $fullCount -ne 2125) {
  throw "Pinned Jsoup entity counts drifted: base=$baseCount full=$fullCount"
}

# ===================== 单一 decoder 算法核心 =====================
# 本 here-string 是全部 JS 解码算法的唯一生成来源：
#  - 局部 var 版（JSVM/嵌入式注入）直接内联数据常量；
#  - 浏览器 window 版（ArkWeb/Rhino 沙箱资源）读取 window.__legadoJsoupEntityData。
# 两版共享完全相同的扫描与替换算法，禁止在生成文件之外维护第二套实现。
$decoderCore = @'
var __legadoJsoupEntityTables = null;
var __legadoJsoupWin1252 = [
  0x20ac,0x0081,0x201a,0x0192,0x201e,0x2026,0x2020,0x2021,
  0x02c6,0x2030,0x0160,0x2039,0x0152,0x008d,0x017d,0x008f,
  0x0090,0x2018,0x2019,0x201c,0x201d,0x2022,0x2013,0x2014,
  0x02dc,0x2122,0x0161,0x203a,0x0153,0x009d,0x017e,0x0178
];
var __legadoFromCodePoint = function(codePoint) {
  if (codePoint <= 0xffff) return String.fromCharCode(codePoint);
  var adjusted = codePoint - 0x10000;
  return String.fromCharCode(0xd800 + (adjusted >> 10), 0xdc00 + (adjusted & 0x3ff));
};
var __legadoParseEntityPoints = function(packed) {
  var map = Object.create(null);
  var records = packed.split('&');
  var maxNameLength = 0;
  for (var index = 0; index < records.length; index++) {
    var record = records[index];
    if (!record) continue;
    var equalsIndex = record.indexOf('=');
    var delimiterIndex = record.indexOf(';', equalsIndex + 1);
    var commaIndex = record.indexOf(',', equalsIndex + 1);
    var name = record.substring(0, equalsIndex);
    var firstEnd = commaIndex > equalsIndex && commaIndex < delimiterIndex ? commaIndex : delimiterIndex;
    var value = __legadoFromCodePoint(parseInt(record.substring(equalsIndex + 1, firstEnd), 36));
    if (commaIndex > equalsIndex && commaIndex < delimiterIndex) {
      value += __legadoFromCodePoint(parseInt(record.substring(commaIndex + 1, delimiterIndex), 36));
    }
    map[name] = value;
    if (name.length > maxNameLength) maxNameLength = name.length;
  }
  return { map: map, maxNameLength: maxNameLength };
};
var __legadoGetEntityTables = function() {
  if (__legadoJsoupEntityTables) return __legadoJsoupEntityTables;
  var base = __legadoParseEntityPoints(__legadoJsoupEntityBasePoints);
  var extended = __legadoParseEntityPoints(__legadoJsoupEntityFullPoints);
  __legadoJsoupEntityTables = {
    base: base.map,
    extended: extended.map,
    maxNameLength: extended.maxNameLength
  };
  return __legadoJsoupEntityTables;
};
var __legadoIsNameLetter = function(character) {
  if (!character) return false;
  var code = character.charCodeAt(0);
  if ((code >= 65 && code <= 90) || (code >= 97 && code <= 122)) return true;
  return code >= 0x80 && /^\p{L}$/u.test(character);
};
var __legadoIsHexDigit = function(character) {
  if (!character) return false;
  var code = character.charCodeAt(0);
  return (code >= 48 && code <= 57) || (code >= 65 && code <= 70) ||
    (code >= 97 && code <= 102);
};
var __legadoIsDecimalDigit = function(character) {
  if (!character) return false;
  var code = character.charCodeAt(0);
  return code >= 48 && code <= 57;
};
var __legadoNormalizeNumericEntity = function(codePoint) {
  if (!isFinite(codePoint) || codePoint < 0 || codePoint > 0x10ffff ||
      (codePoint >= 0xd800 && codePoint <= 0xdfff)) return 0xfffd;
  if (codePoint >= 0x80 && codePoint <= 0x9f) {
    return __legadoJsoupWin1252[codePoint - 0x80];
  }
  return codePoint;
};
var __legadoDecodeHtmlEntities = function(value, inAttribute) {
  var source = String(value === undefined || value === null ? '' : value);
  if (source.indexOf('&') < 0) return source;
  var tables = __legadoGetEntityTables();
  var output = '';
  var cursor = 0;
  while (cursor < source.length) {
    var ampersand = source.indexOf('&', cursor);
    if (ampersand < 0) { output += source.substring(cursor); break; }
    output += source.substring(cursor, ampersand);
    var referenceStart = ampersand + 1;
    if (referenceStart >= source.length) { output += '&'; break; }
    if (source.charAt(referenceStart) === '#') {
      var digitStart = referenceStart + 1;
      var hexadecimal = false;
      if (source.charAt(digitStart) === 'x' || source.charAt(digitStart) === 'X') {
        hexadecimal = true; digitStart++;
      }
      var digitEnd = digitStart;
      while (digitEnd < source.length &&
        (hexadecimal ? __legadoIsHexDigit(source.charAt(digitEnd)) :
          __legadoIsDecimalDigit(source.charAt(digitEnd)))) digitEnd++;
      if (digitEnd === digitStart) { output += '&'; cursor = referenceStart; continue; }
      var codePoint = parseInt(source.substring(digitStart, digitEnd), hexadecimal ? 16 : 10);
      output += __legadoFromCodePoint(__legadoNormalizeNumericEntity(codePoint));
      cursor = source.charAt(digitEnd) === ';' ? digitEnd + 1 : digitEnd;
      continue;
    }
    var nameEnd = referenceStart;
    while (nameEnd < source.length && __legadoIsNameLetter(source.charAt(nameEnd))) nameEnd++;
    while (nameEnd < source.length && __legadoIsDecimalDigit(source.charAt(nameEnd))) nameEnd++;
    if (nameEnd === referenceStart) { output += '&'; cursor = referenceStart; continue; }
    var hasSemicolon = source.charAt(nameEnd) === ';';
    var name = source.substring(referenceStart, nameEnd);
    var named = hasSemicolon ? tables.extended[name] : tables.base[name];
    if (named === undefined) { output += '&'; cursor = referenceStart; continue; }
    var nextCharacter = hasSemicolon ? '' : source.charAt(nameEnd);
    if (!hasSemicolon && inAttribute &&
        (__legadoIsNameLetter(nextCharacter) || __legadoIsDecimalDigit(nextCharacter) || nextCharacter === '=' ||
          nextCharacter === '-' || nextCharacter === '_')) {
      output += '&'; cursor = referenceStart; continue;
    }
    output += named;
    cursor = hasSemicolon ? nameEnd + 1 : nameEnd;
  }
  return output;
};
'@

# 局部 var 作用域版本：JSVM / 嵌入式 JSVM / Rhino 沙箱注入使用。
$jsvmDecoder = @"
var __legadoJsoupEntityBasePoints = '$(Escape-JsString -Value $basePoints)';
var __legadoJsoupEntityFullPoints = '$(Escape-JsString -Value $fullPoints)';
$decoderCore
"@

# 浏览器 window 包装版本：ArkWeb / Rhino 沙箱资源（index.html / index_offline.html / legado_runtime.html）。
$browserDecoder = @"
(function (window) {
  'use strict';
  var data = window.__legadoJsoupEntityData;
  if (!data || Number(data.extendedCount) !== 2125) {
    throw new Error('Pinned Jsoup 1.16.2 entity data is unavailable');
  }
  var __legadoJsoupEntityBasePoints = data.basePoints;
  var __legadoJsoupEntityFullPoints = data.fullPoints;
$decoderCore
  window.__legadoDecodeHtmlEntities = __legadoDecodeHtmlEntities;
})(window);
"@

$arkTs = @"
/**
 * Generated from Jsoup 1.16.2 EntitiesData.java. Do not edit manually.
 * Source SHA-256: $ExpectedEntitiesDataSha256
 */
export const JSOUP_ENTITY_DATA_VERSION: string = '1.16.2';
export const JSOUP_ENTITY_DATA_SHA256: string = '$ExpectedEntitiesDataSha256';
export const JSOUP_BASE_ENTITY_COUNT: number = 106;
export const JSOUP_EXTENDED_ENTITY_COUNT: number = 2125;
export const JSOUP_BASE_ENTITY_POINTS: string = '$(Escape-ArkTsString -Value $basePoints)';
export const JSOUP_FULL_ENTITY_POINTS: string = '$(Escape-ArkTsString -Value $fullPoints)';
/**
 * Shared local-var-scope JS decoder script for JSVM / embedded JSVM / Rhino
 * sandbox injection. Generated from the single decoder core; do not edit.
 */
export const JSOUP_JS_DECODER_SCRIPT: string = '$(Escape-ArkTsString -Value $jsvmDecoder)';
"@

$entityScript = @"
/**
 * JSVM / Rhino shared Jsoup entity decoder script.
 * Generated from Jsoup 1.16.2 EntitiesData.java. Do not edit manually.
 * This module only re-exports the generated decoder constant; it must not
 * maintain an independent entity table, scan rule or decode algorithm.
 */
import { JSOUP_JS_DECODER_SCRIPT } from './JsoupEntityData';

export function buildJsoupEntityCompatibilityScript(): string {
  return JSOUP_JS_DECODER_SCRIPT;
}
"@

$js = @"
/*
 * Generated from Jsoup 1.16.2 EntitiesData.java. Do not edit manually.
 * Source SHA-256: $ExpectedEntitiesDataSha256
 */
(function (window) {
  'use strict';
  window.__legadoJsoupEntityData = Object.freeze({
    version: '1.16.2',
    sourceSha256: '$ExpectedEntitiesDataSha256',
    baseCount: 106,
    extendedCount: 2125,
    basePoints: '$(Escape-JsString -Value $basePoints)',
    fullPoints: '$(Escape-JsString -Value $fullPoints)'
  });
})(window);
"@

$outputs = @(
  [pscustomobject][ordered]@{
    path = 'entry/src/main/ets/libs/htmlparser/JsoupEntityData.ets'
    content = $arkTs
  },
  [pscustomobject][ordered]@{
    path = 'entry/src/main/ets/libs/htmlparser/JsoupEntityScript.ets'
    content = $entityScript
  },
  [pscustomobject][ordered]@{
    path = 'entry/src/main/resources/rawfile/jsoup_entity_data.js'
    content = $js
  },
  [pscustomobject][ordered]@{
    path = 'entry/src/main/resources/rawfile/rhino_sandbox/jsoup_entity_data.js'
    content = $js
  },
  [pscustomobject][ordered]@{
    path = 'entry/src/main/resources/rawfile/jsoup_entity_decoder.js'
    content = $browserDecoder
  },
  [pscustomobject][ordered]@{
    path = 'entry/src/main/resources/rawfile/rhino_sandbox/jsoup_entity_decoder.js'
    content = $browserDecoder
  },
  [pscustomobject][ordered]@{
    path = 'manxia-legado-runtime/jsoup_entity_data.js'
    content = $js
  },
  [pscustomobject][ordered]@{
    path = 'manxia-legado-runtime/rhino_sandbox/jsoup_entity_data.js'
    content = $js
  },
  [pscustomobject][ordered]@{
    path = 'manxia-legado-runtime/jsoup_entity_decoder.js'
    content = $browserDecoder
  },
  [pscustomobject][ordered]@{
    path = 'manxia-legado-runtime/rhino_sandbox/jsoup_entity_decoder.js'
    content = $browserDecoder
  }
)

$written = New-Object 'System.Collections.Generic.List[object]'
$forbiddenToken = 'globalThis'
$forbiddenTokenViolations = New-Object 'System.Collections.Generic.List[string]'
foreach ($output in $outputs) {
  $text = [string]$output.content
  if ($text.Contains($forbiddenToken)) {
    $forbiddenTokenViolations.Add([string]$output.path)
  }
  Write-Utf8NoBom -Path ([string]$output.path) -Text $text
  $absolute = Get-RepoPath -Path ([string]$output.path)
  [void]$written.Add([pscustomobject][ordered]@{
      path = [string]$output.path
      sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $absolute).Hash.ToUpperInvariant()
      bytes = (Get-Item -LiteralPath $absolute).Length
    })
}

if ($forbiddenTokenViolations.Count -gt 0) {
  throw "Generated outputs must not contain ${forbiddenToken}: $($forbiddenTokenViolations -join ', ')"
}

[pscustomobject][ordered]@{
  status = 'generated'
  jsoupVersion = '1.16.2'
  dataSource = $dataSource
  referenceJsonPath = $ReferenceJsonPath
  entitiesDataSha256 = $ExpectedEntitiesDataSha256
  baseEntityCount = $baseCount
  extendedEntityCount = $fullCount
  jsvmDecoderVariant = 'local_var_scope'
  browserDecoderVariant = 'window_wrapper'
  forbiddenTokenViolations = @()
  outputs = $written.ToArray()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
} | ConvertTo-Json -Depth 20
