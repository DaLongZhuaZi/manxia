[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$TargetEvidencePath = 'tools/legado-compat/evidence/r3-actual-docs-source-refactor-target-20260809-235-text-whitespace/target.json',
  [string]$FailureEvidencePath = 'tools/legado-compat/evidence/contract-legado-jsoup-text-whitespace-pre-fix-20260809.json',
  [string]$ConsumerEvidencePath = 'tools/legado-compat/evidence/contract-legado-jsoup-text-whitespace-consumers-pre-fix-20260809.json'
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
  param([string]$Path, [object]$Value)
  $absolute = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Get-RepoPath -RelativePath $Path }
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
  if (-not $Condition) { throw "235 whitespace consumer registration blocked: $Message" }
}

$statePath = Get-RepoPath -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = Get-RepoPath -RelativePath 'tools/legado-compat/state/refactor-objective.json'
$target = Read-StrictJson -RelativePath $TargetEvidencePath
$failure = Read-StrictJson -RelativePath $FailureEvidencePath
$consumer = Read-StrictJson -RelativePath $ConsumerEvidencePath
$state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$objective = Read-StrictJson -RelativePath 'tools/legado-compat/state/refactor-objective.json'

Assert-Registration ([string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS') 'active issue is not 235.'
Assert-Registration ([string]$target.currentSubstage -eq '235-WS-02' -or
  ([string]$target.currentSubstage -eq '235-WS-03' -and [string]$target.consumerContractPath -eq $ConsumerEvidencePath)) 'target is not at WS-02 or an idempotent WS-03 recovery state.'
Assert-Registration ([string]$failure.status -eq 'failed' -and [string]$consumer.status -eq 'failed') 'failure or consumer contract status is not failed-before.'
Assert-Registration ([string]$consumer.rootCause -like 'A single missing Jsoup-compatible*') 'consumer contract did not identify the shared root cause.'
Assert-Registration (@($consumer.consumerMatrix).Count -eq 6) 'consumer matrix must contain six paths.'

Set-PropertyValue -Object $target -Name 'lastUpdatedAt' -Value ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue -Object $target -Name 'consumerContractPath' -Value $ConsumerEvidencePath
Set-PropertyValue -Object $target -Name 'consumerContractStatus' -Value 'failed_before_mapping_registered'
Set-PropertyValue -Object $target -Name 'currentSubstage' -Value '235-WS-03'
$targetPlan = @($target.plan)
$ws02 = $targetPlan | Where-Object { [string]$_.id -eq '235-WS-02' } | Select-Object -First 1
$ws03 = $targetPlan | Where-Object { [string]$_.id -eq '235-WS-03' } | Select-Object -First 1
Assert-Registration ($null -ne $ws02 -and $null -ne $ws03) 'target plan does not contain WS-02 and WS-03.'
Set-PropertyValue -Object $ws02 -Name 'status' -Value 'completed'
Set-PropertyValue -Object $ws02 -Name 'completedEvidence' -Value $ConsumerEvidencePath
Set-PropertyValue -Object $ws03 -Name 'status' -Value 'in_progress'
Set-PropertyValue -Object $ws03 -Name 'startedEvidence' -Value $ConsumerEvidencePath
Write-AtomicJson -Path $TargetEvidencePath -Value $target

$plan = @($objective.continuationPlan)
$objectiveWs02 = $plan | Where-Object { [string]$_.id -eq '235-WS-02' } | Select-Object -First 1
$objectiveWs03 = $plan | Where-Object { [string]$_.id -eq '235-WS-03' } | Select-Object -First 1
Assert-Registration ($null -ne $objectiveWs02 -and $null -ne $objectiveWs03) 'objective plan does not contain WS-02 and WS-03.'
Set-PropertyValue -Object $objectiveWs02 -Name 'status' -Value 'completed'
Set-PropertyValue -Object $objectiveWs02 -Name 'completedEvidence' -Value $ConsumerEvidencePath
Set-PropertyValue -Object $objectiveWs03 -Name 'status' -Value 'in_progress'
Set-PropertyValue -Object $objectiveWs03 -Name 'startedEvidence' -Value $ConsumerEvidencePath
$objective.lastReviewedAt = [DateTimeOffset]::UtcNow.ToString('o')
$objective.nextAction = '执行 235-WS-03：新增共享 LegadoTextAccumulator 并跨 DOM、字符串回退、ArkWeb 统一 text/ownText 与 :contains/:matches 输入；先保持未知语法 fail-closed，不启动 R4。'
Write-AtomicJson -Path $objectivePath -Value $objective

$objectiveDocument = Read-StrictText -RelativePath 'docs/analysis/Legado书源V2源码重构持续目标.md'
$objectiveDocument = $objectiveDocument.Replace('当前子阶段：`235-WS-01` 失败前合同已登记；唯一下一步为 `235-WS-02` 消费者映射与 preserve-whitespace 边界审计。', '当前子阶段：`235-WS-01` 失败前合同与 `235-WS-02` 消费者矩阵已登记；唯一下一步为 `235-WS-03` 共享语义实现。')
$objectiveDocument = $objectiveDocument.Replace('2. 将失败合同映射到 `HTMLElement`/`Matcher`、超大文档字符串回退、ArkWeb `legadoOwnText` 和四类文本伪类消费者；若出现第二主因，先登记新议题，不叠加修复。', '2. `235-WS-02` 已将失败合同映射到 `HTMLElement`/`Matcher`、超大文档字符串回退、ArkWeb `legadoOwnText` 和四类文本伪类消费者，并确认唯一主因为缺少共享 Jsoup 文本累加器。')
$newline = if ($objectiveDocument.Contains("`r`n")) { "`r`n" } else { "`n" }
Write-AtomicText -RelativePath 'docs/analysis/Legado书源V2源码重构持续目标.md' -Value ($objectiveDocument.Replace("`n", $newline))

$setScript = Join-Path $PSScriptRoot 'Set-LegadoRefactorObjective.ps1'
& $setScript -StatePath $statePath -ObjectivePath $objectivePath -ActiveIssueId 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' | Out-Null
if (-not $?) { throw 'refactor objective attachment failed.' }
$updateScript = Join-Path $PSScriptRoot 'Update-LegadoGovernanceState.ps1'
& $updateScript -StatePath $statePath -IssueId 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -IssueStatus verifying -TaskId 'COMPAT-006' -Summary '235-WS-02 消费者矩阵已登记：固定 Legado 的 text/ownText 规范化和 preserve-whitespace 边界，与 DOM、字符串回退、ArkWeb 六条 V2 路径逐项对照；当前进入 235-WS-03 共享语义实现。R4、运行时、构建和设备验证仍延期。' -EvidencePath @($TargetEvidencePath, $FailureEvidencePath, $ConsumerEvidencePath) | Out-Null
if (-not $?) { throw 'governance state refresh failed.' }

$refreshed = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$refreshedObjective = Read-StrictJson -RelativePath 'tools/legado-compat/state/refactor-objective.json'
Assert-Registration ([string]$refreshed.governance.activeIssueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS') 'active issue was not preserved.'
Assert-Registration ([string]$refreshedObjective.nextAction -like '执行 235-WS-03*') 'next action was not advanced to WS-03.'
Write-Output ("CONSUMER_CONTRACT_REGISTERED issue={0} ws02=completed ws03=in_progress evidence={1}" -f $refreshed.governance.activeIssueId, $ConsumerEvidencePath)
