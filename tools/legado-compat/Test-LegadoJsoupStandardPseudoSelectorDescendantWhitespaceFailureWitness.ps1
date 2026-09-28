[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selector-descendant-whitespace-context.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-descendant-whitespace-context-pre-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }; return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Missing text: $Path" }; $bytes = [System.IO.File]::ReadAllBytes($resolved); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }; return $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText $Path | ConvertFrom-Json -Depth 100) }
function Assert-Witness { param([bool]$Condition, [string]$Id, [string]$Detail); if (-not $Condition) { throw "243 descendant whitespace witness failed: $Detail" }; $script:assertions++ }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 80), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$fixture = Read-StrictJson $FixturePath
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$analyzer = Read-StrictText $analyzerPath
$singleStart = $analyzer.IndexOf('private findElementsBySingleSelector(')
$singleEnd = $analyzer.IndexOf('private findElementsBySimpleSelector(', $singleStart)
$directStart = $analyzer.IndexOf('private findElementsByDirectChildSelector(')
$directEnd = $analyzer.IndexOf('private getElementsByRegex(', $directStart)

Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'frozen source and Legado baselines are unchanged.'
Assert-Witness ([string]$fixture.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and @($fixture.cases).Count -eq 5) 'fixture' 'descendant whitespace fixture remains bound to five cases.'
Assert-Witness ($singleStart -ge 0 -and $singleEnd -gt $singleStart) 'single_boundary' 'single-selector fallback boundary is present.'
$singleBody = $analyzer.Substring($singleStart, $singleEnd - $singleStart)
Assert-Witness ($singleBody.Contains('selector.trim().split(/\s+/)')) 'raw_whitespace_split' 'the pre-fix descendant path still splits all whitespace without parser state.'
Assert-Witness ($directStart -ge 0 -and $directEnd -gt $directStart) 'direct_boundary' 'direct-child fallback boundary is present.'
$directBody = $analyzer.Substring($directStart, $directEnd - $directStart)
Assert-Witness ($directBody.Contains('parts.length < 2') -and $analyzer.Contains("if (selector.includes('>'))")) 'nested_gt_dispatch' 'a nested > can still enter direct-child dispatch before top-level classification.'
Assert-Witness (-not $analyzer.Contains('splitTopLevelCssDescendantSelector')) 'missing_descendant_splitter' 'the top-level whitespace splitter is absent before the fix.'
Assert-Witness ($fixture.failureCondition.Contains('selector.trim().split') -and $fixture.failureCondition.Contains('selector.includes')) 'fixture_failure_statement' 'fixture records both parser failure branches.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'failure_witness'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  failureClass = 'v2_large_document_string_fallback_descendant_split_ignores_pseudo_and_attribute_context'
  selectionPath = [string]$fixture.selectionPath
  affectedCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  failureWitness = [pscustomobject][ordered]@{
    branch = 'findElementsBySingleSelector and findElementsByDirectChildSelector'
    observed = 'Top-level descendant detection is based on raw whitespace and any greater-than character, so pseudo arguments and quoted attribute values are treated as outer combinator syntax.'
    sourcePatterns = @('selector.trim().split(/\s+/)', "if (selector.includes('>'))")
    expected = 'Use one stateful selector scanner for parentheses, brackets, quotes and escapes; only top-level whitespace or combinators should split the chain.'
  }
  assertions = $script:assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred'
}
Write-AtomicJson $ResultPath $result
$result | ConvertTo-Json -Depth 80
