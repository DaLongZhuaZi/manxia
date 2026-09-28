[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-arkweb-jsoup-regex-contains-composition-context.json',
  [string]$RuntimeSnapshotPath = 'entry/src/main/resources/rawfile/legado_runtime.html.bak_20260810_issue243_regex_contains_composition',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-regex-contains-composition-pre-fix-20260810.json'
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

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Missing file: $Path" }; $bytes = [System.IO.File]::ReadAllBytes($resolved); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }; $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); Read-StrictText $Path | ConvertFrom-Json -Depth 100 }
function Assert-Witness { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "ArkWeb 243 regex/contains failure witness failed: $Message" }; $script:assertions++ }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$runtime = Read-StrictText $RuntimeSnapshotPath
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$legado = Read-StrictText $legadoPath
$packagePath = 'F:/Downloads-E/墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
$packageBytes = [System.IO.File]::ReadAllBytes($packagePath)
$packageHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash.ToUpperInvariant()
$sources = @($strictUtf8.GetString($packageBytes) | ConvertFrom-Json -Depth 100)
$sourceRule = [string]$sources[266].ruleContent.nextContentUrl

Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen machine baseline drifted.'
Assert-Witness ($sources.Count -eq 458 -and $packageHash -eq $baselineHash) 'frozen source package drifted.'
Assert-Witness ([string]$fixture.issueId -eq $issueId -and [string]$fixture.contract -eq 'arkweb_legado_jsoup_regex_contains_composition_context') 'fixture binding changed.'
Assert-Witness (@($fixture.affectedSourceOrdinals).Count -eq 1 -and [int]$fixture.affectedSourceOrdinals[0] -eq 267) 'ordinal 267 is not the sole affected source.'
foreach ($rule in @($fixture.affectedRuleStrings)) { Assert-Witness ($sourceRule -eq [string]$rule) "real ordinal-267 rule is missing: $rule" }
Assert-Witness ($runtime.Contains('if (ancestor.matches && ancestor.matches(pseudo.targetSelector))')) 'pre-fix native ancestor.matches branch is missing.'
Assert-Witness (-not $runtime.Contains('legadoMatchesJsoupSelector(ancestor, pseudo.targetSelector, documentRoot)')) 'the backup already contains the Jsoup-aware owning-compound bridge.'
Assert-Witness ($runtime.Contains('legadoParseRegexAttributeSelectors') -and $runtime.Contains('legadoMatchesJsoupPseudo')) 'pre-fix ArkWeb selector pipeline is missing.'
Assert-Witness ($legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado Element.select handoff is missing.'

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
  affectedSourceSet = [pscustomobject][ordered]@{ sourceOrdinals = @($fixture.affectedSourceOrdinals); ruleStringCount = @($fixture.affectedRuleStrings).Count }
  sourcePaths = @($RuntimeSnapshotPath, $legadoPath)
  runtimeSnapshotPath = $RuntimeSnapshotPath
  runtimeSnapshotSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $RuntimeSnapshotPath)).Hash.ToUpperInvariant()
  failureWitness = [pscustomobject][ordered]@{
    branch = 'legadoParseJsoupTextPseudos -> legadoMatchesJsoupPseudo -> owning compound projection'
    observed = 'ArkWeb identifies the owning compound with native ancestor.matches(targetSelector) even when targetSelector contains Jsoup ~= regex syntax. Native CSS token semantics or a syntax rejection drops the node before :contains is evaluated.'
    expected = 'The owning compound must use the same Jsoup-aware ~= and text-pseudo semantics as the final candidate selection.'
    representativeRules = @($fixture.affectedRuleStrings)
  }
  rootCauseCategory = '规则解析或编译'
  rootCauseDecision = 'ArkWeb target-compound projection uses a different selector evaluator from the final Jsoup-compatible selection path.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_arkweb_regex_contains_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  assertions = $script:assertions
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
