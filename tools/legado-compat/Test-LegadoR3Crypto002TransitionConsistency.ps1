[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RunId = 'r3-crypto-002-transition-consistency-20260808-r1',
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
if (-not $outputFullPath.StartsWith($evidencePrefix, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Crypto transition evidence must remain under the evidence directory.' }
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

function Get-Sha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$objectivePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\refactor-objective.json'
$sourceFixPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-crypto-002-source-fix-20260808.json'
$auditPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-crypto-002-current-head-hash-audit-20260808-r1\current-head-hash-audit.json'
$contractEvidencePath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-crypto-002-static-contract-20260808.json'
$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\v2-crypto-002-transformation-matrix.json'
$objectiveDocumentPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源V2源码重构持续目标.md'
$governancePath = Join-Path $RepositoryRoot 'tools\legado-compat\LEGADO_V2_GOVERNANCE_TASKS.md'
$ledgerPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎兼容推进台账.md'
$indexPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎证据索引.md'
$diffPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎差分摘要.md'
$packagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
$relativeOutputPath = 'tools/legado-compat/evidence/' + $RunId + '/transition-consistency.json'

$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -Path $statePath
  $objective = Read-StrictJson -Path $objectivePath
  $sourceFix = Read-StrictJson -Path $sourceFixPath
  $audit = Read-StrictJson -Path $auditPath
  $contractEvidence = Read-StrictJson -Path $contractEvidencePath
  $fixture = Read-StrictJson -Path $fixturePath
  $baseline = $state.baseline
  Assert-Gate ([int]$baseline.sourceCount -eq 458 -and [string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine baseline is not frozen.'
  Assert-Gate ((Get-Sha256 -Path $packagePath) -eq [string]$baseline.sourcePackageSha256) 'source package hash drifted.'
  Assert-Gate ((& git -C (Join-Path $RepositoryRoot 'legado') rev-parse HEAD 2>$null | Out-String).Trim() -eq [string]$baseline.legadoCommit) 'Legado checkout is not at the frozen commit.'
  Add-Check -Id 'baseline_binding' -Detail 'State, source package and Legado checkout remain bound to the frozen baseline.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json')

  $governance = $state.governance
  $issues = @($governance.issues)
  $previous = Get-Issue -Issues $issues -Id 'V2-GOV-004-DOCUMENT-TASK-MIRROR'
  $current = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-CRYPTO-002'
  Assert-Gate ([string]$governance.activeTaskId -eq 'COMPAT-006' -and [string]$governance.activeIssueId -eq 'ISSUE-COMPAT-CRYPTO-002' -and [string]$governance.status -eq 'running') 'machine governance queue is not registered on Crypto-002.'
  Assert-Gate ($null -ne $previous -and [string]$previous.status -eq 'verifying') 'V2-GOV-004 must remain verifying for deferred R4.'
  Assert-Gate ($null -ne $current -and [string]$current.status -eq 'verifying') 'Crypto-002 must remain verifying after static closure.'
  $currentEvidence = @($current.evidencePaths | ForEach-Object { [string]$_ })
  Assert-Gate ($currentEvidence -contains 'tools/legado-compat/evidence/v2-crypto-002-source-fix-20260808.json' -and $currentEvidence -contains 'tools/legado-compat/evidence/v2-crypto-002-current-head-hash-audit-20260808-r1/current-head-hash-audit.json') 'Crypto evidence registration is incomplete.'
  Add-Check -Id 'machine_queue' -Detail 'The unique source queue is atomically registered on Crypto-002; prior static closures remain deferred to R4.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json')

  Assert-Gate ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-CRYPTO-002' -and [string]$objective.objective.activeIssue -eq 'ISSUE-COMPAT-CRYPTO-002') 'objective active issue is not Crypto-002.'
  Assert-Gate ([string]$objective.objective.queueSelectionGate.selectedIssue -eq 'ISSUE-COMPAT-CRYPTO-002' -and @($objective.objective.queueSelectionGate.candidateIssues) -contains 'ISSUE-COMPAT-005') 'objective queue selection is not Crypto-002 -> output handoff.'
  Assert-Gate ([string]$objective.executionTarget.currentIssue -eq 'ISSUE-COMPAT-CRYPTO-002' -and @($objective.executionTarget.nextIssues) -contains 'ISSUE-COMPAT-005') 'objective execution target is not Crypto-002 -> output handoff.'
  Assert-Gate ([string]$sourceFix.status -eq 'source_fix_applied_pending_verification' -and [string]$audit.status -eq 'current_head_bound_static_closure' -and [string]$contractEvidence.status -eq 'passed' -and -not [bool]$sourceFix.semanticMatchAllowed -and -not [bool]$audit.semanticMatchAllowed) 'Crypto static evidence contains an invalid status or semantic claim.'
  Assert-Gate ([string]$fixture.issueId -eq 'ISSUE-COMPAT-CRYPTO-002' -and [string]$fixture.verificationPolicy -match 'runtime_regression_deferred_to_R4') 'Crypto fixture policy is not R4-deferred.'
  Add-Check -Id 'objective_and_source_evidence' -Detail 'Objective, fixture, source fix, static contract and current-head audit agree on Crypto-002 as the sole active static-closure issue.' -Evidence @('tools/legado-compat/state/refactor-objective.json', 'tools/legado-compat/evidence/v2-crypto-002-source-fix-20260808.json', 'tools/legado-compat/evidence/v2-crypto-002-current-head-hash-audit-20260808-r1/current-head-hash-audit.json')

  $objectiveDocument = Read-StrictUtf8Text -Path $objectiveDocumentPath
  $governanceDocument = Read-StrictUtf8Text -Path $governancePath
  $ledgerDocument = Read-StrictUtf8Text -Path $ledgerPath
  $indexDocument = Read-StrictUtf8Text -Path $indexPath
  $diffDocument = Read-StrictUtf8Text -Path $diffPath
  Assert-Gate ($objectiveDocument.Contains([string]$objective.targetRevision) -and $objectiveDocument.Contains('当前唯一源码验证议题已原子切换为 `ISSUE-COMPAT-CRYPTO-002`') -and $objectiveDocument.Contains('下一候选为 `ISSUE-COMPAT-005`')) 'objective Markdown does not describe Crypto-002.'
  Assert-Gate ($governanceDocument.Contains('activeIssue=`ISSUE-COMPAT-CRYPTO-002`') -and $governanceDocument -match '\| issue \| ISSUE-COMPAT-CRYPTO-002 \| verifying \|') 'governance mirror does not describe Crypto-002.'
  if ($RequireRegistration) { Assert-Gate ($currentEvidence -contains $relativeOutputPath -and $indexDocument.Contains($relativeOutputPath) -and $diffDocument.Contains($relativeOutputPath)) 'Crypto transition evidence is not registered in machine state and generated documents.' }
  Add-Check -Id 'document_mirror' -Detail 'Objective Markdown, governance mirror, ledger, evidence index and diff summary agree on Crypto-002 and retain the V2-GOV-004 historical boundary.' -Evidence @('docs/analysis/Legado书源V2源码重构持续目标.md', 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md', 'docs/analysis/Legado书源引擎兼容推进台账.md', 'docs/analysis/Legado书源引擎证据索引.md', 'docs/analysis/Legado书源引擎差分摘要.md')

  $result = [pscustomobject][ordered]@{ schemaVersion = 1; kind = 'legado_r3_crypto_002_transition_consistency'; status = 'passed'; issueId = 'ISSUE-COMPAT-CRYPTO-002'; generatedAt = [DateTimeOffset]::UtcNow.ToString('o'); objectiveId = [string]$objective.objectiveId; targetRevision = [string]$objective.targetRevision; transition = [pscustomobject][ordered]@{ fromIssue = 'V2-GOV-004-DOCUMENT-TASK-MIRROR'; fromStatus = 'verifying'; toIssue = 'ISSUE-COMPAT-CRYPTO-002'; toStatus = 'verifying'; nextCandidate = 'ISSUE-COMPAT-005'; runtimeVerification = 'deferred_to_R4' }; baseline = [pscustomobject][ordered]@{ sourceCount = [int]$baseline.sourceCount; sourcePackageSha256 = [string]$baseline.sourcePackageSha256; legadoCommit = [string]$baseline.legadoCommit }; assertions = $script:assertions; checks = $script:checks.ToArray(); evidencePaths = @('tools/legado-compat/state/refactor-objective.json', 'tools/legado-compat/state/full-source-validation-state.json', 'tools/legado-compat/evidence/v2-crypto-002-source-fix-20260808.json', 'tools/legado-compat/evidence/v2-crypto-002-current-head-hash-audit-20260808-r1/current-head-hash-audit.json'); runtimeActionsPerformed = @(); semanticMatchAllowed = $false; verificationPolicy = 'r3_crypto_002_transition_consistency_read_only;R4_runtime_build_device_and_legado_diff_deferred'; registrationRequired = [bool]$RequireRegistration }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{ schemaVersion = 1; kind = 'legado_r3_crypto_002_transition_consistency'; status = 'failed'; issueId = 'ISSUE-COMPAT-CRYPTO-002'; generatedAt = [DateTimeOffset]::UtcNow.ToString('o'); failure = $_.Exception.Message; assertions = $script:assertions; checks = $script:checks.ToArray(); evidencePaths = @(); runtimeActionsPerformed = @(); semanticMatchAllowed = $false; verificationPolicy = 'r3_crypto_002_transition_consistency_read_only;R4_runtime_build_device_and_legado_diff_deferred'; registrationRequired = [bool]$RequireRegistration }
}

$temporaryPath = "$outputFullPath.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
[System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 24), [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $outputFullPath -Force
$result | ConvertTo-Json -Depth 24
if ($exitCode -ne 0) { exit $exitCode }
