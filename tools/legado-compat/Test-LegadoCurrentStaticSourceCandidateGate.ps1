[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/r3-source-queue-preflight-20260809-r2/current-static-candidate-preflight.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$evidenceRoot = (Resolve-Path -LiteralPath (Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).Path
$outputFullPath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot ($OutputPath.Replace('/', '\'))))
$evidencePrefix = $evidenceRoot.TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidencePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Candidate-gate evidence must remain under the evidence directory.'
}

$sourceCount = 458
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Get-PropertyValue {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Get-TextValue {
  param([object]$Object, [string]$Name)
  $value = Get-PropertyValue -Object $Object -Name $Name
  if ($null -eq $value) { return '' }
  return [string]$value
}

function Read-StrictText {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing file: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([string]$Path)
  try { return (Read-StrictText -Path $Path | ConvertFrom-Json) }
  catch { throw "Invalid JSON: $Path; $($_.Exception.Message)" }
}

function Read-EvidenceFile {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing file: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
  if ($extension -in @('.bmp', '.gif', '.jpeg', '.jpg', '.png', '.webp', '.avif', '.pdf', '.hap', '.apk', '.zip', '.bin')) {
    return [pscustomobject][ordered]@{ kind = 'binary'; text = '' }
  }
  $offset = 0
  $kind = 'utf8_text'
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    $offset = 3
    $kind = 'utf8_bom_text'
  }
  try {
    $text = $strictUtf8.GetString($bytes, $offset, $bytes.Length - $offset)
    return [pscustomobject][ordered]@{ kind = $kind; text = $text }
  } catch {
    return [pscustomobject][ordered]@{ kind = 'binary'; text = '' }
  }
}

function Add-Reason {
  param([System.Collections.Generic.List[string]]$Reasons, [string]$Reason)
  if (-not $Reasons.Contains($Reason)) { [void]$Reasons.Add($Reason) }
}

function Test-SourceScope {
  param([string]$IssueId)
  if ($IssueId -match '^ISSUE-(UI|AUTO|DEVICE)-') { return $false }
  if ($IssueId -match '^ISSUE-COMPAT-(FULL-V2|HYPIUM)-') { return $false }
  return $true
}

function Write-AtomicJson {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 50), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$stateRelative = 'tools/legado-compat/state/full-source-validation-state.json'
$objectiveRelative = 'tools/legado-compat/state/refactor-objective.json'
$status = 'failed'
$failure = ''
$evaluations = New-Object 'System.Collections.Generic.List[object]'
$eligible = @()
$state = $null
$objective = $null
$activeIssueId = ''
$targetRevision = ''

try {
  $state = Read-StrictJson -Path (Get-RepoPath $stateRelative)
  $objective = Read-StrictJson -Path (Get-RepoPath $objectiveRelative)
  $baseline = Get-PropertyValue -Object $state -Name 'baseline'
  if ([int](Get-PropertyValue $baseline 'sourceCount') -ne $sourceCount -or
      (Get-TextValue $baseline 'sourcePackageSha256') -ne $sourceHash -or
      (Get-TextValue $baseline 'legadoCommit') -ne $legadoCommit) { throw 'Machine baseline drifted.' }
  $objectiveBaseline = Get-PropertyValue -Object $objective -Name 'baseline'
  if ([int](Get-PropertyValue $objectiveBaseline 'sourceCount') -ne $sourceCount -or
      (Get-TextValue $objectiveBaseline 'sourcePackageSha256') -ne $sourceHash -or
      (Get-TextValue $objectiveBaseline 'legadoCommit') -ne $legadoCommit) { throw 'Objective baseline drifted.' }
  $packagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
  if ((Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToUpperInvariant() -ne $sourceHash) { throw 'Frozen source package hash drifted.' }
  $head = (& git -C (Get-RepoPath 'legado') rev-parse HEAD 2>$null | Out-String).Trim()
  if ($head -ne $legadoCommit) { throw 'Legado checkout is not at the pinned commit.' }

  $governance = Get-PropertyValue -Object $state -Name 'governance'
  $activeIssueId = Get-TextValue $governance 'activeIssueId'
  $targetRevision = Get-TextValue $objective 'targetRevision'
  if ((Get-TextValue $governance 'status') -ne 'running') { throw 'Governance is not running.' }
  $activeIssue = @((Get-PropertyValue $governance 'issues') | Where-Object { (Get-TextValue $_ 'id') -eq $activeIssueId }) | Select-Object -First 1
  if ($null -eq $activeIssue -or (Get-TextValue $activeIssue 'status') -ne 'verifying') { throw 'The current active source issue must remain verifying.' }

  $issues = @((Get-PropertyValue $governance 'issues') | Where-Object { $null -ne $_ })
  $staleVerifying = @($issues | Where-Object {
      (Get-TextValue $_ 'status') -eq 'planned' -and
      $null -ne (Get-PropertyValue $_ 'lastRecovery') -and
      (Get-TextValue (Get-PropertyValue $_ 'lastRecovery') 'reason') -eq 'stale_execution_recovered' -and
      (Get-TextValue (Get-PropertyValue $_ 'lastRecovery') 'priorStatus') -eq 'verifying'
    })
  if ($staleVerifying.Count -gt 0) {
    throw ('STALE_VERIFYING_STATUS_RECOVERY_REQUIRED:{0}' -f ([string]::Join(',', @($staleVerifying | ForEach-Object { [string]$_.id }))))
  }
  foreach ($issue in @($issues | Where-Object {
      (Get-TextValue $_ 'severity') -in @('P0', 'P1') -and
      (Get-TextValue $_ 'id') -ne $activeIssueId -and
      (Get-TextValue $_ 'status') -ne 'passed'
    })) {
    $id = Get-TextValue $issue 'id'
    $stateStatus = Get-TextValue $issue 'status'
    $severity = Get-TextValue $issue 'severity'
    $summary = Get-TextValue $issue 'summary'
    $closeCondition = Get-TextValue $issue 'closeCondition'
    $reasons = New-Object 'System.Collections.Generic.List[string]'
    $evidencePaths = @((Get-PropertyValue $issue 'evidencePaths') | ForEach-Object { if ($null -ne $_) { [string]$_ } } | Where-Object { $_.Length -gt 0 })
    $existingEvidence = New-Object 'System.Collections.Generic.List[string]'
    $evidenceText = New-Object 'System.Text.StringBuilder'
    $failureWitness = $false
    $runtimeEvidence = $false

    if (-not (Test-SourceScope $id)) { Add-Reason $reasons 'outside_source_closure_scope' }
    if ($stateStatus -eq 'verifying') { Add-Reason $reasons 'deferred_r4_verification_item' }
    elseif ($stateStatus -notin @('planned', 'failed')) { Add-Reason $reasons "status_not_source_queue_candidate:$stateStatus" }
    if ([string]::IsNullOrWhiteSpace($summary)) { Add-Reason $reasons 'missing_root_cause_summary' }
    if ([string]::IsNullOrWhiteSpace($closeCondition)) { Add-Reason $reasons 'missing_close_condition' }
    if ($evidencePaths.Count -lt 4) { Add-Reason $reasons 'insufficient_registered_evidence_paths' }

    foreach ($relative in $evidencePaths) {
      $path = if ([System.IO.Path]::IsPathRooted($relative)) { $relative } else { Get-RepoPath $relative }
      if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Add-Reason $reasons "missing_evidence_file:$relative"
        continue
      }
      [void]$existingEvidence.Add($relative)
      try {
        $read = Read-EvidenceFile -Path $path
        if ([string]$read.kind -eq 'binary') {
          Add-Reason $reasons "binary_evidence_file:$relative"
          continue
        }
        $text = [string]$read.text
        [void]$evidenceText.AppendLine($text)
        if ($relative -match '(?i)pre[-_ ]?fix|failure|fixture|contract') { $failureWitness = $true }
        if ($text -match '(?i)runtimeActionsPerformed\s*[:=]\s*\[[^\]]*\S') { $runtimeEvidence = $true }
        if ($text -match '(?i)semanticMatchAllowed\s*[:=]\s*true') { $runtimeEvidence = $true }
      } catch {
        Add-Reason $reasons "unreadable_evidence_file:$relative"
      }
    }
    $joined = $evidenceText.ToString()
    if ($joined -notmatch [regex]::Escape($sourceHash) -or $joined -notmatch [regex]::Escape($legadoCommit) -or $joined -notmatch '(?i)458') { Add-Reason $reasons 'evidence_not_bound_to_frozen_baseline' }
    if ($joined -notmatch '(?i)legado|AnalyzeBy|JsExtensions|AnalyzeRule|Jsoup|JsonPath|ChineseUtils') { Add-Reason $reasons 'missing_fixed_legado_semantic_location' }
    if ($joined -notmatch '(?i)affected|sourceCount|sourcePackageSha256|sourceId|ordinal|书源|规则节点|受影响') { Add-Reason $reasons 'missing_affected_source_set' }
    if (-not $failureWitness -or $joined -notmatch '(?i)failure|fixture|contract|pre[-_ ]?fix|failed|失败') { Add-Reason $reasons 'missing_reproducible_failure_witness' }
    if ($joined -notmatch '(?i)consumer|Analyzer|Rule IR|Matcher|ArkWeb|JSVM|workflow|output|消费者|工作流') { Add-Reason $reasons 'missing_v2_consumer_matrix' }
    if ($joined -notmatch '(?i)closeCondition|close condition|关闭条件|regression|回归') { Add-Reason $reasons 'missing_structured_close_condition' }
    if ($runtimeEvidence) { Add-Reason $reasons 'runtime_or_semantic_match_evidence_present' }

    [void]$evaluations.Add([pscustomobject][ordered]@{
      id = $id
      status = $stateStatus
      severity = $severity
      evidenceCount = $evidencePaths.Count
      existingEvidenceCount = $existingEvidence.Count
      eligible = ($reasons.Count -eq 0)
      reasons = @($reasons.ToArray())
    })
  }
  $eligible = @($evaluations | Where-Object { [bool]$_.eligible } | Sort-Object @{Expression={ if ($_.severity -eq 'P0') { 0 } else { 1 } }}, id)
  $status = 'passed'
} catch {
  $failure = $_.Exception.Message
}

$candidateGateStatus = if ($status -ne 'passed') { 'failed' } elseif ($eligible.Count -eq 0) { 'no_candidate_satisfies_evidence_gate' } else { 'candidate_gate_ready_selection_required' }
$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_current_static_source_candidate_gate'
  status = $status
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveId = if ($null -ne $objective) { Get-TextValue $objective 'objectiveId' } else { 'LEGADO-V2-SOURCE-CLOSURE-R3-20260808' }
  targetRevision = $targetRevision
  activeIssueId = $activeIssueId
  baseline = [pscustomobject][ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  candidateGateStatus = $candidateGateStatus
  candidateIssues = @($eligible | ForEach-Object { [string]$_.id })
  candidateCount = $eligible.Count
  evaluatedCount = $evaluations.Count
  evaluations = $evaluations.ToArray()
  failure = $failure
  reproductionCommand = 'pwsh -NoLogo -NoProfile -NonInteractive -File tools/legado-compat/Test-LegadoCurrentStaticSourceCandidateGate.ps1'
  sourceOfTruth = $stateRelative
  requiredEvidence = @(
    'fixed Legado implementation and exact source rule nodes',
    'affected source and rule-node set bound to the frozen 458-source hash',
    'reproducible failing fixture or static failure contract',
    'V2 Analyzer/Rule IR/Matcher/ArkWeb/JSVM/workflow/output consumer matrix',
    'single primary cause, repair boundary, regression set and close condition'
  )
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_current_static_source_candidate_gate_only;R4_runtime_build_device_and_legado_diff_deferred'
  nextAction = if ($status -ne 'passed') { '保留门禁失败证据，不改变机器队列。' } elseif ($eligible.Count -eq 0) { '保持当前 verifying 源码议题；补齐下一候选五项证据后才允许选择，不启动 R4。' } else { '候选已满足五项静态证据门禁，按 P0 优先、ID 字典序自动选择一个后再登记。' }
}
Write-AtomicJson -Path $outputFullPath -Value $result
$result | ConvertTo-Json -Depth 40
if ($status -ne 'passed') { exit 1 }
