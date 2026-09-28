[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$FixturePath = '',
  [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
if ([string]::IsNullOrWhiteSpace($FixturePath)) {
  $FixturePath = Join-Path $RepoRoot 'tools\legado-compat\fixtures\hypium-governance-evidence-append.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepoRoot 'tools\legado-compat\evidence\v2-harness-023-governance-evidence-append-contract-20260808.json'
}

$assertions = 0
function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Governance evidence append contract failed: $Message" }
  $script:assertions++
}

function Get-StrictUtf8Text {
  param([string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  Assert-Contract (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) "UTF-8 BOM is forbidden: $Path"
  return [System.Text.UTF8Encoding]::new($false, $true).GetString($bytes)
}

function Write-Result {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
  $temporaryPath = $Path + '.tmp-' + $PID
  [System.IO.File]::WriteAllText($temporaryPath, [string]($Value | ConvertTo-Json -Depth 16), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

$result = $null
try {
  $fixtureText = Get-StrictUtf8Text -Path $FixturePath
  $fixture = $fixtureText | ConvertFrom-Json
  $sourcePath = Join-Path $RepoRoot 'tools\legado-compat\Update-LegadoGovernanceState.ps1'
  $sourceText = Get-StrictUtf8Text -Path $sourcePath
  $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToUpperInvariant()

  Assert-Contract ([string]$fixture.contract -eq 'hypium_governance_evidence_append') 'fixture contract must identify evidence append semantics'
  Assert-Contract ([string]$fixture.issueId -eq 'V2-HARNESS-023') 'fixture must bind the harness issue'
  Assert-Contract ([int]$fixture.baseline.sourceCount -eq 458) 'fixture source count must remain 458'
  Assert-Contract ([string]$fixture.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'fixture package hash drifted'
  Assert-Contract ([string]$fixture.preFix.failureCode -eq 'EVIDENCE_PATH_HISTORY_REPLACED') 'fixture must retain the pre-fix failure code'
  Assert-Contract (@($fixture.preFix.existingEvidencePaths).Count -gt 0) 'pre-fix fixture must contain existing evidence'
  Assert-Contract (@($fixture.preFix.incomingEvidencePaths).Count -gt 0) 'pre-fix fixture must contain incoming evidence'
  Assert-Contract (@($fixture.preFix.observedEvidencePaths).Count -eq @($fixture.preFix.incomingEvidencePaths).Count) 'pre-fix observed output must demonstrate replacement'
  Assert-Contract ([string]$fixture.preFix.implementationSha256 -ne $sourceHash) 'current updater must differ from the frozen failing implementation'
  Assert-Contract ($sourceText.Contains('existingEvidenceProperty')) 'updater must read existing evidence paths'
  Assert-Contract ($sourceText.Contains('rawEvidenceValues')) 'updater must merge existing and incoming raw values'
  Assert-Contract ($sourceText.Contains('rawEvidenceValues.ToArray()')) 'updater must normalize the merged values'
  Assert-Contract ($sourceText.Contains('normalizedEvidence.ToArray()')) 'updater must serialize de-duplicated evidence values'

  $expectedPaths = @($fixture.postFix.expectedDistinctEvidencePaths | ForEach-Object { [string]$_ })
  $expectedUnique = @($expectedPaths | Select-Object -Unique)
  Assert-Contract ($expectedUnique.Count -eq [int]$fixture.postFix.expectedDistinctCount) 'post-fix expected evidence count is inconsistent'
  Assert-Contract ($expectedUnique.Count -eq (@($fixture.preFix.existingEvidencePaths).Count + @($fixture.preFix.incomingEvidencePaths).Count)) 'post-fix expected paths must retain existing and incoming evidence'

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'passed'
    kind = 'static_contract_result'
    issueId = [string]$fixture.issueId
    contract = [string]$fixture.contract
    phase = 'source_closure_static_verified_pending_r4'
    assertions = $assertions
    sourcePath = 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
    sourceSha256 = $sourceHash
    preFixEvidencePath = 'tools/legado-compat/evidence/v2-harness-023-governance-evidence-append-contract-20260808-pre-fix.json'
    failureCode = [string]$fixture.preFix.failureCode
    expectedDistinctEvidenceCount = [int]$fixture.postFix.expectedDistinctCount
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'failed'
    kind = 'static_contract_result'
    issueId = 'V2-HARNESS-023'
    contract = 'hypium_governance_evidence_append'
    phase = 'failure_contract_or_source_closure_failed'
    assertions = $assertions
    error = $_.Exception.Message
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
}

Write-Result -Path $ResultPath -Value $result
$result | ConvertTo-Json -Compress -Depth 16
if ($result.status -ne 'passed') { exit 1 }
