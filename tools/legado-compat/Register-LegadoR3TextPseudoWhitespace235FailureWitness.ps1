[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$TargetEvidencePath = 'tools/legado-compat/evidence/r3-actual-docs-source-refactor-target-20260809-235-text-whitespace/target.json',
  [string]$FailureEvidencePath = 'tools/legado-compat/evidence/contract-legado-jsoup-text-whitespace-pre-fix-20260809.json'
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
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing JSON: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes) | ConvertFrom-Json
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing text: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 40), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Write-AtomicText {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, $Value, $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
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
  param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name, [object]$Value)
  if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value }
  else { $Object.$Name = $Value }
}

function Assert-Witness {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "235 whitespace failure witness registration blocked: $Message" }
}

$statePath = Get-RepoPath -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = Get-RepoPath -RelativePath 'tools/legado-compat/state/refactor-objective.json'
$target = Read-StrictJson -RelativePath $TargetEvidencePath
$failure = Read-StrictJson -RelativePath $FailureEvidencePath
$state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$objective = Read-StrictJson -RelativePath 'tools/legado-compat/state/refactor-objective.json'

Assert-Witness ([string]$target.issueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -and [string]$target.status -eq 'active') 'target evidence is not the active 235 target.'
Assert-Witness ([string]$failure.issueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -and [string]$failure.status -eq 'failed') 'failure evidence is not a failed-before witness.'
Assert-Witness ([string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -and [string]$state.governance.activeTaskId -eq 'COMPAT-006') 'machine queue moved during witness registration.'
Assert-Witness ([string]$objective.targetRevision -eq [string]$target.targetRevision) 'objective and target evidence revisions differ.'
Assert-Witness (-not [bool]$failure.semanticMatchAllowed -and @($failure.runtimeActionsPerformed).Count -eq 0) 'failure witness contains a forbidden runtime conclusion.'

Set-PropertyValue -Object $target -Name 'lastUpdatedAt' -Value ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue -Object $target -Name 'failureContractPath' -Value $FailureEvidencePath
Set-PropertyValue -Object $target -Name 'failureContractStatus' -Value 'failed_before_witness_registered'
Set-PropertyValue -Object $target -Name 'currentSubstage' -Value '235-WS-02'
$targetPlan = @($target.plan)
$ws01 = $targetPlan | Where-Object { [string]$_.id -eq '235-WS-01' } | Select-Object -First 1
$ws02 = $targetPlan | Where-Object { [string]$_.id -eq '235-WS-02' } | Select-Object -First 1
Assert-Witness ($null -ne $ws01 -and $null -ne $ws02) 'target plan does not contain WS-01 and WS-02.'
Set-PropertyValue -Object $ws01 -Name 'status' -Value 'completed'
Set-PropertyValue -Object $ws01 -Name 'completedEvidence' -Value $FailureEvidencePath
Set-PropertyValue -Object $ws02 -Name 'status' -Value 'in_progress'
Set-PropertyValue -Object $ws02 -Name 'startedEvidence' -Value $FailureEvidencePath
Write-AtomicJson -Path (Get-RepoPath -RelativePath $TargetEvidencePath) -Value $target

$plan = @($objective.continuationPlan)
$objectiveWs01 = $plan | Where-Object { [string]$_.id -eq '235-WS-01' } | Select-Object -First 1
$objectiveWs02 = $plan | Where-Object { [string]$_.id -eq '235-WS-02' } | Select-Object -First 1
Assert-Witness ($null -ne $objectiveWs01 -and $null -ne $objectiveWs02) 'objective plan does not contain WS-01 and WS-02.'
Set-PropertyValue -Object $objectiveWs01 -Name 'status' -Value 'completed'
Set-PropertyValue -Object $objectiveWs01 -Name 'completedEvidence' -Value $FailureEvidencePath
Set-PropertyValue -Object $objectiveWs02 -Name 'status' -Value 'in_progress'
Set-PropertyValue -Object $objectiveWs02 -Name 'startedEvidence' -Value $FailureEvidencePath
$objective.lastReviewedAt = [DateTimeOffset]::UtcNow.ToString('o')
$objective.nextAction = '执行 235-WS-02：把失败合同映射到 HTMLElement/Matcher、超大文档字符串回退、ArkWeb legadoOwnText 和四类文本伪类消费者，确认唯一主因与 preserve-whitespace 边界；R4 运行时、构建、安装、设备和 Legado 差分仍不启动。'
Write-AtomicJson -Path $objectivePath -Value $objective

$objectiveDocumentPath = Get-RepoPath -RelativePath 'docs/analysis/Legado书源V2源码重构持续目标.md'
$objectiveDocument = Read-StrictText -RelativePath 'docs/analysis/Legado书源V2源码重构持续目标.md'
$substageLine = '当前子阶段：`235-WS-01` 失败前合同已登记；唯一下一步为 `235-WS-02` 消费者映射与 preserve-whitespace 边界审计。'
if (-not $objectiveDocument.Contains($substageLine)) {
  $marker = '### 235-TP-03 细化目标：Jsoup 空白规范化'
  $objectiveDocument = $objectiveDocument.Replace($marker, $marker + "`n`n" + $substageLine)
}
$objectiveDocument = $objectiveDocument.Replace('1. 先固定 Legado Jsoup 1.16.2 `text()`/`ownText()` 的连续空白、换行、制表、NBSP、相邻文本节点和 preserve-whitespace 边界，形成可重复失败合同。', '1. `235-WS-01` 已固定 Legado Jsoup 1.16.2 `text()`/`ownText()` 的连续空白、换行、制表、NBSP、相邻文本节点和 preserve-whitespace 边界，并登记失败前合同。')
$newline = if ($objectiveDocument.Contains("`r`n")) { "`r`n" } else { "`n" }
Write-AtomicText -Path $objectiveDocumentPath -Value ($objectiveDocument.Replace("`n", $newline))

$setScript = Join-Path $PSScriptRoot 'Set-LegadoRefactorObjective.ps1'
& $setScript -StatePath $statePath -ObjectivePath $objectivePath -ActiveIssueId 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' | Out-Null
if (-not $?) { throw 'refactor objective attachment failed.' }
$updateScript = Join-Path $PSScriptRoot 'Update-LegadoGovernanceState.ps1'
& $updateScript -StatePath $statePath -IssueId 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -IssueStatus verifying -TaskId 'COMPAT-006' -Summary '235-WS-01 失败前合同已登记：Jsoup text/ownText 空白规范化在 DOM、字符串回退和 ArkWeb 仍有统一语义缺口；当前转入 235-WS-02 消费者映射与 preserve-whitespace 边界审计。R4、运行时、构建和设备验证仍延期。' -EvidencePath @($TargetEvidencePath, $FailureEvidencePath) | Out-Null
if (-not $?) { throw 'governance state refresh failed.' }

$refreshed = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$refreshedObjective = Read-StrictJson -RelativePath 'tools/legado-compat/state/refactor-objective.json'
Assert-Witness ([string]$refreshed.governance.activeIssueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS') 'active issue was not preserved.'
Assert-Witness ([string]$refreshedObjective.nextAction -like '执行 235-WS-02*') 'next action was not advanced to WS-02.'
Write-Output ("FAILURE_WITNESS_REGISTERED issue={0} ws01=completed ws02=in_progress evidence={1}" -f $refreshed.governance.activeIssueId, $FailureEvidencePath)
