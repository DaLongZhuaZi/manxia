[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = '',
  [ValidateSet('ISSUE-COMPAT-012', 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR')]
  [string]$ExpectedActiveIssueId = 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-rule-composition-current-head-audit-20260808-r1.json'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:assertions = 0

function Assert-Audit {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "Legado rule composition current-head audit failed: $Message"
  }
  $script:assertions++
}

function Read-StrictText {
  param([string]$Path)
  Assert-Audit (Test-Path -LiteralPath $Path -PathType Leaf) ("missing file: {0}" -f $Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  Assert-Audit (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) ("UTF-8 BOM is not allowed: {0}" -f $Path)
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([string]$Path)
  try {
    return (Read-StrictText -Path $Path) | ConvertFrom-Json
  } catch {
    throw "invalid JSON: $Path; $($_.Exception.Message)"
  }
}

function Get-Sha256 {
  param([string]$Path)
  Assert-Audit (Test-Path -LiteralPath $Path -PathType Leaf) ("missing hash input: {0}" -f $Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-RelativePath {
  param([string]$Path)
  return [System.IO.Path]::GetRelativePath($RepositoryRoot, $Path).Replace('\', '/')
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
try {
  $statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
  $sourceFixPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-rule-composition-first-operator-source-fix-20260807.json'
  $contractPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-rule-composition-mixed.json'
  $embeddedContractPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\legado-rule-composition-embedded-runtime-contract-20260807.json'
  $analyzerPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoRuleAnalyzer.ets'
  $enginePath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoJsEngine.ets'
  $runtimePath = Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html'
  $mixedFixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-rule-composition-mixed.json'
  $embeddedFixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-rule-composition-embedded-runtime.json'
  $legadoPaths = @(
    (Join-Path $RepositoryRoot 'legado\app\src\main\java\io\legado\app\model\analyzeRule\RuleAnalyzer.kt'),
    (Join-Path $RepositoryRoot 'legado\app\src\main\java\io\legado\app\model\analyzeRule\AnalyzeRule.kt'),
    (Join-Path $RepositoryRoot 'legado\app\src\main\java\io\legado\app\model\analyzeRule\AnalyzeByJSonPath.kt'),
    (Join-Path $RepositoryRoot 'legado\app\src\main\java\io\legado\app\model\analyzeRule\AnalyzeByJSoup.kt')
  )

  $state = Read-StrictJson -Path $statePath
  $sourceFix = Read-StrictJson -Path $sourceFixPath
  $contract = Read-StrictJson -Path $contractPath
  $embeddedContract = Read-StrictJson -Path $embeddedContractPath
  $baseline = $state.baseline
  Assert-Audit ([int]$baseline.sourceCount -eq 458) 'machine baseline source count is not 458.'
  Assert-Audit ([string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'machine source package hash drifted.'
  Assert-Audit ([string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine Legado commit drifted.'
  $packagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
  Assert-Audit ((Get-Sha256 -Path $packagePath) -eq [string]$baseline.sourcePackageSha256) 'frozen source package hash drifted.'
  $legadoCommit = (& git -C (Join-Path $RepositoryRoot 'legado') rev-parse HEAD 2>$null | Out-String).Trim()
  Assert-Audit ($legadoCommit -eq [string]$baseline.legadoCommit) 'Legado checkout is not at the frozen commit.'

  $issue = @($state.governance.issues | Where-Object { [string]$_.id -eq 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR' })[0]
  Assert-Audit ($null -ne $issue -and [string]$issue.status -eq 'verifying') '232 must remain verifying pending R4.'
  Assert-Audit ([string]$state.governance.activeIssueId -eq $ExpectedActiveIssueId) ("current-head audit expected active issue {0}, found {1}." -f $ExpectedActiveIssueId, [string]$state.governance.activeIssueId)

  Assert-Audit ([string]$sourceFix.issueId -eq 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR') 'source-fix evidence is bound to the wrong issue.'
  Assert-Audit ([string]$sourceFix.status -eq 'source_fix_applied_pending_verification') 'source-fix evidence is not pending verification.'
  Assert-Audit (-not [bool]$sourceFix.semanticMatchAllowed) 'source-fix evidence contains a semantic-match claim.'
  Assert-Audit (@($sourceFix.notRun).Count -gt 0) 'source-fix evidence must retain deferred runtime actions.'
  Assert-Audit ([string]$contract.status -eq 'passed' -and [int]$contract.assertions -eq 10) 'mixed composition contract is not the current 10-assertion pass.'
  Assert-Audit ([string]$embeddedContract.status -eq 'passed' -and [int]$embeddedContract.assertions -eq 12) 'embedded runtime contract is not the current 12-assertion pass.'

  $analyzerText = Read-StrictText -Path $analyzerPath
  $engineText = Read-StrictText -Path $enginePath
  $runtimeText = Read-StrictText -Path $runtimePath
  Assert-Audit ($analyzerText.Contains('findFirstTopLevelSplitter') -and $analyzerText.Contains("splitRuleStr(processedRule, ['&&', '||'])")) 'Analyzer first-operator or caller-specific split path is missing.'
  Assert-Audit ($engineText.Contains('__splitRuleCombinators') -and $engineText.Contains('__nativeSplitRuleCombinators')) 'standard/native JSVM combinator helpers are missing.'
  Assert-Audit ($runtimeText.Contains('legadoJsonPathSplitCombinators') -and $runtimeText.Contains('firstOperator')) 'ArkWeb first-operator helper is missing.'

  $hashPaths = @(
    $analyzerPath, $enginePath, $runtimePath, $mixedFixturePath, $embeddedFixturePath
  ) + $legadoPaths
  $currentHashes = [ordered]@{}
  foreach ($path in $hashPaths) {
    $currentHashes[(Get-RelativePath -Path $path)] = Get-Sha256 -Path $path
  }

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_rule_composition_current_head_static_audit'
    issueId = 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR'
    status = 'passed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    baseline = [pscustomobject][ordered]@{
      sourceCount = [int]$baseline.sourceCount
      sourcePackageSha256 = [string]$baseline.sourcePackageSha256
      legadoCommit = [string]$baseline.legadoCommit
    }
    historicalSourceFixEvidence = Get-RelativePath -Path $sourceFixPath
    staticContractEvidence = @(
      (Get-RelativePath -Path $contractPath)
      (Get-RelativePath -Path $embeddedContractPath)
    )
    currentHeadSha256 = $currentHashes
    affectedSetClaim = [pscustomobject][ordered]@{
      sourceCount = [int]$sourceFix.affectedSourceCount
      ruleStringCount = [int]$sourceFix.affectedRuleStringCount
      pureNonJavaScriptMixedRuleStringCount = [int]$sourceFix.pureNonJavaScriptMixedRuleStringCount
      source = 'frozen source-fix evidence; runtime affected-set verification deferred to R4'
    }
    assertions = $script:assertions
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_rule_composition_current_head_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_rule_composition_current_head_static_audit'
    issueId = 'ISSUE-COMPAT-232-RULE-COMPOSITION-FIRST-OPERATOR'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    failurePosition = $_.InvocationInfo.PositionMessage
    failureStack = $_.ScriptStackTrace
    assertions = $script:assertions
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_rule_composition_current_head_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  }
}

Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Compress
if ([string]$result.status -ne 'passed') { exit 1 }
