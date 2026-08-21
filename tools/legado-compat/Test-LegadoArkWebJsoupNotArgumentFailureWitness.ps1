[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-arkweb-jsoup-not-argument-context.json',
  [string]$RuntimeSnapshotPath = 'entry/src/main/resources/rawfile/legado_runtime.html.bak_20260810_issue243_not_argument_context',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-not-argument-pre-fix-20260810.json'
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

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; $bytes = [System.IO.File]::ReadAllBytes($resolved); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }; return $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText $Path | ConvertFrom-Json -Depth 100) }
function Assert-Witness { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "ArkWeb 243 :not argument failure witness failed: $Message" }; $script:assertions++ }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$runtime = Read-StrictText $RuntimeSnapshotPath
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$legado = Read-StrictText $legadoPath
$sourcePath = 'F:/Downloads-E/墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToUpperInvariant()
$sources = @($strictUtf8.GetString([System.IO.File]::ReadAllBytes($sourcePath)) | ConvertFrom-Json -Depth 100)
$source402 = $sources[401] | ConvertTo-Json -Depth 100 -Compress
$matchesBodyStart = $runtime.IndexOf('var legadoMatchesAnyJsoupSelector = function')
$matchesBodyEnd = $runtime.IndexOf('var legadoSelectorHasInvalidRegexAttribute = function', $matchesBodyStart)
$matchesBody = if ($matchesBodyStart -ge 0 -and $matchesBodyEnd -gt $matchesBodyStart) { $runtime.Substring($matchesBodyStart, $matchesBodyEnd - $matchesBodyStart) } else { '' }

Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen machine baseline drifted.'
Assert-Witness ($sourceHash -eq $baselineHash -and $sources.Count -eq 458) 'frozen source package drifted.'
Assert-Witness ([string]$fixture.issueId -eq $issueId -and [string]$fixture.contract -eq 'arkweb_legado_jsoup_not_argument_context' -and @($fixture.cases).Count -eq 3) 'not-argument fixture binding or case count changed.'
Assert-Witness (@($fixture.affectedSourceOrdinals).Count -eq 1 -and @($fixture.affectedSourceOrdinals) -contains 402) 'affected source ordinal is not bound to the frozen package.'
foreach ($rule in @($fixture.affectedRuleStrings)) { Assert-Witness ($source402.Contains([string]$rule)) ("representative source 402 rule is missing: $rule") }
Assert-Witness ($runtime.Contains('var legadoMatchesAnyJsoupSelector = function (node, selector, documentRoot)')) 'pre-fix selector-list matcher is missing.'
Assert-Witness ($matchesBody.Contains('legadoMatchesJsoupSelector(node, groups[groupIndex], documentRoot)')) 'pre-fix :not argument still delegates to the candidate matcher.'
Assert-Witness (-not $matchesBody.Contains('legadoSelectWithJsoupRegex(')) 'pre-fix :not argument matcher has no full-context selection projection.'
Assert-Witness ($runtime.Contains('if (!node.matches(browserSelector)) return false;')) 'pre-fix nested selectors are reduced to node.matches and lose ancestor combinators.'
Assert-Witness ($runtime.Contains('legadoMatchesAnyJsoupSelector(predicateNode, argument, documentRoot)')) 'outer compound target fix is present, isolating the remaining nested-argument context loss.'
Assert-Witness ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado Jsoup selector handoff is missing.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'failure_witness'
  issueId = $issueId
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  sourcePackagePath = 'redacted_pinned_package'
  sourcePackageHash = $sourceHash
  affectedSourceSet = [pscustomobject][ordered]@{ sourceOrdinals = @($fixture.affectedSourceOrdinals); ruleStringCount = @($fixture.affectedRuleStrings).Count }
  sourcePaths = @($RuntimeSnapshotPath, $legadoPath)
  runtimeSnapshotPath = $RuntimeSnapshotPath
  runtimeSnapshotSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $RuntimeSnapshotPath)).Hash.ToUpperInvariant()
  failureWitness = [pscustomobject][ordered]@{
    branch = 'legadoMatchesJsoupPseudo(:not) -> legadoMatchesAnyJsoupSelector -> legadoMatchesJsoupSelector -> node.matches'
    observed = 'After the owning compound is resolved, the ArkWeb :not argument matcher still checks only node.matches(browserSelector). Ancestor-dependent selectors and selector lists therefore never identify the candidate in the complete root.'
    expected = 'Evaluate each :not argument against the complete available selection root and project the candidate node identity, preserving nested pseudo evaluation.'
    representativeRules = @($fixture.affectedRuleStrings)
  }
  rootCauseCategory = '规则解析或编译'
  rootCauseDecision = 'Pinned Legado Jsoup evaluates :not arguments as selectors in the original Element context. ArkWeb keeps only a local matches() check, so combinators in :not arguments are silently treated as non-matches.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_arkweb_not_argument_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  assertions = $script:assertions
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
