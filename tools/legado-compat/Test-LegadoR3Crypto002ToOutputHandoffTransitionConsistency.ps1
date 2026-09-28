[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RunId = 'r3-output-handoff-005-transition-consistency-20260808-r1',
  [string]$OutputPath = '',
  [switch]$RequireRegistration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($RepositoryRoot.Length -eq 0) { $RepositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$evidenceRoot = (Resolve-Path -LiteralPath (Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).Path
$runDirectory = Join-Path $evidenceRoot $RunId
if ($OutputPath.Length -eq 0) { $OutputPath = Join-Path $runDirectory 'transition-consistency.json' }
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$evidencePrefix = $evidenceRoot.TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidencePrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Output handoff transition evidence must remain under the evidence directory.' }
if (-not (Test-Path -LiteralPath $runDirectory)) { [System.IO.Directory]::CreateDirectory($runDirectory) | Out-Null }

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:checks = New-Object 'System.Collections.Generic.List[object]'
$script:assertions = 0

function Read-StrictUtf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw "Required file is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  try { return (Read-StrictUtf8Text -Path $Path | ConvertFrom-Json) } catch { throw "Invalid JSON: $Path; $($_.Exception.Message)" }
}

function Get-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Get-Issue {
  param([object[]]$Issues, [string]$Id)
  foreach ($issue in $Issues) { if ([string](Get-PropertyValue -Object $issue -Name 'id') -eq $Id) { return $issue } }
  return $null
}

function Assert-Gate {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
  $script:assertions++
}

function Add-Check {
  param([string]$Id, [string]$Detail, [string[]]$Evidence = @())
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) })
}

$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$objectivePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\refactor-objective.json'
$sourceFixPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-output-handoff-source-fix-20260808.json'
$auditPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-output-handoff-current-head-hash-audit-20260808-r1\current-head-hash-audit.json'
$staticContractPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-output-handoff-20260808-r4.json'
$objectiveDocumentPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源V2源码重构持续目标.md'
$governancePath = Join-Path $RepositoryRoot 'tools\legado-compat\LEGADO_V2_GOVERNANCE_TASKS.md'
$ledgerPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎兼容推进台账.md'
$indexPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎证据索引.md'
$diffPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎差分摘要.md'
$relativeOutputPath = 'tools/legado-compat/evidence/' + $RunId + '/transition-consistency.json'

$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -Path $statePath
  $objective = Read-StrictJson -Path $objectivePath
  $sourceFix = Read-StrictJson -Path $sourceFixPath
  $audit = Read-StrictJson -Path $auditPath
  $staticContract = Read-StrictJson -Path $staticContractPath
  $baseline = $state.baseline
  Assert-Gate ([int]$baseline.sourceCount -eq 458 -and [string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine baseline is not frozen.'
  $legadoHead = (& git -C (Join-Path $RepositoryRoot 'legado') rev-parse HEAD 2>$null | Out-String).Trim()
  Assert-Gate ($legadoHead -eq [string]$baseline.legadoCommit) 'Legado checkout is not at the frozen commit.'
  Add-Check -Id 'baseline_binding' -Detail 'Queue transition remains bound to the frozen source and Legado baselines.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json')

  $governance = $state.governance
  $issues = @($governance.issues)
  $crypto = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-CRYPTO-002'
  $output = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-005'
  Assert-Gate ([string]$governance.activeTaskId -eq 'COMPAT-006' -and [string]$governance.activeIssueId -eq 'ISSUE-COMPAT-005' -and [string]$governance.status -eq 'running') 'machine governance queue is not registered on output handoff 005.'
  Assert-Gate ($null -ne $crypto -and [string]$crypto.status -eq 'verifying') 'Crypto-002 must remain verifying for deferred R4.'
  Assert-Gate ($null -ne $output -and [string]$output.status -eq 'verifying') 'Output handoff 005 must remain verifying after static closure.'
  $outputEvidence = @($output.evidencePaths | ForEach-Object { [string]$_ })
  Assert-Gate ($outputEvidence -contains 'tools/legado-compat/evidence/v2-output-handoff-source-fix-20260808.json' -and $outputEvidence -contains 'tools/legado-compat/evidence/v2-output-handoff-current-head-hash-audit-20260808-r1/current-head-hash-audit.json') 'Output handoff evidence registration is incomplete.'
  Add-Check -Id 'machine_queue' -Detail 'The unique source queue is atomically registered on ISSUE-COMPAT-005; Crypto-002 remains deferred to R4.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json')

  Assert-Gate ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-005' -and [string]$objective.objective.activeIssue -eq 'ISSUE-COMPAT-005') 'objective active issue is not output handoff 005.'
  Assert-Gate ([string]$objective.objective.queueSelectionGate.selectedIssue -eq 'ISSUE-COMPAT-005' -and @($objective.objective.queueSelectionGate.candidateIssues) -contains 'ISSUE-COMPAT-012') 'objective queue selection is not 005 -> 012.'
  Assert-Gate ([string]$objective.executionTarget.currentIssue -eq 'ISSUE-COMPAT-005' -and @($objective.executionTarget.nextIssues) -contains 'ISSUE-COMPAT-012') 'objective execution target is not 005 -> 012.'
  Assert-Gate ([string]$sourceFix.status -eq 'source_fix_applied_pending_verification' -and [string]$audit.status -eq 'current_head_bound_static_closure' -and [string]$staticContract.status -eq 'passed' -and [int]$staticContract.assertions -eq 43 -and -not [bool]$sourceFix.semanticMatchAllowed -and -not [bool]$audit.semanticMatchAllowed) 'Output handoff static evidence contains an invalid claim.'
  Add-Check -Id 'objective_and_source_evidence' -Detail 'Objective, source fix, current-head audit and 43-assertion contract agree on 005 as the sole active static-closure issue.' -Evidence @('tools/legado-compat/state/refactor-objective.json', 'tools/legado-compat/evidence/v2-output-handoff-source-fix-20260808.json', 'tools/legado-compat/evidence/v2-output-handoff-current-head-hash-audit-20260808-r1/current-head-hash-audit.json')

  $objectiveDocument = Read-StrictUtf8Text -Path $objectiveDocumentPath
  $governanceDocument = Read-StrictUtf8Text -Path $governancePath
  $ledgerDocument = Read-StrictUtf8Text -Path $ledgerPath
  $indexDocument = Read-StrictUtf8Text -Path $indexPath
  $diffDocument = Read-StrictUtf8Text -Path $diffPath
  Assert-Gate ($objectiveDocument.Contains([string]$objective.targetRevision) -and $objectiveDocument.Contains('当前唯一源码验证议题已原子切换为 `ISSUE-COMPAT-005`') -and $objectiveDocument.Contains('下一候选为 `ISSUE-COMPAT-012`')) 'objective Markdown does not describe output handoff 005.'
  Assert-Gate ($governanceDocument.Contains('activeIssue=`ISSUE-COMPAT-005`') -and $governanceDocument -match '\| issue \| ISSUE-COMPAT-005 \| verifying \|') 'governance mirror does not describe output handoff 005.'
  if ($RequireRegistration) { Assert-Gate ($outputEvidence -contains $relativeOutputPath -and $indexDocument.Contains($relativeOutputPath) -and $diffDocument.Contains($relativeOutputPath)) 'Output handoff transition evidence is not registered in state and generated documents.' }
  Add-Check -Id 'document_mirror' -Detail 'Objective Markdown, governance mirror, ledger, evidence index and diff summary agree on output handoff 005 and retain the Crypto boundary.' -Evidence @('docs/analysis/Legado书源V2源码重构持续目标.md', 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md', 'docs/analysis/Legado书源引擎兼容推进台账.md', 'docs/analysis/Legado书源引擎证据索引.md', 'docs/analysis/Legado书源引擎差分摘要.md')

  $result = [pscustomobject][ordered]@{ schemaVersion = 1; kind = 'legado_r3_output_handoff_005_transition_consistency'; status = 'passed'; issueId = 'ISSUE-COMPAT-005'; generatedAt = [DateTimeOffset]::UtcNow.ToString('o'); objectiveId = [string]$objective.objectiveId; targetRevision = [string]$objective.targetRevision; transition = [pscustomobject][ordered]@{ fromIssue = 'ISSUE-COMPAT-CRYPTO-002'; fromStatus = 'verifying'; toIssue = 'ISSUE-COMPAT-005'; toStatus = 'verifying'; nextCandidate = 'ISSUE-COMPAT-012'; runtimeVerification = 'deferred_to_R4' }; baseline = [pscustomobject][ordered]@{ sourceCount = [int]$baseline.sourceCount; sourcePackageSha256 = [string]$baseline.sourcePackageSha256; legadoCommit = [string]$baseline.legadoCommit }; assertions = $script:assertions; checks = $script:checks.ToArray(); evidencePaths = @('tools/legado-compat/state/refactor-objective.json', 'tools/legado-compat/state/full-source-validation-state.json', 'tools/legado-compat/evidence/v2-output-handoff-source-fix-20260808.json', 'tools/legado-compat/evidence/v2-output-handoff-current-head-hash-audit-20260808-r1/current-head-hash-audit.json'); runtimeActionsPerformed = @(); semanticMatchAllowed = $false; verificationPolicy = 'r3_output_handoff_005_transition_consistency_read_only;R4_runtime_build_device_and_legado_diff_deferred'; registrationRequired = [bool]$RequireRegistration }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{ schemaVersion = 1; kind = 'legado_r3_output_handoff_005_transition_consistency'; status = 'failed'; issueId = 'ISSUE-COMPAT-005'; generatedAt = [DateTimeOffset]::UtcNow.ToString('o'); failure = $_.Exception.Message; assertions = $script:assertions; checks = $script:checks.ToArray(); evidencePaths = @(); runtimeActionsPerformed = @(); semanticMatchAllowed = $false; verificationPolicy = 'r3_output_handoff_005_transition_consistency_read_only;R4_runtime_build_device_and_legado_diff_deferred'; registrationRequired = [bool]$RequireRegistration }
}

$temporaryPath = "$outputFullPath.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
[System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 24), [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $outputFullPath -Force
$result | ConvertTo-Json -Depth 24
if ($exitCode -ne 0) { exit $exitCode }
