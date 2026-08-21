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
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-rule-composition-mixed.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-rule-composition-mixed.json'
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Legado rule composition contract failed: $Message" }
}

function Read-Utf8Json {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) "missing fixture: $Path"
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
}

$result = $null
try {
  $analyzerPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoRuleAnalyzer.ets'
  $runtimePath = Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html'
  $analyzer = [System.IO.File]::ReadAllText($analyzerPath, [System.Text.UTF8Encoding]::new($false, $true))
  $runtime = [System.IO.File]::ReadAllText($runtimePath, [System.Text.UTF8Encoding]::new($false, $true))
  $fixture = Read-Utf8Json -Path $FixturePath
  Assert-Contract ($analyzer.Contains('findFirstTopLevelSplitter')) 'splitter must choose the first top-level operator.'
  Assert-Contract ($analyzer.Contains('allowedSplitters: string[]')) 'splitter must receive the caller-specific operator set.'
  Assert-Contract ($analyzer.Contains("this.splitRuleStr(processedRule, ['&&', '||'])")) 'getString must exclude %% from its operator set.'
  Assert-Contract (-not $analyzer.Contains('按优先级检查分割符')) 'fixed operator-priority splitting must be removed.'
  Assert-Contract ($runtime.Contains('legadoJsonPathGetString') -and $runtime.Contains('legadoJsonPathGetStringList')) 'ArkWeb runtime must use recursive JSONPath composition helpers.'
  Assert-Contract ($runtime.Contains('splitType') -and -not $runtime.Contains('split.separators')) 'ArkWeb runtime must retain one selected combinator type instead of splitting every operator.'
  Assert-Contract (@($fixture.cases).Count -eq 5) 'fixture must retain all mixed-operator cases.'
  $mixedCases = @($fixture.cases | Where-Object { [string]$_.id -ne 'get-string-does-not-consume-percent-merge' })
  Assert-Contract (@($mixedCases | Where-Object { [string]$_.firstOperator -eq '&&' }).Count -eq 2) 'fixture must cover first && selection.'
  Assert-Contract (@($mixedCases | Where-Object { [string]$_.firstOperator -eq '||' }).Count -eq 2) 'fixture must cover first || selection.'
  $percentCase = @($fixture.cases | Where-Object { [string]$_.id -eq 'get-string-does-not-consume-percent-merge' })[0]
  Assert-Contract (@($percentCase.allowedFor) -contains 'getStringList') '%% case must remain a list-only composition witness.'

  $result = [pscustomobject][ordered]@{
    status = 'passed'
    contract = 'legado_rule_composition_mixed'
    assertions = 10
    fixture = [System.IO.Path]::GetRelativePath($RepositoryRoot, $FixturePath).Replace('\\', '/')
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    verification = 'static_source_contract_only;runtime_regression_deferred'
  }
} catch {
  $result = [pscustomobject][ordered]@{
    status = 'failed'
    contract = 'legado_rule_composition_mixed'
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
}

$directory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
[System.IO.File]::WriteAllText($ResultPath, [string]($result | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') { exit 1 }
