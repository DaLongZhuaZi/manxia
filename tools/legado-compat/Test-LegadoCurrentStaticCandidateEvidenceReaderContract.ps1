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
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if ([string]::IsNullOrWhiteSpace($FixturePath)) {
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\current-static-candidate-evidence-reader.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-current-static-candidate-evidence-reader-20260809.json'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$assertions = 0

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Evidence reader contract failed: $Message" }
  $script:assertions++
}

function Read-Json {
  param([string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  Assert-Contract (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) "fixture has a BOM: $Path"
  return $strictUtf8.GetString($bytes) | ConvertFrom-Json
}

function Write-Result {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 20), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$result = $null
try {
  $fixture = Read-Json -Path $FixturePath
  $gatePath = Join-Path $RepositoryRoot 'tools\legado-compat\Test-LegadoCurrentStaticSourceCandidateGate.ps1'
  $gateBytes = [System.IO.File]::ReadAllBytes($gatePath)
  $gateText = $strictUtf8.GetString($gateBytes)
  $gateHash = (Get-FileHash -LiteralPath $gatePath -Algorithm SHA256).Hash.ToUpperInvariant()

  Assert-Contract ([string]$fixture.contract -eq 'current_static_candidate_evidence_reader') 'fixture contract drifted'
  Assert-Contract ([string]$fixture.issueId -eq 'ISSUE-AUTO-044-EVIDENCE-READER-UTF8') 'fixture issue id drifted'
  Assert-Contract ([int]$fixture.baseline.sourceCount -eq 458) 'fixture source count drifted'
  Assert-Contract ([string]$fixture.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'fixture source hash drifted'
  Assert-Contract ([string]$fixture.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'fixture Legado commit drifted'
  Assert-Contract ([string]$fixture.preFix.failureCode -eq 'EVIDENCE_UTF8_BOM_REJECTED') 'pre-fix failure code drifted'
  Assert-Contract ([string]$fixture.preFix.sourceSha256 -ne $gateHash) 'current gate still equals the frozen pre-fix implementation'
  foreach ($marker in @($fixture.postFix.requiredMarkers)) {
    Assert-Contract ($gateText.Contains([string]$marker)) "gate marker missing: $marker"
  }
  Assert-Contract ($gateText.Contains('utf8_bom_text')) 'BOM text must be represented explicitly'
  Assert-Contract ($gateText.Contains('binary_evidence_file')) 'binary evidence must be classified explicitly'

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'passed_static_only'
    kind = 'static_contract_result'
    issueId = [string]$fixture.issueId
    contract = [string]$fixture.contract
    phase = 'r3_harness_static_verified_pending_r4'
    assertions = $assertions
    sourcePath = 'tools/legado-compat/Test-LegadoCurrentStaticSourceCandidateGate.ps1'
    sourceSha256 = $gateHash
    preFixEvidencePath = 'tools/legado-compat/evidence/contract-legado-current-static-candidate-evidence-reader-pre-fix-20260809.json'
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'static_gate_reader_only;R4_runtime_build_device_and_legado_diff_deferred'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'failed'
    kind = 'static_contract_result'
    issueId = 'ISSUE-AUTO-044-EVIDENCE-READER-UTF8'
    contract = 'current_static_candidate_evidence_reader'
    phase = 'failure_contract_or_source_closure_failed'
    assertions = $assertions
    error = $_.Exception.Message
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
}

Write-Result -Path $ResultPath -Value $result
$result | ConvertTo-Json -Compress -Depth 20
if ([string]$result.status -ne 'passed_static_only') { exit 1 }
