[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$TargetEvidencePath = 'tools/legado-compat/evidence/r3-java-object-content-overload-238-target-20260809/target.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issue237 = 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS'
$issue238 = 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD'
$revision = '2026-08-09-actual-docs-source-refactor-continuation-java-object-238-035'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required JSON is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return ($strictUtf8.GetString($bytes) | ConvertFrom-Json)
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required text is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}

function Set-PropertyValue {
  param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value)
  if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
  else { $Object.$Name = $Value }
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value)
  $path = Get-RepoPath -RelativePath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 70), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Write-AtomicText {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][string]$Value)
  $path = Get-RepoPath -RelativePath $RelativePath
  $directory = Split-Path -Parent $path
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, $Value, $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Assert-Target {
  param([Parameter(Mandatory = $true)][bool]$Condition, [Parameter(Mandatory = $true)][string]$Message)
  if (-not $Condition) { throw "238 target registration blocked: $Message" }
}

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson -RelativePath $statePath
$objective = Read-StrictJson -RelativePath $objectivePath
$failureEvidence = 'tools/legado-compat/evidence/contract-legado-java-object-content-overload-pre-fix-20260809-r2.json'
$staticContract = 'tools/legado-compat/evidence/contract-legado-java-object-content-overload.json'
$currentHeadAudit = 'tools/legado-compat/evidence/v2-java-object-content-overload-current-head-audit-20260809-r2.json'
$sourceFix = 'tools/legado-compat/evidence/v2-java-object-content-overload-source-fix-20260809-r2.json'
$fixture = 'tools/legado-compat/fixtures/legado-java-object-content-overload-r2.json'

Assert-Target ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'fixed baseline drifted.'
Assert-Target ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq $issue237) '237 is not the sole active issue before target handoff.'
$issue238Record = @($state.governance.issues | Where-Object { [string]$_.id -eq $issue238 }) | Select-Object -First 1
Assert-Target ($null -ne $issue238Record -and [string]$issue238Record.status -eq 'verifying') '238 must remain verifying while it is only a candidate.'
$preFix = Read-StrictJson -RelativePath $failureEvidence
$contract = Read-StrictJson -RelativePath $staticContract
$audit = Read-StrictJson -RelativePath $currentHeadAudit
$fix = Read-StrictJson -RelativePath $sourceFix
$fixtureObject = Read-StrictJson -RelativePath $fixture
Assert-Target ([string]$preFix.status -eq 'failed' -and [string]$preFix.issueId -eq $issue238 -and -not [bool]$preFix.semanticMatchAllowed) '238 failure witness is invalid.'
Assert-Target ([string]$contract.status -eq 'passed' -and [int]$contract.assertions -eq 20) '238 base contract is invalid.'
Assert-Target ([string]$audit.status -eq 'passed' -and [int]$audit.assertions -ge 13 -and -not [bool]$audit.semanticMatchAllowed) '238 current-head audit is invalid.'
Assert-Target ([string]$fix.status -eq 'source_closed_static_only' -and -not [bool]$fix.semanticMatchAllowed) '238 source-fix evidence is invalid.'
Assert-Target (@($fixtureObject.cases).Count -eq 7) '238 R2 fixture case count drifted.'

$target = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_java_object_content_overload_target'
  status = 'candidate_gate_ready'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  targetRevision = $revision
  objectiveId = [string]$objective.objectiveId
  taskId = 'COMPAT-006'
  activeIssueId = $issue237
  issueId = $issue238
  currentStatus = [string]$issue238Record.status
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  reasonForTarget = '237 的源码静态闭合已交接并保持 verifying；依据当前实际文档和机器事实，238 的对象内容重载现在具备独立失败见证、固定 Legado 原理、V2 三条运行路径消费者矩阵、当前 HEAD 审计和源码修复证据，下一步只允许完成静态队列转移。'
  plan = @(
    [pscustomobject][ordered]@{ id = '238-OC-01'; status = 'completed'; action = '固定 Legado AnalyzeRule NativeObject mContent 的直接键读取、0/false、数组/换行列表、缺失键和 ## replacement 语义。'; evidence = $failureEvidence },
    [pscustomobject][ordered]@{ id = '238-OC-02'; status = 'completed'; action = '登记 ArkWeb、标准 JSVM、Native JSVM 及重复内嵌 native helper 的全部消费者路径；确认对象优先于 JSONPath/CSS coercion。'; evidence = $currentHeadAudit },
    [pscustomobject][ordered]@{ id = '238-OC-03'; status = 'completed'; action = '修复第一份内嵌 native helper 的 replacement 局部作用域、组合/JSONPath/CSS 列表投影替换和重复副本一致性。'; evidence = $sourceFix },
    [pscustomobject][ordered]@{ id = '238-OC-04'; status = 'completed'; action = '执行 20 项基础静态合同、13 项 R2 current-head 审计、UTF-8/JSON/哈希和证据写出检查；保持 semanticMatchAllowed=false。'; evidence = $staticContract },
    [pscustomobject][ordered]@{ id = '238-OC-05'; status = 'in_progress'; action = '完成 237→238 静态转移、注册后一致性和重放幂等审计；转移前不得激活 238，R4 继续 deferred。' }
  )
  currentSubstage = '238-OC-05'
  constraints = [pscustomobject][ordered]@{ runtimeActionsPerformed = @(); semanticMatchAllowed = $false; forbidden = @('458 条运行时批次', '真实端点', '构建、签名、安装、Android/HarmonyOS 设备', 'Legado instrumentation differential') }
  evidencePaths = @($failureEvidence, $staticContract, $currentHeadAudit, $sourceFix, $fixture)
  nextTransition = '仅在 237 verifying 保留、238 证据绑定一致、转移注册与重放幂等审计通过后，原子选择 238 为唯一活动源码议题；静态通过仍不得写成 passed 或 semantic_match。'
}
Write-AtomicJson -RelativePath $TargetEvidencePath -Value $target

$objective.lastReviewedAt = [DateTimeOffset]::UtcNow.ToString('o')
$objective.targetRevision = $revision
$objective.nextAction = '238-OC-05：完成 237→238 静态转移、注册后一致性和重放幂等审计；238 在转移前保持 verifying candidate，R4、运行时、构建和设备验证继续 deferred。'
Set-PropertyValue -Object $objective.continuationTarget -Name 'activeBoundary' -Value 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS 保持 verifying；238 已完成独立失败见证、消费者矩阵、current-head/source-fix 和静态合同，但仍是 candidate_gate_ready，未原子激活。'
Set-PropertyValue -Object $objective.continuationTarget -Name 'nextTransition' -Value '238-OC-01 至 238-OC-04 已完成；下一步仅执行 237→238 静态转移、注册后一致性和重放幂等审计，转移前不得启动 R4。'
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'nextCandidateTargetEvidencePath' -Value $TargetEvidencePath
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'nextCandidateFailureWitnessPath' -Value $failureEvidence
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'nextCandidateCurrentHeadAuditEvidencePath' -Value $currentHeadAudit
Set-PropertyValue -Object $objective.objective.queueSelectionGate -Name 'nextCandidateSourceFixEvidencePath' -Value $sourceFix
Set-PropertyValue -Object $objective.executionTarget -Name 'statement' -Value '在固定 458 条书源与 Legado 提交基线下继续 R2/R3 源码重构。237 保持 verifying；238 的独立失败见证、消费者矩阵、源码修复和静态合同已完成，当前只推进 237→238 静态转移及其幂等审计，不启动 R4。'
$continuationPlan = @($objective.continuationPlan)
if (@($continuationPlan | Where-Object { [string]$_.id -eq '238-OC-01' }).Count -eq 0) {
  $continuationPlan += @($target.plan)
}
Set-PropertyValue -Object $objective -Name 'continuationPlan' -Value $continuationPlan
Write-AtomicJson -RelativePath $objectivePath -Value $objective

$setScript = Join-Path $PSScriptRoot 'Set-LegadoRefactorObjective.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $setScript -StatePath (Get-RepoPath $statePath) -ObjectivePath (Get-RepoPath $objectivePath) -ActiveIssueId $issue237 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'refactor objective attachment failed.' }

Write-Output ("TARGET_REGISTERED issue={0} status={1} activeIssue={2} substage=238-OC-05 evidence={3}" -f $issue238, $target.status, $issue237, $TargetEvidencePath)
