[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-empty-pseudo-context.json',
  [string]$SourcePackagePath = 'F:/Downloads-E/墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-empty-pseudo-pre-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$elementPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$runtimePath = 'entry/src/main/resources/rawfile/legado_runtime.html'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$analyzerBackupPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets.bak_20260810_issue243_empty_pseudo'
$elementBackupPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets.bak_20260810_issue243_empty_pseudo'
$runtimeBackupPath = 'entry/src/main/resources/rawfile/legado_runtime.html.bak_20260810_issue243_empty_pseudo'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
}
function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  $resolved = Get-RepoPath $Path
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Missing file: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($resolved)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return $strictUtf8.GetString($bytes)
}
function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Read-StrictText $Path | ConvertFrom-Json -Depth 100)
}
function Get-Sha256 {
  param([Parameter(Mandatory = $true)][byte[]]$Bytes)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try { return ([System.BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToUpperInvariant() } finally { $sha.Dispose() }
}
function Assert-Witness {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "243 empty pseudo failure witness failed: $Message" }
}
function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $resolved = Get-RepoPath $Path
  $directory = Split-Path -Parent $resolved
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force }
  finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } }
}

$fixture = Read-StrictJson $FixturePath
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$sourcePath = Get-RepoPath $SourcePackagePath
$sourceBytes = [System.IO.File]::ReadAllBytes($sourcePath)
$package = $strictUtf8.GetString($sourceBytes) | ConvertFrom-Json -Depth 100
$sourceText = $strictUtf8.GetString($sourceBytes)
$emptyRuleStringCount = ([regex]::Matches($sourceText, '(?i):empty(?=\s*[@>),\]:]|$)')).Count
$analyzer = Read-StrictText $analyzerBackupPath
$element = Read-StrictText $elementBackupPath
$runtime = Read-StrictText $runtimeBackupPath
$legado = Read-StrictText $legadoPath

Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen machine baseline drifted.'
Assert-Witness (@($package).Count -eq 458 -and (Get-Sha256 $sourceBytes) -eq $baselineHash) 'pinned source package count or hash drifted.'
Assert-Witness ([string]$fixture.issueId -eq $issueId -and [string]$fixture.contract -eq 'legado_jsoup_empty_pseudo_context' -and @($fixture.cases).Count -eq 6) 'fixture binding or case count changed.'
Assert-Witness ($emptyRuleStringCount -eq 0) 'the frozen package unexpectedly contains an :empty rule occurrence.'
Assert-Witness (-not $analyzer.Contains("pseudo.name === 'empty'")) 'large-document string fallback already contains an :empty branch.'
Assert-Witness ($element.Contains("pseudo.name === 'empty'") -and $element.Contains('elem.childNodes.length === 0')) 'DOM pre-fix :empty branch is not the observed child-node-only implementation.'
Assert-Witness (-not $runtime.Contains("pseudo.name === 'empty'") -and -not $runtime.Contains("name === 'empty'")) 'ArkWeb runtime already contains an explicit :empty manual branch.'
Assert-Witness ($legado.Contains('temp.select(ruleStr)')) 'pinned Legado selector handoff is missing.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'failure_witness'
  issueId = $issueId
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  failureClass = 'v2_empty_pseudo_semantics_diverge_across_arkweb_dom_and_large_document_string_consumers'
  fixturePath = $FixturePath
  sourcePackagePath = 'redacted_pinned_package'
  sourcePackageHash = (Get-Sha256 $sourceBytes)
  sourcePackageScan = [pscustomobject][ordered]@{ scannedSourceCount = @($package).Count; emptyRuleStringCount = $emptyRuleStringCount; affectedSourceOrdinals = @() }
  sourcePaths = @($analyzerPath, $elementPath, $runtimePath, $legadoPath)
  preFixBackupPaths = @($analyzerBackupPath, $elementBackupPath, $runtimeBackupPath)
  failureWitness = [pscustomobject][ordered]@{
    branch = 'large-document string fallback, DOM Matcher and ArkWeb manual pseudo projection'
    path = 'LegadoRuleAnalyzer.filterElementsByPseudoClasses; HTMLElement.matchesPseudoClass; legadoParseJsoupTextPseudos/legadoMatchesJsoupPseudo'
    observed = 'The string fallback fails closed on :empty, DOM only accepts zero childNodes (diverging for blank text and ignored comments), and ArkWeb leaves :empty to native CSS instead of applying Jsoup IsEmpty semantics.'
    expected = 'Jsoup Evaluator.IsEmpty accepts blank TextNode content and ignores Comment, XmlDeclaration and DocumentType nodes, while rejecting element children.'
  }
  rootCauseDecision = 'The pinned Legado path delegates to Jsoup 1.16.2 Evaluator.IsEmpty. V2 has no shared Jsoup-compatible :empty contract across its three selector consumers; the frozen package has zero occurrences, so this is a general compatibility gap rather than a source-specific failure.'
  reference = [pscustomobject][ordered]@{ dependency = 'org.jsoup:jsoup:1.16.2'; evaluator = 'org.jsoup.select.Evaluator.IsEmpty'; sourceUrl = 'https://raw.githubusercontent.com/jhy/jsoup/jsoup-1.16.2/src/main/java/org/jsoup/select/Evaluator.java' }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_empty_pseudo_failure_witness_static_only;source_fix_pending;runtime_build_device_and_legado_diff_deferred_to_R4'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
