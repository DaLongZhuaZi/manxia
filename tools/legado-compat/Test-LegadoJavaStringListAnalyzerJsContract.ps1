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
  $OutputPath = Join-Path $PSScriptRoot 'evidence\v2-java-string-list-analyzer-js-contract-20260808.json'
}

function Read-Utf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

$script:AssertionCount = 0
$script:FailedAssertion = ''

function Assert-Contract {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Message
  )
  $script:AssertionCount++
  if (-not $Condition) {
    $script:FailedAssertion = $Message
    throw "Legado Java List Analyzer JS contract failed: $Message"
  }
}

$analyzerPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoRuleAnalyzer.ets'
$enginePath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoJsEngine.ets'
$runtimePath = Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html'
$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-java-string-list-analyzer-js.json'

$result = [ordered]@{
  schemaVersion = 1
  generatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'")
  issueId = 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS'
  status = 'failed'
  verification = 'static_source_contract_only;runtime_regression_deferred'
  assertions = 0
  failedAssertion = ''
  engineSha256 = ''
  analyzerSha256 = ''
  runtimeSha256 = ''
  fixtureSha256 = ''
}

try {
  $analyzer = Read-Utf8Text -Path $analyzerPath
  $engine = Read-Utf8Text -Path $enginePath
  $runtime = Read-Utf8Text -Path $runtimePath
  $fixture = (Read-Utf8Text -Path $fixturePath) | ConvertFrom-Json

  Assert-Contract ($fixture.contract -eq 'legado_java_string_list_analyzer_js') 'fixture contract id changed'
  Assert-Contract (@($fixture.cases).Count -eq 6) 'fixture must retain six semantic witnesses'
  Assert-Contract (@($fixture.requiredPaths).Count -eq 6) 'fixture required path matrix changed'

  $elementsStart = $analyzer.IndexOf('async getElementsAsync(', [System.StringComparison]::Ordinal)
  $singleStart = $analyzer.IndexOf('private async getElementsSingleAsync(', [System.StringComparison]::Ordinal)
  $executeStart = $analyzer.IndexOf('private async executeJavaScriptElementsAsync(', [System.StringComparison]::Ordinal)
  $executeEnd = $analyzer.IndexOf('private async getElementsFromJsonFirstRuleChainAsync(', $executeStart, [System.StringComparison]::Ordinal)
  Assert-Contract ($elementsStart -ge 0 -and $singleStart -gt $elementsStart -and $executeStart -gt $singleStart -and $executeEnd -gt $executeStart) 'Analyzer method boundaries missing'

  $elementsBody = $analyzer.Substring($elementsStart, $singleStart - $elementsStart)
  $singleBody = $analyzer.Substring($singleStart, $executeStart - $singleStart)
  $executeBody = $analyzer.Substring($executeStart, $executeEnd - $executeStart)
  $standaloneIndex = $elementsBody.IndexOf('isStandaloneJavaScriptRule(processedRule)', [System.StringComparison]::Ordinal)
  $splitIndex = $elementsBody.IndexOf("safeSplit(processedRule, '||')", [System.StringComparison]::Ordinal)
  Assert-Contract ($standaloneIndex -ge 0 -and $splitIndex -gt $standaloneIndex) 'standalone JS must bypass generic || splitting'
  Assert-Contract ($singleBody.Contains('executeJavaScriptElementsAsync(standaloneRule.rule')) 'standalone JS element entry must use the JS list executor'
  Assert-Contract ($singleBody.Contains('executeJavaScriptElementsAsync(parsedRule.rule')) 'Mode.Js element entry must use the JS list executor'

  Assert-Contract ($executeBody.Contains("this.lastJsExecutionStatus = 'not_evaluated';")) 'JS list execution must reset status before evaluation'
  Assert-Contract ($executeBody.Contains('this.lastJsExecutionStatus = this.toSafeJsExecutionStatus(executeResult.error);')) 'JS list execution failures must publish a classified status'
  Assert-Contract ($executeBody.Contains("this.lastJsExecutionStatus = parsedArray.length > 0 ? 'result' : 'empty';")) 'array projection must distinguish non-empty and empty lists'
  Assert-Contract ($executeBody.Contains("this.lastJsExecutionStatus = 'error_js_result_not_list';")) 'scalar JS results must be rejected as a typed list mismatch'
  Assert-Contract ($executeBody.Contains('const rawJsResult: string = executeResult.result.trim();')) 'JS list projection must inspect the raw execution result before fallback'
  Assert-Contract (-not $executeBody.Contains(': (context.result || this.content);')) 'empty JS results must not silently fall back to page content'
  Assert-Contract ($executeBody.Contains('Array.isArray(parsed)')) 'JS list projection must require an array result'
  Assert-Contract ($executeBody.Contains('JSON.stringify(item)')) 'object list elements must retain JSON object shape'

  $standardList = $engine.IndexOf('getStringList: function(rule, content)', [System.StringComparison]::Ordinal)
  $nativeBuilder = $engine.IndexOf('private buildNativeScript(', [System.StringComparison]::Ordinal)
  $nativeList = $engine.IndexOf('getStringList: function(rule, content)', $nativeBuilder, [System.StringComparison]::Ordinal)
  Assert-Contract ($standardList -ge 0 -and $nativeList -gt $nativeBuilder) 'standard/native Java List API boundaries missing'
  Assert-Contract ($engine.Contains('list.get = function(index)')) 'native Java List get() bridge missing'
  Assert-Contract ($engine.Contains('list.size = function()')) 'native Java List size() bridge missing'
  Assert-Contract ($engine.Contains('list.toArray = function()')) 'native Java List toArray() bridge missing'
  Assert-Contract ($runtime.Contains("defineMethod('get'")) 'ArkWeb Java List get() bridge missing'
  Assert-Contract ($runtime.Contains("defineMethod('size'")) 'ArkWeb Java List size() bridge missing'
  Assert-Contract ($runtime.Contains("defineMethod('toArray'")) 'ArkWeb Java List toArray() bridge missing'

  $result.status = 'passed'
} catch {
  $result.failedAssertion = $script:FailedAssertion
  if ([string]::IsNullOrWhiteSpace($result.failedAssertion)) {
    $result.failedAssertion = 'contract_exception'
  }
}

$result.assertions = $script:AssertionCount
$result.engineSha256 = (Get-FileHash -LiteralPath $enginePath -Algorithm SHA256).Hash.ToUpperInvariant()
$result.analyzerSha256 = (Get-FileHash -LiteralPath $analyzerPath -Algorithm SHA256).Hash.ToUpperInvariant()
$result.runtimeSha256 = (Get-FileHash -LiteralPath $runtimePath -Algorithm SHA256).Hash.ToUpperInvariant()
$result.fixtureSha256 = (Get-FileHash -LiteralPath $fixturePath -Algorithm SHA256).Hash.ToUpperInvariant()

$directory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $directory)) {
  [void][System.IO.Directory]::CreateDirectory($directory)
}
$temporaryPath = "$OutputPath.tmp-$PID"
[System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::Move($temporaryPath, $OutputPath, $true)
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') {
  exit 1
}
