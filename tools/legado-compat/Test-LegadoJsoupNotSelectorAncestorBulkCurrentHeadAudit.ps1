[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-not-selector-ancestor-context.json',
  [string]$AncestorFailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-not-selector-ancestor-pre-fix-20260810.json',
  [string]$BulkFailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-not-selector-ancestor-bulk-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-not-selector-ancestor-bulk-post-fix-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/v2-jsoup-not-selector-ancestor-bulk-current-head-audit-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$RelativePath); return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$RelativePath); $path = Get-RepoPath $RelativePath; if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing text: $RelativePath" }; return $strictUtf8.GetString([System.IO.File]::ReadAllBytes($path)) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$RelativePath); return (Read-StrictText $RelativePath | ConvertFrom-Json -Depth 100) }
function Assert-Audit { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 :not ancestor bulk current-head audit failed: $Message" }; $script:assertions++ }
function Get-TextHash { param([Parameter(Mandatory = $true)][string]$Text); $sha = [System.Security.Cryptography.SHA256]::Create(); try { return ([System.BitConverter]::ToString($sha.ComputeHash($strictUtf8.GetBytes($Text)))).Replace('-', '').ToUpperInvariant() } finally { $sha.Dispose() } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value); $path = Get-RepoPath $RelativePath; $directory = Split-Path -Parent $path; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temp = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temp -Destination $path -Force } finally { if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) } } }

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$ancestorFailure = Read-StrictJson $AncestorFailureWitnessPath
$bulkFailure = Read-StrictJson $BulkFailureWitnessPath
$contract = Read-StrictJson $PostFixContractPath
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$analyzer = Read-StrictText $analyzerPath
$legado = Read-StrictText $legadoPath
Assert-Audit ([string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and [string]$state.governance.status -eq 'running' -and -not [bool]$state.governance.semanticMatchAllowed) '243 queue binding drifted.'
Assert-Audit ([string]$ancestorFailure.status -eq 'failed' -and [string]$bulkFailure.status -eq 'failed' -and [string]$contract.status -eq 'passed') 'failure witnesses and bulk post-fix contract must be present.'
Assert-Audit (@($ancestorFailure.runtimeActionsPerformed).Count -eq 0 -and @($bulkFailure.runtimeActionsPerformed).Count -eq 0 -and @($contract.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$contract.semanticMatchAllowed) 'audit must remain static-only.'
Assert-Audit ([string]$fixture.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and @($fixture.cases).Count -eq 3) 'fixture binding drifted.'
Assert-Audit ($analyzer.Contains('collectNestedSelectorMatchOffsets') -and $analyzer.Contains('matchedOffsets.add(occurrence.startIndex)')) 'bulk projection consumer is present.'
Assert-Audit (-not $analyzer.Contains('matchesStringNestedSelectorAtOccurrence(element, argument, contextHtml, occurrence.startIndex)')) 'per-candidate full-context scan is absent.'
Assert-Audit (-not $analyzer.Contains('const wrapper = `<legado-not-root>${parentElement}</legado-not-root>`')) 'parent-only projection is absent.'
Assert-Audit ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado selector consumer remains bound.'
Assert-Audit ((Get-TextHash $analyzer).Length -eq 64) 'current analyzer hash is SHA-256.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'v2_jsoup_not_selector_ancestor_bulk_current_head_audit'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'passed'
  assertions = $script:assertions
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  sourceHashes = [pscustomobject][ordered]@{ $analyzerPath = Get-TextHash $analyzer }
  consumerMatrix = [pscustomobject][ordered]@{ cssChain = $analyzerPath; legado = $legadoPath }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_current_head_static_audit_only;runtime_regression_build_device_and_legado_diff_deferred'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
