[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-arkweb-jsoup-empty-compound-pseudo-context.json',
  [string]$RuntimeSnapshotPath = 'entry/src/main/resources/rawfile/legado_runtime.html.bak_20260810_issue243_empty_compound',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-empty-compound-pre-fix-20260810.json'
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
function Assert-Witness { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "ArkWeb 243 empty compound failure witness failed: $Message" }; $script:assertions++ }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$runtime = Read-StrictText $RuntimeSnapshotPath
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$legado = Read-StrictText $legadoPath
$sourcePath = 'F:/Downloads-E/墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePath).Hash.ToUpperInvariant()
$sources = @($strictUtf8.GetString([System.IO.File]::ReadAllBytes($sourcePath)) | ConvertFrom-Json -Depth 100)
$sourceText = ($sources[356] | ConvertTo-Json -Depth 100 -Compress) + ($sources[401] | ConvertTo-Json -Depth 100 -Compress)

Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen machine baseline drifted.'
Assert-Witness ($sourceHash -eq $baselineHash -and $sources.Count -eq 458) 'frozen source package drifted.'
Assert-Witness ([string]$fixture.issueId -eq $issueId -and [string]$fixture.contract -eq 'arkweb_legado_jsoup_empty_compound_pseudo_context' -and @($fixture.cases).Count -eq 6) 'empty-compound fixture binding or case count changed.'
Assert-Witness (@($fixture.affectedSourceOrdinals).Count -eq 2 -and @($fixture.affectedSourceOrdinals) -contains 357 -and @($fixture.affectedSourceOrdinals) -contains 402) 'affected source ordinals are not bound to the frozen package.'
foreach ($rule in @($fixture.affectedRuleStrings)) { Assert-Witness ($sourceText.Contains([string]$rule)) ("representative source rule is missing: $rule") }
Assert-Witness ($runtime.Contains('var targetSelector = legadoSelectorCompoundBefore(normalized, normalized.length);')) 'pre-fix parser does not expose the empty-compound target calculation.'
Assert-Witness (-not $runtime.Contains("if (!targetSelector) targetSelector = '*';")) 'pre-fix parser already substitutes a universal target.'
Assert-Witness (-not $runtime.Contains('normalized += targetSelector;')) 'pre-fix selector compiler does not restore a universal simple selector.'
Assert-Witness ($runtime.Contains('legadoSelectWithJsoupRegex(selectionRoot, selector, documentRoot)')) 'pre-fix browser selection path is missing.'
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
    branch = 'legadoParseJsoupTextPseudos -> normalized selector -> querySelectorAll'
    observed = 'When a manual pseudo is the only simple selector before or after a combinator, removing it leaves an invalid selector such as >a, head> or p>. Consecutive or sibling-joined pseudo-only compounds produce the same invalid browser selector instead of preserving universal element targets.'
    expected = 'Replace a pseudo-only compound with * before browser selection and use * as the owning compound target for predicate evaluation.'
    representativeRules = @($fixture.affectedRuleStrings)
  }
  rootCauseCategory = '规则解析或编译'
  rootCauseDecision = 'Jsoup accepts pseudo-only compounds as element selectors, while the ArkWeb reduction removes the pseudo token without preserving the compound. The resulting trailing combinator is rejected by querySelectorAll.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_arkweb_empty_compound_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  assertions = $script:assertions
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
