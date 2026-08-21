[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-governance-active-issue-section-drift-pre-fix-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-RepoPath([string]$RelativePath) {
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText([string]$RelativePath) {
  $path = Get-RepoPath $RelativePath
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $utf8Strict.GetString($bytes)
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 20), $utf8NoBom)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Get-PropertyValue([object]$Object, [string]$Name, [object]$Default = $null) {
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

$fixtureRelative = 'tools/legado-compat/fixtures/legado-governance-active-issue-section-drift.json'
$stateRelative = 'tools/legado-compat/state/full-source-validation-state.json'
$ledgerRelative = 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
$fixture = Read-StrictText $fixtureRelative | ConvertFrom-Json
$state = Read-StrictText $stateRelative | ConvertFrom-Json
$ledger = Read-StrictText $ledgerRelative
$governance = $state.governance
$activeIssueId = [string](Get-PropertyValue $governance 'activeIssueId' '')
$activeIssue = @($governance.issues | Where-Object { [string](Get-PropertyValue $_ 'id' '') -eq $activeIssueId }) | Select-Object -First 1
$heading = '## 当前源码重构活动议题'
$headingIndex = $ledger.IndexOf($heading, [System.StringComparison]::Ordinal)
if ($headingIndex -lt 0) { throw 'Current source issue heading is missing.' }
$sectionEnd = $ledger.IndexOf('### ', $headingIndex + $heading.Length, [System.StringComparison]::Ordinal)
if ($sectionEnd -lt 0) { $sectionEnd = $ledger.Length }
$section = $ledger.Substring($headingIndex, $sectionEnd - $headingIndex)
$hasher = [System.Security.Cryptography.SHA256]::Create()
try {
  $observedHash = ([System.BitConverter]::ToString($hasher.ComputeHash($utf8NoBom.GetBytes($section)))).Replace('-', '').ToUpperInvariant()
} finally {
  $hasher.Dispose()
}
$staleIssueId = 'ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH'
$failure = [ordered]@{
  schemaVersion = 1
  kind = 'legado_governance_active_issue_section_drift_failure_witness'
  status = 'failed_static_only'
  issueId = [string]$fixture.issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{
    sourceCount = [int]$state.baseline.sourceCount
    sourcePackageSha256 = [string]$state.baseline.sourcePackageSha256
    legadoCommit = [string]$state.baseline.legadoCommit
  }
  sourceOfTruth = [string]$fixture.sourceOfTruth
  ledgerPath = [string]$fixture.mirrorPath
  observed = [ordered]@{
    activeIssueId = $activeIssueId
    activeIssueStatus = [string](Get-PropertyValue $activeIssue 'status' 'missing')
    expectedIssuePresent = $section.Contains($activeIssueId)
    staleIssuePresent = $section.Contains($staleIssueId)
    sectionSha256 = $observedHash
  }
  failure = 'The manually maintained current-source-issue section named the stale 037 issue while machine fact state selected 242.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
}
Write-AtomicJson $OutputPath $failure
$failure | ConvertTo-Json -Depth 20
