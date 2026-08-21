[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-has-direct-child-relative-selector-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-has-direct-child-relative-selector-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-has-direct-child-relative-selector-post-fix-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/v2-jsoup-has-direct-child-relative-selector-current-head-audit-20260810.json'
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
function Assert-Audit { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 :has direct-child relative selector current-head audit failed: $Message" }; $script:assertions++ }
function Get-TextHash { param([Parameter(Mandatory = $true)][string]$Text); $sha = [System.Security.Cryptography.SHA256]::Create(); try { return ([System.BitConverter]::ToString($sha.ComputeHash($strictUtf8.GetBytes($Text)))).Replace('-', '').ToUpperInvariant() } finally { $sha.Dispose() } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value); $path = Get-RepoPath $RelativePath; $directory = Split-Path -Parent $path; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $path -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$contract = Read-StrictJson $PostFixContractPath
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$analyzer = Read-StrictText $analyzerPath
$legado = Read-StrictText $legadoPath
$hashes = [ordered]@{ $analyzerPath = Get-TextHash $analyzer; $legadoPath = Get-TextHash $legado }

Assert-Audit ([string]$failure.status -eq 'failed' -and [string]$contract.status -eq 'passed') 'failure witness and post-fix contract must be present.'
Assert-Audit (@($failure.runtimeActionsPerformed).Count -eq 0 -and @($contract.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$contract.semanticMatchAllowed) 'static audit cannot claim runtime semantic match.'
Assert-Audit ([string]$fixture.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and @($fixture.cases).Count -eq 4) 'fixture binding drifted.'
Assert-Audit ($analyzer.Contains('const subjectSelector = this.extractTopLevelSelectorSubject(childSelector);') -and $analyzer.Contains('matchesStringSelectorAtElementStart(wrapper, subjectSelector, wrapperOpeningEnd + 1)')) 'string fallback current head enforces the direct-child subject.'
Assert-Audit ($analyzer.Contains('private extractTopLevelSelectorSubject(selector: string): string {') -and $analyzer.Contains('private matchesStringSelectorAtElementStart(') -and $analyzer.Contains('expectedStart: number') -and $analyzer.Contains('): boolean {')) 'string fallback subject helpers are present.'
Assert-Audit ($analyzer.Contains('matches.some((match: string): boolean => match !== wrapper)')) 'descendant continuation remains supported after the direct-child guard.'
Assert-Audit ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado selector consumer remains bound.'
Assert-Audit ($hashes[$analyzerPath].Length -eq 64 -and $hashes[$legadoPath].Length -eq 64) 'source hashes must be SHA-256.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'v2_jsoup_has_direct_child_relative_selector_current_head_audit'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'passed'
  assertions = $script:assertions
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  sourceHashes = $hashes
  consumerPaths = [pscustomobject][ordered]@{ stringFallback = $analyzerPath; legado = $legadoPath }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_current_head_static_audit_only;runtime_regression_build_device_and_legado_diff_deferred'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
