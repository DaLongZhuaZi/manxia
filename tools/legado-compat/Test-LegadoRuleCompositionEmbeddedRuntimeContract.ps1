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
  $OutputPath = Join-Path $PSScriptRoot 'evidence\legado-rule-composition-embedded-runtime-contract-20260807.json'
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
    throw "Legado embedded composition contract failed: $Message"
  }
}

$enginePath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoJsEngine.ets'
$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-rule-composition-embedded-runtime.json'
$engine = Read-Utf8Text -Path $enginePath
$fixture = (Read-Utf8Text -Path $fixturePath) | ConvertFrom-Json

Assert-Contract ($fixture.contract -eq 'legado_rule_composition_embedded_runtime') 'fixture contract id changed'
Assert-Contract ($fixture.cases.Count -eq 4) 'fixture must retain four embedded composition witnesses'
Assert-Contract (@($fixture.requiredPaths | Where-Object { $_ -eq 'buildScript' }).Count -eq 1) 'standard path witness missing'
Assert-Contract (@($fixture.requiredPaths | Where-Object { $_ -eq 'buildNativeScript' }).Count -eq 1) 'native path witness missing'

$standardBuilder = $engine.IndexOf('private buildScript(', [System.StringComparison]::Ordinal)
$nativeBuilder = $engine.IndexOf('private buildNativeScript(', [System.StringComparison]::Ordinal)
$standardStart = $engine.IndexOf('var __splitRuleCombinators = function', $standardBuilder, [System.StringComparison]::Ordinal)
$nativeStart = $engine.IndexOf('var __nativeSplitRuleCombinators = function', $nativeBuilder, [System.StringComparison]::Ordinal)
Assert-Contract ($standardBuilder -ge 0 -and $nativeBuilder -gt $standardBuilder) 'runtime builder boundaries are missing'
Assert-Contract ($standardStart -ge 0) 'standard JSVM combinator helper is missing'
Assert-Contract ($nativeStart -ge 0) 'Native JSVM combinator helper is missing'

$standardRuntime = $engine.Substring($standardBuilder, $nativeBuilder - $standardBuilder)
$nativeRuntime = $engine.Substring($nativeBuilder)

Assert-Contract ($standardRuntime.Contains("__splitRuleCombinators(normalizedRule, ['&&', '||'])")) 'standard getString must exclude %%'
Assert-Contract ($standardRuntime.Contains("__splitRuleCombinators(normalizedRule, ['&&', '||', '%%'])")) 'standard getStringList must allow %%'
Assert-Contract ($nativeRuntime.Contains("__nativeSplitRuleCombinators(normalizedRule, ['&&', '||'])")) 'native getString must exclude %%'
Assert-Contract ($nativeRuntime.Contains("__nativeSplitRuleCombinators(normalizedRule, ['&&', '||', '%%'])")) 'native getStringList must allow %%'
Assert-Contract ($standardRuntime.Contains('skipComposition') -and $nativeRuntime.Contains('skipComposition')) 'embedded helpers must avoid recursive re-splitting'
Assert-Contract ($standardRuntime.Contains("split.splitType === '%%'") -and $nativeRuntime.Contains("composition.splitType === '%%'")) 'embedded list helper must implement %% interleave'
Assert-Contract ($standardRuntime.Contains("split.splitType === '||'") -and $nativeRuntime.Contains("composition.splitType === '||'")) 'embedded helpers must implement || short-circuit'
Assert-Contract ($standardRuntime.Contains('Object.keys(value)') -and $nativeRuntime.Contains('Object.keys(currentValue)')) 'embedded splitter must inspect nested object/path scopes'

$result = [ordered]@{
  schemaVersion = 1
  generatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'")
  status = 'passed'
  contract = [string]$fixture.contract
  assertions = 12
  engineSha256 = (Get-FileHash -LiteralPath $enginePath -Algorithm SHA256).Hash.ToUpperInvariant()
  fixtureSha256 = (Get-FileHash -LiteralPath $fixturePath -Algorithm SHA256).Hash.ToUpperInvariant()
  paths = @('buildScript', 'buildNativeScript')
  cases = @($fixture.cases | ForEach-Object { [string]$_.id })
  reproduction = 'pwsh -File tools/legado-compat/Test-LegadoRuleCompositionEmbeddedRuntimeContract.ps1'
}

$directory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $directory)) {
  [void][System.IO.Directory]::CreateDirectory($directory)
}
$temporaryPath = "$OutputPath.tmp-$PID"
[System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::Move($temporaryPath, $OutputPath, $true)
$result | ConvertTo-Json -Compress
