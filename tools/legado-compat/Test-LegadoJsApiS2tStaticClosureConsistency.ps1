[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/r3-jsapi-s2t-static-closure-consistency-20260809/consistency.json'
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
$targetRevision = '2026-08-09-actual-docs-source-refactor-js-api-s2t-default-runtime'
$issueId = 'ISSUE-COMPAT-JSAPI-JAVA-S2T-DEFAULT-RUNTIME'
$evidenceRoot = (Resolve-Path -LiteralPath (Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).Path
$outputFullPath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot ($OutputPath.Replace('/', '\'))))
$evidencePrefix = $evidenceRoot.TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidencePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Consistency evidence must remain under the evidence directory.'
}

$checks = New-Object 'System.Collections.Generic.List[object]'
$assertions = 0
$failures = New-Object 'System.Collections.Generic.List[string]'

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing file: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([string]$RelativePath)
  try { return (Read-StrictText -RelativePath $RelativePath | ConvertFrom-Json) }
  catch { throw "Invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Get-PropertyValue {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return $null }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  return $property.Value
}

function Add-Assertion {
  param([bool]$Condition, [string]$Id, [string]$Message, [string[]]$Evidence = @())
  if (-not $Condition) { [void]$failures.Add("${Id}: $Message") }
  else { $script:assertions++ }
  [void]$checks.Add([pscustomobject][ordered]@{
    id = $Id
    status = if ($Condition) { 'passed' } else { 'failed' }
    detail = $Message
    evidencePaths = @($Evidence)
  })
}

function Get-Sha256 {
  param([string]$RelativePath)
  return (Get-FileHash -LiteralPath (Get-RepoPath $RelativePath) -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Write-AtomicJson {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 30), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$stateRelative = 'tools/legado-compat/state/full-source-validation-state.json'
$objectiveRelative = 'tools/legado-compat/state/refactor-objective.json'
$governanceRelative = 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
$objectiveDocRelative = 'docs/analysis/Legado书源V2源码重构持续目标.md'
$ledgerRelative = 'docs/analysis/Legado书源引擎兼容推进台账.md'
$indexRelative = 'docs/analysis/Legado书源引擎证据索引.md'
$diffRelative = 'docs/analysis/Legado书源引擎差分摘要.md'
$requiredEvidence = @(
  'tools/legado-compat/evidence/r3-jsapi-s2t-default-runtime-target-20260809.json',
  'tools/legado-compat/evidence/contract-legado-jsapi-s2t-default-runtime-pre-fix-20260809.json',
  'tools/legado-compat/evidence/contract-legado-jsapi-s2t-default-runtime-20260809.json',
  'tools/legado-compat/evidence/v2-jsapi-s2t-default-runtime-source-fix-20260809.json',
  'tools/legado-compat/evidence/v2-jsapi-s2t-default-runtime-current-head-audit-20260809-r1/current-head-hash-audit.json'
)

$state = $null
$objective = $null
$status = 'failed'
try {
  $state = Read-StrictJson $stateRelative
  $objective = Read-StrictJson $objectiveRelative
  Add-Assertion ([int]$state.baseline.sourceCount -eq $sourceCount -and [int]$objective.baseline.sourceCount -eq $sourceCount) 'baseline_count' 'State and objective retain 458 sources.' @($stateRelative, $objectiveRelative)
  Add-Assertion ([string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$objective.baseline.sourcePackageSha256 -eq $sourceHash) 'baseline_source_hash' 'State and objective retain the frozen source package hash.' @($stateRelative, $objectiveRelative)
  Add-Assertion ([string]$state.baseline.legadoCommit -eq $legadoCommit -and [string]$objective.baseline.legadoCommit -eq $legadoCommit) 'baseline_legado_commit' 'State and objective retain the frozen Legado commit.' @($stateRelative, $objectiveRelative)
  Add-Assertion ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq $issueId -and [string]$state.governance.status -eq 'running') 'active_issue' 'Machine governance selects S2T as the only active issue.' @($stateRelative)
  $issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId }) | Select-Object -First 1
  Add-Assertion ($null -ne $issue -and [string]$issue.status -eq 'verifying') 'issue_status' 'S2T remains verifying after static closure.' @($stateRelative)
  Add-Assertion ([string]$objective.continuationMode -eq 'R3_JS_API_S2T_DEFAULT_RUNTIME_STATIC_CLOSED_WAIT_R4' -and [string]$objective.executionTarget.currentIssue -eq $issueId) 'objective_mode' 'Objective is static-closed and bound to S2T.' @($objectiveRelative)

  $listedEvidence = @($issue.evidencePaths | ForEach-Object { [string]$_ })
  foreach ($relative in $requiredEvidence) {
    $evidence = Read-StrictJson $relative
    $bound = $listedEvidence -contains $relative
    $isCandidateTarget = $relative -like '*r3-jsapi-s2t-default-runtime-target*'
    $isFailureWitness = $relative -like '*pre-fix*'
    $expectedStatus = if ($isCandidateTarget) { 'candidate_gate_ready' } elseif ($isFailureWitness) { 'failed' } else { 'passed_static_only' }
    $evidenceIssueId = [string](Get-PropertyValue $evidence 'issueId')
    if ($isCandidateTarget) { $evidenceIssueId = [string](Get-PropertyValue $evidence 'candidateIssueId') }
    $runtimeActions = @(Get-PropertyValue $evidence 'runtimeActionsPerformed')
    $semanticMatchAllowed = [bool](Get-PropertyValue $evidence 'semanticMatchAllowed')
    $evidenceRevision = [string](Get-PropertyValue $evidence 'targetRevision')
    $baselineEvidence = Get-PropertyValue $evidence 'baseline'
    $revisionMatches = if ($isFailureWitness) { $evidenceRevision.Length -eq 0 -or $evidenceRevision -eq $targetRevision } else { $evidenceRevision -eq $targetRevision }
    $valid = $bound -and [string]$evidence.status -eq $expectedStatus -and $evidenceIssueId -eq $issueId -and $revisionMatches -and [int](Get-PropertyValue $baselineEvidence 'sourceCount') -eq $sourceCount -and [string](Get-PropertyValue $baselineEvidence 'sourcePackageSha256') -eq $sourceHash -and [string](Get-PropertyValue $baselineEvidence 'legadoCommit') -eq $legadoCommit -and $runtimeActions.Count -eq 0 -and -not $semanticMatchAllowed
    Add-Assertion $valid "evidence_$([System.IO.Path]::GetFileNameWithoutExtension($relative))" "Evidence is bound to the frozen baseline and static-only policy ($expectedStatus)." @($relative, $stateRelative)
  }

  $currentHead = Read-StrictJson $requiredEvidence[4]
  foreach ($hashEntry in @($currentHead.currentHeadHashes)) {
    $path = [string]$hashEntry.path
    $expected = [string]$hashEntry.sha256
    $actual = Get-Sha256 $path
    Add-Assertion ($actual -eq $expected) "source_hash_$([System.IO.Path]::GetFileName($path))" 'Current-head source hash matches the registered audit.' @($path, $requiredEvidence[4])
  }

  $docs = @($governanceRelative, $objectiveDocRelative, $ledgerRelative, $indexRelative, $diffRelative)
  foreach ($doc in $docs) {
    $text = Read-StrictText $doc
    Add-Assertion ($text.Contains($issueId) -and $text.Contains('verifying')) "document_$([System.IO.Path]::GetFileName($doc))" 'Document mirror contains the active issue and verifying status.' @($doc)
  }
  $objectiveText = Read-StrictText $objectiveDocRelative
  Add-Assertion ($objectiveText.Contains('R3-JS-API-S2T-DEFAULT-RUNTIME-STATIC-CLOSED-WAIT-R4') -and $objectiveText.Contains('不得启动 458 条运行时批次')) 'document_static_wait_r4' 'Objective document preserves the static-only boundary and R4 deferral.' @($objectiveDocRelative)

  $packagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
  $actualPackageHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToUpperInvariant()
  Add-Assertion ($actualPackageHash -eq $sourceHash) 'package_hash' 'Pinned source package hash is unchanged.' @($packagePath, $stateRelative)
  $actualLegadoCommit = (& git -C (Get-RepoPath 'legado') rev-parse HEAD 2>$null | Out-String).Trim()
  Add-Assertion ($actualLegadoCommit -eq $legadoCommit) 'legado_commit' 'Legado checkout is unchanged at the pinned commit.' @('legado', $stateRelative)
  $status = if ($failures.Count -eq 0) { 'passed' } else { 'failed' }
} catch {
  [void]$failures.Add($_.Exception.Message)
}

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_jsapi_s2t_static_closure_consistency'
  status = $status
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveId = if ($null -ne $objective) { [string]$objective.objectiveId } else { 'LEGADO-V2-SOURCE-CLOSURE-R3-20260808' }
  targetRevision = $targetRevision
  issueId = $issueId
  baseline = [pscustomobject][ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  assertions = $assertions
  failures = @($failures)
  checks = $checks.ToArray()
  evidencePaths = @($requiredEvidence + $stateRelative, $objectiveRelative, $governanceRelative, $objectiveDocRelative, $ledgerRelative, $indexRelative, $diffRelative)
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_static_evidence_and_document_consistency_only;R4_runtime_differential_build_and_device_deferred'
}
Write-AtomicJson -Path $outputFullPath -Value $result
$result | ConvertTo-Json -Depth 30
if ($status -ne 'passed') { exit 1 }
