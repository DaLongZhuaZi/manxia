[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-dom-document-root-child-pseudo.json',
  [string]$SourcePackagePath = 'F:/Downloads-E/墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-dom-document-root-child-pseudo-pre-fix-20260810.json'
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
$elementPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$parserPath = 'entry/src/main/ets/libs/htmlparser/Parser.ets'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$script:assertions = 0

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
}
function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  $resolved = Get-RepoPath $Path
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Missing text: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($resolved)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return $strictUtf8.GetString($bytes)
}
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText $Path | ConvertFrom-Json -Depth 100) }
function Assert-Witness { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 DOM document-root pseudo failure witness failed: $Message" }; $script:assertions++ }
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
$element = Read-StrictText $elementPath
$parser = Read-StrictText $parserPath
$legado = Read-StrictText $legadoPath
$packageBytes = [System.IO.File]::ReadAllBytes((Get-RepoPath $SourcePackagePath))
$packageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $SourcePackagePath)).Hash.ToUpperInvariant()
$package = @($strictUtf8.GetString($packageBytes) | ConvertFrom-Json -Depth 100)

Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen machine baseline drifted.'
Assert-Witness ($package.Count -eq 458 -and $packageHash -eq $baselineHash) 'frozen source package drifted.'
Assert-Witness ([string]$fixture.issueId -eq $issueId -and [string]$fixture.contract -eq 'legado_jsoup_dom_document_root_child_pseudo' -and @($fixture.htmlCases).Count -eq 3) 'fixture binding or case count changed.'
foreach ($rule in @($fixture.representativeRules)) {
  $found = $false
  foreach ($source in $package) { if (($source | ConvertTo-Json -Depth 100 -Compress).Contains([string]$rule)) { $found = $true; break } }
  Assert-Witness $found "representative rule is missing: $rule"
}
Assert-Witness ($parser.Contains("new HTMLElement('root', null, '', null, rootRange)")) 'parser synthetic root construction is missing.'
$matchesStart = $element.IndexOf('private matchesPseudoClass(')
$matchesEnd = $element.IndexOf('private selectorContainsInvalidRegexAttribute(', $matchesStart)
Assert-Witness ($matchesStart -ge 0 -and $matchesEnd -gt $matchesStart) 'DOM pseudo matcher boundary is not stable.'
$matchesBody = $element.Substring($matchesStart, $matchesEnd - $matchesStart)
Assert-Witness ($matchesBody.Contains("pseudo.name === 'first-child'") -and $matchesBody.Contains("pseudo.name === 'nth-of-type'")) 'DOM child/of-type branches are missing.'
Assert-Witness (-not $matchesBody.Contains("parent.tagName === 'root'")) 'pre-fix DOM matcher already contains a synthetic Document guard.'
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
  sourcePackageHash = $packageHash
  affectedSourceSet = [pscustomobject][ordered]@{ sourceOrdinals = @($fixture.affectedSourceOrdinals); ruleStringCount = @($fixture.representativeRules).Count }
  sourcePaths = @($elementPath, $parserPath, $legadoPath)
  failureWitness = [pscustomobject][ordered]@{
    branch = 'HTMLElement.matchesPseudoClass child and of-type pseudo branches'
    path = 'Parser.parse -> synthetic HTMLElement(root) -> HTMLElement.querySelectorAll -> matchesPseudoClass'
    observed = 'The DOM parser uses a detached root HTMLElement, but the pseudo matcher treats that root as a normal element parent. Top-level fragment nodes can therefore match child/of-type pseudos that Jsoup rejects under Document.'
    expected = 'A synthetic root wrapper is semantically a Document for child and of-type pseudos; only real element parents may satisfy those predicates.'
  }
  rootCauseCategory = '规则解析或编译'
  rootCauseDecision = 'DOM and Jsoup use different document-root models. The V2 parser must preserve its internal root wrapper while explicitly applying Jsoup Document boundary semantics in the matcher.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_dom_document_root_child_pseudo_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred'
  assertions = $script:assertions
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
