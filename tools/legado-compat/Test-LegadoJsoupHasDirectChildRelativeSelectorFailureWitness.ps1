[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-has-direct-child-relative-selector-context.json',
  [string]$AnalyzerSnapshotPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets.bak_20260810_has_direct_child_relative_selector',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-has-direct-child-relative-selector-pre-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$RelativePath); if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $RelativePath }; return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $fullPath = Get-RepoPath $Path; if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Missing text: $Path" }; return $strictUtf8.GetString([System.IO.File]::ReadAllBytes($fullPath)) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText $Path | ConvertFrom-Json -Depth 100) }
function Assert-Witness { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 :has direct-child relative selector failure witness failed: $Message" } }
function Get-TextHash { param([Parameter(Mandatory = $true)][string]$Text); $sha = [System.Security.Cryptography.SHA256]::Create(); try { return ([System.BitConverter]::ToString($sha.ComputeHash($strictUtf8.GetBytes($Text)))).Replace('-', '').ToUpperInvariant() } finally { $sha.Dispose() } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $fullPath = Get-RepoPath $Path; $directory = Split-Path -Parent $fullPath; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$fullPath.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $fullPath -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$fixture = Read-StrictJson $FixturePath
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$analyzer = Read-StrictText $AnalyzerSnapshotPath
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$legado = Read-StrictText $legadoPath
Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$state.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'frozen baseline drifted.'
Assert-Witness ([string]$fixture.contract -eq 'legado_jsoup_has_direct_child_relative_selector_context' -and @($fixture.cases).Count -eq 4) 'direct-child relative selector fixture changed.'
Assert-Witness ($analyzer.Contains('matches.some((match: string): boolean => match !== wrapper)')) 'pre-fix string fallback acceptance guard is absent.'
Assert-Witness (-not $analyzer.Contains('matchesStringSelectorAtElementStart')) 'direct-child subject guard unexpectedly exists in the pre-fix snapshot.'
Assert-Witness ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado Jsoup selector handoff is missing.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_jsoup_has_direct_child_relative_selector_pre_fix_contract'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  classification = 'v2_has_direct_child_relative_selector_accepted_nested_descendant'
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = [string]$state.baseline.sourcePackageSha256; legadoCommit = [string]$state.baseline.legadoCommit }
  fixture = $FixturePath
  sourceSnapshotMode = 'current_head_before_fix'
  sourceSnapshots = [pscustomobject][ordered]@{ analyzer = $AnalyzerSnapshotPath }
  sourceSnapshotHashes = [pscustomobject][ordered]@{ analyzer = Get-TextHash $analyzer }
  failingCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  rootCauseDecision = 'The string fallback evaluates the remainder of a :has(>) selector against a wrapper and accepts every non-wrapper match. It does not verify that the first selector compound matches the direct child itself, so >span.foo incorrectly matches a span nested below a direct div.'
  staticWitnesses = @(
    [pscustomobject][ordered]@{ path = $AnalyzerSnapshotPath; finding = 'matches !== wrapper treats a nested result as proof of a direct-child selector.' },
    [pscustomobject][ordered]@{ path = $legadoPath; finding = 'pinned Legado delegates the complete selector to Jsoup Element.select, whose > combinator binds the first selector subject to a direct child.' }
  )
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_direct_child_relative_selector_failure_witness_static_only;runtime_regression_build_device_and_legado_diff_deferred'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
