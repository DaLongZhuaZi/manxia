[CmdletBinding()]
param(
  [string]$HdcPath = 'F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe',
  [string]$Device = '',
  [string]$PythonPath = '',
  [string]$SourcePackagePath = '',
  [string]$StatePath = '',
  [string]$LegacyGovernancePath = '',
  [string]$LegadoRepositoryPath = 'F:\DevEcoStudioProject\manxia\legado',
  [string]$EvidenceDirectory = '',
  [string]$RunActivityPath = '',
  [ValidateSet('safe_search_only', 'safe_read_path', 'full_workflow')]
  [string]$ExecutionProfile = 'safe_search_only',
  [ValidateRange(1, 458)]
  [int]$MaxSources = 458,
  [ValidateRange(-1, 457)]
  [int]$OnlyOrdinal = -1,
  [ValidateRange(1, 60)]
  [int]$MinRequestIntervalSeconds = 2,
  [ValidateRange(45, 120)]
  [int]$UiTimeoutSeconds = 105,
  [bool]$RequireFreshReadiness = $true,
  [switch]$AllowIdempotentPostSearch,
  [switch]$RevalidateTerminalSources
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ExpectedSourcePackageSha256 = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$script:ExpectedSourceCount = 458
$script:ExpectedLegadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$script:LastRequestAt = $null
$script:RunId = "v2-hypium-full-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
$script:ResultSummary = New-Object 'System.Collections.Generic.List[object]'

if ($StatePath.Length -eq 0) { $StatePath = Join-Path $PSScriptRoot 'state\full-source-validation-state.json' }
if ($LegacyGovernancePath.Length -eq 0) { $LegacyGovernancePath = Join-Path $PSScriptRoot 'state\continuous-governance-state.json' }
$evidencePathsModulePath = Join-Path $PSScriptRoot 'LegadoHypiumEvidencePaths.psm1'
if (-not (Test-Path -LiteralPath $evidencePathsModulePath)) { throw 'HYPIUM_EVIDENCE_PATHS_MODULE_MISSING' }
Import-Module -Name $evidencePathsModulePath -Force -ErrorAction Stop
if ($EvidenceDirectory.Length -eq 0) {
  $EvidenceDirectory = New-LegadoHypiumRunEvidenceDirectory -ScriptRoot $PSScriptRoot
}
$EvidenceDirectory = Assert-LegadoHypiumRunEvidenceDirectory -ScriptRoot $PSScriptRoot -EvidenceDirectory $EvidenceDirectory
if ($RunActivityPath.Length -eq 0) { $RunActivityPath = Join-Path $EvidenceDirectory 'run-activity.json' }
$RunActivityPath = Assert-LegadoHypiumRunActivityPath -EvidenceDirectory $EvidenceDirectory -RunActivityPath $RunActivityPath
if ($PythonPath.Length -eq 0) { $PythonPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) '.venv\Scripts\python.exe' }

$stateModulePath = Join-Path $PSScriptRoot 'LegadoFullSourceState.psm1'
$evidenceProjectionModulePath = Join-Path $PSScriptRoot 'LegadoHypiumEvidenceProjection.psm1'
$workflowSettlementModulePath = Join-Path $PSScriptRoot 'LegadoHypiumWorkflowSettlement.psm1'
$nativeProcessHelperPath = Join-Path $PSScriptRoot 'Invoke-LegadoNativeProcess.ps1'
$driverPath = Join-Path $PSScriptRoot 'Invoke-LegadoV2HypiumNavigation.py'
Import-Module -Name $stateModulePath -Force -ErrorAction Stop
Import-Module -Name $evidenceProjectionModulePath -Force -ErrorAction Stop
Import-Module -Name $workflowSettlementModulePath -Force -ErrorAction Stop
. $nativeProcessHelperPath

function Get-HypiumNow {
  # Evidence freshness is cross-device and cross-time-zone. Persist only an
  # explicit UTC instant; local offsets can otherwise make a same-day run look
  # like a future witness to the canonical state machine.
  return [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Get-HypiumTextProperty {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return '' }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return '' }
  return [string]$property.Value
}

function Get-HypiumBooleanProperty {
  param([object]$Object, [string]$Name)
  # Get-HypiumTextProperty returns a string. In PowerShell, casting the
  # non-empty string 'False' to [bool] yields $true, so parse this fixed
  # transport token explicitly before publishing evidence.
  return (Get-HypiumTextProperty -Object $Object -Name $Name).Trim().ToLowerInvariant() -eq 'true'
}

function Get-HypiumHeaderNames {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return @() }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return @() }
  $names = New-Object 'System.Collections.Generic.List[string]'
  foreach ($value in @($property.Value)) {
    $name = ([string]$value).Trim().ToLowerInvariant()
    if ($name -match '^[a-z0-9-]{1,64}$' -and -not $names.Contains($name)) {
      [void]$names.Add($name)
    }
  }
  return $names.ToArray()
}

function Get-HypiumArrayProperty {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) { return @() }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return @() }
  return @($property.Value)
}

function Get-HypiumImageTraceOutcomeCounts {
  param([object]$ImageTrace, [string]$Name)
  $result = [ordered]@{}
  if ($null -eq $ImageTrace) { return $result }
  $property = $ImageTrace.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $result }
  foreach ($item in @($property.Value.PSObject.Properties)) {
    $key = Get-HypiumSafeToken -Value ([string]$item.Name) -Fallback ''
    if ($key.Length -le 0) { continue }
    $value = [int]([string]$item.Value)
    if ($value -gt 0) { $result[$key] = $value }
  }
  return $result
}

function Test-HypiumImageTraceDnsOnly {
  param([object]$ImageTrace)
  if ($null -eq $ImageTrace) { return $false }
  $requestCount = [int](Get-HypiumTextProperty -Object $ImageTrace -Name 'requestStarted')
  $httpResponseCount = [int](Get-HypiumTextProperty -Object $ImageTrace -Name 'httpResponses')
  $decodeCompleteCount = [int](Get-HypiumTextProperty -Object $ImageTrace -Name 'decodeComplete')
  $failures = Get-HypiumImageTraceOutcomeCounts -ImageTrace $ImageTrace -Name 'failureOutcomes'
  return $requestCount -gt 0 -and $httpResponseCount -eq 0 -and $decodeCompleteCount -eq 0 -and
    $failures.Count -eq 1 -and $failures.Contains('network_dns')
}

function Get-HypiumTargetDigestArrayProperty {
  param([object]$Object, [string]$Name)
  $digests = New-Object 'System.Collections.Generic.List[string]'
  foreach ($value in @(Get-HypiumArrayProperty -Object $Object -Name $Name)) {
    $digest = ([string]$value).Trim().ToLowerInvariant()
    # Device evidence must never persist a target value. Accept only the
    # fixed absence markers and one-way target SHA-256 digests emitted by the
    # Driver's sanitized trace parser.
    if ($digest -match '^(empty|digest_error|[0-9a-f]{64})$' -and $digests.Count -lt 8) {
      [void]$digests.Add($digest)
    }
  }
  return $digests.ToArray()
}

function Get-HypiumReaderContentEvidence {
  param([object]$Evidence)
  $readerProperty = $Evidence.PSObject.Properties['reader']
  if ($null -eq $readerProperty -or $null -eq $readerProperty.Value) { return $null }
  $reader = $readerProperty.Value
  $readerEvidenceProperty = $reader.PSObject.Properties['v2_content_execution_evidence']
  if ($null -eq $readerEvidenceProperty -or $null -eq $readerEvidenceProperty.Value) { return $null }
  $readerEvidence = $readerEvidenceProperty.Value
  $fingerprint = Get-HypiumTextProperty -Object $readerEvidence -Name 'contentFingerprint'
  if ($fingerprint -notmatch '^[0-9a-fA-F]{16}$') { return $null }
  return [pscustomobject][ordered]@{
    state = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $readerEvidence -Name 'state') -Fallback 'unclassified'
    engine = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $readerEvidence -Name 'engine') -Fallback 'unclassified'
    contentCharacterCount = [int](Get-HypiumTextProperty -Object $readerEvidence -Name 'contentCharacterCount')
    contentFingerprint = $fingerprint.ToLowerInvariant()
    contentLineFeedCount = [int](Get-HypiumTextProperty -Object $readerEvidence -Name 'contentLineFeedCount')
    contentCarriageReturnCount = [int](Get-HypiumTextProperty -Object $readerEvidence -Name 'contentCarriageReturnCount')
    contentLeadingWhitespaceCount = [int](Get-HypiumTextProperty -Object $readerEvidence -Name 'contentLeadingWhitespaceCount')
    contentTrailingWhitespaceCount = [int](Get-HypiumTextProperty -Object $readerEvidence -Name 'contentTrailingWhitespaceCount')
    traceOccurredAt = [Int64](Get-HypiumTextProperty -Object $readerEvidence -Name 'traceOccurredAt')
    tracePersisted = (Get-HypiumTextProperty -Object $readerEvidence -Name 'tracePersisted') -eq 'True'
  }
}

function Set-HypiumProperty {
  param([object]$Object, [string]$Name, [object]$Value)
  $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Get-HypiumSafeToken {
  param([string]$Value, [string]$Fallback = 'unclassified')
  $candidate = $Value.Trim().ToLowerInvariant()
  if ($candidate -match '^[a-z0-9_:-]{1,80}$') { return $candidate }
  return $Fallback
}

function Refresh-HypiumGovernanceDocuments {
  $compatibilityScript = Join-Path $PSScriptRoot 'Invoke-LegadoCompatibility.ps1'
  if (-not (Test-Path -LiteralPath $compatibilityScript)) {
    throw 'COMPATIBILITY_DOCUMENT_REFRESH_SCRIPT_MISSING'
  }
  $powerShellHost = Get-LegadoNativeHostExecutable
  $refreshResult = Invoke-LegadoNativeProcess `
    -FilePath $powerShellHost `
    -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $compatibilityScript, '-RefreshDocumentsOnly') `
    -TimeoutSeconds 90 `
    -WorkingDirectory (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
  if ($refreshResult.timedOut -or $refreshResult.exitCode -ne 0) {
    throw 'COMPATIBILITY_DOCUMENT_REFRESH_FAILED'
  }
}

function Write-HypiumJsonAtomically {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
  $temporaryPath = $Path + '.tmp-' + $PID + '-' + [Guid]::NewGuid().ToString('N')
  $backupPath = ''
  try {
    [System.IO.File]::WriteAllText($temporaryPath, [string]($Value | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
    if (Test-Path -LiteralPath $Path) {
      # File.Replace requires a non-empty backup path in PowerShell-hosted .NET;
      # an ephemeral sibling preserves atomic replacement without retaining data.
      $backupPath = $Path + '.replace-backup-' + [Guid]::NewGuid().ToString('N')
      [System.IO.File]::Replace($temporaryPath, $Path, $backupPath)
    } else {
      [System.IO.File]::Move($temporaryPath, $Path)
    }
  } finally {
    if ($backupPath.Length -gt 0 -and (Test-Path -LiteralPath $backupPath)) { [System.IO.File]::Delete($backupPath) }
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Write-HypiumRunActivity {
  param(
    [ValidateSet('starting', 'running', 'passed', 'failed')]
    [string]$Status,
    [string]$Phase,
    [int]$Ordinal = -1,
    [string]$SourceId = '',
    [int]$ScheduledSources = 0,
    [int]$CompletedSources = 0,
    [string]$Outcome = '',
    [string]$ErrorDigest = '',
    [string]$EvidencePath = ''
  )
  $previousEvidencePath = ''
  $previousRunId = ''
  if ([string]::IsNullOrWhiteSpace($EvidencePath) -and (Test-Path -LiteralPath $RunActivityPath -PathType Leaf)) {
    try {
      $previousActivity = [System.IO.File]::ReadAllText($RunActivityPath, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
      $previousRunIdProperty = $previousActivity.PSObject.Properties['runId']
      if ($null -ne $previousRunIdProperty -and $null -ne $previousRunIdProperty.Value) {
        $previousRunId = [string]$previousRunIdProperty.Value
      }
      $previousEvidenceProperty = $previousActivity.PSObject.Properties['evidencePath']
      if ($previousRunId -eq [string]$script:RunId -and $null -ne $previousEvidenceProperty -and $null -ne $previousEvidenceProperty.Value) {
        $previousEvidencePath = [string]$previousEvidenceProperty.Value
      }
    } catch {
      $previousEvidencePath = ''
    }
  }
  $boundEvidencePath = if ([string]::IsNullOrWhiteSpace($EvidencePath)) { $previousEvidencePath } else { $EvidencePath }
  $activity = [pscustomobject][ordered]@{
    schemaVersion = 1
    generatedAt = Get-HypiumNow
    runId = $script:RunId
    status = $Status
    phase = Get-HypiumSafeToken -Value $Phase -Fallback 'unclassified'
    executionProfile = Get-HypiumSafeToken -Value $ExecutionProfile -Fallback 'unclassified'
    ordinal = $Ordinal
    sourceId = $SourceId
    scheduledSources = $ScheduledSources
    completedSources = $CompletedSources
    outcome = Get-HypiumSafeToken -Value $Outcome -Fallback ''
    errorDigest = $ErrorDigest
    evidencePath = $boundEvidencePath
  }
  Write-HypiumJsonAtomically -Path $RunActivityPath -Value $activity
}

function Clear-HypiumRunActivityArtifacts {
  $directory = Split-Path -Parent $RunActivityPath
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { return }
  $activityFileName = [System.IO.Path]::GetFileName($RunActivityPath)
  $temporaryPrefix = $activityFileName + '.tmp-'
  $backupPrefix = $activityFileName + '.replace-backup-'
  foreach ($candidate in @(Get-ChildItem -LiteralPath $directory -File -ErrorAction Stop)) {
    if ($candidate.Name.StartsWith($temporaryPrefix) -or $candidate.Name.StartsWith($backupPrefix)) {
      [System.IO.File]::Delete($candidate.FullName)
    }
  }
}

function Get-HypiumDeviceProcessState {
  param([string]$BundleName)
  try {
    $pid = (& $HdcPath -t $Device shell pidof $BundleName 2>$null | Out-String).Trim()
    if ($pid.Length -eq 0) { return 'pid_missing' }
    return 'pid_present'
  } catch {
    return 'pid_probe_failed'
  }
}

function Resolve-HypiumDevice {
  if ($Device.Trim().Length -gt 0) { return $Device.Trim() }
  $output = (& $HdcPath list targets 2>$null | Out-String)
  $candidates = New-Object 'System.Collections.Generic.List[string]'
  foreach ($line in @($output -split "`r?`n")) {
    $candidate = $line.Trim()
    if ($candidate.Length -gt 0 -and -not $candidate.StartsWith('[')) {
      [void]$candidates.Add($candidate)
    }
  }
  if ($candidates.Count -ne 1) {
    throw "DEVICE_AUTO_DISCOVERY_EXPECTED_ONE_FOUND_$($candidates.Count)"
  }
  return $candidates[0]
}

function Resolve-HypiumSourcePackagePath {
  param([string]$RequestedPath)
  if ($RequestedPath.Trim().Length -gt 0) {
    return $RequestedPath
  }
  $candidateDirectory = 'F:\Downloads-E'
  if (-not (Test-Path -LiteralPath $candidateDirectory -PathType Container)) {
    throw 'PINNED_SOURCE_PACKAGE_DIRECTORY_MISSING'
  }
  $matches = New-Object 'System.Collections.Generic.List[string]'
  foreach ($candidate in @(Get-ChildItem -LiteralPath $candidateDirectory -File -Filter '*.json' -ErrorAction Stop)) {
    $hash = (Get-FileHash -LiteralPath $candidate.FullName -Algorithm SHA256).Hash.ToUpperInvariant()
    if ($hash -eq $script:ExpectedSourcePackageSha256) {
      [void]$matches.Add($candidate.FullName)
    }
  }
  if ($matches.Count -ne 1) {
    throw "PINNED_SOURCE_PACKAGE_EXPECTED_ONE_FOUND_$($matches.Count)"
  }
  return $matches[0]
}

function Write-HypiumMissingResult {
  param([string]$OutputDirectory, [object]$ProcessResult)
  $checkpointPath = Join-Path $OutputDirectory 'checkpoint.json'
  $checkpointStage = 'checkpoint_missing'
  if (Test-Path -LiteralPath $checkpointPath) {
    try {
      $checkpoint = Read-LegadoJsonFile -Path $checkpointPath
      $checkpointStage = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $checkpoint -Name 'stage') -Fallback 'checkpoint_invalid'
    } catch {
      $checkpointStage = 'checkpoint_invalid'
    }
  }
  $processState = Get-HypiumDeviceProcessState -BundleName 'com.dlzz.manxia'
  $category = if ($processState -eq 'pid_missing') { 'app_exited' } else { 'runner_timeout' }
  $fallback = [pscustomobject][ordered]@{
    status = 'failed'; search_outcome = $category; search_error_category = $category; driver_closed = $false
    checkpoint_stage = $checkpointStage; process_classification = $processState
    error = 'hypium_result_missing_' + $category
    native_process_classification = Get-HypiumSafeToken -Value ([string]$ProcessResult.classification) -Fallback 'unclassified'
  }
  Write-HypiumJsonAtomically -Path (Join-Path $OutputDirectory 'result.json') -Value $fallback
}

function Set-HypiumWorkflow {
  param([object]$State, [object]$Record, [string]$Name, [string]$Status, [string]$Outcome, [string]$Digest = '', [switch]$IncrementAttempt)
  $workflow = $Record.workflows.PSObject.Properties[$Name].Value
  if ($IncrementAttempt) { Set-HypiumProperty -Object $workflow -Name 'attempts' -Value ([int]$workflow.attempts + 1) }
  Set-HypiumProperty -Object $workflow -Name 'status' -Value $Status
  Set-HypiumProperty -Object $workflow -Name 'lastOutcome' -Value (Get-HypiumSafeToken -Value $Outcome)
  Set-HypiumProperty -Object $workflow -Name 'lastEvidenceDigest' -Value $Digest
  Set-HypiumProperty -Object $workflow -Name 'lastUpdatedAt' -Value (Get-HypiumNow)
  Write-LegadoStateCheckpoint -Path $StatePath -State $State
}

function Set-HypiumSource {
  param([object]$State, [object]$Record, [string]$Status, [string]$Outcome, [string]$Profile)
  Set-HypiumProperty -Object $Record -Name 'status' -Value $Status
  Set-HypiumProperty -Object $Record -Name 'lastOutcome' -Value (Get-HypiumSafeToken -Value $Outcome)
  Set-HypiumProperty -Object $Record -Name 'validationProfile' -Value $Profile
  Set-HypiumProperty -Object $Record -Name 'lastUpdatedAt' -Value (Get-HypiumNow)
  Write-LegadoStateCheckpoint -Path $StatePath -State $State
}

function Set-HypiumSemanticQualification {
  param([object]$Record, [string]$Qualification)
  Set-HypiumProperty -Object $Record -Name 'semanticQualification' -Value (Get-HypiumSafeToken -Value $Qualification -Fallback 'unverified')
}

function Sync-HypiumSourceAttempt {
  param([object]$State, [object]$Record)
  $maximumWorkflowAttempt = 0
  foreach ($workflowProperty in @($Record.workflows.PSObject.Properties)) {
    $attempts = [int](Get-HypiumTextProperty -Object $workflowProperty.Value -Name 'attempts')
    if ($attempts -gt $maximumWorkflowAttempt) { $maximumWorkflowAttempt = $attempts }
  }
  $sourceAttempts = [int](Get-HypiumTextProperty -Object $Record -Name 'attempts')
  # Source evidence binds to the current workflow matrix, not to a stale
  # source-level counter copied from an earlier batch. Reconcile in both
  # directions so a previous larger source attempt cannot survive after the
  # current workflows have been rebuilt with fewer attempts.
  if ($sourceAttempts -ne $maximumWorkflowAttempt) {
    Set-HypiumProperty -Object $Record -Name 'attempts' -Value $maximumWorkflowAttempt
    Set-HypiumProperty -Object $Record -Name 'attemptsReconciledAt' -Value (Get-HypiumNow)
  }
}

function Set-HypiumNonSearchPolicy {
  param([object]$State, [object]$Record, [switch]$KeepReadWorkflows)
  $workflowNames = if ($KeepReadWorkflows) {
    @('explore', 'file', 'review')
  } else {
    @('explore', 'bookInfo', 'toc', 'content', 'file', 'review')
  }
  foreach ($name in $workflowNames) {
    $outcome = if ($KeepReadWorkflows -and $name -eq 'explore') {
      'safe_read_path_explore_deferred'
    } elseif ($KeepReadWorkflows -and $name -eq 'file') {
      'safe_read_path_file_not_declared'
    } elseif ($KeepReadWorkflows -and $name -eq 'review') {
      'safe_read_path_review_not_declared'
    } else {
      'profile_safe_search_only'
    }
    Set-HypiumWorkflow -State $State -Record $Record -Name $name -Status 'policy_blocked' -Outcome $outcome
  }
}

function Set-HypiumSafeReadWorkflowsRunning {
  param([object]$State, [object]$Record)
  foreach ($name in @('bookInfo', 'toc', 'content')) {
    $capabilityProperty = $Record.capabilities.PSObject.Properties[$name]
    $capabilityAvailable = $null -ne $capabilityProperty -and [bool]$capabilityProperty.Value
    if ($capabilityAvailable) {
      Set-HypiumWorkflow -State $State -Record $Record -Name $name -Status 'running' -Outcome 'safe_read_path_requested' -IncrementAttempt
    } else {
      Set-HypiumWorkflow -State $State -Record $Record -Name $name -Status 'policy_blocked' -Outcome ('{0}_workflow_missing' -f $name)
    }
  }
}

function Set-HypiumFullWorkflowExploreReadWorkflowsRunning {
  param([object]$State, [object]$Record)
  foreach ($name in @('bookInfo', 'toc', 'content')) {
    $capabilityProperty = $Record.capabilities.PSObject.Properties[$name]
    $capabilityAvailable = $null -ne $capabilityProperty -and [bool]$capabilityProperty.Value
    if ($capabilityAvailable) {
      Set-HypiumWorkflow -State $State -Record $Record -Name $name -Status 'running' -Outcome 'full_workflow_explore_read_path_requested' -IncrementAttempt
    } else {
      Set-HypiumWorkflow -State $State -Record $Record -Name $name -Status 'policy_blocked' -Outcome ('{0}_workflow_missing' -f $name)
    }
  }
}

function Set-HypiumSafeReadExploreOnlyWorkflowsRunning {
  param([object]$State, [object]$Record)
  Set-HypiumWorkflow -State $State -Record $Record -Name 'search' -Status 'policy_blocked' -Outcome 'search_workflow_missing'
  $readCapabilitiesReady = $true
  foreach ($name in @('bookInfo', 'toc', 'content')) {
    $capabilityProperty = $Record.capabilities.PSObject.Properties[$name]
    if ($null -eq $capabilityProperty -or -not [bool]$capabilityProperty.Value) {
      $readCapabilitiesReady = $false
      break
    }
  }
  foreach ($name in @('bookInfo', 'toc', 'content')) {
    $capabilityProperty = $Record.capabilities.PSObject.Properties[$name]
    $capabilityAvailable = $null -ne $capabilityProperty -and [bool]$capabilityProperty.Value
    if (-not $capabilityAvailable) {
      Set-HypiumWorkflow -State $State -Record $Record -Name $name -Status 'policy_blocked' -Outcome ('{0}_workflow_missing' -f $name)
    } elseif ($readCapabilitiesReady) {
      Set-HypiumWorkflow -State $State -Record $Record -Name $name -Status 'running' -Outcome 'safe_read_path_explore_read_requested' -IncrementAttempt
    } else {
      Set-HypiumWorkflow -State $State -Record $Record -Name $name -Status 'blocked' -Outcome 'safe_read_path_read_chain_capability_dependency_missing'
    }
  }
  Set-HypiumWorkflow -State $State -Record $Record -Name 'file' -Status 'policy_blocked' -Outcome 'safe_read_path_file_not_declared'
  Set-HypiumWorkflow -State $State -Record $Record -Name 'review' -Status 'policy_blocked' -Outcome 'safe_read_path_review_not_declared'
  Set-HypiumWorkflow -State $State -Record $Record -Name 'explore' -Status 'running' -Outcome 'safe_read_path_explore_requested' -IncrementAttempt
}

function Set-HypiumExploreOnlyReadTerminal {
  param([object]$State, [object]$Record, [string]$Status, [string]$Outcome)
  foreach ($name in @('bookInfo', 'toc', 'content')) {
    $workflow = $Record.workflows.PSObject.Properties[$name].Value
    if ([string]$workflow.status -in @('planned', 'running')) {
      Set-HypiumWorkflow -State $State -Record $Record -Name $name -Status $Status -Outcome $Outcome
    }
  }
}

function Test-HypiumExploreReadCapabilitySet {
  param([object]$Record)
  foreach ($name in @('bookInfo', 'toc', 'content')) {
    $property = $Record.capabilities.PSObject.Properties[$name]
    if ($null -eq $property -or -not [bool]$property.Value) { return $false }
  }
  return $true
}

function Set-HypiumFullWorkflowPlanning {
  param(
    [object]$State,
    [object]$Record,
    [bool]$HasSearch,
    [bool]$HasExplore
  )
  if ($HasSearch) {
    Set-HypiumWorkflow -State $State -Record $Record -Name 'search' -Status 'planned' -Outcome 'full_workflow_search_planned'
  } else {
    Set-HypiumWorkflow -State $State -Record $Record -Name 'search' -Status 'policy_blocked' -Outcome 'search_workflow_missing'
  }
  if ($HasExplore) {
    Set-HypiumWorkflow -State $State -Record $Record -Name 'explore' -Status 'planned' -Outcome 'full_workflow_explore_planned'
  } else {
    Set-HypiumWorkflow -State $State -Record $Record -Name 'explore' -Status 'policy_blocked' -Outcome 'explore_workflow_missing'
  }
  $capabilities = @{
    bookInfo = [bool]$Record.capabilities.bookInfo
    toc = [bool]$Record.capabilities.toc
    content = [bool]$Record.capabilities.content
  }
  foreach ($name in @('bookInfo', 'toc', 'content')) {
    if ([bool]$capabilities[$name]) {
      Set-HypiumWorkflow -State $State -Record $Record -Name $name -Status 'planned' -Outcome ('full_workflow_{0}_planned' -f $name)
    } else {
      Set-HypiumWorkflow -State $State -Record $Record -Name $name -Status 'policy_blocked' -Outcome ('{0}_workflow_missing' -f $name)
    }
  }
  if ([int]$Record.sourceType -eq 3 -or [bool]$Record.capabilities.download) {
    Set-HypiumWorkflow -State $State -Record $Record -Name 'file' -Status 'unsupported_api' -Outcome 'file_consumer_not_implemented'
  } else {
    Set-HypiumWorkflow -State $State -Record $Record -Name 'file' -Status 'policy_blocked' -Outcome 'file_workflow_not_declared'
  }
  if ([bool]$Record.capabilities.review) {
    Set-HypiumWorkflow -State $State -Record $Record -Name 'review' -Status 'unsupported_api' -Outcome 'review_consumer_not_implemented'
  } else {
    Set-HypiumWorkflow -State $State -Record $Record -Name 'review' -Status 'policy_blocked' -Outcome 'review_workflow_not_declared'
  }
}

function Resolve-HypiumFullWorkflowExploreAttempt {
  param([object]$State, [object]$Record, [object]$Attempt)
  $trace = $Attempt.trace
  if ($Attempt.runnerStatus -eq 'passed' -and $Attempt.driverClosed -and $null -ne $trace -and
      [string]$trace.workflow -eq 'explore' -and [int]$trace.statusCode -ge 200 -and
      [int]$trace.statusCode -lt 400 -and [string]$trace.errorCode -eq 'none' -and
      [string]$trace.outputKind -eq 'explore_nonempty') {
    Set-HypiumWorkflow -State $State -Record $Record -Name 'explore' -Status 'passed' -Outcome 'explore_execution_verified_reference_pending' -Digest ([string]$trace.outputSummarySha256)
    return [pscustomobject][ordered]@{ status = 'passed'; outcome = 'explore_execution_verified_reference_pending'; qualification = 'execution_verified_no_reference'; category = 'explore_reference_pending' }
  }
  if ($Attempt.outcome -eq 'empty' -and $null -ne $trace -and [int]$trace.statusCode -ge 200 -and
      [int]$trace.statusCode -lt 400 -and [string]$trace.errorCode -eq 'none') {
    Set-HypiumWorkflow -State $State -Record $Record -Name 'explore' -Status 'blocked' -Outcome 'explore_empty_without_reference' -Digest ([string]$trace.outputSummarySha256)
    return [pscustomobject][ordered]@{ status = 'blocked'; outcome = 'explore_empty_without_reference'; qualification = 'execution_empty_no_reference'; category = 'explore_empty_without_reference' }
  }
  if ($null -ne $trace -and [string]$trace.errorCode -eq 'needs_interaction') {
    Set-HypiumWorkflow -State $State -Record $Record -Name 'explore' -Status 'needs_interaction' -Outcome 'protected_response_requires_interaction' -Digest ([string]$trace.outputSummarySha256)
    return [pscustomobject][ordered]@{ status = 'needs_interaction'; outcome = 'protected_response_requires_interaction'; qualification = 'needs_interaction'; category = 'protected_response_requires_interaction' }
  }
  if (Test-HypiumExploreExternalBoundary -Attempt $Attempt) {
    Set-HypiumWorkflow -State $State -Record $Record -Name 'explore' -Status 'blocked' -Outcome 'external_network_unconfirmed' -Digest $(if ($null -ne $trace) { [string]$trace.outputSummarySha256 } else { '' })
    return [pscustomobject][ordered]@{ status = 'blocked'; outcome = 'external_network_unconfirmed'; qualification = 'endpoint_unconfirmed'; category = 'external_network_unconfirmed' }
  }
  Set-HypiumWorkflow -State $State -Record $Record -Name 'explore' -Status 'failed' -Outcome 'explore_harness_or_engine_failure' -Digest $(if ($null -ne $trace) { [string]$trace.outputSummarySha256 } else { '' })
  return [pscustomobject][ordered]@{ status = 'failed'; outcome = 'explore_harness_or_engine_failure'; qualification = 'harness_or_engine_failure'; category = 'explore_harness_or_engine_failure' }
}

function Resolve-HypiumFullWorkflowExploreReadAttempt {
  param([object]$State, [object]$Record, [object]$Attempt)
  $workflowMap = @{
    bookInfo = 'book_info'
    toc = 'toc'
    content = 'content'
  }
  $success = $true
  $needsInteraction = $false
  $externalBoundary = $false
  $harnessFailure = $false
  foreach ($workflowName in @('bookInfo', 'toc', 'content')) {
    $trace = Get-HypiumDetailTrace -Attempt $Attempt -Workflow $workflowMap[$workflowName]
    if ($null -eq $trace) {
      Set-HypiumWorkflow -State $State -Record $Record -Name $workflowName -Status 'blocked' -Outcome 'explore_read_path_trace_missing'
      $success = $false
      $harnessFailure = $true
      continue
    }
    $statusCode = [int](Get-HypiumTextProperty -Object $trace -Name 'statusCode')
    $errorCode = Get-HypiumTextProperty -Object $trace -Name 'errorCode'
    $outputKind = Get-HypiumTextProperty -Object $trace -Name 'outputKind'
    $expectedKind = switch ($workflowName) {
      'bookInfo' { 'book_info_metadata_resolved' }
      'toc' { 'toc_nonempty' }
      'content' { 'content_readable' }
      default { '' }
    }
    $digest = Get-HypiumTextProperty -Object $trace -Name 'outputSummarySha256'
    $imageWorkflowOutcome = Get-HypiumTextProperty -Object $trace -Name 'imageWorkflowOutcome'
    if ($errorCode -eq 'needs_interaction') {
      Set-HypiumWorkflow -State $State -Record $Record -Name $workflowName -Status 'needs_interaction' -Outcome 'protected_response_requires_interaction' -Digest $digest
      $needsInteraction = $true
      $success = $false
      continue
    }
    if ($errorCode -in @('http', 'network') -or $statusCode -ge 400) {
      Set-HypiumWorkflow -State $State -Record $Record -Name $workflowName -Status 'blocked' -Outcome 'external_network_unconfirmed' -Digest $digest
      $externalBoundary = $true
      $success = $false
      continue
    }
    if ($workflowName -eq 'content' -and ($outputKind -eq 'content_invalid_image' -or $imageWorkflowOutcome -eq 'image_workflow_invalid_content')) {
      Set-HypiumWorkflow -State $State -Record $Record -Name $workflowName -Status 'failed' -Outcome 'image_workflow_invalid_content' -Digest $digest
      $harnessFailure = $true
      $success = $false
      continue
    }
    if ($statusCode -ge 200 -and $statusCode -lt 400 -and $errorCode -eq 'none' -and $outputKind -eq $expectedKind) {
      Set-HypiumWorkflow -State $State -Record $Record -Name $workflowName -Status 'passed' -Outcome ('explore_read_path_{0}_execution_verified_reference_pending' -f $workflowName) -Digest $digest
      continue
    }
    Set-HypiumWorkflow -State $State -Record $Record -Name $workflowName -Status 'failed' -Outcome ('explore_read_path_{0}_trace_unusable' -f $workflowName) -Digest $digest
    $harnessFailure = $true
    $success = $false
  }
  if ($success) {
    Set-HypiumSource -State $State -Record $Record -Status 'blocked' -Outcome 'explore_read_path_reference_pending' -Profile 'v2_hypium_full_workflow_explore_read_path'
    Set-HypiumSemanticQualification -Record $Record -Qualification 'execution_verified_no_reference'
    return [pscustomobject][ordered]@{ status = 'blocked'; outcome = 'explore_read_path_reference_pending'; qualification = 'execution_verified_no_reference'; category = 'explore_read_path_reference_pending' }
  }
  if ($needsInteraction) {
    Set-HypiumSource -State $State -Record $Record -Status 'needs_interaction' -Outcome 'protected_response_requires_interaction' -Profile 'v2_hypium_full_workflow_explore_read_path'
    Set-HypiumSemanticQualification -Record $Record -Qualification 'needs_interaction'
    return [pscustomobject][ordered]@{ status = 'needs_interaction'; outcome = 'protected_response_requires_interaction'; qualification = 'needs_interaction'; category = 'protected_response_requires_interaction' }
  }
  if ($externalBoundary) {
    Set-HypiumSource -State $State -Record $Record -Status 'blocked' -Outcome 'external_network_unconfirmed' -Profile 'v2_hypium_full_workflow_explore_read_path'
    Set-HypiumSemanticQualification -Record $Record -Qualification 'endpoint_unconfirmed'
    return [pscustomobject][ordered]@{ status = 'blocked'; outcome = 'external_network_unconfirmed'; qualification = 'endpoint_unconfirmed'; category = 'external_network_unconfirmed' }
  }
  Set-HypiumSource -State $State -Record $Record -Status 'failed' -Outcome 'explore_read_path_harness_or_engine_failure' -Profile 'v2_hypium_full_workflow_explore_read_path'
  Set-HypiumSemanticQualification -Record $Record -Qualification 'harness_or_engine_failure'
  return [pscustomobject][ordered]@{ status = 'failed'; outcome = 'explore_read_path_harness_or_engine_failure'; qualification = 'harness_or_engine_failure'; category = 'explore_read_path_harness_or_engine_failure' }
}

function Get-HypiumWorkflowResult {
  param([object]$Attempt, [string]$Name)
  $resultsProperty = $Attempt.PSObject.Properties['workflowResults']
  if ($null -eq $resultsProperty -or $null -eq $resultsProperty.Value) { return '' }
  return Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $resultsProperty.Value -Name $Name) -Fallback ''
}

function Get-HypiumWorkflowResultFromAttempts {
  param([object]$Attempt, [object]$AdditionalAttempt, [string]$Name)
  $value = if ($null -ne $AdditionalAttempt) { Get-HypiumWorkflowResult -Attempt $AdditionalAttempt -Name $Name } else { '' }
  if (-not [string]::IsNullOrWhiteSpace($value)) { return $value }
  return Get-HypiumWorkflowResult -Attempt $Attempt -Name $Name
}

function Resolve-HypiumCapturedReadWorkflows {
  param([object]$State, [object]$Record, [object]$Attempt)
  $assessment = Get-LegadoCapturedReadWorkflowAssessments -Attempt $Attempt
  foreach ($name in @('bookInfo', 'toc', 'content')) {
    $item = $assessment.PSObject.Properties[$name].Value
    Set-HypiumWorkflow -State $State -Record $Record -Name $name -Status ([string]$item.status) -Outcome ([string]$item.outcome) -Digest ([string]$item.evidenceDigest)
  }
  return $assessment
}

function Get-HypiumDetailTrace {
  param([object]$Attempt, [string]$Workflow)
  $tracesProperty = $Attempt.PSObject.Properties['detailTraceRecords']
  if ($null -eq $tracesProperty -or $null -eq $tracesProperty.Value) { return $null }
  $matches = @($tracesProperty.Value | Where-Object { [string]$_.workflow -eq $Workflow })
  if ($matches.Count -eq 0) { return $null }
  return $matches[$matches.Count - 1]
}

function Get-HypiumWorkflowEvidence {
  param([object]$Record, [object]$Attempt, [string]$StateName, [string]$TraceName)
  $workflowProperty = $Record.workflows.PSObject.Properties[$StateName]
  if ($null -eq $workflowProperty -or $null -eq $workflowProperty.Value) {
    return [pscustomobject][ordered]@{
      status = 'unclassified'
      outcome = 'workflow_state_missing'
      attempts = 0
      evidenceDigest = ''
      tracePresent = $false
      traceDigest = ''
    }
  }
  $workflow = $workflowProperty.Value
  $trace = $null
  if ($null -ne $Attempt.trace -and [string]$Attempt.trace.workflow -eq $TraceName) {
    $trace = $Attempt.trace
  } else {
    $trace = Get-HypiumDetailTrace -Attempt $Attempt -Workflow $TraceName
  }
  $tracePresent = $null -ne $trace
  $traceDigest = if ($tracePresent) {
    Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'outputSummarySha256') -Fallback ''
  } else { '' }
  $storedDigest = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $workflow -Name 'lastEvidenceDigest') -Fallback ''
  # A few terminal branches update status after the transport trace is
  # persisted and intentionally omit the optional digest argument. The trace
  # is the authoritative witness; project its digest instead of emitting a
  # false trace-without-digest gap.
  $evidenceDigest = if ($tracePresent -and [string]::IsNullOrWhiteSpace($storedDigest)) {
    $traceDigest
  } else { $storedDigest }
  return [pscustomobject][ordered]@{
    status = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $workflow -Name 'status') -Fallback 'unclassified'
    outcome = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $workflow -Name 'lastOutcome') -Fallback 'unclassified'
    attempts = [int](Get-HypiumTextProperty -Object $workflow -Name 'attempts')
    evidenceDigest = $evidenceDigest
    tracePresent = $tracePresent
    traceDigest = $traceDigest
  }
}

function Get-HypiumWorkflowStatusMatrix {
  param([object]$Record, [object]$Attempt, [object]$AdditionalExploreAttempt = $null)
  $exploreAttempt = $Attempt
  if ($null -ne $AdditionalExploreAttempt) { $exploreAttempt = $AdditionalExploreAttempt }
  return [pscustomobject][ordered]@{
    search = Get-HypiumWorkflowEvidence -Record $Record -Attempt $Attempt -StateName 'search' -TraceName 'search'
    explore = Get-HypiumWorkflowEvidence -Record $Record -Attempt $exploreAttempt -StateName 'explore' -TraceName 'explore'
    bookInfo = Get-HypiumWorkflowEvidence -Record $Record -Attempt $Attempt -StateName 'bookInfo' -TraceName 'book_info'
    toc = Get-HypiumWorkflowEvidence -Record $Record -Attempt $Attempt -StateName 'toc' -TraceName 'toc'
    content = Get-HypiumWorkflowEvidence -Record $Record -Attempt $Attempt -StateName 'content' -TraceName 'content'
    file = Get-HypiumWorkflowEvidence -Record $Record -Attempt $Attempt -StateName 'file' -TraceName 'file'
    review = Get-HypiumWorkflowEvidence -Record $Record -Attempt $Attempt -StateName 'review' -TraceName 'review'
  }
}

function Get-HypiumWorkflowEvidenceProjection {
  param([object]$Record, [object]$Attempt, [object]$WorkflowStatusMatrix, [object]$WorkflowResults)
  $projection = [ordered]@{}
  foreach ($name in @('search', 'explore', 'bookInfo', 'toc', 'content', 'file', 'review')) {
    $matrixProperty = $WorkflowStatusMatrix.PSObject.Properties[$name]
    $resultProperty = $WorkflowResults.PSObject.Properties[$name]
    $matrixItem = if ($null -ne $matrixProperty) { $matrixProperty.Value } else { $null }
    $resultValue = if ($null -ne $resultProperty) { [string]$resultProperty.Value } else { '' }
    if ($null -eq $matrixItem) {
      $projection[$name] = [pscustomobject][ordered]@{
        status = 'blocked'
        outcome = 'workflow_state_missing'
        attempts = 0
        evidenceDigest = ''
        tracePresent = $false
        traceDigest = ''
        result = 'blocked:workflow_state_missing'
      }
      continue
    }
    $status = Get-HypiumSafeToken -Value ([string]$matrixItem.status) -Fallback 'blocked'
    $outcome = Get-HypiumSafeToken -Value ([string]$matrixItem.outcome) -Fallback 'workflow_outcome_missing'
    $result = if ([string]::IsNullOrWhiteSpace($resultValue)) { '{0}:{1}' -f $status, $outcome } else { Get-HypiumSafeToken -Value $resultValue -Fallback ('{0}:{1}' -f $status, $outcome) }
    $projection[$name] = [pscustomobject][ordered]@{
      status = $status
      outcome = $outcome
      attempts = [int]$matrixItem.attempts
      evidenceDigest = [string]$matrixItem.evidenceDigest
      tracePresent = [bool]$matrixItem.tracePresent
      traceDigest = [string]$matrixItem.traceDigest
      result = $result
    }
  }
  return [pscustomobject]$projection
}

function Get-HypiumSafeDetailTraceRecords {
  param([object]$Attempt)
  $tracesProperty = $Attempt.PSObject.Properties['detailTraceRecords']
  if ($null -eq $tracesProperty -or $null -eq $tracesProperty.Value) { return @() }
  $safeRecords = New-Object 'System.Collections.Generic.List[object]'
  foreach ($trace in @($tracesProperty.Value)) {
    $traceResponseClass = Get-HypiumTextProperty -Object $trace -Name 'responseClass'
    if ([string]::IsNullOrWhiteSpace([string]$traceResponseClass)) {
      $traceResponseClass = Get-HypiumTextProperty -Object $trace -Name 'contentResponseClass'
    }
    [void]$safeRecords.Add([pscustomobject][ordered]@{
      workflow = Get-HypiumSafeToken -Value ([string]$trace.workflow) -Fallback 'unknown_workflow'
      transport = Get-HypiumSafeToken -Value ([string]$trace.transport) -Fallback 'unknown_transport'
      statusCode = [int]$trace.statusCode
      errorCode = Get-HypiumSafeToken -Value ([string]$trace.errorCode) -Fallback 'unclassified_error'
      outputKind = Get-HypiumSafeToken -Value ([string]$trace.outputKind) -Fallback 'unrecognized'
      outputSummarySha256 = [string]$trace.outputSummarySha256
      outputSummaryLength = [int](Get-HypiumTextProperty -Object $trace -Name 'outputSummaryLength')
      outputSummaryShape = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'outputSummaryShape') -Fallback ''
      tocMatchedElementCount = [int](Get-HypiumTextProperty -Object $trace -Name 'tocMatchedElementCount')
      tocMissingChapterUrlCount = [int](Get-HypiumTextProperty -Object $trace -Name 'tocMissingChapterUrlCount')
      tocPageCount = [int](Get-HypiumTextProperty -Object $trace -Name 'tocPageCount')
      bookInfoTocUrlFingerprint = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'bookInfoTocUrlFingerprint') -Fallback ''
      bookInfoTocRuleFingerprint = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'bookInfoTocRuleFingerprint') -Fallback ''
      bookInfoTocVariablesBeforeFingerprint = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'bookInfoTocVariablesBeforeFingerprint') -Fallback ''
      bookInfoTocVariablesAfterFingerprint = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'bookInfoTocVariablesAfterFingerprint') -Fallback ''
      bookInfoHeadersVariableFingerprint = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'bookInfoHeadersVariableFingerprint') -Fallback ''
      nativeJsShimStatus = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'nativeJsShimStatus') -Fallback ''
      nativeJsShimDetail = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'nativeJsShimDetail') -Fallback ''
      bookInfoRuleCount = [int](Get-HypiumTextProperty -Object $trace -Name 'bookInfoRuleCount')
      bookInfoResolvedCount = [int](Get-HypiumTextProperty -Object $trace -Name 'bookInfoResolvedCount')
      responseBodyLength = [int](Get-HypiumTextProperty -Object $trace -Name 'responseBodyLength')
      responseBodyFingerprint = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'responseBodyFingerprint') -Fallback ''
      responseClass = Get-HypiumSafeToken -Value $traceResponseClass -Fallback ''
      requestTargetSha256 = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'requestTargetSha256') -Fallback ''
      requestUserAgentSha256 = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'requestUserAgentSha256') -Fallback ''
      requestMethod = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'requestMethod') -Fallback ''
      requestHeaderCount = [int](Get-HypiumTextProperty -Object $trace -Name 'requestHeaderCount')
      requestHeaderNames = @(Get-HypiumHeaderNames -Object $trace -Name 'requestHeaderNames')
      requestHeaderFingerprint = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'requestHeaderFingerprint') -Fallback ''
      searchBookTargetSequenceSha256 = @(Get-HypiumTargetDigestArrayProperty -Object $trace -Name 'searchBookTargetSequenceSha256')
      searchBookTargetSequenceDistinctCount = [int](Get-HypiumTextProperty -Object $trace -Name 'searchBookTargetSequenceDistinctCount')
      searchBookTargetSequenceEmptyCount = [int](Get-HypiumTextProperty -Object $trace -Name 'searchBookTargetSequenceEmptyCount')
      responseContentType = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'responseContentType') -Fallback ''
      redirectCount = [int](Get-HypiumTextProperty -Object $trace -Name 'redirectCount')
      contentCharacterCount = [int](Get-HypiumTextProperty -Object $trace -Name 'contentCharacterCount')
      contentDiagnosticsSource = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'contentDiagnosticsSource') -Fallback ''
      contentStageDiagnosticsSource = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'contentStageDiagnosticsSource') -Fallback ''
      contentExtractedCharacterCount = [int](Get-HypiumTextProperty -Object $trace -Name 'contentExtractedCharacterCount')
      contentExtractedLineFeedCount = [int](Get-HypiumTextProperty -Object $trace -Name 'contentExtractedLineFeedCount')
      contentNormalizedCharacterCount = [int](Get-HypiumTextProperty -Object $trace -Name 'contentNormalizedCharacterCount')
      contentNormalizedLineFeedCount = [int](Get-HypiumTextProperty -Object $trace -Name 'contentNormalizedLineFeedCount')
      contentNormalizationDelta = [int](Get-HypiumTextProperty -Object $trace -Name 'contentNormalizationDelta')
      contentJoinedCharacterCount = [int](Get-HypiumTextProperty -Object $trace -Name 'contentJoinedCharacterCount')
      contentJoinedLineFeedCount = [int](Get-HypiumTextProperty -Object $trace -Name 'contentJoinedLineFeedCount')
      contentFinalLineFeedCount = [int](Get-HypiumTextProperty -Object $trace -Name 'contentFinalLineFeedCount')
      contentFirstExtractLeadingWhitespaceCount = [int](Get-HypiumTextProperty -Object $trace -Name 'contentFirstExtractLeadingWhitespaceCount')
      contentFirstExtractStartsWithLineFeed = [int](Get-HypiumTextProperty -Object $trace -Name 'contentFirstExtractStartsWithLineFeed')
      contentFirstExtractStartsWithBlockTag = [int](Get-HypiumTextProperty -Object $trace -Name 'contentFirstExtractStartsWithBlockTag')
      contentFirstNormalizeStartsWithReaderIndent = [int](Get-HypiumTextProperty -Object $trace -Name 'contentFirstNormalizeStartsWithReaderIndent')
      contentBridgeStatus = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'contentBridgeStatus') -Fallback ''
      contentBridgeCharacterCount = [int](Get-HypiumTextProperty -Object $trace -Name 'contentBridgeCharacterCount')
      contentBridgeFingerprint = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'contentBridgeFingerprint') -Fallback ''
      contentBridgeReaderCharacterCount = [int](Get-HypiumTextProperty -Object $trace -Name 'contentBridgeReaderCharacterCount')
      contentBridgeReaderLineFeedCount = [int](Get-HypiumTextProperty -Object $trace -Name 'contentBridgeReaderLineFeedCount')
      contentBridgeReaderFingerprint = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'contentBridgeReaderFingerprint') -Fallback ''
      contentResponseTargetSha256 = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'requestTargetSha256') -Fallback ''
      contentResponseUserAgentSha256 = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'requestUserAgentSha256') -Fallback ''
      contentResponseContentType = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'responseContentType') -Fallback ''
      contentResponseRedirectCount = [int](Get-HypiumTextProperty -Object $trace -Name 'redirectCount')
      contentResponseBodyLength = [int](Get-HypiumTextProperty -Object $trace -Name 'responseBodyLength')
      contentResponseBodyFingerprint = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'responseBodyFingerprint') -Fallback ''
      contentResponseClass = Get-HypiumSafeToken -Value $traceResponseClass -Fallback ''
      imageWorkflowOutcome = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'imageWorkflowOutcome') -Fallback ''
      contentResponseRequestMethod = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'requestMethod') -Fallback ''
      contentResponseRequestHeaderCount = [int](Get-HypiumTextProperty -Object $trace -Name 'requestHeaderCount')
      contentResponseRequestHeaderNames = @(Get-HypiumHeaderNames -Object $trace -Name 'requestHeaderNames')
      contentResponseRequestHeaderFingerprint = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'requestHeaderFingerprint') -Fallback ''
      contentFingerprint = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $trace -Name 'contentFingerprint') -Fallback ''
      # Milliseconds since epoch is evidence only. It proves that a readable
      # Content trace was persisted after the reader action without exposing a
      # URL, request data, or chapter text.
      traceOccurredAt = [Int64](Get-HypiumTextProperty -Object $trace -Name 'traceOccurredAt')
      downloadCount = [int](Get-HypiumTextProperty -Object $trace -Name 'downloadCount')
    })
  }
  return $safeRecords.ToArray()
}

function Resolve-HypiumTocPartialOutcome {
  param([object]$Record, [object]$Attempt, [string]$TocResult)
  if ($TocResult -ne 'empty_or_unconfirmed') {
    return [pscustomobject]@{ status = 'failed'; outcome = 'safe_read_path_incomplete'; category = 'safe_read_path_partial' }
  }
  $trace = Get-HypiumDetailTrace -Attempt $Attempt -Workflow 'toc'
  if ($null -eq $trace) {
    return [pscustomobject]@{ status = 'failed'; outcome = 'toc_trace_missing'; category = 'toc_trace_missing' }
  }
  $errorCode = [string]$trace.errorCode
  $statusCode = [int]$trace.statusCode
  $outputKind = [string]$trace.outputKind
  if ($errorCode -eq 'rule') {
    return [pscustomobject]@{ status = 'failed'; outcome = 'toc_rule_failure'; category = 'toc_rule_failure' }
  }
  if ($errorCode -eq 'network' -or $errorCode -eq 'http' -or $statusCode -ge 400) {
    return [pscustomobject]@{ status = 'blocked'; outcome = 'toc_endpoint_unconfirmed'; category = 'toc_endpoint_unconfirmed' }
  }
  if ($errorCode -eq 'none' -and $outputKind -eq 'toc_empty') {
    $reference = Get-HypiumReferenceSearchEvidence -Record $Record
    if ($null -ne $reference -and [bool]$reference.traceReceived -and [string]$reference.stage -eq 'toc' -and
      [string]$reference.outcome -eq 'reference_exception' -and [int]$reference.tocCount -eq 0) {
      # Both paths reached a zero-entry TOC, but an original exception is not
      # equivalent to a successful empty V2 result. Keep it reproducible and
      # blocked until the underlying rule/endpoint difference is explained.
      return [pscustomobject]@{ status = 'blocked'; outcome = 'toc_reference_exception_unresolved'; category = 'toc_reference_exception_unresolved' }
    }
    return [pscustomobject]@{ status = 'failed'; outcome = 'toc_empty_unexpected'; category = 'toc_empty_unexpected' }
  }
  return [pscustomobject]@{ status = 'failed'; outcome = 'toc_execution_unconfirmed'; category = 'toc_execution_unconfirmed' }
}

function Resolve-HypiumBookInfoTerminalOutcome {
  param([object]$Record, [object]$Attempt, [string]$BookInfoResult)
  if ($BookInfoResult -notin @('terminal_trace_observed', 'metadata_empty_http_error')) {
    return [pscustomobject]@{ status = 'failed'; outcome = 'book_info_execution_unconfirmed'; category = 'book_info_execution_unconfirmed' }
  }
  $trace = Get-HypiumDetailTrace -Attempt $Attempt -Workflow 'book_info'
  if ($null -eq $trace) {
    return [pscustomobject]@{ status = 'failed'; outcome = 'book_info_trace_missing'; category = 'book_info_trace_missing' }
  }
  $errorCode = [string]$trace.errorCode
  $statusCode = [int]$trace.statusCode
  # A login/challenge page can be returned with HTTP 200. The structured
  # V2 trace's errorCode is the authoritative interaction boundary; checking
  # it before the generic HTTP/network branch prevents an interactive source
  # from being misclassified as an engine failure merely because its status
  # code is below 400.
  if ($errorCode -eq 'needs_interaction') {
    return [pscustomobject]@{ status = 'needs_interaction'; outcome = 'protected_response_requires_interaction'; category = 'protected_response_requires_interaction' }
  }
  if ($errorCode -eq 'network' -or $errorCode -eq 'http' -or $statusCode -ge 400) {
    $reference = Get-HypiumReferenceSearchEvidence -Record $Record
    if ($null -ne $reference -and [bool]$reference.traceReceived) {
      $diagnosticProperty = $reference.PSObject.Properties['diagnostic']
      if ($null -eq $diagnosticProperty -or $null -eq $diagnosticProperty.Value) {
        return [pscustomobject]@{ status = 'blocked'; outcome = 'book_info_reference_insufficient'; category = 'book_info_reference_insufficient' }
      }
      $referenceDiagnostic = $diagnosticProperty.Value
      $probeOutcome = Get-HypiumTextProperty -Object $referenceDiagnostic -Name 'bookInfoProbeOutcome'
      $probeStatusCode = [int](Get-HypiumTextProperty -Object $referenceDiagnostic -Name 'bookInfoProbeStatusCode')
      $probeResponseClass = Get-HypiumTextProperty -Object $referenceDiagnostic -Name 'bookInfoProbeResponseClass'
      if ($probeOutcome -ne 'complete') {
        return [pscustomobject]@{ status = 'blocked'; outcome = 'book_info_reference_insufficient'; category = 'book_info_reference_insufficient' }
      }
      if ($probeStatusCode -ge 400 -or $probeResponseClass -match '(^|_)access_denied($|_)') {
        return [pscustomobject]@{ status = 'blocked'; outcome = 'book_info_reference_endpoint_unconfirmed'; category = 'book_info_reference_endpoint_unconfirmed' }
      }
    }
    return [pscustomobject]@{ status = 'blocked'; outcome = 'book_info_endpoint_unconfirmed'; category = 'book_info_endpoint_unconfirmed' }
  }
  return [pscustomobject]@{ status = 'failed'; outcome = 'book_info_execution_unconfirmed'; category = 'book_info_execution_unconfirmed' }
}

function Resolve-HypiumBookInfoPartialOutcome {
  param([object]$Record, [object]$Attempt, [string]$BookInfoResult)
  $trace = Get-HypiumDetailTrace -Attempt $Attempt -Workflow 'book_info'
  if ($BookInfoResult -notin @('passed', 'metadata_empty_http_error') -or $null -eq $trace) {
    return [pscustomobject]@{ status = 'failed'; outcome = 'book_info_trace_missing'; category = 'book_info_trace_missing' }
  }
  $errorCode = [string]$trace.errorCode
  $statusCode = [int]$trace.statusCode
  $resolvedCount = [int](Get-HypiumTextProperty -Object $trace -Name 'bookInfoResolvedCount')
  $reference = Get-HypiumReferenceSearchEvidence -Record $Record
  if ($null -ne $reference -and [bool]$reference.traceReceived -and [bool]$reference.bookInfoReady -and
    ($errorCode -eq 'network' -or $errorCode -eq 'http' -or $statusCode -ge 400) -and $resolvedCount -eq 0) {
    # `bookInfoReady` from the Android reference only means that the returned
    # Book keeps a non-empty bookUrl. It does not prove that the BookInfo HTTP
    # request or its selector produced metadata. A reference mismatch is valid
    # only when the original's redacted direct probe proves a comparable,
    # non-error response. Otherwise identical access-denied/network evidence
    # must stay an endpoint/reference block, not an engine regression.
    $diagnosticProperty = $reference.PSObject.Properties['diagnostic']
    if ($null -eq $diagnosticProperty -or $null -eq $diagnosticProperty.Value) {
      return [pscustomobject]@{ status = 'blocked'; outcome = 'book_info_reference_insufficient'; category = 'book_info_reference_insufficient' }
    }
    $referenceDiagnostic = $diagnosticProperty.Value
    $probeOutcome = Get-HypiumTextProperty -Object $referenceDiagnostic -Name 'bookInfoProbeOutcome'
    $probeStatusCode = [int](Get-HypiumTextProperty -Object $referenceDiagnostic -Name 'bookInfoProbeStatusCode')
    $probeResponseClass = Get-HypiumTextProperty -Object $referenceDiagnostic -Name 'bookInfoProbeResponseClass'
    if ($probeOutcome -ne 'complete') {
      return [pscustomobject]@{ status = 'blocked'; outcome = 'book_info_reference_insufficient'; category = 'book_info_reference_insufficient' }
    }
    if ($probeStatusCode -ge 400 -or $probeResponseClass -match '(^|_)access_denied($|_)') {
      return [pscustomobject]@{ status = 'blocked'; outcome = 'book_info_reference_endpoint_unconfirmed'; category = 'book_info_reference_endpoint_unconfirmed' }
    }
    return [pscustomobject]@{ status = 'blocked'; outcome = 'book_info_reference_response_mismatch'; category = 'book_info_reference_response_mismatch' }
  }
  if ($errorCode -eq 'network' -or $errorCode -eq 'http' -or $statusCode -ge 400) {
    return [pscustomobject]@{ status = 'blocked'; outcome = 'book_info_endpoint_unconfirmed'; category = 'book_info_endpoint_unconfirmed' }
  }
  if ($resolvedCount -le 0) {
    return [pscustomobject]@{ status = 'failed'; outcome = 'book_info_metadata_empty'; category = 'book_info_metadata_empty' }
  }
  return [pscustomobject]@{ status = 'passed'; outcome = 'safe_read_path_verified'; category = 'book_info_verified' }
}

function Test-HypiumSafeReadWorkflowResults {
  param([object]$Attempt)
  foreach ($name in @('book_info', 'toc', 'content')) {
    if ((Get-HypiumWorkflowResult -Attempt $Attempt -Name $name) -ne 'passed') { return $false }
  }
  $contentTrace = Get-HypiumDetailTrace -Attempt $Attempt -Workflow 'content'
  if ($null -eq $contentTrace -or [string]$contentTrace.outputKind -ne 'content_readable' -or
    [int](Get-HypiumTextProperty -Object $contentTrace -Name 'contentCharacterCount') -le 0 -or
    (Get-HypiumTextProperty -Object $contentTrace -Name 'contentFingerprint').Length -le 0) {
    return $false
  }
  $readerContent = $Attempt.PSObject.Properties['readerContent']
  if ($null -eq $readerContent -or $null -eq $readerContent.Value -or
    [string]$readerContent.Value.state -ne 'ready' -or [string]$readerContent.Value.engine -ne 'v2' -or
    [int]$readerContent.Value.contentCharacterCount -le 0 -or [string]$readerContent.Value.contentFingerprint -notmatch '^[0-9a-f]{16}$' -or
    -not [bool]$readerContent.Value.tracePersisted) {
    return $false
  }
  $readerTraceAt = [Int64](Get-HypiumTextProperty -Object $Attempt -Name 'readerContentTraceAt')
  $previousTraceAt = [Int64](Get-HypiumTextProperty -Object $Attempt -Name 'previousContentTraceAt')
  $postReaderTraceAt = [Int64](Get-HypiumTextProperty -Object $Attempt -Name 'contentTraceAfterReaderAt')
  # The reader exposes the summary persistence update time while the detail
  # witness carries the execution occurrence time. Require a fresh trace plus
  # a bounded association window; comparing these distinct timestamps as if
  # they had the same semantic is a false harness failure.
  if ($readerTraceAt -le $previousTraceAt -or $postReaderTraceAt -le $previousTraceAt -or
    [Math]::Abs($postReaderTraceAt - $readerTraceAt) -gt 5000) {
    return $false
  }
  # A bridge is optional by grammar. When the app declares that it evaluated
  # one, its two evidence fields must be complete; otherwise the result is a
  # harness failure rather than a valid semantic observation.
  $bridgeStatus = Get-HypiumTextProperty -Object $contentTrace -Name 'contentBridgeStatus'
  if ($bridgeStatus -ne 'available') { return $true }
  return [int](Get-HypiumTextProperty -Object $contentTrace -Name 'contentBridgeCharacterCount') -gt 0 -and
    (Get-HypiumTextProperty -Object $contentTrace -Name 'contentBridgeFingerprint').Length -gt 0
}

function Add-HypiumGovernanceFinding {
  param(
    [object]$State,
    [object]$Record,
    [string]$Category,
    [string]$Status = 'failed',
    [string]$Severity = 'P1'
  )
  $governanceProperty = $State.PSObject.Properties['governance']
  if ($null -eq $governanceProperty -or $null -eq $governanceProperty.Value) { return }
  $governance = $governanceProperty.Value
  $findingId = 'ISSUE-COMPAT-HYPIUM-' + ([string]$Record.sourceId).Substring(0, 12)
  $findingAttempts = 0
  foreach ($workflowProperty in $Record.workflows.PSObject.Properties) {
    $workflowAttempts = [int](Get-HypiumTextProperty -Object $workflowProperty.Value -Name 'attempts')
    if ($workflowAttempts -gt $findingAttempts) {
      $findingAttempts = $workflowAttempts
    }
  }
  $sourceEvidencePath = Join-Path $EvidenceDirectory ('source-' + [string]$Record.sourceId + '.json')
  $sourceEvidenceRelativePath = ConvertTo-LegadoHypiumEvidenceRelativePath -ScriptRoot $PSScriptRoot -Path $sourceEvidencePath
  $finding = [pscustomobject][ordered]@{
    id = $findingId; taskId = 'COMPAT-006'; status = $Status; severity = $Severity; attempts = $findingAttempts
    summary = 'v2_hypium_' + (Get-HypiumSafeToken -Value $Category); evidencePaths = @($sourceEvidenceRelativePath)
    lastUpdatedAt = Get-HypiumNow
  }
  $existing = @($governance.PSObject.Properties['queuedFindings'].Value)
  $updated = New-Object 'System.Collections.Generic.List[object]'
  $replaced = $false
  foreach ($item in $existing) {
    if ((Get-HypiumTextProperty -Object $item -Name 'id') -eq $findingId) {
      # Older interrupted runs can leave duplicate IDs. Keep one current fact
      # so the Markdown renderer cannot select a stale sibling.
      if (-not $replaced) {
        [void]$updated.Add($finding)
        $replaced = $true
      }
    } else {
      [void]$updated.Add($item)
    }
  }
  if (-not $replaced) { [void]$updated.Add($finding) }
  Set-HypiumProperty -Object $governance -Name 'queuedFindings' -Value $updated.ToArray()
  $issuesProperty = $governance.PSObject.Properties['issues']
  if ($null -eq $issuesProperty -or $null -eq $issuesProperty.Value) { return }
  $issues = @($issuesProperty.Value)
  $refreshedIssues = New-Object 'System.Collections.Generic.List[object]'
  $issueReplaced = $false
  foreach ($item in $issues) {
    if ((Get-HypiumTextProperty -Object $item -Name 'id') -eq $findingId) {
      if (-not $issueReplaced) {
        [void]$refreshedIssues.Add($finding)
        $issueReplaced = $true
      }
    } else {
      [void]$refreshedIssues.Add($item)
    }
  }
  if (-not $issueReplaced) { [void]$refreshedIssues.Add($finding) }
  Set-HypiumProperty -Object $governance -Name 'issues' -Value $refreshedIssues.ToArray()
}

function Test-HypiumExpectedExternal {
  param([object]$Record, [object]$Attempt)
  if ($null -eq $Attempt.trace) { return $false }
  $endpointFailure = [int]$Attempt.trace.statusCode -ge 400 -or [string]$Attempt.trace.errorCode -match '^network(_(dns|timeout|connect|tls))?$'
  if (-not $endpointFailure) { return $false }
  $value = Get-HypiumReferenceSearchEvidence -Record $Record
  if ($null -eq $value) { return $false }
  if (-not [bool]$value.traceReceived) { return $false }
  if ([string]$value.outcome -eq 'empty') {
    return Test-HypiumSearchHttpResponseParity -Record $Record -Trace $Attempt.trace
  }
  # There is no same-response fingerprint when both implementations fail
  # before a response exists.  A fresh original-Legado SocketException on the
  # same raw source and input is nevertheless positive endpoint evidence, not
  # an engine semantic mismatch.  Keep this intentionally narrow: only a
  # status-0 V2 network failure can join this external category.
  $diagnosticProperty = $value.PSObject.Properties['diagnostic']
  if ($null -eq $diagnosticProperty -or $null -eq $diagnosticProperty.Value) { return $false }
  $workflowErrorClass = Get-HypiumTextProperty -Object $diagnosticProperty.Value -Name 'workflowErrorClass'
  return [string]$value.outcome -eq 'reference_exception' -and [int]$Attempt.trace.statusCode -eq 0 -and
    [string]$Attempt.trace.errorCode -eq 'network' -and
    $workflowErrorClass -match '^(SocketException|UnknownHostException|SocketTimeoutException|ConnectException)$'
}

function Test-HypiumExploreExternalBoundary {
  param([object]$Attempt)
  if ($null -eq $Attempt -or $null -eq $Attempt.trace) { return $false }
  if ([string]$Attempt.trace.workflow -ne 'explore') { return $false }
  $statusCode = [int]$Attempt.trace.statusCode
  $errorCode = [string]$Attempt.trace.errorCode
  # HTTP 0 + network is the persisted pre-response transport witness. A
  # received HTTP error remains an endpoint boundary as well, but neither is
  # a proof that the rule engine produced a compatible result.
  return ($errorCode -eq 'network' -and $statusCode -eq 0) -or $statusCode -ge 400
}

function Get-HypiumReferenceSearchEvidence {
  param([object]$Record)
  $sourceId = [string]$Record.sourceId
  $validReferences = New-Object 'System.Collections.Generic.List[object]'
  $candidatePaths = New-Object 'System.Collections.Generic.List[string]'
  foreach ($candidatePath in @(
    (Join-Path $PSScriptRoot ('evidence\full-source-v2-device\reference-' + $sourceId + '.json')),
    (Join-Path $PSScriptRoot ('evidence\single-source-reference-' + $sourceId + '.json'))
  )) { [void]$candidatePaths.Add($candidatePath) }
  # A reference retry receives a timestamped sibling name so a failed Android
  # attempt is never overwritten. The filename is only discovery metadata:
  # raw-document identity is still verified below before it can affect a V2
  # semantic classification.
  $singleReferenceRoot = Join-Path $PSScriptRoot 'evidence'
  if (Test-Path -LiteralPath $singleReferenceRoot) {
    foreach ($referenceFile in @(Get-ChildItem -LiteralPath $singleReferenceRoot -File -Filter ('single-source-reference-' + $sourceId + '-*.json') -ErrorAction SilentlyContinue)) {
      [void]$candidatePaths.Add($referenceFile.FullName)
    }
  }
  # Recovery runs predate the source-scoped evidence path. Their filename is
  # not trusted: only add the local report candidate and re-check its raw
  # document digest below before it can qualify a V2 execution.
  $recoveryEvidenceRoot = Join-Path $PSScriptRoot 'evidence'
  if (Test-Path -LiteralPath $recoveryEvidenceRoot) {
    foreach ($recoveryDirectory in @(Get-ChildItem -LiteralPath $recoveryEvidenceRoot -Directory -Filter 'recovery-ordinal-*-reference-run-*' -ErrorAction SilentlyContinue)) {
      $recoveryReference = Join-Path $recoveryDirectory.FullName 'reference.json'
      if (Test-Path -LiteralPath $recoveryReference) { [void]$candidatePaths.Add($recoveryReference) }
    }
  }
  foreach ($candidatePath in $candidatePaths) {
    if (-not (Test-Path -LiteralPath $candidatePath)) { continue }
    try {
      $referenceEvidence = Read-LegadoJsonFile -Path $candidatePath
    } catch {
      continue
    }
    # A filename is only an index. Require the persisted raw-document identity
    # before allowing an original-Legado trace to qualify a V2 result.
    $referenceSourceHash = Get-HypiumTextProperty -Object $referenceEvidence -Name 'sourceHash'
    $expectedSourceHash = Get-HypiumTextProperty -Object $Record -Name 'rawDocumentSha256'
    if ($expectedSourceHash.Length -eq 0) { $expectedSourceHash = $sourceId }
    if ($referenceSourceHash.Length -eq 0 -or -not $referenceSourceHash.Equals($expectedSourceHash, [System.StringComparison]::OrdinalIgnoreCase)) { continue }
    $reference = $referenceEvidence.PSObject.Properties['reference']
    if ($null -eq $reference -or $null -eq $reference.Value) { continue }
    $generatedAt = [DateTimeOffset]::MinValue
    $generatedAtText = Get-HypiumTextProperty -Object $referenceEvidence -Name 'generatedAt'
    [void][DateTimeOffset]::TryParse($generatedAtText, [ref]$generatedAt)
    [void]$validReferences.Add([pscustomobject][ordered]@{
      reference = $reference.Value
      generatedAt = $generatedAt
    })
  }
  # Older runs can contain a partial trace from before the original-reference
  # harness was repaired. The latest same-raw-document trace is the canonical
  # comparison point; do not let a stale zero-result attempt mask it.
  if ($validReferences.Count -gt 0) {
    return ($validReferences.ToArray() | Sort-Object -Property generatedAt -Descending | Select-Object -First 1).reference
  }
  return $null
}

function Get-HypiumSearchSemanticDifference {
  param([object]$Record, [object]$Attempt)
  $reference = Get-HypiumReferenceSearchEvidence -Record $Record
  if ($null -eq $reference -or -not [bool]$reference.traceReceived -or $null -eq $Attempt.trace) { return $null }
  $referenceCount = [int](Get-HypiumTextProperty -Object $reference -Name 'searchCount')
  $referenceOutcome = Get-HypiumTextProperty -Object $reference -Name 'outcome'
  $referenceResponseClass = ''
  $diagnosticProperty = $reference.PSObject.Properties['diagnostic']
  if ($null -ne $diagnosticProperty -and $null -ne $diagnosticProperty.Value) {
    $referenceResponseClass = Get-HypiumTextProperty -Object $diagnosticProperty.Value -Name 'searchProbeResponseClass'
    if ($referenceResponseClass.Length -eq 0) {
      $referenceResponseClass = Get-HypiumTextProperty -Object $diagnosticProperty.Value -Name 'contentProbeResponseClass'
    }
  }
  # A reference exception contains no original response or rule result. Its
  # zero count is an absence of comparable evidence, not an empty search
  # result, so it must never manufacture a V2 semantic mismatch merely
  # because the V2 endpoint happened to succeed on a different device.
  if ($referenceOutcome -notin @('complete', 'empty')) { return $null }
  $actualCount = [int](Get-HypiumTextProperty -Object $Attempt.trace -Name 'matchedCount')
  $actualIsEmpty = $Attempt.outcome -eq 'empty' -or [string]$Attempt.trace.outputKind -eq 'search_empty'
  $actualIsNonEmpty = $Attempt.outcome -eq 'result' -and [string]$Attempt.trace.outputKind -eq 'search_nonempty'
  $protectedReference = $referenceResponseClass -in @('html_login', 'html_challenge', 'html_access_denied', 'html_rate_limited')
  $protectedV2 = [string]$Attempt.trace.errorCode -in @('needs_interaction', 'http') -and
    (Get-HypiumTextProperty -Object $Attempt.trace -Name 'outputSummarySha256').Length -gt 0
  if ($protectedReference -and $protectedV2) {
    return [pscustomobject][ordered]@{
      category = 'protected_response_requires_interaction'
      referenceResponseClass = $referenceResponseClass
      referenceSearchCount = $referenceCount
      v2MatchedCount = $actualCount
      v2OutputKind = [string]$Attempt.trace.outputKind
      v2ErrorCode = [string]$Attempt.trace.errorCode
      v2StatusCode = [int]$Attempt.trace.statusCode
    }
  }
  # No V2 response means there is no rule output to compare. Preserve the
  # original nonempty witness for network governance below, but never label a
  # status-0 transport failure as a semantic search mismatch.
  if ([int]$Attempt.trace.statusCode -eq 0 -and [string]$Attempt.trace.errorCode -eq 'network') {
    return $null
  }
  $category = ''
  if (($referenceCount -gt 0 -or $referenceOutcome -eq 'complete') -and
    ([int]$Attempt.trace.statusCode -ge 400 -or [string]$Attempt.trace.errorCode -eq 'http') -and
    -not (Test-HypiumSearchHttpResponseParity -Record $Record -Trace $Attempt.trace)) {
    # Accept a non-2xx document only when the original test-only witness proves
    # that both engines evaluated the same rule-readable response. Otherwise a
    # V2 HTTP result is still a semantic mismatch, even if it yielded rows.
    $category = 'reference_success_v2_http_error'
  } elseif ($referenceCount -gt 0 -and -not $actualIsEmpty -and -not $actualIsNonEmpty) {
    # An original same-input nonempty search means a V2 ArkWeb timeout or
    # search-failure trace is an engine semantic gap, not unconfirmed endpoint
    # evidence. Preserve the transport root cause in the attempt trace.
    $category = 'reference_nonempty_v2_search_uncompleted'
  } elseif ($referenceCount -gt 0 -and $actualIsEmpty) {
    $category = 'reference_nonempty_v2_empty'
  } elseif ($referenceCount -eq 0 -and $actualIsNonEmpty) {
    $category = 'reference_empty_v2_nonempty'
  } elseif ($referenceCount -gt 0 -and $actualIsNonEmpty -and (($actualCount -gt ($referenceCount * 2 + 10)) -or ($referenceCount -gt ($actualCount * 2 + 10)))) {
    $category = 'reference_count_materially_divergent'
  }
  if ($category.Length -eq 0) { return $null }
  return [pscustomobject][ordered]@{
    category = $category
    referenceSearchCount = $referenceCount
    v2MatchedCount = $actualCount
    v2OutputKind = [string]$Attempt.trace.outputKind
    v2ErrorCode = [string]$Attempt.trace.errorCode
    v2StatusCode = [int]$Attempt.trace.statusCode
  }
}

function Get-HypiumSearchTargetSequenceDifference {
  param([object]$Record, [object]$Attempt)
  if ($null -eq $Attempt.trace -or -not (Test-HypiumSearchHttpResponseParity -Record $Record -Trace $Attempt.trace)) {
    return $null
  }
  $reference = Get-HypiumReferenceSearchEvidence -Record $Record
  if ($null -eq $reference -or -not [bool]$reference.traceReceived -or [string]$reference.outcome -ne 'complete') {
    return $null
  }
  $diagnosticProperty = $reference.PSObject.Properties['diagnostic']
  if ($null -eq $diagnosticProperty -or $null -eq $diagnosticProperty.Value) { return $null }
  $referenceSequence = @(Get-HypiumTargetDigestArrayProperty -Object $diagnosticProperty.Value -Name 'searchBookTargetSequenceSha256')
  $v2Sequence = @(Get-HypiumTargetDigestArrayProperty -Object $Attempt.trace -Name 'searchBookTargetSequenceSha256')
  # A missing sequence is an observability gap, not a proof of rule drift.
  # The Harness version gate will surface it separately until both sides
  # expose the same bounded digest-only witness.
  if ($referenceSequence.Count -eq 0 -or $v2Sequence.Count -eq 0) { return $null }
  $same = $referenceSequence.Count -eq $v2Sequence.Count
  if ($same) {
    for ($index = 0; $index -lt $referenceSequence.Count; $index++) {
      if (-not $referenceSequence[$index].Equals($v2Sequence[$index], [System.StringComparison]::OrdinalIgnoreCase)) {
        $same = $false
        break
      }
    }
  }
  if ($same) { return $null }
  return [pscustomobject][ordered]@{
    category = 'search_result_target_sequence_mismatch'
    referenceSequenceCount = $referenceSequence.Count
    v2SequenceCount = $v2Sequence.Count
    referenceDistinctCount = [int](Get-HypiumTextProperty -Object $diagnosticProperty.Value -Name 'searchBookTargetSequenceDistinctCount')
    v2DistinctCount = [int](Get-HypiumTextProperty -Object $Attempt.trace -Name 'searchBookTargetSequenceDistinctCount')
    referenceEmptyCount = [int](Get-HypiumTextProperty -Object $diagnosticProperty.Value -Name 'searchBookTargetSequenceEmptyCount')
    v2EmptyCount = [int](Get-HypiumTextProperty -Object $Attempt.trace -Name 'searchBookTargetSequenceEmptyCount')
  }
}

function Test-HypiumSearchHttpResponseParity {
  param([object]$Record, [object]$Trace)
  if ($null -eq $Trace) { return $false }
  $reference = Get-HypiumReferenceSearchEvidence -Record $Record
  if ($null -eq $reference -or -not [bool]$reference.traceReceived) { return $false }
  $diagnosticProperty = $reference.PSObject.Properties['diagnostic']
  if ($null -eq $diagnosticProperty -or $null -eq $diagnosticProperty.Value) { return $false }
  $diagnostic = $diagnosticProperty.Value
  if ((Get-HypiumTextProperty -Object $diagnostic -Name 'searchProbeOutcome') -ne 'complete') { return $false }
  $referenceStatus = [int](Get-HypiumTextProperty -Object $diagnostic -Name 'searchProbeStatusCode')
  $referenceTarget = Get-HypiumTextProperty -Object $diagnostic -Name 'searchProbePlannedTargetSha256'
  $referenceUserAgent = Get-HypiumTextProperty -Object $diagnostic -Name 'searchProbeRequestUserAgentSha256'
  $referenceMethod = Get-HypiumTextProperty -Object $diagnostic -Name 'searchProbeRequestMethod'
  $referenceHeaderCount = [int](Get-HypiumTextProperty -Object $diagnostic -Name 'searchProbeRequestHeaderCount')
  $referenceHeaderFingerprint = Get-HypiumTextProperty -Object $diagnostic -Name 'searchProbeRequestHeaderFingerprint'
  $referenceBodyLength = [int](Get-HypiumTextProperty -Object $diagnostic -Name 'searchProbeBodyLength')
  $referenceBodyFingerprint = Get-HypiumTextProperty -Object $diagnostic -Name 'searchProbeBodyFingerprint'
  $referenceResponseClass = Get-HypiumTextProperty -Object $diagnostic -Name 'searchProbeResponseClass'
  return $referenceStatus -eq [int]$Trace.statusCode -and
    $referenceTarget -eq (Get-HypiumTextProperty -Object $Trace -Name 'requestTargetSha256') -and
    $referenceUserAgent -eq (Get-HypiumTextProperty -Object $Trace -Name 'requestUserAgentSha256') -and
    $referenceMethod -eq (Get-HypiumTextProperty -Object $Trace -Name 'requestMethod') -and
    $referenceHeaderCount -eq [int](Get-HypiumTextProperty -Object $Trace -Name 'requestHeaderCount') -and
    $referenceHeaderFingerprint -eq (Get-HypiumTextProperty -Object $Trace -Name 'requestHeaderFingerprint') -and
    $referenceBodyLength -eq [int](Get-HypiumTextProperty -Object $Trace -Name 'responseBodyLength') -and
    $referenceBodyFingerprint -eq (Get-HypiumTextProperty -Object $Trace -Name 'responseBodyFingerprint') -and
    $referenceResponseClass -eq (Get-HypiumTextProperty -Object $Trace -Name 'responseClass')
}

function Get-HypiumContentResponseParityQualification {
  param([object]$Record, [object]$Attempt, [object]$ContentTrace)
  $reference = Get-HypiumReferenceSearchEvidence -Record $Record
  if ($null -eq $reference -or -not [bool]$reference.traceReceived) {
    return [pscustomobject][ordered]@{ status = 'unavailable'; category = 'content_response_reference_missing' }
  }
  $diagnosticProperty = $reference.PSObject.Properties['diagnostic']
  if ($null -eq $diagnosticProperty -or $null -eq $diagnosticProperty.Value) {
    return [pscustomobject][ordered]@{ status = 'unavailable'; category = 'content_response_reference_missing' }
  }
  $diagnostic = $diagnosticProperty.Value
  if ((Get-HypiumTextProperty -Object $diagnostic -Name 'contentProbeOutcome') -ne 'complete') {
    # Do not compare reader output with an original response that was never
    # fingerprinted. An old reference APK may still produce a content string,
    # but it cannot establish that both engines parsed the same input.
    return [pscustomobject][ordered]@{ status = 'unavailable'; category = 'content_response_parity_unavailable' }
  }
  $isParity =
    [int](Get-HypiumTextProperty -Object $diagnostic -Name 'contentProbeStatusCode') -eq [int]$ContentTrace.statusCode -and
    (Get-HypiumTextProperty -Object $diagnostic -Name 'contentProbePlannedTargetSha256') -eq (Get-HypiumTextProperty -Object $ContentTrace -Name 'requestTargetSha256') -and
    (Get-HypiumTextProperty -Object $diagnostic -Name 'contentProbeRequestUserAgentSha256') -eq (Get-HypiumTextProperty -Object $ContentTrace -Name 'requestUserAgentSha256') -and
    (Get-HypiumTextProperty -Object $diagnostic -Name 'contentProbeRequestMethod').ToUpperInvariant() -eq (Get-HypiumTextProperty -Object $ContentTrace -Name 'requestMethod').ToUpperInvariant() -and
    [int](Get-HypiumTextProperty -Object $diagnostic -Name 'contentProbeRequestHeaderCount') -eq [int](Get-HypiumTextProperty -Object $ContentTrace -Name 'requestHeaderCount') -and
    (Get-HypiumTextProperty -Object $diagnostic -Name 'contentProbeRequestHeaderFingerprint') -eq (Get-HypiumTextProperty -Object $ContentTrace -Name 'requestHeaderFingerprint') -and
    (Get-HypiumTextProperty -Object $diagnostic -Name 'contentProbeContentType') -eq (Get-HypiumTextProperty -Object $ContentTrace -Name 'responseContentType') -and
    [int](Get-HypiumTextProperty -Object $diagnostic -Name 'contentProbeBodyLength') -eq [int](Get-HypiumTextProperty -Object $ContentTrace -Name 'responseBodyLength') -and
    (Get-HypiumTextProperty -Object $diagnostic -Name 'contentProbeBodyFingerprint') -eq (Get-HypiumTextProperty -Object $ContentTrace -Name 'responseBodyFingerprint') -and
    (Get-HypiumTextProperty -Object $diagnostic -Name 'contentProbeResponseClass') -eq (Get-HypiumTextProperty -Object $ContentTrace -Name 'responseClass')
  if ($isParity) {
    return [pscustomobject][ordered]@{ status = 'match'; category = 'content_response_parity_match' }
  }
  return [pscustomobject][ordered]@{ status = 'mismatch'; category = 'content_request_response_parity_mismatch' }
}

function Get-HypiumSafeReadSemanticQualification {
  param([object]$Record, [object]$Attempt)
  $reference = Get-HypiumReferenceSearchEvidence -Record $Record
  $contentTrace = Get-HypiumDetailTrace -Attempt $Attempt -Workflow 'content'
  if ($null -eq $reference -or -not [bool]$reference.traceReceived) {
    return [pscustomobject][ordered]@{ qualification = 'execution_verified_no_reference'; category = 'content_reference_missing' }
  }
  if ($null -eq $contentTrace -or [string]$contentTrace.outputKind -ne 'content_readable') {
    return [pscustomobject][ordered]@{ qualification = 'semantic_mismatch'; category = 'content_trace_missing' }
  }
  $contentResponseParity = Get-HypiumContentResponseParityQualification -Record $Record -Attempt $Attempt -ContentTrace $contentTrace
  if ([string]$contentResponseParity.status -eq 'unavailable') {
    return [pscustomobject][ordered]@{ qualification = 'content_parity_unconfirmed'; category = [string]$contentResponseParity.category }
  }
  if ([string]$contentResponseParity.status -eq 'mismatch') {
    return [pscustomobject][ordered]@{ qualification = 'semantic_mismatch'; category = [string]$contentResponseParity.category }
  }
  $referenceLength = [int](Get-HypiumTextProperty -Object $reference -Name 'contentLength')
  $referenceFingerprint = Get-HypiumTextProperty -Object $reference -Name 'contentFingerprint'
  $readerContent = $Attempt.PSObject.Properties['readerContent']
  if ($null -eq $readerContent -or $null -eq $readerContent.Value) {
    return [pscustomobject][ordered]@{ qualification = 'content_parity_unconfirmed'; category = 'reader_content_fingerprint_missing' }
  }
  $v2Length = [int](Get-HypiumTextProperty -Object $readerContent.Value -Name 'contentCharacterCount')
  $v2Fingerprint = Get-HypiumTextProperty -Object $readerContent.Value -Name 'contentFingerprint'
  if ($referenceLength -le 0) {
    return [pscustomobject][ordered]@{ qualification = 'content_parity_unconfirmed'; category = 'content_reference_unavailable' }
  }
  if ($referenceFingerprint.Length -eq 0) {
    return [pscustomobject][ordered]@{ qualification = 'content_parity_unconfirmed'; category = 'content_fingerprint_missing' }
  }
  $referenceLineFeed = $reference.PSObject.Properties['contentLineFeedCount']
  $referenceCarriageReturn = $reference.PSObject.Properties['contentCarriageReturnCount']
  $referenceLeadingWhitespace = $reference.PSObject.Properties['contentLeadingWhitespaceCount']
  $referenceTrailingWhitespace = $reference.PSObject.Properties['contentTrailingWhitespaceCount']
  if ($null -eq $referenceLineFeed -or $null -eq $referenceCarriageReturn -or
    $null -eq $referenceLeadingWhitespace -or $null -eq $referenceTrailingWhitespace) {
    return [pscustomobject][ordered]@{ qualification = 'content_parity_unconfirmed'; category = 'content_structure_reference_missing' }
  }
  if ($referenceLength -ne $v2Length) {
    return [pscustomobject][ordered]@{ qualification = 'semantic_mismatch'; category = 'content_length_mismatch' }
  }
  if ($v2Fingerprint.Length -eq 0 -or -not $referenceFingerprint.Equals($v2Fingerprint, [System.StringComparison]::OrdinalIgnoreCase)) {
    return [pscustomobject][ordered]@{ qualification = 'semantic_mismatch'; category = 'content_fingerprint_mismatch' }
  }
  if ([int](Get-HypiumTextProperty -Object $reference -Name 'contentLineFeedCount') -ne [int](Get-HypiumTextProperty -Object $readerContent.Value -Name 'contentLineFeedCount')) {
    return [pscustomobject][ordered]@{ qualification = 'semantic_mismatch'; category = 'content_line_feed_count_mismatch' }
  }
  if ([int](Get-HypiumTextProperty -Object $reference -Name 'contentCarriageReturnCount') -ne [int](Get-HypiumTextProperty -Object $readerContent.Value -Name 'contentCarriageReturnCount')) {
    return [pscustomobject][ordered]@{ qualification = 'semantic_mismatch'; category = 'content_carriage_return_count_mismatch' }
  }
  if ([int](Get-HypiumTextProperty -Object $reference -Name 'contentLeadingWhitespaceCount') -ne [int](Get-HypiumTextProperty -Object $readerContent.Value -Name 'contentLeadingWhitespaceCount')) {
    return [pscustomobject][ordered]@{ qualification = 'semantic_mismatch'; category = 'content_leading_whitespace_count_mismatch' }
  }
  if ([int](Get-HypiumTextProperty -Object $reference -Name 'contentTrailingWhitespaceCount') -ne [int](Get-HypiumTextProperty -Object $readerContent.Value -Name 'contentTrailingWhitespaceCount')) {
    return [pscustomobject][ordered]@{ qualification = 'semantic_mismatch'; category = 'content_trailing_whitespace_count_mismatch' }
  }
  return [pscustomobject][ordered]@{ qualification = 'semantic_match'; category = 'content_parity_match' }
}

function Resolve-HypiumGovernanceFinding {
  param(
    [object]$State,
    [object]$Record,
    [string]$ResolutionSummary = 'v2_hypium_retested_passed'
  )
  $governanceProperty = $State.PSObject.Properties['governance']
  if ($null -eq $governanceProperty -or $null -eq $governanceProperty.Value) { return }
  $findingIds = New-Object 'System.Collections.Generic.List[string]'
  [void]$findingIds.Add('ISSUE-COMPAT-HYPIUM-' + ([string]$Record.sourceId).Substring(0, 12))
  $legacyIssueIdsProperty = $Record.PSObject.Properties['issueIds']
  if ($null -ne $legacyIssueIdsProperty -and $null -ne $legacyIssueIdsProperty.Value) {
    foreach ($legacyIssueId in @($legacyIssueIdsProperty.Value)) {
      # Issue IDs intentionally use uppercase source-hash prefixes.  The
      # telemetry token sanitizer lowercases/rejects those IDs, which made a
      # successful retest unable to resolve its own stale finding.
      $normalizedIssueId = ([string]$legacyIssueId).Trim()
      if ($normalizedIssueId.Length -gt 0 -and -not $findingIds.Contains($normalizedIssueId)) {
        [void]$findingIds.Add($normalizedIssueId)
      }
    }
  }
  $attemptCount = [int]$Record.workflows.search.attempts
  # queuedFindings drives recovery while issues drives the Markdown evidence
  # mirror. Resolve both in the same state checkpoint so an accepted device
  # retest can never leave the published task list at a stale failed state.
  foreach ($collectionName in @('queuedFindings', 'issues')) {
    $collectionProperty = $governanceProperty.Value.PSObject.Properties[$collectionName]
    if ($null -eq $collectionProperty -or $null -eq $collectionProperty.Value) { continue }
    foreach ($item in @($collectionProperty.Value)) {
      $itemId = (Get-HypiumTextProperty -Object $item -Name 'id').Trim()
      if ($itemId.Length -gt 0 -and $findingIds.Contains($itemId)) {
        Set-HypiumProperty -Object $item -Name 'status' -Value 'passed'
        Set-HypiumProperty -Object $item -Name 'attempts' -Value $attemptCount
        Set-HypiumProperty -Object $item -Name 'summary' -Value (Get-HypiumSafeToken -Value ('resolved_' + $ResolutionSummary))
        Set-HypiumProperty -Object $item -Name 'lastUpdatedAt' -Value (Get-HypiumNow)
      }
    }
  }
}

function Test-HypiumSafety {
  param([object]$Record, [object]$Source, [string]$RawDocument, [string]$ExecutionProfile)
  $name = Get-HypiumTextProperty -Object $Source -Name 'bookSourceName'
  $url = Get-HypiumTextProperty -Object $Source -Name 'bookSourceUrl'
  if ($name.Trim().Length -eq 0 -or $url.Trim().Length -eq 0) { return [pscustomobject]@{ run = $false; status = 'blocked'; outcome = 'source_identity_fields_missing' } }
  if ([int]$Record.sourceType -eq 4) { return [pscustomobject]@{ run = $false; status = 'policy_blocked'; outcome = 'external_plugin_candidate' } }
  # Interaction is an intrinsic source constraint. Classify it before V2
  # readiness so a disabled V2 record never disguises a login/captcha/paywall
  # requirement as an engine-routing failure.
  if ([bool]$Record.capabilities.login -or $RawDocument -match '(?i)captcha|验证码|人机验证') { return [pscustomobject]@{ run = $false; status = 'needs_interaction'; outcome = 'interactive_login_or_captcha' } }
  if ([bool]$Record.capabilities.payAction) { return [pscustomobject]@{ run = $false; status = 'needs_interaction'; outcome = 'interactive_payment_action' } }
  $readinessProperty = $Record.PSObject.Properties['deviceReadiness']
  $readiness = if ($null -ne $readinessProperty) { $readinessProperty.Value } else { $null }
  if ($RequireFreshReadiness -and ($null -eq $readiness -or -not [bool]$readiness.present -or -not [bool]$readiness.rawHashMatches)) { return [pscustomobject]@{ run = $false; status = 'blocked'; outcome = 'fresh_v2_readiness_gate_failed' } }
  # Database readiness is an import snapshot, not proof of the runtime route.
  # V2 contracts can evolve while the raw source remains unchanged. Let the
  # actual Hypium-driven request produce the authoritative V2 trace; a missing
  # trace is classified as an explicit compatibility failure later in the run.
  $searchUrl = Get-HypiumTextProperty -Object $Source -Name 'searchUrl'
  $exploreUrl = Get-HypiumTextProperty -Object $Source -Name 'exploreUrl'
  $exploreOnlyPath = $ExecutionProfile -in @('safe_read_path', 'full_workflow') -and [bool]$Record.capabilities.explore -and $exploreUrl.Trim().Length -gt 0
  if ($searchUrl.Trim().Length -eq 0) {
    if ($exploreOnlyPath) { return [pscustomobject]@{ run = $true; status = 'running'; outcome = 'explore_only_path' } }
    return [pscustomobject]@{ run = $false; status = 'policy_blocked'; outcome = 'search_workflow_missing' }
  }
  if (-not $AllowIdempotentPostSearch -and $searchUrl -match "(?i)[`"']method[`"']\s*:\s*[`"']POST[`"']|method\s*=\s*POST") { return [pscustomobject]@{ run = $false; status = 'policy_blocked'; outcome = 'post_search_not_authorized' } }
  return [pscustomobject]@{ run = $true; status = 'running'; outcome = 'safe_user_path' }
}

function Wait-HypiumRequestInterval {
  if ($null -ne $script:LastRequestAt) {
    $remaining = $MinRequestIntervalSeconds - ([DateTimeOffset]::UtcNow - $script:LastRequestAt).TotalSeconds
    if ($remaining -gt 0) { Start-Sleep -Milliseconds ([int][Math]::Ceiling($remaining * 1000)) }
  }
  $script:LastRequestAt = [DateTimeOffset]::UtcNow
}

function Get-HypiumProcessTimeoutSeconds {
  param([bool]$SafeReadPath)
  # A safe-read run crosses independent UI boundaries for search, detail,
  # TOC, reader content, and the reversible return-to-detail diagnostic.
  # Its child Driver therefore needs a multi-phase budget; a single UI
  # deadline plus a small buffer can terminate Python before finally writes
  # result.json and closes the Driver.
  $singlePathBudget = $UiTimeoutSeconds + 90
  if (-not $SafeReadPath) {
    return $singlePathBudget
  }
  $safeReadBudget = ($UiTimeoutSeconds * 8) + 120
  return [Math]::Min(1500, [Math]::Max($singlePathBudget, $safeReadBudget))
}

function Invoke-HypiumSourceSearch {
  param([object]$Record, [object]$Source, [int]$Attempt, [bool]$SafeReadPath)
  $outputDirectory = Join-Path $EvidenceDirectory ("hypium-{0}-attempt-{1}" -f [string]$Record.sourceId, $Attempt)
  $sourceUrl = Get-HypiumTextProperty -Object $Source -Name 'bookSourceUrl'
  $sourceName = Get-HypiumTextProperty -Object $Source -Name 'bookSourceName'
  $searchKeyword = '斗破苍穹'
  $ruleSearchProperty = $Source.PSObject.Properties['ruleSearch']
  if ($null -ne $ruleSearchProperty -and $null -ne $ruleSearchProperty.Value) {
    $checkKeyProperty = $ruleSearchProperty.Value.PSObject.Properties['checkKeyWord']
    if ($null -ne $checkKeyProperty -and -not [string]::IsNullOrWhiteSpace([string]$checkKeyProperty.Value)) {
      $searchKeyword = [string]$checkKeyProperty.Value
    }
  }
  Wait-HypiumRequestInterval
  $argumentList = [System.Collections.Generic.List[string]]::new()
  foreach ($argument in @(
    $driverPath, '--device-sn', $Device, '--hdc-path', $HdcPath, '--output-dir', $outputDirectory,
    '--source-id', $sourceUrl, '--source-name', $sourceName, '--search-keyword', $searchKeyword, '--timeout', [string]$UiTimeoutSeconds
  )) { [void]$argumentList.Add($argument) }
  if ($SafeReadPath) {
    [void]$argumentList.Add('--safe-read-path')
    if ([int]$Record.sourceType -eq 2) { [void]$argumentList.Add('--image-workflow') }
  }
  # The Python driver may legitimately wait at more than one workflow
  # boundary. Keep process termination beyond the complete selected path so
  # its finally block can always write evidence and release the UI Driver.
  $processTimeoutSeconds = Get-HypiumProcessTimeoutSeconds -SafeReadPath $SafeReadPath
  $result = Invoke-LegadoNativeProcess -FilePath $PythonPath -ArgumentList $argumentList.ToArray() -TimeoutSeconds $processTimeoutSeconds
  $resultPath = Join-Path $outputDirectory 'result.json'
  if (-not (Test-Path -LiteralPath $resultPath)) {
    # The native timeout terminates Python before its finally block can persist
    # evidence. Preserve the checkpoint and distinguish a process exit from an
    # automation stall instead of leaving the canonical source state running.
    Write-HypiumMissingResult -OutputDirectory $outputDirectory -ProcessResult $result
  }
  $evidence = Read-LegadoJsonFile -Path $resultPath
  $traceRecordsProperty = $evidence.PSObject.Properties['trace_records']
  $traceRecords = if ($null -ne $traceRecordsProperty -and $null -ne $traceRecordsProperty.Value) {
    @($traceRecordsProperty.Value)
  } else {
    @()
  }
  $traces = @($traceRecords | Where-Object { [string]$_.workflow -eq 'search' })
  $trace = if ($traces.Count -gt 0) { $traces[$traces.Count - 1] } else { $null }
  $errorText = Get-HypiumTextProperty -Object $evidence -Name 'error'
  $workflowResultsProperty = $evidence.PSObject.Properties['workflow_results']
  $workflowResults = if ($null -ne $workflowResultsProperty) { $workflowResultsProperty.Value } else { $null }
  $detailTraceRecordsProperty = $evidence.PSObject.Properties['detail_trace_records']
  $detailTraceRecords = if ($null -ne $detailTraceRecordsProperty -and $null -ne $detailTraceRecordsProperty.Value) {
    @($detailTraceRecordsProperty.Value)
  } else {
    @()
  }
  $previousContentTraceAt = [Int64](Get-HypiumTextProperty -Object $evidence -Name 'previous_content_trace_at')
  $readerContentTraceAt = [Int64](Get-HypiumTextProperty -Object $evidence -Name 'reader_content_trace_at')
  $contentTraceAfterReaderAt = [Int64](Get-HypiumTextProperty -Object $evidence -Name 'content_trace_after_reader_at')
  $driverClosedText = Get-HypiumTextProperty -Object $evidence -Name 'driver_closed'
  $readerContent = Get-HypiumReaderContentEvidence -Evidence $evidence
  $imageTraceProperty = $evidence.PSObject.Properties['image_trace']
  $imageTrace = if ($null -ne $imageTraceProperty -and $null -ne $imageTraceProperty.Value) { $imageTraceProperty.Value } else { $null }
  $compileDiagnosticCodesProperty = $evidence.PSObject.Properties['v2_compile_diagnostic_codes']
  $compileDiagnosticCodes = if ($null -ne $compileDiagnosticCodesProperty -and $null -ne $compileDiagnosticCodesProperty.Value) {
    @($compileDiagnosticCodesProperty.Value | ForEach-Object { Get-HypiumSafeToken -Value ([string]$_) -Fallback '' } | Where-Object { $_.Length -gt 0 })
  } else {
    @()
  }
  return [pscustomobject][ordered]@{
    # Python writes a structured fallback result after a process timeout, but
    # an interrupted write can still leave an older or partial JSON object.
    # Treat absent optional result fields as a classified harness failure; do
    # not let StrictMode prevent the source state and governance evidence from
    # being atomically settled.
    outcome = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $evidence -Name 'search_outcome') -Fallback 'ui_failure'
    runnerStatus = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $evidence -Name 'status') -Fallback 'failed'
    errorDigest = if ($errorText.Length -gt 0) { Get-LegadoSha256ForText -Value $errorText } else { '' }
    errorCategory = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $evidence -Name 'search_error_category') -Fallback ''
    evidencePath = [System.IO.Path]::GetRelativePath($EvidenceDirectory, $resultPath).Replace('\\', '/')
    trace = $trace
    detailTraceRecords = $detailTraceRecords
    previousContentTraceAt = $previousContentTraceAt
    readerContentTraceAt = $readerContentTraceAt
    contentTraceAfterReaderAt = $contentTraceAfterReaderAt
    workflowResults = $workflowResults
    readerContent = $readerContent
    imageTrace = $imageTrace
    compileDiagnosticCodes = $compileDiagnosticCodes
    driverClosed = $driverClosedText -eq 'True'
    processClassification = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $evidence -Name 'process_classification') -Fallback 'completed'
  }
}

function Invoke-HypiumSourceExplore {
  param(
    [object]$Record,
    [object]$Source,
    [int]$Attempt,
    [bool]$ContinueReadPath = $false
  )
  $outputDirectory = Join-Path $EvidenceDirectory ("hypium-{0}-explore-attempt-{1}" -f [string]$Record.sourceId, $Attempt)
  $sourceUrl = Get-HypiumTextProperty -Object $Source -Name 'bookSourceUrl'
  $sourceName = Get-HypiumTextProperty -Object $Source -Name 'bookSourceName'
  Wait-HypiumRequestInterval
  $argumentList = [System.Collections.Generic.List[string]]::new()
  foreach ($argument in @(
    $driverPath, '--device-sn', $Device, '--hdc-path', $HdcPath, '--output-dir', $outputDirectory,
    '--source-id', $sourceUrl, '--source-name', $sourceName, '--explore-workflow', '--timeout', [string]$UiTimeoutSeconds
  )) { [void]$argumentList.Add($argument) }
  if ($ContinueReadPath) { [void]$argumentList.Add('--explore-read-path') }
  if ($ContinueReadPath -and [int]$Record.sourceType -eq 2) { [void]$argumentList.Add('--image-workflow') }
  $processTimeoutSeconds = Get-HypiumProcessTimeoutSeconds -SafeReadPath $ContinueReadPath
  $result = Invoke-LegadoNativeProcess -FilePath $PythonPath -ArgumentList $argumentList.ToArray() -TimeoutSeconds $processTimeoutSeconds
  $resultPath = Join-Path $outputDirectory 'result.json'
  if (-not (Test-Path -LiteralPath $resultPath)) {
    Write-HypiumMissingResult -OutputDirectory $outputDirectory -ProcessResult $result
  }
  $evidence = Read-LegadoJsonFile -Path $resultPath
  $errorText = Get-HypiumTextProperty -Object $evidence -Name 'error'
  $exploreTraceProperty = $evidence.PSObject.Properties['explore_trace']
  $exploreTrace = $null
  if ($null -ne $exploreTraceProperty -and $null -ne $exploreTraceProperty.Value) {
    $traceValue = $exploreTraceProperty.Value
    $outputSummary = Get-HypiumTextProperty -Object $traceValue -Name 'outputSummary'
    $exploreTrace = [pscustomobject][ordered]@{
      workflow = 'explore'
      transport = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $traceValue -Name 'transport') -Fallback 'unknown_transport'
      statusCode = [int](Get-HypiumTextProperty -Object $traceValue -Name 'statusCode')
      errorCode = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $traceValue -Name 'errorCode') -Fallback 'unclassified_error'
      outputKind = if ((Get-HypiumTextProperty -Object $evidence -Name 'explore_outcome') -eq 'result') { 'explore_nonempty' } else { 'explore_empty' }
      outputSummarySha256 = Get-LegadoSha256ForText -Value $outputSummary
      requestHeaderNames = @()
      webViewLifecycle = ''
    }
  }
  $workflowResultsProperty = $evidence.PSObject.Properties['workflow_results']
  $workflowResults = if ($null -ne $workflowResultsProperty -and $null -ne $workflowResultsProperty.Value) { $workflowResultsProperty.Value } else { $null }
  $detailTraceRecordsProperty = $evidence.PSObject.Properties['detail_trace_records']
  $detailTraceRecords = if ($null -ne $detailTraceRecordsProperty -and $null -ne $detailTraceRecordsProperty.Value) {
    @($detailTraceRecordsProperty.Value)
  } else { @() }
  $previousContentTraceAt = [Int64](Get-HypiumTextProperty -Object $evidence -Name 'previous_content_trace_at')
  $readerContentTraceAt = [Int64](Get-HypiumTextProperty -Object $evidence -Name 'reader_content_trace_at')
  $contentTraceAfterReaderAt = [Int64](Get-HypiumTextProperty -Object $evidence -Name 'content_trace_after_reader_at')
  $readerContent = Get-HypiumReaderContentEvidence -Evidence $evidence
  $imageTraceProperty = $evidence.PSObject.Properties['image_trace']
  $imageTrace = if ($null -ne $imageTraceProperty -and $null -ne $imageTraceProperty.Value) {
    $imageTraceProperty.Value
  } else {
    $null
  }
  $compileDiagnosticCodesProperty = $evidence.PSObject.Properties['v2_compile_diagnostic_codes']
  $compileDiagnosticCodes = if ($null -ne $compileDiagnosticCodesProperty -and $null -ne $compileDiagnosticCodesProperty.Value) {
    @($compileDiagnosticCodesProperty.Value | ForEach-Object { Get-HypiumSafeToken -Value ([string]$_) -Fallback '' } | Where-Object { $_.Length -gt 0 })
  } else { @() }
  return [pscustomobject][ordered]@{
    outcome = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $evidence -Name 'explore_outcome') -Fallback 'ui_failure'
    runnerStatus = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $evidence -Name 'status') -Fallback 'failed'
    errorDigest = if ($errorText.Length -gt 0) { Get-LegadoSha256ForText -Value $errorText } else { '' }
    errorCategory = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $evidence -Name 'explore_error_category') -Fallback ''
    evidencePath = [System.IO.Path]::GetRelativePath($EvidenceDirectory, $resultPath).Replace('\', '/')
    trace = $exploreTrace
    detailTraceRecords = $detailTraceRecords
    previousContentTraceAt = $previousContentTraceAt
    readerContentTraceAt = $readerContentTraceAt
    contentTraceAfterReaderAt = $contentTraceAfterReaderAt
    workflowResults = $workflowResults
    exploreReadPathRequested = $ContinueReadPath
    readerContent = $readerContent
    imageTrace = $imageTrace
    compileDiagnosticCodes = $compileDiagnosticCodes
    driverClosed = (Get-HypiumTextProperty -Object $evidence -Name 'driver_closed') -eq 'True'
    processClassification = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $evidence -Name 'process_classification') -Fallback 'completed'
  }
}

function Get-HypiumSafeAdditionalAttempt {
  param([object]$Attempt)
  if ($null -eq $Attempt) { return $null }
  $trace = $null
  if ($null -ne $Attempt.trace) {
    $trace = [pscustomobject][ordered]@{
      workflow = Get-HypiumSafeToken -Value ([string]$Attempt.trace.workflow) -Fallback 'unknown_workflow'
      transport = Get-HypiumSafeToken -Value ([string]$Attempt.trace.transport) -Fallback 'unknown_transport'
      statusCode = [int]$Attempt.trace.statusCode
      errorCode = Get-HypiumSafeToken -Value ([string]$Attempt.trace.errorCode) -Fallback 'unclassified_error'
      outputKind = Get-HypiumSafeToken -Value ([string]$Attempt.trace.outputKind) -Fallback 'unrecognized'
      outputSummarySha256 = [string]$Attempt.trace.outputSummarySha256
    }
  }
  return [pscustomobject][ordered]@{
    outcome = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $Attempt -Name 'outcome') -Fallback 'unclassified'
    runnerStatus = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $Attempt -Name 'runnerStatus') -Fallback 'failed'
    errorDigest = Get-HypiumTextProperty -Object $Attempt -Name 'errorDigest'
    evidencePath = Get-HypiumTextProperty -Object $Attempt -Name 'evidencePath'
    driverClosed = [bool]$Attempt.driverClosed
    processClassification = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $Attempt -Name 'processClassification') -Fallback 'completed'
    trace = $trace
  }
}

function Write-HypiumSourceEvidence {
  param([object]$Record, [object]$Attempt)
  # Every terminal branch, including policy-blocked and Explore-only early
  # returns, funnels through this writer. Reconcile immediately before
  # projection so sourceAttempt cannot retain a stale counter from a prior
  # batch even when the caller returns before the normal terminal tail.
  Sync-HypiumSourceAttempt -State $State -Record $Record
  $path = Join-Path $EvidenceDirectory ("source-{0}.json" -f [string]$Record.sourceId)
  $safeTrace = if ($null -ne $Attempt.trace) { [pscustomobject][ordered]@{
    workflow = Get-HypiumSafeToken -Value ([string]$Attempt.trace.workflow) -Fallback 'unknown_workflow'
    transport = Get-HypiumSafeToken -Value ([string]$Attempt.trace.transport) -Fallback 'unknown_transport'
    statusCode = [int]$Attempt.trace.statusCode
    errorCode = Get-HypiumSafeToken -Value ([string]$Attempt.trace.errorCode) -Fallback 'unclassified_error'
    outputKind = Get-HypiumSafeToken -Value ([string]$Attempt.trace.outputKind) -Fallback 'unrecognized'
    outputSummarySha256 = [string]$Attempt.trace.outputSummarySha256
    requestHeaderNames = @(Get-HypiumHeaderNames -Object $Attempt.trace -Name 'requestHeaderNames')
    searchBookTargetSequenceSha256 = @(Get-HypiumTargetDigestArrayProperty -Object $Attempt.trace -Name 'searchBookTargetSequenceSha256')
    searchBookTargetSequenceDistinctCount = [int](Get-HypiumTextProperty -Object $Attempt.trace -Name 'searchBookTargetSequenceDistinctCount')
    searchBookTargetSequenceEmptyCount = [int](Get-HypiumTextProperty -Object $Attempt.trace -Name 'searchBookTargetSequenceEmptyCount')
    searchBookDeduplicatedCount = [int](Get-HypiumTextProperty -Object $Attempt.trace -Name 'searchBookDeduplicatedCount')
    searchBookReversed = Get-HypiumBooleanProperty -Object $Attempt.trace -Name 'searchBookReversed'
    webViewLifecycle = Get-HypiumTextProperty -Object $Attempt.trace -Name 'webViewLifecycle'
  } } else { $null }
  $semanticDifference = $Attempt.PSObject.Properties['semanticDifference']
  $readerContentProperty = $Attempt.PSObject.Properties['readerContent']
  $readerContent = if ($null -ne $readerContentProperty) { $readerContentProperty.Value } else { $null }
  $imageTraceProperty = $Attempt.PSObject.Properties['imageTrace']
  $imageTrace = if ($null -ne $imageTraceProperty -and $null -ne $imageTraceProperty.Value) {
    [pscustomobject][ordered]@{
      eventCount = [int](Get-HypiumTextProperty -Object $imageTraceProperty.Value -Name 'eventCount')
      freshness = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $imageTraceProperty.Value -Name 'freshness') -Fallback 'unclassified'
      planned = [int](Get-HypiumTextProperty -Object $imageTraceProperty.Value -Name 'planned')
      requestStarted = [int](Get-HypiumTextProperty -Object $imageTraceProperty.Value -Name 'requestStarted')
      httpResponses = [int](Get-HypiumTextProperty -Object $imageTraceProperty.Value -Name 'httpResponses')
      decodeComplete = [int](Get-HypiumTextProperty -Object $imageTraceProperty.Value -Name 'decodeComplete')
      decodeFailed = [int](Get-HypiumTextProperty -Object $imageTraceProperty.Value -Name 'decodeFailed')
      transportFailures = [int](Get-HypiumTextProperty -Object $imageTraceProperty.Value -Name 'transportFailures')
      pipelineComplete = [int](Get-HypiumTextProperty -Object $imageTraceProperty.Value -Name 'pipelineComplete')
      pipelineFailures = [int](Get-HypiumTextProperty -Object $imageTraceProperty.Value -Name 'pipelineFailures')
      failureOutcomes = Get-HypiumImageTraceOutcomeCounts -ImageTrace $imageTraceProperty.Value -Name 'failureOutcomes'
      pipelineOutcomes = Get-HypiumImageTraceOutcomeCounts -ImageTrace $imageTraceProperty.Value -Name 'pipelineOutcomes'
      sourceRawSha256 = @(Get-HypiumArrayProperty -Object $imageTraceProperty.Value -Name 'sourceRawSha256')
    }
  } else { $null }
  $exploreAttemptProperty = $Attempt.PSObject.Properties['exploreAttempt']
  $exploreRawAttempt = if ($null -ne $exploreAttemptProperty -and $null -ne $exploreAttemptProperty.Value) { $exploreAttemptProperty.Value } else { $null }
  $exploreAttempt = if ($null -ne $exploreAttemptProperty -and $null -ne $exploreAttemptProperty.Value) {
    Get-HypiumSafeAdditionalAttempt -Attempt $exploreAttemptProperty.Value
  } else { $null }
  $workflowResults = [pscustomobject][ordered]@{
    search = Get-HypiumWorkflowResult -Attempt $Attempt -Name 'search'
    bookInfo = Get-HypiumWorkflowResult -Attempt $Attempt -Name 'book_info'
    toc = Get-HypiumWorkflowResult -Attempt $Attempt -Name 'toc'
    content = Get-HypiumWorkflowResult -Attempt $Attempt -Name 'content'
    explore = Get-HypiumWorkflowResultFromAttempts -Attempt $Attempt -AdditionalAttempt $exploreRawAttempt -Name 'explore'
    file = ''
    review = ''
  }
  $workflowStatusMatrix = Get-HypiumWorkflowStatusMatrix -Record $Record -Attempt $Attempt -AdditionalExploreAttempt $exploreRawAttempt
  foreach ($fallbackPair in @(
    @('search', 'search'),
    @('bookInfo', 'bookInfo'),
    @('toc', 'toc'),
    @('content', 'content'),
    @('explore', 'explore'),
    @('file', 'file'),
    @('review', 'review')
  )) {
    $resultProperty = $workflowResults.PSObject.Properties[[string]$fallbackPair[0]]
    if ($null -ne $resultProperty -and [string]::IsNullOrWhiteSpace([string]$resultProperty.Value)) {
      $statusProperty = $workflowStatusMatrix.PSObject.Properties[[string]$fallbackPair[1]]
      if ($null -ne $statusProperty -and $null -ne $statusProperty.Value) {
        Set-HypiumProperty -Object $workflowResults -Name ([string]$fallbackPair[0]) -Value (
          "{0}:{1}" -f [string]$statusProperty.Value.status, [string]$statusProperty.Value.outcome
        )
      }
    }
  }
  $workflowEvidence = Get-HypiumWorkflowEvidenceProjection -Record $Record -Attempt $Attempt -WorkflowStatusMatrix $workflowStatusMatrix -WorkflowResults $workflowResults
  $evidence = [pscustomobject][ordered]@{
    schemaVersion = 2; generatedAt = Get-HypiumNow; runId = $script:RunId; sourcePackageSha256 = $script:ExpectedSourcePackageSha256
    legadoCommit = $script:ExpectedLegadoCommit; sourceId = [string]$Record.sourceId; ordinal = [int]$Record.ordinal
    status = [string]$Record.status; outcome = [string]$Record.lastOutcome; driverClosed = [bool]$Attempt.driverClosed
    semanticQualification = [string]$Record.semanticQualification
    uiOutcome = [string]$Attempt.outcome; runnerStatus = [string]$Attempt.runnerStatus; errorDigest = [string]$Attempt.errorDigest
    hypiumResult = [string]$Attempt.evidencePath; processClassification = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $Attempt -Name 'processClassification') -Fallback 'not_executed'; trace = $safeTrace
    executionProfile = Get-HypiumSafeToken -Value $ExecutionProfile -Fallback 'unclassified'
    sourceAttempt = [int](Get-HypiumTextProperty -Object $Record -Name 'attempts')
    sourceAttemptEvidence = [pscustomobject][ordered]@{
      sourceAttempt = [int](Get-HypiumTextProperty -Object $Record -Name 'attempts')
      searchAttempt = [int]$workflowStatusMatrix.search.attempts
      workflowAttempts = [pscustomobject][ordered]@{
        search = [int]$workflowStatusMatrix.search.attempts
        explore = [int]$workflowStatusMatrix.explore.attempts
        bookInfo = [int]$workflowStatusMatrix.bookInfo.attempts
        toc = [int]$workflowStatusMatrix.toc.attempts
        content = [int]$workflowStatusMatrix.content.attempts
        file = [int]$workflowStatusMatrix.file.attempts
        review = [int]$workflowStatusMatrix.review.attempts
      }
      generatedAt = Get-HypiumNow
    }
    previousContentTraceAt = [Int64](Get-HypiumTextProperty -Object $Attempt -Name 'previousContentTraceAt')
    readerContentTraceAt = [Int64](Get-HypiumTextProperty -Object $Attempt -Name 'readerContentTraceAt')
    contentTraceAfterReaderAt = [Int64](Get-HypiumTextProperty -Object $Attempt -Name 'contentTraceAfterReaderAt')
    readerContent = $readerContent
    imageTrace = $imageTrace
    compileDiagnosticCodes = @(Get-HypiumArrayProperty -Object $Attempt -Name 'compileDiagnosticCodes')
    detailTraceRecords = Get-HypiumSafeDetailTraceRecords -Attempt $Attempt
    exploreAttempt = $exploreAttempt
    workflowResults = $workflowResults
    workflowStatusMatrix = $workflowStatusMatrix
    workflowEvidence = $workflowEvidence
    semanticDifference = if ($null -ne $semanticDifference) { $semanticDifference.Value } else { $null }
  }
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
  Write-HypiumJsonAtomically -Path $path -Value $evidence
  return Get-LegadoSha256ForText -Value ([string]($evidence | ConvertTo-Json -Depth 12))
}

function Get-HypiumFallbackInt {
  param([object]$Object, [string]$Name)
  $raw = Get-HypiumTextProperty -Object $Object -Name $Name
  try { return [int]$raw } catch { return 0 }
}

function Write-HypiumSourceFallbackEvidence {
  param([object]$Record, [string]$ErrorDigest)
  $sourceIdValue = Get-HypiumTextProperty -Object $Record -Name 'sourceId'
  $sourceId = if ($sourceIdValue -match '^[A-Za-z0-9_-]{1,96}$') { $sourceIdValue } else { 'unknown_source' }
  $path = Join-Path $EvidenceDirectory ("source-{0}.fallback.json" -f $sourceId)
  $workflowNames = @('search', 'explore', 'bookInfo', 'toc', 'content', 'file', 'review')
  $workflowMatrix = [ordered]@{}
  $workflowResults = [ordered]@{}
  $workflowEvidence = [ordered]@{}
  $maximumAttempt = 0
  $workflowsProperty = $Record.PSObject.Properties['workflows']
  foreach ($name in $workflowNames) {
    $workflow = $null
    if ($null -ne $workflowsProperty -and $null -ne $workflowsProperty.Value) {
      $workflowProperty = $workflowsProperty.Value.PSObject.Properties[$name]
      if ($null -ne $workflowProperty) { $workflow = $workflowProperty.Value }
    }
    $attempts = Get-HypiumFallbackInt -Object $workflow -Name 'attempts'
    if ($attempts -gt $maximumAttempt) { $maximumAttempt = $attempts }
    $status = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $workflow -Name 'status') -Fallback 'failed'
    if ($status -in @('planned', 'running')) { $status = 'failed' }
    $outcome = Get-HypiumSafeToken -Value (Get-HypiumTextProperty -Object $workflow -Name 'lastOutcome') -Fallback 'record_harness_exception'
    $item = [pscustomobject][ordered]@{
      status = $status
      outcome = $outcome
      attempts = $attempts
      evidenceDigest = ''
      tracePresent = $false
      traceDigest = ''
    }
    $workflowMatrix[$name] = $item
    $workflowResults[$name] = "{0}:{1}" -f $status, $outcome
    $workflowEvidence[$name] = [pscustomobject][ordered]@{
      status = $status
      outcome = $outcome
      attempts = $attempts
      evidenceDigest = ''
      tracePresent = $false
      traceDigest = ''
      result = "{0}:{1}" -f $status, $outcome
    }
  }
  $workflowAttempts = [ordered]@{}
  foreach ($name in $workflowNames) { $workflowAttempts[$name] = [int]$workflowMatrix[$name].attempts }
  $primaryPath = Join-Path $EvidenceDirectory ("source-{0}.json" -f $sourceId)
  $evidence = [pscustomobject][ordered]@{
    schemaVersion = 2
    evidenceKind = 'source_fallback'
    generatedAt = Get-HypiumNow
    runId = $script:RunId
    sourcePackageSha256 = $script:ExpectedSourcePackageSha256
    legadoCommit = $script:ExpectedLegadoCommit
    sourceId = Get-HypiumTextProperty -Object $Record -Name 'sourceId'
    ordinal = Get-HypiumFallbackInt -Object $Record -Name 'ordinal'
    status = 'failed'
    outcome = 'record_harness_exception'
    driverClosed = $false
    semanticQualification = 'harness_or_engine_failure'
    uiOutcome = 'record_harness_exception'
    runnerStatus = 'failed'
    errorDigest = $ErrorDigest
    hypiumResult = ''
    processClassification = 'record_exception'
    executionProfile = Get-HypiumSafeToken -Value $ExecutionProfile -Fallback 'unclassified'
    primaryEvidencePath = ConvertTo-LegadoHypiumEvidenceRelativePath -ScriptRoot $PSScriptRoot -Path $primaryPath
    fallbackReason = 'source_evidence_write_failed'
    sourceAttempt = $maximumAttempt
    sourceAttemptEvidence = [pscustomobject][ordered]@{
      sourceAttempt = $maximumAttempt
      searchAttempt = [int]$workflowMatrix.search.attempts
      workflowAttempts = [pscustomobject]$workflowAttempts
      generatedAt = Get-HypiumNow
    }
    previousContentTraceAt = 0
    readerContentTraceAt = 0
    contentTraceAfterReaderAt = 0
    readerContent = $null
    imageTrace = $null
    compileDiagnosticCodes = @()
    detailTraceRecords = @()
    exploreAttempt = $null
    trace = $null
    workflowResults = [pscustomobject]$workflowResults
    workflowStatusMatrix = [pscustomobject]$workflowMatrix
    workflowEvidence = [pscustomobject]$workflowEvidence
    semanticDifference = $null
  }
  Write-HypiumJsonAtomically -Path $path -Value $evidence
  return [pscustomobject][ordered]@{
    path = $path
    relativePath = ConvertTo-LegadoHypiumEvidenceRelativePath -ScriptRoot $PSScriptRoot -Path $path
    digest = Get-LegadoSha256ForText -Value ([string]($evidence | ConvertTo-Json -Depth 12))
  }
}

function Invoke-HypiumRecord {
  param([object]$State, [object]$Record, [object]$Source, [string]$RawDocument)
  try {
    $decision = Test-HypiumSafety -Record $Record -Source $Source -RawDocument $RawDocument -ExecutionProfile $ExecutionProfile
  if (-not [bool]$decision.run) {
    foreach ($name in @('search', 'explore', 'bookInfo', 'toc', 'content', 'file', 'review')) { Set-HypiumWorkflow -State $State -Record $Record -Name $name -Status $decision.status -Outcome $decision.outcome }
    Set-HypiumSource -State $State -Record $Record -Status $decision.status -Outcome $decision.outcome -Profile 'not_executed'
    $qualification = if ($decision.status -eq 'needs_interaction') { 'needs_interaction' } elseif ($decision.status -eq 'policy_blocked') { 'policy_rejected' } else { 'unverified' }
    Set-HypiumSemanticQualification -Record $Record -Qualification $qualification
    $notExecutedAttempt = [pscustomobject][ordered]@{
      outcome = [string]$decision.outcome
      runnerStatus = 'not_executed'
      errorDigest = ''
      evidencePath = ''
      trace = $null
      driverClosed = $false
    }
    $digest = Write-HypiumSourceEvidence -Record $Record -Attempt $notExecutedAttempt
    Set-HypiumProperty -Object $Record -Name 'lastEvidenceDigest' -Value $digest
    Write-LegadoStateCheckpoint -Path $StatePath -State $State
    [void]$script:ResultSummary.Add([pscustomobject][ordered]@{
      sourceId = [string]$Record.sourceId
      ordinal = [int]$Record.ordinal
      status = [string]$Record.status
      outcome = [string]$Record.lastOutcome
    })
    return
  }
  Set-HypiumSource -State $State -Record $Record -Status 'running' -Outcome 'source_dispatched' -Profile 'running'
  Set-HypiumProperty -Object $Record -Name 'attempts' -Value ([int](Get-HypiumTextProperty -Object $Record -Name 'attempts') + 1)
  Write-LegadoStateCheckpoint -Path $StatePath -State $State
  $exploreCapability = $false
  $capabilitiesProperty = $Record.PSObject.Properties['capabilities']
  if ($null -ne $capabilitiesProperty -and $null -ne $capabilitiesProperty.Value) {
    $exploreProperty = $capabilitiesProperty.Value.PSObject.Properties['explore']
    $exploreCapability = $null -ne $exploreProperty -and [bool]$exploreProperty.Value
  }
  $fullWorkflow = $ExecutionProfile -eq 'full_workflow'
  $fullWorkflowExploreAttempt = $null
  $fullWorkflowExploreResolution = $null
  if ($fullWorkflow) {
    $sourceSearchUrl = Get-HypiumTextProperty -Object $Source -Name 'searchUrl'
    $sourceExploreUrl = Get-HypiumTextProperty -Object $Source -Name 'exploreUrl'
    $hasSearch = $sourceSearchUrl.Trim().Length -gt 0
    $hasExplore = $exploreCapability -and $sourceExploreUrl.Trim().Length -gt 0
    Set-HypiumFullWorkflowPlanning -State $State -Record $Record -HasSearch:$hasSearch -HasExplore:$hasExplore
    Write-LegadoStateCheckpoint -Path $StatePath -State $State
    if ($hasExplore) {
      Set-HypiumWorkflow -State $State -Record $Record -Name 'explore' -Status 'running' -Outcome 'full_workflow_explore_requested' -IncrementAttempt
      Write-LegadoStateCheckpoint -Path $StatePath -State $State
      $continueExploreReadPath = -not $hasSearch -and (Test-HypiumExploreReadCapabilitySet -Record $Record)
      if ($continueExploreReadPath) {
        Set-HypiumFullWorkflowExploreReadWorkflowsRunning -State $State -Record $Record
        Write-LegadoStateCheckpoint -Path $StatePath -State $State
      }
      $fullWorkflowExploreAttempt = Invoke-HypiumSourceExplore -Record $Record -Source $Source -Attempt ([int]$Record.workflows.explore.attempts) -ContinueReadPath:$continueExploreReadPath
      $fullWorkflowExploreResolution = Resolve-HypiumFullWorkflowExploreAttempt -State $State -Record $Record -Attempt $fullWorkflowExploreAttempt
      if ([string]$fullWorkflowExploreResolution.status -ne 'passed') {
        Add-HypiumGovernanceFinding -State $State -Record $Record -Category ([string]$fullWorkflowExploreResolution.category) -Status ([string]$fullWorkflowExploreResolution.status) -Severity 'P1'
      }
      Write-LegadoStateCheckpoint -Path $StatePath -State $State
    }
    if (-not $hasSearch) {
      if ($hasExplore -and $null -ne $fullWorkflowExploreAttempt -and
          [bool]$fullWorkflowExploreAttempt.exploreReadPathRequested -and
          $null -ne $fullWorkflowExploreResolution -and
          [string]$fullWorkflowExploreResolution.status -eq 'passed') {
        $readResolution = Resolve-HypiumFullWorkflowExploreReadAttempt -State $State -Record $Record -Attempt $fullWorkflowExploreAttempt
        if ([string]$readResolution.status -ne 'passed') {
          Add-HypiumGovernanceFinding -State $State -Record $Record -Category ([string]$readResolution.category) -Status ([string]$readResolution.status) -Severity 'P1'
        }
        $digest = Write-HypiumSourceEvidence -Record $Record -Attempt $fullWorkflowExploreAttempt
        Set-HypiumProperty -Object $Record -Name 'lastEvidenceDigest' -Value $digest
        Write-LegadoStateCheckpoint -Path $StatePath -State $State
        [void]$script:ResultSummary.Add([pscustomobject][ordered]@{ sourceId = [string]$Record.sourceId; ordinal = [int]$Record.ordinal; status = [string]$Record.status; outcome = [string]$Record.lastOutcome })
        return
      }
      $dependentSettlements = @(
        Get-LegadoHypiumExploreDependencySettlements `
          -Record $Record `
          -TerminalStatus 'blocked' `
          -TerminalOutcome 'explore_book_target_not_selected'
      )
      foreach ($settlement in $dependentSettlements) {
        Set-HypiumWorkflow `
          -State $State `
          -Record $Record `
          -Name ([string]$settlement.name) `
          -Status ([string]$settlement.status) `
          -Outcome ([string]$settlement.outcome)
      }
      $sourceOutcome = if ($null -ne $fullWorkflowExploreResolution) {
        [string]$fullWorkflowExploreResolution.outcome
      } else {
        'search_workflow_missing'
      }
      $sourceQualification = if ($null -ne $fullWorkflowExploreResolution) {
        [string]$fullWorkflowExploreResolution.qualification
      } else {
        'unverified'
      }
      $sourceStatus = if ($null -ne $fullWorkflowExploreResolution -and [string]$fullWorkflowExploreResolution.status -eq 'needs_interaction') {
        'needs_interaction'
      } else {
        'blocked'
      }
      Set-HypiumSource -State $State -Record $Record -Status $sourceStatus -Outcome $sourceOutcome -Profile 'v2_hypium_full_workflow_explore_only'
      Set-HypiumSemanticQualification -Record $Record -Qualification $sourceQualification
      $noSearchAttempt = if ($null -ne $fullWorkflowExploreAttempt) {
        $fullWorkflowExploreAttempt
      } else {
        [pscustomobject][ordered]@{
          outcome = 'search_workflow_missing'
          runnerStatus = 'not_executed'
          errorDigest = ''
          evidencePath = ''
          trace = $null
          driverClosed = $false
          processClassification = 'not_executed'
        }
      }
      $digest = Write-HypiumSourceEvidence -Record $Record -Attempt $noSearchAttempt
      Set-HypiumProperty -Object $Record -Name 'lastEvidenceDigest' -Value $digest
      Write-LegadoStateCheckpoint -Path $StatePath -State $State
      [void]$script:ResultSummary.Add([pscustomobject][ordered]@{ sourceId = [string]$Record.sourceId; ordinal = [int]$Record.ordinal; status = [string]$Record.status; outcome = [string]$Record.lastOutcome })
      return
    }
  }
  $sourceSearchUrl = Get-HypiumTextProperty -Object $Source -Name 'searchUrl'
  $sourceExploreUrl = Get-HypiumTextProperty -Object $Source -Name 'exploreUrl'
  $hasSearchUrl = $sourceSearchUrl.Trim().Length -gt 0
  $hasExploreUrl = $exploreCapability -and $sourceExploreUrl.Trim().Length -gt 0
  $safeReadExploreOnly = $ExecutionProfile -eq 'safe_read_path' -and $hasExploreUrl -and -not $hasSearchUrl
  if ($ExecutionProfile -eq 'safe_read_path' -and $hasExploreUrl -and $hasSearchUrl) {
    # Explore is an independently declared capability. safe_read_path uses the
    # Search entry for the guarded read chain and records Explore as deferred;
    # it must not replace Search merely because both URLs are present.
    Set-HypiumWorkflow -State $State -Record $Record -Name 'explore' -Status 'policy_blocked' -Outcome 'safe_read_path_explore_deferred'
  }
  if ($safeReadExploreOnly) {
    # An Explore-only source has no Search entry, but its Explore result can
    # still select a book and continue through the same read workflow. The
    # missing Search capability is settled independently and never becomes a
    # source-wide policy rejection.
    Set-HypiumSafeReadExploreOnlyWorkflowsRunning -State $State -Record $Record
    Write-LegadoStateCheckpoint -Path $StatePath -State $State
    $continueExploreReadPath = Test-HypiumExploreReadCapabilitySet -Record $Record
    $attempt = Invoke-HypiumSourceExplore -Record $Record -Source $Source -Attempt ([int]$Record.workflows.explore.attempts) -ContinueReadPath:$continueExploreReadPath
    $exploreResolution = Resolve-HypiumFullWorkflowExploreAttempt -State $State -Record $Record -Attempt $attempt
    $readResolution = $null
    if ([string]$exploreResolution.status -eq 'passed' -and [bool]$attempt.exploreReadPathRequested) {
      $readResolution = Resolve-HypiumFullWorkflowExploreReadAttempt -State $State -Record $Record -Attempt $attempt
      Set-HypiumSource -State $State -Record $Record -Status ([string]$readResolution.status) -Outcome ([string]$readResolution.outcome) -Profile 'v2_hypium_safe_read_explore_only'
      Set-HypiumSemanticQualification -Record $Record -Qualification ([string]$readResolution.qualification)
    } else {
      $terminalStatus = [string]$exploreResolution.status
      if ($terminalStatus -eq 'passed') { $terminalStatus = 'blocked' }
      $terminalOutcome = if ($terminalStatus -eq 'needs_interaction') {
        'protected_response_requires_interaction'
      } elseif (-not $continueExploreReadPath -and [string]$exploreResolution.status -eq 'passed') {
        'safe_read_path_explore_read_not_executed_after_capability_settlement'
      } else {
        'safe_read_path_explore_read_not_executed_after_explore_terminal'
      }
      Set-HypiumExploreOnlyReadTerminal -State $State -Record $Record -Status $terminalStatus -Outcome $terminalOutcome
      Set-HypiumSource -State $State -Record $Record -Status $terminalStatus -Outcome ([string]$exploreResolution.outcome) -Profile 'v2_hypium_safe_read_explore_only'
      Set-HypiumSemanticQualification -Record $Record -Qualification ([string]$exploreResolution.qualification)
      $readResolution = [pscustomobject][ordered]@{ status = $terminalStatus; outcome = $terminalOutcome; qualification = [string]$exploreResolution.qualification; category = [string]$exploreResolution.category }
    }
    if ([string]$exploreResolution.status -ne 'passed') {
      Add-HypiumGovernanceFinding -State $State -Record $Record -Category ([string]$exploreResolution.category) -Status ([string]$exploreResolution.status) -Severity 'P1'
    }
    if ($null -ne $readResolution -and [string]$readResolution.status -notin @('passed', 'blocked')) {
      Add-HypiumGovernanceFinding -State $State -Record $Record -Category ([string]$readResolution.category) -Status ([string]$readResolution.status) -Severity 'P1'
    }
    $digest = Write-HypiumSourceEvidence -Record $Record -Attempt $attempt
    Set-HypiumProperty -Object $Record -Name 'lastEvidenceDigest' -Value $digest
    Write-LegadoStateCheckpoint -Path $StatePath -State $State
    [void]$script:ResultSummary.Add([pscustomobject][ordered]@{ sourceId = [string]$Record.sourceId; ordinal = [int]$Record.ordinal; status = [string]$Record.status; outcome = [string]$Record.lastOutcome })
    return
  }
  $safeReadPath = $ExecutionProfile -in @('safe_read_path', 'full_workflow') -and [int]$Record.sourceType -in @(0, 2) -and
    [bool]$Record.capabilities.bookInfo -and [bool]$Record.capabilities.toc -and [bool]$Record.capabilities.content
  if (-not $fullWorkflow) {
    Set-HypiumNonSearchPolicy -State $State -Record $Record -KeepReadWorkflows:$safeReadPath
  }
  if ($safeReadPath) { Set-HypiumSafeReadWorkflowsRunning -State $State -Record $Record }
  Set-HypiumWorkflow -State $State -Record $Record -Name 'search' -Status 'running' -Outcome 'request_started' -IncrementAttempt
  $attempt = Invoke-HypiumSourceSearch -Record $Record -Source $Source -Attempt ([int]$Record.workflows.search.attempts) -SafeReadPath $safeReadPath
  if ($fullWorkflow -and $null -ne $fullWorkflowExploreAttempt) {
    Set-HypiumProperty -Object $attempt -Name 'exploreAttempt' -Value $fullWorkflowExploreAttempt
  }
  $readinessProperty = $Record.PSObject.Properties['deviceReadiness']
  if ($null -ne $readinessProperty -and $null -ne $readinessProperty.Value) {
    $readinessProperty.Value | Add-Member -NotePropertyName 'diagnosticCodes' -NotePropertyValue @(Get-HypiumArrayProperty -Object $attempt -Name 'compileDiagnosticCodes') -Force
    $readinessProperty.Value | Add-Member -NotePropertyName 'checkedAt' -NotePropertyValue (Get-HypiumNow) -Force
    $v2TraceObserved = $null -ne $attempt.trace -and $attempt.driverClosed -and
      $attempt.runnerStatus -eq 'passed' -and [string]$attempt.trace.workflow -eq 'search' -and
      $attempt.errorCategory -ne 'v2_full_cutover_blocked'
    if ($v2TraceObserved) {
      # A full-cutover request that reached a structured Search trace proves
      # the effective runtime route. Keep this separate from semantic success:
      # an empty result still needs same-input original evidence.
      $readinessProperty.Value | Add-Member -NotePropertyName 'compileStatus' -NotePropertyValue 'ready' -Force
      $readinessProperty.Value | Add-Member -NotePropertyName 'engineMode' -NotePropertyValue 'v2_enabled' -Force
      $readinessProperty.Value | Add-Member -NotePropertyName 'runtimeRouteObserved' -NotePropertyValue 'v2' -Force
      $readinessProperty.Value | Add-Member -NotePropertyName 'runtimeRouteObservedAt' -NotePropertyValue (Get-HypiumNow) -Force
    } elseif ($attempt.errorCategory -eq 'v2_full_cutover_blocked') {
      $readinessProperty.Value | Add-Member -NotePropertyName 'runtimeRouteObserved' -NotePropertyValue 'blocked_before_dispatch' -Force
    }
  }
  $countSemanticDifference = Get-HypiumSearchSemanticDifference -Record $Record -Attempt $attempt
  $targetSequenceSemanticDifference = Get-HypiumSearchTargetSequenceDifference -Record $Record -Attempt $attempt
  $semanticDifference = if ($null -ne $targetSequenceSemanticDifference) {
    $targetSequenceSemanticDifference
  } else {
    $countSemanticDifference
  }
  Set-HypiumProperty -Object $attempt -Name 'semanticDifference' -Value $semanticDifference
  $responseSemanticallyComparable = $null -ne $attempt.trace -and (Test-HypiumSearchHttpResponseParity -Record $Record -Trace $attempt.trace)
  $normalHttpSuccess = $null -ne $attempt.trace -and [int]$attempt.trace.statusCode -ge 200 -and [int]$attempt.trace.statusCode -lt 400 -and [string]$attempt.trace.errorCode -eq 'none'
  $success = $attempt.runnerStatus -eq 'passed' -and $attempt.driverClosed -and $null -ne $attempt.trace -and
    [string]$attempt.trace.workflow -eq 'search' -and ($normalHttpSuccess -or $responseSemanticallyComparable) -and
    $null -eq $semanticDifference -and (($attempt.outcome -eq 'result' -and [string]$attempt.trace.outputKind -eq 'search_nonempty') -or ($attempt.outcome -eq 'empty' -and [string]$attempt.trace.outputKind -eq 'search_empty'))
  $referenceForEmpty = Get-HypiumReferenceSearchEvidence -Record $Record
  $emptyWithoutReference = $attempt.outcome -eq 'empty' -and
    [string]$attempt.trace.outputKind -eq 'search_empty' -and
    ($null -eq $referenceForEmpty -or -not [bool]$referenceForEmpty.traceReceived)
  if ($emptyWithoutReference) {
    Set-HypiumWorkflow -State $State -Record $Record -Name 'search' -Status 'blocked' -Outcome 'empty_without_reference' -Digest ([string]$attempt.trace.outputSummarySha256)
    Set-HypiumSource -State $State -Record $Record -Status 'blocked' -Outcome 'empty_without_reference' -Profile 'v2_empty_reference_required'
    Set-HypiumSemanticQualification -Record $Record -Qualification 'unverified'
    Add-HypiumGovernanceFinding -State $State -Record $Record -Category 'empty_without_reference' -Status 'blocked' -Severity 'P1'
  } elseif ($null -ne $semanticDifference -and [string]$semanticDifference.category -eq 'protected_response_requires_interaction') {
    Set-HypiumWorkflow -State $State -Record $Record -Name 'search' -Status 'needs_interaction' -Outcome 'protected_response_requires_interaction' -Digest ([string]$attempt.trace.outputSummarySha256)
    Set-HypiumSource -State $State -Record $Record -Status 'needs_interaction' -Outcome 'protected_response_requires_interaction' -Profile 'v2_protected_response_gate'
    Set-HypiumSemanticQualification -Record $Record -Qualification 'needs_interaction'
    Add-HypiumGovernanceFinding -State $State -Record $Record -Category 'protected_response_requires_interaction' -Status 'needs_interaction' -Severity 'P1'
  } elseif ($null -ne $attempt.trace -and [string]$attempt.trace.errorCode -eq 'needs_interaction' -and
    (Get-HypiumTextProperty -Object $attempt.trace -Name 'responseClass') -in @('html_login', 'html_challenge')) {
    # A V2 protected response is an interaction boundary even when the fixed
    # Android reference has no comparable trace. Do not misclassify a login or
    # challenge page as a driver/execution failure merely because comparison
    # evidence is absent.
    Set-HypiumWorkflow -State $State -Record $Record -Name 'search' -Status 'needs_interaction' -Outcome 'protected_response_requires_interaction' -Digest ([string]$attempt.trace.outputSummarySha256)
    Set-HypiumSource -State $State -Record $Record -Status 'needs_interaction' -Outcome 'protected_response_requires_interaction' -Profile 'v2_protected_response_gate'
    Set-HypiumSemanticQualification -Record $Record -Qualification 'needs_interaction'
    Add-HypiumGovernanceFinding -State $State -Record $Record -Category 'protected_response_requires_interaction' -Status 'needs_interaction' -Severity 'P1'
  } elseif ($success) {
    $outcome = if ($attempt.outcome -eq 'empty') { 'search_execution_empty_result' } else { 'search_nonempty_verified' }
    Set-HypiumWorkflow -State $State -Record $Record -Name 'search' -Status 'passed' -Outcome $outcome -Digest ([string]$attempt.trace.outputSummarySha256)
    $reference = Get-HypiumReferenceSearchEvidence -Record $Record
    $qualification = if ($null -ne $reference -and [bool]$reference.traceReceived) { 'search_semantic_match' } else { 'execution_verified_no_reference' }
    Set-HypiumSemanticQualification -Record $Record -Qualification $qualification
    if ($safeReadPath -and $attempt.outcome -eq 'result') {
      if ([int]$Record.sourceType -eq 2) {
        $imageTrace = $attempt.imageTrace
        $imageEventCount = if ($null -ne $imageTrace) { [int]$imageTrace.eventCount } else { 0 }
        $hasImageBookInfoTrace = @($attempt.detailTraceRecords | Where-Object { [string]$_.workflow -eq 'book_info' }).Count -gt 0
        $hasImageTocTrace = @($attempt.detailTraceRecords | Where-Object { [string]$_.workflow -eq 'toc' }).Count -gt 0
        Set-HypiumWorkflow -State $State -Record $Record -Name 'bookInfo' -Status 'blocked' -Outcome $(if ($hasImageBookInfoTrace) { 'image_book_info_trace_observed_reference_pending' } else { 'image_detail_diagnostics_unavailable' })
        Set-HypiumWorkflow -State $State -Record $Record -Name 'toc' -Status 'blocked' -Outcome $(if ($hasImageTocTrace) { 'image_toc_trace_observed_reference_pending' } else { 'image_detail_diagnostics_unavailable' })
        if ($imageEventCount -le 0) {
          Set-HypiumWorkflow -State $State -Record $Record -Name 'content' -Status 'blocked' -Outcome 'image_reader_trace_missing'
          Set-HypiumSource -State $State -Record $Record -Status 'blocked' -Outcome 'image_workflow_harness_gap' -Profile 'v2_hypium_image_harness_gap'
          Set-HypiumSemanticQualification -Record $Record -Qualification 'unverified'
          Add-HypiumGovernanceFinding -State $State -Record $Record -Category 'image_workflow_harness_gap' -Status 'blocked' -Severity 'P0'
        } elseif (Test-HypiumImageTraceDnsOnly -ImageTrace $imageTrace) {
          # The route, V2 transport and source-derived headers are all proven
          # by the fresh device delta. No image asset ever received an HTTP
          # response, so this must remain an external-network boundary rather
          # than a fabricated BookInfo/Content compatibility result.
          Set-HypiumWorkflow -State $State -Record $Record -Name 'content' -Status 'blocked' -Outcome 'image_asset_transport_network_dns'
          Set-HypiumSource -State $State -Record $Record -Status 'blocked' -Outcome 'image_asset_transport_network_dns' -Profile 'v2_hypium_image_asset_network_unconfirmed'
          Set-HypiumSemanticQualification -Record $Record -Qualification 'endpoint_unconfirmed'
          Add-HypiumGovernanceFinding -State $State -Record $Record -Category 'image_asset_transport_network_dns' -Status 'blocked' -Severity 'P1'
        } else {
          Set-HypiumWorkflow -State $State -Record $Record -Name 'content' -Status 'blocked' -Outcome 'image_reader_trace_captured_content_unverified'
          Set-HypiumSource -State $State -Record $Record -Status 'blocked' -Outcome 'image_workflow_reference_pending' -Profile 'v2_hypium_image_reference_pending'
          Set-HypiumSemanticQualification -Record $Record -Qualification 'unverified'
          Add-HypiumGovernanceFinding -State $State -Record $Record -Category 'image_workflow_reference_pending' -Status 'blocked' -Severity 'P0'
        }
      } elseif (Test-HypiumSafeReadWorkflowResults -Attempt $attempt) {
        foreach ($name in @('bookInfo', 'toc', 'content')) {
          Set-HypiumWorkflow -State $State -Record $Record -Name $name -Status 'passed' -Outcome 'safe_read_path_verified'
        }
        $readQualification = Get-HypiumSafeReadSemanticQualification -Record $Record -Attempt $attempt
        Set-HypiumSemanticQualification -Record $Record -Qualification ([string]$readQualification.qualification)
        if ([string]$readQualification.qualification -eq 'semantic_match') {
          Set-HypiumSource -State $State -Record $Record -Status 'passed' -Outcome 'safe_read_path_verified' -Profile 'safe_read_path_v2_hypium_verified'
          Resolve-HypiumGovernanceFinding -State $State -Record $Record
        } elseif ([string]$readQualification.qualification -eq 'semantic_mismatch') {
          $category = 'semantic_mismatch_' + [string]$readQualification.category
          Set-HypiumSource -State $State -Record $Record -Status 'failed' -Outcome $category -Profile 'v2_reference_semantic_mismatch'
          Add-HypiumGovernanceFinding -State $State -Record $Record -Category $category -Severity 'P1'
        } else {
          # Execution alone is not semantic compatibility. A readable V2
          # result without a same-input Legado witness must remain blocked;
          # otherwise the source-level passed state would contradict the
          # semanticQualification and allow an unverified source to proceed.
          Set-HypiumSource -State $State -Record $Record -Status 'blocked' -Outcome 'safe_read_path_verified_content_parity_unconfirmed' -Profile 'safe_read_path_v2_hypium_content_parity_pending'
          Add-HypiumGovernanceFinding -State $State -Record $Record -Category ([string]$readQualification.category) -Status 'blocked' -Severity 'P1'
        }
      } else {
        $bookInfoResult = Get-HypiumWorkflowResult -Attempt $attempt -Name 'book_info'
        $tocResult = Get-HypiumWorkflowResult -Attempt $attempt -Name 'toc'
        $contentResult = Get-HypiumWorkflowResult -Attempt $attempt -Name 'content'
        $bookInfoTrace = Get-HypiumDetailTrace -Attempt $attempt -Workflow 'book_info'
        $bookInfoResolution = Resolve-HypiumBookInfoPartialOutcome -Record $Record -Attempt $attempt -BookInfoResult $bookInfoResult
        if ($tocResult -eq 'not_started_book_info_terminal') {
          $bookInfoResolution = Resolve-HypiumBookInfoTerminalOutcome -Record $Record -Attempt $attempt -BookInfoResult $bookInfoResult
          Set-HypiumWorkflow -State $State -Record $Record -Name 'bookInfo' -Status $bookInfoResolution.status -Outcome $bookInfoResolution.outcome
          Set-HypiumWorkflow -State $State -Record $Record -Name 'toc' -Status 'blocked' -Outcome 'toc_not_started_book_info_terminal'
          Set-HypiumWorkflow -State $State -Record $Record -Name 'content' -Status 'blocked' -Outcome 'content_not_executed_book_info_terminal'
          Set-HypiumSource -State $State -Record $Record -Status 'blocked' -Outcome $bookInfoResolution.outcome -Profile 'v2_hypium_safe_read_partial'
          Add-HypiumGovernanceFinding -State $State -Record $Record -Category $bookInfoResolution.category -Status $bookInfoResolution.status -Severity 'P1'
        } else {
          $tocResolution = Resolve-HypiumTocPartialOutcome -Record $Record -Attempt $attempt -TocResult $tocResult
          Set-HypiumWorkflow -State $State -Record $Record -Name 'bookInfo' -Status $bookInfoResolution.status -Outcome $bookInfoResolution.outcome
          Set-HypiumWorkflow -State $State -Record $Record -Name 'toc' -Status $tocResolution.status -Outcome $tocResolution.outcome
          Set-HypiumWorkflow -State $State -Record $Record -Name 'content' -Status $(if ($contentResult -eq 'not_executed_no_toc') { 'policy_blocked' } else { 'failed' }) -Outcome $(if ($contentResult -eq 'not_executed_no_toc') { 'safe_read_path_content_not_executed_no_toc' } else { 'safe_read_path_incomplete' })
          $primaryResolution = if ($bookInfoResolution.status -eq 'blocked') { $bookInfoResolution } else { $tocResolution }
          Set-HypiumSource -State $State -Record $Record -Status $primaryResolution.status -Outcome $primaryResolution.outcome -Profile 'v2_hypium_safe_read_partial'
          Set-HypiumSemanticQualification -Record $Record -Qualification 'endpoint_unconfirmed'
          Add-HypiumGovernanceFinding -State $State -Record $Record -Category $primaryResolution.category -Status $primaryResolution.status -Severity 'P1'
        }
      }
    } else {
      if ($safeReadPath -and -not $fullWorkflow) { Set-HypiumNonSearchPolicy -State $State -Record $Record }
      if ($qualification -eq 'search_semantic_match') {
        $verifiedProfile = if ($fullWorkflow) { 'full_workflow_v2_hypium_verified' } else { 'safe_search_only_v2_hypium_verified' }
        Set-HypiumSource -State $State -Record $Record -Status 'passed' -Outcome $outcome -Profile $verifiedProfile
        Resolve-HypiumGovernanceFinding -State $State -Record $Record
      } else {
        Set-HypiumSource -State $State -Record $Record -Status 'blocked' -Outcome 'search_reference_pending' -Profile 'v2_search_reference_pending'
        Add-HypiumGovernanceFinding -State $State -Record $Record -Category 'search_reference_pending' -Status 'blocked' -Severity 'P1'
      }
    }
  } elseif ($safeReadPath -and $attempt.runnerStatus -ne 'passed' -and $attempt.driverClosed -and $null -ne $attempt.trace -and
    [string]$attempt.trace.workflow -eq 'search') {
    # A driver can reach and parse the search result, then fail while collecting
    # downstream UI cleanup. Consume complete read traces first; a parent
    # process failure must not erase independently persisted BookInfo/Toc/
    # Content results or their digests.
    Set-HypiumWorkflow -State $State -Record $Record -Name 'search' -Status 'passed' -Outcome 'search_verified_read_harness_failed' -Digest ([string]$attempt.trace.outputSummarySha256)
    $capturedReadAssessment = Resolve-HypiumCapturedReadWorkflows -State $State -Record $Record -Attempt $attempt
    if ([bool]$capturedReadAssessment.allPassed) {
      Set-HypiumSource -State $State -Record $Record -Status 'blocked' -Outcome 'safe_read_path_reference_pending' -Profile 'v2_hypium_safe_read_execution_verified'
      Set-HypiumSemanticQualification -Record $Record -Qualification 'execution_verified_no_reference'
      Add-HypiumGovernanceFinding -State $State -Record $Record -Category 'safe_read_path_reference_pending' -Status 'blocked' -Severity 'P1'
    } else {
      $capturedStatus = if ([int]$capturedReadAssessment.failedCount -gt 0) { 'failed' } else { 'blocked' }
      $capturedOutcome = if ($capturedStatus -eq 'failed') { 'safe_read_path_harness_incomplete' } else { 'safe_read_path_external_unconfirmed' }
      Set-HypiumSource -State $State -Record $Record -Status $capturedStatus -Outcome $capturedOutcome -Profile 'v2_hypium_safe_read_harness_failure'
      Set-HypiumSemanticQualification -Record $Record -Qualification 'harness_or_engine_failure'
      Add-HypiumGovernanceFinding -State $State -Record $Record -Category $capturedOutcome -Status $capturedStatus -Severity 'P1'
    }
  } elseif ($null -ne $semanticDifference) {
    $category = 'semantic_mismatch_' + [string]$semanticDifference.category
    Set-HypiumWorkflow -State $State -Record $Record -Name 'search' -Status 'failed' -Outcome $category
    Set-HypiumSource -State $State -Record $Record -Status 'failed' -Outcome $category -Profile 'v2_reference_semantic_mismatch'
    Set-HypiumSemanticQualification -Record $Record -Qualification 'semantic_mismatch'
    Add-HypiumGovernanceFinding -State $State -Record $Record -Category $category -Severity 'P1'
  } elseif (Test-HypiumExpectedExternal -Record $Record -Attempt $attempt) {
    Set-HypiumWorkflow -State $State -Record $Record -Name 'search' -Status 'expected_external' -Outcome 'original_legado_empty_v2_endpoint_failure'
    Set-HypiumSource -State $State -Record $Record -Status 'expected_external' -Outcome 'original_legado_empty_v2_endpoint_failure' -Profile 'external_confirmation'
    Set-HypiumSemanticQualification -Record $Record -Qualification 'external_confirmed'
    Resolve-HypiumGovernanceFinding -State $State -Record $Record -ResolutionSummary 'v2_hypium_expected_external_confirmed'
  } elseif ($attempt.errorCategory -eq 'v2_full_cutover_blocked') {
    $category = 'v2_full_cutover_blocked'
    Set-HypiumWorkflow -State $State -Record $Record -Name 'search' -Status 'blocked' -Outcome $category
    Set-HypiumSource -State $State -Record $Record -Status 'blocked' -Outcome $category -Profile 'v2_structured_rejection'
    Set-HypiumSemanticQualification -Record $Record -Qualification 'engine_rejected'
    Add-HypiumGovernanceFinding -State $State -Record $Record -Category $category -Status 'blocked' -Severity 'P1'
  } elseif ($null -ne $attempt.trace -and [string]$attempt.trace.errorCode -eq 'unsupported_api') {
    $category = 'unsupported_api'
    Set-HypiumWorkflow -State $State -Record $Record -Name 'search' -Status 'blocked' -Outcome $category
    Set-HypiumSource -State $State -Record $Record -Status 'blocked' -Outcome $category -Profile 'v2_unsupported_api'
    Set-HypiumSemanticQualification -Record $Record -Qualification 'engine_rejected'
    Add-HypiumGovernanceFinding -State $State -Record $Record -Category $category -Status 'blocked' -Severity 'P1'
  } elseif ($null -ne $attempt.trace -and (Get-HypiumTextProperty -Object $attempt.trace -Name 'webViewLifecycle') -match 'WEBVIEW_ERROR;.*errorCode=-102$') {
    # ArkWeb reports Chromium's connection-refused code after target navigation
    # has started. This is endpoint evidence, not a missing controller or URL
    # matching failure; require the original-Legado comparison before promotion.
    $category = 'arkweb_endpoint_unconfirmed'
    Set-HypiumWorkflow -State $State -Record $Record -Name 'search' -Status 'blocked' -Outcome $category
    Set-HypiumSource -State $State -Record $Record -Status 'blocked' -Outcome $category -Profile 'arkweb_external_confirmation_required'
    Set-HypiumSemanticQualification -Record $Record -Qualification 'endpoint_unconfirmed'
    Add-HypiumGovernanceFinding -State $State -Record $Record -Category $category -Status 'blocked' -Severity 'P2'
  } elseif ($null -ne $attempt.trace -and [string]$attempt.trace.errorCode -eq 'web_view') {
    # HTTP 0 with an ArkWeb trace proves the user path reached V2, but not that
    # target navigation or rule execution completed. Keep it separate from a
    # Driver failure so related sources share one ArkWeb root-cause queue.
    $category = 'arkweb_execution_unconfirmed'
    Set-HypiumWorkflow -State $State -Record $Record -Name 'search' -Status 'failed' -Outcome $category
    Set-HypiumSource -State $State -Record $Record -Status 'failed' -Outcome $category -Profile 'v2_arkweb_execution_unconfirmed'
    Set-HypiumSemanticQualification -Record $Record -Qualification 'arkweb_unconfirmed'
    Add-HypiumGovernanceFinding -State $State -Record $Record -Category $category -Severity 'P0'
  } elseif ($null -ne $attempt.trace -and ([string]$attempt.trace.errorCode -eq 'network' -or [int]$attempt.trace.statusCode -ge 400)) {
    $category = 'external_network_unconfirmed'
    Set-HypiumWorkflow -State $State -Record $Record -Name 'search' -Status 'blocked' -Outcome $category
    Set-HypiumSource -State $State -Record $Record -Status 'blocked' -Outcome $category -Profile 'external_confirmation_required'
    Set-HypiumSemanticQualification -Record $Record -Qualification 'endpoint_unconfirmed'
    Add-HypiumGovernanceFinding -State $State -Record $Record -Category $category -Status 'blocked' -Severity 'P2'
  } else {
    $category = if ($attempt.errorCategory -eq 'app_exited' -or $attempt.outcome -eq 'app_exited') { 'app_exited' } elseif ($attempt.errorCategory -eq 'runner_timeout' -or $attempt.outcome -eq 'runner_timeout') { 'runner_timeout' } elseif ($attempt.outcome -eq 'execution_failure') { 'execution_failure' } elseif ($attempt.outcome -eq 'ui_timeout') { 'ui_timeout' } else { 'ui_trace_mismatch' }
    Set-HypiumWorkflow -State $State -Record $Record -Name 'search' -Status 'failed' -Outcome $category
    if ($safeReadPath) {
      # A driver exception can occur after the read workflows are marked
      # running but before it writes workflow_results. Never leave those
      # states hanging: the evidence has completed and is reproducible.
      foreach ($name in @('bookInfo', 'toc', 'content')) {
        $workflow = $Record.workflows.PSObject.Properties[$name].Value
        if ([string]$workflow.status -eq 'running') {
          Set-HypiumWorkflow -State $State -Record $Record -Name $name -Status 'failed' -Outcome 'safe_read_path_harness_incomplete'
        }
      }
    }
    Set-HypiumSource -State $State -Record $Record -Status 'failed' -Outcome $category -Profile 'v2_hypium_execution_failed'
    Set-HypiumSemanticQualification -Record $Record -Qualification 'harness_or_engine_failure'
    $severity = if ($category -eq 'app_exited') { 'P0' } else { 'P1' }
    Add-HypiumGovernanceFinding -State $State -Record $Record -Category $category -Severity $severity
  }
  if ($safeReadPath) {
    # Every terminal source outcome must settle the workflows that were marked
    # running before navigation. This is an evidence invariant, not a retry.
    foreach ($name in @('bookInfo', 'toc', 'content')) {
      $workflow = $Record.workflows.PSObject.Properties[$name].Value
      if ([string]$workflow.status -eq 'running') {
        Set-HypiumWorkflow -State $State -Record $Record -Name $name -Status 'blocked' -Outcome 'safe_read_path_not_executed_after_search_terminal'
      }
    }
  }
  if ($fullWorkflow) {
    # A source type without a concrete UI consumer must never leave a
    # workflow in planned/running after Search settles. Publish a structured
    # rejection so the source remains auditable and cannot be mistaken for a
    # successful full-workflow verification.
    foreach ($name in @('search', 'explore', 'bookInfo', 'toc', 'content', 'file', 'review')) {
      $workflow = $Record.workflows.PSObject.Properties[$name].Value
      if ([string]$workflow.status -in @('planned', 'running')) {
        $terminalStatus = if ($name -in @('bookInfo', 'toc', 'content')) { 'unsupported_api' } else { 'blocked' }
        $terminalOutcome = if ($name -in @('bookInfo', 'toc', 'content')) {
          'full_workflow_driver_not_available_for_source_type'
        } else {
          'full_workflow_terminal_unsettled'
        }
        Set-HypiumWorkflow -State $State -Record $Record -Name $name -Status $terminalStatus -Outcome $terminalOutcome
      }
    }
  }
  Sync-HypiumSourceAttempt -State $State -Record $Record
  $digest = Write-HypiumSourceEvidence -Record $Record -Attempt $attempt
  Set-HypiumProperty -Object $Record -Name 'lastEvidenceDigest' -Value $digest
  Write-LegadoStateCheckpoint -Path $StatePath -State $State
    [void]$script:ResultSummary.Add([pscustomobject][ordered]@{ sourceId = [string]$Record.sourceId; ordinal = [int]$Record.ordinal; status = [string]$Record.status; outcome = [string]$Record.lastOutcome })
  } catch {
    # A malformed child result or an unexpected projection error must be
    # contained to this source. Settle every still-planned workflow, persist a
    # closed evidence matrix, and continue the batch instead of leaving the
    # source running or aborting the remaining ordinals.
    $errorMessage = [string]$_.Exception.Message
    $errorDigest = if ($errorMessage.Length -gt 0) { Get-LegadoSha256ForText -Value $errorMessage } else { '' }
    foreach ($name in @('search', 'explore', 'bookInfo', 'toc', 'content', 'file', 'review')) {
      $workflowProperty = $Record.workflows.PSObject.Properties[$name]
      if ($null -eq $workflowProperty -or $null -eq $workflowProperty.Value) { continue }
      $workflowStatus = Get-HypiumTextProperty -Object $workflowProperty.Value -Name 'status'
      if ($workflowStatus -in @('planned', 'running')) {
        Set-HypiumWorkflow -State $State -Record $Record -Name $name -Status 'failed' -Outcome 'record_harness_exception'
      }
    }
    Set-HypiumSource -State $State -Record $Record -Status 'failed' -Outcome 'record_harness_exception' -Profile 'v2_hypium_record_exception'
    Set-HypiumSemanticQualification -Record $Record -Qualification 'harness_or_engine_failure'
    Add-HypiumGovernanceFinding -State $State -Record $Record -Category 'record_harness_exception' -Status 'failed' -Severity 'P1'
    $failureAttempt = [pscustomobject][ordered]@{
      outcome = 'record_harness_exception'
      runnerStatus = 'failed'
      errorDigest = $errorDigest
      errorCategory = 'record_exception'
      evidencePath = ''
      trace = $null
      detailTraceRecords = @()
      workflowResults = $null
      driverClosed = $false
      processClassification = 'record_exception'
    }
    try {
      Sync-HypiumSourceAttempt -State $State -Record $Record
      $digest = Write-HypiumSourceEvidence -Record $Record -Attempt $failureAttempt
      Set-HypiumProperty -Object $Record -Name 'lastEvidenceDigest' -Value $digest
      Write-LegadoStateCheckpoint -Path $StatePath -State $State
    } catch {
      # Preserve a minimal, run-scoped source record if the full projection
      # cannot be serialized. A second filesystem failure remains explicit in
      # activity and must not abort the following source.
      $fallbackMessage = [string]$_.Exception.Message
      $fallbackDigest = if ($fallbackMessage.Length -gt 0) { Get-LegadoSha256ForText -Value $fallbackMessage } else { '' }
      $fallbackEvidence = $null
      try {
        $fallbackEvidence = Write-HypiumSourceFallbackEvidence -Record $Record -ErrorDigest $fallbackDigest
        Set-HypiumProperty -Object $Record -Name 'lastEvidenceDigest' -Value ([string]$fallbackEvidence.digest)
        Write-LegadoStateCheckpoint -Path $StatePath -State $State
      } catch {
        $fallbackWriteDigest = Get-LegadoSha256ForText -Value ([string]$_.Exception.Message)
        try {
          Write-HypiumRunActivity -Status 'running' -Phase 'source_evidence_write_failed' -Ordinal ([int]$Record.ordinal) -SourceId ([string]$Record.sourceId) -Outcome 'source_evidence_write_failed' -ErrorDigest $fallbackWriteDigest
        } catch { }
      }
      if ($null -ne $fallbackEvidence) {
        try {
          Write-HypiumRunActivity -Status 'running' -Phase 'source_evidence_fallback_written' -Ordinal ([int]$Record.ordinal) -SourceId ([string]$Record.sourceId) -Outcome 'source_evidence_fallback_written' -ErrorDigest $fallbackDigest -EvidencePath ([string]$fallbackEvidence.relativePath)
        } catch { }
      }
    }
    [void]$script:ResultSummary.Add([pscustomobject][ordered]@{
      sourceId = [string]$Record.sourceId
      ordinal = [int]$Record.ordinal
      status = [string]$Record.status
      outcome = [string]$Record.lastOutcome
    })
  }
}

try {
  $SourcePackagePath = Resolve-HypiumSourcePackagePath -RequestedPath $SourcePackagePath
  Clear-HypiumRunActivityArtifacts
  Write-HypiumRunActivity -Status 'starting' -Phase 'preflight'
  foreach ($requiredPath in @($HdcPath, $PythonPath, $driverPath, $SourcePackagePath, $LegadoRepositoryPath)) { if (-not (Test-Path -LiteralPath $requiredPath)) { throw "REQUIRED_PATH_MISSING:$requiredPath" } }
  $Device = Resolve-HypiumDevice
  $head = (& git -C $LegadoRepositoryPath rev-parse HEAD).Trim()
  $state = Initialize-LegadoFullSourceState -SourcePackagePath $SourcePackagePath -StatePath $StatePath -LegacyGovernancePath $LegacyGovernancePath -ExpectedPackageSha256 $script:ExpectedSourcePackageSha256 -ExpectedSourceCount $script:ExpectedSourceCount -LegadoCommit $head -ExpectedLegadoCommit $script:ExpectedLegadoCommit
  $packageText = [System.Text.UTF8Encoding]::new($false, $true).GetString([System.IO.File]::ReadAllBytes($SourcePackagePath))
  $sources = @(ConvertFrom-LegadoJsonArray -Json $packageText -Label 'pinned source package')
  $rawDocuments = @(Get-LegadoRawSourceDocuments -Json $packageText -Label 'pinned source package')
  $statuses = if ($RevalidateTerminalSources) { @('planned', 'failed', 'passed', 'expected_external', 'needs_interaction', 'policy_blocked', 'blocked') } else { @('planned') }
  $records = @($state.sources | Where-Object { [string]$_.status -in $statuses } | Sort-Object { [int]$_.ordinal })
  if ($OnlyOrdinal -ge 0) { $records = @($records | Where-Object { [int]$_.ordinal -eq $OnlyOrdinal }) }
  $records = @($records | Select-Object -First $MaxSources)
  Write-HypiumRunActivity -Status 'running' -Phase 'records_selected' -ScheduledSources $records.Count -CompletedSources $script:ResultSummary.Count
  foreach ($record in $records) {
    $ordinal = [int]$record.ordinal
    $rawDocument = if ($ordinal -ge 0 -and $ordinal -lt $rawDocuments.Count) { [string]$rawDocuments[$ordinal] } else { '' }
    $rawHash = if ($rawDocument.Length -gt 0) { Get-LegadoSha256ForText -Value $rawDocument } else { '' }
    if ($ordinal -lt 0 -or $ordinal -ge $sources.Count -or $rawHash -ne [string]$record.sourceId) { throw 'RAW_SOURCE_IDENTITY_MISMATCH' }
    Write-HypiumRunActivity -Status 'running' -Phase 'source_dispatched' -Ordinal $ordinal -SourceId ([string]$record.sourceId) -ScheduledSources $records.Count -CompletedSources $script:ResultSummary.Count
    Invoke-HypiumRecord -State $state -Record $record -Source $sources[$ordinal] -RawDocument $rawDocument
    Write-HypiumRunActivity -Status 'running' -Phase 'source_settled' -Ordinal $ordinal -SourceId ([string]$record.sourceId) -ScheduledSources $records.Count -CompletedSources $script:ResultSummary.Count -Outcome ([string]$record.lastOutcome)
  }
  Write-LegadoStateCheckpoint -Path $StatePath -State $state
  Write-HypiumRunActivity -Status 'running' -Phase 'document_refresh' -ScheduledSources $records.Count -CompletedSources $script:ResultSummary.Count
  Refresh-HypiumGovernanceDocuments
  Write-HypiumRunActivity -Status 'passed' -Phase 'completed' -ScheduledSources $records.Count -CompletedSources $script:ResultSummary.Count
  [pscustomobject][ordered]@{ status = 'passed'; runId = $script:RunId; sources = $script:ResultSummary.ToArray(); statePath = $StatePath } | ConvertTo-Json -Depth 10
} catch {
  $failureDigest = Get-LegadoSha256ForText -Value ([string]$_.Exception.Message)
  try { Write-HypiumRunActivity -Status 'failed' -Phase 'failed' -ScheduledSources $script:ResultSummary.Count -CompletedSources $script:ResultSummary.Count -ErrorDigest $failureDigest } catch { }
  Write-Error ("HYPIUM_FULL_RUNNER_FAILURE:{0}" -f $_.Exception.Message)
  [pscustomobject][ordered]@{ status = 'failed'; runId = $script:RunId; errorDigest = $failureDigest; statePath = $StatePath } | ConvertTo-Json -Depth 10
  exit 1
}
