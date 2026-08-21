[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-terminal-text-projection-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-terminal-text-projection-pre-fix-20260810.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-terminal-text-projection-post-fix-20260811.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$sourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'
$script:textNodesOccurrences = 0
$script:ownTextOccurrences = 0
$script:jsOwnTextOccurrences = 0
$script:textNodesSources = [System.Collections.Generic.HashSet[int]]::new()
$script:ownTextSources = [System.Collections.Generic.HashSet[int]]::new()
$script:jsOwnTextSources = [System.Collections.Generic.HashSet[int]]::new()

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  if ([System.IO.Path]::IsPathRooted($RelativePath)) {
    return $RelativePath
  }
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "required file is missing: $RelativePath"
  }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and
    $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Read-StrictText -RelativePath $RelativePath | ConvertFrom-Json -Depth 100
}

function Assert-Contract {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][string]$Detail,
    [string[]]$Evidence = @()
  )
  if (-not $Condition) {
    throw "243 terminal text projection post-fix contract failed: $Detail"
  }
  $script:assertions++
  [void]$script:checks.Add([pscustomobject][ordered]@{
      id = $Id
      status = 'passed'
      detail = $Detail
      evidencePaths = @($Evidence)
    })
}

function Write-AtomicJson {
  param(
    [Parameter(Mandatory = $true)][string]$RelativePath,
    [Parameter(Mandatory = $true)][object]$Value
  )
  $path = Get-RepoPath -RelativePath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText(
      $temporaryPath,
      ($Value | ConvertTo-Json -Depth 100),
      $noBomUtf8
    )
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      [System.IO.File]::Delete($temporaryPath)
    }
  }
}

function Get-SourceRange {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$StartMarker,
    [Parameter(Mandatory = $true)][string]$EndMarker,
    [Parameter(Mandatory = $true)][string]$Label
  )
  $start = $Source.IndexOf($StartMarker)
  if ($start -lt 0) {
    throw "$Label start marker is missing"
  }
  $end = $Source.IndexOf($EndMarker, $start + $StartMarker.Length)
  if ($end -le $start) {
    throw "$Label end marker is missing"
  }
  return $Source.Substring($start, $end - $start)
}

function Get-TemplateBody {
  param(
    [Parameter(Mandatory = $true)][string]$Source,
    [Parameter(Mandatory = $true)][string]$MethodMarker,
    [Parameter(Mandatory = $true)][string]$Label
  )
  $methodStart = $Source.IndexOf($MethodMarker)
  if ($methodStart -lt 0) {
    throw "$Label method marker is missing"
  }
  $tick = [char]96
  $returnMarker = 'return ' + $tick
  $returnStart = $Source.IndexOf($returnMarker, $methodStart)
  if ($returnStart -lt 0) {
    throw "$Label template return is missing"
  }
  $bodyStart = $returnStart + $returnMarker.Length
  $bodyEnd = $Source.IndexOf(($tick + ';'), $bodyStart)
  if ($bodyEnd -le $bodyStart) {
    throw "$Label template terminator is missing"
  }
  return $Source.Substring($bodyStart, $bodyEnd - $bodyStart)
}

function Measure-SourceUsage {
  param(
    [AllowNull()][object]$Value,
    [Parameter(Mandatory = $true)][int]$Ordinal
  )
  if ($null -eq $Value) {
    return
  }
  if ($Value -is [string]) {
    $text = [string]$Value
    $textNodesCount = [regex]::Matches(
      $text,
      '(?i)@textNodes(?![A-Za-z0-9_])'
    ).Count
    $ownTextCount = [regex]::Matches(
      $text,
      '(?i)@ownText(?![A-Za-z0-9_])'
    ).Count
    $jsOwnTextCount = [regex]::Matches(
      $text,
      '(?i)\.ownText\s*\('
    ).Count
    if ($textNodesCount -gt 0) {
      $script:textNodesOccurrences += $textNodesCount
      [void]$script:textNodesSources.Add($Ordinal)
    }
    if ($ownTextCount -gt 0) {
      $script:ownTextOccurrences += $ownTextCount
      [void]$script:ownTextSources.Add($Ordinal)
    }
    if ($jsOwnTextCount -gt 0) {
      $script:jsOwnTextOccurrences += $jsOwnTextCount
      [void]$script:jsOwnTextSources.Add($Ordinal)
    }
    return
  }
  if ($Value -is [System.Collections.IEnumerable]) {
    foreach ($item in $Value) {
      Measure-SourceUsage -Value $item -Ordinal $Ordinal
    }
    return
  }
  foreach ($property in $Value.PSObject.Properties) {
    Measure-SourceUsage -Value $property.Value -Ordinal $Ordinal
  }
}

$state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson -RelativePath $FixturePath
$failureWitness = Read-StrictJson -RelativePath $FailureWitnessPath

$normalizationPath = 'entry/src/main/ets/libs/htmlparser/LegadoTextNormalization.ets'
$elementPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$bridgePath = 'entry/src/main/ets/libs/htmlparser/LegadoHtmlBridge.ets'
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$arkWebPath = 'entry/src/main/resources/rawfile/legado_runtime.html'
$jsEnginePath = 'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets'
$rhinoInlinePath = 'entry/src/main/ets/Framework/Novel/RhinoWasmExecutor.ets'
$rhinoStandalonePath = 'entry/src/main/resources/rawfile/rhino_sandbox/jsoup_impl.js'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$versionsPath = 'legado/gradle/libs.versions.toml'

$normalization = Read-StrictText -RelativePath $normalizationPath
$element = Read-StrictText -RelativePath $elementPath
$bridge = Read-StrictText -RelativePath $bridgePath
$analyzer = Read-StrictText -RelativePath $analyzerPath
$arkWeb = Read-StrictText -RelativePath $arkWebPath
$jsEngine = Read-StrictText -RelativePath $jsEnginePath
$rhinoInline = Read-StrictText -RelativePath $rhinoInlinePath
$rhinoStandalone = Read-StrictText -RelativePath $rhinoStandalonePath
$legado = Read-StrictText -RelativePath $legadoPath
$versions = Read-StrictText -RelativePath $versionsPath

Assert-Contract (
  [int]$state.baseline.sourceCount -eq 458 -and
  [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and
  [string]$state.baseline.legadoCommit -eq $legadoCommit
) 'baseline_state' 'machine state remains pinned to the frozen 458-source and Legado baseline.' @(
  'tools/legado-compat/state/full-source-validation-state.json'
)
Assert-Contract (
  [string]$state.governance.status -eq 'running' -and
  [string]$state.governance.activeTaskId -eq 'COMPAT-006' -and
  [string]$state.governance.activeIssueId -eq $issueId -and
  -not [bool]$state.governance.semanticMatchAllowed
) 'queue_gate' 'issue 243 remains the sole active static issue and semantic match stays locked.' @(
  'tools/legado-compat/state/full-source-validation-state.json'
)
Assert-Contract (
  [string]$fixture.contract -eq 'legado_jsoup_terminal_text_projection' -and
  [string]$fixture.issueId -eq $issueId -and
  @($fixture.cases).Count -eq 6 -and
  [string]$fixture.baseline.jsoupVersion -eq '1.16.2'
) 'fixture_shape' 'the six-case terminal projection fixture remains bound to Jsoup 1.16.2.' @(
  $FixturePath
)
Assert-Contract (
  [string]$failureWitness.status -eq 'failed' -and
  [string]$failureWitness.issueId -eq $issueId -and
  @($failureWitness.runtimeActionsPerformed).Count -eq 0 -and
  -not [bool]$failureWitness.semanticMatchAllowed
) 'failure_witness_preserved' 'the pre-fix failure witness remains failed and static-only.' @(
  $FailureWitnessPath
)
Assert-Contract (
  $versions.Contains('jsoup = "1.16.2"') -and
  $legado.Contains('val text = element.text()') -and
  $legado.Contains('val contentEs = element.textNodes()') -and
  $legado.Contains('val text = item.text().trim { it <= '' '' }') -and
  $legado.Contains('tn.joinToString("\n")') -and
  $legado.Contains('val text = element.ownText()')
) 'legado_reference' 'the pinned Legado consumer keeps text, textNodes, and ownText as distinct terminal projections.' @(
  $legadoPath,
  $versionsPath
)

if (-not (Test-Path -LiteralPath $sourcePackagePath -PathType Leaf)) {
  throw "frozen source package is missing: $sourcePackagePath"
}
$packageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePackagePath).Hash.ToUpperInvariant()
$packageBytes = [System.IO.File]::ReadAllBytes($sourcePackagePath)
$packageOffset = 0
if ($packageBytes.Length -ge 3 -and $packageBytes[0] -eq 0xEF -and
  $packageBytes[1] -eq 0xBB -and $packageBytes[2] -eq 0xBF) {
  $packageOffset = 3
}
$packageText = $strictUtf8.GetString(
  $packageBytes,
  $packageOffset,
  $packageBytes.Length - $packageOffset
)
$sources = @($packageText | ConvertFrom-Json -Depth 100)
for ($sourceIndex = 0; $sourceIndex -lt $sources.Count; $sourceIndex++) {
  Measure-SourceUsage -Value $sources[$sourceIndex] -Ordinal ($sourceIndex + 1)
}
Assert-Contract (
  $packageHash -eq $baselineHash -and
  $sources.Count -eq 458
) 'source_package_binding' 'the local source package still matches the frozen hash and count.' @(
  $FixturePath
)
Assert-Contract (
  $script:textNodesOccurrences -eq [int]$fixture.sourceUsage.textNodes.occurrences -and
  $script:textNodesSources.Count -eq [int]$fixture.sourceUsage.textNodes.sourceCount -and
  $script:ownTextOccurrences -eq [int]$fixture.sourceUsage.ownText.occurrences -and
  $script:ownTextSources.Count -eq [int]$fixture.sourceUsage.ownText.sourceCount -and
  $script:jsOwnTextOccurrences -eq [int]$fixture.sourceUsage.jsOwnText.occurrences -and
  $script:jsOwnTextSources.Count -eq [int]$fixture.sourceUsage.jsOwnText.sourceCount
) 'source_usage_matrix' 'the fixture usage counts are reproduced from all UTF-8 JSON strings in the frozen package.' @(
  $FixturePath
)

Assert-Contract (
  $normalization.Contains('appendJsoupSpaceBoundary(): void') -and
  $normalization.Contains('static isDataTag(tagName: string): boolean') -and
  $normalization.Contains('static isFormatAsBlockTag(tagName: string): boolean') -and
  $normalization.Contains('static trimJavaWhitespace(value: string): string')
) 'typed_normalization_primitives' 'typed DOM projections share explicit Jsoup boundary, data-node, formatting, and Java-trim primitives.' @(
  $normalizationPath
)
Assert-Contract (
  $element.Contains('  get text(): string {') -and
  $element.Contains('  get textNodes(): string {') -and
  $element.Contains('  get ownText(): string {') -and
  $element.Contains('accumulator.appendJsoupSpaceBoundary();') -and
  $element.Contains('LegadoTextNormalization.isDataTag(this.tagName)')
) 'typed_dom_projection' 'typed DOM exposes three separate terminal projections and excludes data nodes.' @(
  $elementPath
)
Assert-Contract (
  $bridge.Contains("case 'textnodes':") -and
  $bridge.Contains('return elem.textNodes;') -and
  $bridge.Contains("case 'owntext':") -and
  $bridge.Contains('return elem.ownText;')
) 'typed_bridge_consumers' 'the DOM bridge consumes textNodes and ownText without collapsing them into text.' @(
  $bridgePath
)
Assert-Contract (
  $analyzer.Contains('return this.extractJsoupText(element);') -and
  $analyzer.Contains('return this.extractDirectTextNodes(element);') -and
  $analyzer.Contains('return this.extractOwnText(element);') -and
  $analyzer.Contains('const parsed = parseHtml(element);') -and
  $analyzer.Contains('return candidate.textNodes;') -and
  $analyzer.Contains('return candidate.ownText;')
) 'string_analyzer_projection' 'the string analyzer delegates all terminal projections to the same typed parser contract.' @(
  $analyzerPath,
  $elementPath
)
Assert-Contract (
  $arkWeb.Contains("if (attr === 'textNodes') return legadoDirectTextNodes(node).join('\n');") -and
  $arkWeb.Contains("if (attr === 'ownText') return legadoOwnText(node);") -and
  $arkWeb.Contains('textNodes: function () { return legadoCreateRuntimeTextNodeList(node); }') -and
  $arkWeb.Contains('ownText: function () { return node ? legadoOwnText(node) : ''''; }')
) 'arkweb_projection_consumers' 'ArkWeb terminal rules and direct JS wrappers expose distinct textNodes and ownText APIs.' @(
  $arkWebPath
)

$injectionMarker = [char]36 + '{this.buildJsoupTextProjectionCompatibilityScript()}'
$jsEngineInjectionCount = [regex]::Matches(
  $jsEngine,
  [regex]::Escape($injectionMarker)
).Count
$jsEngineEscapedJoinCount = @(
  $jsEngine -split "\r?\n" |
    Where-Object { $_.Contains("return values.join('\\n');") }
).Count
$rhinoEscapedJoinCount = @(
  $rhinoInline -split "\r?\n" |
    Where-Object {
      $_.Contains(
        "return textValues.filter(function(value) { return value.length > 0; }).join('\\n');"
      )
    }
).Count
Assert-Contract (
  $jsEngineInjectionCount -eq 2 -and
  $jsEngineEscapedJoinCount -eq 1 -and
  $rhinoEscapedJoinCount -eq 1
) 'generated_script_escape_contract' 'both ArkTS templates retain two source backslashes so generated inner JS contains one valid LF escape.' @(
  $jsEnginePath,
  $rhinoInlinePath
)
Assert-Contract (
  $jsEngine.Contains("if (attr === 'textNodes') return __legadoJsoupTextNodesTerminal(element);") -and
  $jsEngine.Contains("if (attr === 'ownText') return typeof element.ownText === 'function' ? element.ownText() : '';") -and
  $jsEngine.Contains("if (split.attr === 'textNodes')") -and
  $jsEngine.Contains("if (split.attr === 'ownText')")
) 'jsvm_terminal_consumers' 'every generated JSVM terminal path branches textNodes and ownText explicitly.' @(
  $jsEnginePath
)
Assert-Contract (
  $rhinoInline.Contains('JsoupElement.prototype.ownText = function()') -and
  $rhinoInline.Contains('JsoupElement.prototype.textNodes = function()') -and
  $rhinoInline.Contains("if (name === 'textNodes')") -and
  $rhinoInline.Contains("if (name === 'ownText')")
) 'rhino_inline_consumers' 'the inline Rhino shim exposes direct and terminal textNodes/ownText consumers.' @(
  $rhinoInlinePath
)
Assert-Contract (
  $rhinoStandalone.Contains('function legadoFallbackTokenize(value)') -and
  $rhinoStandalone.Contains('function legadoFallbackBuildTree(value, expectedTagName)') -and
  $rhinoStandalone.Contains('function legadoFallbackText(node)') -and
  $rhinoStandalone.Contains('function legadoFallbackOwnText(node)') -and
  $rhinoStandalone.Contains('function legadoFallbackTextNodeList(node)') -and
  $rhinoStandalone.Contains('const tree = legadoFallbackBuildTree(this._html, this._tagName);')
) 'rhino_standalone_fallback' 'parserless Rhino uses a structured tree for all three projections instead of regex tag stripping.' @(
  $rhinoStandalonePath
)

$arkWebProjection = Get-SourceRange -Source $arkWeb -StartMarker '    var legadoIsActuallyWhitespace = function (code) {' -EndMarker '    var legadoElementSiblingIndex = function (node) {' -Label 'ArkWeb projection'
$jsVmTemplateBody = Get-TemplateBody -Source $jsEngine -MethodMarker '  private buildJsoupTextProjectionCompatibilityScript(): string {' -Label 'JSVM projection'
$rhinoInlineProjection = Get-SourceRange -Source $rhinoInline -StartMarker '  var legadoIsActuallyWhitespace = function(code) {' -EndMarker '  JsoupDocument.prototype.title = function() {' -Label 'Rhino inline projection'

$nodeCommand = Get-Command node -ErrorAction Stop
$standaloneAbsolutePath = (Resolve-Path -LiteralPath (Get-RepoPath $rhinoStandalonePath)).Path
$nodeCheckOutput = (& $nodeCommand.Source --check $standaloneAbsolutePath 2>&1 | Out-String).Trim()
$nodeCheckExitCode = $LASTEXITCODE
Assert-Contract (
  $nodeCheckExitCode -eq 0
) 'rhino_standalone_syntax' 'the standalone Rhino compatibility source passes Node syntax validation.' @(
  $rhinoStandalonePath
)

$payload = [pscustomobject][ordered]@{
  fixture = $fixture
  arkWebProjection = $arkWebProjection
  jsVmTemplateBody = $jsVmTemplateBody
  rhinoInlineProjection = $rhinoInlineProjection
  rhinoStandalonePath = $standaloneAbsolutePath
}
$nodeRunner = @'
'use strict';
const fs = require('fs');
const payload = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));

function decodeTemplateBody(body, label) {
  const tick = String.fromCharCode(96);
  if (body.indexOf(tick) >= 0 || body.indexOf('$' + '{') >= 0) {
    throw new Error(label + ' contains an unsupported nested template token');
  }
  return Function('return ' + tick + body + tick + ';')();
}

function decodeEntities(value) {
  const named = {
    nbsp: '\u00a0',
    amp: '&',
    lt: '<',
    gt: '>',
    quot: '"',
    apos: "'"
  };
  return String(value || '').replace(
    /&(#x[0-9a-f]+|#[0-9]+|[a-z]+);/gi,
    function(match, entity) {
      const lower = entity.toLowerCase();
      if (lower.charAt(0) === '#') {
        const radix = lower.charAt(1) === 'x' ? 16 : 10;
        const digits = radix === 16 ? lower.substring(2) : lower.substring(1);
        const codePoint = parseInt(digits, radix);
        return Number.isFinite(codePoint) && codePoint >= 0 && codePoint <= 0x10ffff
          ? String.fromCodePoint(codePoint)
          : match;
      }
      return Object.prototype.hasOwnProperty.call(named, lower) ? named[lower] : match;
    }
  );
}

function appendChild(parent, child) {
  const previous = parent.childNodes.length > 0
    ? parent.childNodes[parent.childNodes.length - 1]
    : null;
  if (previous) previous.nextSibling = child;
  child.parentNode = parent;
  child.parentElement = parent.nodeType === 1 ? parent : null;
  child.nextSibling = null;
  parent.childNodes.push(child);
}

function createElement(name) {
  return {
    nodeType: 1,
    localName: name,
    tagName: name,
    childNodes: [],
    parentNode: null,
    parentElement: null,
    nextSibling: null
  };
}

function createText(value) {
  return {
    nodeType: 3,
    nodeValue: value,
    textContent: value,
    childNodes: [],
    parentNode: null,
    parentElement: null,
    nextSibling: null
  };
}

function parseRoot(html) {
  const synthetic = createElement('__root__');
  const stack = [synthetic];
  const voidTags = new Set([
    'area', 'base', 'basefont', 'bgsound', 'br', 'col', 'command', 'device',
    'embed', 'frame', 'hr', 'img', 'input', 'keygen', 'link', 'menuitem',
    'meta', 'param', 'source', 'track', 'wbr'
  ]);
  let cursor = 0;
  while (cursor < html.length) {
    const tagStart = html.indexOf('<', cursor);
    if (tagStart < 0) {
      if (cursor < html.length) {
        appendChild(stack[stack.length - 1], createText(decodeEntities(html.substring(cursor))));
      }
      break;
    }
    if (tagStart > cursor) {
      appendChild(
        stack[stack.length - 1],
        createText(decodeEntities(html.substring(cursor, tagStart)))
      );
    }
    if (html.substring(tagStart, tagStart + 4) === '<!--') {
      const commentEnd = html.indexOf('-->', tagStart + 4);
      cursor = commentEnd < 0 ? html.length : commentEnd + 3;
      continue;
    }
    let scan = tagStart + 1;
    let quote = '';
    while (scan < html.length) {
      const character = html.charAt(scan);
      if (quote) {
        if (character === quote) quote = '';
      } else if (character === '"' || character === "'") {
        quote = character;
      } else if (character === '>') {
        break;
      }
      scan++;
    }
    if (scan >= html.length) {
      appendChild(stack[stack.length - 1], createText(decodeEntities(html.substring(tagStart))));
      break;
    }
    const body = html.substring(tagStart + 1, scan).trim();
    if (!body || body.charAt(0) === '!' || body.charAt(0) === '?') {
      cursor = scan + 1;
      continue;
    }
    const closing = body.charAt(0) === '/';
    const nameMatch = (closing ? body.substring(1) : body).trim().match(/^([A-Za-z0-9:_-]+)/);
    if (!nameMatch) {
      cursor = scan + 1;
      continue;
    }
    const name = nameMatch[1].toLowerCase();
    if (closing) {
      for (let stackIndex = stack.length - 1; stackIndex > 0; stackIndex--) {
        if (stack[stackIndex].localName === name) {
          stack.length = stackIndex;
          break;
        }
      }
    } else {
      const element = createElement(name);
      appendChild(stack[stack.length - 1], element);
      const selfClosing = /\/\s*$/.test(body) || voidTags.has(name);
      if (!selfClosing) stack.push(element);
    }
    cursor = scan + 1;
  }
  for (let index = 0; index < synthetic.childNodes.length; index++) {
    if (synthetic.childNodes[index].nodeType === 1) return synthetic.childNodes[index];
  }
  return synthetic;
}

function buildArkWebApi(source) {
  return Function(
    source +
    '\nreturn {' +
    'text: legadoText,' +
    'ownText: legadoOwnText,' +
    'textNodes: function(node) { return legadoDirectTextNodes(node).join("\\n"); }' +
    '};'
  )();
}

function buildRhinoInlineApi(templateBody) {
  const source = decodeTemplateBody(templateBody, 'Rhino inline projection');
  return Function(
    source +
    '\nreturn {' +
    'text: legadoText,' +
    'ownText: legadoOwnText,' +
    'textNodes: function(node) {' +
    'var nodes = legadoCreateTextNodeList(node);' +
    'var values = [];' +
    'for (var index = 0; index < nodes.length; index++) {' +
    'var value = legadoTrimJavaWhitespace(nodes[index].text());' +
    'if (value) values.push(value);' +
    '}' +
    'return values.join("\\n");' +
    '}' +
    '};'
  )();
}

function buildJsVmApi(templateBody) {
  const source = decodeTemplateBody(templateBody, 'JSVM projection');
  return Function(
    source +
    '\nreturn {' +
    'text: __legadoJsoupTextFromHtml,' +
    'ownText: __legadoJsoupOwnTextFromHtml,' +
    'textNodes: function(html) {' +
    'return __legadoJsoupTextNodesTerminal({' +
    'textNodes: function() { return __legadoJsoupTextNodeListFromHtml(html); }' +
    '});' +
    '}' +
    '};'
  )();
}

function projectDom(api, html) {
  const root = parseRoot(html);
  return {
    text: api.text(root),
    ownText: api.ownText(root),
    textNodes: api.textNodes(root)
  };
}

function compare(pathName, caseItem, actual, checks) {
  const fields = ['text', 'ownText', 'textNodes'];
  for (let index = 0; index < fields.length; index++) {
    const field = fields[index];
    const expected = caseItem.expected[field];
    if (actual[field] !== expected) {
      throw new Error(
        pathName + '/' + caseItem.id + '/' + field +
        ' expected ' + JSON.stringify(expected) +
        ' but received ' + JSON.stringify(actual[field])
      );
    }
    checks.push({
      path: pathName,
      caseId: caseItem.id,
      field: field,
      status: 'passed'
    });
  }
}

const arkWebApi = buildArkWebApi(payload.arkWebProjection);
const rhinoInlineApi = buildRhinoInlineApi(payload.rhinoInlineProjection);
const jsVmApi = buildJsVmApi(payload.jsVmTemplateBody);
const savedLog = console.log;
console.log = function() {};
require(payload.rhinoStandalonePath);
console.log = savedLog;

const checks = [];
for (let caseIndex = 0; caseIndex < payload.fixture.cases.length; caseIndex++) {
  const caseItem = payload.fixture.cases[caseIndex];
  compare('arkweb_dom', caseItem, projectDom(arkWebApi, caseItem.html), checks);
  compare('rhino_inline_dom', caseItem, projectDom(rhinoInlineApi, caseItem.html), checks);
  compare('jsvm_string', caseItem, {
    text: jsVmApi.text(caseItem.html),
    ownText: jsVmApi.ownText(caseItem.html),
    textNodes: jsVmApi.textNodes(caseItem.html)
  }, checks);
  const rootMatch = caseItem.html.match(/^\s*<([A-Za-z0-9:_-]+)/);
  const rootName = rootMatch ? rootMatch[1].toLowerCase() : '';
  const standalone = new global.JsoupElement(null, null, caseItem.html, rootName);
  compare('rhino_standalone_string', caseItem, {
    text: standalone.text(),
    ownText: standalone.ownText(),
    textNodes: standalone.attr('textNodes')
  }, checks);
}

process.stdout.write(JSON.stringify({
  status: 'passed',
  pathCount: 4,
  caseCount: payload.fixture.cases.length,
  fieldChecks: checks.length,
  checks: checks
}));
'@

$payloadPath = Join-Path ([System.IO.Path]::GetTempPath()) (
  "manxia-jsoup-terminal-payload-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()).json"
)
$runnerPath = Join-Path ([System.IO.Path]::GetTempPath()) (
  "manxia-jsoup-terminal-runner-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()).js"
)
try {
  [System.IO.File]::WriteAllText(
    $payloadPath,
    ($payload | ConvertTo-Json -Depth 100),
    $noBomUtf8
  )
  [System.IO.File]::WriteAllText($runnerPath, $nodeRunner, $noBomUtf8)
  $nodeOutput = (& $nodeCommand.Source $runnerPath $payloadPath 2>&1 | Out-String).Trim()
  $nodeExitCode = $LASTEXITCODE
  if ($nodeExitCode -ne 0) {
    throw "deterministic projection evaluator failed: $nodeOutput"
  }
  $projectionResult = $nodeOutput | ConvertFrom-Json -Depth 100
} finally {
  if (Test-Path -LiteralPath $payloadPath) {
    [System.IO.File]::Delete($payloadPath)
  }
  if (Test-Path -LiteralPath $runnerPath) {
    [System.IO.File]::Delete($runnerPath)
  }
}

Assert-Contract (
  [string]$projectionResult.status -eq 'passed' -and
  [int]$projectionResult.pathCount -eq 4 -and
  [int]$projectionResult.caseCount -eq 6 -and
  [int]$projectionResult.fieldChecks -eq 72
) 'deterministic_projection_matrix' 'four executable projection paths match all three fields in all six fixed cases.' @(
  $FixturePath,
  $arkWebPath,
  $jsEnginePath,
  $rhinoInlinePath,
  $rhinoStandalonePath
)

$hashPaths = @(
  $normalizationPath,
  $elementPath,
  $bridgePath,
  $analyzerPath,
  $arkWebPath,
  $jsEnginePath,
  $rhinoInlinePath,
  $rhinoStandalonePath
)
$currentHeadHashes = @(
  foreach ($hashPath in $hashPaths) {
    [pscustomobject][ordered]@{
      path = $hashPath
      sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (
          Get-RepoPath -RelativePath $hashPath
        )).Hash.ToUpperInvariant()
    }
  }
)

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'post_fix_static_contract'
  issueId = $issueId
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{
    sourceCount = 458
    sourcePackageSha256 = $baselineHash
    legadoCommit = $legadoCommit
    jsoupVersion = '1.16.2'
  }
  fixturePath = $FixturePath
  failureWitnessPath = $FailureWitnessPath
  sourceUsage = [pscustomobject][ordered]@{
    textNodes = [pscustomobject][ordered]@{
      occurrences = $script:textNodesOccurrences
      sourceCount = $script:textNodesSources.Count
    }
    ownText = [pscustomobject][ordered]@{
      occurrences = $script:ownTextOccurrences
      sourceCount = $script:ownTextSources.Count
    }
    jsOwnText = [pscustomobject][ordered]@{
      occurrences = $script:jsOwnTextOccurrences
      sourceCount = $script:jsOwnTextSources.Count
    }
  }
  changedPaths = $hashPaths
  currentHeadHashes = $currentHeadHashes
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  deterministicProjection = [pscustomobject][ordered]@{
    pathCount = [int]$projectionResult.pathCount
    caseCount = [int]$projectionResult.caseCount
    fieldChecks = [int]$projectionResult.fieldChecks
    paths = @('arkweb_dom', 'rhino_inline_dom', 'jsvm_string', 'rhino_standalone_string')
  }
  nodeSyntaxCheck = [pscustomobject][ordered]@{
    path = $rhinoStandalonePath
    exitCode = $nodeCheckExitCode
    output = $nodeCheckOutput
  }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_static_source_and_deterministic_projection_contract_only;app_runtime_build_device_and_fixed_legado_diff_deferred_to_R4'
  deferredGates = @(
    'ArkTS compile and HarmonyOS build',
    'ArkWeb and JSVM device execution',
    'Rhino runtime execution',
    'deterministic 458-source Harness',
    'fixed-Legado differential'
  )
  closeCondition = 'ISSUE-COMPAT-243 remains verifying until R4 executes the fixed cases and affected source sets through app, device, deterministic Harness, and pinned Legado differential gates.'
}

Write-AtomicJson -RelativePath $ResultPath -Value $result
$result | ConvertTo-Json -Depth 100
