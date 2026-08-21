[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$state = Get-Content -LiteralPath $statePath -Raw -Encoding utf8 | ConvertFrom-Json
$issueId = 'ISSUE-COMPAT-231-JAVA-JSONPATH-V2-RUNTIME'
$issue = [pscustomobject][ordered]@{
  id = $issueId
  taskId = 'COMPAT-006'
  status = 'in_progress'
  severity = 'P0'
  attempts = 2
  summary = 'Default V2 Runtime java.getString/getStringList lacked Legado JSONPath traversal. Runtime now covers scalar, wildcard, index, slice, recursive descent, &&/||/%% composition and ## replacement; all 60 affected sources are mapped to deterministic fixture coverage, while fresh Android reference differential remains blocked.'
  closeCondition = 'Fresh pinned-Legado Android instrumentation validates the JSONPath witness; then affected equivalence set, deterministic 458-source Harness, and same-input Legado differential pass without semantic gaps.'
  evidencePaths = @(
    'tools/legado-compat/evidence/full-source-v2-hypium-device/hypium-4B33C6BA1A7DC3AA12EFF8FA54B529A7B6510E692892093A38D98A15544119B1-explore-attempt-17/result.json',
    'tools/legado-compat/evidence/full-source-v2-hypium-device/hypium-4B33C6BA1A7DC3AA12EFF8FA54B529A7B6510E692892093A38D98A15544119B1-explore-attempt-18/result.json',
    'tools/legado-compat/evidence/full-source-v2-hypium-device/source-4B33C6BA1A7DC3AA12EFF8FA54B529A7B6510E692892093A38D98A15544119B1.json',
    'tools/legado-compat/evidence/legado-jsonpath-runtime-affected-source-set-20260807.json',
    'tools/legado-compat/evidence/legado-jsonpath-runtime-execution-20260807.json',
    'tools/legado-compat/evidence/legado-jsonpath-runtime-extended-execution-20260807.json',
    'tools/legado-compat/evidence/legado-jsonpath-runtime-equivalence-matrix-20260807.json',
    'tools/legado-compat/Test-LegadoJsonPathRuntimeAffectedSetContract.ps1',
    'tools/legado-compat/fixtures/legado-jsonpath-bridge.json',
    'tools/legado-compat/Test-LegadoJsonPathBridgeContract.ps1',
    'tools/legado-compat/Test-LegadoJsonPathRuntimeFixture.ps1',
    'tools/legado-compat/Test-LegadoJsonPathRuntimeExtendedFixture.ps1',
    'legado/app/src/androidTest/java/io/legado/app/compat/LegadoJsonPathReferenceTest.kt'
  )
  lastUpdatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'")
}

$governance = $state.governance
$issues = New-Object 'System.Collections.Generic.List[object]'
$found = $false
foreach ($existing in @($governance.issues)) {
  if ([string]$existing.id -eq $issueId) {
    if (-not $found) { [void]$issues.Add($issue); $found = $true }
  } else {
    [void]$issues.Add($existing)
  }
}
if (-not $found) { [void]$issues.Add($issue) }

$referenceIssueId = 'ISSUE-AUTO-028'
$referenceIssueUpdated = $false
$updatedIssues = New-Object 'System.Collections.Generic.List[object]'
foreach ($existing in @($issues.ToArray())) {
  if ([string]$existing.id -ne $referenceIssueId) {
    [void]$updatedIssues.Add($existing)
    continue
  }
  $attempts = [int]$existing.attempts + 1
  [void]$updatedIssues.Add([pscustomobject][ordered]@{
    id = $referenceIssueId
    severity = 'P1'
    taskId = 'AUTO-028'
    status = 'blocked'
    attempts = $attempts
    summary = '2026-08-07: fresh JDK 17 appDebug/androidTest build for LegadoJsonPathReferenceTest started with the isolated seeded cache but emitted only daemon initialization during the bounded interval; it was cancelled without producing a new APK. Old APK was not used for this probe.'
    evidencePaths = @(
      'tools/legado-compat/evidence/content-parity-d017-reference-20260804.json',
      'tools/legado-compat/evidence/android-reference-online-build-20260804/build.stdout.log',
      'tools/legado-compat/evidence/android-reference-online-build-20260804/gradle-daemon-thread-dump.txt',
      'tools/legado-compat/evidence/legado-jsonpath-runtime-extended-execution-20260807.json'
    )
    lastUpdatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'")
  })
  $referenceIssueUpdated = $true
}
if (-not $referenceIssueUpdated) {
  throw 'ISSUE-AUTO-028 is missing from the governance issue list'
}
$issues = $updatedIssues
$governance.issues = $issues.ToArray()

$json = $state | ConvertTo-Json -Depth 20
$temporaryPath = "$statePath.tmp-$PID"
[System.IO.File]::WriteAllText($temporaryPath, $json, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::Move($temporaryPath, $statePath, $true)
Write-Output ($issue | ConvertTo-Json -Compress -Depth 8)
