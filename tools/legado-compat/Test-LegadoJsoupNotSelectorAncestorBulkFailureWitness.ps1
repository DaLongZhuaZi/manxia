[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-not-selector-ancestor-context.json',
  [string]$AnalyzerSnapshotPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets.bak_20260810_not_ancestor_bulk',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-not-selector-ancestor-bulk-pre-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$RelativePath); return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$RelativePath); $path = Get-RepoPath $RelativePath; if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing text: $RelativePath" }; return $strictUtf8.GetString([System.IO.File]::ReadAllBytes($path)) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$RelativePath); return (Read-StrictText $RelativePath | ConvertFrom-Json -Depth 100) }
function Assert-Witness { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 :not ancestor bulk failure witness failed: $Message" } }
function Get-TextHash { param([Parameter(Mandatory = $true)][string]$Text); $sha = [System.Security.Cryptography.SHA256]::Create(); try { return ([System.BitConverter]::ToString($sha.ComputeHash($strictUtf8.GetBytes($Text)))).Replace('-', '').ToUpperInvariant() } finally { $sha.Dispose() } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value); $path = Get-RepoPath $RelativePath; $directory = Split-Path -Parent $path; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temp = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temp -Destination $path -Force } finally { if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) } } }

$fixture = Read-StrictJson $FixturePath
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$analyzer = Read-StrictText $AnalyzerSnapshotPath
Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$state.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'frozen baseline drifted.'
Assert-Witness ([string]$fixture.contract -eq 'legado_jsoup_not_selector_ancestor_context' -and @($fixture.cases).Count -eq 3) 'ancestor-context fixture changed.'
Assert-Witness ($analyzer.Contains('this.matchesStringNestedSelectorAtOccurrence(element, argument, contextHtml, occurrence.startIndex)')) 'pre-fix per-candidate full-context scan is absent.'
Assert-Witness (-not $analyzer.Contains('collectNestedSelectorMatchOffsets')) 'pre-fix bulk offset collector unexpectedly exists.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_jsoup_not_selector_ancestor_bulk_pre_fix_contract'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  classification = 'v2_string_fallback_not_selector_repeated_full_document_scan'
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = [string]$state.baseline.sourcePackageSha256; legadoCommit = [string]$state.baseline.legadoCommit }
  fixture = $FixturePath
  sourceSnapshotMode = 'backup_before_fix'
  sourceSnapshotPath = $AnalyzerSnapshotPath
  sourceSnapshotHash = Get-TextHash $analyzer
  failingCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  rootCauseDecision = 'After restoring full ancestor semantics, the complete document selector was executed once per candidate. A source with many matching nodes could rescan the entire response for every node and violate the large-document performance guard.'
  staticWitnesses = @([pscustomobject][ordered]@{ path = $AnalyzerSnapshotPath; finding = 'the complete-context :not branch invokes matchesStringNestedSelectorAtOccurrence inside the candidate loop.' })
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_not_selector_ancestor_bulk_failure_witness_static_only;runtime_regression_build_device_and_legado_diff_deferred'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
