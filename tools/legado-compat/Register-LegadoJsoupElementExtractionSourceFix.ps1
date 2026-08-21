param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-element-extraction-quoted-closing-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-element-extraction-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-element-extraction-post-fix-20260810.json',
  [string]$CurrentHeadAuditPath = 'tools/legado-compat/evidence/v2-jsoup-element-extraction-current-head-audit-20260810.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-element-extraction-source-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$taskId = 'COMPAT-006'
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$revision = '2026-08-10-actual-docs-source-refactor-jsoup-element-extraction-static-closure'
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }; return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "required file is missing: $Path" }; $bytes = [System.IO.File]::ReadAllBytes($resolved); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }; return $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100) }
function Set-PropertyValue { param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value); if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force } else { $Object.$Name = $Value } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }
function Assert-Gate { param([bool]$Condition, [string]$Detail); if (-not $Condition) { throw "243 element extraction source-fix gate failed: $Detail" } }

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson -Path $statePath
$objective = Read-StrictJson -Path $objectivePath
$fixture = Read-StrictJson -Path $FixturePath
$failure = Read-StrictJson -Path $FailureWitnessPath
$contract = Read-StrictJson -Path $PostFixContractPath
$audit = Read-StrictJson -Path $CurrentHeadAuditPath
$analyzer = Read-StrictText -Path $analyzerPath
$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId })[0]

Assert-Gate ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Gate ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq $taskId -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) '243 must remain the active static issue.'
Assert-Gate ($null -ne $issue -and [string]$issue.status -eq 'verifying') '243 must remain verifying.'
Assert-Gate ([string]$failure.status -eq 'failed' -and [string]$contract.status -eq 'passed' -and [string]$audit.status -eq 'passed' -and -not [bool]$failure.semanticMatchAllowed -and -not [bool]$contract.semanticMatchAllowed -and -not [bool]$audit.semanticMatchAllowed) 'static evidence is incomplete or claims semantic match.'
Assert-Gate ([string]$fixture.issueId -eq $issueId -and @($fixture.cases).Count -eq 3) 'element extraction fixture drifted.'
Assert-Gate ($analyzer.Contains('private extractElement(html: string, startIndex: number, tagName: string): string | null') -and $analyzer.Contains('const scan = this.scanNextHtmlTag(html, pos);') -and -not $analyzer.Contains('class TagRegexPair') -and -not $analyzer.Contains('private getTagRegexPair(tagName: string): TagRegexPair')) 'same-tag extraction source closure is missing.'

$existingSourceFixPath = Get-RepoPath $SourceFixPath
if ([string]$objective.targetRevision -eq $revision -and (Test-Path -LiteralPath $existingSourceFixPath -PathType Leaf)) {
  [pscustomobject][ordered]@{ status = 'already_registered'; issueId = $issueId; targetRevision = $revision; sourceFixEvidencePath = $SourceFixPath; runtimeActionsPerformed = @(); semanticMatchAllowed = $false; idempotent = $true } | ConvertTo-Json -Depth 100
  return
}

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $analyzerPath)).Hash.ToUpperInvariant()
$backupPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets.bak_20260810_element_extraction'
$backupHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $backupPath)).Hash.ToUpperInvariant()
$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_fix'
  issueId = $issueId
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  extends = 'tools/legado-compat/evidence/v2-jsoup-script-style-removal-source-fix-20260810.json'
  failureEvidence = @($FailureWitnessPath)
  staticContract = $PostFixContractPath
  currentHeadAudit = $CurrentHeadAuditPath
  changedPaths = @($analyzerPath)
  backupPath = $backupPath
  backupSha256 = $backupHash
  currentHeadHashes = [pscustomobject][ordered]@{ $analyzerPath = $hash }
  affectedCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  selectionPaths = @($fixture.selectionPaths)
  rootCause = [pscustomobject][ordered]@{
    category = '规则解析或编译'
    before = 'extractElement used same-tag opening and closing regular expressions. Markup-looking text inside quoted attributes was counted as a real node and changed the nesting depth, truncating or expanding the extracted element.'
    after = 'extractElement consumes quote-aware scanned HTML tag nodes and changes depth only for actual same-tag opening or closing nodes; self-closing nodes do not alter depth.'
    legadoReference = 'Pinned Legado AnalyzeByJSoup delegates element boundaries to Jsoup nodes, so quoted attribute values are data rather than Element nodes.'
  }
  consumerMatrix = [pscustomobject][ordered]@{
    tagSelector = $analyzerPath
    simpleSelector = $analyzerPath
    attributeExtraction = $analyzerPath
    scriptStyleCleanup = $analyzerPath
    legado = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
  }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_element_extraction_source_fix_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = 'R4 must execute all three element extraction cases, the affected source set, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson -Path $SourceFixPath -Value $sourceFix

$now = [DateTimeOffset]::UtcNow.ToString('o')
Set-PropertyValue $objective 'lastReviewedAt' $now
Set-PropertyValue $objective 'targetRevision' $revision
Set-PropertyValue $objective 'continuationMode' 'R3_ISSUE_243_ELEMENT_EXTRACTION_STATIC_CLOSED_WAIT_R4'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.authority 'activeIssueSelection' 'full-source-validation-state.json remains the only queue; 243 remains the sole active source-closure issue. Element extraction now uses the shared quote-aware HTML scanner and ignores markup-like text inside quoted attributes; semanticMatchAllowed remains false and R4 is deferred.'
Set-PropertyValue $objective.objective 'activeIssueRule' '243 standard CSS/XPath traversal and html terminal extraction must preserve Jsoup element-node boundaries: quoted attribute text cannot become a same-tag node, and actual nested elements must remain complete.'
Set-PropertyValue $objective 'nextAction' '243 element extraction static closure is registered; continue one-root-cause source audit while R4 remains deferred.'
$plan = @($objective.continuationPlan)
if (-not @($plan | Where-Object { [string]$_.id -eq '243-SP-41' })) {
  $plan += [pscustomobject][ordered]@{ id = '243-SP-41'; status = 'completed'; action = '将同名元素提取从 quote-blind 正则改为共享 HTML 标签扫描，仅按真实节点维护 depth，保留属性中的字面标签文本和完整嵌套元素。'; evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath) }
  $plan += [pscustomobject][ordered]@{ id = '243-SP-42'; status = 'deferred'; action = 'R4 执行三个元素提取 fixture、影响源集合、458 条 Harness、Legado 差分、构建和真机验证。' }
  Set-PropertyValue $objective 'continuationPlan' $plan
}
Write-AtomicJson -Path $objectivePath -Value $objective

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$evidence = @($FixturePath, $FailureWitnessPath, $PostFixContractPath, $CurrentHeadAuditPath, $SourceFixPath, $analyzerPath, $backupPath, 'tools/legado-compat/Test-LegadoJsoupElementExtractionFailureWitness.ps1', 'tools/legado-compat/Test-LegadoJsoupElementExtractionPostFixContract.ps1', 'tools/legado-compat/Test-LegadoJsoupElementExtractionCurrentHeadAudit.ps1', 'tools/legado-compat/Register-LegadoJsoupElementExtractionSourceFix.ps1', 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt')
$summary = '243 same-tag element extraction now uses the shared quote-aware HTML scanner, preserving complete nested elements and quoted attribute data. Runtime, full Harness, Legado differential, build and device validation remain deferred.'
$closeCondition = [string]$sourceFix.closeCondition
$pwsh = (Get-Command pwsh -ErrorAction Stop).Source
$updateOutput = & $pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript -IssueId $issueId -IssueStatus verifying -TaskId $taskId -TaskStatus running -Summary $summary -CloseCondition $closeCondition -EvidencePath ([string]::Join(',', $evidence)) 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "Update-LegadoGovernanceState failed:`n$updateOutput" }
[pscustomobject][ordered]@{ status = 'registered'; issueId = $issueId; sourceFixEvidencePath = $SourceFixPath; currentHeadAuditPath = $CurrentHeadAuditPath; postFixContractPath = $PostFixContractPath; governanceUpdate = $updateOutput.Trim(); runtimeActionsPerformed = @(); semanticMatchAllowed = $false } | ConvertTo-Json -Depth 100
