[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/r3-jsoup-text-pseudo-235-to-has-236-transition-20260809/registration-idempotency.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$outputFullPath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot ($OutputPath.Replace('/', '\'))))
$evidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidenceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'idempotency evidence must remain under the evidence directory.'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "required JSON is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  try { return ($strictUtf8.GetString($bytes) | ConvertFrom-Json) }
  catch { throw "invalid JSON: $Path; $($_.Exception.Message)" }
}

function Get-Issue {
  param([object[]]$Issues, [string]$Id)
  foreach ($issue in $Issues) {
    if ([string]$issue.id -eq $Id) { return $issue }
  }
  return $null
}

function Assert-Recovery {
  param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @())
  if (-not $Condition) { throw "236 transition recovery blocked: $Detail" }
  $script:assertions++
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) })
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 40), [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$objectivePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\refactor-objective.json'
$registerScript = Join-Path $RepositoryRoot 'tools\legado-compat\Register-LegadoR3TextPseudo235ToHas236Transition.ps1'
$result = $null
$exitCode = 0
try {
  $stateBefore = Read-StrictJson -Path $statePath
  $objectiveBefore = Read-StrictJson -Path $objectivePath
  $stateDigestBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $statePath).Hash
  $objectiveDigestBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $objectivePath).Hash
  $issueBefore = Get-Issue -Issues @($stateBefore.governance.issues) -Id 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR'
  Assert-Recovery ($null -ne $issueBefore) 'issue_present' '236 governance issue exists.' @('tools/legado-compat/state/full-source-validation-state.json')
  $attemptsBefore = [int]$issueBefore.attempts

  $registrationOutput = (& pwsh -NoLogo -NoProfile -NonInteractive -File $registerScript -RepositoryRoot $RepositoryRoot 2>&1 | Out-String).Trim()
  $registrationExitCode = $LASTEXITCODE
  Assert-Recovery ($registrationExitCode -eq 0) 'registration_exit' ('registration replay exited with ' + $registrationExitCode) @('tools/legado-compat/Register-LegadoR3TextPseudo235ToHas236Transition.ps1')
  $registrationResult = $registrationOutput | ConvertFrom-Json
  Assert-Recovery ([string]$registrationResult.status -eq 'already_registered' -and [bool]$registrationResult.idempotent) 'already_registered' 'replay used the post-registration branch.' @('tools/legado-compat/Register-LegadoR3TextPseudo235ToHas236Transition.ps1')
  Assert-Recovery (-not [bool]$registrationResult.semanticMatchAllowed -and @($registrationResult.runtimeActionsPerformed).Count -eq 0) 'static_only' 'replay made no runtime or semantic-match claim.' @('tools/legado-compat/Register-LegadoR3TextPseudo235ToHas236Transition.ps1')

  $stateAfter = Read-StrictJson -Path $statePath
  $objectiveAfter = Read-StrictJson -Path $objectivePath
  $stateDigestAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath $statePath).Hash
  $objectiveDigestAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath $objectivePath).Hash
  $issueAfter = Get-Issue -Issues @($stateAfter.governance.issues) -Id 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR'
  Assert-Recovery ($stateDigestBefore -eq $stateDigestAfter -and $objectiveDigestBefore -eq $objectiveDigestAfter) 'state_unchanged' 'state and objective SHA-256 remain unchanged after replay.' @('tools/legado-compat/state/full-source-validation-state.json','tools/legado-compat/state/refactor-objective.json')
  Assert-Recovery ($null -ne $issueAfter -and [int]$issueAfter.attempts -eq $attemptsBefore) 'attempt_unchanged' '236 attempt count remains unchanged after replay.' @('tools/legado-compat/state/full-source-validation-state.json')
  Assert-Recovery ([string]$stateAfter.governance.activeTaskId -eq 'COMPAT-006' -and [string]$stateAfter.governance.activeIssueId -eq 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR') 'queue_unchanged' 'active machine queue remains on 236.' @('tools/legado-compat/state/full-source-validation-state.json')
  Assert-Recovery ([string]$objectiveAfter.authority.activeIssueId -eq 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR' -and [string]$objectiveAfter.executionTarget.currentIssue -eq 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR') 'objective_unchanged' 'objective queue remains on 236.' @('tools/legado-compat/state/refactor-objective.json')

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_text_pseudo_235_to_has_236_transition_registration_idempotency'
    status = 'passed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    objectiveId = [string]$objectiveAfter.objectiveId
    targetRevision = [string]$objectiveAfter.targetRevision
    baseline = [pscustomobject][ordered]@{ sourceCount = [int]$stateAfter.baseline.sourceCount; sourcePackageSha256 = [string]$stateAfter.baseline.sourcePackageSha256; legadoCommit = [string]$stateAfter.baseline.legadoCommit }
    activeIssueId = [string]$stateAfter.governance.activeIssueId
    attemptsBefore = $attemptsBefore
    attemptsAfter = [int]$issueAfter.attempts
    stateSha256Before = $stateDigestBefore
    stateSha256After = $stateDigestAfter
    objectiveSha256Before = $objectiveDigestBefore
    objectiveSha256After = $objectiveDigestAfter
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'static_registration_recovery_only;R4_runtime_build_device_and_legado_diff_deferred'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_text_pseudo_235_to_has_236_transition_registration_idempotency'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'static_registration_recovery_only;R4_runtime_build_device_and_legado_diff_deferred'
  }
}

Write-AtomicJson -Path $outputFullPath -Value $result
$result | ConvertTo-Json -Depth 40
if ($exitCode -ne 0) { exit $exitCode }
