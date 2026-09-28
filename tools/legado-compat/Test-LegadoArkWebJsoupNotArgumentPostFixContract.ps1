[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-arkweb-jsoup-not-argument-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-not-argument-pre-fix-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-not-argument-post-fix-20260810.json'
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

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; $bytes = [System.IO.File]::ReadAllBytes($resolved); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }; return $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText $Path | ConvertFrom-Json -Depth 100) }
function Assert-Contract { param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @()); if (-not $Condition) { throw "ArkWeb 243 :not argument post-fix contract failed: $Detail" }; $script:assertions++; [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) }) }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$runtimePath = 'entry/src/main/resources/rawfile/legado_runtime.html'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$runtime = Read-StrictText $runtimePath
$legado = Read-StrictText $legadoPath
$matchesBodyStart = $runtime.IndexOf('var legadoMatchesAnyJsoupSelector = function')
$matchesBodyEnd = $runtime.IndexOf('var legadoSelectorHasInvalidRegexAttribute = function', $matchesBodyStart)
$matchesBody = if ($matchesBodyStart -ge 0 -and $matchesBodyEnd -gt $matchesBodyStart) { $runtime.Substring($matchesBodyStart, $matchesBodyEnd - $matchesBodyStart) } else { '' }

Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'frozen machine baseline is unchanged.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Contract ([string]$fixture.issueId -eq $issueId -and [string]$fixture.contract -eq 'arkweb_legado_jsoup_not_argument_context' -and @($fixture.cases).Count -eq 3) 'fixture' 'not-argument fixture retains three full-context cases.' @($FixturePath)
Assert-Contract (@($fixture.affectedSourceOrdinals).Count -eq 1 -and @($fixture.affectedSourceOrdinals) -contains 402) 'affected_sources' 'the frozen affected set retains ordinal 402.' @($FixturePath)
Assert-Contract ([string]$failure.status -eq 'failed' -and @($failure.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed) 'failure_witness' 'pre-fix witness remains failed and static-only.' @($FailureWitnessPath)
Assert-Contract ($runtime.Contains('var legadoMatchesJsoupSelectorInContext = function') -and $runtime.Contains('legadoSelectWithJsoupRegex(selectionRoot, selector, documentRoot)')) 'context_helper' 'nested selector arguments can select against the complete available root.' @($runtimePath)
Assert-Contract ($runtime.Contains('if (legadoMatchesJsoupSelectorInContext(node, groups[groupIndex], documentRoot)) return true;')) 'context_projection' ':not selector-list groups project the candidate node from contextual selection.' @($runtimePath)
Assert-Contract ($matchesBody.Contains('legadoMatchesJsoupSelector(node, groups[groupIndex], documentRoot)') -and $matchesBody.Contains('legadoMatchesJsoupSelectorInContext(node, groups[groupIndex], documentRoot)')) 'fast_and_context_paths' 'the local matches fast path remains, with a full-context fallback.' @($runtimePath)
Assert-Contract ($runtime.Contains('legadoMatchesAnyJsoupSelector(predicateNode, argument, documentRoot)')) 'owning_compound' 'the contextual fallback is invoked for the resolved owning compound.' @($runtimePath)
Assert-Contract ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'legado_consumer' 'the pinned Legado consumer remains the Jsoup CSS-selection reference.' @($legadoPath)

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
  verificationPolicy = 'r3_243_arkweb_not_argument_post_fix_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  closeCondition = 'R4 must execute all three :not argument cases, ordinal 402, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
