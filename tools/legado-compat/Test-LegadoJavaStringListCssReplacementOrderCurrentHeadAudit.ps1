[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$SourceFixPath = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if ([string]::IsNullOrWhiteSpace($SourceFixPath)) {
  $SourceFixPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-java-string-list-css-replacement-order-source-fix-20260808.json'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-java-string-list-css-replacement-order-current-head-audit-20260808.json'
}

$utf8 = [System.Text.UTF8Encoding]::new($false, $true)
function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return ($utf8.GetString($bytes) | ConvertFrom-Json)
}
function Get-Sha256 { param([string]$Path) return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant() }
function Get-RepoPath { param([string]$RelativePath) return (Resolve-Path -LiteralPath (Join-Path $RepositoryRoot ($RelativePath -replace '/', '\'))).Path }
$sourceFix = Read-StrictJson -Path $SourceFixPath
$state = Read-StrictJson -Path (Get-RepoPath -RelativePath 'tools/legado-compat/state/full-source-validation-state.json')
if ([string]$sourceFix.issueId -ne 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION') { throw 'Source-fix evidence is bound to the wrong issue.' }
if ([string]$sourceFix.status -ne 'source_fix_applied_pending_verification' -or [bool]$sourceFix.semanticMatchAllowed) { throw 'Source-fix evidence is not static-only.' }
if ([string]$state.governance.activeIssueId -ne 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION') { throw 'Machine active issue is not 233.' }
$hashes = [ordered]@{}
foreach ($property in $sourceFix.sourceHashes.PSObject.Properties) {
  $relativePath = [string]$property.Name
  $actualHash = Get-Sha256 -Path (Get-RepoPath -RelativePath $relativePath)
  if ($actualHash -ne ([string]$property.Value).ToUpperInvariant()) { throw "Source hash drifted: $relativePath" }
  $hashes[$relativePath] = $actualHash
}
$result = [ordered]@{
  schemaVersion = 1
  kind = 'legado_java_string_list_css_replacement_order_current_head_audit'
  issueId = [string]$sourceFix.issueId
  status = 'current_head_bound_static_closure'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = [int]$state.baseline.sourceCount; sourcePackageSha256 = [string]$state.baseline.sourcePackageSha256; legadoCommit = [string]$state.baseline.legadoCommit }
  sourceFixEvidence = $SourceFixPath
  implementationHashes = $hashes
  fixtureSha256 = [string]$sourceFix.fixtureSha256
  contractSha256 = [string]$sourceFix.contractSha256
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_current_head_static_only;R4_runtime_build_device_and_legado_diff_deferred'
}
$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) { [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null }
$temporaryPath = "$OutputPath.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
[System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $OutputPath -Force
$result | ConvertTo-Json -Depth 20
