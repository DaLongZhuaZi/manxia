[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = '',
  [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
if ([string]::IsNullOrWhiteSpace($FixturePath)) {
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-java-string-list-css-replacement-order.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-java-string-list-css-replacement-order-20260808.json'
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Legado CSS replacement-order contract failed: $Message" }
}

function Read-Utf8Text {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) "missing file: $Path"
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

$result = $null
try {
  $analyzerPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoRuleAnalyzer.ets'
  $enginePath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoJsEngine.ets'
  $runtimePath = Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html'
  $fixture = (Read-Utf8Text -Path $FixturePath) | ConvertFrom-Json
  $analyzer = Read-Utf8Text -Path $analyzerPath
  $engine = Read-Utf8Text -Path $enginePath
  $runtime = Read-Utf8Text -Path $runtimePath

  Assert-Contract (@($fixture.cases).Count -eq 4) 'fixture must contain four replacement-order cases.'
  Assert-Contract (@($fixture.cases | Where-Object { [bool]$_.replaceFirst }).Count -eq 2) 'fixture must contain two replace-first cases.'
  Assert-Contract ($analyzer.Contains("replacement.endsWith('##')")) 'Analyzer must use the trailing double-delimiter marker used by Legado.'
  Assert-Contract (-not $analyzer.Contains("replacement.endsWith('#')")) 'Analyzer must not treat a literal trailing single # as replace-first.'
  Assert-Contract ($analyzer.Contains('const replacementParts = this.splitReplaceRule(processedRule);')) 'getString/getStringList must split replacement before composition.'
  Assert-Contract ($analyzer.Contains('replacementParts.rule')) 'Analyzer must compose the rule without its replacement suffix.'
  Assert-Contract ($analyzer.Contains('applyReplaceToList')) 'Analyzer must apply replacement to the merged list, not each split operand.'
  Assert-Contract ($analyzer.Contains('applyReplaceToString')) 'Analyzer must apply replacement to the merged string result.'
  $jsNewline = [string][char]92 + 'n'
  Assert-Contract ($engine.Contains([string]::Concat("return __applyRuleReplacement(textList.join('", $jsNewline, "'), replacement);"))) 'standard JSVM getString must replace after composition.'
  Assert-Contract ($engine.Contains([string]::Concat("return __nativeApplyRuleReplacement(textList.join('", $jsNewline, "'), replacement);"))) 'Native JSVM getString must replace after composition.'
  Assert-Contract ($engine.Contains('var replacement = __splitRuleReplacement(rule);')) 'standard JSVM must parse replacement at the outer rule boundary.'
  Assert-Contract ($engine.Contains('var replacement = __nativeSplitRuleReplacement(rule);')) 'Native JSVM must parse replacement at the outer rule boundary.'
  Assert-Contract ($runtime.Contains("replaceFirst: pieces.length > 0")) 'ArkWeb runtime must use the extra split field as replace-first marker.'
  Assert-Contract ($runtime.Contains([string]::Concat("return values.length > 0 ? values.join('", $jsNewline, "') : '';"))) 'ArkWeb runtime getString must consume the replaced merged list.'

  $result = [pscustomobject][ordered]@{
    status = 'passed'
    contract = 'legado_java_string_list_css_replacement_order'
    assertions = 14
    fixture = [System.IO.Path]::GetRelativePath($RepositoryRoot, $FixturePath).Replace('\\', '/')
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    verification = 'static_source_contract_only;runtime_regression_deferred'
    semanticMatchAllowed = $false
  }
} catch {
  $result = [pscustomobject][ordered]@{
    status = 'failed'
    contract = 'legado_java_string_list_css_replacement_order'
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    semanticMatchAllowed = $false
  }
}

$directory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
[System.IO.File]::WriteAllText($ResultPath, [string]($result | ConvertTo-Json -Depth 10), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') { exit 1 }
