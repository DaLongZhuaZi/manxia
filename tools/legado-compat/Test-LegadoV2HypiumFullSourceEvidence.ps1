[CmdletBinding()]
param(
  [string]$EvidenceDirectory = '',
  [string]$StatePath = '',
  [int]$ExpectedSourceCount = 458,
  [string]$ExpectedSourcePackageSha256 = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67',
  [string]$ExpectedLegadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd',
  [string]$ResultPath = '',
  [string]$OverlayRoot = '',
  [string]$EffectiveEvidenceDirectory = '',
  [switch]$DisableEvidenceOverlay,
  [switch]$RequireCompleted
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$evidencePathsModulePath = Join-Path $PSScriptRoot 'LegadoHypiumEvidencePaths.psm1'
if (-not (Test-Path -LiteralPath $evidencePathsModulePath)) {
  throw 'HYPIUM_EVIDENCE_PATHS_MODULE_MISSING'
}
Import-Module -Name $evidencePathsModulePath -Force -ErrorAction Stop

if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
  $EvidenceDirectory = Join-Path $PSScriptRoot 'evidence\full-source-v2-hypium-device'
}
if ([string]::IsNullOrWhiteSpace($StatePath)) {
  $StatePath = Join-Path $PSScriptRoot 'state\full-source-validation-state.json'
}
if ([string]::IsNullOrWhiteSpace($OverlayRoot)) {
  $OverlayRoot = Split-Path -Parent $EvidenceDirectory
}
if ([string]::IsNullOrWhiteSpace($EffectiveEvidenceDirectory)) {
  $EffectiveEvidenceDirectory = Join-Path $OverlayRoot 'effective-full-source-v2-hypium-device'
}
if (-not $DisableEvidenceOverlay) {
  $EffectiveEvidenceDirectory = Assert-LegadoHypiumEffectiveEvidenceDirectory `
    -EvidenceRoot $OverlayRoot `
    -BaselineEvidenceDirectory $EvidenceDirectory `
    -EffectiveEvidenceDirectory $EffectiveEvidenceDirectory
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  if ($DisableEvidenceOverlay) {
    $ResultPath = Join-Path $EvidenceDirectory 'full-source-evidence-contract.json'
  } else {
    $ResultPath = Join-Path $EffectiveEvidenceDirectory 'full-source-evidence-contract.json'
  }
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$allowedStatuses = @(
  'planned', 'running', 'passed', 'failed', 'blocked', 'unsupported_api',
  'needs_interaction', 'policy_blocked', 'expected_external'
)
$workflowNames = @('search', 'explore', 'bookInfo', 'toc', 'content', 'file', 'review')

function Read-Utf8Json {
  param([Parameter(Mandatory = $true)][string]$Path)
  return [System.IO.File]::ReadAllText($Path, $strictUtf8) | ConvertFrom-Json
}

function Add-Failure {
  param(
    [System.Collections.Generic.List[object]]$Failures,
    [string]$Code,
    [string]$Message,
    [string]$File = '',
    [int]$Ordinal = -1
  )
  [void]$Failures.Add([pscustomobject][ordered]@{
    code = $Code
    message = $Message
    file = $File
    ordinal = $Ordinal
  })
}

function Get-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Fallback = $null)
  if ($null -eq $Object) { return $Fallback }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { return $Fallback }
  return $property.Value
}

function Get-EvidenceTimestamp {
  param(
    [object]$Evidence,
    [object]$Activity,
    [System.IO.FileInfo]$File
  )
  $value = [string](Get-PropertyValue -Object $Evidence -Name 'generatedAt' -Fallback '')
  if ([string]::IsNullOrWhiteSpace($value)) {
    $value = [string](Get-PropertyValue -Object $Activity -Name 'generatedAt' -Fallback '')
  }
  if (-not [string]::IsNullOrWhiteSpace($value)) {
    try { return [System.DateTimeOffset]::Parse($value) } catch { }
  }
  return [System.DateTimeOffset]$File.LastWriteTimeUtc
}

function Write-Utf8JsonAtomic {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][object]$Value,
    [int]$Depth = 32
  )
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) {
    [void][System.IO.Directory]::CreateDirectory($directory)
  }
  $temporaryPath = $Path + '.tmp'
  $json = $Value | ConvertTo-Json -Depth $Depth
  [System.IO.File]::WriteAllText($temporaryPath, $json, [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

$failures = [System.Collections.Generic.List[object]]::new()
$files = @()
if (Test-Path -LiteralPath $EvidenceDirectory) {
  $files = @(Get-ChildItem -LiteralPath $EvidenceDirectory -File -Filter 'source-*.json')
} else {
  Add-Failure -Failures $failures -Code 'EVIDENCE_DIRECTORY_MISSING' -Message $EvidenceDirectory
}

$baselineActivity = $null
$baselineActivityPath = Join-Path $EvidenceDirectory 'run-activity.json'
if (Test-Path -LiteralPath $baselineActivityPath) {
  try { $baselineActivity = Read-Utf8Json -Path $baselineActivityPath } catch { }
}

$baselineRecords = [System.Collections.Generic.List[object]]::new()
foreach ($file in $files) {
  try {
    $evidence = Read-Utf8Json -Path $file.FullName
    $baselineRecords.Add([pscustomobject][ordered]@{
      file = $file.Name
      path = $file.FullName
      evidence = $evidence
      sourceKind = 'baseline'
      evidenceDirectory = $EvidenceDirectory
      generatedAt = (Get-EvidenceTimestamp -Evidence $evidence -Activity $baselineActivity -File $file)
    })
  } catch {
    Add-Failure -Failures $failures -Code 'EVIDENCE_JSON_INVALID' -Message $_.Exception.Message -File $file.Name
  }
}

$overlayCandidates = [System.Collections.Generic.List[object]]::new()
$overlayDirectories = [System.Collections.Generic.List[object]]::new()
if (-not $DisableEvidenceOverlay -and (Test-Path -LiteralPath $OverlayRoot)) {
  $effectiveFullPath = [System.IO.Path]::GetFullPath($EffectiveEvidenceDirectory)
  foreach ($directory in @(Get-ChildItem -LiteralPath $OverlayRoot -Directory)) {
    $directoryFullPath = [System.IO.Path]::GetFullPath($directory.FullName)
    if ($directoryFullPath -eq [System.IO.Path]::GetFullPath($EvidenceDirectory) -or
        $directoryFullPath -eq $effectiveFullPath) {
      continue
    }
    $activityPath = Join-Path $directory.FullName 'run-activity.json'
    if (-not (Test-Path -LiteralPath $activityPath)) { continue }
    try { $activity = Read-Utf8Json -Path $activityPath } catch { continue }
    $profile = [string](Get-PropertyValue -Object $activity -Name 'executionProfile' -Fallback '')
    $activityStatus = [string](Get-PropertyValue -Object $activity -Name 'status' -Fallback '')
    $activityPhase = [string](Get-PropertyValue -Object $activity -Name 'phase' -Fallback '')
    if ($profile -ne 'full_workflow' -or $activityStatus -ne 'passed' -or $activityPhase -ne 'completed') {
      continue
    }
    $sourceFiles = @(Get-ChildItem -LiteralPath $directory.FullName -File -Filter 'source-*.json')
    if ($sourceFiles.Count -eq 0) { continue }
    $overlayDirectories.Add([pscustomobject][ordered]@{
      directory = $directory.Name
      path = $directory.FullName
      runId = [string](Get-PropertyValue -Object $activity -Name 'runId' -Fallback '')
      generatedAt = [string](Get-PropertyValue -Object $activity -Name 'generatedAt' -Fallback '')
      sourceCount = $sourceFiles.Count
    })
    foreach ($sourceFile in $sourceFiles) {
      try {
        $evidence = Read-Utf8Json -Path $sourceFile.FullName
        $packageHash = [string](Get-PropertyValue -Object $evidence -Name 'sourcePackageSha256' -Fallback '')
        $legadoCommit = [string](Get-PropertyValue -Object $evidence -Name 'legadoCommit' -Fallback '')
        $runId = [string](Get-PropertyValue -Object $evidence -Name 'runId' -Fallback '')
        $ordinal = [int](Get-PropertyValue -Object $evidence -Name 'ordinal' -Fallback -1)
        $sourceId = [string](Get-PropertyValue -Object $evidence -Name 'sourceId' -Fallback '')
        if ($packageHash -ne $ExpectedSourcePackageSha256 -or $legadoCommit -ne $ExpectedLegadoCommit) {
          Add-Failure -Failures $failures -Code 'OVERLAY_BASELINE_MISMATCH' -Message $directory.Name -File $sourceFile.Name -Ordinal $ordinal
          continue
        }
        if (-not [string]::IsNullOrWhiteSpace([string](Get-PropertyValue -Object $activity -Name 'runId' -Fallback '')) -and $runId -ne [string](Get-PropertyValue -Object $activity -Name 'runId' -Fallback '')) {
          Add-Failure -Failures $failures -Code 'OVERLAY_RUN_ID_MISMATCH' -Message $directory.Name -File $sourceFile.Name -Ordinal $ordinal
          continue
        }
        $overlayCandidates.Add([pscustomobject][ordered]@{
          file = $sourceFile.Name
          path = $sourceFile.FullName
          evidence = $evidence
          sourceKind = 'overlay'
          evidenceDirectory = $directory.FullName
          overlayDirectory = $directory.Name
          generatedAt = (Get-EvidenceTimestamp -Evidence $evidence -Activity $activity -File $sourceFile)
        })
      } catch {
        Add-Failure -Failures $failures -Code 'OVERLAY_EVIDENCE_JSON_INVALID' -Message $_.Exception.Message -File $sourceFile.Name
      }
    }
  }
}

$baselineByOrdinal = @{}
foreach ($record in $baselineRecords) {
  $ordinal = [int](Get-PropertyValue -Object $record.evidence -Name 'ordinal' -Fallback -1)
  if ($baselineByOrdinal.ContainsKey([string]$ordinal)) {
    Add-Failure -Failures $failures -Code 'BASELINE_DUPLICATE_ORDINAL' -Message ([string]$ordinal) -File $record.file -Ordinal $ordinal
  } else {
    $baselineByOrdinal[[string]$ordinal] = $record
  }
}

$selectedByOrdinal = @{}
foreach ($record in $baselineRecords) {
  $ordinal = [int](Get-PropertyValue -Object $record.evidence -Name 'ordinal' -Fallback -1)
  $selectedByOrdinal[[string]$ordinal] = $record
}
foreach ($candidate in $overlayCandidates) {
  $ordinal = [int](Get-PropertyValue -Object $candidate.evidence -Name 'ordinal' -Fallback -1)
  $sourceId = [string](Get-PropertyValue -Object $candidate.evidence -Name 'sourceId' -Fallback '')
  $baseline = $baselineByOrdinal[[string]$ordinal]
  if ($null -eq $baseline) {
    Add-Failure -Failures $failures -Code 'OVERLAY_ORDINAL_NOT_IN_BASELINE' -Message $candidate.overlayDirectory -File $candidate.file -Ordinal $ordinal
    continue
  }
  $baselineSourceId = [string](Get-PropertyValue -Object $baseline.evidence -Name 'sourceId' -Fallback '')
  if ($sourceId -ne $baselineSourceId) {
    Add-Failure -Failures $failures -Code 'OVERLAY_SOURCE_ID_MISMATCH' -Message $candidate.overlayDirectory -File $candidate.file -Ordinal $ordinal
    continue
  }
  if ($candidate.generatedAt -le $baseline.generatedAt) {
    Add-Failure -Failures $failures -Code 'OVERLAY_NOT_NEWER_THAN_BASELINE' -Message $candidate.overlayDirectory -File $candidate.file -Ordinal $ordinal
    continue
  }
  $current = $selectedByOrdinal[[string]$ordinal]
  if ($current.sourceKind -eq 'baseline' -or
      $candidate.generatedAt -gt $current.generatedAt -or
      ($candidate.generatedAt -eq $current.generatedAt -and $candidate.path -gt $current.path)) {
    $selectedByOrdinal[[string]$ordinal] = $candidate
  }
}

$records = [System.Collections.Generic.List[object]]::new()
foreach ($ordinal in ($selectedByOrdinal.Keys | ForEach-Object { [int]$_ } | Sort-Object)) {
  [void]$records.Add($selectedByOrdinal[[string]$ordinal])
}

if ($records.Count -ne $ExpectedSourceCount) {
  Add-Failure -Failures $failures -Code 'SOURCE_EVIDENCE_COUNT_MISMATCH' -Message ("expected={0};actual={1}" -f $ExpectedSourceCount, $records.Count)
}

$effectiveMap = @($records | ForEach-Object {
  [pscustomobject][ordered]@{
    ordinal = [int](Get-PropertyValue -Object $_.evidence -Name 'ordinal' -Fallback -1)
    sourceId = [string](Get-PropertyValue -Object $_.evidence -Name 'sourceId' -Fallback '')
    sourceKind = $_.sourceKind
    evidenceFile = $_.file
    evidencePath = $_.path
    evidenceDirectory = $_.evidenceDirectory
    overlayDirectory = [string](Get-PropertyValue -Object $_ -Name 'overlayDirectory' -Fallback '')
    runId = [string](Get-PropertyValue -Object $_.evidence -Name 'runId' -Fallback '')
    generatedAt = $_.generatedAt.ToString('o')
  }
})
$overlayAppliedCount = @($effectiveMap | Where-Object { $_.sourceKind -eq 'overlay' }).Count

if (-not $DisableEvidenceOverlay) {
  foreach ($record in $records) {
    $sourceId = [string](Get-PropertyValue -Object $record.evidence -Name 'sourceId' -Fallback '')
    if (-not [string]::IsNullOrWhiteSpace($sourceId)) {
      $outputPath = Join-Path $EffectiveEvidenceDirectory ("source-{0}.json" -f $sourceId)
      Write-Utf8JsonAtomic -Path $outputPath -Value $record.evidence -Depth 32
    }
  }
  Write-Utf8JsonAtomic -Path (Join-Path $EffectiveEvidenceDirectory 'source-map.json') -Value ([pscustomobject][ordered]@{
    schemaVersion = 1
    generatedAt = [DateTime]::UtcNow.ToString('o')
    baselineDirectory = $EvidenceDirectory
    overlayRoot = $OverlayRoot
    expectedSourceCount = $ExpectedSourceCount
    effectiveSourceCount = $records.Count
    overlayAppliedCount = $overlayAppliedCount
    entries = $effectiveMap
  }) -Depth 32
}

$runIds = [System.Collections.Generic.HashSet[string]]::new()
$ordinals = [System.Collections.Generic.HashSet[int]]::new()
$sourceIds = [System.Collections.Generic.HashSet[string]]::new()
$statusCounts = @{}
$outcomeCounts = @{}
$workflowStatusCounts = @{}
$workflowAttemptCounts = @{}

foreach ($record in $records) {
  $evidence = $record.evidence
  $fileName = $record.file
  $ordinal = [int](Get-PropertyValue -Object $evidence -Name 'ordinal' -Fallback -1)
  $sourceId = [string](Get-PropertyValue -Object $evidence -Name 'sourceId' -Fallback '')
  $status = [string](Get-PropertyValue -Object $evidence -Name 'status' -Fallback '')
  $outcome = [string](Get-PropertyValue -Object $evidence -Name 'outcome' -Fallback '')
  $evidenceKind = [string](Get-PropertyValue -Object $evidence -Name 'evidenceKind' -Fallback 'full')
  $runId = [string](Get-PropertyValue -Object $evidence -Name 'runId' -Fallback '')
  $packageHash = [string](Get-PropertyValue -Object $evidence -Name 'sourcePackageSha256' -Fallback '')
  $legadoCommit = [string](Get-PropertyValue -Object $evidence -Name 'legadoCommit' -Fallback '')

  if ($evidenceKind -eq 'source_fallback') {
    Add-Failure -Failures $failures -Code 'SOURCE_EVIDENCE_FALLBACK' -Message 'full source evidence writer failed; fallback artifact requires remediation' -File $fileName -Ordinal $ordinal
  }

  if (-not $runIds.Add($runId)) {
    # A repeated run id is expected; this call only initializes the set.
  }
  if ($ordinal -lt 0 -or $ordinal -ge $ExpectedSourceCount) {
    Add-Failure -Failures $failures -Code 'ORDINAL_OUT_OF_RANGE' -Message ([string]$ordinal) -File $fileName -Ordinal $ordinal
  } elseif (-not $ordinals.Add($ordinal)) {
    Add-Failure -Failures $failures -Code 'DUPLICATE_ORDINAL' -Message ([string]$ordinal) -File $fileName -Ordinal $ordinal
  }
  if ([string]::IsNullOrWhiteSpace($sourceId)) {
    Add-Failure -Failures $failures -Code 'SOURCE_ID_MISSING' -Message 'sourceId is empty' -File $fileName -Ordinal $ordinal
  } elseif (-not $sourceIds.Add($sourceId)) {
    Add-Failure -Failures $failures -Code 'DUPLICATE_SOURCE_ID' -Message $sourceId -File $fileName -Ordinal $ordinal
  }
  if ($packageHash -ne $ExpectedSourcePackageSha256) {
    Add-Failure -Failures $failures -Code 'PACKAGE_HASH_MISMATCH' -Message $packageHash -File $fileName -Ordinal $ordinal
  }
  if ($legadoCommit -ne $ExpectedLegadoCommit) {
    Add-Failure -Failures $failures -Code 'LEGADO_COMMIT_MISMATCH' -Message $legadoCommit -File $fileName -Ordinal $ordinal
  }
  if ([string]::IsNullOrWhiteSpace($runId)) {
    Add-Failure -Failures $failures -Code 'RUN_ID_MISSING' -Message 'runId is empty' -File $fileName -Ordinal $ordinal
  }
  if ($allowedStatuses -notcontains $status) {
    Add-Failure -Failures $failures -Code 'SOURCE_STATUS_INVALID' -Message $status -File $fileName -Ordinal $ordinal
  }
  if ([string]::IsNullOrWhiteSpace($outcome)) {
    Add-Failure -Failures $failures -Code 'SOURCE_OUTCOME_MISSING' -Message 'outcome is empty' -File $fileName -Ordinal $ordinal
  }
  if (-not $statusCounts.ContainsKey($status)) { $statusCounts[$status] = 0 }
  $statusCounts[$status] = [int]$statusCounts[$status] + 1
  if (-not $outcomeCounts.ContainsKey($outcome)) { $outcomeCounts[$outcome] = 0 }
  $outcomeCounts[$outcome] = [int]$outcomeCounts[$outcome] + 1

  $matrix = Get-PropertyValue -Object $evidence -Name 'workflowStatusMatrix'
  $results = Get-PropertyValue -Object $evidence -Name 'workflowResults'
  $workflowEvidence = Get-PropertyValue -Object $evidence -Name 'workflowEvidence'
  $sourceAttempt = [int](Get-PropertyValue -Object $evidence -Name 'sourceAttempt' -Fallback 0)
  $sourceAttemptEvidence = Get-PropertyValue -Object $evidence -Name 'sourceAttemptEvidence'
  if ($null -eq $matrix) {
    Add-Failure -Failures $failures -Code 'WORKFLOW_MATRIX_MISSING' -Message 'workflowStatusMatrix is missing' -File $fileName -Ordinal $ordinal
    continue
  }
  if ($null -eq $results) {
    Add-Failure -Failures $failures -Code 'WORKFLOW_RESULTS_MISSING' -Message 'workflowResults is missing' -File $fileName -Ordinal $ordinal
  } else {
    $resultNames = @($results.PSObject.Properties.Name)
    if ($resultNames.Count -ne $workflowNames.Count -or @($workflowNames | Where-Object { $resultNames -notcontains $_ }).Count -gt 0) {
      Add-Failure -Failures $failures -Code 'WORKFLOW_RESULTS_NOT_CLOSED' -Message (($resultNames | Sort-Object) -join ',') -File $fileName -Ordinal $ordinal
    }
    foreach ($workflowName in $workflowNames) {
      $resultProperty = $results.PSObject.Properties[$workflowName]
      if ($null -eq $resultProperty -or [string]::IsNullOrWhiteSpace([string]$resultProperty.Value)) {
        Add-Failure -Failures $failures -Code 'WORKFLOW_RESULT_MISSING' -Message $workflowName -File $fileName -Ordinal $ordinal
      }
    }
  }
  if ($null -eq $workflowEvidence) {
    Add-Failure -Failures $failures -Code 'WORKFLOW_EVIDENCE_MISSING' -Message 'workflowEvidence is missing' -File $fileName -Ordinal $ordinal
  }
  if ($sourceAttempt -lt 0) {
    Add-Failure -Failures $failures -Code 'SOURCE_ATTEMPT_INVALID' -Message ([string]$sourceAttempt) -File $fileName -Ordinal $ordinal
  }
  $maximumWorkflowAttempt = 0
  if ($null -ne $matrix) {
    foreach ($matrixProperty in @($matrix.PSObject.Properties)) {
      $candidateAttempt = [int](Get-PropertyValue -Object $matrixProperty.Value -Name 'attempts' -Fallback 0)
      if ($candidateAttempt -gt $maximumWorkflowAttempt) { $maximumWorkflowAttempt = $candidateAttempt }
    }
  }
  if ($sourceAttempt -ne $maximumWorkflowAttempt) {
    Add-Failure -Failures $failures -Code 'SOURCE_ATTEMPT_NOT_EQUAL_WORKFLOW_MAX' -Message ("source={0};workflowMax={1}" -f $sourceAttempt, $maximumWorkflowAttempt) -File $fileName -Ordinal $ordinal
  }
  if ($null -eq $sourceAttemptEvidence) {
    Add-Failure -Failures $failures -Code 'SOURCE_ATTEMPT_EVIDENCE_MISSING' -Message 'sourceAttemptEvidence is missing' -File $fileName -Ordinal $ordinal
  } else {
    $boundSourceAttempt = [int](Get-PropertyValue -Object $sourceAttemptEvidence -Name 'sourceAttempt' -Fallback -1)
    if ($boundSourceAttempt -ne $sourceAttempt) {
      Add-Failure -Failures $failures -Code 'SOURCE_ATTEMPT_BINDING_MISMATCH' -Message ("sourceAttempt={0};bound={1}" -f $sourceAttempt, $boundSourceAttempt) -File $fileName -Ordinal $ordinal
    }
    $workflowAttemptsEvidence = Get-PropertyValue -Object $sourceAttemptEvidence -Name 'workflowAttempts'
    if ($null -eq $workflowAttemptsEvidence) {
      Add-Failure -Failures $failures -Code 'WORKFLOW_ATTEMPTS_EVIDENCE_MISSING' -Message 'sourceAttemptEvidence.workflowAttempts is missing' -File $fileName -Ordinal $ordinal
    } else {
      $attemptEvidenceNames = @($workflowAttemptsEvidence.PSObject.Properties.Name)
      if ($attemptEvidenceNames.Count -ne $workflowNames.Count -or @($workflowNames | Where-Object { $attemptEvidenceNames -notcontains $_ }).Count -gt 0) {
        Add-Failure -Failures $failures -Code 'WORKFLOW_ATTEMPTS_EVIDENCE_NOT_CLOSED' -Message (($attemptEvidenceNames | Sort-Object) -join ',') -File $fileName -Ordinal $ordinal
      }
      foreach ($workflowName in $workflowNames) {
        $attemptEvidenceProperty = $workflowAttemptsEvidence.PSObject.Properties[$workflowName]
        $matrixProperty = $matrix.PSObject.Properties[$workflowName]
        if ($null -eq $attemptEvidenceProperty -or $null -eq $matrixProperty) { continue }
        $boundAttempt = [int]$attemptEvidenceProperty.Value
        $matrixAttempt = [int](Get-PropertyValue -Object $matrixProperty.Value -Name 'attempts' -Fallback -1)
        if ($boundAttempt -ne $matrixAttempt) {
          Add-Failure -Failures $failures -Code 'WORKFLOW_ATTEMPT_BINDING_MISMATCH' -Message ("{0}:{1}!={2}" -f $workflowName, $boundAttempt, $matrixAttempt) -File $fileName -Ordinal $ordinal
        }
      }
    }
  }
  $matrixNames = @($matrix.PSObject.Properties.Name)
  foreach ($workflowName in $workflowNames) {
    $workflowProperty = $matrix.PSObject.Properties[$workflowName]
    if ($null -eq $workflowProperty -or $null -eq $workflowProperty.Value) {
      Add-Failure -Failures $failures -Code 'WORKFLOW_ENTRY_MISSING' -Message $workflowName -File $fileName -Ordinal $ordinal
      continue
    }
    $workflow = $workflowProperty.Value
    $workflowStatus = [string](Get-PropertyValue -Object $workflow -Name 'status' -Fallback '')
    $workflowOutcome = [string](Get-PropertyValue -Object $workflow -Name 'outcome' -Fallback '')
    $attempts = [int](Get-PropertyValue -Object $workflow -Name 'attempts' -Fallback -1)
    $tracePresent = [bool](Get-PropertyValue -Object $workflow -Name 'tracePresent' -Fallback $false)
    $matrixDigest = [string](Get-PropertyValue -Object $workflow -Name 'evidenceDigest' -Fallback '')
    $matrixTraceDigest = [string](Get-PropertyValue -Object $workflow -Name 'traceDigest' -Fallback '')
    if ($allowedStatuses -notcontains $workflowStatus) {
      Add-Failure -Failures $failures -Code 'WORKFLOW_STATUS_INVALID' -Message ("{0}:{1}" -f $workflowName, $workflowStatus) -File $fileName -Ordinal $ordinal
    }
    if ([string]::IsNullOrWhiteSpace($workflowOutcome)) {
      Add-Failure -Failures $failures -Code 'WORKFLOW_OUTCOME_MISSING' -Message $workflowName -File $fileName -Ordinal $ordinal
    }
    if ($attempts -lt 0) {
      Add-Failure -Failures $failures -Code 'WORKFLOW_ATTEMPTS_INVALID' -Message ("{0}:{1}" -f $workflowName, $attempts) -File $fileName -Ordinal $ordinal
    }
    if ($workflowStatus -eq 'passed' -and $attempts -eq 0 -and -not $tracePresent) {
      Add-Failure -Failures $failures -Code 'PASSED_WORKFLOW_WITHOUT_EVIDENCE' -Message $workflowName -File $fileName -Ordinal $ordinal
    }
    if ($tracePresent -and $matrixTraceDigest -notmatch '^[0-9a-fA-F]{64}$') {
      Add-Failure -Failures $failures -Code 'WORKFLOW_TRACE_DIGEST_INVALID' -Message ("{0}:traceDigest" -f $workflowName) -File $fileName -Ordinal $ordinal
    }
    if (-not $tracePresent -and -not [string]::IsNullOrWhiteSpace($matrixTraceDigest)) {
      Add-Failure -Failures $failures -Code 'WORKFLOW_TRACE_DIGEST_WITHOUT_TRACE' -Message $workflowName -File $fileName -Ordinal $ordinal
    }
    if ($tracePresent -and $matrixDigest -notmatch '^[0-9a-fA-F]{64}$') {
      Add-Failure -Failures $failures -Code 'WORKFLOW_MATRIX_DIGEST_INVALID' -Message $workflowName -File $fileName -Ordinal $ordinal
    }
    if (-not $tracePresent -and -not [string]::IsNullOrWhiteSpace($matrixDigest)) {
      Add-Failure -Failures $failures -Code 'WORKFLOW_MATRIX_DIGEST_WITHOUT_TRACE' -Message $workflowName -File $fileName -Ordinal $ordinal
    }
    if ($tracePresent -and $matrixDigest -ne $matrixTraceDigest) {
      Add-Failure -Failures $failures -Code 'WORKFLOW_MATRIX_TRACE_DIGEST_MISMATCH' -Message ("{0}:{1}!={2}" -f $workflowName, $matrixDigest, $matrixTraceDigest) -File $fileName -Ordinal $ordinal
    }
    if ($null -ne $workflowEvidence) {
      $projectionProperty = $workflowEvidence.PSObject.Properties[$workflowName]
      if ($null -eq $projectionProperty -or $null -eq $projectionProperty.Value) {
        Add-Failure -Failures $failures -Code 'WORKFLOW_EVIDENCE_ENTRY_MISSING' -Message $workflowName -File $fileName -Ordinal $ordinal
      } else {
        $projection = $projectionProperty.Value
        $projectionStatus = [string](Get-PropertyValue -Object $projection -Name 'status' -Fallback '')
        $projectionOutcome = [string](Get-PropertyValue -Object $projection -Name 'outcome' -Fallback '')
        $projectionAttempts = [int](Get-PropertyValue -Object $projection -Name 'attempts' -Fallback -1)
        $projectionDigest = [string](Get-PropertyValue -Object $projection -Name 'evidenceDigest' -Fallback '')
        $projectionTracePresent = [bool](Get-PropertyValue -Object $projection -Name 'tracePresent' -Fallback $false)
        $projectionTraceDigest = [string](Get-PropertyValue -Object $projection -Name 'traceDigest' -Fallback '')
        $projectionResult = [string](Get-PropertyValue -Object $projection -Name 'result' -Fallback '')
        if ($projectionStatus -ne $workflowStatus) {
          Add-Failure -Failures $failures -Code 'WORKFLOW_EVIDENCE_STATUS_MISMATCH' -Message ("{0}:{1}!={2}" -f $workflowName, $projectionStatus, $workflowStatus) -File $fileName -Ordinal $ordinal
        }
        if ($projectionOutcome -ne $workflowOutcome) {
          Add-Failure -Failures $failures -Code 'WORKFLOW_EVIDENCE_OUTCOME_MISMATCH' -Message ("{0}:{1}!={2}" -f $workflowName, $projectionOutcome, $workflowOutcome) -File $fileName -Ordinal $ordinal
        }
        if ($projectionAttempts -ne $attempts) {
          Add-Failure -Failures $failures -Code 'WORKFLOW_EVIDENCE_ATTEMPTS_MISMATCH' -Message ("{0}:{1}!={2}" -f $workflowName, $projectionAttempts, $attempts) -File $fileName -Ordinal $ordinal
        }
        if ($projectionTracePresent -ne $tracePresent) {
          Add-Failure -Failures $failures -Code 'WORKFLOW_EVIDENCE_TRACE_PRESENCE_MISMATCH' -Message ("{0}:{1}!={2}" -f $workflowName, $projectionTracePresent, $tracePresent) -File $fileName -Ordinal $ordinal
        }
        if ($projectionDigest -ne $matrixDigest) {
          Add-Failure -Failures $failures -Code 'WORKFLOW_EVIDENCE_DIGEST_MISMATCH' -Message ("{0}:{1}!={2}" -f $workflowName, $projectionDigest, $matrixDigest) -File $fileName -Ordinal $ordinal
        }
        if ($projectionTraceDigest -ne $matrixTraceDigest) {
          Add-Failure -Failures $failures -Code 'WORKFLOW_EVIDENCE_TRACE_DIGEST_MISMATCH' -Message ("{0}:{1}!={2}" -f $workflowName, $projectionTraceDigest, $matrixTraceDigest) -File $fileName -Ordinal $ordinal
        }
        if ([string]::IsNullOrWhiteSpace($projectionResult)) {
          Add-Failure -Failures $failures -Code 'WORKFLOW_EVIDENCE_RESULT_MISSING' -Message $workflowName -File $fileName -Ordinal $ordinal
        }
        if ($projectionTracePresent -and $projectionDigest -notmatch '^[0-9a-fA-F]{64}$') {
          Add-Failure -Failures $failures -Code 'WORKFLOW_TRACE_DIGEST_INVALID' -Message $workflowName -File $fileName -Ordinal $ordinal
        }
        if ($projectionTracePresent -and $projectionTraceDigest -notmatch '^[0-9a-fA-F]{64}$') {
          Add-Failure -Failures $failures -Code 'WORKFLOW_TRACE_DIGEST_INVALID' -Message ("{0}:projectionTraceDigest" -f $workflowName) -File $fileName -Ordinal $ordinal
        }
        if (-not $projectionTracePresent -and (-not [string]::IsNullOrWhiteSpace($projectionDigest) -or -not [string]::IsNullOrWhiteSpace($projectionTraceDigest))) {
          Add-Failure -Failures $failures -Code 'WORKFLOW_DIGEST_WITHOUT_TRACE' -Message $workflowName -File $fileName -Ordinal $ordinal
        }
      }
  }
  if (-not $workflowStatusCounts.ContainsKey($workflowName)) { $workflowStatusCounts[$workflowName] = @{} }
    if (-not $workflowStatusCounts[$workflowName].ContainsKey($workflowStatus)) { $workflowStatusCounts[$workflowName][$workflowStatus] = 0 }
    $workflowStatusCounts[$workflowName][$workflowStatus] = [int]$workflowStatusCounts[$workflowName][$workflowStatus] + 1
    if (-not $workflowAttemptCounts.ContainsKey($workflowName)) { $workflowAttemptCounts[$workflowName] = 0 }
    $workflowAttemptCounts[$workflowName] = [int]$workflowAttemptCounts[$workflowName] + $attempts
  }
  if ($null -ne $workflowEvidence) {
    $projectionNames = @($workflowEvidence.PSObject.Properties.Name)
    if ($projectionNames.Count -ne $workflowNames.Count -or @($workflowNames | Where-Object { $projectionNames -notcontains $_ }).Count -gt 0) {
      Add-Failure -Failures $failures -Code 'WORKFLOW_EVIDENCE_NOT_CLOSED' -Message (($projectionNames | Sort-Object) -join ',') -File $fileName -Ordinal $ordinal
    }
  }
  $topLevelTrace = Get-PropertyValue -Object $evidence -Name 'trace'
  if ($null -ne $topLevelTrace) {
    $topLevelTraceWorkflow = [string](Get-PropertyValue -Object $topLevelTrace -Name 'workflow' -Fallback '')
    $topLevelTraceDigest = [string](Get-PropertyValue -Object $topLevelTrace -Name 'outputSummarySha256' -Fallback '')
    if ($topLevelTraceWorkflow -notin @('search', 'explore', 'book_info', 'toc', 'content', 'file', 'review')) {
      Add-Failure -Failures $failures -Code 'TOP_LEVEL_TRACE_WORKFLOW_INVALID' -Message $topLevelTraceWorkflow -File $fileName -Ordinal $ordinal
    } elseif ($topLevelTraceDigest -notmatch '^[0-9a-fA-F]{64}$') {
      Add-Failure -Failures $failures -Code 'TOP_LEVEL_TRACE_DIGEST_INVALID' -Message $topLevelTraceWorkflow -File $fileName -Ordinal $ordinal
    } else {
      $traceStateName = switch ($topLevelTraceWorkflow) {
        'book_info' { 'bookInfo' }
        default { $topLevelTraceWorkflow }
      }
      $traceStateProperty = $matrix.PSObject.Properties[$traceStateName]
      if ($null -eq $traceStateProperty -or -not [bool](Get-PropertyValue -Object $traceStateProperty.Value -Name 'tracePresent' -Fallback $false)) {
        Add-Failure -Failures $failures -Code 'TOP_LEVEL_TRACE_NOT_BOUND' -Message $topLevelTraceWorkflow -File $fileName -Ordinal $ordinal
      } elseif ([string](Get-PropertyValue -Object $traceStateProperty.Value -Name 'traceDigest' -Fallback '') -ne $topLevelTraceDigest) {
        Add-Failure -Failures $failures -Code 'TOP_LEVEL_TRACE_DIGEST_MISMATCH' -Message $topLevelTraceWorkflow -File $fileName -Ordinal $ordinal
      }
    }
  }
  if ($matrixNames.Count -ne $workflowNames.Count -or @($workflowNames | Where-Object { $matrixNames -notcontains $_ }).Count -gt 0) {
    Add-Failure -Failures $failures -Code 'WORKFLOW_MATRIX_NOT_CLOSED' -Message (($matrixNames | Sort-Object) -join ',') -File $fileName -Ordinal $ordinal
  }
  $driverClosed = [bool](Get-PropertyValue -Object $evidence -Name 'driverClosed' -Fallback $false)
  $runnerStatus = [string](Get-PropertyValue -Object $evidence -Name 'runnerStatus' -Fallback '')
  if ($runnerStatus -ne 'not_executed' -and -not $driverClosed) {
    Add-Failure -Failures $failures -Code 'DRIVER_NOT_CLOSED' -Message $runnerStatus -File $fileName -Ordinal $ordinal
  }
}

if ($ordinals.Count -eq $ExpectedSourceCount) {
  foreach ($ordinal in 0..($ExpectedSourceCount - 1)) {
    if (-not $ordinals.Contains($ordinal)) {
      Add-Failure -Failures $failures -Code 'ORDINAL_MISSING' -Message ([string]$ordinal) -Ordinal $ordinal
    }
  }
}

if ($RequireCompleted) {
  $activityPath = Join-Path $EvidenceDirectory 'run-activity.json'
  if (-not (Test-Path -LiteralPath $activityPath)) {
    Add-Failure -Failures $failures -Code 'RUN_ACTIVITY_MISSING' -Message $activityPath
  } else {
    $activity = Read-Utf8Json -Path $activityPath
    if ([string](Get-PropertyValue -Object $activity -Name 'status' -Fallback '') -ne 'passed' -or
        [string](Get-PropertyValue -Object $activity -Name 'phase' -Fallback '') -ne 'completed') {
      Add-Failure -Failures $failures -Code 'RUN_NOT_COMPLETED' -Message ([string]($activity | ConvertTo-Json -Compress))
    }
  }
}

if (Test-Path -LiteralPath $StatePath) {
  $state = Read-Utf8Json -Path $StatePath
  $stateSources = @(Get-PropertyValue -Object $state -Name 'sources' -Fallback @())
  if ($stateSources.Count -ne $ExpectedSourceCount) {
    Add-Failure -Failures $failures -Code 'STATE_SOURCE_COUNT_MISMATCH' -Message ("expected={0};actual={1}" -f $ExpectedSourceCount, $stateSources.Count)
  }
  $stateByOrdinal = @{}
  foreach ($stateSource in $stateSources) {
    $stateOrdinal = [int](Get-PropertyValue -Object $stateSource -Name 'ordinal' -Fallback -1)
    $stateByOrdinal[[string]$stateOrdinal] = $stateSource
  }
  foreach ($record in $records) {
    $evidence = $record.evidence
    $ordinal = [int](Get-PropertyValue -Object $evidence -Name 'ordinal' -Fallback -1)
    $stateSource = $stateByOrdinal[[string]$ordinal]
    if ($null -eq $stateSource) {
      Add-Failure -Failures $failures -Code 'STATE_SOURCE_MISSING' -Message ([string]$ordinal) -File $record.file -Ordinal $ordinal
      continue
    }
    if ([string](Get-PropertyValue -Object $stateSource -Name 'sourceId' -Fallback '') -ne [string](Get-PropertyValue -Object $evidence -Name 'sourceId' -Fallback '')) {
      Add-Failure -Failures $failures -Code 'STATE_EVIDENCE_SOURCE_MISMATCH' -Message 'sourceId differs' -File $record.file -Ordinal $ordinal
    }
    if ([string](Get-PropertyValue -Object $stateSource -Name 'status' -Fallback '') -ne [string](Get-PropertyValue -Object $evidence -Name 'status' -Fallback '')) {
      Add-Failure -Failures $failures -Code 'STATE_EVIDENCE_STATUS_MISMATCH' -Message 'status differs' -File $record.file -Ordinal $ordinal
    }
  }
} else {
  Add-Failure -Failures $failures -Code 'STATE_FILE_MISSING' -Message $StatePath
}

$status = if ($failures.Count -eq 0) { 'passed' } else { 'failed' }
$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  generatedAt = [DateTime]::UtcNow.ToString('o')
  status = $status
  evidenceMode = if ($DisableEvidenceOverlay) { 'baseline' } else { 'effective_overlay' }
  baselineEvidenceDirectory = $EvidenceDirectory
  overlayRoot = $OverlayRoot
  effectiveEvidenceDirectory = if ($DisableEvidenceOverlay) { '' } else { $EffectiveEvidenceDirectory }
  expectedSourceCount = $ExpectedSourceCount
  evidenceCount = $records.Count
  uniqueOrdinalCount = $ordinals.Count
  uniqueSourceIdCount = $sourceIds.Count
  runIdCount = $runIds.Count
  overlayDirectoryCount = $overlayDirectories.Count
  overlayCandidateCount = $overlayCandidates.Count
  overlayAppliedCount = $overlayAppliedCount
  effectiveEvidenceMap = $effectiveMap
  statusCounts = $statusCounts
  outcomeCounts = $outcomeCounts
  workflowStatusCounts = $workflowStatusCounts
  workflowAttemptCounts = $workflowAttemptCounts
  failureCount = $failures.Count
  failures = @($failures)
}
$resultDirectory = Split-Path -Parent $ResultPath
Write-Utf8JsonAtomic -Path $ResultPath -Value $result -Depth 32
if (-not $DisableEvidenceOverlay) {
  Write-Utf8JsonAtomic -Path (Join-Path $EffectiveEvidenceDirectory 'effective-run-activity.json') -Value ([pscustomobject][ordered]@{
    schemaVersion = 1
    generatedAt = [DateTime]::UtcNow.ToString('o')
    runId = 'effective-evidence-overlay-audit'
    status = $status
    phase = if ($status -eq 'passed') { 'completed' } else { 'failed' }
    executionProfile = 'effective_overlay'
    baselineRunId = [string](Get-PropertyValue -Object $baselineActivity -Name 'runId' -Fallback '')
    scheduledSources = $ExpectedSourceCount
    completedSources = $records.Count
    overlayAppliedCount = $overlayAppliedCount
    errorDigest = if ($failures.Count -eq 0) { '' } else { ([string]($failures | ConvertTo-Json -Compress)).GetHashCode().ToString('X8') }
  }) -Depth 16
}
$result | ConvertTo-Json -Depth 16
if ($status -ne 'passed') { exit 1 }
