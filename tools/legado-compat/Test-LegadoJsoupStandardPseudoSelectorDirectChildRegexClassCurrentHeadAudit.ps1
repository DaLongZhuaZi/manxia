[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selector-direct-child-regex-class-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-direct-child-regex-class-context-pre-fix-20260809.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-direct-child-regex-class-context-post-fix-20260809.json',
  [string]$SplitContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-direct-child-split-context-post-fix-20260809.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-direct-child-regex-class-context-current-head-audit-20260809.json'
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
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$RelativePath); return (Read-StrictText -RelativePath $RelativePath | ConvertFrom-Json -Depth 100) }
function Assert-Audit {
  param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @())
  if (-not $Condition) { throw "243 regex-class current-head audit failed: $Detail" }
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
$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$analyzerRelativePath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$elementRelativePath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$runtimeRelativePath = 'entry/src/main/resources/rawfile/legado_runtime.html'
$legadoRelativePath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$state = Read-StrictJson $statePath
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$contract = Read-StrictJson $PostFixContractPath
$splitContract = Read-StrictJson $SplitContractPath
$analyzer = Read-StrictText $analyzerRelativePath
$element = Read-StrictText $elementRelativePath
$runtime = Read-StrictText $runtimeRelativePath
$legado = Read-StrictText $legadoRelativePath
$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' })[0]

Assert-Audit ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'the frozen 458-source package and Legado commit remain unchanged.' @($statePath)
Assert-Audit ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and -not [bool]$state.governance.semanticMatchAllowed) 'queue' '243 remains the sole active issue and semantic match remains disabled.' @($statePath)
Assert-Audit ($null -ne $issue -and [string]$issue.status -eq 'verifying') 'issue_status' '243 remains verifying.' @($statePath)
Assert-Audit ([string]$failure.status -eq 'failed' -and -not [bool]$failure.semanticMatchAllowed -and @($failure.runtimeActionsPerformed).Count -eq 0) 'failure_witness' 'regex-class failure witness remains failed and static-only.' @($FailureWitnessPath)
Assert-Audit ([string]$contract.status -eq 'passed' -and -not [bool]$contract.semanticMatchAllowed -and @($contract.runtimeActionsPerformed).Count -eq 0) 'regex_contract' 'regex-class source contract is a static-only pass.' @($PostFixContractPath)
Assert-Audit ([string]$splitContract.status -eq 'passed' -and -not [bool]$splitContract.semanticMatchAllowed) 'split_contract' 'the broader top-level split contract remains preserved.' @($SplitContractPath)
Assert-Audit (@($fixture.cases).Count -eq 2) 'fixture_shape' 'the regex-class fixture contains two cases.' @($FixturePath)

$helperStart = $analyzer.IndexOf('private splitTopLevelDirectChildSelectors(')
$helperEnd = $analyzer.IndexOf('private findElementsByDirectChildSelector(', $helperStart)
Assert-Audit ($helperStart -ge 0 -and $helperEnd -gt $helperStart) 'helper_boundary' 'the top-level splitter remains present.' @($analyzerRelativePath)
$helperBody = $analyzer.Substring($helperStart, $helperEnd - $helperStart)
Assert-Audit ($helperBody.Contains("if (character === '(' && bracketDepth === 0) {") -and $helperBody.Contains("else if (character === ')' && parenthesisDepth > 0 && bracketDepth === 0) {")) 'regex_class_guards' 'pseudo parenthesis accounting is opaque to regex or attribute brackets.' @($analyzerRelativePath)
Assert-Audit ($helperBody.Contains("character === '>' && parenthesisDepth === 0 && bracketDepth === 0")) 'top_level_boundary' 'only a fully top-level greater-than remains a direct-child boundary.' @($analyzerRelativePath)
Assert-Audit ($analyzer.Contains('matchesStringHasPseudo') -and $element.Contains("pseudo.name === 'has'") -and $runtime.Contains('root.querySelectorAll(browserSelector)') -and $legado.Contains('temp.select(ruleStr)')) 'consumer_paths' 'string fallback, DOM matcher, ArkWeb and pinned Legado consumers remain bound.' @($analyzerRelativePath, $elementRelativePath, $runtimeRelativePath, $legadoRelativePath)

$hashes = [ordered]@{}
foreach ($path in @($analyzerRelativePath, $elementRelativePath, $runtimeRelativePath)) {
  $bytes = [System.IO.File]::ReadAllBytes((Get-RepoPath $path))
  Assert-Audit (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) ('no_bom_' + $path.Replace('/', '_')) "source has no UTF-8 BOM: $path" @($path)
  $hashes[$path] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $path)).Hash.ToUpperInvariant()
}
$legadoHead = (& git -C (Get-RepoPath 'legado') rev-parse HEAD 2>$null | Out-String).Trim()
Assert-Audit ($legadoHead -eq $legadoCommit) 'legado_head' 'Legado checkout remains pinned to the reference commit.' @($legadoRelativePath)

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'current_head_static_audit'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  supersedes = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-direct-child-split-context-current-head-audit-20260809.json'
  changedPaths = @($analyzerRelativePath, $elementRelativePath, $runtimeRelativePath)
  currentHeadHashes = $hashes
  consumerMatrix = @(
    [pscustomobject][ordered]@{ id = 'direct_child_split_regex_class'; path = $analyzerRelativePath; status = 'supported_static'; semantics = @('regex character class parenthesis', 'regex greater-than inside pseudo argument', 'outer direct-child combinator') },
    [pscustomobject][ordered]@{ id = 'direct_child_split_context'; path = $analyzerRelativePath; status = 'supported_static'; semantics = @('nested pseudo', 'attribute value', 'quoted value', 'escape context') },
    [pscustomobject][ordered]@{ id = 'dom_matcher'; path = $elementRelativePath; status = 'supported_static'; semantics = @('standard pseudo and :has consumer') },
    [pscustomobject][ordered]@{ id = 'arkweb_native_selector'; path = $runtimeRelativePath; status = 'supported_static'; semantics = @('browser selector consumer') }
  )
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_current_head_static_audit_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  nextGate = 'R4 must execute regex-class and all existing direct-child cases against fixed Legado before 243 can leave verifying.'
}
Write-AtomicJson -RelativePath $ResultPath -Value $result
$result | ConvertTo-Json -Depth 80
