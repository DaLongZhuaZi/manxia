[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-css-at-delimiter-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-css-at-delimiter-context-pre-fix-20260810.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-css-at-delimiter-context-post-fix-20260810.json'
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
function Assert-Contract { param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @()); if (-not $Condition) { throw "243 CSS @ delimiter post-fix contract failed: $Detail" }; $script:assertions++; [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) }) }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$analyzer = Read-StrictText $analyzerPath
$legado = Read-StrictText 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$legadoRuleAnalyzer = Read-StrictText 'legado/app/src/main/java/io/legado/app/model/analyzeRule/RuleAnalyzer.kt'
$indexStart = $analyzer.IndexOf('private hasLegacyIndexInCssChain(')
$chainStart = $analyzer.IndexOf('private getElementsByCSSChain(', $indexStart)
$splitStart = $analyzer.IndexOf('private splitSelectorWithJs(', $chainStart)
$parseCssStart = $analyzer.IndexOf('private parseCSSSelectorAndAttr(', $splitStart)

Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'frozen source and Legado baselines remain unchanged.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Contract ([string]$state.governance.activeIssueId -eq $issueId -and [string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.status -eq 'running') 'queue' '243 remains the sole active static issue.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Contract ([string]$failure.status -eq 'failed' -and -not [bool]$failure.semanticMatchAllowed -and @($failure.runtimeActionsPerformed).Count -eq 0) 'failure_witness' 'pre-fix @ delimiter failure remains failed and static-only.' @($FailureWitnessPath)
Assert-Contract ([string]$fixture.issueId -eq $issueId -and @($fixture.cases).Count -eq 3 -and [int]$fixture.largeDocumentThreshold -eq 50000) 'fixture' 'large-document @ delimiter fixture remains bound to three cases.' @($FixturePath)
Assert-Contract ($indexStart -ge 0 -and $chainStart -gt $indexStart -and $splitStart -gt $chainStart -and $parseCssStart -gt $splitStart) 'source_boundaries' 'index, chain and stateful @ splitter boundaries are stable.' @($analyzerPath)

$indexBody = $analyzer.Substring($indexStart, $chainStart - $indexStart)
$chainBody = $analyzer.Substring($chainStart, $splitStart - $chainStart)
$splitBody = $analyzer.Substring($splitStart, $parseCssStart - $splitStart)
Assert-Contract ($indexBody.Contains('this.splitSelectorWithJs(selector)') -and -not $indexBody.Contains("selector.split('@')")) 'index_shared_splitter' 'legacy-index detection shares the stateful top-level @ splitter.' @($analyzerPath)
Assert-Contract ($chainBody.Contains('this.splitSelectorWithJs(selector)') -and -not $chainBody.Contains("selector.split('@')")) 'chain_shared_splitter' 'large-document CSS chain shares the stateful top-level @ splitter.' @($analyzerPath)
Assert-Contract ($splitBody.Contains('parenthesisDepth') -and $splitBody.Contains('bracketDepth') -and $splitBody.Contains('quote') -and $splitBody.Contains('escaped') -and $splitBody.Contains('inJs')) 'parser_state' 'splitter preserves parentheses, brackets, quotes, escapes and <js> state.' @($analyzerPath)
Assert-Contract ($splitBody.Contains("character === '@' && parenthesisDepth === 0 && bracketDepth === 0")) 'top_level_at_guard' 'only a top-level @ creates a Legado chain boundary.' @($analyzerPath)
Assert-Contract ($legado.Contains("lastIndexOf('@')") -and $legado.Contains('temp.select(ruleStr)') -and $legadoRuleAnalyzer.Contains('chompRuleBalanced') -and $legadoRuleAnalyzer.Contains('splitRule')) 'legado_reference' 'pinned Legado keeps final output-attribute semantics, balanced selector contexts and Jsoup evaluation.' @('legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt', 'legado/app/src/main/java/io/legado/app/model/analyzeRule/RuleAnalyzer.kt')

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
  verificationPolicy = 'r3_243_css_at_delimiter_context_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  closeCondition = 'R4 must execute large-document CSS selectors with @ inside pseudo arguments, quoted attributes and regex, affected 243 sources, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $ResultPath $result
$result | ConvertTo-Json -Depth 100
