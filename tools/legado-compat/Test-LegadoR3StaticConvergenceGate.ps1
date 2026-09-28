[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/r3-static-convergence-20260809/static-gate.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'

function Get-RepoPath([string]$RelativePath) {
  if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $RelativePath }
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText([string]$Path, [switch]$AllowBom) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing file: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $offset = 0
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    if (-not $AllowBom) { throw "UTF-8 BOM is not allowed: $Path" }
    $offset = 3
  }
  return $strictUtf8.GetString($bytes, $offset, $bytes.Length - $offset)
}

function Read-Json([string]$Path) {
  return (Read-StrictText $Path | ConvertFrom-Json)
}

function Get-PropertyValue([object]$Object, [string]$Name) {
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Get-TextValue([object]$Object, [string]$Name) {
  $value = Get-PropertyValue -Object $Object -Name $Name
  if ($null -eq $value) { return '' }
  return [string]$value
}

function Get-Hash([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Add-Check([System.Collections.Generic.List[object]]$Checks, [string]$Id, [bool]$Passed, [string]$Detail) {
  [void]$Checks.Add([pscustomobject][ordered]@{ id = $Id; passed = $Passed; detail = $Detail })
  if (-not $Passed) { throw "R3_STATIC_GATE_FAILED:${Id}:$Detail" }
}

function Write-AtomicJson([string]$Path, [object]$Value) {
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 40), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

$checks = New-Object 'System.Collections.Generic.List[object]'
$statePath = Get-RepoPath 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = Get-RepoPath 'tools/legado-compat/state/refactor-objective.json'
$state = Read-Json $statePath
$objective = Read-Json $objectivePath
$baseline = $state.baseline
$objectiveBaseline = $objective.baseline
$activeIssue = [string]$state.governance.activeIssueId
$objectiveActiveIssue = Get-TextValue -Object $objective.authority -Name 'activeIssueId'
$objectiveRootActiveIssue = Get-TextValue -Object $objective.objective -Name 'activeIssue'
$queueAudit = $objective.continuationTarget.queueAudit
$queuePreflight = $state.governance.queuePreflight
$activeIssueRecord = @($state.governance.issues | Where-Object { [string]$_.id -eq $activeIssue }) | Select-Object -First 1
Add-Check $checks 'frozen_source_count' ([int]$baseline.sourceCount -eq 458 -and [int]$objectiveBaseline.sourceCount -eq 458) 'machine and objective source counts are 458'
Add-Check $checks 'frozen_source_hash' ([string]$baseline.sourcePackageSha256 -eq $sourceHash -and [string]$objectiveBaseline.sourcePackageSha256 -eq $sourceHash) 'machine and objective source hashes match the frozen package'
Add-Check $checks 'frozen_legado_commit' ([string]$baseline.legadoCommit -eq $legadoCommit -and (& git -C (Get-RepoPath 'legado') rev-parse HEAD 2>$null | Out-String).Trim() -eq $legadoCommit) 'Legado checkout and state use the pinned commit'
Add-Check $checks 'active_issue_binding' (-not [string]::IsNullOrWhiteSpace($activeIssue) -and $objectiveActiveIssue -eq $activeIssue -and $objectiveRootActiveIssue -eq $activeIssue) 'machine state and objective document point to the same active issue'
Add-Check $checks 'active_issue_record' ($null -ne $activeIssueRecord -and [string]$activeIssueRecord.status -eq 'verifying') 'the active source issue exists and remains verifying'
Add-Check $checks 'semantic_match_locked' (-not [bool]$state.governance.semanticMatchAllowed -and -not [bool]$objective.objective.apiCapabilitySettlement.semanticMatchAllowed) 'semantic match remains disabled before R4'
Add-Check $checks 'queue_audit_no_candidate_status' ([string]$queueAudit.status -eq 'preflight_passed_no_candidate' -and [int]$queuePreflight.candidateCount -eq 0 -and [string]$queueAudit.candidateGateStatus -eq 'no_candidate_satisfies_evidence_gate' -and [string]$queueAudit.candidateStatus -eq 'no_candidate_satisfies_evidence_gate') 'queue audit explicitly describes the no-candidate branch'

$activeIssueEvidence = @($activeIssueRecord.evidencePaths | ForEach-Object { if ($null -ne $_) { [string]$_ } } | Where-Object { $_.Length -gt 0 })
$activeEvidenceMissing = @($activeIssueEvidence | Where-Object {
    $path = Get-RepoPath $_
    -not (Test-Path -LiteralPath $path -PathType Leaf)
  })
Add-Check $checks 'active_issue_evidence_registered' ($activeIssueEvidence.Count -ge 4) 'active issue has the required registered evidence set'
Add-Check $checks 'active_issue_evidence_present' ($activeEvidenceMissing.Count -eq 0) 'all active issue evidence paths exist'

$activeEvidenceStatuses = [ordered]@{}
$activePostFixPassed = 0
$activeCurrentHeadPassed = 0
$activeSourceFixRecorded = 0
foreach ($relative in $activeIssueEvidence) {
  $path = Get-RepoPath $relative
  if ([System.IO.Path]::GetExtension($path).ToLowerInvariant() -ne '.json') { continue }
  try {
    $evidence = Read-Json $path
    $status = Get-TextValue -Object $evidence -Name 'status'
    $activeEvidenceStatuses[$relative] = $status
    if ($relative -match '(?i)post[-_ ]?fix' -and $status -in @('passed', 'passed_static_only')) { $activePostFixPassed++ }
    if ($relative -match '(?i)current[-_ ]?head' -and $status -in @('passed', 'passed_static_only')) { $activeCurrentHeadPassed++ }
    if ($relative -match '(?i)source[-_ ]?fix' -and $status -in @('source_closed_static_only', 'passed_static_only', 'passed')) { $activeSourceFixRecorded++ }
  } catch {
    $activeEvidenceStatuses[$relative] = 'parse_error'
  }
}
Add-Check $checks 'active_issue_post_fix_contract' ($activePostFixPassed -gt 0) 'active issue has a passing post-fix contract'
Add-Check $checks 'active_issue_current_head_audit' ($activeCurrentHeadPassed -gt 0) 'active issue has a passing current-head audit'
Add-Check $checks 'active_issue_source_fix_recorded' ($activeSourceFixRecorded -gt 0) 'active issue has a recorded static source fix'

$evidenceRoot = Get-RepoPath 'tools/legado-compat/evidence'
$candidateEvidence = @()
$documentEvidence = @()
foreach ($file in @(Get-ChildItem -LiteralPath $evidenceRoot -Recurse -Filter '*.json' -File)) {
  try { $evidence = Read-Json $file.FullName } catch { continue }
  $kind = Get-TextValue -Object $evidence -Name 'kind'
  $evidenceIssue = Get-TextValue -Object $evidence -Name 'activeIssueId'
  if ($kind -eq 'legado_current_static_source_candidate_gate' -and $evidenceIssue -eq $activeIssue) {
    $candidateEvidence += [pscustomobject]@{ Path = $file.FullName; Evidence = $evidence }
  }
  if ($kind -eq 'legado_active_issue_document_consistency' -and (Get-TextValue -Object $evidence -Name 'issueId') -eq $activeIssue) {
    $documentEvidence += [pscustomobject]@{ Path = $file.FullName; Evidence = $evidence }
  }
}
$candidateRecord = @($candidateEvidence | Sort-Object { [string](Get-TextValue -Object $_.Evidence -Name 'generatedAt') } -Descending) | Select-Object -First 1
$documentRecord = @($documentEvidence | Sort-Object { [string](Get-TextValue -Object $_.Evidence -Name 'generatedAt') } -Descending) | Select-Object -First 1
$requiredEvidence = @()
$candidateRelative = if ($null -ne $candidateRecord) { $candidateRecord.Path.Substring($RepositoryRoot.Length + 1).Replace('\', '/') } else { '' }
$documentRelative = if ($null -ne $documentRecord) { $documentRecord.Path.Substring($RepositoryRoot.Length + 1).Replace('\', '/') } else { '' }
$requiredEvidence += @($candidateRelative, $documentRelative) | Where-Object { $_.Length -gt 0 }
$evidenceStatuses = [ordered]@{}
foreach ($relative in $requiredEvidence) {
  $path = Get-RepoPath $relative
  Add-Check $checks "evidence_present:$relative" (Test-Path -LiteralPath $path -PathType Leaf) 'required evidence file exists'
  $evidence = Read-Json $path
  $evidenceStatuses[$relative] = [string]$evidence.status
}
Add-Check $checks 'candidate_gate_passed_without_candidate' ($null -ne $candidateRecord -and $candidateRecord.Evidence.status -eq 'passed' -and $candidateRecord.Evidence.activeIssueId -eq $activeIssue -and $candidateRecord.Evidence.candidateGateStatus -eq 'no_candidate_satisfies_evidence_gate') 'current active issue candidate gate completed without selecting an unproven issue'
Add-Check $checks 'document_consistency_passed' ($null -ne $documentRecord -and $documentRecord.Evidence.status -eq 'passed_static_only' -and $documentRecord.Evidence.issueId -eq $activeIssue) 'active issue documents agree with machine facts'

$scriptFiles = @(Get-ChildItem -LiteralPath (Get-RepoPath 'tools/legado-compat') -Filter '*.ps1' -File)
$syntaxErrors = New-Object 'System.Collections.Generic.List[object]'
foreach ($file in $scriptFiles) {
  $tokens = $null
  $parseErrors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
  foreach ($errorRecord in @($parseErrors)) {
    [void]$syntaxErrors.Add([pscustomobject]@{ file = $file.Name; line = $errorRecord.Extent.StartLineNumber; message = $errorRecord.Message })
  }
}
Add-Check $checks 'powershell_syntax' ($syntaxErrors.Count -eq 0) ("$($scriptFiles.Count) scripts parsed with zero syntax errors")

$jsonFiles = @(Get-ChildItem -LiteralPath (Get-RepoPath 'tools/legado-compat') -Recurse -Filter '*.json' -File)
$jsonErrors = New-Object 'System.Collections.Generic.List[object]'
foreach ($file in $jsonFiles) {
  try {
    $text = Read-StrictText $file.FullName -AllowBom
    $null = $text | ConvertFrom-Json
  } catch {
    [void]$jsonErrors.Add([pscustomobject]@{ file = $file.Name; message = $_.Exception.Message })
  }
}
Add-Check $checks 'json_parse' ($jsonErrors.Count -eq 0) ("$($jsonFiles.Count) JSON files parsed with zero errors")

$result = [ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_static_convergence_gate'
  status = 'passed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = 458; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  activeIssueId = $activeIssue
  checks = $checks.ToArray()
  evidenceStatuses = $evidenceStatuses
  activeIssueEvidenceStatuses = $activeEvidenceStatuses
  powershell = [ordered]@{ fileCount = $scriptFiles.Count; syntaxErrorCount = $syntaxErrors.Count }
  json = [ordered]@{ fileCount = $jsonFiles.Count; parseErrorCount = $jsonErrors.Count }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_static_convergence_only;R4_runtime_build_device_and_legado_diff_deferred'
  nextGate = 'JDK21_HVIGOR_DEBUG_BUILD_THEN_DEVICE_COLD_START'
  reproductionCommand = 'pwsh -NoLogo -NoProfile -NonInteractive -File tools/legado-compat/Test-LegadoR3StaticConvergenceGate.ps1'
}
Write-AtomicJson (Get-RepoPath $OutputPath) $result
$result | ConvertTo-Json -Depth 20
