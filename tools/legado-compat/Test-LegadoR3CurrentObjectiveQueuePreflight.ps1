[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/r3-source-queue-preflight-20260809/current-objective-preflight.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path

$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$activeIssueId = 'ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH'
$stateRelative = 'tools/legado-compat/state/full-source-validation-state.json'
$objectiveRelative = 'tools/legado-compat/state/refactor-objective.json'
$sourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "required file is missing: $RelativePath"
  }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $utf8Strict.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  try {
    return (Read-StrictText -RelativePath $RelativePath | ConvertFrom-Json)
  } catch {
    throw "invalid JSON: $RelativePath; $($_.Exception.Message)"
  }
}

function Get-PropertyValue {
  param([object]$Object, [Parameter(Mandatory = $true)][string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Get-TextValue {
  param([object]$Object, [Parameter(Mandatory = $true)][string]$Name)
  $value = Get-PropertyValue -Object $Object -Name $Name
  if ($null -eq $value) { return '' }
  return [string]$value
}

function Get-Sha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  $algorithm = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($algorithm.ComputeHash([System.IO.File]::ReadAllBytes($Path)))).Replace('-', '')
  } finally {
    $algorithm.Dispose()
  }
}

function Write-AtomicJson {
  param(
    [Parameter(Mandatory = $true)][string]$RelativePath,
    [Parameter(Mandatory = $true)][object]$Value
  )
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 50), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      [System.IO.File]::Delete($temporaryPath)
    }
  }
}

function Add-Reason {
  param([System.Collections.Generic.List[string]]$Reasons, [string]$Reason)
  if (-not $Reasons.Contains($Reason)) {
    [void]$Reasons.Add($Reason)
  }
}

$state = Read-StrictJson -RelativePath $stateRelative
$objective = Read-StrictJson -RelativePath $objectiveRelative
$sourcePackageFullPath = [System.IO.Path]::GetFullPath($sourcePackagePath)
if (-not (Test-Path -LiteralPath $sourcePackageFullPath -PathType Leaf)) {
  throw "frozen source package is missing: $sourcePackagePath"
}

$baseline = Get-PropertyValue -Object $state -Name 'baseline'
if ([int](Get-PropertyValue -Object $baseline -Name 'sourceCount') -ne 458 -or
    (Get-TextValue -Object $baseline -Name 'sourcePackageSha256') -ne $baselineHash -or
    (Get-TextValue -Object $baseline -Name 'legadoCommit') -ne $legadoCommit) {
  throw 'machine baseline does not match the frozen objective baseline.'
}
if ((Get-Sha256 -Path $sourcePackageFullPath) -ne $baselineHash) {
  throw 'frozen source package hash drifted.'
}
$legadoHead = (& git -C (Get-RepoPath 'legado') rev-parse HEAD 2>$null | Out-String).Trim()
if ($legadoHead -ne $legadoCommit) {
  throw 'Legado checkout is not at the fixed commit.'
}

$governance = Get-PropertyValue -Object $state -Name 'governance'
if ((Get-TextValue -Object $governance -Name 'activeIssueId') -ne $activeIssueId -or
    (Get-TextValue -Object $governance -Name 'status') -ne 'running') {
  throw 'the machine queue is not anchored to the expected 037 running governance task.'
}
$issues = @((Get-PropertyValue -Object $governance -Name 'issues')) | Where-Object { $null -ne $_ }
$activeIssue = @($issues | Where-Object { (Get-TextValue -Object $_ -Name 'id') -eq $activeIssueId }) | Select-Object -First 1
if ($null -eq $activeIssue -or (Get-TextValue -Object $activeIssue -Name 'status') -ne 'verifying') {
  throw '037 must remain the sole verifying source-closure anchor during preflight.'
}

$evaluations = New-Object 'System.Collections.Generic.List[object]'
foreach ($issue in @($issues | Where-Object {
    (Get-TextValue -Object $_ -Name 'severity') -in @('P0', 'P1') -and
    (Get-TextValue -Object $_ -Name 'id') -ne $activeIssueId -and
    (Get-TextValue -Object $_ -Name 'status') -ne 'passed'
  })) {
  $id = Get-TextValue -Object $issue -Name 'id'
  $status = Get-TextValue -Object $issue -Name 'status'
  $severity = Get-TextValue -Object $issue -Name 'severity'
  $summary = Get-TextValue -Object $issue -Name 'summary'
  $closeCondition = Get-TextValue -Object $issue -Name 'closeCondition'
  $evidence = @((Get-PropertyValue -Object $issue -Name 'evidencePaths')) | ForEach-Object { [string]$_ } | Where-Object { $_.Length -gt 0 }
  $reasons = New-Object 'System.Collections.Generic.List[string]'

  if ($status -eq 'verifying') {
    Add-Reason -Reasons $reasons -Reason 'deferred_r4_verification_item'
  } elseif ($status -notin @('planned', 'failed')) {
    Add-Reason -Reasons $reasons -Reason "status_not_source_queue_candidate:$status"
  }
  if ([string]::IsNullOrWhiteSpace($summary)) { Add-Reason -Reasons $reasons -Reason 'missing_root_cause_summary' }
  if ([string]::IsNullOrWhiteSpace($closeCondition)) { Add-Reason -Reasons $reasons -Reason 'missing_close_condition' }
  if (@($evidence).Count -lt 4) { Add-Reason -Reasons $reasons -Reason 'insufficient_registered_evidence_paths' }

  $existingEvidence = New-Object 'System.Collections.Generic.List[string]'
  $evidenceText = New-Object 'System.Text.StringBuilder'
  foreach ($pathValue in $evidence) {
    $candidatePath = $pathValue
    if (-not [System.IO.Path]::IsPathRooted($candidatePath)) {
      $candidatePath = Get-RepoPath $candidatePath
    }
    if (-not (Test-Path -LiteralPath $candidatePath -PathType Leaf)) {
      Add-Reason -Reasons $reasons -Reason "missing_evidence_file:$pathValue"
      continue
    }
    [void]$existingEvidence.Add($pathValue)
    try {
      [void]$evidenceText.Append([System.IO.File]::ReadAllText($candidatePath, $utf8Strict))
    } catch {
      Add-Reason -Reasons $reasons -Reason "unreadable_evidence_file:$pathValue"
    }
  }
  $joinedEvidence = $evidenceText.ToString()
  if ($joinedEvidence -notmatch '(?i)legado|analyzer|analyzebyjsoup|bookinfo|jsoup') {
    Add-Reason -Reasons $reasons -Reason 'missing_fixed_legado_semantic_location'
  }
  if ($joinedEvidence -notmatch '(?i)pre[-_ ]?fix|failure|fixture|contract|failed') {
    Add-Reason -Reasons $reasons -Reason 'missing_reproducible_failure_witness'
  }
  if ($joinedEvidence -notmatch '(?i)affected|sourceCount|sourceId|ordinal|书源|规则节点') {
    Add-Reason -Reasons $reasons -Reason 'missing_affected_source_set'
  }
  if ($joinedEvidence -notmatch '(?i)consumer|workflow|analyzer|matcher|arkweb|jsvm|transport|output') {
    Add-Reason -Reasons $reasons -Reason 'missing_v2_consumer_matrix'
  }

  [void]$evaluations.Add([pscustomobject][ordered]@{
      id = $id
      status = $status
      severity = $severity
      evidenceCount = @($evidence).Count
      existingEvidenceCount = $existingEvidence.Count
      eligible = $reasons.Count -eq 0
      reasons = @($reasons.ToArray())
    })
}

$eligible = @($evaluations | Where-Object { [bool]$_.eligible })
$candidateGateStatus = if ($eligible.Count -eq 0) { 'no_candidate_satisfies_evidence_gate' } else { 'candidate_gate_ready_selection_required' }
$outputRelative = $OutputPath.Replace('\', '/')
$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_current_objective_queue_preflight'
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveId = Get-TextValue -Object $objective -Name 'objectiveId'
  targetRevision = '2026-08-09-actual-docs-source-refactor-queue-preflight-037'
  activeIssueId = $activeIssueId
  baseline = [pscustomobject][ordered]@{
    sourceCount = 458
    sourcePackageSha256 = $baselineHash
    legadoCommit = $legadoCommit
  }
  candidateGateStatus = $candidateGateStatus
  candidateIssues = @($eligible | ForEach-Object { [string]$_.id })
  candidateCount = $eligible.Count
  evaluatedCount = $evaluations.Count
  reproductionCommand = 'pwsh -NoLogo -NoProfile -NonInteractive -File tools/legado-compat/Test-LegadoR3CurrentObjectiveQueuePreflight.ps1'
  sourceOfTruth = 'tools/legado-compat/state/full-source-validation-state.json'
  evaluations = $evaluations.ToArray()
  requiredEvidence = @(
    'fixed Legado implementation and exact source rule nodes',
    'affected source and rule-node set bound to the frozen 458-source hash',
    'reproducible failing fixture or static failure contract',
    'V2 Analyzer/Rule IR/Matcher/ArkWeb/JSVM/workflow/output consumer matrix',
    'single primary cause, repair boundary, regression set and close condition'
  )
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_current_objective_queue_preflight_static_only;037_remains_verifying_when_no_candidate_meets_gate;R4_runtime_build_device_and_legado_diff_deferred'
  nextAction = if ($eligible.Count -eq 0) {
    '保持 ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH verifying；补齐下一候选的五项证据门禁后才可原子选择，不启动 R4。'
  } else {
    '候选已满足五项静态证据门禁；仍需通过唯一活动议题注册脚本原子选择后才能开始源码修复。'
  }
}

Write-AtomicJson -RelativePath $OutputPath -Value $result
$result | ConvertTo-Json -Depth 30
