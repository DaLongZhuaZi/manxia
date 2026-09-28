[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-element-select-context-self.json',
  [string]$ElementSnapshotPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets.bak_20260810_issue243_element_select_context',
  [string]$BridgeSnapshotPath = 'entry/src/main/ets/libs/htmlparser/LegadoHtmlBridge.ets.bak_20260810_issue243_element_select_context',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-element-select-context-self-pre-fix-20260810.json'
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

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }; return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "required file is missing: $Path" }; $bytes = [System.IO.File]::ReadAllBytes($resolved); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }; return $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100) }
function Assert-Witness { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 Element.select context-self failure witness failed: $Message" }; $script:assertions++ }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$elementSnapshot = Read-StrictText $ElementSnapshotPath
$bridgeSnapshot = Read-StrictText $BridgeSnapshotPath
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$legado = Read-StrictText $legadoPath
$sourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
$packageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePackagePath).Hash.ToUpperInvariant()
$sources = @($strictUtf8.GetString([System.IO.File]::ReadAllBytes($sourcePackagePath)) | ConvertFrom-Json -Depth 100)
$sourceText = ($sources[157] | ConvertTo-Json -Depth 100 -Compress) + ($sources[227] | ConvertTo-Json -Depth 100 -Compress) + ($sources[375] | ConvertTo-Json -Depth 100 -Compress)
$queryStart = $elementSnapshot.IndexOf('  querySelectorAll(selector: string): HTMLElement[] {')
$queryEnd = $elementSnapshot.IndexOf("`r`n  /**", $queryStart + 1)
if ($queryEnd -lt 0) { $queryEnd = $elementSnapshot.IndexOf("`n  /**", $queryStart + 1) }
$queryBody = if ($queryStart -ge 0 -and $queryEnd -gt $queryStart) { $elementSnapshot.Substring($queryStart, $queryEnd - $queryStart) } else { '' }
$matchStart = $elementSnapshot.IndexOf('  private matchSelectorChain(chain: SelectorNode[], startIndex: number): HTMLElement[] {')
$matchEnd = $elementSnapshot.IndexOf("`r`n  /**", $matchStart + 1)
if ($matchEnd -lt 0) { $matchEnd = $elementSnapshot.IndexOf("`n  /**", $matchStart + 1) }
$matchBody = if ($matchStart -ge 0 -and $matchEnd -gt $matchStart) { $elementSnapshot.Substring($matchStart, $matchEnd - $matchStart) } else { '' }

Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline drifted.'
Assert-Witness ($packageHash -eq $baselineHash -and $sources.Count -eq 458) 'frozen source package drifted.'
Assert-Witness ([string]$fixture.issueId -eq $issueId -and [string]$fixture.contract -eq 'legado_jsoup_element_select_context_self' -and @($fixture.cases).Count -eq 4) 'fixture binding or case count changed.'
Assert-Witness (@($fixture.representativeSourceSet.sourceOrdinals).Count -eq 3 -and @($fixture.representativeSourceSet.sourceOrdinals) -contains 158 -and @($fixture.representativeSourceSet.sourceOrdinals) -contains 228 -and @($fixture.representativeSourceSet.sourceOrdinals) -contains 376) 'representative source ordinal binding changed.'
foreach ($rule in @($fixture.representativeSourceSet.ruleStrings)) { Assert-Witness ($sourceText.Contains([string]$rule)) ("frozen representative rule is missing: $rule") }
Assert-Witness ($queryBody.Contains('for (const chain of selectorGroups)') -and $matchBody.Contains("const descendants = this.getElementsByTagName('*');") -and -not $elementSnapshot.Contains('getSelectionDocumentOrder') -and -not $elementSnapshot.Contains('  select(selector: string): HTMLElement[] {')) 'pre-fix DOM matcher does not show descendant-only selection.'
Assert-Witness ($bridgeSnapshot.Contains('results = context.querySelectorAll(`.${className}`);') -and $bridgeSnapshot.Contains('const elem = context.querySelector(`#${idName}`);') -and $bridgeSnapshot.Contains('results = context.querySelectorAll(tagName);') -and $bridgeSnapshot.Contains('results = context.querySelectorAll(selector);')) 'pre-fix bridge does not route chain segments through descendant-only querySelectorAll.'
Assert-Witness ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))') -and $legado.Contains('temp.getElementsByClass(rules[1])') -and $legado.Contains('temp.getElementsByTag(rules[1])') -and $legado.Contains('Collector.collect(Evaluator.Id(rules[1]), temp)')) 'pinned Legado Element.select and ElementsSingle semantics are missing.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'failure_witness'
  issueId = $issueId
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  sourcePackagePath = 'redacted_pinned_package'
  sourcePackageHash = $packageHash
  sourcePaths = @($ElementSnapshotPath, $BridgeSnapshotPath, $legadoPath)
  snapshotHashes = [pscustomobject][ordered]@{
    element = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $ElementSnapshotPath)).Hash.ToUpperInvariant()
    bridge = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $BridgeSnapshotPath)).Hash.ToUpperInvariant()
  }
  affectedSourceSet = $fixture.representativeSourceSet
  failureClass = 'v2_legado_chain_context_omits_current_element'
  failureWitness = [pscustomobject][ordered]@{
    branch = 'LegadoHtmlBridge.parseChainRuleToElements -> findElementsInContext -> HTMLElement.querySelectorAll'
    observed = 'The V2 DOM matcher starts every selection at getElementsByTagName("*"), which excludes the current context. The bridge also sent class, id, tag and generic chain segments through that descendant-only API.'
    expected = 'Legado uses Jsoup Element.select and Element collector APIs, which evaluate the supplied context Element itself before its descendants.'
    documentBoundary = 'The parser synthetic root must remain excluded because it represents a Document boundary, not an HTML element.'
  }
  rootCauseCategory = '规则解析或编译'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_element_select_context_self_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  assertions = $script:assertions
}
Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Depth 100
