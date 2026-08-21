[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-regex-class-parenthesis-context.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-regex-class-parenthesis-pre-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$RelativePath); return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "required file is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return $strictUtf8.GetString($bytes)
}
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100) }
function Assert-Witness { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 regex-class parenthesis witness failed: $Message" }; $script:assertions++ }
function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 80), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$fixtureAbsolutePath = Get-RepoPath $FixturePath
$resultAbsolutePath = Get-RepoPath $ResultPath
$statePath = Get-RepoPath 'tools/legado-compat/state/full-source-validation-state.json'
$analyzerPath = Get-RepoPath 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$fixture = Read-StrictJson -Path $fixtureAbsolutePath
$state = Read-StrictJson -Path $statePath
$analyzer = Read-StrictText -Path $analyzerPath
$chainStart = $analyzer.IndexOf('class LegadoRuleChainAnalyzer')
$chainSplitStart = $analyzer.IndexOf('splitByAt(): string[]', $chainStart)
$chainSplitEnd = $analyzer.IndexOf('  /**', $chainSplitStart + 1)
$selectorSplitStart = $analyzer.IndexOf('private splitSelectorWithJs(')
$selectorSplitEnd = $analyzer.IndexOf('  /**', $selectorSplitStart + 1)
$groupSplitStart = $analyzer.IndexOf('private splitTopLevelCssSelectorGroups(')
$groupSplitEnd = $analyzer.IndexOf('  /**', $groupSplitStart + 1)
Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline drifted.'
Assert-Witness ([string]$fixture.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and @($fixture.cases).Count -eq 2) 'fixture is not bound to the two regex-parenthesis cases.'
Assert-Witness ($chainSplitStart -gt $chainStart -and $chainSplitEnd -gt $chainSplitStart -and $selectorSplitStart -ge 0 -and $selectorSplitEnd -gt $selectorSplitStart -and $groupSplitStart -ge 0 -and $groupSplitEnd -gt $groupSplitStart) 'splitter boundaries are missing.'
$chainBody = $analyzer.Substring($chainSplitStart, $chainSplitEnd - $chainSplitStart)
$selectorBody = $analyzer.Substring($selectorSplitStart, $selectorSplitEnd - $selectorSplitStart)
$groupBody = $analyzer.Substring($groupSplitStart, $groupSplitEnd - $groupSplitStart)
Assert-Witness ($chainBody.Contains("if (c === '(')")) 'legacy chain splitter is already bracket-aware.'
Assert-Witness ($selectorBody.Contains("if (character === '(')")) 'top-level @ splitter is already bracket-aware.'
Assert-Witness ($groupBody.Contains("if (character === '(')")) 'selector-group splitter is already bracket-aware.'
Assert-Witness (-not $chainBody.Contains("if (c === '(' && bracketDepth === 0)")) 'legacy chain splitter already guards parentheses with bracket depth.'
Assert-Witness (-not $selectorBody.Contains("if (character === '(' && bracketDepth === 0)")) 'top-level @ splitter already guards parentheses with bracket depth.'
Assert-Witness (-not $groupBody.Contains("if (character === '(' && bracketDepth === 0)")) 'selector-group splitter already guards parentheses with bracket depth.'
Assert-Witness ([string]$fixture.failureCondition -match 'bracketDepth') 'fixture does not bind the bracket-depth failure condition.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'failure_witness'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  failureClass = 'v2_css_splitters_count_parentheses_inside_regex_character_classes'
  selectionPaths = @($fixture.selectionPaths)
  affectedCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  failureWitness = [pscustomobject][ordered]@{
    branches = @('LegadoRuleChainAnalyzer.splitByAt', 'splitSelectorWithJs', 'splitTopLevelCssSelectorGroups')
    observed = 'Each splitter increments parenthesisDepth for a literal ( inside an open bracket context. A valid regex class such as [(] leaves an extra depth and hides a later top-level @ or comma.'
    sourcePattern = "if (character === '(') / if (c === '(')"
    expected = 'Bracket context must be opaque to parenthesis accounting; only parentheses at bracketDepth zero may change pseudo depth.'
  }
  assertions = $script:assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred'
}
Write-AtomicJson -Path $resultAbsolutePath -Value $result
$result | ConvertTo-Json -Depth 80
