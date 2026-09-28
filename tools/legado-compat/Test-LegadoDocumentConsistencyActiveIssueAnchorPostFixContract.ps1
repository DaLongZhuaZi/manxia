[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-document-consistency-active-issue-anchor.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-document-consistency-active-issue-anchor-pre-fix-20260810.json',
  [string]$ReproductionFixturePath = 'tools/legado-compat/fixtures/legado-document-consistency-reproduction-command.json',
  [string]$ReproductionFailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-document-consistency-reproduction-command-pre-fix-20260810.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-document-consistency-active-issue-anchor-post-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-AUTO-046-DOCUMENT-ACTIVE-ANCHOR'
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$scriptPath = 'tools/legado-compat/Test-LegadoIssue011DocumentConsistency.ps1'
$script:assertions = 0

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }; return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Missing text: $Path" }; $bytes = [System.IO.File]::ReadAllBytes($resolved); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }; return $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText $Path | ConvertFrom-Json -Depth 100) }
function Assert-Contract { param([bool]$Condition, [string]$Detail); if (-not $Condition) { throw "AUTO-046 document anchor post-fix contract failed: $Detail" }; $script:assertions++ }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$reproductionFixture = Read-StrictJson $ReproductionFixturePath
$reproductionFailure = Read-StrictJson $ReproductionFailureWitnessPath
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$scriptText = Read-StrictText $scriptPath
$helperStart = $scriptText.IndexOf('function Test-ActiveIssueAnchor(')
$helperEnd = $scriptText.IndexOf('function Write-AtomicJson(', $helperStart)
$helperBody = if ($helperStart -ge 0 -and $helperEnd -gt $helperStart) { $scriptText.Substring($helperStart, $helperEnd - $helperStart) } else { '' }
$legacyAnchorCheck = '当前唯一活动源码议题为 $issueId'

Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline is unchanged.'
Assert-Contract ([string]$state.governance.activeIssueId -eq [string]$fixture.activeSourceIssue) 'fixture active issue matches machine state.'
Assert-Contract ([string]$failure.status -eq 'failed' -and -not [bool]$failure.semanticMatchAllowed -and @($failure.runtimeActionsPerformed).Count -eq 0) 'pre-fix failure remains static-only.'
Assert-Contract ([string]$reproductionFailure.status -eq 'failed' -and -not [bool]$reproductionFailure.semanticMatchAllowed -and @($reproductionFailure.runtimeActionsPerformed).Count -eq 0) 'stale reproduction-command failure remains static-only.'
Assert-Contract ($helperBody.Contains('shortPlainAnchor') -and $helperBody.Contains('uniquePlainAnchor') -and $helperBody.Contains('shortAnchor') -and $helperBody.Contains('uniqueAnchor')) 'active anchor helper accepts plain and Markdown-marked generated wording variants.'
Assert-Contract (-not $scriptText.Contains($legacyAnchorCheck)) 'strict literal-only anchor checks were removed.'
Assert-Contract ($reproductionFixture.expectedInvocation.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and $scriptText.Contains('reproductionCommand = (') -and -not $scriptText.Contains('ExpectedIssueId ISSUE-COMPAT-009')) 'reproductionCommand is generated from invocation parameters.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'post_fix_static_contract'
  issueId = $issueId
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  failureWitnessPath = $FailureWitnessPath
  changedPaths = @($scriptPath)
  affectedAnchorForms = @($fixture.acceptedAnchorForms)
  reproductionFixturePath = $ReproductionFixturePath
  reproductionFailureWitnessPath = $ReproductionFailureWitnessPath
  assertions = $script:assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_governance_document_consistency_static_only;runtime_build_device_and_legado_diff_deferred'
  closeCondition = 'The active issue ID must remain bound across machine state, objective authority and all generated document anchors; no runtime validation is required for this tooling-only contract.'
}
Write-AtomicJson $ResultPath $result
$result | ConvertTo-Json -Depth 100
