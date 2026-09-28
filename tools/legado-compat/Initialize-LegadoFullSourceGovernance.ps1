[CmdletBinding()]
param(
  [string]$SourcePackagePath = '',
  [string]$SourcePackageDirectory = 'F:\Downloads-E',
  [string]$StatePath = '',
  [string]$LegacyGovernancePath = '',
  [string]$ExpectedPackageSha256 = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67',
  [int]$ExpectedSourceCount = 458,
  [string]$LegadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd',
  [string]$ExpectedLegadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($StatePath.Length -eq 0) {
  $StatePath = Join-Path $PSScriptRoot 'state\full-source-validation-state.json'
}
if ($LegacyGovernancePath.Length -eq 0) {
  $LegacyGovernancePath = Join-Path $PSScriptRoot 'state\continuous-governance-state.json'
}

$modulePath = Join-Path $PSScriptRoot 'LegadoFullSourceState.psm1'
Import-Module -Name $modulePath -Force

if ($SourcePackagePath.Length -eq 0) {
  if (-not (Test-Path -LiteralPath $SourcePackageDirectory)) {
    throw "Source package directory does not exist: $SourcePackageDirectory"
  }
  foreach ($candidate in @(Get-ChildItem -LiteralPath $SourcePackageDirectory -Filter '*.json' -File)) {
    $candidateHash = Get-LegadoSha256ForBytes -Bytes ([System.IO.File]::ReadAllBytes($candidate.FullName))
    if ($candidateHash -eq $ExpectedPackageSha256) {
      $SourcePackagePath = $candidate.FullName
      break
    }
  }
  if ($SourcePackagePath.Length -eq 0) {
    throw "No JSON file in $SourcePackageDirectory matches the pinned package SHA-256."
  }
}

$state = Initialize-LegadoFullSourceState `
  -SourcePackagePath $SourcePackagePath `
  -StatePath $StatePath `
  -LegacyGovernancePath $LegacyGovernancePath `
  -ExpectedPackageSha256 $ExpectedPackageSha256 `
  -ExpectedSourceCount $ExpectedSourceCount `
  -LegadoCommit $LegadoCommit `
  -ExpectedLegadoCommit $ExpectedLegadoCommit

$counts = $state.bucketCounts
$recovery = $state.recovery
$summary = (
  'FULL_SOURCE_STATE_READY count={0} safe_text={1} js_text={2} interactive={3} ' +
  'audio={4} image={5} file={6} external={7} recovered={8} governance_recovered={9}'
) -f
  [int]$state.baseline.sourceCount,
  [int]$counts.safe_text,
  [int]$counts.js_text,
  [int]$counts.interactive,
  [int]$counts.audio,
  [int]$counts.image,
  [int]$counts.file,
  [int]$counts.external,
  [int]$recovery.staleSourceAndWorkflowCount,
  [int]$recovery.staleGovernanceCount
Write-Output $summary
