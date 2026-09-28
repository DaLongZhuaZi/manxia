[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = '',
  [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
if ([string]::IsNullOrWhiteSpace($FixturePath)) {
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\hypium-ordinal096-evidence-consumption.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-ordinal096-evidence-consumption.json'
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Ordinal 096 evidence-consumption contract failed: $Message" }
}

function Read-Utf8Json {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) "missing fixture: $Path"
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
}

$result = $null
try {
  $runnerPath = Join-Path $RepositoryRoot 'tools\legado-compat\Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1'
  $modulePath = Join-Path $RepositoryRoot 'tools\legado-compat\LegadoHypiumEvidenceProjection.psm1'
  $runnerText = [System.IO.File]::ReadAllText($runnerPath, [System.Text.UTF8Encoding]::new($false, $true))
  Assert-Contract ($runnerText.Contains('LegadoHypiumEvidenceProjection.psm1')) 'the device runner must import the shared evidence projection module.'
  Assert-Contract ($runnerText.Contains('Get-LegadoCapturedReadWorkflowAssessments')) 'the device runner must consume captured read workflow assessments before parent-process classification.'
  Assert-Contract ($runnerText.Contains('safe_read_path_reference_pending')) 'captured read evidence must settle as reference-pending, not harness-incomplete.'

  Import-Module -Name $modulePath -Force
  $fixture = Read-Utf8Json -Path $FixturePath
  $assessment = Get-LegadoCapturedReadWorkflowAssessments -Attempt $fixture
  Assert-Contract ([bool]$assessment.allPassed) 'the complete BookInfo/Toc/Content fixture must be accepted even when runnerStatus is failed.'
  foreach ($name in @('bookInfo', 'toc', 'content')) {
    $item = $assessment.PSObject.Properties[$name].Value
    Assert-Contract ([string]$item.status -eq 'passed') "$name must be passed from its own trace and workflow result."
    Assert-Contract ([string]$item.evidenceDigest -match '^[0-9a-f]{64}$') "$name must retain its trace digest."
    Assert-Contract (-not ([string]$item.outcome -eq 'safe_read_path_harness_incomplete')) "$name must not be downgraded to safe_read_path_harness_incomplete."
  }

  $result = [pscustomobject][ordered]@{
    status = 'passed'
    contract = 'ordinal096_captured_read_evidence_consumption'
    assertions = 10
    fixture = [System.IO.Path]::GetRelativePath($RepositoryRoot, $FixturePath).Replace('\\', '/')
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
} catch {
  $result = [pscustomobject][ordered]@{
    status = 'failed'
    contract = 'ordinal096_captured_read_evidence_consumption'
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
}
$directory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
[System.IO.File]::WriteAllText($ResultPath, [string]($result | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') { exit 1 }
