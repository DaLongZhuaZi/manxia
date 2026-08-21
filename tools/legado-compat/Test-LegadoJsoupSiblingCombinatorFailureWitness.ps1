[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-sibling-combinator-context.json',
  [string]$AnalyzerSnapshotPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets.bak_20260810_sibling_combinator',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-sibling-combinator-pre-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$RelativePath); return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$RelativePath); $path = Get-RepoPath $RelativePath; if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing text: $RelativePath" }; return $strictUtf8.GetString([System.IO.File]::ReadAllBytes($path)) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$RelativePath); return (Read-StrictText $RelativePath | ConvertFrom-Json -Depth 100) }
function Assert-Witness { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 sibling combinator failure witness failed: $Message" } }
function Get-TextHash { param([Parameter(Mandatory = $true)][string]$Text); $sha = [System.Security.Cryptography.SHA256]::Create(); try { return ([System.BitConverter]::ToString($sha.ComputeHash($strictUtf8.GetBytes($Text)))).Replace('-', '').ToUpperInvariant() } finally { $sha.Dispose() } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value); $path = Get-RepoPath $RelativePath; $directory = Split-Path -Parent $path; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temp = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temp -Destination $path -Force } finally { if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) } } }

$fixture = Read-StrictJson $FixturePath
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$analyzer = Read-StrictText $AnalyzerSnapshotPath
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$legado = Read-StrictText $legadoPath
Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$state.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'frozen baseline drifted.'
Assert-Witness ([string]$fixture.contract -eq 'legado_jsoup_sibling_combinator_context' -and @($fixture.cases).Count -eq 3) 'sibling fixture changed.'
Assert-Witness (-not $analyzer.Contains('splitTopLevelCssSiblingCombinatorSelector')) 'pre-fix sibling combinator parser unexpectedly exists.'
Assert-Witness ($analyzer.Contains('if (selector.includes(''>'')')) 'pre-fix path still only dispatches the direct-child combinator.'
Assert-Witness (-not $analyzer.Contains('Combinator.ADJACENT_SIBLING')) 'string fallback has no adjacent-sibling path.'
Assert-Witness (-not $analyzer.Contains('Combinator.GENERAL_SIBLING')) 'string fallback has no general-sibling path.'
Assert-Witness ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado selector handoff is missing.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_jsoup_sibling_combinator_pre_fix_contract'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  classification = 'v2_string_fallback_missing_adjacent_and_general_sibling_combinators'
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = [string]$state.baseline.sourcePackageSha256; legadoCommit = [string]$state.baseline.legadoCommit }
  fixture = $FixturePath
  sourceSnapshotMode = 'backup_before_fix'
  sourceSnapshotPath = $AnalyzerSnapshotPath
  sourceSnapshotHash = Get-TextHash $analyzer
  failingCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  rootCauseDecision = 'DOM Matcher and fixed Legado support + and ~ sibling combinators, but the large-document string fallback tokenizes only spaces and >. Nested :not sibling arguments therefore fail closed at the wrong layer and widen candidates.'
  staticWitnesses = @(
    [pscustomobject][ordered]@{ path = $AnalyzerSnapshotPath; finding = 'findElementsBySingleSelector dispatches only > and otherwise splits on whitespace, so + and ~ become invalid selector parts.' },
    [pscustomobject][ordered]@{ path = $legadoPath; finding = 'pinned Legado delegates sibling combinators to Jsoup Element.select.' }
  )
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_sibling_combinator_failure_witness_static_only;runtime_regression_build_device_and_legado_diff_deferred'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
