[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RunId = 'r3-015-queue-gate-20260808-r1',
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
  $OutputPath = Join-Path $runDirectory 'r3-015-queue-static-gate.json'
}
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$evidencePrefix = $evidenceRoot.TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidencePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw '015 queue gate output must remain under the evidence directory.'
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
  try {
    return ($text | ConvertFrom-Json)
  } catch {
    throw "Invalid JSON: $Path; $($_.Exception.Message)"
  }
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

function Assert-Gate {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
  $script:assertions++
}

function Add-Check {
  param([string]$Id, [string]$Detail, [string[]]$Evidence = @())
  [void]$script:checks.Add([pscustomobject][ordered]@{
      id = $Id
      status = 'passed'
      detail = $Detail
      evidencePaths = @($Evidence)
    })
}

function Get-Issue {
  param([object[]]$Issues, [string]$Id)
  foreach ($issue in $Issues) {
    if ([string](Get-PropertyValue -Object $issue -Name 'id') -eq $Id) { return $issue }
  }
  return $null
}

$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$objectivePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\refactor-objective.json'
$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-manga-reader-source-identity.json'
$contractPath = Join-Path $RepositoryRoot 'tools\legado-compat\Test-LegadoMangaReaderSourceIdentityContract.ps1'
$preFixPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-manga-reader-source-identity-contract-20260808-pre-fix.json'
$postFixPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\r3-015-source-closure-20260808-r1\manga-reader-source-identity-contract-post-fix.json'
$sourceFixPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\r3-015-source-closure-20260808-r1\v2-manga-reader-source-identity-source-fix-20260808-r1.json'
$transitionPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\r3-015-source-closure-20260808-r1\r3-source-queue-transition-20260808-r1.json'
$objectiveDocumentPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源V2源码重构持续目标.md'
$governancePath = Join-Path $RepositoryRoot 'tools\legado-compat\LEGADO_V2_GOVERNANCE_TASKS.md'
$ledgerPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎兼容推进台账.md'
$indexPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎证据索引.md'
$diffPath = Join-Path $RepositoryRoot 'docs\analysis\Legado书源引擎差分摘要.md'
$packagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'

$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -Path $statePath
  $objective = Read-StrictJson -Path $objectivePath
  $fixture = Read-StrictJson -Path $fixturePath
  $preFix = Read-StrictJson -Path $preFixPath
  $postFix = Read-StrictJson -Path $postFixPath
  $sourceFix = Read-StrictJson -Path $sourceFixPath
  $transition = Read-StrictJson -Path $transitionPath

  $baseline = $state.baseline
  Assert-Gate ([int]$baseline.sourceCount -eq 458) 'machine baseline source count is not 458.'
  Assert-Gate ((Get-Sha256 -Path $packagePath) -eq [string]$baseline.sourcePackageSha256) 'source package hash drifted from the machine baseline.'
  $legadoRoot = Join-Path $RepositoryRoot 'legado'
  $legadoCommit = (& git -C $legadoRoot rev-parse HEAD 2>$null | Out-String).Trim()
  Assert-Gate ($legadoCommit -eq [string]$baseline.legadoCommit) 'Legado checkout is not at the frozen commit.'
  Assert-Gate ([string]$objective.baseline.sourcePackageSha256 -eq [string]$baseline.sourcePackageSha256 -and [int]$objective.baseline.sourceCount -eq [int]$baseline.sourceCount -and [string]$objective.baseline.legadoCommit -eq [string]$baseline.legadoCommit) 'objective baseline differs from machine baseline.'
  Add-Check -Id 'baseline_binding' -Detail '458-source package, objective and Legado checkout remain bound to the frozen baseline.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json', 'tools/legado-compat/state/refactor-objective.json')

  $governance = $state.governance
  Assert-Gate ([string]$governance.activeTaskId -eq 'COMPAT-006') 'active task drifted from COMPAT-006.'
  Assert-Gate ([string]$governance.activeIssueId -eq 'ISSUE-COMPAT-015') 'active issue drifted from ISSUE-COMPAT-015.'
  Assert-Gate ([string]$governance.status -eq 'running') 'governance status is not running.'
  $issues = @($governance.issues)
  $issue014 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-014'
  $issue015 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-015'
  Assert-Gate ($null -ne $issue014 -and [string]$issue014.status -eq 'verifying') '014 must remain verifying for deferred R4.'
  Assert-Gate ($null -ne $issue015 -and [string]$issue015.status -eq 'verifying') '015 must be the current verifying issue.'
  Assert-Gate ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-015' -and [string]$objective.objective.activeIssue -eq 'ISSUE-COMPAT-015') 'objective active issue is not 015.'
  Assert-Gate ([string]$objective.objective.queueSelectionGate.currentAnchor -eq 'ISSUE-COMPAT-015' -and [string]$objective.objective.queueSelectionGate.selectedIssue -eq 'ISSUE-COMPAT-015') 'objective queue anchor is not 015.'
  Assert-Gate (@($objective.objective.queueSelectionGate.candidateIssues) -contains 'V2-HARNESS-023') 'Harness-023 is not the next candidate.'
  Add-Check -Id 'queue_binding' -Detail 'COMPAT-006 selects ISSUE-COMPAT-015; ISSUE-COMPAT-014 stays verifying and V2-HARNESS-023 is next.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json', 'tools/legado-compat/state/refactor-objective.json')

  $requiredEvidence = @(
    'tools/legado-compat/evidence/v2-manga-reader-source-identity-contract-20260808-pre-fix.json',
    'tools/legado-compat/evidence/r3-015-source-closure-20260808-r1/manga-reader-source-identity-contract-post-fix.json',
    'tools/legado-compat/evidence/r3-015-source-closure-20260808-r1/v2-manga-reader-source-identity-source-fix-20260808-r1.json',
    'tools/legado-compat/evidence/r3-015-source-closure-20260808-r1/r3-source-queue-transition-20260808-r1.json'
  )
  foreach ($relativeEvidence in $requiredEvidence) {
    $absoluteEvidence = Join-Path $RepositoryRoot ($relativeEvidence.Replace('/', '\'))
    Assert-Gate (Test-Path -LiteralPath $absoluteEvidence) ("required 015 evidence is missing: {0}" -f $relativeEvidence)
  }
  foreach ($relativeEvidence in $requiredEvidence) {
    $evidenceValues = @((Get-PropertyValue -Object $issue015 -Name 'evidencePaths' -Default @()) | ForEach-Object { [string]$_ })
    Assert-Gate ($evidenceValues -contains $relativeEvidence) ("state ledger does not retain 015 evidence: {0}" -f $relativeEvidence)
  }
  Add-Check -Id 'evidence_registration' -Detail '015 failure, source-fix, transition and static closure evidence are present and retained by the machine ledger.' -Evidence $requiredEvidence

  Assert-Gate ([string]$preFix.issueId -eq 'ISSUE-COMPAT-015' -and [string]$preFix.phase -eq 'failure_contract_pre_fix' -and [string]$preFix.status -eq 'passed') '015 pre-fix evidence is not a passed failure contract.'
  Assert-Gate ([string]$postFix.issueId -eq 'ISSUE-COMPAT-015' -and [int]$postFix.assertions -eq 41 -and [string]$postFix.phase -eq 'source_closure_static_verified_pending_r4' -and [string]$postFix.status -eq 'passed') '015 post-fix static contract evidence is not the expected 41-assertion result.'
  Assert-Gate ([string]$sourceFix.issueId -eq 'ISSUE-COMPAT-015' -and [string]$sourceFix.status -eq 'source_closure_static_verified_pending_r4' -and [int]$sourceFix.assertions -eq 41) '015 source-fix evidence metadata is incomplete.'
  Assert-Gate (-not [bool]$sourceFix.semanticMatchAllowed) '015 source-fix evidence incorrectly permits semantic match.'
  Assert-Gate (@((Get-PropertyValue -Object $sourceFix -Name 'runtimeActionsPerformed' -Default @())).Count -eq 0) '015 source-fix evidence records runtime actions.'
  Assert-Gate ([string]$transition.status -eq 'passed' -and [string]$transition.fromIssue -eq 'ISSUE-COMPAT-014' -and [string]$transition.fromStatus -eq 'verifying' -and [string]$transition.toIssue -eq 'ISSUE-COMPAT-015' -and [string]$transition.toStatus -eq 'verifying' -and [bool]$transition.fromSourceClosureStaticExit -and [string]$transition.fromRuntimeVerification -eq 'deferred_to_R4') '015 queue transition evidence is not a deferred-R4 static transition.'
  Assert-Gate (-not [bool]$transition.semanticMatchAllowed -and @($transition.runtimeActionsPerformed).Count -eq 0) '015 queue transition evidence permits runtime or semantic claims.'
  Add-Check -Id 'static_status_contract' -Detail '015 remains source-closure-static-verified-pending-R4; no runtime action or semantic-match claim is present.' -Evidence @('tools/legado-compat/evidence/r3-015-source-closure-20260808-r1/v2-manga-reader-source-identity-source-fix-20260808-r1.json', 'tools/legado-compat/evidence/r3-015-source-closure-20260808-r1/r3-source-queue-transition-20260808-r1.json')

  $sourceHashProperties = @($sourceFix.sourceHashes.PSObject.Properties)
  Assert-Gate ($sourceHashProperties.Count -eq 8) '015 source-fix evidence must bind all eight implementation files.'
  foreach ($sourceHashProperty in $sourceHashProperties) {
    $relativeSource = [string]$sourceHashProperty.Name
    $absoluteSource = Join-Path $RepositoryRoot ($relativeSource.Replace('/', '\'))
    Assert-Gate (Test-Path -LiteralPath $absoluteSource) ("015 implementation file is missing: {0}" -f $relativeSource)
    Assert-Gate ((Get-Sha256 -Path $absoluteSource) -eq ([string]$sourceHashProperty.Value).ToUpperInvariant()) ("015 implementation hash drifted: {0}" -f $relativeSource)
  }
  Assert-Gate ((Get-Sha256 -Path $fixturePath) -eq [string]$sourceFix.fixtureSha256) '015 fixture hash drifted from source-fix evidence.'
  Assert-Gate ((Get-Sha256 -Path $contractPath) -eq [string]$sourceFix.contractSha256) '015 contract hash drifted from source-fix evidence.'
  Add-Check -Id 'source_hash_binding' -Detail 'All eight 015 implementation files plus fixture and contract are bound to current HEAD hashes.' -Evidence @('tools/legado-compat/evidence/r3-015-source-closure-20260808-r1/v2-manga-reader-source-identity-source-fix-20260808-r1.json', 'tools/legado-compat/fixtures/legado-manga-reader-source-identity.json', 'tools/legado-compat/Test-LegadoMangaReaderSourceIdentityContract.ps1')

  $objectiveDocument = Read-StrictUtf8Text -Path $objectiveDocumentPath
  $governanceDocument = Read-StrictUtf8Text -Path $governancePath
  $ledgerDocument = Read-StrictUtf8Text -Path $ledgerPath
  $indexDocument = Read-StrictUtf8Text -Path $indexPath
  $diffDocument = Read-StrictUtf8Text -Path $diffPath
  Assert-Gate ($objectiveDocument.Contains([string]$objective.targetRevision) -and $objectiveDocument.Contains('ISSUE-COMPAT-015') -and $objectiveDocument.Contains('V2-HARNESS-023')) 'objective Markdown does not describe the 015 active queue.'
  Assert-Gate ($governanceDocument.Contains('activeIssue=`ISSUE-COMPAT-015`') -and $governanceDocument -match '\| issue \| ISSUE-COMPAT-015 \| verifying \|') 'governance mirror does not describe 015 as active verifying.'
  Assert-Gate ($ledgerDocument.Contains('活跃任务：COMPAT-006') -and $indexDocument -match '\| `ISSUE-COMPAT-015` \| `verifying` \|' -and $diffDocument -match '\| `ISSUE-COMPAT-015` \| `verifying` \|') 'generated document mirrors do not describe the current 015 queue.'
  Add-Check -Id 'document_binding' -Detail 'Objective, governance mirror, ledger, evidence index and diff summary describe the same 015 queue.' -Evidence @('docs/analysis/Legado书源V2源码重构持续目标.md', 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md', 'docs/analysis/Legado书源引擎兼容推进台账.md', 'docs/analysis/Legado书源引擎证据索引.md', 'docs/analysis/Legado书源引擎差分摘要.md')

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_issue015_queue_static_gate'
    status = 'passed'
    issueId = 'ISSUE-COMPAT-015'
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
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
      nextCandidate = 'V2-HARNESS-023'
    }
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @($requiredEvidence + @('tools/legado-compat/state/refactor-objective.json', 'tools/legado-compat/state/full-source-validation-state.json'))
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_issue015_queue_static_only;R4_runtime_build_device_and_legado_diff_deferred'
    nextGate = 'V2-HARNESS-023 may be selected only after this static evidence is registered; R4 remains user-gated.'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_issue015_queue_static_gate'
    status = 'failed'
    issueId = 'ISSUE-COMPAT-015'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_issue015_queue_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  }
}

$temporaryPath = "$outputFullPath.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
[System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $outputFullPath -Force
$result | ConvertTo-Json -Depth 20
if ($exitCode -ne 0) { exit $exitCode }
