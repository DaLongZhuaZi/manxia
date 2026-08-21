[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/r3-java-string-list-233-to-jsoup-regex-234-idempotent-recovery-20260808/registration-recovery.json'
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
  throw 'recovery evidence must remain under the evidence directory.'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Assert-Recovery {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "234 transition recovery blocked: $Message" }
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

function Read-StrictJson {
  param([string]$Path)
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

function Get-FileDigest {
  param([string]$Path)
  return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function Write-AtomicJson {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 24), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$objectivePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\refactor-objective.json'
$registerScript = Join-Path $RepositoryRoot 'tools\legado-compat\Register-LegadoR3JsoupRegex234Transition.ps1'
$result = $null
$exitCode = 0
try {
  $stateBefore = Read-StrictJson -Path $statePath
  $objectiveBefore = Read-StrictJson -Path $objectivePath
  $stateDigestBefore = Get-FileDigest -Path $statePath
  $objectiveDigestBefore = Get-FileDigest -Path $objectivePath
  $issueBefore = Get-Issue -Issues @($stateBefore.governance.issues) -Id 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
  Assert-Recovery ($null -ne $issueBefore) '234 governance issue is missing.'
  $attemptsBefore = [int]$issueBefore.attempts

  $registrationOutput = (& pwsh -NoLogo -NoProfile -File $registerScript -RepositoryRoot $RepositoryRoot 2>&1 | Out-String).Trim()
  $registrationExitCode = $LASTEXITCODE
  Assert-Recovery ($registrationExitCode -eq 0) "registration script exited with $registrationExitCode."
  $registrationResult = $registrationOutput | ConvertFrom-Json
  Assert-Recovery ([string]$registrationResult.status -eq 'already_registered' -and [bool]$registrationResult.idempotent) 'registration script did not take the idempotent path.'
  Assert-Recovery (-not [bool]$registrationResult.semanticMatchAllowed -and @($registrationResult.runtimeActionsPerformed).Count -eq 0) 'idempotent recovery reported runtime activity or semantic match.'
  Add-Check -Id 'idempotent_registration' -Detail 'A post-transition registration replay returns already_registered without changing the queue.' -Evidence @('tools/legado-compat/Register-LegadoR3JsoupRegex234Transition.ps1','tools/legado-compat/evidence/r3-java-string-list-233-to-jsoup-regex-234-post-transition-20260808/registration.json')

  $stateAfter = Read-StrictJson -Path $statePath
  $objectiveAfter = Read-StrictJson -Path $objectivePath
  $stateDigestAfter = Get-FileDigest -Path $statePath
  $objectiveDigestAfter = Get-FileDigest -Path $objectivePath
  $issueAfter = Get-Issue -Issues @($stateAfter.governance.issues) -Id 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
  Assert-Recovery ($stateDigestBefore -eq $stateDigestAfter -and $objectiveDigestBefore -eq $objectiveDigestAfter) 'idempotent replay changed machine state or objective bytes.'
  Assert-Recovery ([int]$issueAfter.attempts -eq $attemptsBefore) 'idempotent replay incremented the 234 attempt counter.'
  Assert-Recovery ([string]$stateAfter.governance.activeTaskId -eq 'COMPAT-006' -and [string]$stateAfter.governance.activeIssueId -eq 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR') 'active queue changed during recovery.'
  Assert-Recovery ([string]$objectiveAfter.authority.activeIssueId -eq 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR' -and [string]$objectiveAfter.executionTarget.currentIssue -eq 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR') 'objective queue changed during recovery.'
  Add-Check -Id 'state_unchanged' -Detail 'State/objective SHA-256 and the 234 attempt counter remain unchanged after replay.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json','tools/legado-compat/state/refactor-objective.json')

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_java_string_list_233_to_jsoup_regex_234_transition_registration_idempotency'
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
    kind = 'legado_r3_java_string_list_233_to_jsoup_regex_234_transition_registration_idempotency'
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
$result | ConvertTo-Json -Depth 24
if ($exitCode -ne 0) { exit $exitCode }
