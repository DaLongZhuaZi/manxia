[CmdletBinding()]
param(
  [string]$ResultPath = '',
  [string]$PinnedSourcePackageDirectory = 'F:\Downloads-E'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($ResultPath.Length -eq 0) {
  $ResultPath = Join-Path $PSScriptRoot 'evidence\full-source-state-contract.json'
}

$modulePath = Join-Path $PSScriptRoot 'LegadoFullSourceState.psm1'
$readinessPath = Join-Path $PSScriptRoot 'Invoke-LegadoFullDeviceReadinessAudit.ps1'
$deviceQualificationUpdaterPath = Join-Path $PSScriptRoot 'Update-LegadoDevicePersistedQualification.ps1'
Import-Module -Name $modulePath -Force

$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$utf8WithBom = [System.Text.UTF8Encoding]::new($true)
$pinnedPackageSha256 = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$pinnedLegadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$knownImageRawDocumentSha256 = 'C37C70C8CAEF443BDC3D5E889BAD907A63A028970446353BF19609146EAE72E7'

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "CONTRACT FAILED: $Message"
  }
}

function Write-TestText {
  param([string]$Path, [string]$Text, [System.Text.Encoding]$Encoding)
  $directory = Split-Path -Path $Path -Parent
  if (-not (Test-Path -LiteralPath $directory)) {
    [void][System.IO.Directory]::CreateDirectory($directory)
  }
  [System.IO.File]::WriteAllText($Path, $Text, $Encoding)
}

function Write-TestJson {
  param([string]$Path, [object]$Value)
  Write-TestText -Path $Path -Text ([string]($Value | ConvertTo-Json -Depth 30)) -Encoding $utf8NoBom
}

function Get-PropertyValue {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) {
    return $null
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }
  return $property.Value
}

function Invoke-StateInitialization {
  param(
    [string]$PackagePath,
    [string]$StatePath,
    [string]$GovernancePath,
    [string]$ExpectedHash,
    [int]$ExpectedCount,
    [string]$LegadoCommit = $pinnedLegadoCommit,
    [string]$ExpectedCommit = $pinnedLegadoCommit
  )
  return Initialize-LegadoFullSourceState `
    -SourcePackagePath $PackagePath `
    -StatePath $StatePath `
    -LegacyGovernancePath $GovernancePath `
    -ExpectedPackageSha256 $ExpectedHash `
    -ExpectedSourceCount $ExpectedCount `
    -LegadoCommit $LegadoCommit `
    -ExpectedLegadoCommit $ExpectedCommit
}

$tempBase = [System.IO.Path]::GetTempPath()
$tempRoot = Join-Path $tempBase ("manxia-legado-state-contract-{0}-{1}" -f $PID, [Guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($tempRoot)
$assertionCount = 0
$realPackageChecked = $false

try {
  $emptyDocuments = @(Get-LegadoRawSourceDocuments -Json '[]' -Label 'empty fixture')
  Assert-Contract ($emptyDocuments.Count -eq 0) 'Raw document scanner must preserve an empty array.'
  $assertionCount++

  $unicodeValue = ([string][char]0x4E2D) + ([string][char]0x6587)
  $oneDocument = '{"bookSourceType":0,"label":"' + $unicodeValue + '","nested":{"text":"brace { and escaped \" quote"}}'
  $onePackageText = "[`n  $oneDocument`n]"
  $oneDocuments = @(Get-LegadoRawSourceDocuments -Json $onePackageText -Label 'one fixture')
  Assert-Contract ($oneDocuments.Count -eq 1 -and $oneDocuments[0] -eq $oneDocument) 'One-element raw array must retain the exact object text.'
  $assertionCount++

  $manyDocumentA = '{"bookSourceType":0,"value":1}'
  $manyDocumentB = '{"bookSourceType":2,"value":[{"nested":true}]}'
  $manyDocumentC = '{"bookSourceType":4,"value":"tail"}'
  $manyPackageText = "[`n$manyDocumentA,`n$manyDocumentB,`n$manyDocumentC`n]"
  $manyDocuments = @(Get-LegadoRawSourceDocuments -Json $manyPackageText -Label 'many fixture')
  Assert-Contract ($manyDocuments.Count -eq 3) 'N-element raw array must retain every object.'
  Assert-Contract ($manyDocuments[1] -eq $manyDocumentB) 'Nested arrays and objects must not split a raw document.'
  $assertionCount += 2

  $bomPackagePath = Join-Path $tempRoot 'bom-package.json'
  $bomStatePath = Join-Path $tempRoot 'bom-state.json'
  $bomGovernancePath = Join-Path $tempRoot 'bom-governance.json'
  Write-TestText -Path $bomPackagePath -Text $onePackageText -Encoding $utf8WithBom
  $bomPackageHash = Get-LegadoSha256ForBytes -Bytes ([System.IO.File]::ReadAllBytes($bomPackagePath))
  $bomState = Invoke-StateInitialization `
    -PackagePath $bomPackagePath `
    -StatePath $bomStatePath `
    -GovernancePath $bomGovernancePath `
    -ExpectedHash $bomPackageHash `
    -ExpectedCount 1
  $expectedOneSourceId = Get-LegadoSha256ForText -Value $oneDocument
  Assert-Contract ([string]$bomState.sources[0].sourceId -eq $expectedOneSourceId) 'sourceId must hash the exact raw object, not a reserialized object.'
  Assert-Contract ([string]$bomState.sources[0].sourceHash -eq $expectedOneSourceId) 'Compatibility sourceHash must equal the canonical raw sourceId.'
  Assert-Contract ([string]$bomState.sources[0].semanticQualification -eq 'unverified') 'New records must not claim semantic compatibility before a reference-backed execution.'
  Assert-Contract ([string]$bomState.devicePersistedQualification.observationStatus -eq 'unobserved') 'New state must not fabricate a device-persisted complete-verification result.'
  Assert-Contract ([int]$bomState.devicePersistedQualification.totalSourceCount -eq 1 -and [int]$bomState.devicePersistedQualification.completeVerificationCount -eq 0 -and [int]$bomState.devicePersistedQualification.verificationDenominator -eq 0) 'New device-persisted qualification must remain distinct from source workflow counters.'
  $bomStateBytes = [System.IO.File]::ReadAllBytes($bomStatePath)
  $hasBom = $bomStateBytes.Length -ge 3 -and $bomStateBytes[0] -eq 0xEF -and $bomStateBytes[1] -eq 0xBB -and $bomStateBytes[2] -eq 0xBF
  Assert-Contract (-not $hasBom) 'State checkpoints must be UTF-8 without BOM even when the input package has a BOM.'
  Assert-Contract (@((Read-LegadoJsonFile -Path $bomStatePath).sources).Count -eq 1) 'One-element source arrays must remain arrays after checkpoint serialization.'
  $assertionCount += 7

  $deviceProbePath = Join-Path $tempRoot 'book-source-management-result.json'
  $deviceProbe = [pscustomobject][ordered]@{
    status = 'passed'
    device_sn = 'contract-device'
    package = 'com.dlzz.manxia'
    driver_closed = $true
    total_count_text = '1'
    verified_count_text = '0/1'
    policy_summary_text = 'V2 全量切换 · 完整验证 0/1'
  }
  Write-TestJson -Path $deviceProbePath -Value $deviceProbe
  $deviceUpdateOutput = & $deviceQualificationUpdaterPath `
    -StatePath $bomStatePath `
    -ProbeResultPath $deviceProbePath `
    -RepositoryRoot $tempRoot `
    -SkipDocumentRefresh
  $deviceUpdateResult = ([string]($deviceUpdateOutput | Select-Object -Last 1)) | ConvertFrom-Json
  $deviceUpdatedState = Read-LegadoJsonFile -Path $bomStatePath
  Assert-Contract ([string]$deviceUpdateResult.status -eq 'passed') 'Device qualification updater must publish a passed aggregate observation.'
  Assert-Contract ([string]$deviceUpdatedState.devicePersistedQualification.observationStatus -eq 'observed_incomplete') 'A zero-row device observation must remain incomplete rather than inheriting fixture passes.'
  Assert-Contract ([int]$deviceUpdatedState.devicePersistedQualification.totalSourceCount -eq 1 -and [int]$deviceUpdatedState.devicePersistedQualification.completeVerificationCount -eq 0 -and [int]$deviceUpdatedState.devicePersistedQualification.verificationDenominator -eq 1) 'Device qualification numerator and denominator must be copied only from the management aggregate.'
  Assert-Contract ([string]$deviceUpdatedState.devicePersistedQualification.executionPolicy -eq 'v2_full_cutover' -and [string]$deviceUpdatedState.devicePersistedQualification.sourceIdentityCoverage -eq 'aggregate_only') 'Device aggregate evidence must retain policy scope without claiming source-level identity coverage.'
  $assertionCount += 4

  $invalidDeviceProbePath = Join-Path $tempRoot 'book-source-management-invalid-result.json'
  $invalidDeviceProbe = [pscustomobject][ordered]@{
    status = 'passed'
    device_sn = 'contract-device'
    package = 'com.dlzz.manxia'
    driver_closed = $true
    total_count_text = '1'
    verified_count_text = '1/2'
    policy_summary_text = 'V2 全量切换 · 完整验证 1/2'
  }
  Write-TestJson -Path $invalidDeviceProbePath -Value $invalidDeviceProbe
  $invalidDeviceUpdateThrown = $false
  try {
    & $deviceQualificationUpdaterPath `
      -StatePath $bomStatePath `
      -ProbeResultPath $invalidDeviceProbePath `
      -RepositoryRoot $tempRoot `
      -SkipDocumentRefresh | Out-Null
  } catch {
    $invalidDeviceUpdateThrown = $_.Exception.Message.Contains('Management aggregate denominator mismatch')
  }
  $afterInvalidDeviceUpdate = Read-LegadoJsonFile -Path $bomStatePath
  Assert-Contract $invalidDeviceUpdateThrown 'A device aggregate with a denominator different from the immutable baseline must be rejected.'
  Assert-Contract ([int]$afterInvalidDeviceUpdate.devicePersistedQualification.completeVerificationCount -eq 0 -and [int]$afterInvalidDeviceUpdate.devicePersistedQualification.verificationDenominator -eq 1) 'Rejected device evidence must not overwrite the prior atomic aggregate observation.'
  $assertionCount += 2

  $completedBomState = Read-LegadoJsonFile -Path $bomStatePath
  $completedBomState.sources[0].status = 'passed'
  $completedBomState.sources[0].attempts = 6
  Write-LegadoStateCheckpoint -Path $bomStatePath -State $completedBomState
  $completedBomState = Invoke-StateInitialization `
    -PackagePath $bomPackagePath `
    -StatePath $bomStatePath `
    -GovernancePath $bomGovernancePath `
    -ExpectedHash $bomPackageHash `
    -ExpectedCount 1
  Assert-Contract ([string]$completedBomState.sources[0].status -eq 'passed') 'Reinitialization must retain a completed source.'
  Assert-Contract ([int]$completedBomState.sources[0].attempts -eq 6) 'Reinitialization must retain completed source attempts.'
  Assert-Contract ([string]$completedBomState.devicePersistedQualification.observationStatus -eq 'observed_incomplete' -and [int]$completedBomState.devicePersistedQualification.verificationDenominator -eq 1) 'Reinitialization must retain an observed device aggregate instead of resetting it to unobserved.'
  Assert-Contract ([string]$completedBomState.status -eq 'passed') 'A fully completed ledger must retain its top-level passed status.'
  $assertionCount += 4

  $emptyPackagePath = Join-Path $tempRoot 'empty-package.json'
  $emptyStatePath = Join-Path $tempRoot 'empty-state.json'
  $emptyGovernancePath = Join-Path $tempRoot 'empty-governance.json'
  Write-TestText -Path $emptyPackagePath -Text '[]' -Encoding $utf8NoBom
  $emptyHash = Get-LegadoSha256ForBytes -Bytes ([System.IO.File]::ReadAllBytes($emptyPackagePath))
  $emptyState = Invoke-StateInitialization `
    -PackagePath $emptyPackagePath `
    -StatePath $emptyStatePath `
    -GovernancePath $emptyGovernancePath `
    -ExpectedHash $emptyHash `
    -ExpectedCount 0
  Assert-Contract (@($emptyState.sources).Count -eq 0) 'Zero-element source arrays must remain empty after initialization.'
  Assert-Contract (@((Read-LegadoJsonFile -Path $emptyStatePath).sources).Count -eq 0) 'Zero-element source arrays must remain arrays on disk.'
  $assertionCount += 2

  $manyPackagePath = Join-Path $tempRoot 'many-package.json'
  $manyStatePath = Join-Path $tempRoot 'many-state.json'
  $manyGovernancePath = Join-Path $tempRoot 'continuous-governance-state.json'
  Write-TestText -Path $manyPackagePath -Text $manyPackageText -Encoding $utf8NoBom
  $manyHash = Get-LegadoSha256ForBytes -Bytes ([System.IO.File]::ReadAllBytes($manyPackagePath))
  $legacyGovernance = [pscustomobject][ordered]@{
    schemaVersion = 1
    baseline = [pscustomobject][ordered]@{
      sourcePackageSha256 = $manyHash
      sourceCount = 3
      legadoCommit = $pinnedLegadoCommit
    }
    status = 'running'
    activeTaskId = 'TASK-RUNNING'
    tasks = @(
      [pscustomobject][ordered]@{ id = 'TASK-PASSED'; status = 'passed'; attempts = 5 },
      [pscustomobject][ordered]@{ id = 'TASK-RUNNING'; status = 'running'; attempts = 2 }
    )
    sourceValidation = [pscustomobject][ordered]@{ planned = 2; running = 1; passed = 0 }
    uiAudit = [pscustomobject][ordered]@{ captured = 7 }
    issues = @([pscustomobject][ordered]@{ id = 'ISSUE-RUNNING'; status = 'running'; attempts = 3 })
  }
  Write-TestJson -Path $manyGovernancePath -Value $legacyGovernance
  $initialManyState = Invoke-StateInitialization `
    -PackagePath $manyPackagePath `
    -StatePath $manyStatePath `
    -GovernancePath $manyGovernancePath `
    -ExpectedHash $manyHash `
    -ExpectedCount 3
  Assert-Contract ([int]$initialManyState.schemaVersion -eq 2) 'Merged state must use schema version 2.'
  Assert-Contract ([string]$initialManyState.machineFactSource -eq 'full-source-validation-state.json') 'Merged state must declare the canonical machine fact source.'
  Assert-Contract ([string]$initialManyState.governance.tasks[0].status -eq 'passed') 'Completed governance tasks must survive migration.'
  Assert-Contract ([int]$initialManyState.governance.tasks[0].attempts -eq 5) 'Completed governance task attempts must survive migration.'
  Assert-Contract ([string]$initialManyState.governance.tasks[1].status -eq 'planned') 'Stale running governance tasks must become retryable planned work.'
  Assert-Contract ([string]$initialManyState.governance.issues[0].status -eq 'planned') 'Stale running governance issues must become retryable planned work.'
  Assert-Contract ([int]$initialManyState.governance.sourceValidation.planned -eq 3) 'Governance source counts must be derived from canonical source records.'
  $assertionCount += 7

  $checkpointState = Read-LegadoJsonFile -Path $manyStatePath
  $checkpointState.sources[0].status = 'passed'
  $checkpointState.sources[0].attempts = 4
  $checkpointState.sources[0].lastOutcome = 'verified-result'
  $checkpointState.sources[0].workflows.search.status = 'passed'
  $checkpointState.sources[0].workflows.search.attempts = 2
  $checkpointState.sources[0].workflows.search.lastEvidenceDigest = ('A' * 64)
  [void]$checkpointState.sources[0].PSObject.Properties.Remove('sourceId')
  [void]$checkpointState.sources[0].PSObject.Properties.Remove('rawDocumentSha256')
  $checkpointState.sources[0].sourceHash = ('C' * 64)
  $checkpointState.sources[0] | Add-Member -NotePropertyName 'deviceReadiness' -NotePropertyValue ([pscustomobject][ordered]@{ present = $true; rawHashMatches = $true }) -Force
  $checkpointState.sources[1].status = 'running'
  $checkpointState.sources[1].attempts = 2
  $checkpointState.sources[1].workflows.content.status = 'running'
  $checkpointState.sources[1].workflows.content.attempts = 3
  $checkpointState.sources[2].status = 'failed'
  $checkpointState.sources[2].attempts = 1
  Write-LegadoStateCheckpoint -Path $manyStatePath -State $checkpointState
  $writtenCheckpoint = Read-LegadoJsonFile -Path $manyStatePath
  Assert-Contract ([int]$writtenCheckpoint.statusCounts.passed -eq 1 -and [int]$writtenCheckpoint.statusCounts.running -eq 1 -and [int]$writtenCheckpoint.statusCounts.failed -eq 1) 'Each checkpoint must atomically refresh derived source counts.'
  Assert-Contract ([string]$writtenCheckpoint.status -eq 'running') 'A checkpoint with active source work must atomically publish running status.'
  Assert-Contract ([int]$writtenCheckpoint.governance.sourceValidation.running -eq 1) 'The merged governance summary must derive from the same checkpoint records.'
  Assert-Contract ([int]$writtenCheckpoint.qualificationCounts.unverified -eq 3) 'Qualification counts must remain independent from workflow status until a semantic result is recorded.'
  $assertionCount += 4

  $recoveredState = Invoke-StateInitialization `
    -PackagePath $manyPackagePath `
    -StatePath $manyStatePath `
    -GovernancePath $manyGovernancePath `
    -ExpectedHash $manyHash `
    -ExpectedCount 3
  Assert-Contract ([string]$recoveredState.sources[0].status -eq 'passed') 'A completed source must not reset during recovery.'
  Assert-Contract ([int]$recoveredState.sources[0].attempts -eq 4) 'A completed source attempt count must not reset.'
  Assert-Contract ([string]$recoveredState.sources[0].workflows.search.status -eq 'passed') 'A completed workflow must not reset.'
  Assert-Contract ([string]$recoveredState.sources[0].workflows.search.lastEvidenceDigest -eq ('A' * 64)) 'Completed workflow evidence must not reset.'
  Assert-Contract (-not [bool]$recoveredState.sources[0].deviceReadiness.rawHashMatches) 'A legacy length-only raw hash claim must be invalidated during migration.'
  Assert-Contract ([string]$recoveredState.sources[0].deviceReadiness.rawHashVerification -eq 'pending_exact_digest_reaudit') 'Invalid legacy raw hash evidence must require an exact digest reaudit.'
  Assert-Contract ([string]$recoveredState.sources[0].sourceId -eq (Get-LegadoSha256ForText -Value $manyDocumentA)) 'A legacy reserialized identity must migrate to the raw-document sourceId by ordinal under the same package baseline.'
  Assert-Contract ([string]$recoveredState.sources[0].legacySourceHash -eq ('C' * 64)) 'The prior reserialized identity must remain as migration evidence.'
  Assert-Contract ([string]$recoveredState.sources[1].status -eq 'planned') 'A stale running source must become retryable planned work.'
  Assert-Contract ([int]$recoveredState.sources[1].attempts -eq 2) 'Recovery must retain the interrupted source attempt count.'
  Assert-Contract ([string]$recoveredState.sources[1].workflows.content.status -eq 'planned') 'A stale running workflow must become retryable planned work.'
  Assert-Contract ([int]$recoveredState.sources[1].workflows.content.attempts -eq 3) 'Recovery must retain the interrupted workflow attempt count.'
  Assert-Contract ([string]$recoveredState.sources[2].status -eq 'failed') 'A failed source must remain failed and retryable by the cursor.'
  Assert-Contract ([int]$recoveredState.statusCounts.running -eq 0) 'Canonical status counts must have no stale running source.'
  Assert-Contract ([int]$recoveredState.statusCounts.passed -eq 1 -and [int]$recoveredState.statusCounts.failed -eq 1) 'Canonical status counts must reflect preserved progress.'
  Assert-Contract ([int]$recoveredState.recovery.recordedSourceAndWorkflowRecoveryCount -eq 2) 'Recovery history must retain both the interrupted source and workflow records.'
  Assert-Contract ([int]$recoveredState.recovery.recordedGovernanceRecoveryCount -eq 3) 'Recovery history must retain interrupted governance records.'
  $assertionCount += 17

  $pointerState = Read-LegadoJsonFile -Path $manyGovernancePath
  Assert-Contract (-not [bool]$pointerState.isMachineFactSource) 'Legacy governance state must become a non-authoritative pointer.'
  Assert-Contract ([string]$pointerState.canonicalStatePath -eq [System.IO.Path]::GetFileName($manyStatePath)) 'Legacy pointer must identify the canonical state file.'
  Assert-Contract ($null -eq (Get-PropertyValue -Object $pointerState -Name 'tasks')) 'Legacy pointer must not retain a second mutable task ledger.'
  $assertionCount += 3

  $idempotentState = Invoke-StateInitialization `
    -PackagePath $manyPackagePath `
    -StatePath $manyStatePath `
    -GovernancePath $manyGovernancePath `
    -ExpectedHash $manyHash `
    -ExpectedCount 3
  Assert-Contract ([int]$idempotentState.recovery.staleSourceAndWorkflowCount -eq 0) 'A second recovery pass must be idempotent.'
  Assert-Contract ([int]$idempotentState.recovery.staleGovernanceCount -eq 0) 'Governance recovery must be idempotent.'
  Assert-Contract ([string]$idempotentState.sources[0].status -eq 'passed' -and [int]$idempotentState.sources[0].attempts -eq 4) 'Idempotent initialization must retain completed progress.'
  Assert-Contract ([string]$idempotentState.sources[0].legacySourceHash -eq ('C' * 64)) 'Idempotent initialization must retain the migrated legacy identity evidence.'
  Assert-Contract ([string]$idempotentState.sources[0].deviceReadiness.rawHashVerification -eq 'pending_exact_digest_reaudit') 'A second pass must not promote invalidated readiness evidence.'
  Assert-Contract ([int]$idempotentState.recovery.recordedSourceAndWorkflowRecoveryCount -eq 2) 'Idempotent initialization must retain source recovery history.'
  Assert-Contract ([int]$idempotentState.recovery.recordedGovernanceRecoveryCount -eq 3) 'Idempotent initialization must retain governance recovery history.'
  $assertionCount += 7

  $compileRecoveryState = Read-LegadoJsonFile -Path $manyStatePath
  $compileRecoveryState.sources[2].status = 'blocked'
  $compileRecoveryState.sources[2].attempts = 0
  $compileRecoveryState.sources[2].lastOutcome = 'device_compile_blocked'
  $compileRecoveryState.sources[2].semanticQualification = 'unverified'
  $compileRecoveryState.sources[2] | Add-Member -NotePropertyName 'deviceReadiness' -NotePropertyValue ([pscustomobject][ordered]@{
    present = $true
    rawHashMatches = $true
    rawHashVerification = 'exact_digest_match'
    compileStatus = 'ready'
    engineMode = 'v2_enabled'
  }) -Force
  foreach ($workflowProperty in $compileRecoveryState.sources[2].workflows.PSObject.Properties) {
    $workflowProperty.Value.status = 'blocked'
    $workflowProperty.Value.attempts = 0
    $workflowProperty.Value.lastOutcome = 'device_compile_blocked'
  }
  Write-LegadoStateCheckpoint -Path $manyStatePath -State $compileRecoveryState
  $compileRecoveredState = Invoke-StateInitialization `
    -PackagePath $manyPackagePath `
    -StatePath $manyStatePath `
    -GovernancePath $manyGovernancePath `
    -ExpectedHash $manyHash `
    -ExpectedCount 3
  Assert-Contract ([string]$compileRecoveredState.sources[2].status -eq 'planned') 'A historical compile block superseded by current V2-ready evidence must become planned work.'
  Assert-Contract ([string]$compileRecoveredState.sources[2].lastOutcome -eq 'recovery_pending_v2_execution') 'Superseded compile-block recovery must preserve an explicit pending-execution outcome.'
  Assert-Contract ([string]$compileRecoveredState.sources[2].lastRecovery.reason -eq 'compile_block_superseded_by_device_ready') 'Superseded compile-block recovery must retain its narrow reason.'
  Assert-Contract (@($compileRecoveredState.sources[2].workflows.PSObject.Properties | Where-Object { [string]$_.Value.status -ne 'planned' -or [int]$_.Value.attempts -ne 0 }).Count -eq 0) 'A recovered zero-attempt compile block must return every workflow to planned without fabricating attempts.'
  $assertionCount += 4

  $atomicArtifacts = @(Get-ChildItem -LiteralPath $tempRoot -File | Where-Object { $_.Name -match '\.(tmp|replace)\.' })
  Assert-Contract ($atomicArtifacts.Count -eq 0) 'Atomic checkpoints must not leave temporary or replacement files.'
  $assertionCount++

  $mismatchStatePath = Join-Path $tempRoot 'mismatch-state.json'
  $mismatchGovernancePath = Join-Path $tempRoot 'mismatch-governance.json'
  $mismatchInitial = Invoke-StateInitialization `
    -PackagePath $manyPackagePath `
    -StatePath $mismatchStatePath `
    -GovernancePath $mismatchGovernancePath `
    -ExpectedHash $manyHash `
    -ExpectedCount 3
  $mismatchInitial.sources[0].status = 'passed'
  $mismatchInitial.sources[0].attempts = 9
  Write-LegadoStateCheckpoint -Path $mismatchStatePath -State $mismatchInitial
  $packageMismatchThrown = $false
  try {
    [void](Invoke-StateInitialization `
      -PackagePath $manyPackagePath `
      -StatePath $mismatchStatePath `
      -GovernancePath $mismatchGovernancePath `
      -ExpectedHash ('B' * 64) `
      -ExpectedCount 3)
  } catch {
    $packageMismatchThrown = $_.Exception.Message.Contains('SOURCE_PACKAGE_SHA256_MISMATCH')
  }
  $packageBlockedState = Read-LegadoJsonFile -Path $mismatchStatePath
  Assert-Contract $packageMismatchThrown 'A package hash mismatch must fail initialization.'
  Assert-Contract ([string]$packageBlockedState.status -eq 'blocked' -and [string]$packageBlockedState.block.code -eq 'SOURCE_PACKAGE_SHA256_MISMATCH') 'A package hash mismatch must atomically persist blocked state.'
  Assert-Contract ([string]$packageBlockedState.sources[0].status -eq 'passed' -and [int]$packageBlockedState.sources[0].attempts -eq 9) 'Blocking a changed input must not reset completed progress.'
  $assertionCount += 3

  $commitStatePath = Join-Path $tempRoot 'commit-state.json'
  $commitGovernancePath = Join-Path $tempRoot 'commit-governance.json'
  [void](Invoke-StateInitialization `
    -PackagePath $manyPackagePath `
    -StatePath $commitStatePath `
    -GovernancePath $commitGovernancePath `
    -ExpectedHash $manyHash `
    -ExpectedCount 3)
  $commitMismatchThrown = $false
  try {
    [void](Invoke-StateInitialization `
      -PackagePath $manyPackagePath `
      -StatePath $commitStatePath `
      -GovernancePath $commitGovernancePath `
      -ExpectedHash $manyHash `
      -ExpectedCount 3 `
      -LegadoCommit ('F' * 40) `
      -ExpectedCommit $pinnedLegadoCommit)
  } catch {
    $commitMismatchThrown = $_.Exception.Message.Contains('LEGADO_COMMIT_MISMATCH')
  }
  $commitBlockedState = Read-LegadoJsonFile -Path $commitStatePath
  Assert-Contract $commitMismatchThrown 'A Legado commit mismatch must fail initialization.'
  Assert-Contract ([string]$commitBlockedState.status -eq 'blocked' -and [string]$commitBlockedState.block.code -eq 'LEGADO_COMMIT_MISMATCH') 'A Legado commit mismatch must atomically persist blocked state.'
  $assertionCount += 2

  Assert-Contract (Test-LegadoRawHashMatch -ExpectedSha256 ('A' * 64) -ActualSha256 ('a' * 64)) 'Raw hash comparison must be case-insensitive and compare the complete digest.'
  Assert-Contract (-not (Test-LegadoRawHashMatch -ExpectedSha256 ('A' * 64) -ActualSha256 ('B' * 64))) 'Different complete raw hashes must not match.'
  Assert-Contract (-not (Test-LegadoRawHashMatch -ExpectedSha256 ('A' * 64) -ActualSha256 '64-characters-is-not-a-digest')) 'Digest length alone must never count as a raw hash match.'
  $assertionCount += 3

  $readinessText = [System.IO.File]::ReadAllText($readinessPath, $utf8NoBom)
  Assert-Contract ($readinessText.Contains('rawHashMatches = Test-LegadoRawHashMatch')) 'Device readiness must use the complete raw hash comparator.'
  Assert-Contract (-not [regex]::IsMatch($readinessText, 'rawHashMatches\s*=.*\.Length\s*-eq\s*64')) 'Device readiness must not treat a 64-character value as a successful match.'
  Assert-Contract ($readinessText.Contains("'exact_digest_match'")) 'Device readiness must label successful exact digest verification.'
  Assert-Contract ($readinessText.Contains("'digest_mismatch'")) 'Device readiness must label an exact digest mismatch.'
  $assertionCount += 4

  if (Test-Path -LiteralPath $PinnedSourcePackageDirectory) {
    $pinnedPath = ''
    foreach ($candidate in @(Get-ChildItem -LiteralPath $PinnedSourcePackageDirectory -Filter '*.json' -File)) {
      $candidateHash = Get-LegadoSha256ForBytes -Bytes ([System.IO.File]::ReadAllBytes($candidate.FullName))
      if ($candidateHash -eq $pinnedPackageSha256) {
        $pinnedPath = $candidate.FullName
        break
      }
    }
    if ($pinnedPath.Length -gt 0) {
      $pinnedText = [System.IO.File]::ReadAllText($pinnedPath, [System.Text.UTF8Encoding]::new($false, $true))
      $pinnedDocuments = @(Get-LegadoRawSourceDocuments -Json $pinnedText -Label 'pinned 458-source package')
      Assert-Contract ($pinnedDocuments.Count -eq 458) 'Pinned package must expose exactly 458 raw source documents.'
      Assert-Contract ((Get-LegadoSha256ForText -Value $pinnedDocuments[249]) -eq $knownImageRawDocumentSha256) 'Pinned IMAGE sample must use its known raw-document identity, not its reserialized hash.'
      $assertionCount += 2
      $realPackageChecked = $true
    }
  }

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    hostVersion = [string]$PSVersionTable.PSVersion
    status = 'passed'
    assertionCount = $assertionCount
    realPinnedPackageChecked = $realPackageChecked
    sourceIdentity = 'sha256(utf8(rawTopLevelJsonObjectWithoutBom))'
    canonicalState = 'full-source-validation-state.json'
    legacyGovernanceState = 'non-authoritative-pointer'
  }
  Write-LegadoStateCheckpoint -Path $ResultPath -State $result -Depth 8
  Write-Output ($result | ConvertTo-Json -Depth 8 -Compress)
} finally {
  $resolvedTempRoot = [System.IO.Path]::GetFullPath($tempRoot)
  $resolvedTempBase = [System.IO.Path]::GetFullPath($tempBase)
  if ($resolvedTempRoot.StartsWith($resolvedTempBase, [System.StringComparison]::OrdinalIgnoreCase) -and
    (Test-Path -LiteralPath $resolvedTempRoot)) {
    Remove-Item -LiteralPath $resolvedTempRoot -Recurse -Force
  }
}
