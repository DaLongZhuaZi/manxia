[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RunId = 'r3-actual-docs-consistency-audit-20260808-r1',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($RepositoryRoot.Length -eq 0) {
  $RepositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$evidenceRoot = (Resolve-Path -LiteralPath (Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).Path
$runDirectory = Join-Path $evidenceRoot $RunId
if ($OutputPath.Length -eq 0) {
  $OutputPath = Join-Path $runDirectory 'r3-actual-docs-consistency-audit.json'
}
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$evidencePrefix = $evidenceRoot.TrimEnd('\') + '\'
if (-not $outputFullPath.ToLowerInvariant().StartsWith($evidencePrefix.ToLowerInvariant())) {
  throw 'Audit output must remain under the evidence directory.'
}
if (-not (Test-Path -LiteralPath $runDirectory)) {
  [System.IO.Directory]::CreateDirectory($runDirectory) | Out-Null
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:checks = New-Object 'System.Collections.Generic.List[object]'
$script:assertions = 0

function Get-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Read-StrictUtf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw "Required file is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  $text = Read-StrictUtf8Text -Path $Path
  try { return ($text | ConvertFrom-Json) } catch { throw "Invalid JSON: $Path; $($_.Exception.Message)" }
}

function Get-Sha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-RelativePath {
  param([Parameter(Mandatory = $true)][string]$Path)
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $rootPrefix = $RepositoryRoot.TrimEnd('\') + '\'
  if ($fullPath.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $fullPath.Substring($rootPrefix.Length).Replace('\', '/')
  }
  return $fullPath.Replace('\', '/')
}

function Add-Check {
  param([string]$Id, [string]$Detail, [string[]]$Evidence = @())
  $script:checks.Add([pscustomobject][ordered]@{
    id = $Id
    status = 'passed'
    detail = $Detail
    evidencePaths = @($Evidence)
  })
  $script:assertions++
}

function Assert-Check {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
}

function Get-Issue {
  param([object[]]$Issues, [string]$Id)
  foreach ($issue in $Issues) {
    if ([string](Get-PropertyValue $issue 'id') -eq $Id) { return $issue }
  }
  return $null
}

$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$objectivePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\refactor-objective.json'
$governancePath = Join-Path $RepositoryRoot 'tools\legado-compat\LEGADO_V2_GOVERNANCE_TASKS.md'
$objectiveDocumentPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源V2源码重构持续目标.md'
$ledgerPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎兼容推进台账.md'
$diffPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎差分摘要.md'
$indexPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎证据索引.md'
$packagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
$auditHashPath = Join-Path $evidenceRoot 'r3-source-fix-hash-audit-20260808-r1.json'

$summary = $null
$exitCode = 0
try {
  $state = Read-StrictJson -Path $statePath
  $objective = Read-StrictJson -Path $objectivePath
  $governanceText = Read-StrictUtf8Text -Path $governancePath
  $objectiveDocumentText = Read-StrictUtf8Text -Path $objectiveDocumentPath
  $ledgerText = Read-StrictUtf8Text -Path $ledgerPath
  $diffText = Read-StrictUtf8Text -Path $diffPath
  $indexText = Read-StrictUtf8Text -Path $indexPath

  $baseline = $state.baseline
  Assert-Check ([int]$baseline.sourceCount -eq 458) 'Machine baseline source count is not 458.'
  Assert-Check ([int]$objective.baseline.sourceCount -eq 458) 'Objective baseline source count is not 458.'
  Assert-Check ([string]$baseline.sourcePackageSha256 -eq [string]$objective.baseline.sourcePackageSha256) 'State/objective source package hash differs.'
  Assert-Check ([string]$baseline.legadoCommit -eq [string]$objective.baseline.legadoCommit) 'State/objective Legado commit differs.'
  Assert-Check ((Get-Sha256 -Path $packagePath) -eq [string]$baseline.sourcePackageSha256) 'Source package hash drifted from the frozen baseline.'
  $legadoCommit = (& git -C (Join-Path $RepositoryRoot 'legado') rev-parse HEAD 2>$null | Out-String).Trim()
  Assert-Check ($legadoCommit -eq [string]$baseline.legadoCommit) 'Legado checkout is not at the frozen commit.'
  Add-Check -Id 'baseline_binding' -Detail 'State, objective, source package and Legado checkout share the frozen baseline.' -Evidence @((Get-RelativePath $statePath), (Get-RelativePath $objectivePath))

  $governance = $state.governance
  Assert-Check ([string]$governance.activeTaskId -eq 'COMPAT-006') 'Active task is not COMPAT-006.'
  Assert-Check ([string]$governance.activeIssueId -eq 'ISSUE-COMPAT-014') 'Active issue is not ISSUE-COMPAT-014.'
  Assert-Check ([string]$governance.status -eq 'running') 'Governance status is not running.'
  $issues = @($governance.issues)
  $issue014 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-014'
  $issue015 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-015'
  Assert-Check ($null -ne $issue014 -and [string]$issue014.status -eq 'verifying') 'ISSUE-COMPAT-014 must remain verifying.'
  Assert-Check ($null -ne $issue015 -and [string]$issue015.status -eq 'planned') 'ISSUE-COMPAT-015 must remain planned.'
  Assert-Check ([string]$governance.refactorObjective.targetRevision -eq [string]$objective.targetRevision) 'Attached objective revision differs from objective file.'
  Add-Check -Id 'queue_binding' -Detail 'The unique R3 queue remains COMPAT-006 -> ISSUE-COMPAT-014, with ISSUE-COMPAT-015 only a planned candidate.' -Evidence @((Get-RelativePath $statePath), (Get-RelativePath $governancePath))

  Assert-Check ([string]$objective.status -eq 'active') 'Refactor objective is not active.'
  Assert-Check ([string]$objective.continuationMode -eq 'R2-R3_SOURCE_CLOSURE_ONLY') 'Objective continuation mode drifted.'
  Assert-Check ($objectiveDocumentText.Contains([string]$objective.targetRevision)) 'Objective Markdown does not contain the machine revision.'
  Assert-Check ($objectiveDocumentText.Contains('R3-ACTUAL-DOCS-CONSISTENCY-AUDIT')) 'Objective Markdown does not contain the actual-docs audit target.'
  Add-Check -Id 'objective_binding' -Detail 'Machine objective, attached objective and Markdown target are bound to the same revision.' -Evidence @((Get-RelativePath $objectivePath), (Get-RelativePath $objectiveDocumentPath))

  $mirrorHeader = '基线：书源数=458；SHA-256=`' + [string]$baseline.sourcePackageSha256 + '`；Legado=`' + [string]$baseline.legadoCommit + '`；activeTask=`COMPAT-006`；activeIssue=`ISSUE-COMPAT-014`'
  Assert-Check ($governanceText.Contains($mirrorHeader)) 'Governance task mirror header is stale.'
  Assert-Check ($governanceText -match '\| issue \| ISSUE-COMPAT-014 \| verifying \|') 'Governance task mirror does not show ISSUE-COMPAT-014=verifying.'
  Assert-Check ($governanceText -match '\| issue \| ISSUE-COMPAT-015 \| planned \|') 'Governance task mirror does not show ISSUE-COMPAT-015=planned.'
  Assert-Check ($ledgerText.Contains('完整验证=0/458')) 'Progress ledger does not preserve the observed 0/458 device qualification.'
  Assert-Check ($indexText -match '\| `ISSUE-COMPAT-014` \| `verifying` \|') 'Evidence index does not show ISSUE-COMPAT-014=verifying.'
  Assert-Check ($diffText -match '\| `ISSUE-COMPAT-015` \| `planned` \|') 'Diff summary does not show ISSUE-COMPAT-015=planned.'
  Add-Check -Id 'document_mirror' -Detail 'Governance mirror, ledger, evidence index and diff summary retain the machine queue and incomplete device qualification.' -Evidence @((Get-RelativePath $governancePath), (Get-RelativePath $ledgerPath), (Get-RelativePath $indexPath), (Get-RelativePath $diffPath))

  $hashAudit = Read-StrictJson -Path $auditHashPath
  Assert-Check ([string]$hashAudit.status -eq 'passed_with_historical_superseded_evidence') 'Source-fix hash audit is not classified as historical superseded evidence.'
  Assert-Check (-not [bool]$hashAudit.newIssueRequired) 'Source-fix hash audit unexpectedly requires a new issue.'
  Assert-Check ([string]$hashAudit.baseline.sourcePackageSha256 -eq [string]$baseline.sourcePackageSha256) 'Hash audit source package baseline differs.'
  Assert-Check ([string]$hashAudit.baseline.legadoCommit -eq [string]$baseline.legadoCommit) 'Hash audit Legado baseline differs.'
  Add-Check -Id 'source_fix_classification' -Detail 'Historical source-fix hash drift is classified and no unexplained current-root-cause issue is introduced.' -Evidence @((Get-RelativePath $auditHashPath))

  $summary = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_actual_docs_consistency_audit'
    status = 'passed'
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    machineFactSource = 'tools/legado-compat/state/full-source-validation-state.json'
    baseline = [pscustomobject][ordered]@{
      sourceCount = [int]$baseline.sourceCount
      sourcePackageSha256 = [string]$baseline.sourcePackageSha256
      legadoCommit = [string]$baseline.legadoCommit
    }
    queue = [pscustomobject][ordered]@{
      activeTaskId = [string]$governance.activeTaskId
      activeIssueId = [string]$governance.activeIssueId
      issue014 = [string]$issue014.status
      issue015 = [string]$issue015.status
    }
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @(
      'tools/legado-compat/state/full-source-validation-state.json',
      'tools/legado-compat/state/refactor-objective.json',
      'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md',
      'docs/analysis/Legado书源V2源码重构持续目标.md',
      'docs/analysis/Legado书源引擎兼容推进台账.md',
      'docs/analysis/Legado书源引擎证据索引.md',
      'docs/analysis/Legado书源引擎差分摘要.md',
      'tools/legado-compat/evidence/r3-source-fix-hash-audit-20260808-r1.json'
    )
    runtimeActionsPerformed = @()
    verificationPolicy = 'r3_actual_docs_and_evidence_consistency_only;R4_runtime_build_device_and_legado_diff_deferred'
    semanticMatchAllowed = $false
    newIssueRequired = $false
  }
} catch {
  $exitCode = 1
  $summary = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_actual_docs_consistency_audit'
    status = 'failed'
    objectiveId = 'LEGADO-V2-SOURCE-CLOSURE-R3-20260808'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    machineFactSource = 'tools/legado-compat/state/full-source-validation-state.json'
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @()
    runtimeActionsPerformed = @()
    verificationPolicy = 'r3_actual_docs_and_evidence_consistency_only;R4_runtime_build_device_and_legado_diff_deferred'
    semanticMatchAllowed = $false
    newIssueRequired = $true
  }
}

$temporaryPath = "$outputFullPath.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
[System.IO.File]::WriteAllText($temporaryPath, ($summary | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $outputFullPath -Force
Write-Output ($summary | ConvertTo-Json -Depth 20)
if ($exitCode -ne 0) { exit $exitCode }
