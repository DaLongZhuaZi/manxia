[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RunId = 'r3-harness-023-transition-consistency-20260808-r1',
  [string]$OutputPath = '',
  [switch]$RequireRegistration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($RepositoryRoot.Length -eq 0) {
  $RepositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$evidenceRoot = (Resolve-Path -LiteralPath (Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).Path
$runDirectory = Join-Path $evidenceRoot $RunId
if ($OutputPath.Length -eq 0) {
  $OutputPath = Join-Path $runDirectory 'transition-consistency.json'
}
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$evidencePrefix = $evidenceRoot.TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidencePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Transition consistency evidence must remain under the evidence directory.'
}
if (-not (Test-Path -LiteralPath $runDirectory)) {
  [System.IO.Directory]::CreateDirectory($runDirectory) | Out-Null
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:checks = New-Object 'System.Collections.Generic.List[object]'
$script:assertions = 0

function Get-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Get-Issue {
  param([object[]]$Issues, [string]$Id)
  foreach ($issue in $Issues) {
    if ([string](Get-PropertyValue -Object $issue -Name 'id') -eq $Id) { return $issue }
  }
  return $null
}

function Read-StrictUtf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw "Required file is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  try { return (Read-StrictUtf8Text -Path $Path | ConvertFrom-Json) }
  catch { throw "Invalid JSON: $Path; $($_.Exception.Message)" }
}

function Get-Sha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-Gate {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
  $script:assertions++
}

function Add-Check {
  param([string]$Id, [string]$Detail, [string[]]$Evidence = @())
  [void]$script:checks.Add([pscustomobject][ordered]@{
      id = $Id
      status = 'passed'
      detail = $Detail
      evidencePaths = @($Evidence)
    })
}

$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$objectivePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\refactor-objective.json'
$queueGatePath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\r3-harness-023-queue-gate-20260808-r1\r3-harness-023-queue-static-gate.json'
$objectiveDocumentPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源V2源码重构持续目标.md'
$governancePath = Join-Path $RepositoryRoot 'tools\legado-compat\LEGADO_V2_GOVERNANCE_TASKS.md'
$ledgerPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎兼容推进台账.md'
$indexPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎证据索引.md'
$diffPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎差分摘要.md'
$packagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
$relativeOutputPath = 'tools/legado-compat/evidence/' + $RunId + '/transition-consistency.json'

$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -Path $statePath
  $objective = Read-StrictJson -Path $objectivePath
  $queueGate = Read-StrictJson -Path $queueGatePath
  $baseline = $state.baseline
  $objectiveBaseline = $objective.baseline

  Assert-Gate ([int]$baseline.sourceCount -eq 458) 'machine baseline source count is not 458.'
  Assert-Gate ([string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'machine source hash is not the frozen 458-source hash.'
  Assert-Gate ((Get-Sha256 -Path $packagePath) -eq [string]$baseline.sourcePackageSha256) 'source package hash drifted from the machine baseline.'
  Assert-Gate ([string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine Legado commit is not the frozen reference.'
  $legadoRoot = Join-Path $RepositoryRoot 'legado'
  $legadoCommit = (& git -C $legadoRoot rev-parse HEAD 2>$null | Out-String).Trim()
  Assert-Gate ($legadoCommit -eq [string]$baseline.legadoCommit) 'Legado checkout is not at the frozen commit.'
  Assert-Gate ([string]$objectiveBaseline.sourcePackageSha256 -eq [string]$baseline.sourcePackageSha256 -and [int]$objectiveBaseline.sourceCount -eq [int]$baseline.sourceCount -and [string]$objectiveBaseline.legadoCommit -eq [string]$baseline.legadoCommit) 'objective baseline differs from machine baseline.'
  Add-Check -Id 'baseline_binding' -Detail 'The objective and machine state remain bound to the frozen 458-source package and Legado commit.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json', 'tools/legado-compat/state/refactor-objective.json')

  $governance = $state.governance
  Assert-Gate ([string]$governance.activeTaskId -eq 'COMPAT-006') 'active task drifted from COMPAT-006.'
  Assert-Gate ([string]$governance.activeIssueId -eq 'V2-HARNESS-023') 'machine active issue is not Harness-023.'
  Assert-Gate ([string]$governance.status -eq 'running') 'governance status is not running.'
  $issues = @($governance.issues)
  $issue014 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-014'
  $issue015 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-015'
  $issue023 = Get-Issue -Issues $issues -Id 'V2-HARNESS-023'
  $issue228 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS'
  Assert-Gate ($null -ne $issue014 -and [string]$issue014.status -eq 'verifying') '014 must remain verifying for deferred R4.'
  Assert-Gate ($null -ne $issue015 -and [string]$issue015.status -eq 'verifying') '015 must remain verifying for deferred R4.'
  Assert-Gate ($null -ne $issue023 -and [string]$issue023.status -eq 'verifying') 'Harness-023 must remain verifying after static closure.'
  Assert-Gate ($null -ne $issue228 -and [string]$issue228.status -eq 'verifying') '228 must remain a non-active, source-closure candidate.'
  Add-Check -Id 'machine_queue' -Detail 'The machine queue has one active source-verification issue; 014, 015 and Harness-023 remain verifying and 228 is not activated.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json')

  $objectiveAuthority = $objective.authority
  $objectiveBody = $objective.objective
  $executionTarget = $objective.executionTarget
  $selectionGate = $objectiveBody.queueSelectionGate
  Assert-Gate ([string]$objectiveAuthority.activeIssueId -eq 'V2-HARNESS-023') 'objective authority does not point to Harness-023.'
  Assert-Gate ([string]$objectiveBody.activeIssue -eq 'V2-HARNESS-023') 'objective body does not point to Harness-023.'
  Assert-Gate ([string]$selectionGate.currentAnchor -eq 'V2-HARNESS-023' -and [string]$selectionGate.selectedIssue -eq 'V2-HARNESS-023') 'objective queue anchor is not Harness-023.'
  Assert-Gate (@($selectionGate.candidateIssues) -contains 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS') '228 is not registered as the next candidate.'
  Assert-Gate ([string]$executionTarget.nextIssues[0] -eq 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS') 'objective next issue is not 228.'
  Add-Check -Id 'objective_binding' -Detail 'The persistent refactor objective selects Harness-023 and records 228 as the next single-issue candidate.' -Evidence @('tools/legado-compat/state/refactor-objective.json')

  Assert-Gate ([string]$queueGate.status -eq 'passed' -and [string]$queueGate.issueId -eq 'V2-HARNESS-023') 'Harness-023 queue static gate is not a passed evidence artifact.'
  Assert-Gate (-not [bool]$queueGate.semanticMatchAllowed -and @($queueGate.runtimeActionsPerformed).Count -eq 0) 'Harness-023 queue gate contains runtime or semantic-match claims.'
  Assert-Gate ([string]$queueGate.transition.toIssue -eq 'V2-HARNESS-023' -and [string]$queueGate.transition.toStatus -eq 'verifying' -and [string]$queueGate.queue.nextCandidate -eq 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS') 'Harness-023 queue gate does not describe the registered transition and next candidate.'
  Add-Check -Id 'transition_evidence' -Detail 'The 96-assertion Harness-023 static queue evidence is retained without runtime or semantic claims.' -Evidence @('tools/legado-compat/evidence/r3-harness-023-queue-gate-20260808-r1/r3-harness-023-queue-static-gate.json')

  $objectiveDocument = Read-StrictUtf8Text -Path $objectiveDocumentPath
  $governanceDocument = Read-StrictUtf8Text -Path $governancePath
  $ledgerDocument = Read-StrictUtf8Text -Path $ledgerPath
  $indexDocument = Read-StrictUtf8Text -Path $indexPath
  $diffDocument = Read-StrictUtf8Text -Path $diffPath
  Assert-Gate ($objectiveDocument.Contains([string]$objective.targetRevision) -and $objectiveDocument.Contains('当前唯一源码验证议题') -and $objectiveDocument.Contains('V2-HARNESS-023') -and $objectiveDocument.Contains('ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS')) 'objective Markdown does not describe the current queue.'
  Assert-Gate ($governanceDocument.Contains('activeIssue=`V2-HARNESS-023`') -and $governanceDocument -match '\| issue \| V2-HARNESS-023 \| verifying \|' -and $governanceDocument -notmatch '当前唯一活动根因议题为 `ISSUE-COMPAT-012`') 'governance document has a stale active-issue narrative.'
  Assert-Gate ($ledgerDocument.Contains('活跃任务：COMPAT-006') -and $indexDocument -match '\| `V2-HARNESS-023` \| `verifying` \|' -and $diffDocument -match '\| `V2-HARNESS-023` \| `verifying` \|') 'generated documents do not mirror Harness-023.'
  Add-Check -Id 'document_mirror' -Detail 'The objective, governance mirror, ledger, evidence index and diff summary all describe the same Harness-023 transition.' -Evidence @('docs/analysis/Legado书源V2源码重构持续目标.md', 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md', 'docs/analysis/Legado书源引擎兼容推进台账.md', 'docs/analysis/Legado书源引擎证据索引.md', 'docs/analysis/Legado书源引擎差分摘要.md')

  $issueEvidence = @($issue023.evidencePaths | ForEach-Object { [string]$_ })
  Assert-Gate ($issueEvidence -contains 'tools/legado-compat/evidence/r3-harness-023-queue-gate-20260808-r1/r3-harness-023-queue-static-gate.json') 'machine state lost the Harness-023 queue gate evidence.'
  $candidateEvidence = @($issue228.evidencePaths | ForEach-Object { [string]$_ })
  Assert-Gate ($candidateEvidence -contains 'tools/legado-compat/evidence/v2-java-string-list-analyzer-js-source-fix-20260808.json') '228 source-fix evidence is not retained for the next queue selection.'
  if ($RequireRegistration) {
    Assert-Gate ($issueEvidence -contains $relativeOutputPath) 'transition consistency evidence is not registered in machine state.'
    Assert-Gate ($indexDocument.Contains($relativeOutputPath) -and $diffDocument.Contains($relativeOutputPath)) 'registered transition evidence is missing from generated evidence documents.'
  }
  Add-Check -Id 'evidence_registration' -Detail 'Harness-023 queue evidence and the 228 candidate source-fix evidence remain traceable; registration is checked when requested.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json', 'tools/legado-compat/evidence/v2-java-string-list-analyzer-js-source-fix-20260808.json')

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_harness023_transition_consistency'
    status = 'passed'
    issueId = 'V2-HARNESS-023'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    transition = [pscustomobject][ordered]@{
      fromIssue = 'ISSUE-COMPAT-015'
      toIssue = 'V2-HARNESS-023'
      toStatus = 'verifying'
      nextCandidate = 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS'
      runtimeVerification = 'deferred_to_R4'
    }
    baseline = [pscustomobject][ordered]@{
      sourceCount = [int]$baseline.sourceCount
      sourcePackageSha256 = [string]$baseline.sourcePackageSha256
      legadoCommit = [string]$baseline.legadoCommit
    }
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @('tools/legado-compat/state/refactor-objective.json', 'tools/legado-compat/state/full-source-validation-state.json', 'tools/legado-compat/evidence/r3-harness-023-queue-gate-20260808-r1/r3-harness-023-queue-static-gate.json')
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_transition_consistency_read_only;R4_runtime_build_device_and_legado_diff_deferred'
    registrationRequired = [bool]$RequireRegistration
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_harness023_transition_consistency'
    status = 'failed'
    issueId = 'V2-HARNESS-023'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_transition_consistency_read_only;R4_runtime_build_device_and_legado_diff_deferred'
    registrationRequired = [bool]$RequireRegistration
  }
}

$temporaryPath = "$outputFullPath.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
[System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 24), [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $outputFullPath -Force
$result | ConvertTo-Json -Depth 24
if ($exitCode -ne 0) { exit $exitCode }
