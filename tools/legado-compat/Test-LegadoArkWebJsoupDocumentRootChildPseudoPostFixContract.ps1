[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-arkweb-jsoup-dom-document-root-child-pseudo.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-dom-document-root-child-pseudo-pre-fix-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-dom-document-root-child-pseudo-post-fix-20260810.json'
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
function Assert-Contract { param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @()); if (-not $Condition) { throw "ArkWeb 243 post-fix contract failed: $Detail" }; $script:assertions++; [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) }) }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$runtimePath = 'entry/src/main/resources/rawfile/legado_runtime.html'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$runtime = Read-StrictText $runtimePath
$legado = Read-StrictText $legadoPath

Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'frozen machine baseline is unchanged.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Contract ([string]$fixture.issueId -eq $issueId -and @($fixture.htmlCases).Count -eq 10 -and @($fixture.affectedSourceOrdinals).Count -eq 13) 'fixture' 'ArkWeb fixture retains ten deterministic root/context cases and the 13-source affected set.' @($FixturePath)
Assert-Contract ([string]$failure.status -eq 'failed' -and @($failure.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed) 'failure_witness' 'ArkWeb pre-fix witness remains failed and static-only.' @($FailureWitnessPath)
Assert-Contract ($runtime.Contains('var legadoStandardDocumentPseudoNames = [') -and $runtime.Contains("'first-child'") -and $runtime.Contains("'nth-last-of-type'")) 'standard_pseudo_registry' 'ArkWeb registers the full child/of-type pseudo set for synthetic Document evaluation.' @($runtimePath)
Assert-Contract ($runtime.Contains('legadoParseJsoupTextPseudos = function (selector, extractStandardDocumentPseudos)') -and $runtime.Contains('isStandardDocumentPseudo')) 'standard_pseudo_compiler' 'standard pseudos are extracted only for the explicit synthetic Document context.' @($runtimePath)
Assert-Contract ($runtime.Contains("holder.setAttribute('data-legado-document-root', '1');") -and $runtime.Contains('legadoIsSyntheticDocumentRoot')) 'synthetic_root_marker' 'the response holder is explicitly marked as a synthetic Jsoup Document boundary.' @($runtimePath)
Assert-Contract ($runtime.Contains('var legadoElementSiblingCount = function') -and $runtime.Contains('var legadoElementTypeCount = function')) 'position_helpers' 'manual child/of-type evaluation has explicit sibling and same-tag counts.' @($runtimePath)
Assert-Contract ($runtime.Contains('legadoMatchesJsoupPseudo = function (node, pseudo, documentRoot)') -and $runtime.Contains('predicateNode.parentElement === documentRoot') -and $runtime.Contains('legadoIsDocumentBoundaryPseudo')) 'document_boundary_guard' 'direct children of the synthetic Document fail closed for child/of-type pseudos.' @($runtimePath)
Assert-Contract ($runtime.Contains("pseudoName === 'first-child'") -and $runtime.Contains("pseudoName === 'last-child'") -and $runtime.Contains("pseudoName === 'nth-child'") -and $runtime.Contains("pseudoName === 'only-child'")) 'child_pseudo_dispatch' 'all standard child pseudo branches are evaluated with element-child positions.' @($runtimePath)
Assert-Contract ($runtime.Contains("pseudoName === 'first-of-type'") -and $runtime.Contains("pseudoName === 'last-of-type'") -and $runtime.Contains("pseudoName === 'only-of-type'") -and $runtime.Contains("pseudoName === 'nth-last-of-type'")) 'of_type_pseudo_dispatch' 'all standard of-type pseudo branches are evaluated with same-tag positions.' @($runtimePath)
Assert-Contract ($runtime.Contains('legadoMatchesAnyJsoupSelector(predicateNode, argument, documentRoot)') -and $runtime.Contains('legadoSelectWithJsoupRegex(predicateNode, relativeSelector, null)')) 'nested_contexts' ':not and :has inherit the resolved owning element context while preserving the synthetic Document boundary.' @($runtimePath)
Assert-Contract ($runtime.Contains('legadoSelectWithJsoupRegex = function (root, selector, documentRoot)') -and $runtime.Contains('selectionDocumentRoot') -and $runtime.Contains('legadoSelectWithJsoupRegex(root, selectorGroups[groupIndex], selectionDocumentRoot)')) 'selection_context' 'selector groups preserve the document-root context through the ArkWeb pipeline.' @($runtimePath)
Assert-Contract ($runtime.Contains('legadoParseJsoupTextPseudos(selector, selectionDocumentRoot !== null)') -and $runtime.Contains('legadoMatchesJsoupPseudo(node, pseudoParsed.pseudos[pseudoIndex], selectionDocumentRoot)')) 'manual_predicate_handoff' 'the native browser selector is reduced before manual Jsoup predicates are applied.' @($runtimePath)
Assert-Contract ($runtime.Contains('legadoSelectorHasTopLevelCombinatorBefore') -and $runtime.Contains('legadoSelectorCompoundBefore') -and $runtime.Contains("targetScope: isStandardDocumentPseudo ? 'first-compound'" ) -and $runtime.Contains('targetSelector: targetSelector') -and $runtime.Contains("pseudo.targetScope === 'compound'" ) -and $runtime.Contains('predicateNode')) 'compound_target_context' 'manual pseudos retain the owning compound target across first and later selector compounds.' @($runtimePath)
Assert-Contract ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('getStringList')) 'legado_consumer' 'the pinned Legado consumer remains the Jsoup CSS-selection reference.' @($legadoPath)

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
  cases = @($fixture.htmlCases).Count
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_arkweb_document_root_post_fix_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  closeCondition = 'R4 must execute all ArkWeb root/context cases, the affected 243 source set, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
