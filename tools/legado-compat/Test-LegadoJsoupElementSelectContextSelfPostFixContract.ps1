[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-element-select-context-self.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-element-select-context-self-pre-fix-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-element-select-context-self-post-fix-20260810.json'
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

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }; return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "required file is missing: $Path" }; $bytes = [System.IO.File]::ReadAllBytes($resolved); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }; return $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100) }
function Assert-Contract { param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @()); if (-not $Condition) { throw "243 Element.select context-self post-fix contract failed: $Detail" }; $script:assertions++; [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) }) }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$elementPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$bridgePath = 'entry/src/main/ets/libs/htmlparser/LegadoHtmlBridge.ets'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$element = Read-StrictText $elementPath
$bridge = Read-StrictText $bridgePath
$legado = Read-StrictText $legadoPath
$sourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
$packageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePackagePath).Hash.ToUpperInvariant()
$sources = @($strictUtf8.GetString([System.IO.File]::ReadAllBytes($sourcePackagePath)) | ConvertFrom-Json -Depth 100)
$sourceText = ($sources[157] | ConvertTo-Json -Depth 100 -Compress) + ($sources[227] | ConvertTo-Json -Depth 100 -Compress) + ($sources[375] | ConvertTo-Json -Depth 100 -Compress)
$queryStart = $element.IndexOf('  querySelectorAll(selector: string): HTMLElement[] {')
$queryEnd = $element.IndexOf("`r`n  /**", $queryStart + 1)
if ($queryEnd -lt 0) { $queryEnd = $element.IndexOf("`n  /**", $queryStart + 1) }
$queryBody = if ($queryStart -ge 0 -and $queryEnd -gt $queryStart) { $element.Substring($queryStart, $queryEnd - $queryStart) } else { '' }

Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit -and $packageHash -eq $baselineHash -and $sources.Count -eq 458) 'baseline' 'machine state and frozen package remain bound to the same baseline.' @('tools/legado-compat/state/full-source-validation-state.json', $FixturePath)
Assert-Contract ([string]$fixture.issueId -eq $issueId -and [string]$fixture.contract -eq 'legado_jsoup_element_select_context_self' -and @($fixture.cases).Count -eq 4) 'fixture_shape' 'the context-self fixture retains the three Element cases and the synthetic Document-root guard.' @($FixturePath)
Assert-Contract ([string]$failure.status -eq 'failed' -and @($failure.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed) 'failure_witness_preserved' 'the pre-fix witness remains failed and static-only.' @($FailureWitnessPath)
foreach ($rule in @($fixture.representativeSourceSet.ruleStrings)) { Assert-Contract ($sourceText.Contains([string]$rule)) 'representative_source_binding' "the frozen representative rule remains present: $rule" @($FixturePath) }
Assert-Contract ($queryBody.Contains('return this.selectAll(selector, false);')) 'dom_query_selector_contract' 'standard querySelectorAll remains a descendant-only API.' @($elementPath)
Assert-Contract ($element.Contains('  select(selector: string): HTMLElement[] {') -and $element.Contains('return this.selectAll(selector, true);') -and $element.Contains('private selectAll(selector: string, includeSelf: boolean): HTMLElement[]')) 'element_select_entry' 'HTMLElement exposes an explicit Jsoup-style selection entry instead of changing the DOM API contract.' @($elementPath)
Assert-Contract ($element.Contains("const descendants = this.getElementsByTagName('*');") -and $element.Contains('if (!includeSelf || this.isSyntheticDocumentRoot()) {') -and $element.Contains('const results: HTMLElement[] = [this];')) 'context_candidate_order' 'Element.select places a normal context element before its descendants, while preserving document order.' @($elementPath)
Assert-Contract ($element.Contains("return this.tagName === 'root' && this.parentNode === null;") -and $element.Contains('private isWithinSelectionScope(element: HTMLElement, includeSelf: boolean): boolean') -and $element.Contains('if (this.isWithinSelectionScope(m, includeSelf)) {')) 'document_boundary_and_scope' 'synthetic Document roots are excluded and combinator results cannot escape the selected subtree.' @($elementPath)
Assert-Contract ($element.Contains('private matchSelectorChain(chain: SelectorNode[], startIndex: number, includeSelf: boolean): HTMLElement[]') -and $element.Contains('const descendants = this.getSelectionDocumentOrder(includeSelf);')) 'matcher_context_propagation' 'the DOM matcher receives the include-self decision at its first selector segment.' @($elementPath)
Assert-Contract ($bridge.Contains('const elements = this.root.select(selector);') -and $bridge.Contains('return this.root.select(selector);') -and $bridge.Contains('results = context.select(`.${className}`);') -and $bridge.Contains('const elem = context.select(`#${idName}`)[0];') -and $bridge.Contains('results = context.select(tagName);') -and $bridge.Contains('results = context.select(selector);')) 'bridge_consumer_routing' 'Legado bridge routes CSS, class, id and tag chain segments through the Jsoup-style entry.' @($bridgePath)
Assert-Contract ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))') -and $legado.Contains('temp.getElementsByClass(rules[1])') -and $legado.Contains('temp.getElementsByTag(rules[1])') -and $legado.Contains('Collector.collect(Evaluator.Id(rules[1]), temp)')) 'legado_reference' 'the pinned Legado implementation remains the source of the Element-context contract.' @($legadoPath)

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'post_fix_static_contract'
  issueId = $issueId
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  failureWitnessPath = $FailureWitnessPath
  changedPaths = @($elementPath, $bridgePath)
  affectedSourceSet = $fixture.representativeSourceSet
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_element_select_context_self_post_fix_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  closeCondition = 'R4 must execute all four context-self cases, the ordinal 158/228/376 context-prefix consumers, the affected 243 selector set, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Depth 100
