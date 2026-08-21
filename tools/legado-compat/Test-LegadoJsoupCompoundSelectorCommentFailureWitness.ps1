param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-compound-selector-comment-context.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-compound-selector-comment-pre-fix-20260810.json'
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
function Assert-Witness { param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @()); if (-not $Condition) { throw "243 compound selector comment failure witness failed: $Detail" }; $script:assertions++; [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) }) }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value); $path = Get-RepoPath $RelativePath; $directory = Split-Path -Parent $path; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporaryPath -Destination $path -Force } finally { if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) } } }

$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$fixture = Read-StrictJson -RelativePath $FixturePath
$state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$analyzer = Read-StrictText -RelativePath $analyzerPath

Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'frozen machine baseline remains bound.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Witness ([string]$state.governance.activeIssueId -eq $issueId -and [string]$state.governance.activeTaskId -eq 'COMPAT-006' -and -not [bool]$state.governance.semanticMatchAllowed) 'queue' '243 remains active and semantic matching stays locked.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Witness ([string]$fixture.issueId -eq $issueId -and @($fixture.cases).Count -eq 1) 'fixture' 'the compound comment case remains bound to 243.' @($FixturePath)
Assert-Witness ($analyzer.Contains("const tagStartIndex = html.indexOf('<', searchStart);") -and $analyzer.Contains('searchStart = tagStartIndex + 1;')) 'raw-compound-tag-search' 'compound selector discovery can re-enter comment content after a special-tag branch.' @($analyzerPath)

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'pre_fix_static_failure_witness'
  issueId = $issueId
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  changedPaths = @($analyzerPath)
  affectedCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  selectionPaths = @($fixture.selectionPaths)
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  observed = 'The compound selector fallback resumes one character after a comment marker, so a markup-like tag inside the comment can be interpreted as a candidate element.'
  expected = 'Consume special/comment nodes through the shared quote-aware scanner and resume after their complete boundary.'
  legadoReference = 'Pinned AnalyzeByJSoup evaluates parsed Jsoup elements; comment nodes are not selected by CSS.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_static_failure_witness_only;no_runtime_build_device_or_legado_execution'
  nextGate = 'Replace the compound selector raw tag loop with scanNextHtmlTag, then add post-fix contract and current-head audit.'
}
Write-AtomicJson -RelativePath $ResultPath -Value $result
$result | ConvertTo-Json -Depth 100
