[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$SourceFixPath = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if ([string]::IsNullOrWhiteSpace($SourceFixPath)) { $SourceFixPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-jsoup-regex-attribute-selector-source-fix-20260807.json' }
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-jsoup-regex-attribute-selector-current-head-audit-20260808.json' }

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return ($strictUtf8.GetString($bytes) | ConvertFrom-Json)
}
function Get-Sha256 { param([Parameter(Mandatory = $true)][string]$Path) return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant() }
function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$RelativePath) return (Resolve-Path -LiteralPath (Join-Path $RepositoryRoot ($RelativePath -replace '/', '\'))).Path }
function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

$sourceFix = Read-StrictJson -Path $SourceFixPath
$preFixPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-jsoup-regex-attribute-selector-pre-fix-20260808.json'
$contractPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-jsoup-regex-attribute-selector.json'
$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-jsoup-regex-attribute-selector.json'
$state = Read-StrictJson -Path (Get-RepoPath -RelativePath 'tools/legado-compat/state/full-source-validation-state.json')
$preFix = Read-StrictJson -Path $preFixPath
$contract = Read-StrictJson -Path $contractPath
if ([string]$sourceFix.issueId -ne 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR') { throw 'Source-fix evidence is bound to the wrong issue.' }
if ([string]$sourceFix.status -ne 'verifying') { throw '234 source-fix evidence is not static verifying.' }
if ([string]$preFix.status -ne 'failed' -or [bool]$preFix.semanticMatchAllowed) { throw '234 failed-before evidence is not static failed.' }
if ([string]$contract.status -ne 'passed' -or [int]$contract.assertions -ne 13) { throw '234 static contract is not a 13-assertion pass.' }
if ([int]$state.baseline.sourceCount -ne 458 -or [string]$state.baseline.sourcePackageSha256 -ne '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -or [string]$state.baseline.legadoCommit -ne '95973d186b147fb9ab43a9240021d688e4304fbd') { throw 'Frozen baseline drifted.' }

$implementationRelativePaths = @(
  'entry/src/main/ets/libs/htmlparser/Matcher.ets',
  'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
  'entry/src/main/resources/rawfile/legado_runtime.html',
  'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt',
  'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeRule.kt',
  'legado/app/src/main/java/io/legado/app/model/analyzeRule/RuleAnalyzer.kt'
)
$hashes = [ordered]@{}
foreach ($relativePath in $implementationRelativePaths) { $hashes[$relativePath] = Get-Sha256 -Path (Get-RepoPath -RelativePath $relativePath) }

$result = [ordered]@{
  schemaVersion = 1
  kind = 'legado_jsoup_regex_attribute_selector_current_head_audit'
  issueId = [string]$sourceFix.issueId
  status = 'current_head_bound_static_closure'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = [int]$state.baseline.sourceCount; sourcePackageSha256 = [string]$state.baseline.sourcePackageSha256; legadoCommit = [string]$state.baseline.legadoCommit }
  sourceFixEvidence = [System.IO.Path]::GetRelativePath($RepositoryRoot, $SourceFixPath).Replace('\', '/')
  preFixEvidence = [System.IO.Path]::GetRelativePath($RepositoryRoot, $preFixPath).Replace('\', '/')
  contractEvidence = [System.IO.Path]::GetRelativePath($RepositoryRoot, $contractPath).Replace('\', '/')
  fixture = [System.IO.Path]::GetRelativePath($RepositoryRoot, $fixturePath).Replace('\', '/')
  implementationHashes = $hashes
  impact = [ordered]@{ attributeRegexRuleStringCount = 139; affectedSourceCountLowerBound = 51; javaInlineRegexFlagRuleValueCount = 4; javaInlineRegexFlagAffectedSourceCount = 2 }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_current_head_static_only;R4_runtime_build_device_and_legado_diff_deferred'
}
Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Depth 20
