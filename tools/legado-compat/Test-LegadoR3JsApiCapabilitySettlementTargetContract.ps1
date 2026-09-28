[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path

$targetRevision = '2026-08-09-actual-docs-source-refactor-js-api-capability-settlement-preflight-037'
$objectivePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\refactor-objective.json'
$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$matrixPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\legado-js-api-usage-matrix.json'
$targetPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\r3-js-api-capability-settlement-preflight-20260809\target.json'
$mappingPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\r3-js-api-capability-settlement-preflight-20260809\reference-mapping.json'
$objectiveDocumentPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源V2源码重构持续目标.md'
$governanceDocumentPath = Join-Path $RepositoryRoot 'tools\legado-compat\LEGADO_V2_GOVERNANCE_TASKS.md'
$contractEvidencePath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\r3-js-api-capability-settlement-preflight-20260809\target-contract.json'

$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$activeIssue = 'ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH'

function Read-JsonObject {
  param([string]$Path)
  $encoding = [System.Text.UTF8Encoding]::new($false, $true)
  return $encoding.GetString([System.IO.File]::ReadAllBytes($Path)) | ConvertFrom-Json
}

function Assert-Contract {
  param([bool]$Condition, [string]$Name, [string]$Detail)
  $script:assertions++
  if (-not $Condition) {
    $script:failures.Add([pscustomobject][ordered]@{ name = $Name; detail = $Detail }) | Out-Null
  }
}

function Write-AtomicJson {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$Path.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  $encoding = [System.Text.UTF8Encoding]::new($false)
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 20), $encoding)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      [System.IO.File]::Delete($temporaryPath)
    }
  }
}

$script:assertions = 0
$script:failures = New-Object 'System.Collections.Generic.List[object]'
$paths = @($objectivePath, $statePath, $matrixPath, $targetPath, $mappingPath, $objectiveDocumentPath, $governanceDocumentPath)
foreach ($path in $paths) {
  Assert-Contract (Test-Path -LiteralPath $path -PathType Leaf) 'file_exists' ("Required file exists: {0}" -f $path)
}

$objective = Read-JsonObject $objectivePath
$state = Read-JsonObject $statePath
$matrix = Read-JsonObject $matrixPath
$target = Read-JsonObject $targetPath
$mapping = Read-JsonObject $mappingPath
$objectiveDocument = [System.Text.UTF8Encoding]::new($false, $true).GetString([System.IO.File]::ReadAllBytes($objectiveDocumentPath))
$governanceDocument = [System.Text.UTF8Encoding]::new($false, $true).GetString([System.IO.File]::ReadAllBytes($governanceDocumentPath))

Assert-Contract ([string]$objective.targetRevision -eq $targetRevision) 'objective_revision' 'Machine objective uses the current JS API settlement revision.'
Assert-Contract ([string]$state.governance.refactorObjective.targetRevision -eq $targetRevision) 'attached_revision' 'Canonical state attaches the same objective revision.'
Assert-Contract ([string]$state.governance.activeIssueId -eq $activeIssue) 'active_issue' '037 remains the only machine active issue.'
Assert-Contract ([string]$objective.authority.activeIssueId -eq $activeIssue -and [string]$objective.objective.activeIssue -eq $activeIssue) 'objective_active_issue' 'Objective active issue agrees with the machine queue.'
Assert-Contract ([string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$objective.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$matrix.sourcePackageSha256 -eq $sourceHash -and [string]$target.baseline.sourcePackageSha256 -eq $sourceHash) 'source_hash' 'All target inputs use the frozen source package hash.'
Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [int]$objective.baseline.sourceCount -eq 458 -and [int]$matrix.sourceCount -eq 458 -and [int]$target.baseline.sourceCount -eq 458) 'source_count' 'All target inputs use 458 sources.'
Assert-Contract ([string]$state.baseline.legadoCommit -eq $legadoCommit -and [string]$objective.baseline.legadoCommit -eq $legadoCommit -and [string]$target.baseline.legadoCommit -eq $legadoCommit) 'legado_commit' 'All target inputs use the frozen Legado commit.'
Assert-Contract ([string]$matrix.status -eq 'passed' -and [int]$matrix.summary.apiReferenceCount -eq 118 -and [int]$matrix.summary.registeredExact + [int]$matrix.summary.registeredPrefix -eq 74 -and [int]$matrix.summary.unregistered -eq 44) 'matrix_counts' 'The static matrix remains 118 references, 74 registered references and 44 unregistered candidates.'
Assert-Contract ([int]$objective.objective.apiCapabilitySettlement.observedReferenceCount -eq 118 -and [int]$objective.objective.apiCapabilitySettlement.observedRegisteredCount -eq 74 -and [int]$objective.objective.apiCapabilitySettlement.observedUnregisteredCount -eq 44) 'objective_matrix_counts' 'The machine objective records the matrix counts.'
Assert-Contract ([int]$objective.objective.apiCapabilitySettlement.observedUnregisteredOccurrenceCount -eq 140 -and [int]$objective.objective.apiCapabilitySettlement.mappedUnregisteredOccurrenceCount -eq 140 -and [int]$objective.objective.apiCapabilitySettlement.unmappedReferenceCount -eq 0) 'objective_mapping_counts' 'The machine objective records complete 140-occurrence mapping.'
Assert-Contract ([string]$target.targetRevision -eq $targetRevision -and [int]$target.matrixEvidence.apiReferenceCount -eq 118 -and [int]$target.matrixEvidence.registeredReferencedCount -eq 74 -and [int]$target.matrixEvidence.unregisteredReferenceCount -eq 44) 'target_evidence_binding' 'Target evidence is bound to the current revision and matrix.'
Assert-Contract ([string]$mapping.status -eq 'passed' -and [int]$mapping.unregisteredApiCount -eq 44 -and [int]$mapping.matrixUniqueApiCount -eq 44 -and [int]$mapping.matrixReferenceCount -eq 140 -and [int]$mapping.mappedReferenceCount -eq 140 -and @($mapping.unmappedApis).Count -eq 0) 'reference_mapping' 'Every unregistered API token and all 140 matrix occurrences are mapped with no unmapped token.'
Assert-Contract ([int]$target.referenceMapping.mappedApiCount -eq 44 -and [int]$target.referenceMapping.mappedOccurrenceCount -eq 140 -and [int]$target.referenceMapping.unmappedApiCount -eq 0) 'target_mapping_binding' 'Target evidence records the completed 44-token/140-occurrence mapping.'
Assert-Contract ([int]$target.candidateGate.candidateCount -eq 0 -and -not [bool]$target.candidateGate.semanticMatchAllowed -and @($target.candidateGate.runtimeActionsPerformed).Count -eq 0) 'static_only_gate' 'No candidate, runtime action or semantic match is allowed at this preflight.'
Assert-Contract ($objectiveDocument.Contains($targetRevision) -and $objectiveDocument.Contains('R3-JS-API-CAPABILITY-SETTLEMENT-PREFLIGHT') -and $objectiveDocument.Contains('44 个未注册')) 'objective_document' 'Objective Markdown contains the current revision and API settlement boundary.'
Assert-Contract ($governanceDocument.Contains($targetRevision) -and $governanceDocument.Contains('R3 JS API 能力结算前置目标')) 'governance_document' 'Governance task ledger contains the current target section.'

$resultStatus = if ($script:failures.Count -eq 0) { 'passed' } else { 'failed' }
$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_js_api_capability_settlement_target_contract'
  status = $resultStatus
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  targetRevision = $targetRevision
  activeIssueId = $activeIssue
  assertions = $script:assertions
  failures = @($script:failures.ToArray())
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  evidencePaths = @(
    'tools/legado-compat/state/refactor-objective.json',
    'tools/legado-compat/state/full-source-validation-state.json',
    'tools/legado-compat/evidence/legado-js-api-usage-matrix.json',
    'tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/target.json',
    'tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/reference-mapping.json',
    'docs/analysis/Legado书源V2源码重构持续目标.md',
    'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
  )
}
Write-AtomicJson -Path $contractEvidencePath -Value $result
if ($script:failures.Count -gt 0) {
  throw ('JS API settlement target contract failed: {0} assertion(s) failed. Evidence: {1}' -f $script:failures.Count, $contractEvidencePath)
}
Write-Output ('JS_API_SETTLEMENT_TARGET_CONTRACT status=passed assertions={0} evidence={1} runtimeActions=0 semanticMatchAllowed=false' -f $script:assertions, $contractEvidencePath)
