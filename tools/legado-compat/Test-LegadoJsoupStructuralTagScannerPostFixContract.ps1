param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-structural-tag-scanner-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-structural-tag-scanner-pre-fix-20260810.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-structural-tag-scanner-post-fix-20260810.json'
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
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$RelativePath); $path = Get-RepoPath $RelativePath; if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required file is missing: $RelativePath" }; $bytes = [System.IO.File]::ReadAllBytes($path); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }; return $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$RelativePath); return (Read-StrictText -RelativePath $RelativePath | ConvertFrom-Json -Depth 100) }
function Assert-Contract { param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @()); if (-not $Condition) { throw "243 structural tag-scanner post-fix contract failed: $Detail" }; $script:assertions++; [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) }) }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value); $path = Get-RepoPath $RelativePath; $directory = Split-Path -Parent $path; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporaryPath -Destination $path -Force } finally { if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) } } }

$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$fixture = Read-StrictJson -RelativePath $FixturePath
$failure = Read-StrictJson -RelativePath $FailureWitnessPath
$state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$analyzer = Read-StrictText -RelativePath $analyzerPath
$backupPath = Get-RepoPath 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets.bak_20260810_structural_tag_scanner'

Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'machine baseline remains frozen.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Contract ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and -not [bool]$state.governance.semanticMatchAllowed) 'queue' '243 remains the active static issue and semantic matching stays locked.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Contract ([string]$fixture.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and @($fixture.cases).Count -eq 5) 'fixture' 'structural scanner fixture keeps all five cases.' @($FixturePath)
Assert-Contract ([string]$fixture.cases[0].html -like '*data-note="a > <fake>"*' -and [string]$fixture.cases[2].rule -eq '//section/descendant::*') 'fixture-semantics' 'fixture binds quoted markup-like attributes and wildcard descendant semantics.' @($FixturePath)
Assert-Contract ([string]$failure.status -eq 'failed' -and -not [bool]$failure.semanticMatchAllowed -and @($failure.runtimeActionsPerformed).Count -eq 0) 'failure-preserved' 'pre-fix failure witness remains failed and static-only.' @($FailureWitnessPath)
Assert-Contract ($analyzer.Contains('interface HtmlTagScan') -and $analyzer.Contains('private scanNextHtmlTag(html: string, fromIndex: number): HtmlTagScan | null')) 'shared-scanner' 'structural paths share a typed HTML tag scanner.' @($analyzerPath)
Assert-Contract ($analyzer.Contains('return this.findDirectChildren(searchContent, MAX_ELEMENTS);') -and $analyzer.Contains('private findDirectChildren(html: string, maxElementsHint: number = 0): string[]')) 'legacy-children' 'legacy children uses the bounded direct-child scanner.' @($analyzerPath)
Assert-Contract ($analyzer.Contains('const scan = this.scanNextHtmlTag(fullContent, cursor);') -and $analyzer.Contains('const parentScan = openTags[openTags.length - 1];')) 'parent-axis' 'parent traversal uses forward stack reconstruction instead of backwards raw tag matching.' @($analyzerPath)
Assert-Contract ($analyzer.Contains('const scan = this.scanNextHtmlTag(content, cursor);') -and $analyzer.Contains('if (depth === 0) {') -and $analyzer.Contains('return scan.startIndex;')) 'sibling-axis' 'following-sibling boundary uses quote-aware structural depth.' @($analyzerPath)
Assert-Contract ($analyzer.Contains('private findAllElements(html: string): string[]') -and $analyzer.Contains('cursor = scan.endIndex + 1;') -and $analyzer.Contains('const element = this.extractElement(html, scan.startIndex, scan.tagName);')) 'wildcard-descendants' 'wildcard traversal scans every opening tag without skipping nested descendants.' @($analyzerPath)
Assert-Contract ($analyzer.Contains('new StringElementOccurrence(element, scan.startIndex, scan.tagName)') -and $analyzer.Contains('private findDirectChildOccurrences(html: string): StringElementOccurrence[]')) 'occurrence-mapping' 'standard child pseudo occurrence mapping uses the same scanner.' @($analyzerPath)
Assert-Contract (-not $analyzer.Contains('const tagRegex = /<([a-zA-Z][a-zA-Z0-9]*)[^>]*>/g;') -and -not $analyzer.Contains('const openingMatch = html.substring(index).match(/^<([a-zA-Z][a-zA-Z0-9]*)[^>]*>/);') -and -not $analyzer.Contains('const anyTagMatch = html.substring(i).match(/^<\/?([a-zA-Z][a-zA-Z0-9]*)[^>]*>/);')) 'raw-forward-regexes-removed' 'the audited structural helpers no longer use raw tag regular expressions.' @($analyzerPath)
Assert-Contract (-not $analyzer.Contains("while (tagEnd >= 0 && content[tagEnd] !== '>'")) 'raw-backward-scan-removed' 'parent-start traversal no longer scans for an unqualified > character.' @($analyzerPath)
Assert-Contract (Test-Path -LiteralPath $backupPath -PathType Leaf) 'backup' 'pre-fix analyzer snapshot is preserved beside the source.' @('entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets.bak_20260810_structural_tag_scanner')
Assert-Contract ((Get-FileHash -Algorithm SHA256 -LiteralPath $backupPath).Hash.ToUpperInvariant().Length -eq 64) 'backup-hash' 'pre-fix analyzer snapshot has a SHA-256 digest.' @('entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets.bak_20260810_structural_tag_scanner')

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $analyzerPath)).Hash.ToUpperInvariant()
$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'post_fix_static_contract'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  failureWitnessPath = $FailureWitnessPath
  changedPaths = @($analyzerPath)
  currentHeadHashes = [pscustomobject][ordered]@{ $analyzerPath = $hash }
  affectedCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  selectionPaths = @($fixture.selectionPaths)
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_structural_tag_scanner_static_contract_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  closeCondition = 'R4 must execute all five structural scanner cases, the affected source set, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson -RelativePath $ResultPath -Value $result
$result | ConvertTo-Json -Depth 100
