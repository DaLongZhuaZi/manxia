[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$PreFixEvidencePath = 'tools/legado-compat/evidence/contract-legado-jsoup-index-pseudo-selectors-pre-fix-20260809.json',
  [string]$CurrentHeadEvidencePath = 'tools/legado-compat/evidence/v2-jsoup-index-pseudo-selector-current-head-audit-20260809.json',
  [string]$StaticContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-index-pseudo-selectors.json',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-index-pseudo-selectors.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-index-pseudo-selector-source-fix-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$sourceFixFullPath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot ($SourceFixPath.Replace('/', '\'))))
$evidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).TrimEnd('\') + '\'
if (-not $sourceFixFullPath.StartsWith($evidenceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'source-fix evidence must remain under the evidence directory.'
}
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required JSON is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return ($strictUtf8.GetString($bytes) | ConvertFrom-Json)
}

function Assert-SourceFix {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "237 source-fix registration blocked: $Message" }
  $script:assertions++
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 50), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
  $preFix = Read-StrictJson -RelativePath $PreFixEvidencePath
  $currentHead = Read-StrictJson -RelativePath $CurrentHeadEvidencePath
  $staticContract = Read-StrictJson -RelativePath $StaticContractPath
  $fixture = Read-StrictJson -RelativePath $FixturePath
  Assert-SourceFix ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'fixed baseline drifted.'
  Assert-SourceFix ([string]$preFix.status -eq 'failed' -and [string]$preFix.issueId -eq 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS' -and -not [bool]$preFix.semanticMatchAllowed) 'failure witness is not static-only.'
  Assert-SourceFix ([string]$currentHead.status -eq 'passed' -and [string]$currentHead.issueId -eq 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS' -and -not [bool]$currentHead.semanticMatchAllowed -and @($currentHead.runtimeActionsPerformed).Count -eq 0) 'current-head audit is not static-only.'
  Assert-SourceFix ([string]$staticContract.status -eq 'passed' -and [int]$staticContract.assertions -eq 20) 'static contract is not the expected 20-assertion pass.'
  Assert-SourceFix (@($fixture.cases).Count -eq 6) 'fixture case count drifted.'

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    evidenceType = 'source_fix'
    issueId = 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS'
    status = 'source_closed_static_only'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    baseline = [pscustomobject][ordered]@{ sourcePackageSha256 = $baselineHash; sourceCount = 458; legadoCommit = $legadoCommit }
    staticImpact = [pscustomobject][ordered]@{ ruleStringCount = 16; affectedSourceCount = 9; nthOfTypeMatchCount = 14; eqMatchCount = 2; ltMatchCount = 4; representativePatterns = @('tr:nth-of-type(3)', 'td:nth-of-type(2)', 'li:eq(0)', 'a:lt(2)', 'tr:lt(5)') }
    rootCause = [pscustomobject][ordered]@{ category = '规则解析或编译'; originalSemantics = 'Pinned Legado delegates CSS selectors to Jsoup 1.16.2: nth-of-type is 1-based same-tag an+b, eq compares zero-based elementSiblingIndex, and lt matches elementSiblingIndex below the numeric argument.'; v2BeforeFix = 'The project HEAD lacked these semantics in the DOM matcher, large-document string fallback and ArkWeb runtime; invalid numeric arguments were not represented as an explicit fail-closed contract.'; evidence = @('legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt', $PreFixEvidencePath, $CurrentHeadEvidencePath) }
    changes = @(
      [pscustomobject][ordered]@{ path = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'; change = 'Implement Jsoup-compatible nth-of-type, eq and lt using same-tag and element-sibling positions with fail-closed numeric parsing.' },
      [pscustomobject][ordered]@{ path = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'; change = 'Preserve parent/child occurrence context in large-document string fallback for index pseudos.' },
      [pscustomobject][ordered]@{ path = 'entry/src/main/resources/rawfile/legado_runtime.html'; change = 'Normalize index pseudos before browser selection and evaluate Jsoup-compatible sibling predicates in ArkWeb.' }
    )
    failureEvidence = @($PreFixEvidencePath)
    staticContract = $StaticContractPath
    currentHeadAudit = $CurrentHeadEvidencePath
    consumerMatrix = $currentHead.consumerMatrix
    assertions = $script:assertions
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_source_fix_static_only;237_verifying;runtime_build_device_and_legado_diff_deferred'
    followUp = '237 must be compared with fixed Legado across the six cases, affected source set and 458-source Harness before passed or semantic_match.'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{ schemaVersion = 1; evidenceType = 'source_fix'; issueId = 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS'; status = 'failed'; generatedAt = [DateTimeOffset]::UtcNow.ToString('o'); failure = $_.Exception.Message; runtimeActionsPerformed = @(); semanticMatchAllowed = $false }
}

Write-AtomicJson -Path $sourceFixFullPath -Value $result
$result | ConvertTo-Json -Depth 50
if ($exitCode -ne 0) { exit $exitCode }
