[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-java-string-list-css-replacement-order-source-fix-20260808.json'
}

$utf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return ($utf8.GetString($bytes) | ConvertFrom-Json)
}

function Get-Sha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Join-Path $RepositoryRoot ($RelativePath -replace '/', '\')
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing evidence input: $RelativePath" }
  return (Resolve-Path -LiteralPath $path).Path
}

function Get-RelativePath {
  param([Parameter(Mandatory = $true)][string]$Path)
  return [System.IO.Path]::GetRelativePath($RepositoryRoot, $Path).Replace('\', '/')
}

$statePath = Get-RepoPath -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$fixturePath = Get-RepoPath -RelativePath 'tools/legado-compat/fixtures/legado-java-string-list-css-replacement-order.json'
$contractScriptPath = Get-RepoPath -RelativePath 'tools/legado-compat/Test-LegadoJavaStringListCssReplacementOrderContract.ps1'
$contractEvidencePath = Get-RepoPath -RelativePath 'tools/legado-compat/evidence/contract-legado-java-string-list-css-replacement-order-20260808.json'
$preFixEvidencePath = Get-RepoPath -RelativePath 'tools/legado-compat/evidence/contract-legado-java-string-list-css-composition-pre-fix-20260808.json'
$replacementPreFixEvidencePath = Get-RepoPath -RelativePath 'tools/legado-compat/evidence/contract-legado-java-string-list-css-replacement-order-pre-fix-20260808.json'
$implementationRelativePaths = @(
  'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
  'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets',
  'entry/src/main/resources/rawfile/legado_runtime.html',
  'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeRule.kt',
  'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt',
  'legado/app/src/main/java/io/legado/app/model/analyzeRule/RuleAnalyzer.kt'
)

$state = Read-StrictJson -Path $statePath
$contract = Read-StrictJson -Path $contractEvidencePath
$preFix = Read-StrictJson -Path $preFixEvidencePath
$replacementPreFix = Read-StrictJson -Path $replacementPreFixEvidencePath
$baseline = $state.baseline
if ([int]$baseline.sourceCount -ne 458) { throw 'Frozen source count is not 458.' }
if ([string]$baseline.sourcePackageSha256 -ne '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') { throw 'Frozen source package hash drifted.' }
if ([string]$baseline.legadoCommit -ne '95973d186b147fb9ab43a9240021d688e4304fbd') { throw 'Frozen Legado commit drifted.' }
if ([string]$state.governance.activeIssueId -ne 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION') { throw 'Active issue is not 233.' }
if ([string]$contract.status -ne 'passed' -or [int]$contract.assertions -ne 14) { throw 'Replacement-order static contract is not a 14-assertion pass.' }
if ([string]$preFix.status -ne 'failed' -or [bool]$preFix.semanticMatchAllowed) { throw '233 failure evidence is not a static failed-before witness.' }
if ([string]$replacementPreFix.status -ne 'failed' -or @($replacementPreFix.mismatches).Count -ne 2 -or [bool]$replacementPreFix.semanticMatchAllowed -or @($replacementPreFix.runtimeActionsPerformed).Count -ne 0) { throw 'Replacement-order failure evidence is not a two-case static failed-before witness.' }

$sourceHashes = [ordered]@{}
foreach ($relativePath in $implementationRelativePaths) {
  $sourceHashes[$relativePath] = Get-Sha256 -Path (Get-RepoPath -RelativePath $relativePath)
}

$result = [ordered]@{
  schemaVersion = 1
  issueId = 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION'
  sourcePackageSha256 = [string]$baseline.sourcePackageSha256
  legadoCommit = [string]$baseline.legadoCommit
  sourceCount = [int]$baseline.sourceCount
  status = 'source_fix_applied_pending_verification'
  rootCause = 'V2 parsed replacement after splitting composition operands, and treated a literal trailing single # as replace-first. Legado parses the complete rule first, composes the values, then applies ## replacement; the extra split field created by a trailing ## marks replaceFirst.'
  change = 'LegadoRuleAnalyzer now strips replacement before &&/||/%% composition and applies it to the merged string/list; trailing ## is the only replace-first marker. Standard and Native JSVM getString composition branches now apply the outer replacement after newline joining.'
  fixture = Get-RelativePath -Path $fixturePath
  contract = Get-RelativePath -Path $contractEvidencePath
  preFixEvidence = Get-RelativePath -Path $preFixEvidencePath
  replacementOrderPreFixEvidence = Get-RelativePath -Path $replacementPreFixEvidencePath
  preFixEvidencePaths = @((Get-RelativePath -Path $preFixEvidencePath), (Get-RelativePath -Path $replacementPreFixEvidencePath))
  implementationPaths = @($implementationRelativePaths)
  sourceHashes = $sourceHashes
  fixtureSha256 = Get-Sha256 -Path $fixturePath
  contractSha256 = Get-Sha256 -Path $contractScriptPath
  staticContract = [ordered]@{
    status = [string]$contract.status
    assertions = [int]$contract.assertions
    evidence = Get-RelativePath -Path $contractEvidencePath
  }
  verificationPolicy = 'r3_source_fix_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  notRun = @('ArkTS_build', 'standard_JSVM_runtime_execution', 'Native_JSVM_runtime_execution', 'ArkWeb_runtime_execution', '458_source_deterministic_regression', 'Legado_reference_differential', 'real_device_regression')
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) { [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null }
$temporaryPath = "$OutputPath.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
[System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $OutputPath -Force
$result | ConvertTo-Json -Depth 20
