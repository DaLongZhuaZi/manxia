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
  $OutputPath = Join-Path $PSScriptRoot 'evidence\contract-legado-java-object-content-overload.json'
}

$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-java-object-content-overload.json'
$runtimePath = Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html'
$enginePath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoJsEngine.ets'
$originalAnalyzeRulePath = Join-Path $RepositoryRoot 'legado\app\src\main\java\io\legado\app\model\analyzeRule\AnalyzeRule.kt'
$originalJsonPath = Join-Path $RepositoryRoot 'legado\app\src\main\java\io\legado\app\model\analyzeRule\AnalyzeByJSonPath.kt'

foreach ($path in @($fixturePath, $runtimePath, $enginePath, $originalAnalyzeRulePath, $originalJsonPath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Required object-content contract input is missing: $path"
  }
}

$fixture = Get-Content -LiteralPath $fixturePath -Raw -Encoding UTF8 | ConvertFrom-Json
$runtime = Get-Content -LiteralPath $runtimePath -Raw -Encoding UTF8
$engine = Get-Content -LiteralPath $enginePath -Raw -Encoding UTF8
$originalAnalyzeRule = Get-Content -LiteralPath $originalAnalyzeRulePath -Raw -Encoding UTF8
$originalJsonPathText = Get-Content -LiteralPath $originalJsonPath -Raw -Encoding UTF8

$assertions = 0
$failures = New-Object 'System.Collections.Generic.List[string]'
function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  $script:assertions++
  if (-not $Condition) { [void]$script:failures.Add($Message) }
}

Assert-Contract ([string]$fixture.contract -eq 'legado_java_object_content_overload') 'fixture contract identifier must be stable'
Assert-Contract ([int]$fixture.baselineSourceCount -eq 458) 'fixture must stay bound to 458-source baseline'
Assert-Contract ([string]$fixture.baselineSourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'fixture source hash must match pinned package'
Assert-Contract (@($fixture.cases).Count -ge 9) 'fixture must cover scalar, falsy, list, replacement, replace-first, missing and JSONPath cases'
Assert-Contract (@($fixture.cases | Where-Object { [string]$_.id -eq 'replace-first-after-object-lookup' }).Count -eq 1) 'fixture must include a fourth ## segment for replace-first semantics'

# The reference path is the actual NativeObject branch in AnalyzeRule. It must
# remain visible in the contract so this cannot silently become a CSS-only shim.
Assert-Contract ($originalAnalyzeRule.Contains('result is NativeObject')) 'Legado AnalyzeRule must retain the NativeObject mContent branch'
Assert-Contract ($originalAnalyzeRule.Contains('result[sourceRule.rule]?.toString()')) 'Legado getString must read a NativeObject property by rule key'
Assert-Contract ($originalAnalyzeRule.Contains('result[sourceRule.rule]')) 'Legado getStringList must read a NativeObject property by rule key'
Assert-Contract ($originalJsonPathText.Contains('ruleAnalyzes.innerRule("{$.")')) 'Legado JSONPath path must remain available for non-object JSON rules'

Assert-Contract ($runtime.Contains('legadoGetObjectContentValue')) 'ArkWeb runtime must have a typed object-content lookup helper'
Assert-Contract ($runtime.Contains('legadoGetObjectContentList')) 'ArkWeb runtime must have an object-content list projection helper'
Assert-Contract ($runtime.Contains('legadoGetObjectContentValue(rule, content)')) 'ArkWeb getString must check object mContent before CSS string coercion and preserve ## replacement'
Assert-Contract ($runtime.Contains('legadoGetObjectContentList(rule, content)')) 'ArkWeb getStringList must check object mContent before CSS string coercion and preserve ## replacement'
Assert-Contract ($runtime.Contains('Object.prototype.hasOwnProperty.call(content, key)')) 'object lookup must preserve falsy values and distinguish missing keys'

Assert-Contract ($engine.Contains('__getObjectContentValue')) 'ArkTS JS runtime must have a typed object-content lookup helper'
Assert-Contract ($engine.Contains('__nativeGetObjectContentValue')) 'ArkTS native JS runtime must have a typed object-content lookup helper'
Assert-Contract ($engine.Contains('__getObjectContentValue(rule, contentValue)')) 'ArkTS JS getString path must consume object mContent'
Assert-Contract ($engine.Contains('__nativeGetObjectContentValue(rule, contentValue)')) 'ArkTS native getString path must consume object mContent'
Assert-Contract ($engine.Contains('__getObjectContentList')) 'ArkTS JS runtime must project object list values'
Assert-Contract ($engine.Contains('__nativeGetObjectContentList')) 'ArkTS native JS runtime must project object list values'

$runtimeHash = (Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash.ToUpperInvariant()
$engineHash = (Get-FileHash -LiteralPath $enginePath -Algorithm SHA256).Hash.ToUpperInvariant()
$fixtureHash = (Get-FileHash -LiteralPath $fixturePath -Algorithm SHA256).Hash.ToUpperInvariant()
$result = [ordered]@{
  schemaVersion = 1
  generatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'")
  status = if ($failures.Count -eq 0) { 'passed' } else { 'failed' }
  contract = [string]$fixture.contract
  assertions = $assertions
  failedAssertions = $failures.ToArray()
  fixtureSha256 = $fixtureHash
  runtimeSha256 = $runtimeHash
  engineSha256 = $engineHash
  fixture = 'tools/legado-compat/fixtures/legado-java-object-content-overload.json'
  originalImplementation = @(
    'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeRule.kt',
    'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSonPath.kt'
  )
  v2Implementation = @(
    'entry/src/main/resources/rawfile/legado_runtime.html',
    'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets'
  )
  reproduction = 'pwsh -NoProfile -File tools/legado-compat/Test-LegadoJavaObjectContentOverloadContract.ps1'
}
$directory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
$temporaryPath = "$OutputPath.tmp-$PID"
[System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::Move($temporaryPath, $OutputPath, $true)
$result | ConvertTo-Json -Compress
if ($failures.Count -gt 0) {
  throw ('Legado Java object-content overload contract failed: ' + ([string]::Join('; ', $failures.ToArray())))
}
