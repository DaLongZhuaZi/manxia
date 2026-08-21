[CmdletBinding()]
param([string]$RepositoryRoot = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$state = Get-Content -LiteralPath $statePath -Raw -Encoding utf8 | ConvertFrom-Json
$issue = [pscustomobject][ordered]@{
  id = 'V2-HARNESS-026'
  taskId = 'COMPAT-006'
  status = 'passed'
  severity = 'P1'
  attempts = 1
  summary = 'V2 source evidence fresh r1 failed before dispatch because PowerShell treated an inline if expression as a command in the Explore projection. The expression is now assigned through an explicit local variable; fresh r2/r3 completed on device and r3 reconciled sourceAttempt with the maximum workflow attempt.'
  evidencePaths = @(
    'tools/legado-compat/evidence/fresh-v2-harness-023-ordinal55-20260807/run-activity.json',
    'tools/legado-compat/evidence/fresh-v2-harness-023-ordinal55-20260807-r2/run-activity.json',
    'tools/legado-compat/evidence/fresh-v2-harness-023-ordinal55-20260807-r3/source-CC5D833AA5FB5DD205B00C90CAC92FB32F825C971ED22F329468E0D786C47D13.json',
    'tools/legado-compat/Test-LegadoV2SourceWorkflowEvidenceProjectionContract.ps1'
  )
  closeCondition = 'fresh r3 ordinal evidence has passed runner completion, seven workflow projection, sourceAttempt binding, and no Harness process failure.'
  lastUpdatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'")
}
$issues = New-Object 'System.Collections.Generic.List[object]'
$replaced = $false
foreach ($existing in @($state.governance.issues)) {
  if ([string]$existing.id -eq [string]$issue.id) { [void]$issues.Add($issue); $replaced = $true } else { [void]$issues.Add($existing) }
}
if (-not $replaced) { [void]$issues.Add($issue) }
$state.governance.issues = $issues.ToArray()
$temporaryPath = "$statePath.tmp-$PID"
[System.IO.File]::WriteAllText($temporaryPath, ($state | ConvertTo-Json -Depth 24), [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::Move($temporaryPath, $statePath, $true)
$issue | ConvertTo-Json -Compress -Depth 8
