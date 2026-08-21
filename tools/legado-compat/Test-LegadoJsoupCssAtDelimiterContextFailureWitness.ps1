[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-css-at-delimiter-context.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-css-at-delimiter-context-pre-fix-20260810.json'
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
function Assert-Witness { param([bool]$Condition, [string]$Id, [string]$Detail); if (-not $Condition) { throw "243 CSS @ delimiter witness failed: $Detail" }; $script:assertions++ }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$fixture = Read-StrictJson $FixturePath
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$analyzer = Read-StrictText $analyzerPath
$chainStart = $analyzer.IndexOf('private getElementsByCSSChain(')
$chainEnd = $analyzer.IndexOf('private splitSelectorWithJs(', $chainStart)
$indexStart = $analyzer.IndexOf('private hasLegacyIndexInCssChain(')

Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'frozen source and Legado baselines are unchanged.'
Assert-Witness ([string]$fixture.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and @($fixture.cases).Count -eq 3 -and [int]$fixture.largeDocumentThreshold -eq 50000) 'fixture' 'fixture contains the large-document threshold and three nested-at cases.'
Assert-Witness ($chainStart -ge 0 -and $chainEnd -gt $chainStart -and $indexStart -ge 0 -and $indexStart -lt $chainStart) 'source_boundaries' 'CSS chain and index splitter boundaries are present.'
$chainBody = $analyzer.Substring($chainStart, $chainEnd - $chainStart)
Assert-Witness ($chainBody.Contains("parts = selector.split('@')")) 'raw_chain_at_split' 'large-document CSS chain still splits every @ character before the fix.'
Assert-Witness ($analyzer.Substring($indexStart, $chainStart - $indexStart).Contains("selector.split('@')")) 'raw_index_at_split' 'legacy-index detection uses the same unsafe @ split before the fix.'
Assert-Witness ($fixture.failureCondition.Contains("selector.split('@')") -and $fixture.failureCondition.Contains('final @')) 'fixture_failure_statement' 'fixture records the raw @ split and Legado final-attribute semantics.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'failure_witness'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  failureClass = 'v2_large_document_css_chain_at_delimiter_split_ignores_nested_selector_context'
  selectionPath = [string]$fixture.selectionPath
  affectedCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  failureWitness = [pscustomobject][ordered]@{
    branch = 'getElementsByCSSChain and hasLegacyIndexInCssChain'
    observed = 'The string fallback and its index preflight split the complete selector on every @ character, including @ inside :contains, :matches and quoted attribute values.'
    sourcePatterns = @("parts = selector.split('@')", "parts: string[] = selector.split('@')")
    expected = 'Split @ only when the scanner is at top level (outside parentheses, brackets, quoted strings and escaped characters), preserving nested selector text for Jsoup-equivalent evaluation.'
  }
  largeDocumentThreshold = [int]$fixture.largeDocumentThreshold
  padding = $fixture.padding
  assertions = $script:assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred'
}
Write-AtomicJson $ResultPath $result
$result | ConvertTo-Json -Depth 100
