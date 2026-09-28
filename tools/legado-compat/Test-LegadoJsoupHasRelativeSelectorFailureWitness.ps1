[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-has-relative-selector-context.json',
  [string]$AnalyzerSnapshotPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets.bak_20260809_has_relative_selector',
  [string]$ElementSnapshotPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets.bak_20260809_has_relative_selector',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-has-relative-selector-pre-fix-20260809.json'
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
function Assert-Witness { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 :has relative selector failure witness failed: $Message" } }
function Get-TextHash { param([Parameter(Mandatory = $true)][string]$Text); $sha = [System.Security.Cryptography.SHA256]::Create(); try { return ([System.BitConverter]::ToString($sha.ComputeHash($strictUtf8.GetBytes($Text)))).Replace('-', '').ToUpperInvariant() } finally { $sha.Dispose() } }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value); $path = Get-RepoPath $RelativePath; $directory = Split-Path -Parent $path; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temp = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temp -Destination $path -Force } finally { if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) } } }

$fixture = Read-StrictJson $FixturePath
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$analyzer = Read-StrictText $AnalyzerSnapshotPath
$element = Read-StrictText $ElementSnapshotPath
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$legado = Read-StrictText $legadoPath
Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$state.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'frozen baseline drifted.'
Assert-Witness ([string]$fixture.contract -eq 'legado_jsoup_has_relative_selector_context' -and @($fixture.cases).Count -eq 4) 'relative selector fixture changed.'
Assert-Witness ($analyzer.Contains('matches.some((match: string): boolean => match === child)')) 'pre-fix string fallback equality guard is absent.'
Assert-Witness ($element.Contains('child.matches(childSelector)')) 'pre-fix DOM child.matches guard is absent.'
Assert-Witness (-not $element.Contains('matchesHasDirectChildRelativeSelector')) 'relative-selector helper unexpectedly exists in the pre-fix snapshot.'
Assert-Witness ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'pinned Legado Jsoup handoff is missing.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_jsoup_has_relative_selector_pre_fix_contract'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  classification = 'v2_has_relative_selector_rejected_descendants_below_direct_child'
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = [string]$state.baseline.sourcePackageSha256; legadoCommit = [string]$state.baseline.legadoCommit }
  fixture = $FixturePath
  sourceSnapshotMode = 'backup_before_fix'
  sourceSnapshots = [pscustomobject][ordered]@{ analyzer = $AnalyzerSnapshotPath; element = $ElementSnapshotPath }
  sourceSnapshotHashes = [pscustomobject][ordered]@{ analyzer = Get-TextHash $analyzer; element = Get-TextHash $element }
  failingCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  rootCauseDecision = 'DOM child.matches only handles a single selector part and string fallback requires result === direct child; both diverge from Jsoup relative selector evaluation for >div span.'
  staticWitnesses = @(
    [pscustomobject][ordered]@{ path = $ElementSnapshotPath; finding = 'child.matches(childSelector) cannot prove a descendant span below the direct div child.' },
    [pscustomobject][ordered]@{ path = $AnalyzerSnapshotPath; finding = 'matches.some(match === child) rejects descendant matches returned for >div span.' },
    [pscustomobject][ordered]@{ path = $legadoPath; finding = 'pinned Legado delegates CSS selection to Jsoup Element.select, which evaluates the complete relative selector.' }
  )
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_relative_selector_failure_witness_static_only;runtime_regression_build_device_and_legado_diff_deferred'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
