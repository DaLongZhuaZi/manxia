[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$StatePath = 'tools/legado-compat/state/full-source-validation-state.json',
  [string]$EvidencePath = 'tools/legado-compat/evidence/r3-governance-verifying-recovery-20260809/recovery.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$sourceCount = 458
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'

function Get-RepoPath([string]$RelativePath) {
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson([string]$RelativePath) {
  $path = Get-RepoPath $RelativePath
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $utf8Strict.GetString($bytes) | ConvertFrom-Json
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 40), $utf8NoBom)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

$state = Read-StrictJson $StatePath
if ([int]$state.baseline.sourceCount -ne $sourceCount -or
    [string]$state.baseline.sourcePackageSha256 -ne $sourceHash -or
    [string]$state.baseline.legadoCommit -ne $legadoCommit) {
  throw 'Machine baseline drifted.'
}
if ($null -eq $state.governance) { throw 'Machine governance section is missing.' }

$now = [DateTimeOffset]::UtcNow.ToString('o')
$restored = New-Object 'System.Collections.Generic.List[string]'
foreach ($issue in @($state.governance.issues)) {
  if ($null -eq $issue) { continue }
  $recovery = $issue.PSObject.Properties['lastRecovery']
  $priorStatus = if ($null -ne $recovery -and $null -ne $recovery.Value) { [string]$recovery.Value.priorStatus } else { '' }
  $reason = if ($null -ne $recovery -and $null -ne $recovery.Value) { [string]$recovery.Value.reason } else { '' }
  if ([string]$issue.status -eq 'planned' -and $reason -eq 'stale_execution_recovered' -and $priorStatus -eq 'verifying') {
    $issue.status = 'verifying'
    $issue | Add-Member -NotePropertyName 'recoveryRestoredAt' -NotePropertyValue $now -Force
    $issue | Add-Member -NotePropertyName 'recoveryRestoredFrom' -NotePropertyValue 'stale_execution_recovered.priorStatus=verifying' -Force
    [void]$restored.Add([string]$issue.id)
  }
}

$state.generatedAt = $now
Write-AtomicJson $StatePath $state

$priorEvidence = $null
$evidenceFullPath = Get-RepoPath $EvidencePath
if (Test-Path -LiteralPath $evidenceFullPath -PathType Leaf) {
  $priorBytes = [System.IO.File]::ReadAllBytes($evidenceFullPath)
  if ($priorBytes.Length -ge 3 -and $priorBytes[0] -eq 0xEF -and $priorBytes[1] -eq 0xBB -and $priorBytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $EvidencePath"
  }
  $priorEvidence = $utf8Strict.GetString($priorBytes) | ConvertFrom-Json
}
$historicalIds = New-Object 'System.Collections.Generic.List[string]'
if ($null -ne $priorEvidence) {
  foreach ($id in @($priorEvidence.restoredIssueIds)) {
    if (-not $historicalIds.Contains([string]$id)) { [void]$historicalIds.Add([string]$id) }
  }
}
foreach ($id in $restored.ToArray()) {
  if (-not $historicalIds.Contains([string]$id)) { [void]$historicalIds.Add([string]$id) }
}
$evidence = [ordered]@{
  schemaVersion = 1
  kind = 'legado_governance_verifying_status_recovery'
  status = 'passed'
  generatedAt = $now
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  restoredIssueCount = $historicalIds.Count
  restoredIssueIds = @($historicalIds.ToArray())
  lastRunRestoredIssueCount = $restored.Count
  idempotentReplay = ($null -ne $priorEvidence -and $restored.Count -eq 0)
  recoveryRule = 'Only planned issues with lastRecovery.reason=stale_execution_recovered and priorStatus=verifying are restored to verifying; running issues remain eligible for planned recovery.'
  activeIssueId = [string]$state.governance.activeIssueId
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  deviceRegression = 'not_run'
}
Write-AtomicJson $EvidencePath $evidence

$refreshScript = Get-RepoPath 'tools/legado-compat/Invoke-LegadoCompatibility.ps1'
$pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
if ($null -eq $pwsh) { throw 'PowerShell 7 (pwsh) is required to refresh derived governance documents.' }
$refreshCommand = "& '" + $refreshScript.Replace("'", "''") + "' -RefreshDocumentsOnly"
& $pwsh.Source -NoLogo -NoProfile -NonInteractive -Command $refreshCommand | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Derived governance document refresh failed.' }

$evidence | ConvertTo-Json -Depth 20 -Compress
