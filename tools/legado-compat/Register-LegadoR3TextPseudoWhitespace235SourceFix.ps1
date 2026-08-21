[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$TargetEvidencePath = 'tools/legado-compat/evidence/r3-actual-docs-source-refactor-target-20260809-235-text-whitespace/target.json',
  [string]$PreFixEvidencePath = 'tools/legado-compat/evidence/contract-legado-jsoup-text-whitespace-pre-fix-20260809.json',
  [string]$ConsumerEvidencePath = 'tools/legado-compat/evidence/contract-legado-jsoup-text-whitespace-consumers-pre-fix-20260809.json',
  [string]$StaticContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-text-whitespace-20260809.json',
  [string]$SourceFixEvidencePath = 'tools/legado-compat/evidence/v2-jsoup-text-whitespace-source-fix-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing JSON: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes) | ConvertFrom-Json
}

function Read-StrictText {
  param([string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing text: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}

function Write-AtomicJson {
  param([string]$RelativePath, [object]$Value)
  $absolute = Get-RepoPath -RelativePath $RelativePath
  $directory = Split-Path -Parent $absolute
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$absolute.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 40), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $absolute -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Write-AtomicText {
  param([string]$RelativePath, [string]$Value)
  $absolute = Get-RepoPath -RelativePath $RelativePath
  $directory = Split-Path -Parent $absolute
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$absolute.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, $Value, $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $absolute -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Get-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Set-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Value)
  if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
  else { $Object.$Name = $Value }
}

function Assert-Registration {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "235 whitespace source-fix registration blocked: $Message" }
}

$statePath = Get-RepoPath -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = Get-RepoPath -RelativePath 'tools/legado-compat/state/refactor-objective.json'
$target = Read-StrictJson -RelativePath $TargetEvidencePath
$preFix = Read-StrictJson -RelativePath $PreFixEvidencePath
$consumer = Read-StrictJson -RelativePath $ConsumerEvidencePath
$contract = Read-StrictJson -RelativePath $StaticContractPath
$state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$objective = Read-StrictJson -RelativePath 'tools/legado-compat/state/refactor-objective.json'

Assert-Registration ([string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS') 'active issue is not 235.'
Assert-Registration ([string]$target.currentSubstage -eq '235-WS-03') 'target is not at WS-03.'
Assert-Registration ([string]$preFix.status -eq 'failed' -and [string]$consumer.status -eq 'failed') 'pre-fix evidence is not preserved as failed.'
Assert-Registration ([string]$contract.status -eq 'passed' -and -not [bool]$contract.semanticMatchAllowed -and @($contract.runtimeActionsPerformed).Count -eq 0) 'static contract is not a static-only pass.'

$changedPaths = @(
  'entry/src/main/ets/libs/htmlparser/LegadoTextNormalization.ets',
  'entry/src/main/ets/libs/htmlparser/index.ets',
  'entry/src/main/ets/libs/htmlparser/HTMLElement.ets',
  'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
  'entry/src/main/resources/rawfile/legado_runtime.html'
)
$sourceHashes = [ordered]@{}
foreach ($path in $changedPaths) {
  $sourceHashes[$path] = (Get-FileHash -LiteralPath (Get-RepoPath -RelativePath $path) -Algorithm SHA256).Hash.ToUpperInvariant()
}

$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_jsoup_text_whitespace_source_fix'
  issueId = 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
  status = 'source_closed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{
    sourceCount = [int]$state.baseline.sourceCount
    sourcePackageSha256 = [string]$state.baseline.sourcePackageSha256
    legadoCommit = [string]$state.baseline.legadoCommit
  }
  failureEvidence = @($PreFixEvidencePath, $ConsumerEvidencePath)
  staticContract = $StaticContractPath
  rootCause = 'The DOM, large-document fallback and ArkWeb projected Jsoup text independently as raw text plus trim. A shared LegadoTextAccumulator contract now carries normalised whitespace, invisible-character filtering, preserve-whitespace tags, br/block boundaries and Java-range final trim across all paths.'
  changedPaths = $changedPaths
  currentHeadHashes = $sourceHashes
  consumers = @('HTMLElement.text', 'HTMLElement.ownText', 'LegadoRuleAnalyzer.htmlToText', 'LegadoRuleAnalyzer.extractDirectTextNodes', 'ArkWeb legadoText', 'ArkWeb legadoOwnText', 'ArkWeb Jsoup pseudo predicates', 'ArkWeb java element text handoff')
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_source_fix_only;static_contract_passed;runtime_regression_build_device_and_legado_diff_deferred'
  followUp = 'R4 must compare the fixture and affected source set against Legado at runtime before any semantic_match or passed state.'
}
Write-AtomicJson -RelativePath $SourceFixEvidencePath -Value $sourceFix

Set-PropertyValue -Object $target -Name 'lastUpdatedAt' -Value ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue -Object $target -Name 'sourceFixEvidencePath' -Value $SourceFixEvidencePath
Set-PropertyValue -Object $target -Name 'sourceFixStatus' -Value 'source_closed_static_only'
Set-PropertyValue -Object $target -Name 'currentSubstage' -Value '235-WS-04'
$targetPlan = @($target.plan)
$ws03 = $targetPlan | Where-Object { [string]$_.id -eq '235-WS-03' } | Select-Object -First 1
$ws04 = $targetPlan | Where-Object { [string]$_.id -eq '235-WS-04' } | Select-Object -First 1
Assert-Registration ($null -ne $ws03 -and $null -ne $ws04) 'target plan does not contain WS-03 and WS-04.'
Set-PropertyValue -Object $ws03 -Name 'status' -Value 'completed'
Set-PropertyValue -Object $ws03 -Name 'completedEvidence' -Value $SourceFixEvidencePath
Set-PropertyValue -Object $ws04 -Name 'status' -Value 'in_progress'
Set-PropertyValue -Object $ws04 -Name 'startedEvidence' -Value $SourceFixEvidencePath
Write-AtomicJson -RelativePath $TargetEvidencePath -Value $target

$plan = @($objective.continuationPlan)
$objectiveWs03 = $plan | Where-Object { [string]$_.id -eq '235-WS-03' } | Select-Object -First 1
$objectiveWs04 = $plan | Where-Object { [string]$_.id -eq '235-WS-04' } | Select-Object -First 1
Assert-Registration ($null -ne $objectiveWs03 -and $null -ne $objectiveWs04) 'objective plan does not contain WS-03 and WS-04.'
Set-PropertyValue -Object $objectiveWs03 -Name 'status' -Value 'completed'
Set-PropertyValue -Object $objectiveWs03 -Name 'completedEvidence' -Value $SourceFixEvidencePath
Set-PropertyValue -Object $objectiveWs04 -Name 'status' -Value 'in_progress'
Set-PropertyValue -Object $objectiveWs04 -Name 'startedEvidence' -Value $SourceFixEvidencePath
$objective.lastReviewedAt = [DateTimeOffset]::UtcNow.ToString('o')
$objective.nextAction = '执行 235-WS-04：完成静态合同、PowerShell 语法、JSON/UTF-8、current-head 哈希和证据隔离审计；保持 235 verifying，尚不得激活 236 或启动 R4。'
$objective.objective.latestStaticClosure = '235 文本伪类及其 text/ownText 空白规范化已完成跨 DOM、字符串回退和 ArkWeb 的源码闭合；静态证据不能提升为 passed 或 semantic_match。'
Write-AtomicJson -RelativePath 'tools/legado-compat/state/refactor-objective.json' -Value $objective

$objectiveDocument = Read-StrictText -RelativePath 'docs/analysis/Legado书源V2源码重构持续目标.md'
$objectiveDocument = $objectiveDocument.Replace('当前子阶段：`235-WS-01` 失败前合同与 `235-WS-02` 消费者矩阵已登记；唯一下一步为 `235-WS-03` 共享语义实现。', '当前子阶段：`235-WS-01`/`235-WS-02` 失败证据与消费者矩阵已登记，`235-WS-03` 源码闭合；唯一下一步为 `235-WS-04` 静态证据与文档审计。')
$objectiveDocument = $objectiveDocument.Replace('3. 失败合同固定后，使用共享的类型化空白规范化语义跨三条路径修复；静态合同通过仍只保持 `verifying`，不得写成 `passed` 或 `semantic_match`。', '3. `235-WS-03` 已使用共享的类型化空白规范化语义跨三条路径修复；静态合同仍只保持 `verifying`，不得写成 `passed` 或 `semantic_match`。')
$newline = if ($objectiveDocument.Contains("`r`n")) { "`r`n" } else { "`n" }
Write-AtomicText -RelativePath 'docs/analysis/Legado书源V2源码重构持续目标.md' -Value ($objectiveDocument.Replace("`n", $newline))

$setScript = Join-Path $PSScriptRoot 'Set-LegadoRefactorObjective.ps1'
& $setScript -StatePath $statePath -ObjectivePath (Get-RepoPath -RelativePath 'tools/legado-compat/state/refactor-objective.json') -ActiveIssueId 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' | Out-Null
if (-not $?) { throw 'refactor objective attachment failed.' }
$updateScript = Join-Path $PSScriptRoot 'Update-LegadoGovernanceState.ps1'
& $updateScript -StatePath $statePath -IssueId 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -IssueStatus verifying -TaskId 'COMPAT-006' -Summary '235-WS-03 源码闭合：新增共享 LegadoTextAccumulator/Normalization，统一 DOM、字符串回退和 ArkWeb 的 text/ownText、空白集合、保留空白、br/块边界与 Java trim；16 项静态合同通过，R4 仍延期。' -EvidencePath @($TargetEvidencePath, $PreFixEvidencePath, $ConsumerEvidencePath, $StaticContractPath, $SourceFixEvidencePath) | Out-Null
if (-not $?) { throw 'governance state refresh failed.' }

$refreshed = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$refreshedObjective = Read-StrictJson -RelativePath 'tools/legado-compat/state/refactor-objective.json'
Assert-Registration ([string]$refreshed.governance.activeIssueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS') 'active issue changed during source-fix registration.'
Assert-Registration ([string]$refreshedObjective.nextAction -like '执行 235-WS-04*') 'next action was not advanced to WS-04.'
Write-Output ("SOURCE_FIX_REGISTERED issue={0} ws03=completed ws04=in_progress evidence={1}" -f $refreshed.governance.activeIssueId, $SourceFixEvidencePath)
