[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RunId = 'r3-issue228-queue-gate-20260808-r1',
  [string]$OutputPath = '',
  [switch]$RequireRegistration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($RepositoryRoot.Length -eq 0) {
  $RepositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$evidenceRoot = (Resolve-Path -LiteralPath (Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).Path
$runDirectory = Join-Path $evidenceRoot $RunId
if ($OutputPath.Length -eq 0) {
  $OutputPath = Join-Path $runDirectory 'r3-issue228-queue-static-gate.json'
}
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$evidencePrefix = $evidenceRoot.TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidencePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Issue-228 queue gate output must remain under the evidence directory.'
}
if (-not (Test-Path -LiteralPath $runDirectory)) {
  [System.IO.Directory]::CreateDirectory($runDirectory) | Out-Null
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:checks = New-Object 'System.Collections.Generic.List[object]'
$script:assertions = 0

function Get-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Get-Issue {
  param([object[]]$Issues, [string]$Id)
  foreach ($issue in $Issues) {
    if ([string](Get-PropertyValue -Object $issue -Name 'id') -eq $Id) { return $issue }
  }
  return $null
}

function Read-StrictUtf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw "Required file is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  try { return (Read-StrictUtf8Text -Path $Path | ConvertFrom-Json) }
  catch { throw "Invalid JSON: $Path; $($_.Exception.Message)" }
}

function Read-SourceUtf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw "Required source file is missing: $Path" }
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

function Get-Sha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-BytesSha256 {
  param([Parameter(Mandatory = $true)][string]$Text)
  $hash = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([BitConverter]::ToString($hash.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text))) -replace '-', '').ToUpperInvariant()
  } finally {
    $hash.Dispose()
  }
}

function Get-StringLeaves {
  param([object]$Value)
  if ($null -eq $Value) { return @() }
  if ($Value -is [string]) { return @([string]$Value) }
  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
    $values = New-Object 'System.Collections.Generic.List[string]'
    foreach ($item in $Value) {
      foreach ($text in @(Get-StringLeaves -Value $item)) { [void]$values.Add($text) }
    }
    return $values.ToArray()
  }
  $result = New-Object 'System.Collections.Generic.List[string]'
  foreach ($property in $Value.PSObject.Properties) {
    foreach ($text in @(Get-StringLeaves -Value $property.Value)) { [void]$result.Add($text) }
  }
  return $result.ToArray()
}

function Assert-Gate {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
  $script:assertions++
}

function Add-Check {
  param([string]$Id, [string]$Detail, [string[]]$Evidence = @())
  [void]$script:checks.Add([pscustomobject][ordered]@{
      id = $Id
      status = 'passed'
      detail = $Detail
      evidencePaths = @($Evidence)
    })
}

$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$objectivePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\refactor-objective.json'
$preFixPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-java-string-list-analyzer-js-contract-20260808-pre-fix.json'
$postFixPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-java-string-list-analyzer-js-contract-20260808-post-fix.json'
$contractPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-java-string-list-analyzer-js-contract-20260808.json'
$sourceFixPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-java-string-list-analyzer-js-source-fix-20260808.json'
$currentHeadAuditPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-java-string-list-analyzer-js-source-fix-current-head-hash-audit-20260808-r1.json'
$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-java-string-list-analyzer-js.json'
$analyzerPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoRuleAnalyzer.ets'
$enginePath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoJsEngine.ets'
$runtimePath = Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html'
$legadoAnalyzeRulePath = Join-Path $RepositoryRoot 'legado\app\src\main\java\io\legado\app\model\analyzeRule\AnalyzeRule.kt'
$legadoJsoupPath = Join-Path $RepositoryRoot 'legado\app\src\main\java\io\legado\app\model\analyzeRule\AnalyzeByJSoup.kt'
$objectiveDocumentPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源V2源码重构持续目标.md'
$governancePath = Join-Path $RepositoryRoot 'tools\legado-compat\LEGADO_V2_GOVERNANCE_TASKS.md'
$ledgerPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎兼容推进台账.md'
$indexPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎证据索引.md'
$diffPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎差分摘要.md'
$packagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
$relativeOutputPath = 'tools/legado-compat/evidence/' + $RunId + '/r3-issue228-queue-static-gate.json'

$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -Path $statePath
  $objective = Read-StrictJson -Path $objectivePath
  $preFix = Read-StrictJson -Path $preFixPath
  $postFix = Read-StrictJson -Path $postFixPath
  $contract = Read-StrictJson -Path $contractPath
  $sourceFix = Read-StrictJson -Path $sourceFixPath
  $currentHeadAudit = Read-StrictJson -Path $currentHeadAuditPath
  $fixture = Read-StrictJson -Path $fixturePath

  $baseline = $state.baseline
  Assert-Gate ([int]$baseline.sourceCount -eq 458) 'machine baseline source count is not 458.'
  Assert-Gate ([string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'machine source hash is not frozen.'
  Assert-Gate ((Get-Sha256 -Path $packagePath) -eq [string]$baseline.sourcePackageSha256) 'source package hash drifted.'
  Assert-Gate ([string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine Legado commit is not frozen.'
  $legadoRoot = Join-Path $RepositoryRoot 'legado'
  $legadoCommit = (& git -C $legadoRoot rev-parse HEAD 2>$null | Out-String).Trim()
  Assert-Gate ($legadoCommit -eq [string]$baseline.legadoCommit) 'Legado checkout is not at the frozen commit.'
  Add-Check -Id 'baseline_binding' -Detail '228 evidence is bound to the frozen 458-source package and Legado commit.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json', 'tools/legado-compat/evidence/v2-java-string-list-analyzer-js-source-fix-20260808.json')

  $governance = $state.governance
  $issues = @($governance.issues)
  $issueHarness = Get-Issue -Issues $issues -Id 'V2-HARNESS-023'
  $issue228 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS'
  Assert-Gate ([string]$governance.activeTaskId -eq 'COMPAT-006') 'active task drifted from COMPAT-006.'
  if ($RequireRegistration) {
    Assert-Gate ([string]$governance.activeIssueId -eq 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS') 'post-transition active issue is not 228.'
  } else {
    Assert-Gate ([string]$governance.activeIssueId -eq 'V2-HARNESS-023') 'pre-transition active issue must remain Harness-023.'
  }
  Assert-Gate ([string]$governance.status -eq 'running') 'governance status is not running.'
  Assert-Gate ($null -ne $issueHarness -and [string]$issueHarness.status -eq 'verifying') 'Harness-023 must remain verifying.'
  Assert-Gate ($null -ne $issue228 -and [string]$issue228.status -eq 'verifying') '228 must be verifying before or after queue selection.'
  Add-Check -Id 'queue_precondition' -Detail 'Harness-023 remains deferred-R4 and 228 is the only candidate being prepared for queue selection.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json')

  Assert-Gate ([string]$preFix.issueId -eq 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS' -and [string]$preFix.status -eq 'failed' -and [int]$preFix.assertions -gt 0) '228 frozen failure contract is missing or not failed.'
  Assert-Gate ([string]$postFix.issueId -eq 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS' -and [string]$postFix.status -eq 'passed' -and [int]$postFix.assertions -eq 22) '228 post-fix static contract is not the expected 22-assertion result.'
  Assert-Gate ([string]$contract.issueId -eq 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS' -and [string]$contract.status -eq 'passed' -and [int]$contract.assertions -eq 22) '228 current static contract is not passed.'
  Assert-Gate ([string]$sourceFix.issueId -eq 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS' -and [string]$sourceFix.status -eq 'source_fix_applied_pending_verification') '228 source-fix evidence is not pending verification.'
  Assert-Gate (-not [bool]$sourceFix.semanticMatchAllowed -and [string]$sourceFix.verificationPolicy -eq 'runtime_regression_deferred_by_user') '228 source-fix evidence contains an invalid semantic or runtime claim.'
  Assert-Gate ([string]$currentHeadAudit.status -eq 'current_head_bound_with_historical_superseded_evidence') '228 current-head hash audit is missing or has an invalid historical classification.'
  Assert-Gate ([string]$currentHeadAudit.historicalEvidence.classification -eq 'superseded_shared_engine_hash') '228 historical shared-engine hash drift is not explicitly classified.'
  Assert-Gate ([string]$currentHeadAudit.historicalEvidence.path -eq 'tools/legado-compat/evidence/v2-java-string-list-analyzer-js-contract-20260808-post-fix.json') '228 historical post-fix evidence path is not retained.'
  Assert-Gate ([string]$currentHeadAudit.historicalEvidence.replacementEvidencePath -eq 'tools/legado-compat/evidence/v2-java-string-list-analyzer-js-source-fix-current-head-hash-audit-20260808-r1.json') '228 current-head replacement evidence path is not self-bound.'
  Add-Check -Id 'failure_and_static_contract' -Detail '228 has a frozen failed contract, a passed 22-assertion static contract and an explicit pending-verification source-fix record.' -Evidence @('tools/legado-compat/evidence/v2-java-string-list-analyzer-js-contract-20260808-pre-fix.json', 'tools/legado-compat/evidence/v2-java-string-list-analyzer-js-contract-20260808-post-fix.json', 'tools/legado-compat/evidence/v2-java-string-list-analyzer-js-source-fix-20260808.json')

  $expectedRequiredPaths = @('getElementsAsync', 'getElementsSingleAsync', 'executeJavaScriptElementsAsync', 'LegadoJsEngine.standard', 'LegadoJsEngine.native', 'legado_runtime.html')
  Assert-Gate (@($fixture.requiredPaths).Count -eq $expectedRequiredPaths.Count) '228 fixture required path matrix changed.'
  Assert-Gate ((@($fixture.requiredPaths) -join '|') -eq ($expectedRequiredPaths -join '|')) '228 fixture requiredPaths must remain semantic call-path identifiers, not filesystem paths.'
  $analyzerText = Read-SourceUtf8Text -Path $analyzerPath
  $engineText = Read-SourceUtf8Text -Path $enginePath
  $runtimeText = Read-SourceUtf8Text -Path $runtimePath
  Assert-Gate ($analyzerText.Contains('async getElementsAsync(')) 'Analyzer getElementsAsync path is missing.'
  Assert-Gate ($analyzerText.Contains('private async getElementsSingleAsync(')) 'Analyzer getElementsSingleAsync path is missing.'
  Assert-Gate ($analyzerText.Contains('private async executeJavaScriptElementsAsync(')) 'Analyzer JS element executor path is missing.'
  Assert-Gate ($engineText.Contains('getStringList: function(rule, content)') -and $engineText.Contains('private buildNativeScript(')) 'standard/native JS engine paths are missing.'
  Assert-Gate ($runtimeText.Contains('getStringList: function (rule, content)')) 'ArkWeb runtime getStringList path is missing.'
  Assert-Gate ((Get-Sha256 -Path $analyzerPath) -eq [string]$currentHeadAudit.currentHead.analyzerSha256) 'Analyzer HEAD hash drifted from current 228 audit.'
  Assert-Gate ((Get-Sha256 -Path $enginePath) -eq [string]$currentHeadAudit.currentHead.engineSha256) 'JS engine HEAD hash drifted from current 228 audit.'
  Assert-Gate ((Get-Sha256 -Path $runtimePath) -eq [string]$currentHeadAudit.currentHead.runtimeSha256) 'ArkWeb runtime HEAD hash drifted from current 228 audit.'
  Assert-Gate ((Get-Sha256 -Path $fixturePath) -eq [string]$currentHeadAudit.currentHead.fixtureSha256) '228 fixture hash drifted from current audit.'
  Assert-Gate ((Get-Sha256 -Path $legadoAnalyzeRulePath) -ne '') 'Legado AnalyzeRule reference is missing or unreadable.'
  Assert-Gate ((Get-Sha256 -Path $legadoJsoupPath) -ne '') 'Legado AnalyzeByJSoup reference is missing or unreadable.'
  Add-Check -Id 'implementation_hash_binding' -Detail 'Analyzer, both JS engines, ArkWeb runtime and fixture are bound to the current HEAD audit; the historical shared-engine hash remains retained as superseded evidence.' -Evidence @('tools/legado-compat/evidence/v2-java-string-list-analyzer-js-contract-20260808.json', 'tools/legado-compat/evidence/v2-java-string-list-analyzer-js-source-fix-20260808.json', 'tools/legado-compat/evidence/v2-java-string-list-analyzer-js-source-fix-current-head-hash-audit-20260808-r1.json')

  $package = Read-StrictJson -Path $packagePath
  Assert-Gate (@($package).Count -eq 458) 'frozen package does not contain 458 source documents.'
  $affected = New-Object 'System.Collections.Generic.List[object]'
  $ordinal = 0
  foreach ($source in @($package)) {
    $leaves = @(Get-StringLeaves -Value $source)
    $hits = @($leaves | Where-Object { $_ -match 'java\.getStringList' })
    if ($hits.Count -gt 0) {
      $chains = @($hits | Where-Object { $_ -match '(?i)(class\.|id\.|tag\.|@css:)' })
      $stateSource = @($state.sources | Where-Object { [int]$_.ordinal -eq $ordinal })
      Assert-Gate ($stateSource.Count -eq 1) ("state source identity missing for ordinal {0}." -f $ordinal)
      [void]$affected.Add([pscustomobject][ordered]@{
          ordinal = $ordinal
          sourceId = [string]$stateSource[0].sourceId
          javaGetStringListCount = $hits.Count
          chainCount = $chains.Count
        })
    }
    $ordinal++
  }
  Assert-Gate ($affected.Count -eq 10) '228 affected source count drifted from the pinned package analysis.'
  $totalCalls = [int](($affected | Measure-Object javaGetStringListCount -Sum).Sum)
  $chainSources = @($affected | Where-Object { [int]$_.chainCount -gt 0 }).Count
  Assert-Gate ($totalCalls -eq 18 -and $chainSources -eq 4) '228 affected capability counts drifted from the pinned package analysis.'
  $affectedCanonical = $affected.ToArray() | ConvertTo-Json -Compress -Depth 8
  $affectedDigest = Get-BytesSha256 -Text $affectedCanonical
  Add-Check -Id 'affected_source_set' -Detail 'The pinned package contains 10 affected sources, 18 java.getStringList call sites and 4 chained-rule sources; identities are bound to machine source IDs.' -Evidence @('tools/legado-compat/fixtures/legado-java-string-list-analyzer-js.json', 'tools/legado-compat/state/full-source-validation-state.json')

  $objective = Read-StrictJson -Path $objectivePath
  $objectiveBody = $objective.objective
  $executionTarget = $objective.executionTarget
  if ($RequireRegistration) {
    Assert-Gate ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS' -and [string]$objectiveBody.activeIssue -eq 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS') 'post-transition objective does not select 228.'
  } else {
    Assert-Gate ([string]$objective.authority.activeIssueId -eq 'V2-HARNESS-023' -and [string]$objectiveBody.activeIssue -eq 'V2-HARNESS-023') 'pre-transition objective must remain on Harness-023.'
  }
  Assert-Gate (@($executionTarget.nextIssues) -contains 'ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT') '230 is not registered as the following candidate.'
  $objectiveDocument = Read-StrictUtf8Text -Path $objectiveDocumentPath
  $governanceDocument = Read-StrictUtf8Text -Path $governancePath
  $ledgerDocument = Read-StrictUtf8Text -Path $ledgerPath
  $indexDocument = Read-StrictUtf8Text -Path $indexPath
  $diffDocument = Read-StrictUtf8Text -Path $diffPath
  if ($RequireRegistration) {
    Assert-Gate ($governanceDocument.Contains('activeIssue=`ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS`') -and $objectiveDocument.Contains('当前唯一源码验证议题为 `ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS`')) 'post-transition documents do not select 228.'
  } else {
    Assert-Gate ($governanceDocument.Contains('activeIssue=`V2-HARNESS-023`') -and $objectiveDocument.Contains('下一候选为 `ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS`')) 'pre-transition documents do not retain 228 as candidate.'
  }
  Assert-Gate ($ledgerDocument.Contains('活跃任务：COMPAT-006') -and $indexDocument -match '\| `ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS` \| `verifying` \|' -and $diffDocument -match '\| `ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS` \| `verifying` \|') 'generated documents do not retain 228 evidence.'
  if ($RequireRegistration) {
    $issueEvidence = @($issue228.evidencePaths | ForEach-Object { [string]$_ })
    Assert-Gate ($issueEvidence -contains $relativeOutputPath) '228 queue gate is not registered in machine state.'
    Assert-Gate ($indexDocument.Contains($relativeOutputPath) -and $diffDocument.Contains($relativeOutputPath)) '228 queue gate is missing from generated evidence documents.'
  }
  Add-Check -Id 'objective_document_binding' -Detail 'The objective and generated documents preserve one active issue and defer R4.' -Evidence @('tools/legado-compat/state/refactor-objective.json', 'docs/analysis/Legado书源V2源码重构持续目标.md', 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md', 'docs/analysis/Legado书源引擎证据索引.md', 'docs/analysis/Legado书源引擎差分摘要.md')

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_issue228_queue_static_gate'
    status = 'passed'
    issueId = 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    baseline = [pscustomobject][ordered]@{ sourceCount = [int]$baseline.sourceCount; sourcePackageSha256 = [string]$baseline.sourcePackageSha256; legadoCommit = [string]$baseline.legadoCommit }
    transition = [pscustomobject][ordered]@{ fromIssue = 'V2-HARNESS-023'; fromStatus = 'verifying'; toIssue = 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS'; toStatus = 'verifying'; nextCandidate = 'ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT'; runtimeVerification = 'deferred_to_R4' }
    affectedSourceSet = [pscustomobject][ordered]@{ selection = 'any string field containing java.getStringList in the frozen source package'; sourceCount = $affected.Count; callCount = $totalCalls; chainedSourceCount = $chainSources; digest = $affectedDigest; records = $affected.ToArray() }
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @('tools/legado-compat/evidence/v2-java-string-list-analyzer-js-contract-20260808-pre-fix.json', 'tools/legado-compat/evidence/v2-java-string-list-analyzer-js-contract-20260808-post-fix.json', 'tools/legado-compat/evidence/v2-java-string-list-analyzer-js-source-fix-20260808.json', 'tools/legado-compat/evidence/v2-java-string-list-analyzer-js-source-fix-current-head-hash-audit-20260808-r1.json', 'tools/legado-compat/fixtures/legado-java-string-list-analyzer-js.json', 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeRule.kt', 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt')
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_issue228_source_closure_static_only;R4_runtime_build_device_and_legado_diff_deferred'
    registrationRequired = [bool]$RequireRegistration
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_issue228_queue_static_gate'
    status = 'failed'
    issueId = 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_issue228_source_closure_static_only;R4_runtime_build_device_and_legado_diff_deferred'
    registrationRequired = [bool]$RequireRegistration
  }
}

$temporaryPath = "$outputFullPath.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
[System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 24), [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $outputFullPath -Force
$result | ConvertTo-Json -Depth 24
if ($exitCode -ne 0) { exit $exitCode }
