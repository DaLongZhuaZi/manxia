[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selector-direct-child-regex-class-context.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-direct-child-regex-class-context-pre-fix-20260809.json'
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
function Assert-Witness { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 regex-class witness failed: $Message" }; $script:assertions++ }
function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try { [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 80), $noBomUtf8); Move-Item -LiteralPath $temporaryPath -Destination $Path -Force }
  finally { if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) } }
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
$helperStart = $analyzer.IndexOf('private splitTopLevelDirectChildSelectors(')
$helperEnd = $analyzer.IndexOf('private findElementsByDirectChildSelector(', $helperStart)
Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline drifted.'
Assert-Witness ([string]$fixture.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and @($fixture.cases).Count -eq 2) 'fixture is not bound to the two regex-class cases.'
Assert-Witness ($helperStart -ge 0 -and $helperEnd -gt $helperStart) 'top-level splitter boundary is missing.'
$helperBody = $analyzer.Substring($helperStart, $helperEnd - $helperStart)
Assert-Witness ($helperBody.Contains("else if (character === ')' && parenthesisDepth > 0)")) 'the unguarded parenthesis close was not found.'
Assert-Witness (-not $helperBody.Contains("parenthesisDepth > 0 && bracketDepth === 0")) 'the bracket-aware parenthesis guard already exists.'
Assert-Witness ($fixture.failureCondition.Contains('bracketDepth')) 'fixture does not bind the bracket-depth failure condition.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'failure_witness'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  failureClass = 'v2_large_document_string_fallback_direct_child_split_parenthesis_depth_leaks_from_regex_character_class'
  selectionPath = [string]$fixture.selectionPath
  affectedCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  failureWitness = [pscustomobject][ordered]@{
    branch = 'splitTopLevelDirectChildSelectors'
    observed = 'a closing parenthesis inside bracketDepth decrements parenthesisDepth, allowing a greater-than in the still-open pseudo argument to be emitted as a top-level boundary.'
    sourcePattern = "else if (character === ')' && parenthesisDepth > 0)"
    expected = 'parenthesis depth must change only when bracketDepth is zero; regex character classes must be opaque to pseudo-parenthesis accounting.'
  }
  assertions = $script:assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred'
}
Write-AtomicJson -Path $resultAbsolutePath -Value $result
$result | ConvertTo-Json -Depth 80
