[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-empty-pseudo-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-empty-pseudo-pre-fix-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-empty-pseudo-post-fix-20260810.json'
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
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$elementPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$runtimePath = 'entry/src/main/resources/rawfile/legado_runtime.html'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

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
function Assert-Contract {
  param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @())
  if (-not $Condition) { throw "243 empty pseudo post-fix contract failed: $Detail" }
  $script:assertions++
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) })
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

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$analyzer = Read-StrictText $analyzerPath
$element = Read-StrictText $elementPath
$runtime = Read-StrictText $runtimePath
$legado = Read-StrictText $legadoPath
$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId })[0]

Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'frozen machine baseline is unchanged.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Contract ([string]$state.governance.activeIssueId -eq $issueId -and [string]$state.governance.status -eq 'running' -and -not [bool]$state.governance.semanticMatchAllowed) 'queue' '243 remains active and semantic matching remains disabled.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Contract ($null -ne $issue -and [string]$issue.status -eq 'verifying') 'issue' '243 remains verifying until R4.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Contract ([string]$fixture.contract -eq 'legado_jsoup_empty_pseudo_context' -and @($fixture.cases).Count -eq 6) 'fixture' 'six :empty semantic cases remain bound to 243.' @($FixturePath)
Assert-Contract ([string]$failure.status -eq 'failed' -and @($failure.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed) 'failure_witness' 'the pre-fix witness remains failed and static-only.' @($FailureWitnessPath)
Assert-Contract ($analyzer.Contains("pseudo.name === 'empty'") -and $analyzer.Contains('matchesStringEmptyPseudo') -and $analyzer.Contains("rawTag.startsWith('<!--')")) 'string_fallback' 'large-document fallback implements Jsoup blank-text/comment filtering for :empty.' @($analyzerPath)
Assert-Contract ($element.Contains('matchesJsoupEmptyPseudo') -and $element.Contains('(child as TextNode).isWhitespace') -and $element.Contains('NodeType.COMMENT_NODE')) 'dom_matcher' 'DOM Matcher implements Jsoup empty-node classification.' @($elementPath)
Assert-Contract ($runtime.Contains("name === 'empty'") -and $runtime.Contains("pseudo.name === 'empty'") -and $runtime.Contains('childNodeType === 8') -and $runtime.Contains('childNodeType === 10')) 'arkweb' 'ArkWeb manually evaluates :empty instead of relying on divergent native CSS behavior.' @($runtimePath)
Assert-Contract ($legado.Contains('temp.select(ruleStr)')) 'legado_consumer' 'pinned Legado selector handoff remains the reference.' @($legadoPath)

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'post_fix_static_contract'
  issueId = $issueId
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  failureWitnessPath = $FailureWitnessPath
  changedPaths = @($runtimePath, $elementPath, $analyzerPath)
  affectedSourceOrdinals = @()
  affectedRuleStringCount = 0
  cases = @($fixture.cases).Count
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_empty_pseudo_post_fix_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  closeCondition = 'R4 must execute all six :empty fixture cases, the existing 243 selector equivalence classes, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
