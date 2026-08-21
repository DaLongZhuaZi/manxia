[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selector-descendant-whitespace-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-descendant-whitespace-context-pre-fix-20260810.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-descendant-whitespace-context-post-fix-20260810.json'
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
function Assert-Contract { param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @()); if (-not $Condition) { throw "243 descendant whitespace post-fix contract failed: $Detail" }; $script:assertions++; [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) }) }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$analyzer = Read-StrictText $analyzerPath
$legado = Read-StrictText 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'

Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'frozen source and Legado baselines remain unchanged.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Contract ([string]$state.governance.activeIssueId -eq $issueId -and [string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.status -eq 'running') 'queue' '243 remains the sole active static issue.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Contract ([string]$failure.status -eq 'failed' -and -not [bool]$failure.semanticMatchAllowed -and @($failure.runtimeActionsPerformed).Count -eq 0) 'failure_witness' 'pre-fix whitespace split failure remains failed and static-only.' @($FailureWitnessPath)
Assert-Contract ([string]$fixture.issueId -eq $issueId -and @($fixture.cases).Count -eq 5) 'fixture' 'descendant whitespace fixture remains bound to five cases.' @($FixturePath)

$singleStart = $analyzer.IndexOf('private findElementsBySingleSelector(')
$simpleStart = $analyzer.IndexOf('private findElementsBySimpleSelector(', $singleStart)
Assert-Contract ($singleStart -ge 0 -and $simpleStart -gt $singleStart) 'single_boundary' 'single-selector fallback boundary is stable.' @($analyzerPath)
$singleBody = $analyzer.Substring($singleStart, $simpleStart - $singleStart)
Assert-Contract ($singleBody.Contains('this.splitTopLevelDirectChildSelectors(selector)') -and $singleBody.Contains('directChildParts.length > 1')) 'top_level_direct_dispatch' 'direct-child dispatch is gated by a top-level split result.' @($analyzerPath)
Assert-Contract (-not $singleBody.Contains("if (selector.includes('>'))")) 'nested_gt_guard' 'nested pseudo/attribute greater-than text no longer activates the direct-child branch.' @($analyzerPath)
Assert-Contract ($singleBody.Contains('this.splitTopLevelCssDescendantSelector(selector)') -and -not $singleBody.Contains('selector.trim().split(/\s+/)')) 'top_level_descendant_dispatch' 'descendant splitting is stateful and does not split pseudo or attribute argument whitespace.' @($analyzerPath)
Assert-Contract ($singleBody.Contains('findElementsBySimpleSelector(html, selector, effectiveContextHtml)')) 'single_part_context' 'single-part pseudo evaluation retains the full selector context.' @($analyzerPath)

$helperStart = $analyzer.IndexOf('private splitTopLevelCssDescendantSelector(')
$helperEnd = $analyzer.IndexOf('private annotateStringSelectorHtml(', $helperStart)
Assert-Contract ($helperStart -ge 0 -and $helperEnd -gt $helperStart) 'helper_boundary' 'top-level descendant splitter has a stable boundary.' @($analyzerPath)
$helperBody = $analyzer.Substring($helperStart, $helperEnd - $helperStart)
Assert-Contract ($helperBody.Contains('parenthesisDepth') -and $helperBody.Contains('bracketDepth') -and $helperBody.Contains('quote') -and $helperBody.Contains('escaped')) 'parser_state' 'descendant splitter tracks parentheses, brackets, quotes and escapes.' @($analyzerPath)
Assert-Contract ($helperBody.Contains('parenthesisDepth === 0 && bracketDepth === 0 && /\s/.test(character)')) 'top_level_space_guard' 'only top-level whitespace creates a descendant boundary.' @($analyzerPath)
Assert-Contract ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains("lastIndexOf('@')")) 'legado_consumer' 'pinned Legado keeps Jsoup selector evaluation and final attribute split semantics.' @('legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt')

$hashes = [ordered]@{ $analyzerPath = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $analyzerPath)).Hash.ToUpperInvariant() }
$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'post_fix_static_contract'
  issueId = $issueId
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  failureWitnessPath = $FailureWitnessPath
  changedPaths = @($analyzerPath)
  currentHeadHashes = $hashes
  affectedCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_descendant_whitespace_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  closeCondition = 'R4 must execute pseudo-argument whitespace, quoted attributes, nested :has/:not with outer descendants, affected 243 sources, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $ResultPath $result
$result | ConvertTo-Json -Depth 100
