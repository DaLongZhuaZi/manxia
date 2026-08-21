[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RunId = 'r3-harness-023-queue-gate-20260808-r1',
  [string]$OutputPath = ''
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
  $OutputPath = Join-Path $runDirectory 'r3-harness-023-queue-static-gate.json'
}
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$evidencePrefix = $evidenceRoot.TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidencePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Harness-023 queue gate output must remain under the evidence directory.'
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

function Get-RelativePath {
  param([Parameter(Mandatory = $true)][string]$Path)
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $rootPrefix = $RepositoryRoot.TrimEnd('\') + '\'
  if ($fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $fullPath.Substring($rootPrefix.Length).Replace('\', '/')
  }
  return $fullPath.Replace('\', '/')
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

function Get-Issue {
  param([object[]]$Issues, [string]$Id)
  foreach ($issue in $Issues) {
    if ([string](Get-PropertyValue -Object $issue -Name 'id') -eq $Id) { return $issue }
  }
  return $null
}

$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$objectivePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\refactor-objective.json'
$preFixPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-v2-harness-023-pre-fix-20260808.json'
$sourceFixPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-harness-023-source-fix-20260808-r2.json'
$appendFixPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-harness-023-governance-evidence-append-source-fix-20260808-r1.json'
$hashAuditPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\r3-source-fix-hash-audit-20260808-r1.json'
$objectiveDocumentPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源V2源码重构持续目标.md'
$governancePath = Join-Path $RepositoryRoot 'tools\legado-compat\LEGADO_V2_GOVERNANCE_TASKS.md'
$ledgerPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎兼容推进台账.md'
$indexPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎证据索引.md'
$diffPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎差分摘要.md'
$packagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'

$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -Path $statePath
  $objective = Read-StrictJson -Path $objectivePath
  $preFix = Read-StrictJson -Path $preFixPath
  $sourceFix = Read-StrictJson -Path $sourceFixPath
  $appendFix = Read-StrictJson -Path $appendFixPath
  $hashAudit = Read-StrictJson -Path $hashAuditPath

  $baseline = $state.baseline
  Assert-Gate ([int]$baseline.sourceCount -eq 458) 'machine baseline source count is not 458.'
  Assert-Gate ((Get-Sha256 -Path $packagePath) -eq [string]$baseline.sourcePackageSha256) 'source package hash drifted from the machine baseline.'
  $legadoRoot = Join-Path $RepositoryRoot 'legado'
  $legadoCommit = (& git -C $legadoRoot rev-parse HEAD 2>$null | Out-String).Trim()
  Assert-Gate ($legadoCommit -eq [string]$baseline.legadoCommit) 'Legado checkout is not at the frozen commit.'
  Assert-Gate ([string]$sourceFix.baseline.sourcePackageSha256 -eq [string]$baseline.sourcePackageSha256 -and [int]$sourceFix.baseline.sourceCount -eq [int]$baseline.sourceCount -and [string]$sourceFix.baseline.legadoCommit -eq [string]$baseline.legadoCommit) 'Harness source-fix baseline differs from machine baseline.'
  Assert-Gate ([string]$appendFix.baseline.sourcePackageSha256 -eq [string]$baseline.sourcePackageSha256 -and [int]$appendFix.baseline.sourceCount -eq [int]$baseline.sourceCount -and [string]$appendFix.baseline.legadoCommit -eq [string]$baseline.legadoCommit) 'Harness evidence-append baseline differs from machine baseline.'
  Add-Check -Id 'baseline_binding' -Detail 'Harness-023 source fixes and append supplement remain bound to the frozen 458-source baseline.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json', 'tools/legado-compat/evidence/v2-harness-023-source-fix-20260808-r2.json', 'tools/legado-compat/evidence/v2-harness-023-governance-evidence-append-source-fix-20260808-r1.json')

  $governance = $state.governance
  Assert-Gate ([string]$governance.activeTaskId -eq 'COMPAT-006') 'active task drifted from COMPAT-006.'
  Assert-Gate ([string]$governance.activeIssueId -eq 'ISSUE-COMPAT-015') 'pre-transition active issue must remain ISSUE-COMPAT-015.'
  Assert-Gate ([string]$governance.status -eq 'running') 'governance status is not running.'
  $issues = @($governance.issues)
  $issue015 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-015'
  $issue023 = Get-Issue -Issues $issues -Id 'V2-HARNESS-023'
  Assert-Gate ($null -ne $issue015 -and [string]$issue015.status -eq 'verifying') '015 must remain verifying while Harness-023 is selected.'
  Assert-Gate ($null -ne $issue023 -and [string]$issue023.status -eq 'verifying') 'Harness-023 must have a verifying source closure state.'
  Assert-Gate ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-015' -and [string]$objective.objective.activeIssue -eq 'ISSUE-COMPAT-015') 'objective must still point to 015 before the transition.'
  Assert-Gate ([string]$objective.objective.queueSelectionGate.currentAnchor -eq 'ISSUE-COMPAT-015' -and [string]$objective.objective.queueSelectionGate.selectedIssue -eq 'ISSUE-COMPAT-015') 'objective queue anchor must still point to 015 before the transition.'
  Assert-Gate (@($objective.objective.queueSelectionGate.candidateIssues) -contains 'V2-HARNESS-023') 'Harness-023 is not the registered next candidate.'
  Add-Check -Id 'pre_transition_queue' -Detail 'The unique queue is ready to move from 015 to the independently evidenced Harness-023 root cause.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json', 'tools/legado-compat/state/refactor-objective.json')

  Assert-Gate ([string]$preFix.issueId -eq 'V2-HARNESS-023' -and [string]$preFix.status -eq 'failed') 'Harness-023 frozen failure evidence is missing or not failed.'
  $contractEvidence = @($sourceFix.contracts)
  Assert-Gate ($contractEvidence.Count -eq 6) 'Harness-023 source-fix evidence must contain six core static contracts.'
  foreach ($contract in $contractEvidence) {
    Assert-Gate ([string]$contract.status -eq 'passed' -and [int]$contract.assertions -gt 0) ("Harness-023 contract is not passed: {0}" -f [string]$contract.path)
    $absoluteContract = Join-Path $RepositoryRoot ([string]$contract.path -replace '/', '\')
    Assert-Gate (Test-Path -LiteralPath $absoluteContract) ("Harness-023 contract evidence is missing: {0}" -f [string]$contract.path)
    Assert-Gate ((Get-Sha256 -Path $absoluteContract) -eq ([string]$contract.sha256).ToUpperInvariant()) ("Harness-023 contract evidence hash drifted: {0}" -f [string]$contract.path)
  }
  $appendContracts = @($appendFix.contracts)
  Assert-Gate ($appendContracts.Count -eq 2) 'Harness-023 append supplement must contain two contracts.'
  foreach ($contract in $appendContracts) {
    Assert-Gate ([string]$contract.status -eq 'passed' -and [int]$contract.assertions -gt 0) ("Harness-023 append contract is not passed: {0}" -f [string]$contract.path)
    $absoluteContract = Join-Path $RepositoryRoot ([string]$contract.path -replace '/', '\')
    Assert-Gate (Test-Path -LiteralPath $absoluteContract) ("Harness-023 append contract evidence is missing: {0}" -f [string]$contract.path)
    Assert-Gate ((Get-Sha256 -Path $absoluteContract) -eq ([string]$contract.sha256).ToUpperInvariant()) ("Harness-023 append contract evidence hash drifted: {0}" -f [string]$contract.path)
  }
  Add-Check -Id 'contract_hash_binding' -Detail 'Six Harness projection/isolation contracts and two evidence-append contracts are passed and hash-bound.' -Evidence @($contractEvidence.path + $appendContracts.path)

  Assert-Gate ([string]$sourceFix.status -eq 'source_closure_static_verified_pending_r4' -and [string]$sourceFix.issueId -eq 'V2-HARNESS-023') 'Harness-023 source-fix evidence is not pending-R4 static closure.'
  Assert-Gate ([string]$appendFix.status -eq 'source_closure_static_verified_pending_r4' -and [string]$appendFix.issueId -eq 'V2-HARNESS-023') 'Harness-023 append source-fix evidence is not pending-R4 static closure.'
  Assert-Gate ([string]$hashAudit.status -eq 'passed_with_historical_superseded_evidence' -and -not [bool]$hashAudit.newIssueRequired) 'Harness source-fix hash audit is not classified as historical superseded evidence.'
  Assert-Gate ([string]$hashAudit.classification.superseded_shared_harness.replacementEvidencePath -eq 'tools/legado-compat/evidence/v2-harness-023-governance-evidence-append-source-fix-20260808-r1.json') 'Harness historical source-fix replacement evidence is not the registered append supplement.'
  Assert-Gate (-not [bool]$sourceFix.semanticMatchAllowed -and -not [bool]$appendFix.semanticMatchAllowed) 'Harness source fixes must not allow semantic match.'
  Assert-Gate (@((Get-PropertyValue -Object $sourceFix -Name 'runtimeActionsPerformed' -Default @())).Count -eq 0 -and @((Get-PropertyValue -Object $appendFix -Name 'runtimeActionsPerformed' -Default @())).Count -eq 0) 'Harness source fixes record runtime actions.'
  Assert-Gate (@($sourceFix.r4Required).Count -ge 4 -and @($appendFix.r4Required).Count -ge 3) 'Harness source fixes must retain R4 closure requirements.'
  Add-Check -Id 'static_status_contract' -Detail 'Harness-023 source closure is static-only, explicitly pending fresh full_workflow and R4, with no semantic claim.' -Evidence @('tools/legado-compat/evidence/v2-harness-023-source-fix-20260808-r2.json', 'tools/legado-compat/evidence/v2-harness-023-governance-evidence-append-source-fix-20260808-r1.json')

  $sourceFiles = @($sourceFix.sourceFiles)
  Assert-Gate ($sourceFiles.Count -eq 5) 'Harness-023 source-fix evidence must bind five implementation files.'
  foreach ($sourceFile in $sourceFiles) {
    $relativeSource = [string]$sourceFile.path
    $absoluteSource = Join-Path $RepositoryRoot ($relativeSource -replace '/', '\')
    Assert-Gate (Test-Path -LiteralPath $absoluteSource) ("Harness implementation file is missing: {0}" -f $relativeSource)
    if ($relativeSource -eq 'tools/legado-compat/Update-LegadoGovernanceState.ps1') {
      Assert-Gate ((Get-Sha256 -Path $absoluteSource) -eq ([string]$appendFix.changes[0].sha256).ToUpperInvariant()) 'Harness updater hash must be validated through the current append supplement.'
    } else {
      Assert-Gate ((Get-Sha256 -Path $absoluteSource) -eq ([string]$sourceFile.sha256).ToUpperInvariant()) ("Harness implementation hash drifted: {0}" -f $relativeSource)
    }
  }
  $appendChanges = @($appendFix.changes)
  Assert-Gate ($appendChanges.Count -eq 1) 'Harness append source-fix evidence must bind the updater change.'
  foreach ($change in $appendChanges) {
    $relativeChange = [string]$change.path
    $absoluteChange = Join-Path $RepositoryRoot ($relativeChange -replace '/', '\')
    Assert-Gate (Test-Path -LiteralPath $absoluteChange) ("Harness append implementation file is missing: {0}" -f $relativeChange)
    Assert-Gate ((Get-Sha256 -Path $absoluteChange) -eq ([string]$change.sha256).ToUpperInvariant()) ("Harness append implementation hash drifted: {0}" -f $relativeChange)
  }
  foreach ($fixture in @($sourceFix.fixtureFiles)) {
    $relativeFixture = [string]$fixture.path
    $absoluteFixture = Join-Path $RepositoryRoot ($relativeFixture -replace '/', '\')
    Assert-Gate (Test-Path -LiteralPath $absoluteFixture) ("Harness fixture is missing: {0}" -f $relativeFixture)
    Assert-Gate ((Get-Sha256 -Path $absoluteFixture) -eq ([string]$fixture.sha256).ToUpperInvariant()) ("Harness fixture hash drifted: {0}" -f $relativeFixture)
  }
  Add-Check -Id 'source_fixture_hash_binding' -Detail 'Harness runner, navigation, path, settlement and state-writer sources plus six fixtures remain bound to current HEAD.' -Evidence @($sourceFiles.path + $appendChanges.path + @($sourceFix.fixtureFiles | ForEach-Object { [string]$_.path }))

  $objectiveDocument = Read-StrictUtf8Text -Path $objectiveDocumentPath
  $governanceDocument = Read-StrictUtf8Text -Path $governancePath
  $ledgerDocument = Read-StrictUtf8Text -Path $ledgerPath
  $indexDocument = Read-StrictUtf8Text -Path $indexPath
  $diffDocument = Read-StrictUtf8Text -Path $diffPath
  Assert-Gate ($objectiveDocument.Contains([string]$objective.targetRevision) -and $objectiveDocument.Contains('V2-HARNESS-023')) 'objective Markdown does not retain Harness-023 as the next candidate.'
  Assert-Gate ($governanceDocument.Contains('activeIssue=`ISSUE-COMPAT-015`') -and $governanceDocument -match '\| issue \| V2-HARNESS-023 \| verifying \|') 'governance mirror does not retain the pre-transition Harness state.'
  Assert-Gate ($ledgerDocument.Contains('活跃任务：COMPAT-006') -and $indexDocument -match '\| `V2-HARNESS-023` \| `verifying` \|' -and $diffDocument -match '\| `V2-HARNESS-023` \| `verifying` \|') 'generated documents do not retain Harness-023 evidence.'
  Add-Check -Id 'document_binding' -Detail 'All generated documents retain the evidenced Harness-023 candidate before the atomic queue transition.' -Evidence @('docs/analysis/Legado书源V2源码重构持续目标.md', 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md', 'docs/analysis/Legado书源引擎兼容推进台账.md', 'docs/analysis/Legado书源引擎证据索引.md', 'docs/analysis/Legado书源引擎差分摘要.md')

  $requiredEvidence = @(
    'tools/legado-compat/evidence/contract-v2-harness-023-pre-fix-20260808.json',
    'tools/legado-compat/evidence/v2-harness-023-source-fix-20260808-r2.json',
    'tools/legado-compat/evidence/v2-harness-023-governance-evidence-append-source-fix-20260808-r1.json',
    'tools/legado-compat/evidence/v2-harness-023-evidence-run-isolation-contract-20260808.json',
    'tools/legado-compat/evidence/v2-harness-023-effective-overlay-write-isolation-contract-20260808.json',
    'tools/legado-compat/evidence/v2-harness-023-record-exception-containment-contract-20260808.json',
    'tools/legado-compat/evidence/v2-harness-023-activity-run-reuse-contract-20260808.json',
    'tools/legado-compat/evidence/v2-harness-023-governance-in-progress-status-contract-20260808.json',
    'tools/legado-compat/evidence/v2-hypium-full-source-runner-contract.json',
    'tools/legado-compat/evidence/v2-source-workflow-evidence-projection-contract.json'
  )
  foreach ($relativeEvidence in $requiredEvidence) {
    $absoluteEvidence = Join-Path $RepositoryRoot ($relativeEvidence -replace '/', '\')
    Assert-Gate (Test-Path -LiteralPath $absoluteEvidence) ("required Harness evidence is missing: {0}" -f $relativeEvidence)
    $ledgerEvidence = @($issue023.evidencePaths | ForEach-Object { [string]$_ })
    Assert-Gate ($ledgerEvidence -contains $relativeEvidence) ("machine ledger does not retain Harness evidence: {0}" -f $relativeEvidence)
  }
  Add-Check -Id 'evidence_registration' -Detail 'Harness failure, source-fix and all static contract evidence are present and retained.' -Evidence $requiredEvidence

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_harness023_queue_static_gate'
    status = 'passed'
    issueId = 'V2-HARNESS-023'
    transition = [pscustomobject][ordered]@{
      fromIssue = 'ISSUE-COMPAT-015'
      fromStatus = 'verifying'
      toIssue = 'V2-HARNESS-023'
      toStatus = 'verifying'
      sourceClosureStaticExit = $true
      runtimeVerification = 'deferred_to_R4'
    }
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    baseline = [pscustomobject][ordered]@{
      sourceCount = [int]$baseline.sourceCount
      sourcePackageSha256 = [string]$baseline.sourcePackageSha256
      legadoCommit = [string]$baseline.legadoCommit
    }
    queue = [pscustomobject][ordered]@{
      activeTaskId = [string]$governance.activeTaskId
      activeIssueId = [string]$governance.activeIssueId
      fromIssue = 'ISSUE-COMPAT-015'
      toIssue = 'V2-HARNESS-023'
      nextCandidate = 'ISSUE-COMPAT-228-JAVA-STRING-LIST-ANALYZER-JS'
    }
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @($requiredEvidence + @('tools/legado-compat/state/refactor-objective.json', 'tools/legado-compat/state/full-source-validation-state.json'))
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_harness023_queue_static_only;R4_runtime_build_device_and_legado_diff_deferred'
    nextGate = 'V2-HARNESS-023 remains verifying until fresh full_workflow, affected-set, differential, build and device gates complete.'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_harness023_queue_static_gate'
    status = 'failed'
    issueId = 'V2-HARNESS-023'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_harness023_queue_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  }
}

$temporaryPath = "$outputFullPath.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
[System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 24), [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $outputFullPath -Force
$result | ConvertTo-Json -Depth 24
if ($exitCode -ne 0) { exit $exitCode }
