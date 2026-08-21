[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = '',
  [string]$PreFixEvidencePath = '',
  [string]$ConsumerEvidencePath = '',
  [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if ([string]::IsNullOrWhiteSpace($FixturePath)) { $FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-text-whitespace.json' }
if ([string]::IsNullOrWhiteSpace($PreFixEvidencePath)) { $PreFixEvidencePath = 'tools/legado-compat/evidence/contract-legado-jsoup-text-whitespace-pre-fix-20260809.json' }
if ([string]::IsNullOrWhiteSpace($ConsumerEvidencePath)) { $ConsumerEvidencePath = 'tools/legado-compat/evidence/contract-legado-jsoup-text-whitespace-consumers-pre-fix-20260809.json' }
if ([string]::IsNullOrWhiteSpace($ResultPath)) { $ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-text-whitespace-20260809.json' }

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing JSON: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes) | ConvertFrom-Json
}

function Read-StrictText {
  param([string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing text: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Jsoup text whitespace contract failed: $Message" }
}

function Write-AtomicJson {
  param([string]$Path, [object]$Value)
  $absolute = Get-RepoPath -RelativePath $Path
  $directory = Split-Path -Parent $absolute
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$absolute.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 30), [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $absolute -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$result = $null
try {
  $state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
  $fixture = Read-StrictJson -RelativePath $FixturePath
  $preFix = Read-StrictJson -RelativePath $PreFixEvidencePath
  $consumer = Read-StrictJson -RelativePath $ConsumerEvidencePath
  Assert-Contract ([string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS') '235 is not the active issue.'
  Assert-Contract ([string]$fixture.contract -eq 'legado_jsoup_text_whitespace' -and @($fixture.cases).Count -eq 8) 'whitespace fixture shape changed.'
  Assert-Contract ([string]$preFix.status -eq 'failed' -and [string]$consumer.status -eq 'failed') 'pre-fix witnesses must remain preserved as failed evidence.'

  $normalization = Read-StrictText -RelativePath 'entry/src/main/ets/libs/htmlparser/LegadoTextNormalization.ets'
  $index = Read-StrictText -RelativePath 'entry/src/main/ets/libs/htmlparser/index.ets'
  $element = Read-StrictText -RelativePath 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
  $analyzer = Read-StrictText -RelativePath 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
  $runtime = Read-StrictText -RelativePath 'entry/src/main/resources/rawfile/legado_runtime.html'
  $legadoAnalyze = Read-StrictText -RelativePath 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
  $legadoExtensions = Read-StrictText -RelativePath 'legado/app/src/main/java/io/legado/app/utils/JsoupExtensions.kt'

  $assertions = [System.Collections.Generic.List[string]]::new()
  $assertions.Add('normalization module exists')
  Assert-Contract ($normalization.Contains('isActuallyWhitespace') -and $normalization.Contains('0xA0')) 'normalization module must include Jsoup ordinary whitespace and NBSP.'
  $assertions.Add('ordinary whitespace set')
  Assert-Contract ($normalization.Contains('isInvisibleChar') -and $normalization.Contains('0x200B') -and $normalization.Contains('0x00AD')) 'normalization module must filter Jsoup invisible characters.'
  $assertions.Add('invisible character set')
  Assert-Contract ($normalization.Contains('isPreserveWhitespaceTag') -and $normalization.Contains('plaintext') -and $normalization.Contains('textarea')) 'preserve-whitespace tag set is incomplete.'
  $assertions.Add('preserve-whitespace tags')
  Assert-Contract ($normalization.Contains('trimJavaWhitespace') -and $normalization.Contains('0x20')) 'final trim must follow Java String.trim range.'
  $assertions.Add('Java trim')
  Assert-Contract ($index.Contains("LegadoTextAccumulator") -and $index.Contains("LegadoTextNormalization")) 'normalization exports are missing.'
  $assertions.Add('normalization exports')
  Assert-Contract ($element.Contains('new LegadoTextAccumulator()') -and $element.Contains('appendJsoupText') -and $element.Contains('isPreserveWhitespace')) 'DOM text projection is not routed through the accumulator.'
  $assertions.Add('DOM accumulator route')
  Assert-Contract ($element.Contains("element.tagName === 'br'") -and $element.Contains('appendLineBreak')) 'DOM ownText/text does not handle br boundaries.'
  $assertions.Add('DOM br boundary')
  Assert-Contract ($analyzer.Contains('new LegadoTextAccumulator()') -and $analyzer.Contains('LegadoTextNormalization.isPreserveWhitespaceTag')) 'string fallback does not use the shared normalization contract.'
  $assertions.Add('string shared accumulator')
  Assert-Contract ($analyzer.Contains('return this.extractDirectTextNodes(element);') -and $analyzer.Contains('extractTagNameFromRawTag')) 'string ownText projection is not routed through direct-node normalization.'
  $assertions.Add('string ownText route')
  Assert-Contract ($analyzer.Contains('this.decodeHtmlEntitiesFast(part)') -and $analyzer.Contains('accumulator.toTrimmedString()')) 'string fallback does not decode before normalizing and trim at the final boundary.'
  $assertions.Add('string decode/trim order')
  Assert-Contract ($runtime.Contains('legadoCreateTextAccumulator') -and $runtime.Contains('legadoAppendElementText') -and $runtime.Contains('legadoText = function')) 'ArkWeb text projection helper is missing.'
  $assertions.Add('ArkWeb accumulator route')
  Assert-Contract ($runtime.Contains('legadoIsActuallyWhitespace') -and $runtime.Contains('legadoIsPreserveWhitespaceTag') -and $runtime.Contains('legadoTrimJavaWhitespace')) 'ArkWeb helper contract is incomplete.'
  $assertions.Add('ArkWeb whitespace policy')
  Assert-Contract ($runtime.Contains('? legadoOwnText(node)') -and $runtime.Contains(': legadoText(node);')) 'ArkWeb pseudo predicates do not use normalized descendant/direct projections.'
  $assertions.Add('ArkWeb pseudo projections')
  Assert-Contract ($runtime.Contains("if (attr === 'text') return legadoText(node);") -and $runtime.Contains('text: function () { return node ? legadoText(node) :')) 'ArkWeb java element text handoff is not normalized.'
  $assertions.Add('ArkWeb java text handoff')
  Assert-Contract ($legadoAnalyze.Contains('val text = element.text()') -and $legadoAnalyze.Contains('val text = element.ownText()') -and $legadoExtensions.Contains('StringUtil.appendNormalisedWhitespace')) 'fixed Legado reference markers are missing.'
  $assertions.Add('Legado reference markers')

  $sourceHashes = [ordered]@{}
  foreach ($path in @(
    'entry/src/main/ets/libs/htmlparser/LegadoTextNormalization.ets',
    'entry/src/main/ets/libs/htmlparser/HTMLElement.ets',
    'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
    'entry/src/main/resources/rawfile/legado_runtime.html'
  )) {
    $sourceHashes[$path] = (Get-FileHash -LiteralPath (Get-RepoPath -RelativePath $path) -Algorithm SHA256).Hash.ToUpperInvariant()
  }

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_jsoup_text_whitespace_static_contract'
    issueId = 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
    status = 'passed'
    assertions = $assertions.Count
    fixture = $FixturePath
    preFixEvidence = $PreFixEvidencePath
    consumerEvidence = $ConsumerEvidencePath
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    verification = 'static_source_contract_only;runtime_regression_deferred'
    baseline = [pscustomobject][ordered]@{
      sourceCount = [int]$state.baseline.sourceCount
      sourcePackageSha256 = [string]$state.baseline.sourcePackageSha256
      legadoCommit = [string]$state.baseline.legadoCommit
    }
    consumerPaths = @('DOM.Matcher/HTMLElement', 'large-document string fallback', 'ArkWeb runtime', 'standard JSVM handoff')
    currentHeadHashes = $sourceHashes
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_jsoup_text_whitespace_static_contract'
    issueId = 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    error = $_.Exception.Message
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verification = 'static_source_contract_only;runtime_regression_deferred'
  }
}

Write-AtomicJson -Path $ResultPath -Value $result
$result | ConvertTo-Json -Compress
if ([string]$result.status -ne 'passed') { exit 1 }
