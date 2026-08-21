[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/r3-java-object-237-to-238-transition-20260809/registration-idempotency.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:checks = New-Object 'System.Collections.Generic.List[object]'
$script:assertions = 0

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "required JSON is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  try { return ($strictUtf8.GetString($bytes) | ConvertFrom-Json) }
  catch { throw "invalid JSON: $Path; $($_.Exception.Message)" }
}

function Get-Issue {
  param([object[]]$Issues, [Parameter(Mandatory = $true)][string]$Id)
  foreach ($issue in $Issues) { if ([string]$issue.id -eq $Id) { return $issue } }
  return $null
}

function Assert-Check {
  param([bool]$Condition, [Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][string]$Detail, [string[]]$Evidence = @())
  if (-not $Condition) { throw "238 registration replay blocked: $Detail" }
  $script:assertions++
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) })
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 70), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$outputFullPath = [System.IO.Path]::GetFullPath((Get-RepoPath -RelativePath $OutputPath))
$evidenceRoot = [System.IO.Path]::GetFullPath((Get-RepoPath -RelativePath 'tools/legado-compat/evidence')).TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidenceRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'idempotency output must remain under evidence.' }

$statePath = Get-RepoPath -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = Get-RepoPath -RelativePath 'tools/legado-compat/state/refactor-objective.json'
$registerScript = Get-RepoPath -RelativePath 'tools/legado-compat/Register-LegadoR3Index237ToJavaObject238Transition.ps1'
$stateBefore = $null
$objectiveBefore = $null
$result = $null
$exitCode = 0
try {
  $stateBefore = Read-StrictJson -Path $statePath
  $objectiveBefore = Read-StrictJson -Path $objectivePath
  $stateDigestBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $statePath).Hash
  $objectiveDigestBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $objectivePath).Hash
  $issueBefore = Get-Issue -Issues @($stateBefore.governance.issues) -Id 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD'
  Assert-Check ($null -ne $issueBefore) 'issue_present' '238 governance issue exists.' @('tools/legado-compat/state/full-source-validation-state.json')
  $attemptsBefore = [int]$issueBefore.attempts

  $registrationOutput = (& pwsh -NoLogo -NoProfile -NonInteractive -File $registerScript -RepositoryRoot $RepositoryRoot 2>&1 | Out-String).Trim()
  $registrationExitCode = $LASTEXITCODE
  Assert-Check ($registrationExitCode -eq 0) 'registration_exit' ('registration replay exited with ' + $registrationExitCode) @('tools/legado-compat/Register-LegadoR3Index237ToJavaObject238Transition.ps1')
  $registrationResult = $registrationOutput | ConvertFrom-Json
  Assert-Check ([string]$registrationResult.status -eq 'already_registered' -and [bool]$registrationResult.idempotent -and [string]$registrationResult.issueId -eq 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD') 'already_registered' 'replay used the post-registration branch for 238.' @('tools/legado-compat/Register-LegadoR3Index237ToJavaObject238Transition.ps1')
  Assert-Check (-not [bool]$registrationResult.semanticMatchAllowed -and @($registrationResult.runtimeActionsPerformed).Count -eq 0) 'static_only' 'replay made no runtime or semantic-match claim.' @('tools/legado-compat/Register-LegadoR3Index237ToJavaObject238Transition.ps1')

  $stateAfter = Read-StrictJson -Path $statePath
  $objectiveAfter = Read-StrictJson -Path $objectivePath
  $stateDigestAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath $statePath).Hash
  $objectiveDigestAfter = (Get-FileHash -Algorithm SHA256 -LiteralPath $objectivePath).Hash
  $issueAfter = Get-Issue -Issues @($stateAfter.governance.issues) -Id 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD'
  Assert-Check ($stateDigestBefore -eq $stateDigestAfter -and $objectiveDigestBefore -eq $objectiveDigestAfter) 'state_unchanged' 'state and objective SHA-256 remain unchanged after replay.' @('tools/legado-compat/state/full-source-validation-state.json', 'tools/legado-compat/state/refactor-objective.json')
  Assert-Check ($null -ne $issueAfter -and [int]$issueAfter.attempts -eq $attemptsBefore) 'attempt_unchanged' '238 attempt count remains unchanged after replay.' @('tools/legado-compat/state/full-source-validation-state.json')
  Assert-Check ([string]$stateAfter.governance.activeTaskId -eq 'COMPAT-006' -and [string]$stateAfter.governance.activeIssueId -eq 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD') 'queue_unchanged' 'active machine queue remains on 238.' @('tools/legado-compat/state/full-source-validation-state.json')
  Assert-Check ([string]$objectiveAfter.authority.activeIssueId -eq 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD' -and [string]$objectiveAfter.executionTarget.currentIssue -eq 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD' -and @($objectiveAfter.executionTarget.nextIssues).Count -eq 0) 'objective_unchanged' 'objective queue remains on 238 with no parallel candidate.' @('tools/legado-compat/state/refactor-objective.json')

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_java_object_237_to_238_transition_registration_idempotency'
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
    verificationPolicy = 'static_registration_recovery_only;238_verifying;R4_runtime_build_device_and_legado_diff_deferred'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_java_object_237_to_238_transition_registration_idempotency'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'static_registration_recovery_only;238_verifying;R4_runtime_build_device_and_legado_diff_deferred'
  }
}

Write-AtomicJson -Path $outputFullPath -Value $result
$result | ConvertTo-Json -Depth 70
if ($exitCode -ne 0) { exit $exitCode }
