param(
  [string]$EvidenceRoot = '',
  [int]$ExpectedSourceCount = 458,
  [string]$ExpectedSourcePackageSha256 = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67',
  [string]$ExpectedLegadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd',
  [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($EvidenceRoot)) {
  $EvidenceRoot = Join-Path $PSScriptRoot 'evidence'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $EvidenceRoot 'effective-full-source-v2-hypium-device\evidence-overlay-contract.json'
}

$auditScript = Join-Path $PSScriptRoot 'Test-LegadoV2HypiumFullSourceEvidence.ps1'
$effectiveDirectory = Join-Path $EvidenceRoot 'effective-full-source-v2-hypium-device'
$contractPath = Join-Path $effectiveDirectory 'full-source-evidence-contract.json'
$mapPath = Join-Path $effectiveDirectory 'source-map.json'

$assertions = [System.Collections.Generic.List[object]]::new()
function Assert-Contract {
  param([bool]$Condition, [string]$Name, [string]$Detail)
  [void]$assertions.Add([pscustomobject][ordered]@{
    name = $Name
    passed = $Condition
    detail = $Detail
  })
  if (-not $Condition) { throw "OVERLAY_CONTRACT_FAILED: ${Name}: $Detail" }
}

$null = & $auditScript -EvidenceDirectory (Join-Path $EvidenceRoot 'full-source-v2-hypium-device') -OverlayRoot $EvidenceRoot -RequireCompleted 2>&1
$auditSucceeded = $?
Assert-Contract $auditSucceeded 'effective_audit_exit_code' ("success={0}" -f $auditSucceeded)
Assert-Contract (Test-Path -LiteralPath $contractPath) 'effective_contract_exists' $contractPath
Assert-Contract (Test-Path -LiteralPath $mapPath) 'effective_source_map_exists' $mapPath

$contract = Get-Content -LiteralPath $contractPath -Encoding UTF8 | ConvertFrom-Json
$sourceMap = Get-Content -LiteralPath $mapPath -Encoding UTF8 | ConvertFrom-Json
$entries = @($sourceMap.entries)

Assert-Contract ([string]$contract.status -eq 'passed') 'effective_audit_passed' ([string]$contract.status)
Assert-Contract ([string]$contract.evidenceMode -eq 'effective_overlay') ([string]$contract.evidenceMode) 'evidence mode must select baseline plus validated overlays'
Assert-Contract ([int]$contract.evidenceCount -eq $ExpectedSourceCount) 'effective_source_count' ([string]$contract.evidenceCount)
Assert-Contract ([int]$contract.uniqueOrdinalCount -eq $ExpectedSourceCount) 'effective_unique_ordinals' ([string]$contract.uniqueOrdinalCount)
Assert-Contract ([int]$contract.uniqueSourceIdCount -eq $ExpectedSourceCount) 'effective_unique_source_ids' ([string]$contract.uniqueSourceIdCount)
Assert-Contract ([int]$contract.failureCount -eq 0) 'effective_failure_count' ([string]$contract.failureCount)
Assert-Contract ($entries.Count -eq $ExpectedSourceCount) 'effective_map_entry_count' ([string]$entries.Count)
Assert-Contract ((@($entries | Select-Object -ExpandProperty ordinal | Sort-Object -Unique).Count) -eq $ExpectedSourceCount) 'effective_map_ordinal_uniqueness' 'ordinal set must be closed'
Assert-Contract ((@($entries | Select-Object -ExpandProperty sourceId | Sort-Object -Unique).Count) -eq $ExpectedSourceCount) 'effective_map_source_uniqueness' 'sourceId set must be closed'
Assert-Contract ([int]$contract.overlayAppliedCount -gt 0) 'overlay_applied' ([string]$contract.overlayAppliedCount)

foreach ($ordinal in @(96, 173, 222, 227, 292, 297, 301, 162, 74)) {
  $entry = @($entries | Where-Object { [int]$_.ordinal -eq $ordinal })
  Assert-Contract ($entry.Count -eq 1) ("overlay_entry_{0}_exists" -f $ordinal) ("count={0}" -f $entry.Count)
  Assert-Contract ([string]$entry[0].sourceKind -eq 'overlay') ("overlay_entry_{0}_selected" -f $ordinal) ([string]$entry[0].sourceKind)
}

$sourceEvidenceCount = @(Get-ChildItem -LiteralPath $effectiveDirectory -File -Filter 'source-*.json' | Where-Object { $_.Name -ne 'source-map.json' }).Count
Assert-Contract ($sourceEvidenceCount -eq $ExpectedSourceCount) 'effective_source_artifact_count' ([string]$sourceEvidenceCount)

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  generatedAt = [DateTime]::UtcNow.ToString('o')
  status = 'passed'
  evidenceRoot = $EvidenceRoot
  expectedSourceCount = $ExpectedSourceCount
  auditContract = $contractPath
  sourceMap = $mapPath
  assertions = @($assertions)
}
$resultDirectory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $resultDirectory)) { [void][System.IO.Directory]::CreateDirectory($resultDirectory) }
$temporaryPath = $ResultPath + '.tmp'
[System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 16), [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $ResultPath -Force
$result | ConvertTo-Json -Depth 16
