[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if ([string]::IsNullOrWhiteSpace($FixturePath)) {
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-java-string-list-css-composition.json'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-java-string-list-css-composition-pre-fix-20260808.json'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:assertions = 0

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "Legado java.getStringList CSS pre-fix contract failed: $Message"
  }
  $script:assertions++
}

function Read-StrictJson {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) ("missing fixture: {0}" -f $Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  Assert-Contract (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) ("UTF-8 BOM is not allowed: {0}" -f $Path)
  try {
    return ($strictUtf8.GetString($bytes) | ConvertFrom-Json)
  } catch {
    throw "invalid JSON: $Path; $($_.Exception.Message)"
  }
}

function Read-GitHeadText {
  param([string]$RelativePath)
  $text = (& git -C $RepositoryRoot show ("HEAD:{0}" -f $RelativePath) 2>$null | Out-String)
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($text)) {
    throw "frozen source is missing from git HEAD: $RelativePath"
  }
  return $text
}

function Write-AtomicJson {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$Path.tmp-$PID"
  [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 24), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

$result = $null
$exitCode = 1
try {
  $statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
  $state = Read-StrictJson -Path $statePath
  $fixture = Read-StrictJson -Path $FixturePath
  $baseline = $state.baseline
  Assert-Contract ([int]$baseline.sourceCount -eq 458) 'machine baseline source count is not 458.'
  Assert-Contract ([string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'machine source package hash drifted.'
  Assert-Contract ([string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine Legado commit drifted.'
  Assert-Contract ([string]$fixture.contract -eq 'legado_java_string_list_css_composition') 'fixture contract id changed.'
  $cases = @($fixture.cases)
  Assert-Contract ($cases.Count -eq 5) 'fixture must retain five CSS/List witnesses.'
  Assert-Contract (@($cases | Where-Object { [string]$_.firstOperator -eq '||' }).Count -eq 1) 'fixture must retain CSS || witness.'
  Assert-Contract (@($cases | Where-Object { [string]$_.firstOperator -eq '&&' }).Count -eq 1) 'fixture must retain CSS && witness.'
  Assert-Contract (@($cases | Where-Object { [string]$_.firstOperator -eq '%%' }).Count -eq 1) 'fixture must retain CSS %% witness.'
  Assert-Contract (@($cases | Where-Object { [string]$_.rule -like '@css:*' }).Count -eq 1) 'fixture must retain @CSS witness.'
  Assert-Contract (@($cases | Where-Object { [string]$_.rule -like '*##*' }).Count -eq 1) 'fixture must retain ## replacement witness.'

  $runtime = Read-GitHeadText -RelativePath 'entry/src/main/resources/rawfile/legado_runtime.html'
  $engine = Read-GitHeadText -RelativePath 'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets'

  # The frozen runtime had only one-selector extraction. These missing helpers
  # are the stable source-level witness for the independent 233 root cause.
  Assert-Contract (-not $runtime.Contains('legadoNormalizeCssRule')) 'frozen ArkWeb runtime unexpectedly contains @CSS normalization.'
  Assert-Contract (-not $runtime.Contains('legadoJsonPathSplitCombinators')) 'frozen ArkWeb runtime unexpectedly contains recursive CSS composition.'
  Assert-Contract (-not $runtime.Contains('legadoCreateJavaList')) 'frozen ArkWeb runtime unexpectedly contains Java List projection.'
  Assert-Contract (-not $engine.Contains('__splitRuleCombinators')) 'frozen standard JSVM unexpectedly contains CSS composition splitter.'
  Assert-Contract (-not $engine.Contains('__nativeSplitRuleCombinators')) 'frozen Native JSVM unexpectedly contains CSS composition splitter.'
  Assert-Contract (-not $engine.Contains('__nativeCreateJavaList')) 'frozen Native JSVM unexpectedly contains Java List projection.'
  Assert-Contract ($engine.Contains('__getStringListFromContent') -and $engine.Contains('__nativeGetStringListFromContent')) 'frozen embedded paths must expose the single-selector baseline being replaced.'

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_java_string_list_css_composition_pre_fix_contract'
    issueId = 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    classification = 'historical_v2_missing_css_composition_and_java_list'
    baseline = [pscustomobject][ordered]@{
      sourceCount = [int]$baseline.sourceCount
      sourcePackageSha256 = [string]$baseline.sourcePackageSha256
      legadoCommit = [string]$baseline.legadoCommit
      v2SourceRevision = 'git HEAD'
    }
    rootCause = 'Frozen ArkWeb and embedded JSVM paths only extracted one CSS selector and returned plain arrays; they lacked Legado first-operator recursive &&/||/%% composition, @CSS normalization, post-composition ## replacement and Java List-compatible projection.'
    failingCases = @($cases | ForEach-Object { [string]$_.id })
    fixture = 'tools/legado-compat/fixtures/legado-java-string-list-css-composition.json'
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_java_string_list_css_pre_fix_contract_only;source_fix_and_runtime_regression_deferred'
    assertions = $script:assertions
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_java_string_list_css_composition_pre_fix_contract'
    issueId = 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION'
    status = 'contract_error'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    error = $_.Exception.Message
    assertions = $script:assertions
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_java_string_list_css_pre_fix_contract_only;source_fix_and_runtime_regression_deferred'
  }
  $exitCode = 1
}

Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Compress
exit $exitCode
