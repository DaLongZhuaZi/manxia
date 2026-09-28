[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-arkweb-jsoup-regex-contains-composition-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-regex-contains-composition-pre-fix-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-regex-contains-composition-post-fix-20260810.json'
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
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; $bytes = [System.IO.File]::ReadAllBytes($resolved); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }; $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); Read-StrictText $Path | ConvertFrom-Json -Depth 100 }
function Assert-Contract { param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @()); if (-not $Condition) { throw "ArkWeb 243 regex/contains post-fix contract failed: $Detail" }; $script:assertions++; [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) }) }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$runtimePath = 'entry/src/main/resources/rawfile/legado_runtime.html'
$runtime = Read-StrictText $runtimePath
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$analyzer = Read-StrictText $analyzerPath
$matcherPath = 'entry/src/main/ets/libs/htmlparser/Matcher.ets'
$matcher = Read-StrictText $matcherPath
$elementPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$element = Read-StrictText $elementPath
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$legado = Read-StrictText $legadoPath

Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'frozen machine baseline is unchanged.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Contract ([string]$fixture.issueId -eq $issueId -and [string]$fixture.contract -eq 'arkweb_legado_jsoup_regex_contains_composition_context') 'fixture' 'ordinal-267 regex/contains fixture binding is unchanged.' @($FixturePath)
Assert-Contract (@($fixture.affectedSourceOrdinals).Count -eq 1 -and [int]$fixture.affectedSourceOrdinals[0] -eq 267 -and @($fixture.cases).Count -eq 3) 'affected_set' 'the fixture retains one real source and three composition controls.' @($FixturePath)
Assert-Contract ([string]$failure.status -eq 'failed' -and @($failure.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed) 'failure_witness' 'pre-fix evidence remains failed and static-only.' @($FailureWitnessPath)
Assert-Contract ($runtime.Contains('legadoMatchesJsoupSelector(ancestor, pseudo.targetSelector, documentRoot)')) 'owning_compound_bridge' 'ArkWeb resolves the owning compound through the Jsoup-aware selector bridge.' @($runtimePath)
Assert-Contract (-not $runtime.Contains('if (ancestor.matches && ancestor.matches(pseudo.targetSelector))')) 'native_branch_removed' 'the native-only target compound branch is removed.' @($runtimePath)
Assert-Contract ($runtime.Contains('legadoParseRegexAttributeSelectors') -and $runtime.Contains('legadoNormalizeJavaRegex')) 'regex_semantics' 'the selector bridge retains Jsoup regex and Java inline-flag handling.' @($runtimePath)
Assert-Contract ($runtime.Contains("pseudo.name === 'contains'") -or $runtime.Contains("pseudoName === 'contains'")) 'text_pseudo_semantics' 'the same ArkWeb pipeline retains :contains evaluation.' @($runtimePath)
Assert-Contract ($analyzer.Contains('parseLegadoAttributeSelectors') -and $analyzer.Contains("pseudo.name === 'contains'")) 'string_fallback_consumer' 'large-document fallback keeps regex attributes and :contains as separate conjunctive filters.' @($analyzerPath)
Assert-Contract ($matcher.Contains('static matchAttribute') -and $element.Contains('Matcher.matchAttribute') -and $element.Contains("pseudo.name === 'contains'")) 'dom_consumer' 'DOM Matcher keeps regex attributes and :contains in the owning selector part.' @($matcherPath, $elementPath)
Assert-Contract ($legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'legado_consumer' 'pinned Legado remains the complete Element.select semantic reference.' @($legadoPath)

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'post_fix_static_contract'
  issueId = $issueId
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  failureWitnessPath = $FailureWitnessPath
  changedPaths = @($runtimePath)
  affectedSourceOrdinals = @($fixture.affectedSourceOrdinals)
  cases = @($fixture.cases).Count
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_arkweb_regex_contains_composition_post_fix_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  closeCondition = 'R4 must execute all three ordinal-267 composition cases, the existing 243 pseudo equivalence classes, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
