[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selector-descendant-whitespace-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-descendant-whitespace-context-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-descendant-whitespace-context-post-fix-20260810.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-descendant-whitespace-current-head-audit-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }; return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Missing text: $Path" }; $bytes = [System.IO.File]::ReadAllBytes($resolved); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }; return $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText $Path | ConvertFrom-Json -Depth 100) }
function Assert-Audit { param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @()); if (-not $Condition) { throw "243 descendant whitespace current-head audit failed: $Detail" }; $script:assertions++; [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) }) }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$contract = Read-StrictJson $PostFixContractPath
$analyzer = Read-StrictText $analyzerPath
$legado = Read-StrictText 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'

Assert-Audit ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'frozen source and Legado baselines are unchanged.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Audit ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) 'queue' '243 remains the sole active static issue with semantic matching disabled.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Audit ([string]$failure.status -eq 'failed' -and [string]$contract.status -eq 'passed' -and -not [bool]$contract.semanticMatchAllowed -and @($contract.runtimeActionsPerformed).Count -eq 0) 'evidence_chain' 'failure witness and post-fix contract form a static-only evidence chain.' @($FailureWitnessPath, $PostFixContractPath)
Assert-Audit ([string]$fixture.issueId -eq $issueId -and @($fixture.cases).Count -eq 5) 'fixture' 'five parser-context cases remain bound to 243.' @($FixturePath)

$singleStart = $analyzer.IndexOf('private findElementsBySingleSelector(')
$simpleStart = $analyzer.IndexOf('private findElementsBySimpleSelector(', $singleStart)
$helperStart = $analyzer.IndexOf('private splitTopLevelCssDescendantSelector(')
$helperEnd = $analyzer.IndexOf('private annotateStringSelectorHtml(', $helperStart)
Assert-Audit ($singleStart -ge 0 -and $simpleStart -gt $singleStart -and $helperStart -ge 0 -and $helperEnd -gt $helperStart) 'source_boundaries' 'single-selector and top-level descendant helper boundaries are present.' @($analyzerPath)
$singleBody = $analyzer.Substring($singleStart, $simpleStart - $singleStart)
$helperBody = $analyzer.Substring($helperStart, $helperEnd - $helperStart)
Assert-Audit ($singleBody.Contains('directChildParts.length > 1') -and $singleBody.Contains('this.splitTopLevelCssDescendantSelector(selector)')) 'source_dispatch' 'current source gates direct-child dispatch at top level and uses the stateful descendant splitter.' @($analyzerPath)
Assert-Audit (-not $singleBody.Contains('selector.trim().split(/\s+/)') -and -not $singleBody.Contains("if (selector.includes('>'))")) 'source_raw_split_removed' 'raw whitespace and raw greater-than dispatch are absent from the selector path.' @($analyzerPath)
Assert-Audit ($helperBody.Contains('parenthesisDepth') -and $helperBody.Contains('bracketDepth') -and $helperBody.Contains('quote') -and $helperBody.Contains('escaped')) 'source_parser_state' 'helper preserves nested pseudo, attribute, quote and escape state.' @($analyzerPath)
Assert-Audit ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains("lastIndexOf('@')")) 'legado_reference' 'pinned Legado continues to delegate CSS evaluation to Jsoup.' @('legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt')

$bytes = [System.IO.File]::ReadAllBytes((Get-RepoPath $analyzerPath))
Assert-Audit (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) 'utf8' 'analyzer source is UTF-8 without BOM.' @($analyzerPath)
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $analyzerPath)).Hash.ToUpperInvariant()
$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'current_head_static_audit'
  issueId = $issueId
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  changedPaths = @($analyzerPath)
  currentHeadHashes = [pscustomobject][ordered]@{ $analyzerPath = $hash }
  fixturePath = $FixturePath
  failureWitnessPath = $FailureWitnessPath
  postFixContractPath = $PostFixContractPath
  affectedCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_descendant_whitespace_current_head_static_only;runtime_build_device_and_legado_diff_deferred'
  nextGate = 'Register the source fix and retain 243 verifying until R4 runtime, deterministic Harness, fixed-Legado differential, build and device gates.'
}
Write-AtomicJson $ResultPath $result
$result | ConvertTo-Json -Depth 100
