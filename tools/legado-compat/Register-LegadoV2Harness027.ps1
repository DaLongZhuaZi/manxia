[CmdletBinding()]
param([string]$RepositoryRoot = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path }
$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$state = Get-Content -LiteralPath $statePath -Raw -Encoding utf8 | ConvertFrom-Json
$issue = [pscustomobject][ordered]@{
  id = 'V2-HARNESS-027'
  taskId = 'COMPAT-006'
  status = 'passed'
  severity = 'P1'
  attempts = 1
  summary = 'Workflow evidence projection previously treated any Attempt.trace as Explore evidence, so Search-only terminal sources reported explore.tracePresent=true. The projection now requires trace.workflow to equal the requested workflow and r4 fresh device evidence records false for unexecuted Explore.'
  evidencePaths = @(
    'tools/legado-compat/Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1',
    'tools/legado-compat/Test-LegadoV2SourceWorkflowEvidenceProjectionContract.ps1',
    'tools/legado-compat/evidence/v2-source-workflow-evidence-projection-contract.json',
    'tools/legado-compat/evidence/fresh-v2-harness-023-ordinal55-20260807-r4/source-CC5D833AA5FB5DD205B00C90CAC92FB32F825C971ED22F329468E0D786C47D13.json'
  )
  closeCondition = 'fresh evidence for the complete full_workflow batch has no tracePresent=true for an unexecuted workflow and the evidence audit remains clean.'
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
