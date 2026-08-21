[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$ResultPath = 'tools/legado-compat/evidence/r3-jsoup-standard-pseudo-243-transition-20260809/registration-idempotency.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Read-StrictText $RelativePath | ConvertFrom-Json -Depth 100
}

function Get-Hash {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return (Get-FileHash -LiteralPath (Get-RepoPath $RelativePath) -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value)
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 50), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      [System.IO.File]::Delete($temporaryPath)
    }
  }
}

$trackedPaths = @(
  'tools/legado-compat/state/full-source-validation-state.json',
  'tools/legado-compat/state/refactor-objective.json',
  'tools/legado-compat/evidence/r3-jsoup-standard-pseudo-243-transition-20260809/registration.json',
  'docs/analysis/Legado书源V2源码重构持续目标.md',
  'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
)
$result = $null
$exitCode = 0
try {
  $stateBefore = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
  $registrationBefore = Read-StrictJson 'tools/legado-compat/evidence/r3-jsoup-standard-pseudo-243-transition-20260809/registration.json'
  if ([int]$stateBefore.baseline.sourceCount -ne 458 -or
      [string]$stateBefore.baseline.sourcePackageSha256 -ne $baselineHash -or
      [string]$stateBefore.baseline.legadoCommit -ne $legadoCommit -or
      [string]$stateBefore.governance.activeIssueId -ne $issueId -or
      [string]$registrationBefore.issueId -ne $issueId) {
    throw '243 registration idempotency precondition is not bound to the frozen active issue.'
  }

  $before = [ordered]@{}
  foreach ($path in $trackedPaths) {
    $before[$path] = Get-Hash $path
  }

  $registrationScript = Get-RepoPath 'tools/legado-compat/Register-LegadoJsoupStandardPseudoSelectorSourceFix.ps1'
  $output = & pwsh -NoLogo -NoProfile -NonInteractive -File $registrationScript -RepositoryRoot $RepositoryRoot 2>&1 | Out-String
  if ($LASTEXITCODE -ne 0) {
    throw ('idempotent registration replay failed: ' + $output)
  }

  $after = [ordered]@{}
  foreach ($path in $trackedPaths) {
    $after[$path] = Get-Hash $path
  }
  $differences = New-Object 'System.Collections.Generic.List[string]'
  foreach ($path in $trackedPaths) {
    if ([string]$before[$path] -ne [string]$after[$path]) {
      [void]$differences.Add($path)
    }
  }
  if ($differences.Count -ne 0) {
    throw ('idempotent replay changed tracked files: ' + ($differences -join ', '))
  }

  $stateAfter = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
  $post = Read-StrictJson 'tools/legado-compat/evidence/r3-jsoup-standard-pseudo-243-transition-20260809/post-registration-consistency.json'
  if ([string]$stateAfter.governance.activeIssueId -ne $issueId -or
      [string]$post.status -ne 'passed' -or
      [bool]$post.semanticMatchAllowed -or
      @($post.runtimeActionsPerformed).Count -ne 0) {
    throw 'idempotent replay changed the active boundary or introduced a runtime claim.'
  }

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_jsoup_standard_pseudo_243_registration_idempotency'
    status = 'passed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    issueId = $issueId
    baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
    trackedPaths = $trackedPaths
    beforeSha256 = $before
    afterSha256 = $after
    changedPaths = @()
    assertions = 6
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_registration_idempotency_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_jsoup_standard_pseudo_243_registration_idempotency'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    issueId = $issueId
    failure = $_.Exception.Message
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_registration_idempotency_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  }
}
Write-AtomicJson -RelativePath $ResultPath -Value $result
$result | ConvertTo-Json -Depth 50
if ($exitCode -ne 0) {
  exit $exitCode
}
