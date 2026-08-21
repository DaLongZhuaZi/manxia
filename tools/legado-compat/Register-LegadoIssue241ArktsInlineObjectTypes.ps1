[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$BuildEvidenceDirectory = 'tools/legado-compat/evidence/r4-build-device-20260809',
  [string]$RegistrationEvidencePath = 'tools/legado-compat/evidence/r4-build-device-20260809/issue-241-registration.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$sourceCount = 458
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-241-ARKTS-INLINE-OBJECT-TYPES'
$taskId = 'COMPAT-241'
$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$failurePath = Join-Path $BuildEvidenceDirectory 'issue-241-build-failure.json'
$stderrPath = Join-Path $BuildEvidenceDirectory 'build.stderr.log'
$stdoutPath = Join-Path $BuildEvidenceDirectory 'build.stdout.log'

function Get-RepositoryPath([string]$RelativePath) {
  if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $RelativePath }
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson([string]$RelativePath) {
  $path = Get-RepositoryPath $RelativePath
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes) | ConvertFrom-Json
}

function Set-PropertyValue([object]$Object, [string]$Name, [object]$Value) {
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
  else { $property.Value = $Value }
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepositoryPath $RelativePath
  $directory = Split-Path -Parent $path
  [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 80), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Get-BuildErrorSummary {
  $lines = @()
  foreach ($relativePath in @($stderrPath, $stdoutPath)) {
    $path = Get-RepositoryPath $relativePath
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      $lines += [System.IO.File]::ReadAllText($path, $strictUtf8) -split "`r?`n"
    }
  }
  $matches = @($lines | Where-Object { $_ -match 'ArkTS Compiler Error|Object literals cannot be used as type declarations|Object literal must correspond to some explicitly declared class or interface|COMPILE RESULT:FAIL|BUILD FAILED' })
  return @($matches | Select-Object -Unique)
}

$state = Read-StrictJson $statePath
$objective = Read-StrictJson $objectivePath
if ([int]$state.baseline.sourceCount -ne $sourceCount -or [string]$state.baseline.sourcePackageSha256 -ne $sourceHash -or [string]$state.baseline.legadoCommit -ne $legadoCommit) {
  throw 'ISSUE241_REGISTRATION_BLOCKED: frozen baseline drifted.'
}

$failure = [ordered]@{
  schemaVersion = 1
  kind = 'legado_issue_241_arkts_inline_object_types_build_failure'
  status = 'failed'
  issueId = $issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  buildEvidenceDirectory = $BuildEvidenceDirectory
  buildStdoutPath = (Join-Path $BuildEvidenceDirectory 'build.stdout.log')
  buildStderrPath = (Join-Path $BuildEvidenceDirectory 'build.stderr.log')
  primaryCause = [ordered]@{
    classification = 'arkts_type_system'
    statement = 'ArkTS compilation rejects inline object return types and untyped nested object literals in the Legado CSS/parser helpers; the implementation must use explicit named interfaces or classes.'
  }
  affectedFiles = @(
    'entry/src/main/ets/libs/htmlparser/Matcher.ets',
    'entry/src/main/ets/libs/htmlparser/HTMLElement.ets',
    'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
  )
  compilerErrorCount = 18
  compilerErrorSummary = Get-BuildErrorSummary
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  closeCondition = 'Named result contracts compile under ArkTS with zero errors, parser behavior remains unchanged, static convergence and final debug build pass, and no new compiler diagnostics are introduced.'
  reproductionCommand = "JDK21_HVIGOR assembleApp; evidence=$BuildEvidenceDirectory"
}
Write-AtomicJson $failurePath $failure

$issues = @($state.governance.issues)
$issue = @($issues | Where-Object { [string]$_.id -eq $issueId }) | Select-Object -First 1
if ($null -eq $issue) {
  $issue = [pscustomobject][ordered]@{
    id = $issueId
    taskId = $taskId
    status = 'running'
    severity = 'P0'
    retryable = $true
    attempts = 1
    summary = 'R4 debug build exposed 18 ArkTS compiler errors caused by inline object return types and untyped nested result literals in the Legado CSS/parser path.'
    closeCondition = $failure.closeCondition
    evidencePaths = @($failurePath, 'entry/src/main/ets/libs/htmlparser/Matcher.ets', 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets', 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets')
    lastUpdatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
  $issues += $issue
} else {
  Set-PropertyValue $issue 'status' 'running'
  Set-PropertyValue $issue 'attempts' ([int]$issue.attempts + 1)
  Set-PropertyValue $issue 'lastUpdatedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
}
Set-PropertyValue $state.governance 'issues' $issues
$task = @($state.governance.tasks | Where-Object { [string]$_.id -eq $taskId }) | Select-Object -First 1
if ($null -eq $task) {
  $task = [pscustomobject][ordered]@{ id = $taskId; status = 'running'; attempts = 1; retryable = $true; lastUpdatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
  Set-PropertyValue $state.governance 'tasks' (@($state.governance.tasks) + @($task))
} else {
  Set-PropertyValue $task 'status' 'running'
  Set-PropertyValue $task 'attempts' ([int]$task.attempts + 1)
  Set-PropertyValue $task 'lastUpdatedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
}
Set-PropertyValue $state.governance 'activeIssueId' $issueId
Set-PropertyValue $state.governance 'activeTaskId' 'COMPAT-006'
Set-PropertyValue $state.governance 'status' 'running'
Set-PropertyValue $state.governance 'currentSourceClosureBoundary' $issueId
Set-PropertyValue $state.governance 'semanticMatchAllowed' $false
Set-PropertyValue $state.governance 'runtimeActionsPerformed' @()
Set-PropertyValue $state 'updatedAt' ([DateTimeOffset]::UtcNow.ToString('o'))

$objective.targetRevision = '2026-08-09-r4-build-arkts-type-errors-issue241'
Set-PropertyValue $objective 'lastReviewedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue $objective 'nextAction' '先修复 ISSUE-COMPAT-241 的 ArkTS 命名类型合同；修复后重新执行定向静态合同和 JDK21 Hvigor 构建，再进入真机门禁。'
Set-PropertyValue $objective.authority 'activeIssueId' $issueId
Set-PropertyValue $objective.objective 'currentWorkstream' 'R4-ISSUE-241-ARKTS-TYPED-RESULT-CONTRACTS'
Set-PropertyValue $objective.objective 'activeIssue' $issueId
Set-PropertyValue $objective.executionTarget 'currentIssue' $issueId
Set-PropertyValue $objective.executionTarget 'statement' '围绕构建暴露的唯一 ArkTS 类型根因完成命名结果合同重构；禁止以关闭编译检查或旧执行器回退掩盖错误。'
Set-PropertyValue $objective.executionTarget 'nextIssues' @()
Set-PropertyValue $objective.continuationTarget 'activeBoundary' "$issueId 保持 running：ArkTS 编译错误尚未修复。"
Set-PropertyValue $objective.continuationTarget 'nextTransition' '修复命名类型合同后重新构建；构建通过才允许真机安装。'
Set-PropertyValue $objective.continuationTarget.queueAudit 'status' 'r4_build_failure_issue_registered'
Set-PropertyValue $objective.continuationTarget.queueAudit 'currentAnchor' $issueId
Set-PropertyValue $objective.continuationTarget.queueAudit 'selectedIssue' $issueId
Set-PropertyValue $objective.continuationTarget.queueAudit 'candidateStatus' 'build_failed'
Set-PropertyValue $objective.continuationTarget.queueAudit 'candidateFailureWitnessPath' $failurePath

Import-Module -Name (Get-RepositoryPath 'tools/legado-compat/LegadoFullSourceState.psm1') -Force
Sync-LegadoStateDerivedFields -State $state
Write-LegadoStateCheckpoint -Path (Get-RepositoryPath $statePath) -State $state -Depth 80
Write-AtomicJson $objectivePath $objective

& pwsh -NoLogo -NoProfile -NonInteractive -File (Get-RepositoryPath 'tools/legado-compat/Invoke-LegadoCompatibility.ps1') -RefreshDocumentsOnly | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Issue 241 document refresh failed.' }

$registration = [ordered]@{
  schemaVersion = 1
  kind = 'legado_issue_241_arkts_inline_object_types_registration'
  status = 'registered_running'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  issueId = $issueId
  taskId = $taskId
  baseline = $failure.baseline
  failureWitnessPath = $failurePath
  machineIssueStatus = 'running'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  nextGate = 'named-type-fix-then-jdk21-build'
}
Write-AtomicJson $RegistrationEvidencePath $registration
$registration | ConvertTo-Json -Depth 20
