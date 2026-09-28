[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-rule-composition-pre-fix-20260808.json'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:assertions = 0

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "Legado rule composition pre-fix contract failed: $Message"
  }
  $script:assertions++
}

function Read-StrictJson {
  param([string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  Assert-Contract (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) ("UTF-8 BOM is not allowed: {0}" -f $Path)
  try {
    return ($strictUtf8.GetString($bytes) | ConvertFrom-Json)
  } catch {
    throw "invalid JSON: $Path; $($_.Exception.Message)"
  }
}

function Write-AtomicJson {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$Path.tmp-$PID"
  [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Get-GitText {
  param([string]$Path)
  $text = & git -C $RepositoryRoot show ("HEAD:{0}" -f $Path) 2>$null | Out-String
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($text)) {
    throw "frozen V2 source is missing from git HEAD: $Path"
  }
  return $text
}

$result = $null
try {
  $statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
  $fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-rule-composition-mixed.json'
  $state = Read-StrictJson -Path $statePath
  $fixture = Read-StrictJson -Path $fixturePath
  $baseline = $state.baseline
  Assert-Contract ([int]$baseline.sourceCount -eq 458) 'machine baseline source count is not 458.'
  Assert-Contract ([string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'machine source package hash drifted.'
  Assert-Contract ([string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine Legado commit drifted.'
  $analyzer = Get-GitText -Path 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
  $runtime = Get-GitText -Path 'entry/src/main/resources/rawfile/legado_runtime.html'
  $engine = Get-GitText -Path 'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets'
  Assert-Contract ($analyzer.Contains('按优先级检查分割符: %%, ||, &&')) 'frozen V2 baseline no longer contains the fixed-priority implementation marker.'
  Assert-Contract ($analyzer.Contains('private splitRuleStr(ruleStr: string): RuleSplitResult')) 'frozen V2 baseline split signature is not the pre-fix signature.'
  Assert-Contract (-not $analyzer.Contains('findFirstTopLevelSplitter')) 'frozen V2 baseline unexpectedly contains the first-operator fix.'
  Assert-Contract (-not $runtime.Contains('legadoJsonPathSplitCombinators')) 'frozen ArkWeb baseline unexpectedly contains the composition bridge fix.'
  Assert-Contract (-not $engine.Contains('__splitRuleCombinators')) 'frozen JSVM baseline unexpectedly contains the embedded composition fix.'

  $cases = @($fixture.cases)
  Assert-Contract ($cases.Count -eq 5) 'mixed composition fixture must contain five counterexamples.'
  $priorityMismatchCases = @($cases | Where-Object { [string]$_.firstOperator -in @('&&', '||') })
  Assert-Contract ($priorityMismatchCases.Count -eq 4) 'fixture must retain four first-operator witnesses.'
  $percentCase = @($cases | Where-Object { [string]$_.id -eq 'get-string-does-not-consume-percent-merge' })[0]
  Assert-Contract ($null -ne $percentCase -and @($percentCase.allowedFor) -contains 'getStringList' -and @($percentCase.allowedFor) -notcontains 'getString') 'getString %% exclusion witness is missing.'

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_rule_composition_pre_fix_contract'
    issueId = 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    classification = 'historical_v2_fixed_priority_semantics'
    baseline = [pscustomobject][ordered]@{
      sourceCount = [int]$baseline.sourceCount
      sourcePackageSha256 = [string]$baseline.sourcePackageSha256
      legadoCommit = [string]$baseline.legadoCommit
      v2SourceRevision = 'git HEAD'
    }
    rootCause = 'Frozen V2 splitRuleStr checks %% then || then && and lets getString consume the default %% path; Legado chooses the first top-level operator and limits getString to &&/||.'
    failingCases = @($priorityMismatchCases | ForEach-Object { [string]$_.id }) + @('get-string-does-not-consume-percent-merge')
    fixture = 'tools/legado-compat/fixtures/legado-rule-composition-mixed.json'
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_rule_composition_pre_fix_contract_only;source_fix_and_runtime_regression_deferred'
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_rule_composition_pre_fix_contract'
    issueId = 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR'
    status = 'contract_error'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    error = $_.Exception.Message
    assertions = $script:assertions
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_rule_composition_pre_fix_contract_only;source_fix_and_runtime_regression_deferred'
  }
}

Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Compress
if ([string]$result.status -ne 'failed') { exit 1 }
