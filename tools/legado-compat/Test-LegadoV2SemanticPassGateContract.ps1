[CmdletBinding()]
param(
  [string]$EvidenceDirectory = '',
  [string]$StatePath = '',
  [switch]$RequireNoViolations
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($EvidenceDirectory)) {
  $EvidenceDirectory = Join-Path $PSScriptRoot 'evidence\full-source-v2-hypium-device'
}

$allowedQualifications = @('semantic_match', 'search_semantic_match')
if ([string]::IsNullOrWhiteSpace($StatePath)) {
  $records = @(
    Get-ChildItem -LiteralPath $EvidenceDirectory -Filter 'source-*.json' -File |
      ForEach-Object { Get-Content -LiteralPath $_.FullName -Encoding UTF8 -Raw | ConvertFrom-Json }
  )
} else {
  $state = Get-Content -LiteralPath $StatePath -Encoding UTF8 -Raw | ConvertFrom-Json
  $records = @(
    $state.sources | ForEach-Object {
      [pscustomobject][ordered]@{
        ordinal = $_.ordinal
        sourceId = $_.sourceId
        status = $_.status
        outcome = $_.lastOutcome
        semanticQualification = $_.semanticQualification
      }
    }
  )
}
$violations = @(
  $records | Where-Object {
    [string]$_.status -eq 'passed' -and
    (
      [string]$_.semanticQualification -notin $allowedQualifications -or
      [string]$_.outcome -match '(?i)(unconfirmed|pending|unverified|reference_missing|reference_pending)'
    )
  }
)

if ($RequireNoViolations -and $violations.Count -gt 0) {
  $sample = @($violations | Select-Object -First 10 | ForEach-Object {
    '{0}:{1}:{2}:{3}' -f $_.ordinal, $_.status, $_.semanticQualification, $_.outcome
  }) -join '; '
  throw "Legado V2 semantic pass gate failed: $($violations.Count) passed records lack a confirmed Legado semantic match. Sample: $sample"
}

[pscustomobject][ordered]@{
  status = if ($violations.Count -eq 0) { 'passed' } else { 'failed' }
  contract = 'passed_requires_confirmed_legado_semantic_match'
  sourceCount = $records.Count
  violationCount = $violations.Count
  violations = @($violations | Select-Object ordinal,sourceId,status,outcome,semanticQualification)
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
} | ConvertTo-Json -Depth 8
