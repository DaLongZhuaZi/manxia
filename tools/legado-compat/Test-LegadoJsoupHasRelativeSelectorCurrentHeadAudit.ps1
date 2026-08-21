[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-has-relative-selector-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-has-relative-selector-pre-fix-20260809.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-has-relative-selector-post-fix-20260809.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/v2-jsoup-has-relative-selector-current-head-audit-20260809.json'
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
function Assert-Audit { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 :has relative selector current-head audit failed: $Message" }; $script:assertions++ }
function Get-TextHash { param([Parameter(Mandatory = $true)][string]$Text); $sha = [System.Security.Cryptography.SHA256]::Create(); try { return ([System.BitConverter]::ToString($sha.ComputeHash($strictUtf8.GetBytes($Text)))).Replace('-', '').ToUpperInvariant() } finally { $sha.Dispose() } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value); $path = Get-RepoPath $RelativePath; $directory = Split-Path -Parent $path; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temp = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temp -Destination $path -Force } finally { if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) } } }

$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$contract = Read-StrictJson $PostFixContractPath
$paths = @(
  'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
  'entry/src/main/ets/libs/htmlparser/HTMLElement.ets',
  'entry/src/main/resources/rawfile/legado_runtime.html',
  'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
)
$texts = @{}
$hashes = [ordered]@{}
foreach ($path in $paths) {
  $text = Read-StrictText $path
  $texts[$path] = $text
  $hashes[$path] = Get-TextHash $text
}
$analyzer = [string]$texts[$paths[0]]
$element = [string]$texts[$paths[1]]
$runtime = [string]$texts[$paths[2]]
$legado = [string]$texts[$paths[3]]

Assert-Audit ([string]$failure.status -eq 'failed' -and [string]$contract.status -eq 'passed') 'failure witness and post-fix contract must be present.'
Assert-Audit (@($failure.runtimeActionsPerformed).Count -eq 0 -and @($contract.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$contract.semanticMatchAllowed) 'static audit cannot claim runtime semantic match.'
Assert-Audit ([string]$fixture.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and @($fixture.cases).Count -eq 4) 'fixture binding drifted.'
Assert-Audit ($analyzer.Contains('matches.some((match: string): boolean => match !== wrapper)') -and -not $analyzer.Contains('match === child')) 'string fallback current head is fixed.'
Assert-Audit ($element.Contains('matchesHasDirectChildRelativeSelector') -and $element.Contains('parentNode === elem') -and -not $element.Contains('child.matches(childSelector)')) 'DOM current head is fixed.'
Assert-Audit ($runtime.Contains("':scope ' + argument")) 'ArkWeb relative-selector bridge remains fixed.'
Assert-Audit ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado selector consumer remains bound.'
Assert-Audit ($hashes[$paths[0]].Length -eq 64 -and $hashes[$paths[1]].Length -eq 64 -and $hashes[$paths[2]].Length -eq 64 -and $hashes[$paths[3]].Length -eq 64) 'source hashes must be SHA-256.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'v2_jsoup_has_relative_selector_current_head_audit'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'passed'
  assertions = $script:assertions
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  sourceHashes = $hashes
  consumerPaths = [pscustomobject][ordered]@{ dom = $paths[1]; stringFallback = $paths[0]; arkWeb = $paths[2]; legado = $paths[3] }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_current_head_static_audit_only;runtime_regression_build_device_and_legado_diff_deferred'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
