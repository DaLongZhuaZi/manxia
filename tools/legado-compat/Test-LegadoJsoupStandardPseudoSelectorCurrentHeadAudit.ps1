[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selectors.json',
  [string]$PreFixEvidencePath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selectors-pre-fix-20260809.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selectors-post-fix-20260809.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-current-head-audit-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$RelativePath); return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required file is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$RelativePath); return (Read-StrictText $RelativePath | ConvertFrom-Json -Depth 100) }
function Assert-Audit {
  param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @())
  if (-not $Condition) { throw "243 current-head audit failed: $Detail" }
  $script:assertions++
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) })
}
function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value)
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try { [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 80), $noBomUtf8); Move-Item -LiteralPath $temporaryPath -Destination $path -Force }
  finally { if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) } }
}

$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$paths = @(
  'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
  'entry/src/main/ets/libs/htmlparser/HTMLElement.ets',
  'entry/src/main/resources/rawfile/legado_runtime.html'
)
$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
  $fixture = Read-StrictJson $FixturePath
  $preFix = Read-StrictJson $PreFixEvidencePath
  $contract = Read-StrictJson $PostFixContractPath
  Assert-Audit ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'frozen machine baseline is unchanged.' @('tools/legado-compat/state/full-source-validation-state.json')
  Assert-Audit ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and [string]$state.governance.status -eq 'running') 'queue_precondition' '243 remains the sole active issue while its current-head audit is refreshed.' @('tools/legado-compat/state/full-source-validation-state.json')
  Assert-Audit ([string]$preFix.status -eq 'failed' -and -not [bool]$preFix.semanticMatchAllowed) 'failure_witness' '243 pre-fix failure witness is preserved as failed and static-only.' @($PreFixEvidencePath)
  Assert-Audit ([string]$contract.status -eq 'passed' -and [int]$contract.assertions -ge 30 -and -not [bool]$contract.semanticMatchAllowed -and @($contract.runtimeActionsPerformed).Count -eq 0) 'post_fix_contract' '243 post-fix contract is a static-only pass.' @($PostFixContractPath)
  Assert-Audit (@($fixture.cases).Count -eq 6 -and [int]$fixture.pseudoCounts.total -eq 52) 'fixture' '243 fixture retains six cases and 52-rule impact metadata.' @($FixturePath)
  Assert-Audit ((& git -C (Get-RepoPath 'legado') rev-parse HEAD 2>$null | Out-String).Trim() -eq $legadoCommit) 'legado_head' 'Legado checkout remains pinned.' @('legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt')

  $hashes = [ordered]@{}
  $matrix = New-Object 'System.Collections.Generic.List[object]'
  foreach ($path in $paths) {
    $absolutePath = Get-RepoPath $path
    $bytes = [System.IO.File]::ReadAllBytes($absolutePath)
    Assert-Audit (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) ('no_bom_' + $path.Replace('/', '_')) ("source has no UTF-8 BOM: $path") @($path)
    $text = $strictUtf8.GetString($bytes)
    if ($path.EndsWith('LegadoRuleAnalyzer.ets')) {
      Assert-Audit ($text.Contains('filterElementsByStandardChildPseudo') -and $text.Contains('siblingCount: number') -and $text.Contains('siblingPosition.siblingIndex + 1')) 'string_fallback' 'large-document fallback has standard child pseudo evaluation with explicit sibling context.' @($path)
      [void]$matrix.Add([pscustomobject][ordered]@{ id = 'large_document_string_fallback'; path = $path; status = 'supported_static'; semantics = @('first-child', 'last-child', 'nth-child 1-based an+b', 'only-child') })
    } elseif ($path.EndsWith('HTMLElement.ets')) {
      Assert-Audit ($text.Contains("pseudo.name === 'first-child'") -and $text.Contains("pseudo.name === 'last-child'") -and $text.Contains("pseudo.name === 'nth-child'") -and $text.Contains("pseudo.name === 'only-child'")) 'dom_matcher' 'DOM matcher exposes all four standard child pseudo branches.' @($path)
      [void]$matrix.Add([pscustomobject][ordered]@{ id = 'dom_matcher'; path = $path; status = 'supported_static'; semantics = @('first-child', 'last-child', 'nth-child 1-based an+b', 'only-child') })
    } else {
      $parserStart = $text.IndexOf('var legadoParseJsoupTextPseudos = function')
      $parserEnd = $text.IndexOf('var legadoPseudoArgument = function', $parserStart)
      $parser = if ($parserStart -ge 0 -and $parserEnd -gt $parserStart) { $text.Substring($parserStart, $parserEnd - $parserStart) } else { '' }
      Assert-Audit ($parser.Length -gt 0 -and -not $parser.Contains("name === 'first-child'") -and -not $parser.Contains("name === 'last-child'") -and -not $parser.Contains("name === 'nth-child'") -and -not $parser.Contains("name === 'only-child'") -and $text.Contains('root.querySelectorAll(browserSelector)')) 'arkweb_native_css' 'ArkWeb keeps standard child pseudos in the native browser selector path.' @($path)
      [void]$matrix.Add([pscustomobject][ordered]@{ id = 'arkweb_native_selector'; path = $path; status = 'supported_static'; semantics = @('browser querySelectorAll standard CSS child pseudos') })
    }
    $hashes[$path] = (Get-FileHash -Algorithm SHA256 -LiteralPath $absolutePath).Hash.ToUpperInvariant()
  }
  Assert-Audit ($matrix.Count -eq 3) 'consumer_matrix' 'all V2 consumer paths are registered.' $paths

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    evidenceType = 'current_head_static_audit'
    issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
    status = 'passed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
    changedPaths = $paths
    currentHeadHashes = $hashes
    consumerMatrix = $matrix.ToArray()
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_current_head_static_audit_only;runtime_build_device_and_legado_diff_deferred_to_R4'
    nextGate = '243 remains verifying until R4 executes the selector equivalence classes, full Harness, fixed-Legado differential, build and device gates.'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{ schemaVersion = 1; evidenceType = 'current_head_static_audit'; issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'; status = 'failed'; generatedAt = [DateTimeOffset]::UtcNow.ToString('o'); failure = $_.Exception.Message; assertions = $script:assertions; checks = $script:checks.ToArray(); runtimeActionsPerformed = @(); semanticMatchAllowed = $false; verificationPolicy = 'r3_current_head_static_audit_only;runtime_build_device_and_legado_diff_deferred_to_R4' }
}
Write-AtomicJson -RelativePath $ResultPath -Value $result
$result | ConvertTo-Json -Depth 80
if ($exitCode -ne 0) { exit $exitCode }
