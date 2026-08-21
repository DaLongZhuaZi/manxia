Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:Utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)

function Get-LegadoOptionalProperty {
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

function Get-LegadoTextProperty {
  param([object]$Object, [string]$Name)
  $value = Get-LegadoOptionalProperty -Object $Object -Name $Name
  if ($null -eq $value) {
    return ''
  }
  if ($value -is [string]) {
    return [string]$value
  }
  return [string]($value | ConvertTo-Json -Compress -Depth 100)
}

function Get-LegadoSha256ForBytes {
  param([byte[]]$Bytes)
  $algorithm = [System.Security.Cryptography.SHA256]::Create()
  try {
    return ([System.BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace('-', '')
  } finally {
    $algorithm.Dispose()
  }
}

function Get-LegadoSha256ForText {
  param([string]$Value)
  return Get-LegadoSha256ForBytes -Bytes $script:Utf8NoBom.GetBytes($Value)
}

function ConvertFrom-LegadoJsonArray {
  param([string]$Json, [string]$Label = 'JSON')
  $text = $Json.Trim()
  if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) {
    $text = $text.Substring(1).TrimStart()
  }
  if (-not $text.StartsWith('[') -or -not $text.EndsWith(']')) {
    throw "$Label must be a top-level JSON array."
  }
  $parsed = ConvertFrom-Json -InputObject $text -DateKind String
  $items = New-Object 'System.Collections.Generic.List[object]'
  if ($null -ne $parsed) {
    if ($parsed -is [System.Array]) {
      foreach ($item in $parsed) {
        [void]$items.Add($item)
      }
    } else {
      [void]$items.Add($parsed)
    }
  }
  return $items.ToArray()
}

function Get-LegadoRawSourceDocuments {
  param([string]$Json, [string]$Label = 'source package')
  $text = $Json.Trim()
  if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) {
    $text = $text.Substring(1).TrimStart()
  }
  if (-not $text.StartsWith('[') -or -not $text.EndsWith(']')) {
    throw "$Label must be a top-level JSON array."
  }

  $documents = New-Object 'System.Collections.Generic.List[string]'
  $inString = $false
  $escaped = $false
  $objectDepth = 0
  $arrayDepth = 0
  $start = -1
  for ($index = 0; $index -lt $text.Length; $index++) {
    $char = $text[$index]
    if ($inString) {
      if ($escaped) {
        $escaped = $false
      } elseif ($char -eq '\') {
        $escaped = $true
      } elseif ($char -eq '"') {
        $inString = $false
      }
      continue
    }
    if ($char -eq '"') {
      $inString = $true
    } elseif ($char -eq '[') {
      $arrayDepth++
    } elseif ($char -eq ']') {
      $arrayDepth--
      if ($arrayDepth -lt 0) {
        throw "$Label has an invalid array boundary."
      }
    } elseif ($char -eq '{') {
      if ($arrayDepth -eq 1 -and $objectDepth -eq 0) {
        $start = $index
      }
      $objectDepth++
    } elseif ($char -eq '}') {
      $objectDepth--
      if ($objectDepth -lt 0) {
        throw "$Label has an invalid object boundary."
      }
      if ($arrayDepth -eq 1 -and $objectDepth -eq 0 -and $start -ge 0) {
        [void]$documents.Add($text.Substring($start, $index - $start + 1))
        $start = -1
      }
    }
  }
  if ($inString -or $escaped -or $objectDepth -ne 0 -or $arrayDepth -ne 0 -or $start -ne -1) {
    throw "$Label has incomplete JSON boundaries."
  }

  $parsedCount = @(ConvertFrom-LegadoJsonArray -Json $text -Label $Label).Count
  if ($parsedCount -ne $documents.Count) {
    throw "$Label may contain only top-level JSON objects. parsed=$parsedCount raw=$($documents.Count)"
  }
  return $documents.ToArray()
}

function Read-LegadoJsonFile {
  param([string]$Path)
  if ($Path.Length -eq 0 -or -not (Test-Path -LiteralPath $Path)) {
    return $null
  }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $text = $script:Utf8Strict.GetString($bytes)
  if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) {
    $text = $text.Substring(1)
  }
  return ConvertFrom-Json -InputObject $text -DateKind String
}

function Enter-LegadoStateLock {
  param([string]$StatePath, [int]$TimeoutMilliseconds = 10000)
  $lockPath = "$StatePath.lock"
  $directory = Split-Path -Path $lockPath -Parent
  if (-not (Test-Path -LiteralPath $directory)) {
    [void][System.IO.Directory]::CreateDirectory($directory)
  }
  $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMilliseconds)
  while ([DateTime]::UtcNow -lt $deadline) {
    try {
      return [System.IO.File]::Open(
        $lockPath,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
      )
    } catch [System.IO.IOException] {
      Start-Sleep -Milliseconds 50
    }
  }
  throw "State checkpoint is locked by another process: $StatePath"
}

function Write-LegadoUtf8AtomicInternal {
  param([string]$Path, [string]$Content)
  $directory = Split-Path -Path $Path -Parent
  if (-not (Test-Path -LiteralPath $directory)) {
    [void][System.IO.Directory]::CreateDirectory($directory)
  }
  $nonce = "{0}.{1}" -f $PID, ([Guid]::NewGuid().ToString('N'))
  $temporaryPath = "$Path.tmp.$nonce"
  $replacementBackup = "$Path.replace.$nonce"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, $Content, $script:Utf8NoBom)
    if (Test-Path -LiteralPath $Path) {
      [System.IO.File]::Replace($temporaryPath, $Path, $replacementBackup, $true)
      if (Test-Path -LiteralPath $replacementBackup) {
        [System.IO.File]::Delete($replacementBackup)
      }
    } else {
      [System.IO.File]::Move($temporaryPath, $Path)
    }
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      [System.IO.File]::Delete($temporaryPath)
    }
  }
}

function Write-LegadoStateCheckpoint {
  param([string]$Path, [object]$State, [int]$Depth = 30)
  $lock = Enter-LegadoStateLock -StatePath $Path
  try {
    Sync-LegadoStateDerivedFields -State $State
    Write-LegadoUtf8AtomicInternal -Path $Path -Content ([string]($State | ConvertTo-Json -Depth $Depth))
  } finally {
    $lock.Dispose()
  }
}

function Test-LegadoRawHashMatch {
  param([string]$ExpectedSha256, [string]$ActualSha256)
  if ($ExpectedSha256 -notmatch '^[A-Fa-f0-9]{64}$' -or $ActualSha256 -notmatch '^[A-Fa-f0-9]{64}$') {
    return $false
  }
  return [string]::Equals(
    $ExpectedSha256,
    $ActualSha256,
    [System.StringComparison]::OrdinalIgnoreCase
  )
}

function New-LegadoWorkflowState {
  return [pscustomobject][ordered]@{
    status = 'planned'
    attempts = 0
    lastOutcome = ''
    lastEvidenceDigest = ''
  }
}

function Get-LegadoStatusCounts {
  param([object[]]$Records)
  $counts = [ordered]@{
    planned = 0
    running = 0
    verifying = 0
    passed = 0
    failed = 0
    expected_external = 0
    needs_interaction = 0
    policy_blocked = 0
    blocked = 0
  }
  foreach ($record in @($Records)) {
    $status = [string](Get-LegadoOptionalProperty -Object $record -Name 'status')
    if (-not $counts.Contains($status)) {
      $counts[$status] = 0
    }
    $counts[$status] = [int]$counts[$status] + 1
  }
  return $counts
}

function Get-LegadoSemanticQualificationCounts {
  param([object[]]$Records)
  $counts = [ordered]@{
    unverified = 0
    execution_verified_no_reference = 0
    semantic_match = 0
    semantic_mismatch = 0
    external_confirmed = 0
    endpoint_unconfirmed = 0
    needs_interaction = 0
    policy_rejected = 0
    engine_rejected = 0
    arkweb_unconfirmed = 0
    harness_or_engine_failure = 0
  }
  foreach ($record in @($Records)) {
    $qualification = [string](Get-LegadoOptionalProperty -Object $record -Name 'semanticQualification')
    if ($qualification.Length -eq 0) { $qualification = 'unverified' }
    if (-not $counts.Contains($qualification)) { $counts[$qualification] = 0 }
    $counts[$qualification] = [int]$counts[$qualification] + 1
  }
  return $counts
}

function Get-LegadoSourceValidationSummary {
  param([object]$StatusCounts)
  return [pscustomobject][ordered]@{
    planned = [int]$StatusCounts.planned
    running = [int]$StatusCounts.running
    verifying = [int]$StatusCounts.verifying
    passed = [int]$StatusCounts.passed
    failed = [int]$StatusCounts.failed
    expectedExternal = [int]$StatusCounts.expected_external
    needsInteraction = [int]$StatusCounts.needs_interaction
    policyBlocked = [int]$StatusCounts.policy_blocked
    blocked = [int]$StatusCounts.blocked
  }
}

function Get-LegadoSemanticQualificationSummary {
  param([object]$QualificationCounts)
  return [pscustomobject][ordered]@{
    unverified = [int]$QualificationCounts.unverified
    executionVerifiedNoReference = [int]$QualificationCounts.execution_verified_no_reference
    semanticMatch = [int]$QualificationCounts.semantic_match
    semanticMismatch = [int]$QualificationCounts.semantic_mismatch
    externalConfirmed = [int]$QualificationCounts.external_confirmed
    endpointUnconfirmed = [int]$QualificationCounts.endpoint_unconfirmed
    needsInteraction = [int]$QualificationCounts.needs_interaction
    policyRejected = [int]$QualificationCounts.policy_rejected
    engineRejected = [int]$QualificationCounts.engine_rejected
    arkWebUnconfirmed = [int]$QualificationCounts.arkweb_unconfirmed
    harnessOrEngineFailure = [int]$QualificationCounts.harness_or_engine_failure
  }
}

function New-LegadoDevicePersistedQualification {
  param([int]$SourceCount)
  return [pscustomobject][ordered]@{
    schemaVersion = 1
    observationStatus = 'unobserved'
    observationKind = 'management_summary_aggregate'
    totalSourceCount = $SourceCount
    verificationRows = 0
    completeVerificationCount = 0
    verificationDenominator = 0
    executionPolicy = 'unknown'
    sourceIdentityCoverage = 'not_observed'
    evidencePath = ''
    evidenceSha256 = ''
    deviceIdSha256 = ''
    clockStatus = 'host_wall_clock_untrusted'
    observedAtUtc = ''
  }
}

function Get-LegadoDevicePersistedQualificationSummary {
  param([object]$Qualification, [int]$ExpectedSourceCount)
  if ($null -eq $Qualification) {
    return New-LegadoDevicePersistedQualification -SourceCount $ExpectedSourceCount
  }
  $totalSourceCount = [int](Get-LegadoOptionalProperty -Object $Qualification -Name 'totalSourceCount')
  $verificationRows = [int](Get-LegadoOptionalProperty -Object $Qualification -Name 'verificationRows')
  $completeVerificationCount = [int](Get-LegadoOptionalProperty -Object $Qualification -Name 'completeVerificationCount')
  $verificationDenominator = [int](Get-LegadoOptionalProperty -Object $Qualification -Name 'verificationDenominator')
  if ($totalSourceCount -ne $ExpectedSourceCount -or $verificationDenominator -gt $ExpectedSourceCount -or
    $verificationRows -lt 0 -or $completeVerificationCount -lt 0 -or
    $verificationRows -ne $completeVerificationCount) {
    throw 'Device-persisted qualification is inconsistent with the immutable source baseline.'
  }
  return [pscustomobject][ordered]@{
    schemaVersion = [int](Get-LegadoOptionalProperty -Object $Qualification -Name 'schemaVersion')
    observationStatus = [string](Get-LegadoOptionalProperty -Object $Qualification -Name 'observationStatus')
    observationKind = [string](Get-LegadoOptionalProperty -Object $Qualification -Name 'observationKind')
    totalSourceCount = $totalSourceCount
    verificationRows = $verificationRows
    completeVerificationCount = $completeVerificationCount
    verificationDenominator = $verificationDenominator
    executionPolicy = [string](Get-LegadoOptionalProperty -Object $Qualification -Name 'executionPolicy')
    sourceIdentityCoverage = [string](Get-LegadoOptionalProperty -Object $Qualification -Name 'sourceIdentityCoverage')
    evidencePath = [string](Get-LegadoOptionalProperty -Object $Qualification -Name 'evidencePath')
    evidenceSha256 = [string](Get-LegadoOptionalProperty -Object $Qualification -Name 'evidenceSha256')
    deviceIdSha256 = [string](Get-LegadoOptionalProperty -Object $Qualification -Name 'deviceIdSha256')
    clockStatus = [string](Get-LegadoOptionalProperty -Object $Qualification -Name 'clockStatus')
    observedAtUtc = [string](Get-LegadoOptionalProperty -Object $Qualification -Name 'observedAtUtc')
  }
}

function Sync-LegadoStateDerivedFields {
  param([object]$State)
  if ($null -eq $State) {
    return
  }
  $sourcesProperty = $State.PSObject.Properties['sources']
  if ($null -eq $sourcesProperty) {
    return
  }
  $records = @($sourcesProperty.Value)
  $statusCounts = Get-LegadoStatusCounts -Records $records
  $qualificationCounts = Get-LegadoSemanticQualificationCounts -Records $records
  $devicePersistedQualification = Get-LegadoDevicePersistedQualificationSummary `
    -Qualification (Get-LegadoOptionalProperty -Object $State -Name 'devicePersistedQualification') `
    -ExpectedSourceCount $records.Count
  $State | Add-Member -NotePropertyName 'statusCounts' -NotePropertyValue ([pscustomobject]$statusCounts) -Force
  $State | Add-Member -NotePropertyName 'qualificationCounts' -NotePropertyValue ([pscustomobject]$qualificationCounts) -Force
  $State | Add-Member -NotePropertyName 'devicePersistedQualification' -NotePropertyValue $devicePersistedQualification -Force

  $governance = Get-LegadoOptionalProperty -Object $State -Name 'governance'
  if ($null -ne $governance) {
    $governance | Add-Member -NotePropertyName 'sourceValidation' -NotePropertyValue (Get-LegadoSourceValidationSummary -StatusCounts $statusCounts) -Force
    $governance | Add-Member -NotePropertyName 'semanticQualification' -NotePropertyValue (Get-LegadoSemanticQualificationSummary -QualificationCounts $qualificationCounts) -Force
    $governance | Add-Member -NotePropertyName 'devicePersistedQualification' -NotePropertyValue $devicePersistedQualification -Force
  }

  $pending = @(
    $records |
      Where-Object { [string]$_.status -in @('running', 'verifying', 'planned', 'failed') } |
      Select-Object -First 1
  )
  $cursorOrdinal = if ($pending.Count -gt 0) { [int]$pending[0].ordinal } else { $records.Count }
  $cursorSourceId = ''
  if ($pending.Count -gt 0) {
    $cursorSourceId = [string](Get-LegadoOptionalProperty -Object $pending[0] -Name 'sourceId')
    if ($cursorSourceId.Length -ne 64) {
      $cursorSourceId = [string](Get-LegadoOptionalProperty -Object $pending[0] -Name 'rawDocumentSha256')
    }
    if ($cursorSourceId.Length -ne 64) {
      $cursorSourceId = [string](Get-LegadoOptionalProperty -Object $pending[0] -Name 'sourceHash')
    }
  }
  $State | Add-Member -NotePropertyName 'cursor' -NotePropertyValue ([pscustomobject][ordered]@{
    ordinal = $cursorOrdinal
    sourceId = $cursorSourceId
  }) -Force

  $overallStatus = 'planned'
  if ([int]$statusCounts.blocked -gt 0) {
    $overallStatus = 'blocked'
  } elseif ([int]$statusCounts.running -gt 0 -or [int]$statusCounts.verifying -gt 0) {
    $overallStatus = 'running'
  } elseif ([int]$statusCounts.planned -eq 0 -and [int]$statusCounts.failed -eq 0) {
    $overallStatus = 'passed'
  }
  $State | Add-Member -NotePropertyName 'status' -NotePropertyValue $overallStatus -Force
  $State | Add-Member -NotePropertyName 'generatedAt' -NotePropertyValue ([DateTimeOffset]::UtcNow.ToString('o')) -Force
}

function New-LegadoSourceRecord {
  param([object]$Source, [string]$RawDocument, [int]$Ordinal)
  $sourceId = Get-LegadoSha256ForText -Value $RawDocument
  $inspectionText = $RawDocument
  $sourceTypeText = Get-LegadoTextProperty -Object $Source -Name 'bookSourceType'
  $sourceType = 0
  if (-not [int]::TryParse($sourceTypeText, [ref]$sourceType)) {
    $sourceType = 0
  }
  $login = (Get-LegadoTextProperty -Object $Source -Name 'loginUrl').Length -gt 0 -or
    (Get-LegadoTextProperty -Object $Source -Name 'loginUi').Length -gt 0 -or
    (Get-LegadoTextProperty -Object $Source -Name 'loginCheckJs').Length -gt 0
  $explicitJs = [regex]::IsMatch(
    $inspectionText,
    '(?i)@js|<js>|java\.|source\.[A-Za-z_$]|javascript:|eval\s*\(|function\s*\('
  )
  $template = [regex]::IsMatch($inspectionText, '\{\{')
  $webView = [regex]::IsMatch($inspectionText, '(?i)"webView"\s*:\s*true|"webJs"\s*:')
  $ruleBookInfo = Get-LegadoOptionalProperty -Object $Source -Name 'ruleBookInfo'
  $ruleContent = Get-LegadoOptionalProperty -Object $Source -Name 'ruleContent'
  $review = (Get-LegadoTextProperty -Object $Source -Name 'ruleReview').Length -gt 0
  $download = (Get-LegadoTextProperty -Object $ruleBookInfo -Name 'downloadUrls').Length -gt 0
  $payAction = (Get-LegadoTextProperty -Object $ruleContent -Name 'payAction').Length -gt 0
  $imageDecode = (Get-LegadoTextProperty -Object $ruleContent -Name 'imageDecode').Length -gt 0

  $bucket = 'safe_text'
  if ($sourceType -eq 1) {
    $bucket = 'audio'
  } elseif ($sourceType -eq 2) {
    $bucket = 'image'
  } elseif ($sourceType -eq 3) {
    $bucket = 'file'
  } elseif ($sourceType -lt 0 -or $sourceType -gt 3) {
    $bucket = 'external'
  } elseif ($login -or $payAction) {
    $bucket = 'interactive'
  } elseif ($explicitJs -or $webView) {
    $bucket = 'js_text'
  }

  return [pscustomobject][ordered]@{
    ordinal = $Ordinal
    sourceId = $sourceId
    sourceHash = $sourceId
    rawDocumentSha256 = $sourceId
    sourceType = $sourceType
    bucket = $bucket
    capabilities = [pscustomobject][ordered]@{
      search = (Get-LegadoTextProperty -Object $Source -Name 'searchUrl').Length -gt 0
      explore = (Get-LegadoTextProperty -Object $Source -Name 'exploreUrl').Length -gt 0
      bookInfo = $null -ne (Get-LegadoOptionalProperty -Object $Source -Name 'ruleBookInfo')
      toc = $null -ne (Get-LegadoOptionalProperty -Object $Source -Name 'ruleToc')
      content = $null -ne (Get-LegadoOptionalProperty -Object $Source -Name 'ruleContent')
      explicitJs = $explicitJs
      template = $template
      webView = $webView
      login = $login
      review = $review
      download = $download
      payAction = $payAction
      imageDecode = $imageDecode
    }
    status = 'planned'
    semanticQualification = 'unverified'
    attempts = 0
    lastOutcome = ''
    lastUpdatedAt = ''
    workflows = [pscustomobject][ordered]@{
      search = New-LegadoWorkflowState
      explore = New-LegadoWorkflowState
      bookInfo = New-LegadoWorkflowState
      toc = New-LegadoWorkflowState
      content = New-LegadoWorkflowState
      file = New-LegadoWorkflowState
      review = New-LegadoWorkflowState
    }
    issueIds = @()
  }
}

function Copy-LegadoRecordProgress {
  param([object]$Existing, [object]$Target)
  if ($null -eq $Existing) {
    return
  }
  $excluded = @(
    'ordinal', 'sourceId', 'sourceHash', 'rawDocumentSha256', 'legacySourceHash',
    'sourceType', 'bucket', 'capabilities'
  )
  foreach ($property in $Existing.PSObject.Properties) {
    if ($excluded -notcontains [string]$property.Name) {
      $Target | Add-Member -NotePropertyName ([string]$property.Name) -NotePropertyValue $property.Value -Force
    }
  }
  $legacyHash = [string](Get-LegadoOptionalProperty -Object $Existing -Name 'legacySourceHash')
  if ($legacyHash.Length -ne 64) {
    $legacyHash = [string](Get-LegadoOptionalProperty -Object $Existing -Name 'sourceHash')
  }
  if ($legacyHash.Length -eq 64 -and $legacyHash -ne [string]$Target.sourceId) {
    $Target | Add-Member -NotePropertyName 'legacySourceHash' -NotePropertyValue $legacyHash -Force
  }
  $readiness = Get-LegadoOptionalProperty -Object $Target -Name 'deviceReadiness'
  if ($null -ne $readiness) {
    $verification = [string](Get-LegadoOptionalProperty -Object $readiness -Name 'rawHashVerification')
    if ($verification.Length -eq 0) {
      $readiness | Add-Member -NotePropertyName 'rawHashMatches' -NotePropertyValue $false -Force
      $readiness | Add-Member -NotePropertyName 'rawHashVerification' -NotePropertyValue 'pending_exact_digest_reaudit' -Force
      $readiness | Add-Member -NotePropertyName 'rawHashExpectedSourceId' -NotePropertyValue ([string]$Target.sourceId) -Force
      $readiness | Add-Member -NotePropertyName 'legacyRawHashClaimInvalidated' -NotePropertyValue $true -Force
    }
  }
}

function Reset-LegadoStaleStatus {
  param([object]$Item, [string]$Scope, [string]$RecoveredAt)
  if ($null -eq $Item) {
    return 0
  }
  $statusProperty = $Item.PSObject.Properties['status']
  # Only an interrupted execution is stale. `verifying` is a durable
  # post-static-closure state and must not be reopened merely because the
  # host restarted.
  if ($null -eq $statusProperty -or [string]$statusProperty.Value -ne 'running') {
    return 0
  }
  $priorStatus = [string]$statusProperty.Value
  $statusProperty.Value = 'planned'
  $Item | Add-Member -NotePropertyName 'retryable' -NotePropertyValue $true -Force
  $Item | Add-Member -NotePropertyName 'lastRecovery' -NotePropertyValue ([pscustomobject][ordered]@{
    reason = 'stale_execution_recovered'
    priorStatus = $priorStatus
    scope = $Scope
    recoveredAt = $RecoveredAt
  }) -Force
  return 1
}

function Recover-LegadoSupersededCompileBlock {
  param([object]$Record, [string]$RecoveredAt)
  if ($null -eq $Record -or [string](Get-LegadoOptionalProperty -Object $Record -Name 'status') -ne 'blocked' -or
    [string](Get-LegadoOptionalProperty -Object $Record -Name 'lastOutcome') -ne 'device_compile_blocked') {
    return 0
  }
  $readiness = Get-LegadoOptionalProperty -Object $Record -Name 'deviceReadiness'
  if ($null -eq $readiness -or [string](Get-LegadoOptionalProperty -Object $readiness -Name 'compileStatus') -ne 'ready' -or
    [string](Get-LegadoOptionalProperty -Object $readiness -Name 'engineMode') -ne 'v2_enabled' -or
    [string](Get-LegadoOptionalProperty -Object $readiness -Name 'rawHashVerification') -ne 'exact_digest_match') {
    return 0
  }
  $workflows = Get-LegadoOptionalProperty -Object $Record -Name 'workflows'
  if ($null -eq $workflows) {
    return 0
  }
  foreach ($property in $workflows.PSObject.Properties) {
    if ([int](Get-LegadoOptionalProperty -Object $property.Value -Name 'attempts') -gt 0) {
      return 0
    }
  }
  $priorOutcome = [string](Get-LegadoOptionalProperty -Object $Record -Name 'lastOutcome')
  $Record | Add-Member -NotePropertyName 'status' -NotePropertyValue 'planned' -Force
  $Record | Add-Member -NotePropertyName 'lastOutcome' -NotePropertyValue 'recovery_pending_v2_execution' -Force
  $Record | Add-Member -NotePropertyName 'semanticQualification' -NotePropertyValue 'unverified' -Force
  $Record | Add-Member -NotePropertyName 'retryable' -NotePropertyValue $true -Force
  $Record | Add-Member -NotePropertyName 'lastRecovery' -NotePropertyValue ([pscustomobject][ordered]@{
    reason = 'compile_block_superseded_by_device_ready'
    priorStatus = 'blocked'
    priorOutcome = $priorOutcome
    scope = 'source'
    recoveredAt = $RecoveredAt
  }) -Force
  $recovered = 1
  foreach ($property in $workflows.PSObject.Properties) {
    $workflow = $property.Value
    $workflow | Add-Member -NotePropertyName 'status' -NotePropertyValue 'planned' -Force
    $workflow | Add-Member -NotePropertyName 'lastOutcome' -NotePropertyValue 'recovery_pending_v2_execution' -Force
    $workflow | Add-Member -NotePropertyName 'retryable' -NotePropertyValue $true -Force
    $workflow | Add-Member -NotePropertyName 'lastRecovery' -NotePropertyValue ([pscustomobject][ordered]@{
      reason = 'compile_block_superseded_by_device_ready'
      priorStatus = 'blocked'
      priorOutcome = 'device_compile_blocked'
      scope = ("workflow:{0}" -f $property.Name)
      recoveredAt = $RecoveredAt
    }) -Force
    $recovered++
  }
  return $recovered
}

function Recover-LegadoSourceRecords {
  param([object[]]$Records, [string]$RecoveredAt)
  $count = 0
  foreach ($record in @($Records)) {
    $count += Reset-LegadoStaleStatus -Item $record -Scope 'source' -RecoveredAt $RecoveredAt
    $workflows = Get-LegadoOptionalProperty -Object $record -Name 'workflows'
    if ($null -ne $workflows) {
      foreach ($property in $workflows.PSObject.Properties) {
        $count += Reset-LegadoStaleStatus -Item $property.Value -Scope ("workflow:{0}" -f $property.Name) -RecoveredAt $RecoveredAt
      }
    }
    $count += Recover-LegadoSupersededCompileBlock -Record $record -RecoveredAt $RecoveredAt
  }
  return $count
}

function Get-LegadoRecordedSourceRecoveryCount {
  param([object[]]$Records)
  $count = 0
  foreach ($record in @($Records)) {
    if ($null -ne (Get-LegadoOptionalProperty -Object $record -Name 'lastRecovery')) {
      $count++
    }
    $workflows = Get-LegadoOptionalProperty -Object $record -Name 'workflows'
    if ($null -ne $workflows) {
      foreach ($property in $workflows.PSObject.Properties) {
        if ($null -ne (Get-LegadoOptionalProperty -Object $property.Value -Name 'lastRecovery')) {
          $count++
        }
      }
    }
  }
  return $count
}

function Recover-LegadoGovernance {
  param([object]$Governance, [string]$RecoveredAt)
  if ($null -eq $Governance) {
    return [pscustomobject][ordered]@{
      governance = [pscustomobject][ordered]@{
        status = 'planned'
        activeTaskId = ''
        tasks = @()
        uiAudit = [pscustomobject][ordered]@{}
        issues = @()
      }
      recovered = 0
    }
  }
  $activeTaskProperty = $Governance.PSObject.Properties['activeTaskId']
  $activeTaskId = [string](Get-LegadoOptionalProperty -Object $Governance -Name 'activeTaskId')
  # The governance task referenced by activeTaskId is the long-running parent
  # of the current active issue. Its running status is the expected state and
  # must not be reset as stale by per-source runner reinitialization.
  $activeTaskGuarded = $activeTaskId.Length -gt 0
  $recovered = 0
  if (-not $activeTaskGuarded) {
    $recovered = Reset-LegadoStaleStatus -Item $Governance -Scope 'governance' -RecoveredAt $RecoveredAt
  }
  if ($null -ne $activeTaskProperty -and $recovered -gt 0) {
    $activeTaskProperty.Value = ''
  }
  foreach ($task in @((Get-LegadoOptionalProperty -Object $Governance -Name 'tasks'))) {
    if ($activeTaskGuarded -and [string](Get-LegadoOptionalProperty -Object $task -Name 'id') -eq $activeTaskId) {
      continue
    }
    $recovered += Reset-LegadoStaleStatus -Item $task -Scope 'governance_task' -RecoveredAt $RecoveredAt
  }
  foreach ($issue in @((Get-LegadoOptionalProperty -Object $Governance -Name 'issues'))) {
    $recovered += Reset-LegadoStaleStatus -Item $issue -Scope 'governance_issue' -RecoveredAt $RecoveredAt
  }
  return [pscustomobject][ordered]@{
    governance = $Governance
    recovered = $recovered
  }
}

function Get-LegadoRecordedGovernanceRecoveryCount {
  param([object]$Governance)
  if ($null -eq $Governance) {
    return 0
  }
  $count = 0
  if ($null -ne (Get-LegadoOptionalProperty -Object $Governance -Name 'lastRecovery')) {
    $count++
  }
  foreach ($task in @((Get-LegadoOptionalProperty -Object $Governance -Name 'tasks'))) {
    if ($null -ne (Get-LegadoOptionalProperty -Object $task -Name 'lastRecovery')) {
      $count++
    }
  }
  foreach ($issue in @((Get-LegadoOptionalProperty -Object $Governance -Name 'issues'))) {
    if ($null -ne (Get-LegadoOptionalProperty -Object $issue -Name 'lastRecovery')) {
      $count++
    }
  }
  return $count
}

function Get-LegadoGovernanceForMigration {
  param([object]$ExistingState, [object]$LegacyGovernance)
  $canonicalGovernance = Get-LegadoOptionalProperty -Object $ExistingState -Name 'governance'
  if ($null -ne $canonicalGovernance) {
    return $canonicalGovernance
  }
  if ($null -eq $LegacyGovernance) {
    return $null
  }
  $isMachineFactSource = Get-LegadoOptionalProperty -Object $LegacyGovernance -Name 'isMachineFactSource'
  if ($isMachineFactSource -is [bool] -and -not [bool]$isMachineFactSource) {
    return $null
  }
  return [pscustomobject][ordered]@{
    status = [string](Get-LegadoOptionalProperty -Object $LegacyGovernance -Name 'status')
    activeTaskId = [string](Get-LegadoOptionalProperty -Object $LegacyGovernance -Name 'activeTaskId')
    tasks = @((Get-LegadoOptionalProperty -Object $LegacyGovernance -Name 'tasks'))
    uiAudit = Get-LegadoOptionalProperty -Object $LegacyGovernance -Name 'uiAudit'
    issues = @((Get-LegadoOptionalProperty -Object $LegacyGovernance -Name 'issues'))
  }
}

function Write-LegadoBlockedState {
  param(
    [string]$StatePath,
    [object]$ExistingState,
    [string]$Code,
    [string]$Expected,
    [string]$Actual
  )
  $now = [DateTimeOffset]::UtcNow.ToString('o')
  $state = $ExistingState
  if ($null -eq $state) {
    $state = [pscustomobject][ordered]@{
      schemaVersion = 2
      revision = '2026-07-31-v2-raw-document-state'
      generatedAt = $now
      machineFactSource = 'full-source-validation-state.json'
      baseline = [pscustomobject][ordered]@{}
      status = 'blocked'
      sources = @()
    }
  }
  $state | Add-Member -NotePropertyName 'status' -NotePropertyValue 'blocked' -Force
  $state | Add-Member -NotePropertyName 'generatedAt' -NotePropertyValue $now -Force
  $state | Add-Member -NotePropertyName 'block' -NotePropertyValue ([pscustomobject][ordered]@{
    code = $Code
    expected = $Expected
    actual = $Actual
    retryable = $false
    blockedAt = $now
  }) -Force
  Write-LegadoUtf8AtomicInternal -Path $StatePath -Content ([string]($state | ConvertTo-Json -Depth 30))
  throw "BLOCKED:$Code expected=$Expected actual=$Actual"
}

function Test-LegadoBaselineProperty {
  param([object]$State, [string]$PropertyName, [string]$ExpectedValue)
  if ($null -eq $State) {
    return $true
  }
  $baseline = Get-LegadoOptionalProperty -Object $State -Name 'baseline'
  if ($null -eq $baseline) {
    return $true
  }
  $actual = [string](Get-LegadoOptionalProperty -Object $baseline -Name $PropertyName)
  return $actual.Length -eq 0 -or $actual -eq $ExpectedValue
}

function Initialize-LegadoFullSourceState {
  param(
    [string]$SourcePackagePath,
    [string]$StatePath,
    [string]$LegacyGovernancePath,
    [string]$ExpectedPackageSha256,
    [int]$ExpectedSourceCount,
    [string]$LegadoCommit,
    [string]$ExpectedLegadoCommit
  )
  if (-not (Test-Path -LiteralPath $SourcePackagePath)) {
    throw 'The pinned source package does not exist.'
  }
  $lock = Enter-LegadoStateLock -StatePath $StatePath
  try {
    $existingState = Read-LegadoJsonFile -Path $StatePath
    $legacyGovernance = Read-LegadoJsonFile -Path $LegacyGovernancePath
    $packageBytes = [System.IO.File]::ReadAllBytes($SourcePackagePath)
    $packageSha256 = Get-LegadoSha256ForBytes -Bytes $packageBytes
    if ($packageSha256 -ne $ExpectedPackageSha256) {
      Write-LegadoBlockedState -StatePath $StatePath -ExistingState $existingState -Code 'SOURCE_PACKAGE_SHA256_MISMATCH' -Expected $ExpectedPackageSha256 -Actual $packageSha256
    }
    if ($LegadoCommit -ne $ExpectedLegadoCommit) {
      Write-LegadoBlockedState -StatePath $StatePath -ExistingState $existingState -Code 'LEGADO_COMMIT_MISMATCH' -Expected $ExpectedLegadoCommit -Actual $LegadoCommit
    }
    if (-not (Test-LegadoBaselineProperty -State $existingState -PropertyName 'sourcePackageSha256' -ExpectedValue $packageSha256)) {
      $actual = [string]$existingState.baseline.sourcePackageSha256
      Write-LegadoBlockedState -StatePath $StatePath -ExistingState $existingState -Code 'EXISTING_STATE_PACKAGE_MISMATCH' -Expected $packageSha256 -Actual $actual
    }
    if (-not (Test-LegadoBaselineProperty -State $existingState -PropertyName 'legadoCommit' -ExpectedValue $LegadoCommit)) {
      $actual = [string]$existingState.baseline.legadoCommit
      Write-LegadoBlockedState -StatePath $StatePath -ExistingState $existingState -Code 'EXISTING_STATE_LEGADO_COMMIT_MISMATCH' -Expected $LegadoCommit -Actual $actual
    }
    if (-not (Test-LegadoBaselineProperty -State $legacyGovernance -PropertyName 'sourcePackageSha256' -ExpectedValue $packageSha256)) {
      $actual = [string]$legacyGovernance.baseline.sourcePackageSha256
      Write-LegadoBlockedState -StatePath $StatePath -ExistingState $existingState -Code 'LEGACY_GOVERNANCE_PACKAGE_MISMATCH' -Expected $packageSha256 -Actual $actual
    }
    if (-not (Test-LegadoBaselineProperty -State $legacyGovernance -PropertyName 'legadoCommit' -ExpectedValue $LegadoCommit)) {
      $actual = [string]$legacyGovernance.baseline.legadoCommit
      Write-LegadoBlockedState -StatePath $StatePath -ExistingState $existingState -Code 'LEGACY_GOVERNANCE_LEGADO_COMMIT_MISMATCH' -Expected $LegadoCommit -Actual $actual
    }

    $packageText = $script:Utf8Strict.GetString($packageBytes)
    $sources = @(ConvertFrom-LegadoJsonArray -Json $packageText -Label 'pinned source package')
    $rawDocuments = @(Get-LegadoRawSourceDocuments -Json $packageText -Label 'pinned source package')
    if ($sources.Count -ne $ExpectedSourceCount -or $rawDocuments.Count -ne $ExpectedSourceCount) {
      Write-LegadoBlockedState -StatePath $StatePath -ExistingState $existingState -Code 'SOURCE_COUNT_MISMATCH' -Expected ([string]$ExpectedSourceCount) -Actual ("parsed={0};raw={1}" -f $sources.Count, $rawDocuments.Count)
    }

    $existingByIdentity = @{}
    $existingByOrdinal = @{}
    if ($null -ne $existingState) {
      foreach ($record in @((Get-LegadoOptionalProperty -Object $existingState -Name 'sources'))) {
        $identity = [string](Get-LegadoOptionalProperty -Object $record -Name 'sourceId')
        if ($identity.Length -ne 64) {
          $identity = [string](Get-LegadoOptionalProperty -Object $record -Name 'rawDocumentSha256')
        }
        if ($identity.Length -ne 64) {
          $identity = [string](Get-LegadoOptionalProperty -Object $record -Name 'sourceHash')
        }
        if ($identity.Length -eq 64) {
          $existingByIdentity[$identity] = $record
        }
        $ordinal = [string](Get-LegadoOptionalProperty -Object $record -Name 'ordinal')
        if ($ordinal -match '^\d+$') {
          $existingByOrdinal[$ordinal] = $record
        }
      }
    }

    $records = New-Object 'System.Collections.Generic.List[object]'
    $seenSourceIds = @{}
    $bucketCounts = [ordered]@{
      safe_text = 0
      js_text = 0
      interactive = 0
      audio = 0
      image = 0
      file = 0
      external = 0
    }
    for ($index = 0; $index -lt $sources.Count; $index++) {
      $record = New-LegadoSourceRecord -Source $sources[$index] -RawDocument $rawDocuments[$index] -Ordinal $index
      $sourceId = [string]$record.sourceId
      if ($seenSourceIds.ContainsKey($sourceId)) {
        Write-LegadoBlockedState -StatePath $StatePath -ExistingState $existingState -Code 'DUPLICATE_RAW_DOCUMENT_SHA256' -Expected 'unique' -Actual $sourceId
      }
      $seenSourceIds[$sourceId] = $true
      $existingRecord = $null
      if ($existingByIdentity.ContainsKey($sourceId)) {
        $existingRecord = $existingByIdentity[$sourceId]
      } elseif ($existingByOrdinal.ContainsKey([string]$index)) {
        $existingRecord = $existingByOrdinal[[string]$index]
      }
      Copy-LegadoRecordProgress -Existing $existingRecord -Target $record
      $bucketCounts[[string]$record.bucket] = [int]$bucketCounts[[string]$record.bucket] + 1
      [void]$records.Add($record)
    }

    $now = [DateTimeOffset]::UtcNow.ToString('o')
    $sourceRecoveryCount = Recover-LegadoSourceRecords -Records $records.ToArray() -RecoveredAt $now
    $governanceInput = Get-LegadoGovernanceForMigration -ExistingState $existingState -LegacyGovernance $legacyGovernance
    $governanceRecovery = Recover-LegadoGovernance -Governance $governanceInput -RecoveredAt $now
    $statusCounts = Get-LegadoStatusCounts -Records $records.ToArray()
    $governance = $governanceRecovery.governance
    $recordedSourceRecoveryCount = Get-LegadoRecordedSourceRecoveryCount -Records $records.ToArray()
    $recordedGovernanceRecoveryCount = Get-LegadoRecordedGovernanceRecoveryCount -Governance $governance
    $governance | Add-Member -NotePropertyName 'sourceValidation' -NotePropertyValue (Get-LegadoSourceValidationSummary -StatusCounts $statusCounts) -Force
    $existingDeviceQualification = Get-LegadoOptionalProperty -Object $existingState -Name 'devicePersistedQualification'
    $deviceQualification = if ($null -eq $existingDeviceQualification) {
      New-LegadoDevicePersistedQualification -SourceCount $sources.Count
    } else {
      # Per-source runners reinitialize the canonical ledger before each
      # dispatch. Preserve the last independently observed device aggregate,
      # after validating it against the current immutable source count.
      Get-LegadoDevicePersistedQualificationSummary `
        -Qualification $existingDeviceQualification `
        -ExpectedSourceCount $sources.Count
    }

    $firstPending = @($records.ToArray() | Where-Object { [string]$_.status -in @('planned', 'failed') } | Select-Object -First 1)
    $cursorOrdinal = if ($firstPending.Count -gt 0) { [int]$firstPending[0].ordinal } else { $records.Count }
    $cursorSourceId = if ($firstPending.Count -gt 0) { [string]$firstPending[0].sourceId } else { '' }
    $overallStatus = 'planned'
    $unfinishedCount = [int]$statusCounts.planned + [int]$statusCounts.running +
      [int]$statusCounts.verifying + [int]$statusCounts.failed
    if ([int]$statusCounts.blocked -gt 0) {
      $overallStatus = 'blocked'
    } elseif ($unfinishedCount -eq 0) {
      $overallStatus = 'passed'
    }
    $state = [pscustomobject][ordered]@{
      schemaVersion = 2
      revision = '2026-07-31-v2-raw-document-state'
      generatedAt = $now
      machineFactSource = 'full-source-validation-state.json'
      baseline = [pscustomobject][ordered]@{
        sourcePackageSha256 = $packageSha256
        sourceCount = $sources.Count
        legadoCommit = $LegadoCommit
        sourceIdentity = 'sha256(utf8(rawTopLevelJsonObjectWithoutBom))'
      }
      status = $overallStatus
      block = $null
      recovery = [pscustomobject][ordered]@{
        recoveredAt = $now
        staleSourceAndWorkflowCount = $sourceRecoveryCount
        staleGovernanceCount = [int]$governanceRecovery.recovered
        recordedSourceAndWorkflowRecoveryCount = $recordedSourceRecoveryCount
        recordedGovernanceRecoveryCount = $recordedGovernanceRecoveryCount
      }
      cursor = [pscustomobject][ordered]@{
        ordinal = $cursorOrdinal
        sourceId = $cursorSourceId
      }
      bucketCounts = [pscustomobject]$bucketCounts
      statusCounts = [pscustomobject]$statusCounts
      devicePersistedQualification = $deviceQualification
      governance = $governance
      sources = $records.ToArray()
    }
    Write-LegadoUtf8AtomicInternal -Path $StatePath -Content ([string]($state | ConvertTo-Json -Depth 30))

    if ($LegacyGovernancePath.Length -gt 0) {
      $pointer = [pscustomobject][ordered]@{
        schemaVersion = 2
        revision = '2026-07-31-migrated-pointer'
        generatedAt = $now
        isMachineFactSource = $false
        canonicalStatePath = [System.IO.Path]::GetFileName($StatePath)
        baseline = $state.baseline
      }
      Write-LegadoUtf8AtomicInternal -Path $LegacyGovernancePath -Content ([string]($pointer | ConvertTo-Json -Depth 6))
    }
    return $state
  } finally {
    $lock.Dispose()
  }
}

Export-ModuleMember -Function @(
  'ConvertFrom-LegadoJsonArray',
  'Get-LegadoRawSourceDocuments',
  'Get-LegadoSha256ForBytes',
  'Get-LegadoSha256ForText',
  'Initialize-LegadoFullSourceState',
  'Read-LegadoJsonFile',
  'Sync-LegadoStateDerivedFields',
  'Test-LegadoRawHashMatch',
  'Write-LegadoStateCheckpoint'
)
