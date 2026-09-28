param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-structural-tag-scanner-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-structural-tag-scanner-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-structural-tag-scanner-post-fix-20260810.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/v2-jsoup-structural-tag-scanner-current-head-audit-20260810.json'
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
function Assert-Audit { param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @()); if (-not $Condition) { throw "243 structural tag-scanner current-head audit failed: $Detail" }; $script:assertions++; [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) }) }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value); $path = Get-RepoPath $RelativePath; $directory = Split-Path -Parent $path; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporaryPath -Destination $path -Force } finally { if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) } } }

$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$fixture = Read-StrictJson -RelativePath $FixturePath
$failure = Read-StrictJson -RelativePath $FailureWitnessPath
$contract = Read-StrictJson -RelativePath $PostFixContractPath
$state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$analyzer = Read-StrictText -RelativePath $analyzerPath

Assert-Audit ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'frozen machine baseline remains unchanged.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Audit ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and -not [bool]$state.governance.semanticMatchAllowed) 'queue' '243 remains the sole active issue and semantic matching is locked.' @('tools/legado-compat/state/full-source-validation-state.json')
$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' })[0]
Assert-Audit ($null -ne $issue -and [string]$issue.status -eq 'verifying') 'issue-status' '243 remains verifying until R4.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Audit ([string]$fixture.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and @($fixture.cases).Count -eq 5) 'fixture' 'all five structural scanner cases remain bound to 243.' @($FixturePath)
Assert-Audit ([string]$failure.status -eq 'failed' -and [string]$contract.status -eq 'passed' -and -not [bool]$failure.semanticMatchAllowed -and -not [bool]$contract.semanticMatchAllowed) 'evidence-status' 'failure witness and post-fix contract preserve static-only status.' @($FailureWitnessPath, $PostFixContractPath)
Assert-Audit ($analyzer.Contains('private scanNextHtmlTag(html: string, fromIndex: number): HtmlTagScan | null') -and $analyzer.Contains('const tagEnd = this.findHtmlTagEnd(html, tagStart);')) 'scanner-consumer' 'the shared scanner resolves tag ends with quote-aware findHtmlTagEnd.' @($analyzerPath)
Assert-Audit ($analyzer.Contains('private findDirectChildren(html: string, maxElementsHint: number = 0): string[]') -and $analyzer.Contains('private findParentEndTag(content: string, startIndex: number): number') -and $analyzer.Contains('private findParentStartTag(content: string, endIndex: number): number')) 'structural-helpers' 'all audited structural helpers remain present under the new contract.' @($analyzerPath)
Assert-Audit (-not $analyzer.Contains('const tagRegex = /<([a-zA-Z][a-zA-Z0-9]*)[^>]*>/g;') -and -not $analyzer.Contains('const openingMatch = html.substring(index).match(/^<([a-zA-Z][a-zA-Z0-9]*)[^>]*>/);') -and -not $analyzer.Contains('const anyTagMatch = html.substring(i).match(/^<\/?([a-zA-Z][a-zA-Z0-9]*)[^>]*>/);')) 'raw-regex-closure' 'no audited raw structural tag regular expression remains.' @($analyzerPath)
Assert-Audit (-not $analyzer.Contains("while (tagEnd >= 0 && content[tagEnd] !== '>'")) 'backward-scan-closure' 'no quote-blind backwards tag-end scan remains.' @($analyzerPath)
Assert-Audit ($analyzer.Contains('const parentScan = openTags[openTags.length - 1];') -and $analyzer.Contains('openTags.splice(index, 1);')) 'parent-stack-closure' 'parent lookup reconstructs open-tag stack in document order.' @($analyzerPath)
Assert-Audit ($analyzer.Contains('if (depth === 0) {') -and $analyzer.Contains('return scan.startIndex;') -and $analyzer.Contains('scan.isSelfClosing')) 'sibling-stack-closure' 'sibling boundary tracks closing and self-closing tags through the shared scanner.' @($analyzerPath)
Assert-Audit ($analyzer.Contains('cursor = scan.endIndex + 1;') -and $analyzer.Contains('new StringElementOccurrence(element, scan.startIndex, scan.tagName)')) 'wildcard-occurrence-closure' 'wildcard and child-pseudo occurrence paths advance by scanner boundaries.' @($analyzerPath)
Assert-Audit ((& git -C (Get-RepoPath 'legado') rev-parse HEAD 2>$null | Out-String).Trim() -eq $legadoCommit) 'legado-commit' 'Legado checkout remains at the pinned reference commit.' @('legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt')

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $analyzerPath)).Hash.ToUpperInvariant()
$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'current_head_static_audit'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
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
  verificationPolicy = 'r3_243_structural_tag_scanner_current_head_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  nextGate = 'Register the structural tag-scanner source fix and keep 243 verifying until R4 runtime and Legado differential gates.'
}
Write-AtomicJson -RelativePath $ResultPath -Value $result
$result | ConvertTo-Json -Depth 100
