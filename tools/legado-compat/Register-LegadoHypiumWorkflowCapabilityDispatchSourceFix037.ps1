[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/v2-hypium-workflow-capability-dispatch-source-fix-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH'
$failurePath = 'tools/legado-compat/evidence/contract-legado-hypium-workflow-capability-dispatch-037-pre-fix.json'
$contractPath = 'tools/legado-compat/evidence/contract-legado-hypium-workflow-capability-dispatch-037.json'
$auditPath = 'tools/legado-compat/evidence/v2-hypium-workflow-capability-dispatch-current-head-audit-20260809.json'
$fixturePath = 'tools/legado-compat/fixtures/legado-hypium-workflow-capability-dispatch-037.json'
$sourcePaths = @(
  'tools/legado-compat/Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1',
  'tools/legado-compat/Invoke-LegadoV2HypiumNavigation.py',
  'tools/legado-compat/LegadoHypiumWorkflowSettlement.psm1'
)
$contractScriptPath = 'tools/legado-compat/Test-LegadoV2HypiumWorkflowCapabilityDispatchContract.ps1'
$auditScriptPath = 'tools/legado-compat/Test-LegadoR3WorkflowCapabilityDispatchCurrentHeadAudit.ps1'

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required JSON missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return ($strictUtf8.GetString($bytes) | ConvertFrom-Json)
}

function Get-Sha256 {
  param([string]$Path)
  $algorithm = [System.Security.Cryptography.SHA256]::Create()
  try { return ([System.BitConverter]::ToString($algorithm.ComputeHash([System.IO.File]::ReadAllBytes($Path)))).Replace('-', '') }
  finally { $algorithm.Dispose() }
}

function Assert-SourceFix {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "037 source-fix evidence blocked: $Message" }
}

function Write-AtomicJson {
  param([string]$RelativePath, [object]$Value)
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 60), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$objective = Read-StrictJson 'tools/legado-compat/state/refactor-objective.json'
$failure = Read-StrictJson $failurePath
$contract = Read-StrictJson $contractPath
$audit = Read-StrictJson $auditPath
$fixture = Read-StrictJson $fixturePath
Assert-SourceFix ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'fixed machine baseline drifted.'
Assert-SourceFix ([string]$failure.status -eq 'failed' -and [string]$failure.issueId -eq $issueId -and @($failure.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed) 'pre-fix failure witness is not static-only.'
Assert-SourceFix ([string]$contract.status -eq 'passed' -and [int]$contract.assertions -ge 29 -and @($contract.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$contract.semanticMatchAllowed) 'post-fix contract is not a static-only pass.'
Assert-SourceFix ([string]$audit.status -eq 'passed' -and [int]$audit.assertions -ge 27 -and @($audit.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$audit.semanticMatchAllowed) 'current-head audit is not a static-only pass.'
Assert-SourceFix (@($fixture.cases).Count -eq 6) 'capability fixture count drifted.'

$hashes = [ordered]@{}
foreach ($relativePath in $sourcePaths + @($contractScriptPath, $auditScriptPath)) {
  $path = Get-RepoPath $relativePath
  Assert-SourceFix (Test-Path -LiteralPath $path -PathType Leaf) "source file is missing: $relativePath"
  $hashes[$relativePath] = Get-Sha256 $path
}

$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'legado_hypium_workflow_capability_dispatch_source_fix_037'
  issueId = $issueId
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  objectiveId = [string]$objective.objectiveId
  targetRevision = '2026-08-09-actual-docs-source-refactor-continuation-capability-settlement-037'
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  failureWitness = $failurePath
  fixture = $fixturePath
  staticContract = $contractPath
  currentHeadAudit = $auditPath
  rootCause = 'safe_read_path and Explore-only dispatch coupled entry URL presence, capability planning and terminal settlement. A missing Search URL could prematurely project a whole profile, and an Explore-only source with incomplete BookInfo/Toc/Content capabilities could start a read chain whose traces could never be validly consumed.'
  changes = @(
    [pscustomobject][ordered]@{ path = 'tools/legado-compat/Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1'; change = 'Plan Search and Explore independently, gate Explore read continuation on the complete BookInfo/Toc/Content capability set, and settle missing/dependent workflows with explicit outcomes.' },
    [pscustomobject][ordered]@{ path = 'tools/legado-compat/Invoke-LegadoV2HypiumNavigation.py'; change = 'Replace profile-wide Explore-only placeholders with workflow-specific missing/not-requested outcomes so UI evidence cannot claim an unexecuted workflow was settled by profile.' },
    [pscustomobject][ordered]@{ path = 'tools/legado-compat/LegadoHypiumWorkflowSettlement.psm1'; change = 'Retain pure dependency settlement as the shared terminal projection boundary; no runtime actions are performed by this evidence step.' }
  )
  affectedStaticSet = [pscustomobject][ordered]@{ sourceCount = 458; searchUrlCount = 447; exploreUrlCount = 362; dualEntryCount = 351; exploreOnlyCount = 11; workflowCases = 6 }
  currentHeadHashes = $hashes
  contractAssertions = [int]$contract.assertions
  auditAssertions = [int]$audit.assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_source_fix_static_only;candidate_registration_pending;R4_runtime_build_device_and_legado_diff_deferred'
  closeCondition = 'R4 must execute fresh safe_read/full_workflow traces for affected capability classes, compare the same input with fixed Legado, and complete the unified runtime/build/device gates. Static closure alone must remain verifying.'
}
Write-AtomicJson -RelativePath $OutputPath -Value $sourceFix
$sourceFix | ConvertTo-Json -Depth 60
