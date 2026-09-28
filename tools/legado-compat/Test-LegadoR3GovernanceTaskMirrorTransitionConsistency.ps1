[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RunId = 'r3-governance-task-mirror-transition-consistency-20260808-r1',
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
  throw 'Governance task mirror transition evidence must remain under the evidence directory.'
}
if (-not (Test-Path -LiteralPath $runDirectory)) {
  [System.IO.Directory]::CreateDirectory($runDirectory) | Out-Null
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:checks = New-Object 'System.Collections.Generic.List[object]'
$script:assertions = 0

function Read-StrictUtf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Required file is missing: $Path"
  }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  try {
    return (Read-StrictUtf8Text -Path $Path | ConvertFrom-Json)
  } catch {
    throw "Invalid JSON: $Path; $($_.Exception.Message)"
  }
}

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

function Get-Sha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$objectivePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\refactor-objective.json'
$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\v2-governance-task-mirror.json'
$sourceFixPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-governance-task-mirror-source-fix-20260808.json'
$contractPath = Join-Path $RepositoryRoot 'tools\legado-compat\Test-LegadoV2GovernanceTaskMirrorContract.ps1'
$ledgerPath = Join-Path $RepositoryRoot 'tools\legado-compat\LEGADO_V2_GOVERNANCE_TASKS.md'
$objectiveDocumentPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源V2源码重构持续目标.md'
$indexPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎证据索引.md'
$diffPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎差分摘要.md'
$relativeOutputPath = 'tools/legado-compat/evidence/' + $RunId + '/transition-consistency.json'
$packagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'

$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -Path $statePath
  $objective = Read-StrictJson -Path $objectivePath
  $fixture = Read-StrictJson -Path $fixturePath
  $sourceFix = Read-StrictJson -Path $sourceFixPath
  $baseline = $state.baseline
  Assert-Gate ([int]$baseline.sourceCount -eq 458 -and [string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine baseline is not frozen.'
  Assert-Gate ((Get-Sha256 -Path $packagePath) -eq [string]$baseline.sourcePackageSha256) 'source package hash drifted.'
  Assert-Gate ((& git -C (Join-Path $RepositoryRoot 'legado') rev-parse HEAD 2>$null | Out-String).Trim() -eq [string]$baseline.legadoCommit) 'Legado checkout is not at the frozen commit.'
  Add-Check -Id 'baseline_binding' -Detail 'State, objective, package and Legado checkout remain bound to the frozen baseline.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json', 'tools/legado-compat/state/refactor-objective.json')

  $governance = $state.governance
  $issues = @($governance.issues)
  $issue230 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT'
  $issueMirror = Get-Issue -Issues $issues -Id 'V2-GOV-004-DOCUMENT-TASK-MIRROR'
  Assert-Gate ([string]$governance.activeTaskId -eq 'COMPAT-006' -and [string]$governance.activeIssueId -eq 'V2-GOV-004-DOCUMENT-TASK-MIRROR' -and [string]$governance.status -eq 'running') 'machine governance queue is not registered on V2-GOV-004.'
  Assert-Gate ($null -ne $issue230 -and [string]$issue230.status -eq 'verifying') '230 must remain verifying for deferred R4.'
  Assert-Gate ($null -ne $issueMirror -and [string]$issueMirror.status -eq 'verifying') 'V2-GOV-004 must remain verifying after static closure.'
  $mirrorEvidence = @($issueMirror.evidencePaths | ForEach-Object { [string]$_ })
  Assert-Gate ($mirrorEvidence -contains 'tools/legado-compat/evidence/v2-governance-task-mirror-source-fix-20260808.json') 'V2-GOV-004 source-fix evidence is not registered.'
  Add-Check -Id 'machine_queue' -Detail 'The unique source queue is atomically registered on V2-GOV-004; 230 and prior source issues remain deferred to R4.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json')

  Assert-Gate ([string]$objective.authority.activeIssueId -eq 'V2-GOV-004-DOCUMENT-TASK-MIRROR' -and [string]$objective.objective.activeIssue -eq 'V2-GOV-004-DOCUMENT-TASK-MIRROR') 'objective active issue is not V2-GOV-004.'
  Assert-Gate ([string]$objective.objective.queueSelectionGate.selectedIssue -eq 'V2-GOV-004-DOCUMENT-TASK-MIRROR' -and @($objective.objective.queueSelectionGate.candidateIssues) -contains 'ISSUE-COMPAT-CRYPTO-002') 'objective queue selection is not V2-GOV-004 -> Crypto.'
  Assert-Gate ([string]$objective.executionTarget.currentIssue -eq 'V2-GOV-004-DOCUMENT-TASK-MIRROR' -and @($objective.executionTarget.nextIssues) -contains 'ISSUE-COMPAT-CRYPTO-002') 'objective execution target is not V2-GOV-004 -> Crypto.'
  Assert-Gate ([string]$sourceFix.status -eq 'source_static_closed' -and -not [bool](Get-PropertyValue -Object $sourceFix -Name 'semanticMatchAllowed' -Default $true)) 'V2-GOV-004 source-fix evidence contains an invalid semantic claim.'
  Assert-Gate ([string]$fixture.issueId -eq 'V2-GOV-004-DOCUMENT-TASK-MIRROR' -and [string]$fixture.sourceOfTruth -eq 'tools/legado-compat/state/full-source-validation-state.json') 'V2-GOV-004 fixture is not bound to the machine fact source.'
  Add-Check -Id 'objective_and_source_evidence' -Detail 'Objective, source-fix evidence and fixture agree on V2-GOV-004 as the sole active static-closure issue and defer R4.' -Evidence @('tools/legado-compat/state/refactor-objective.json', 'tools/legado-compat/evidence/v2-governance-task-mirror-source-fix-20260808.json', 'tools/legado-compat/fixtures/v2-governance-task-mirror.json')

  $ledger = Read-StrictUtf8Text -Path $ledgerPath
  $objectiveDocument = Read-StrictUtf8Text -Path $objectiveDocumentPath
  $indexDocument = Read-StrictUtf8Text -Path $indexPath
  $diffDocument = Read-StrictUtf8Text -Path $diffPath
  $startMarker = [string]$fixture.startMarker
  $endMarker = [string]$fixture.endMarker
  Assert-Gate (([regex]::Matches($ledger, [regex]::Escape($startMarker))).Count -eq 1 -and ([regex]::Matches($ledger, [regex]::Escape($endMarker))).Count -eq 1) 'governance ledger must contain one generated mirror.'
  Assert-Gate ($ledger -match '(?m)^\| issue \| V2-GOV-004-DOCUMENT-TASK-MIRROR \| verifying \|' -and $ledger -match '(?m)^\| issue \| ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT \| verifying \|') 'governance mirror rows do not reflect the active transition.'
  Assert-Gate ($objectiveDocument.Contains([string]$objective.targetRevision) -and $objectiveDocument.Contains('当前唯一源码验证议题已原子切换为 `V2-GOV-004-DOCUMENT-TASK-MIRROR`') -and $objectiveDocument.Contains('下一候选为 `ISSUE-COMPAT-CRYPTO-002`')) 'objective Markdown does not describe the registered V2-GOV-004 queue.'
  if ($RequireRegistration) {
    Assert-Gate ($mirrorEvidence -contains $relativeOutputPath -and $indexDocument.Contains($relativeOutputPath) -and $diffDocument.Contains($relativeOutputPath)) 'V2-GOV-004 transition evidence is not registered in machine state and generated documents.'
  }
  Add-Check -Id 'document_mirror' -Detail 'Objective Markdown, governance mirror, evidence index and diff summary agree on V2-GOV-004 and retain the 230 historical boundary.' -Evidence @('docs/analysis/Legado书源V2源码重构持续目标.md', 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md', 'docs/analysis/Legado书源引擎证据索引.md', 'docs/analysis/Legado书源引擎差分摘要.md')

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_governance_task_mirror_transition_consistency'
    status = 'passed'
    issueId = 'V2-GOV-004-DOCUMENT-TASK-MIRROR'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    transition = [pscustomobject][ordered]@{
      fromIssue = 'ISSUE-COMPAT-230-EXPLORE-HARNESS-SERIAL-TIMEOUT'
      fromStatus = 'verifying'
      toIssue = 'V2-GOV-004-DOCUMENT-TASK-MIRROR'
      toStatus = 'verifying'
      nextCandidate = 'ISSUE-COMPAT-CRYPTO-002'
      runtimeVerification = 'deferred_to_R4'
    }
    baseline = [pscustomobject][ordered]@{
      sourceCount = [int]$baseline.sourceCount
      sourcePackageSha256 = [string]$baseline.sourcePackageSha256
      legadoCommit = [string]$baseline.legadoCommit
    }
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @('tools/legado-compat/state/refactor-objective.json', 'tools/legado-compat/state/full-source-validation-state.json', 'tools/legado-compat/evidence/v2-governance-task-mirror-source-fix-20260808.json', 'tools/legado-compat/fixtures/v2-governance-task-mirror.json')
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_governance_task_mirror_transition_consistency_read_only;R4_runtime_build_device_and_legado_diff_deferred'
    registrationRequired = [bool]$RequireRegistration
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_governance_task_mirror_transition_consistency'
    status = 'failed'
    issueId = 'V2-GOV-004-DOCUMENT-TASK-MIRROR'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_governance_task_mirror_transition_consistency_read_only;R4_runtime_build_device_and_legado_diff_deferred'
    registrationRequired = [bool]$RequireRegistration
  }
}

$temporaryPath = "$outputFullPath.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
[System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 24), [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $outputFullPath -Force
$result | ConvertTo-Json -Depth 24
if ($exitCode -ne 0) { exit $exitCode }
