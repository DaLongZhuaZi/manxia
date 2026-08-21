[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-arkweb-jsoup-dom-document-root-child-pseudo.json',
  [string]$RuntimeSnapshotPath = 'entry/src/main/resources/rawfile/legado_runtime.html.bak_20260809_issue033',
  [string]$SourcePackagePath = 'F:/Downloads-E/墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-arkweb-jsoup-dom-document-root-child-pseudo-pre-fix-20260810.json'
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
$runtimePath = Join-Path $RepositoryRoot ($RuntimeSnapshotPath.Replace('/', '\'))
$legadoPath = Join-Path $RepositoryRoot 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$statePath = Join-Path $RepositoryRoot 'tools/legado-compat/state/full-source-validation-state.json'
$fixtureFullPath = Join-Path $RepositoryRoot ($FixturePath.Replace('/', '\'))
$sourceFullPath = [System.IO.Path]::GetFullPath($SourcePackagePath)
$outputFullPath = Join-Path $RepositoryRoot ($OutputPath.Replace('/', '\'))
$script:assertions = 0

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return $strictUtf8.GetString($bytes)
}
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText $Path | ConvertFrom-Json -Depth 100) }
function Assert-Witness { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "ArkWeb 243 failure witness failed: $Message" }; $script:assertions++ }
function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporary = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $Path -Force }
  finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } }
}

$state = Read-StrictJson $statePath
$fixture = Read-StrictJson $fixtureFullPath
$runtime = Read-StrictText $runtimePath
$legado = Read-StrictText $legadoPath
$sourceBytes = [System.IO.File]::ReadAllBytes($sourceFullPath)
$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceFullPath).Hash.ToUpperInvariant()
$sources = @($strictUtf8.GetString($sourceBytes) | ConvertFrom-Json -Depth 100)

Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen machine baseline drifted.'
Assert-Witness ($sourceHash -eq $baselineHash -and $sources.Count -eq 458) 'frozen source package drifted.'
Assert-Witness ([string]$fixture.issueId -eq $issueId -and @($fixture.htmlCases).Count -eq 10) 'ArkWeb fixture binding or case count changed.'
Assert-Witness ($runtime.Contains("var holder = document.createElement('div');") -and $runtime.Contains("holder.innerHTML = String(content || '');")) 'ArkWeb holder construction is missing.'
Assert-Witness ($runtime.Contains('root.querySelectorAll(browserSelector)') -and $runtime.Contains('legadoSelectWithJsoupRegex')) 'ArkWeb native selector path is missing.'
Assert-Witness ($runtime.Contains('var legadoParseJsoupTextPseudos = function (selector)') -and -not $runtime.Contains('legadoStandardDocumentPseudoNames')) 'pre-fix runtime has no standard pseudo extraction set.'
Assert-Witness (-not $runtime.Contains("data-legado-document-root")) 'pre-fix runtime already marks the synthetic Document root.'
Assert-Witness (-not $runtime.Contains('documentRoot)') -and -not $runtime.Contains('documentRoot, pseudo')) 'pre-fix matcher has no document-root context propagation.'
Assert-Witness ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('getStringList')) 'pinned Legado Jsoup selector consumer is missing.'

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
  affectedSourceSet = [pscustomobject][ordered]@{ sourceOrdinals = @($fixture.affectedSourceOrdinals); ruleStringCount = @($fixture.representativeRules).Count }
  sourcePaths = @($RuntimeSnapshotPath, 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt')
  runtimeSnapshotPath = $RuntimeSnapshotPath
  runtimeSnapshotSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $runtimePath).Hash.ToUpperInvariant()
  failureWitness = [pscustomobject][ordered]@{
    branch = 'legadoGetStringListSingle holder -> legadoSelectWithJsoupRegex -> native querySelectorAll'
    path = 'ArkWeb holder div -> browser selector engine'
    observed = 'The ArkWeb runtime parses response fragments under a detached div and lets querySelectorAll evaluate child/of-type pseudos as if that div were a normal element parent. Top-level fragment nodes therefore diverge from Jsoup Document semantics.'
    expected = 'The holder must be marked as a synthetic Document; child/of-type pseudos on direct holder children must fail closed, while nested real-element and :has relative contexts retain normal positions.'
  }
  rootCauseCategory = '规则解析或编译'
  rootCauseDecision = 'ArkWeb uses a synthetic element wrapper for HTML fragments, but the pinned Legado consumer delegates to Jsoup with a Document boundary. The wrapper identity and pseudo context must be explicit in the ArkWeb selector pipeline.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_arkweb_document_root_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  assertions = $script:assertions
}
Write-AtomicJson $outputFullPath $result
$result | ConvertTo-Json -Depth 100
