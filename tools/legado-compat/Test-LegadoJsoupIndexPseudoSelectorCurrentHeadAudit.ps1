[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$PreFixEvidencePath = 'tools/legado-compat/evidence/contract-legado-jsoup-index-pseudo-selectors-pre-fix-20260809.json',
  [string]$StaticContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-index-pseudo-selectors.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-index-pseudo-selectors-source-fix-20260807.json',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-index-pseudo-selectors.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/v2-jsoup-index-pseudo-selector-current-head-audit-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$resultFullPath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot ($ResultPath.Replace('/', '\'))))
$evidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).TrimEnd('\') + '\'
if (-not $resultFullPath.StartsWith($evidenceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'current-head evidence must remain under the evidence directory.'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required JSON is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return ($strictUtf8.GetString($bytes) | ConvertFrom-Json)
}

function Assert-Audit {
  param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @())
  if (-not $Condition) { throw "237 current-head audit blocked: $Detail" }
  $script:assertions++
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) })
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
$sourcePaths = @(
  'entry/src/main/ets/libs/htmlparser/HTMLElement.ets',
  'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
  'entry/src/main/resources/rawfile/legado_runtime.html'
)
$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
  $objective = Read-StrictJson -RelativePath 'tools/legado-compat/state/refactor-objective.json'
  $preFix = Read-StrictJson -RelativePath $PreFixEvidencePath
  $staticContract = Read-StrictJson -RelativePath $StaticContractPath
  $sourceFix = Read-StrictJson -RelativePath $SourceFixPath
  $fixture = Read-StrictJson -RelativePath $FixturePath
  Assert-Audit ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'fixed source and Legado baselines are unchanged.' @('tools/legado-compat/state/full-source-validation-state.json')
  Assert-Audit ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR') 'queue' '237 is audited as the next candidate while 236 remains the sole active queue anchor.' @('tools/legado-compat/state/full-source-validation-state.json')
  Assert-Audit (@($objective.executionTarget.nextIssues) -contains 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS') 'objective_candidate' 'objective registers 237 as the next candidate.' @('tools/legado-compat/state/refactor-objective.json')
  Assert-Audit ([string]$preFix.status -eq 'failed' -and [string]$preFix.issueId -eq 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS' -and -not [bool]$preFix.semanticMatchAllowed -and @($preFix.runtimeActionsPerformed).Count -eq 0) 'failure_witness' '237 failure witness is preserved as static-only evidence.' @($PreFixEvidencePath)
  Assert-Audit ([string]$staticContract.status -eq 'passed' -and [int]$staticContract.assertions -eq 20 -and [int]$staticContract.impact.ruleStringCount -eq 16 -and [int]$staticContract.impact.affectedSourceCount -eq 9) 'static_contract' '237 static contract covers 20 assertions and the fixed 16-rule/9-source impact set.' @($StaticContractPath)
  Assert-Audit ([string]$sourceFix.issueId -eq 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS' -and -not [bool]$sourceFix.semanticMatchAllowed) 'source_fix' 'existing 237 source-fix evidence makes no semantic-match claim.' @($SourceFixPath)
  Assert-Audit (@($fixture.cases).Count -eq 6) 'fixture' '237 fixture retains six deterministic selector cases.' @($FixturePath)

  $legadoHead = (& git -C (Join-Path $RepositoryRoot 'legado') rev-parse HEAD 2>$null | Out-String).Trim()
  Assert-Audit ($legadoHead -eq $legadoCommit) 'legado_head' 'Legado checkout is pinned to the required commit.' @('legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt')
  $legadoSource = [System.IO.File]::ReadAllText((Join-Path $RepositoryRoot 'legado\app\src\main\java\io\legado\app\model\analyzeRule\AnalyzeByJSoup.kt'), $strictUtf8)
  Assert-Audit ($legadoSource.Contains('temp.select(ruleStr)') -and $legadoSource.Contains('getStringList')) 'legado_consumer' 'fixed Legado selector/text consumer is present.' @('legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt')

  $currentHashes = [ordered]@{}
  $consumerMatrix = New-Object 'System.Collections.Generic.List[object]'
  foreach ($path in $sourcePaths) {
    $absolutePath = Join-Path $RepositoryRoot ($path.Replace('/', '\'))
    $bytes = [System.IO.File]::ReadAllBytes($absolutePath)
    Assert-Audit (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) ('no_bom_' + $path.Replace('/', '_')) ('source has no UTF-8 BOM: ' + $path) @($path)
    $text = $strictUtf8.GetString($bytes)
    if ($path.EndsWith('HTMLElement.ets')) {
      Assert-Audit ($text.Contains("pseudo.name === 'nth-of-type'") -and $text.Contains("pseudo.name === 'eq'") -and $text.Contains("pseudo.name === 'lt'") -and $text.Contains('getElementTypeIndex') -and $text.Contains('parseIndexPseudoArgument')) 'dom_consumer' 'DOM matcher covers nth-of-type, eq, lt and fail-closed numeric parsing.' @($path)
      [void]$consumerMatrix.Add([pscustomobject][ordered]@{ id = 'dom_matcher'; path = $path; semantics = @('same-tag an+b', 'elementSiblingIndex equality', 'elementSiblingIndex less-than') })
    } elseif ($path.EndsWith('LegadoRuleAnalyzer.ets')) {
      Assert-Audit ($text.Contains("pseudo.name === 'nth-of-type'") -and $text.Contains("pseudo.name === 'eq'") -and $text.Contains("pseudo.name === 'lt'") -and $text.Contains('findDirectChildOccurrences') -and $text.Contains('parseIndexPseudoArgument')) 'string_consumer' 'large-document string fallback preserves sibling context for index pseudos.' @($path)
      [void]$consumerMatrix.Add([pscustomobject][ordered]@{ id = 'string_fallback'; path = $path; semantics = @('same-tag an+b', 'elementSiblingIndex equality', 'elementSiblingIndex less-than') })
    } else {
      Assert-Audit ($text.Contains("name === 'nth-of-type'") -and $text.Contains("name === 'eq'") -and $text.Contains("name === 'lt'") -and $text.Contains('legadoMatchNthExpression') -and $text.Contains('legadoElementSiblingIndex')) 'arkweb_consumer' 'ArkWeb runtime normalizes and evaluates all index pseudos.' @($path)
      [void]$consumerMatrix.Add([pscustomobject][ordered]@{ id = 'arkweb'; path = $path; semantics = @('same-tag an+b', 'elementSiblingIndex equality', 'elementSiblingIndex less-than') })
    }
    $currentHashes[$path] = (Get-FileHash -Algorithm SHA256 -LiteralPath $absolutePath).Hash.ToUpperInvariant()
  }
  Assert-Audit ($consumerMatrix.Count -eq 3) 'consumer_matrix' 'DOM, string fallback and ArkWeb consumers are all registered.' @($sourcePaths)

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    evidenceType = 'current_head_static_audit'
    issueId = 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS'
    status = 'passed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    baseline = [pscustomobject][ordered]@{ sourcePackageSha256 = $baselineHash; sourceCount = 458; legadoCommit = $legadoCommit }
    changedPaths = $sourcePaths
    currentHeadHashes = $currentHashes
    consumerMatrix = $consumerMatrix.ToArray()
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_current_head_static_audit_only;runtime_build_device_and_legado_diff_deferred'
    nextGate = '237 independent transition registration must bind this audit, failure witness, fixture, static contract and source-fix evidence before activating 237.'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    evidenceType = 'current_head_static_audit'
    issueId = 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_current_head_static_audit_only;runtime_build_device_and_legado_diff_deferred'
  }
}

Write-AtomicJson -Path $resultFullPath -Value $result
$result | ConvertTo-Json -Depth 50
if ($exitCode -ne 0) { exit $exitCode }
