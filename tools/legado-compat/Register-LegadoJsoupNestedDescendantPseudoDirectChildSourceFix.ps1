[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-nested-descendant-pseudo-direct-child-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-nested-descendant-pseudo-direct-child-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-nested-descendant-pseudo-direct-child-post-fix-20260810.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-jsoup-nested-descendant-pseudo-direct-child-current-head-audit-20260810.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-nested-descendant-pseudo-direct-child-source-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$taskId = 'COMPAT-006'
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$backupPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets.bak_20260810_nested_descendant_pseudo_direct_child'

function Get-RepoPath([string]$RelativePath) { return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictText([string]$RelativePath) { $path=Get-RepoPath $RelativePath; if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing file: $RelativePath"}; $bytes=[System.IO.File]::ReadAllBytes($path); if($bytes.Length -ge 3 -and $bytes[0]-eq 0xEF -and $bytes[1]-eq 0xBB -and $bytes[2]-eq 0xBF){throw "UTF-8 BOM is not allowed: $RelativePath"}; return $strictUtf8.GetString($bytes) }
function Read-StrictJson([string]$RelativePath) { return Read-StrictText $RelativePath | ConvertFrom-Json -Depth 100 }
function Set-Prop([object]$Object,[string]$Name,[object]$Value){if($null -eq $Object.PSObject.Properties[$Name]){$Object|Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force}else{$Object.$Name=$Value}}
function Assert-Gate([bool]$Condition,[string]$Message){if(-not $Condition){throw "243 nested descendant pseudo source-fix gate failed: $Message"}}
function Write-AtomicJson([string]$RelativePath,[object]$Value){$path=Get-RepoPath $RelativePath;$temp="$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())";try{[System.IO.File]::WriteAllText($temp,($Value|ConvertTo-Json -Depth 100),$noBomUtf8);Move-Item -LiteralPath $temp -Destination $path -Force}finally{if(Test-Path -LiteralPath $temp){[System.IO.File]::Delete($temp)}}}

$statePath='tools/legado-compat/state/full-source-validation-state.json'
$objectivePath='tools/legado-compat/state/refactor-objective.json'
$state=Read-StrictJson $statePath
$objective=Read-StrictJson $objectivePath
$fixture=Read-StrictJson $FixturePath
$failure=Read-StrictJson $FailureWitnessPath
$contract=Read-StrictJson $PostFixContractPath
$audit=Read-StrictJson $CurrentHeadAuditPath
$analyzer=Read-StrictText $analyzerPath
$backup=Read-StrictText $backupPath
$issue=@($state.governance.issues|Where-Object{[string]$_.id -eq $issueId})[0]
Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Gate ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) '243 must remain the sole active static issue.'
Assert-Gate ($null -ne $issue -and [string]$issue.status -eq 'verifying') '243 must remain verifying.'
Assert-Gate ([string]$failure.status -eq 'failed' -and [string]$contract.status -eq 'passed' -and [string]$audit.status -eq 'passed') 'failure, post-fix and current-head evidence are incomplete.'
Assert-Gate (@($failure.runtimeActionsPerformed).Count -eq 0 -and @($contract.runtimeActionsPerformed).Count -eq 0 -and @($audit.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed -and -not [bool]$contract.semanticMatchAllowed -and -not [bool]$audit.semanticMatchAllowed) 'static evidence must not claim runtime or semantic match.'
Assert-Gate ($backup.Contains('findElementsBySimpleSelector(scopedParent, childSelector, effectiveContextHtml)') -and $analyzer.Contains('const childSelectorParts = this.splitTopLevelCssDescendantSelector(childSelector);') -and $analyzer.Contains('qualifyingDirectStarts')) 'the exact before/after segmented pseudo change is not present.'

$sourceFix=[pscustomobject][ordered]@{
  schemaVersion=1
  evidenceType='source_fix'
  issueId=$issueId
  status='source_closed_static_only'
  generatedAt=[DateTimeOffset]::UtcNow.ToString('o')
  baseline=[pscustomobject][ordered]@{sourceCount=458;sourcePackageSha256=$sourceHash;legadoCommit=$legadoCommit}
  failureEvidence=@($FailureWitnessPath)
  staticContract=$PostFixContractPath
  currentHeadAudit=$CurrentHeadAuditPath
  changedPaths=@($analyzerPath)
  backupPath=$backupPath
  backupSha256=(Get-FileHash -LiteralPath (Get-RepoPath $backupPath) -Algorithm SHA256).Hash.ToUpperInvariant()
  currentHeadHashes=[pscustomobject][ordered]@{$analyzerPath=(Get-FileHash -LiteralPath (Get-RepoPath $analyzerPath) -Algorithm SHA256).Hash.ToUpperInvariant()}
  affectedSourceOrdinals=@($fixture.affectedSourceOrdinals)
  affectedRuleStringCount=[int]$fixture.affectedRuleStringCount
  fixturePath=$FixturePath
  rootCause=[pscustomobject][ordered]@{
    category='规则解析或编译'
    originalSemantics='Pinned Legado evaluates each compound selector segment through Jsoup Element.select, so :nth-child on the direct-child ancestor and :first-child on its descendant retain separate contexts.'
    v2BeforeFix='The direct-child helper sent the entire right operand to findElementsBySimpleSelector, which collected all pseudo classes globally and applied them to the final result element.'
    v2AfterFix='The right operand now uses findElementsBySingleSelector, splits descendant segments, verifies the first segment at direct-child offsets, and projects descendant matches by owner range.'
    evidence=@($FixturePath,$FailureWitnessPath,$PostFixContractPath,$CurrentHeadAuditPath)
  }
  consumerMatrix=[pscustomobject][ordered]@{stringFallback=$analyzerPath;domMatcher='entry/src/main/ets/libs/htmlparser/HTMLElement.ets';arkWeb='entry/src/main/resources/rawfile/legado_runtime.html';legado='legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'}
  runtimeActionsPerformed=@()
  semanticMatchAllowed=$false
  verificationPolicy='r3_243_nested_descendant_pseudo_direct_child_source_fix_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition='R4 must execute all four segmented pseudo cases, ordinal 223, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $SourceFixPath $sourceFix

$existingOrdinals=@($issue.affectedSourceOrdinals|ForEach-Object{[int]$_})
$mergedOrdinals=@($existingOrdinals+$fixture.affectedSourceOrdinals|Sort-Object -Unique)
Set-Prop $issue 'affectedSourceOrdinals' $mergedOrdinals
Set-Prop $issue 'latestAffectedSourceOrdinals' @($fixture.affectedSourceOrdinals)
Set-Prop $issue 'latestAffectedRuleStringCount' ([int]$fixture.affectedRuleStringCount)
Set-Prop $issue 'rootCauseCategory' '规则解析或编译'
Set-Prop $issue 'lastSourceFixEvidencePath' $SourceFixPath
Set-Prop $issue 'lastUpdatedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
Set-Prop $objective 'lastReviewedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
Set-Prop $objective 'targetRevision' '2026-08-10-actual-docs-source-refactor-jsoup-nested-descendant-pseudo-direct-child-static-closure'
Set-Prop $objective 'continuationMode' 'R3_ISSUE_243_NESTED_DESCENDANT_PSEUDO_DIRECT_CHILD_STATIC_CLOSED_WAIT_R4'
Set-Prop $objective.authority 'activeIssueId' $issueId
Set-Prop $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; 243 remains the sole active source-closure issue. Nested descendant/direct-child pseudo segmentation is statically closed; semanticMatchAllowed remains false and R4 is deferred.'
Set-Prop $objective.objective 'activeIssueRule' '243 direct-child right operands may contain descendant segments; each segment must retain its own standard pseudo context and only descendants below a qualifying direct child may be projected.'
Set-Prop $objective 'nextAction' '243 nested descendant/direct-child pseudo source closure is registered; continue one-root-cause source audit while R4 remains deferred.'
Set-Prop $objective.continuationTarget 'activeBoundary' '243 保持 verifying；右操作数 descendant 分段伪类、ordinal 223 影响规则、失败见证、post-fix/current-head/source-fix 证据已登记；242 保持 verifying 等待 R4。'
Set-Prop $objective.continuationTarget 'nextTransition' '继续审计 243 的多级链、重复兄弟和嵌套伪类组合；R4 运行时与差分保持延期。'
$plan=@($objective.continuationPlan)
if(-not @($plan|Where-Object{[string]$_.id -eq '243-SP-51'})){
  $plan += [pscustomobject][ordered]@{id='243-SP-51';status='completed';action='修复 direct-child 右操作数包含后代链时的伪类上下文丢失，并登记第 223 条书源的真实规则。';evidence=@($FixturePath,$FailureWitnessPath,$PostFixContractPath,$CurrentHeadAuditPath,$SourceFixPath)}
  $plan += [pscustomobject][ordered]@{id='243-SP-52';status='deferred';action='R4 执行四个分段伪类案例、第 223 条书源、458 条 Harness、Legado 差分、构建和真机验证。'}
  Set-Prop $objective 'continuationPlan' $plan
}
Write-AtomicJson $statePath $state
Write-AtomicJson $objectivePath $objective

$evidence=@($FixturePath,$FailureWitnessPath,$PostFixContractPath,$CurrentHeadAuditPath,$SourceFixPath,$analyzerPath,$backupPath,'tools/legado-compat/Test-LegadoJsoupNestedDescendantPseudoDirectChildFailureWitness.ps1','tools/legado-compat/Test-LegadoJsoupNestedDescendantPseudoDirectChildPostFixContract.ps1','tools/legado-compat/Test-LegadoJsoupNestedDescendantPseudoDirectChildCurrentHeadAudit.ps1','tools/legado-compat/Register-LegadoJsoupNestedDescendantPseudoDirectChildSourceFix.ps1','legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt')
$summary='243 nested descendant/direct-child pseudo closure: the right operand now preserves segment-level :nth-child/:first-child context and projects descendants below qualifying direct children; ordinal 223 is bound to static failure, post-fix and current-head evidence. Runtime, full Harness, Legado differential, build and device validation remain deferred.'
$updateScript=Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$updateOutput=& pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript -StatePath (Get-RepoPath $statePath) -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition ([string]$sourceFix.closeCondition) -EvidencePath ([string]::Join(',', $evidence)) 2>&1 | Out-String
if($LASTEXITCODE -ne 0){throw "Update-LegadoGovernanceState failed:`n$updateOutput"}
[pscustomobject][ordered]@{status='registered';issueId=$issueId;latestAffectedSourceCount=@($fixture.affectedSourceOrdinals).Count;sourceFixEvidencePath=$SourceFixPath;runtimeActionsPerformed=@();semanticMatchAllowed=$false;governanceUpdate=$updateOutput.Trim()}|ConvertTo-Json -Depth 80
