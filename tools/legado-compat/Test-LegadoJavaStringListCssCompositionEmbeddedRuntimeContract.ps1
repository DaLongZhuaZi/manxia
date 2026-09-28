[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $PSScriptRoot 'evidence\legado-java-string-list-css-composition-embedded-runtime-contract-20260807.json'
}

function Read-Utf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

function Assert-Contract {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Message
  )
  if (-not $Condition) {
    throw "Legado embedded CSS List contract failed: $Message"
  }
}

$enginePath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoJsEngine.ets'
$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-java-string-list-css-composition-embedded-runtime.json'
$engine = Read-Utf8Text -Path $enginePath
$fixture = (Read-Utf8Text -Path $fixturePath) | ConvertFrom-Json

Assert-Contract ($fixture.contract -eq 'legado_java_string_list_css_composition_embedded_runtime') 'fixture contract id changed'
Assert-Contract ($fixture.cases.Count -eq 5) 'fixture must retain five CSS/List witnesses'
Assert-Contract (@($fixture.requiredPaths | Where-Object { $_ -eq 'buildScript' }).Count -eq 1) 'standard path witness missing'
Assert-Contract (@($fixture.requiredPaths | Where-Object { $_ -eq 'buildNativeScript' }).Count -eq 1) 'native path witness missing'

$standardBuilder = $engine.IndexOf('private buildScript(', [System.StringComparison]::Ordinal)
$nativeBuilder = $engine.IndexOf('private buildNativeScript(', [System.StringComparison]::Ordinal)
$standardStart = $engine.IndexOf('var __getStringListFromContent = function', $standardBuilder, [System.StringComparison]::Ordinal)
$standardEnd = $engine.IndexOf('var __getStringListFromCurrentResult = function', $standardStart, [System.StringComparison]::Ordinal)
$nativeStart = $engine.IndexOf('var __nativeGetStringListFromContent = function', $nativeBuilder, [System.StringComparison]::Ordinal)
$nativeEnd = $engine.IndexOf('var __nativeGetStringListFromCurrentResult = function', $nativeStart, [System.StringComparison]::Ordinal)
Assert-Contract ($standardBuilder -ge 0 -and $nativeBuilder -gt $standardBuilder) 'runtime builder boundaries missing'
Assert-Contract ($standardStart -ge 0 -and $standardEnd -gt $standardStart) 'standard CSS List helper boundaries missing'
Assert-Contract ($nativeStart -ge 0 -and $nativeEnd -gt $nativeStart) 'native CSS List helper boundaries missing'

$standardBody = $engine.Substring($standardStart, $standardEnd - $standardStart)
$nativeBody = $engine.Substring($nativeStart, $nativeEnd - $nativeStart)
$standardRuntime = $engine.Substring($standardBuilder, $nativeBuilder - $standardBuilder)
$nativeRuntime = $engine.Substring($nativeBuilder)

Assert-Contract ($standardBody.Contains("__splitRuleCombinators(normalizedRule, ['&&', '||', '%%'])")) 'standard List helper must preserve all CSS combinators'
Assert-Contract ($nativeBody.Contains("__nativeSplitRuleCombinators(normalizedRule, ['&&', '||', '%%'])")) 'native List helper must preserve all CSS combinators'
Assert-Contract ($standardBody.Contains('skipComposition') -and $nativeBody.Contains('skipComposition')) 'recursive List helpers must not split the same expression twice'
Assert-Contract ($standardBody.Contains('__applyRuleReplacement')) 'standard List helper must apply ## replacement after extraction'
Assert-Contract ($nativeBody.Contains('__nativeApplyRuleReplacement')) 'native List helper must apply ## replacement after extraction'
Assert-Contract ($standardBody.Contains('return merged.map(function(value) { return __applyRuleReplacement(value, replacement); });')) 'standard composition must apply ## replacement after merge'
Assert-Contract ($nativeBody.Contains('return merged.map(function(value) { return __nativeApplyRuleReplacement(value, replacement); });')) 'native composition must apply ## replacement after merge'
Assert-Contract ($standardRuntime.Contains('__normalizeCssRule')) 'standard List helper must normalize @CSS'
Assert-Contract ($nativeRuntime.Contains('__nativeNormalizeCssRule')) 'native List helper must normalize @CSS'

$standardListApi = $engine.Substring($engine.IndexOf('getStringList: function(rule, content)', $standardStart, [System.StringComparison]::Ordinal), 380)
$nativeListApi = $engine.Substring($engine.IndexOf('getStringList: function(rule, content)', $nativeStart, [System.StringComparison]::Ordinal), 430)
Assert-Contract ($standardListApi.Contains('__createJavaList')) 'standard java.getStringList must expose Java List methods'
Assert-Contract ($nativeListApi.Contains('__nativeCreateJavaList')) 'native java.getStringList must expose Java List methods'

$result = [ordered]@{
  schemaVersion = 1
  generatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'")
  status = 'passed'
  contract = [string]$fixture.contract
  assertions = 19
  engineSha256 = (Get-FileHash -LiteralPath $enginePath -Algorithm SHA256).Hash.ToUpperInvariant()
  fixtureSha256 = (Get-FileHash -LiteralPath $fixturePath -Algorithm SHA256).Hash.ToUpperInvariant()
  paths = @('buildScript', 'buildNativeScript')
  cases = @($fixture.cases | ForEach-Object { [string]$_.id })
  verification = 'static_source_contract_only;runtime_regression_deferred'
  reproduction = 'pwsh -File tools/legado-compat/Test-LegadoJavaStringListCssCompositionEmbeddedRuntimeContract.ps1'
}

$directory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $directory)) {
  [void][System.IO.Directory]::CreateDirectory($directory)
}
$temporaryPath = "$OutputPath.tmp-$PID"
[System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::Move($temporaryPath, $OutputPath, $true)
$result | ConvertTo-Json -Compress
