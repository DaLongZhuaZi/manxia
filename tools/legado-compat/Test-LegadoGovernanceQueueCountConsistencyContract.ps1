[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-governance-queue-count-consistency.json',
  [string]$PreFixEvidencePath = 'tools/legado-compat/evidence/contract-legado-governance-queue-count-consistency-pre-fix-20260809.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-governance-queue-count-consistency-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$sourceCount = 458
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-AUTO-048-GOVERNANCE-QUEUE-SELECTION-ANCHOR-DRIFT'
$assertions = 0

function Get-RepoPath([string]$RelativePath) {
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText([string]$RelativePath) {
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing file: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson([string]$RelativePath) {
  return (Read-StrictText $RelativePath | ConvertFrom-Json)
}

function Assert-Contract([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "Governance queue-count contract failed: $Message" }
  $script:assertions++
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 30), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

$fixture = Read-StrictJson $FixturePath
$preFix = Read-StrictJson $PreFixEvidencePath
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$queueEvidencePath = [string]$state.governance.queuePreflight.evidencePath
$gate = Read-StrictJson $queueEvidencePath
$governance = Read-StrictText ([string]$fixture.governancePath)

Assert-Contract ([string]$fixture.contract -eq 'current_static_queue_count_consistency') 'fixture contract drifted.'
Assert-Contract ([string]$fixture.issueId -eq $issueId) 'fixture issue binding drifted.'
Assert-Contract ([int]$fixture.baseline.sourceCount -eq $sourceCount -and [string]$fixture.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$fixture.baseline.legadoCommit -eq $legadoCommit) 'fixture baseline drifted.'
Assert-Contract ([int]$state.baseline.sourceCount -eq $sourceCount -and [string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline drifted.'
Assert-Contract ([string]$preFix.status -eq 'failed_static_only' -and [string]$preFix.issueId -eq $issueId) 'pre-fix failure witness is missing or drifted.'
Assert-Contract ([string]$gate.status -eq 'passed' -and [string]$gate.candidateGateStatus -eq [string]$fixture.expectedCandidateGateStatus) 'current candidate gate did not complete with the expected no-candidate status.'
Assert-Contract ([int]$gate.candidateCount -eq [int]$fixture.expectedCandidateCount) 'candidate count changed unexpectedly.'
Assert-Contract ([int]$state.governance.queuePreflight.evaluatedCount -eq [int]$gate.evaluatedCount) 'machine queue count differs from current gate count.'
$currentSectionStart = $governance.IndexOf('## R3 当前目标队列前置审计', [System.StringComparison]::Ordinal)
$currentSectionEnd = $governance.IndexOf('<!-- LEGADO_V2_GOVERNANCE_TASK_MIRROR:START -->', $currentSectionStart, [System.StringComparison]::Ordinal)
Assert-Contract ($currentSectionStart -ge 0 -and $currentSectionEnd -gt $currentSectionStart) 'current execution-target section boundary is missing.'
$currentSection = $governance.Substring($currentSectionStart, $currentSectionEnd - $currentSectionStart)
$lineMatch = [regex]::Match($currentSection, '(?m)静态(?:队列)?门禁评估 `?(?<count>\d+)`? 个 P0/P1 条目，合格候选为 `?(?<candidates>\d+)`?；')
Assert-Contract $lineMatch.Success 'current queue summary line is missing.'
$documentCount = [int]$lineMatch.Groups['count'].Value
$documentCandidates = [int]$lineMatch.Groups['candidates'].Value
Assert-Contract ($documentCount -eq [int]$gate.evaluatedCount) 'governance document count differs from current gate count.'
Assert-Contract ($documentCandidates -eq [int]$gate.candidateCount) 'governance document candidate count differs from current gate count.'
Assert-Contract (-not $currentSection.Contains([string]$fixture.staleTopLine)) 'stale 226 queue count remains in the current summary.'
Assert-Contract ([string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and -not [bool]$state.governance.semanticMatchAllowed) 'current source issue or semantic gate drifted.'

$result = [ordered]@{
  schemaVersion = 1
  kind = 'legado_governance_queue_count_consistency_contract'
  status = 'passed_static_only'
  issueId = $issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  preFixEvidencePath = $PreFixEvidencePath
  currentGatePath = $queueEvidencePath
  governancePath = [string]$fixture.governancePath
  gateEvaluatedCount = [int]$gate.evaluatedCount
  documentEvaluatedCount = $documentCount
  gateCandidateCount = [int]$gate.candidateCount
  documentCandidateCount = $documentCandidates
  assertionCount = $assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  execution = 'static_document_contract_only'
  runtimeRegression = 'not_run'
  deviceRegression = 'not_run'
  verificationPolicy = [string]$fixture.verificationPolicy
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 20 -Compress
