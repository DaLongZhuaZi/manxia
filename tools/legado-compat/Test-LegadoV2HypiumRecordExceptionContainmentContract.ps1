[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$FixturePath = '',
  [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepoRoot)) { $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
if ([string]::IsNullOrWhiteSpace($FixturePath)) { $FixturePath = Join-Path $RepoRoot 'tools\legado-compat\fixtures\hypium-record-exception-containment.json' }
if ([string]::IsNullOrWhiteSpace($ResultPath)) { $ResultPath = Join-Path $RepoRoot 'tools\legado-compat\evidence\v2-harness-023-record-exception-containment-contract-20260808.json' }

$assertions = 0
function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Hypium record exception containment contract failed: $Message" }
  $script:assertions++
}

function Invoke-FallbackBuilderFixture {
  param(
    [Parameter(Mandatory = $true)][string]$FunctionText,
    [Parameter(Mandatory = $true)][string]$ActivityFunctionText
  )
  $temporaryRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('legado-v2-fallback-builder-' + [Guid]::NewGuid().ToString('N'))
  [void][System.IO.Directory]::CreateDirectory($temporaryRoot)
  try {
    $EvidenceDirectory = $temporaryRoot
    $ExecutionProfile = 'full_workflow'
    $script:RunId = 'fixture-fallback-run'
    $script:ExpectedSourcePackageSha256 = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
    $script:ExpectedLegadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'

    function Get-HypiumTextProperty {
      param([object]$Object, [string]$Name)
      if ($null -eq $Object) { return '' }
      $property = $Object.PSObject.Properties[$Name]
      if ($null -eq $property -or $null -eq $property.Value) { return '' }
      return [string]$property.Value
    }
    function Get-HypiumSafeToken {
      param([string]$Value, [string]$Fallback = 'unclassified')
      $candidate = if ($null -eq $Value) { '' } else { $Value.Trim().ToLowerInvariant() }
      if ($candidate -match '^[a-z0-9_:-]{1,80}$') { return $candidate }
      return $Fallback
    }
    function Get-HypiumNow { return '2026-08-08T00:00:00.0000000Z' }
    function Get-HypiumFallbackInt {
      param([object]$Object, [string]$Name)
      $raw = Get-HypiumTextProperty -Object $Object -Name $Name
      try { return [int]$raw } catch { return 0 }
    }
    function ConvertTo-LegadoHypiumEvidenceRelativePath {
      param([string]$ScriptRoot, [string]$Path)
      return [System.IO.Path]::GetFileName($Path)
    }
    function Get-LegadoSha256ForText {
      param([string]$Value)
      $sha = [System.Security.Cryptography.SHA256]::Create()
      try {
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Value)
        return ([System.BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
      } finally { $sha.Dispose() }
    }
    function Write-HypiumJsonAtomically {
      param([string]$Path, [object]$Value)
      $json = $Value | ConvertTo-Json -Depth 24
      [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
    }

    Invoke-Expression $FunctionText
    $workflowData = [ordered]@{
      search = [pscustomobject][ordered]@{ status = 'failed'; lastOutcome = 'record_harness_exception'; attempts = 2 }
      explore = [pscustomobject][ordered]@{ status = 'blocked'; lastOutcome = 'explore_reference_pending'; attempts = 1 }
      bookInfo = [pscustomobject][ordered]@{ status = 'failed'; lastOutcome = 'record_harness_exception'; attempts = 3 }
      toc = [pscustomobject][ordered]@{ status = 'failed'; lastOutcome = 'record_harness_exception'; attempts = 0 }
      content = [pscustomobject][ordered]@{ status = 'unsupported_api'; lastOutcome = 'content_consumer_missing'; attempts = 4 }
      file = [pscustomobject][ordered]@{ status = 'policy_blocked'; lastOutcome = 'file_workflow_not_declared'; attempts = 0 }
      review = [pscustomobject][ordered]@{ status = 'needs_interaction'; lastOutcome = 'interactive_review_required'; attempts = 2 }
    }
    $record = [pscustomobject][ordered]@{
      sourceId = 'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789'
      ordinal = 17
      workflows = [pscustomobject]$workflowData
    }
    $output = Write-HypiumSourceFallbackEvidence -Record $record -ErrorDigest ('a' * 64)
    $evidence = Get-Content -LiteralPath ([string]$output.path) -Raw -Encoding UTF8 | ConvertFrom-Json
    $outputExists = Test-Path -LiteralPath ([string]$output.path) -PathType Leaf
    $RunActivityPath = Join-Path $temporaryRoot 'run-activity.json'
    Invoke-Expression $ActivityFunctionText
    Write-HypiumRunActivity -Status 'running' -Phase 'source_evidence_fallback_written' -Ordinal 17 -SourceId ([string]$record.sourceId) -Outcome 'source_evidence_fallback_written' -EvidencePath ([string]$output.relativePath)
    Write-HypiumRunActivity -Status 'running' -Phase 'source_settled' -Ordinal 17 -SourceId ([string]$record.sourceId) -Outcome 'record_harness_exception'
    $activity = Get-Content -LiteralPath $RunActivityPath -Raw -Encoding UTF8 | ConvertFrom-Json
    return [pscustomobject][ordered]@{ output = $output; evidence = $evidence; outputExists = $outputExists; activity = $activity }
  } finally {
    if (Test-Path -LiteralPath $temporaryRoot) { Remove-Item -LiteralPath $temporaryRoot -Recurse -Force }
  }
}

try {
  $runnerPath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1'
  $auditPath = Join-Path $RepoRoot 'tools\legado-compat\Test-LegadoV2HypiumFullSourceEvidence.ps1'
  $runnerText = [System.IO.File]::ReadAllText($runnerPath, [System.Text.UTF8Encoding]::new($false, $true))
  $auditText = [System.IO.File]::ReadAllText($auditPath, [System.Text.UTF8Encoding]::new($false, $true))
  $fixture = [System.IO.File]::ReadAllText($FixturePath, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
  $start = $runnerText.IndexOf('function Invoke-HypiumRecord', [System.StringComparison]::Ordinal)
  $end = $runnerText.IndexOf("`n}`n`ntry {", $start, [System.StringComparison]::Ordinal)
  $body = if ($start -ge 0 -and $end -gt $start) { $runnerText.Substring($start, $end - $start) } else { '' }

  Assert-Contract ($fixture.contract -eq 'hypium_record_exception_containment') 'fixture contract must identify record containment'
  Assert-Contract (@($fixture.workflowNames).Count -eq 7) 'fixture must cover all seven workflows'
  Assert-Contract ($body.Contains('try {') -and $body.Contains('} catch {')) 'Invoke-HypiumRecord must isolate unexpected record exceptions'
  Assert-Contract ($body.Contains("'record_harness_exception'")) 'record exception must have a stable outcome'
  Assert-Contract ($body.Contains("'v2_hypium_record_exception'")) 'record exception must have a stable execution profile'
  Assert-Contract ($body.Contains("'harness_or_engine_failure'")) 'record exception must have an explicit semantic qualification'
  Assert-Contract ($body.Contains("Set-HypiumWorkflow -State `$State -Record `$Record -Name `$name -Status 'failed' -Outcome 'record_harness_exception'")) 'planned/running workflows must be settled as failed'
  Assert-Contract ($body.Contains('Write-HypiumSourceEvidence -Record $Record -Attempt $failureAttempt')) 'record exception must still write source evidence'
  Assert-Contract ($body.Contains("processClassification = 'record_exception'")) 'record exception must be classified in evidence'
  Assert-Contract ($body.Contains('$script:ResultSummary.Add')) 'record exception must return control to the batch summary'
  Assert-Contract ([bool]$fixture.afterFix.batchContinuation) 'fixture must require batch continuation'
  Assert-Contract ($runnerText.Contains('function Write-HypiumSourceFallbackEvidence')) 'fallback evidence writer must exist'
  Assert-Contract ($runnerText.Contains("evidenceKind = 'source_fallback'")) 'fallback evidence must have an explicit kind'
  Assert-Contract ($runnerText.Contains("fallbackReason = 'source_evidence_write_failed'")) 'fallback evidence must preserve the primary writer failure'
  Assert-Contract ($runnerText.Contains('source-{0}.fallback.json')) 'fallback evidence must use a distinct source file'
  Assert-Contract ($runnerText.Contains('Write-HypiumJsonAtomically -Path $path -Value $evidence')) 'fallback evidence must be atomically written'
  Assert-Contract ($runnerText.Contains('-EvidencePath ([string]$fallbackEvidence.relativePath)')) 'activity must bind a successful fallback path'
  Assert-Contract ([bool]$fixture.fallbackEvidence.runScoped) 'fallback evidence must remain run scoped'
  Assert-Contract ([bool]$fixture.fallbackEvidence.atomic) 'fallback evidence must be atomic'
  Assert-Contract ([bool]$fixture.fallbackEvidence.workflowMatrixClosed) 'fallback evidence must close all workflows'
  Assert-Contract ([string]$fixture.fallbackEvidence.activityPathField -eq 'evidencePath') 'activity must expose fallback evidence path'
  Assert-Contract ([bool]$fixture.fallbackEvidence.batchContinuation) 'fallback write handling must preserve batch continuation'
  Assert-Contract ($auditText.Contains("'SOURCE_EVIDENCE_FALLBACK'")) 'source evidence audit must classify fallback artifacts explicitly'
  Assert-Contract ([string]$fixture.primaryWriteFailure.operation -eq 'full_source_evidence_writer') 'fixture must model the primary source writer failure'
  Assert-Contract ([bool]$fixture.primaryWriteFailure.fallbackExpected -and [string]$fixture.primaryWriteFailure.activityOutcome -eq 'source_evidence_fallback_written') 'primary writer failure must require a bound fallback activity'
  Assert-Contract ($runnerText.Contains('previousEvidencePath') -and $runnerText.Contains('boundEvidencePath')) 'activity writer must preserve an existing evidence binding when a later update omits the path'
  Assert-Contract ([string]$fixture.activityBindingPersistence.fallbackPhase -eq 'source_evidence_fallback_written' -and [string]$fixture.activityBindingPersistence.subsequentPhase -eq 'source_settled' -and [bool]$fixture.activityBindingPersistence.subsequentEvidencePathEmpty) 'fixture must model the later empty-path activity update'
  Assert-Contract ([bool]$fixture.activityBindingPersistence.preserveEvidencePath) 'fixture must require evidence path persistence'

  $errors = $null
  $tokens = $null
  $runnerAst = [System.Management.Automation.Language.Parser]::ParseFile($runnerPath, [ref]$tokens, [ref]$errors)
  Assert-Contract (@($errors).Count -eq 0) 'runner must remain syntactically valid'
  $fallbackAst = @($runnerAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-HypiumSourceFallbackEvidence' }, $true))
  Assert-Contract ($fallbackAst.Count -eq 1) 'fallback writer AST must be discoverable'
  $activityAst = @($runnerAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-HypiumRunActivity' }, $true))
  Assert-Contract ($activityAst.Count -eq 1) 'activity writer AST must be discoverable'
  $fallbackProjection = Invoke-FallbackBuilderFixture -FunctionText ([string]$fallbackAst[0].Extent.Text) -ActivityFunctionText ([string]$activityAst[0].Extent.Text)
  $fallbackOutput = $fallbackProjection.output
  $fallbackEvidence = $fallbackProjection.evidence
  Assert-Contract ([bool]$fallbackProjection.outputExists) 'fallback writer must create an evidence file before cleanup'
  Assert-Contract ([string]$fallbackEvidence.evidenceKind -eq 'source_fallback') 'functional fallback must publish its evidence kind'
  Assert-Contract ([string]$fallbackEvidence.sourceId -eq 'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789') 'functional fallback must preserve the source identity'
  Assert-Contract ([string]$fallbackEvidence.fallbackReason -eq 'source_evidence_write_failed') 'functional fallback must retain the primary writer failure reason'
  Assert-Contract ([string]$fallbackOutput.relativePath -eq 'source-ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789.fallback.json') 'functional fallback path must remain run scoped and source bound'
  $matrix = $fallbackEvidence.workflowStatusMatrix
  $matrixNames = @($matrix.PSObject.Properties.Name)
  Assert-Contract ($matrixNames.Count -eq 7 -and @($fixture.workflowNames | Where-Object { $matrixNames -notcontains $_ }).Count -eq 0) 'functional fallback matrix must contain all seven workflows'
  Assert-Contract (@($matrix.PSObject.Properties | Where-Object { [string]$_.Value.status -eq 'failed' }).Count -eq 3 -and [string]$matrix.explore.status -eq 'blocked' -and [string]$matrix.content.status -eq 'unsupported_api' -and [string]$matrix.file.status -eq 'policy_blocked' -and [string]$matrix.review.status -eq 'needs_interaction') 'functional fallback must preserve terminal workflow classifications'
  $resultNames = @($fallbackEvidence.workflowResults.PSObject.Properties.Name)
  Assert-Contract ($resultNames.Count -eq 7 -and @($fallbackEvidence.workflowResults.PSObject.Properties | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.Value) }).Count -eq 0) 'functional fallback results must be non-empty and closed'
  Assert-Contract ([int]$fallbackEvidence.sourceAttempt -eq 4) 'functional fallback source attempt must equal the workflow maximum'
  Assert-Contract ([int]$fallbackEvidence.sourceAttemptEvidence.sourceAttempt -eq 4) 'functional fallback attempt evidence must bind the source attempt'
  $attemptMismatches = @($fallbackEvidence.sourceAttemptEvidence.workflowAttempts.PSObject.Properties | Where-Object {
    $matrixProperty = $matrix.PSObject.Properties[$_.Name]
    $null -eq $matrixProperty -or [int]$_.Value -ne [int]$matrixProperty.Value.attempts
  })
  Assert-Contract ($attemptMismatches.Count -eq 0) 'functional fallback attempt evidence must match the matrix'
  Assert-Contract ([string]$fallbackEvidence.errorDigest -eq ('a' * 64)) 'functional fallback must retain only the supplied digest'
  Assert-Contract ([string]$fallbackEvidence.primaryEvidencePath -eq 'source-ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789.json') 'functional fallback must point to the primary source path'
  Assert-Contract ([string]$fallbackProjection.activity.phase -eq 'source_settled') 'functional activity must record the later source settlement phase'
  Assert-Contract ([string]$fallbackProjection.activity.evidencePath -eq [string]$fallbackOutput.relativePath) 'functional activity must preserve the fallback evidence path after an empty-path update'

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'passed'
    contract = [string]$fixture.contract
    assertions = $assertions
    failureMode = [string]$fixture.trigger.strictModeFailure
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'failed'
    contract = 'hypium_record_exception_containment'
    assertions = $assertions
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
}

$directory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
[System.IO.File]::WriteAllText($ResultPath, [string]($result | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') { exit 1 }
