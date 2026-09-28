[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$ResultPath = 'tools/legado-compat/evidence/v2-jsoup-dom-matcher-selector-group-registration-idempotency-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$revision = '2026-08-10-actual-docs-source-refactor-jsoup-dom-matcher-selector-group-static-closure'

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$RelativePath); return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$RelativePath); return Read-StrictText $RelativePath | ConvertFrom-Json -Depth 100 }
function Get-Hash { param([Parameter(Mandatory = $true)][string]$RelativePath); return (Get-FileHash -LiteralPath (Get-RepoPath $RelativePath) -Algorithm SHA256).Hash.ToUpperInvariant() }
function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value)
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$trackedPaths = @(
  'tools/legado-compat/state/full-source-validation-state.json',
  'tools/legado-compat/state/refactor-objective.json',
  'tools/legado-compat/evidence/v2-jsoup-dom-matcher-selector-group-source-fix-20260810.json',
  'docs/analysis/Legado书源V2源码重构持续目标.md',
  'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md',
  'docs/analysis/Legado书源引擎证据索引.md',
  'docs/analysis/Legado书源引擎差分摘要.md'
)
$before = [ordered]@{}
foreach ($path in $trackedPaths) { $before[$path] = Get-Hash $path }
$registrationScript = Get-RepoPath 'tools/legado-compat/Register-LegadoJsoupDomMatcherSelectorGroupSourceFix.ps1'
$output = & pwsh -NoLogo -NoProfile -NonInteractive -File $registrationScript -RepositoryRoot $RepositoryRoot 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw ('DOM Matcher source-fix replay failed: ' + $output) }
$after = [ordered]@{}
foreach ($path in $trackedPaths) { $after[$path] = Get-Hash $path }
$differences = New-Object 'System.Collections.Generic.List[string]'
foreach ($path in $trackedPaths) {
  if ([string]$before[$path] -ne [string]$after[$path]) { [void]$differences.Add($path) }
}
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$objective = Read-StrictJson 'tools/legado-compat/state/refactor-objective.json'
$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId })[0]
if ($differences.Count -ne 0) { throw ('DOM Matcher source-fix replay changed tracked paths: ' + ($differences -join ', ')) }
if ([string]$objective.targetRevision -ne $revision -or [string]$state.governance.activeIssueId -ne $issueId -or [string]$issue.status -ne 'verifying' -or [bool]$state.governance.semanticMatchAllowed -or @($state.governance.runtimeActionsPerformed).Count -ne 0) {
  throw 'DOM Matcher source-fix replay changed the active static boundary or introduced a runtime claim.'
}

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'registration_idempotency_static_contract'
  issueId = $issueId
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  targetRevision = $revision
  trackedPaths = $trackedPaths
  beforeSha256 = $before
  afterSha256 = $after
  changedPaths = @()
  replayOutput = $output.Trim()
  assertions = 8
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_dom_matcher_registration_idempotency_static_only;R4_runtime_build_device_and_legado_diff_deferred'
}
Write-AtomicJson -RelativePath $ResultPath -Value $result
$result | ConvertTo-Json -Depth 100
