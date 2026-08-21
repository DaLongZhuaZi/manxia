[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-regex-class-parenthesis-context.json',
  [string]$PreFixEvidencePath = 'tools/legado-compat/evidence/contract-legado-jsoup-regex-class-parenthesis-pre-fix-20260810.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-regex-class-parenthesis-post-fix-20260810.json'
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
function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required file is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$RelativePath); return (Read-StrictText -RelativePath $RelativePath | ConvertFrom-Json -Depth 100) }
function Assert-Contract {
  param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @())
  if (-not $Condition) { throw "243 regex-class parenthesis post-fix contract failed: $Detail" }
  $script:assertions++
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) })
}
function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value)
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 80), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$fixture = Read-StrictJson -RelativePath $FixturePath
$preFix = Read-StrictJson -RelativePath $PreFixEvidencePath
$state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$analyzer = Read-StrictText -RelativePath $analyzerPath
$chainStart = $analyzer.IndexOf('class LegadoRuleChainAnalyzer')
$chainSplitStart = $analyzer.IndexOf('splitByAt(): string[]', $chainStart)
$chainSplitEnd = $analyzer.IndexOf('  /**', $chainSplitStart + 1)
$selectorSplitStart = $analyzer.IndexOf('private splitSelectorWithJs(')
$selectorSplitEnd = $analyzer.IndexOf('  /**', $selectorSplitStart + 1)
$groupSplitStart = $analyzer.IndexOf('private splitTopLevelCssSelectorGroups(')
$groupSplitEnd = $analyzer.IndexOf('  /**', $groupSplitStart + 1)
Assert-Contract ([int]$fixture.baseline.sourceCount -eq 458 -and [string]$fixture.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$fixture.baseline.legadoCommit -eq $legadoCommit) 'fixture_baseline' 'fixture is bound to the frozen baselines.' @($FixturePath)
Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine_baseline' 'machine fact baseline is unchanged.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Contract ([string]$preFix.status -eq 'failed' -and -not [bool]$preFix.semanticMatchAllowed -and @($preFix.runtimeActionsPerformed).Count -eq 0) 'failure_witness_preserved' 'the pre-fix failure witness remains failed and static-only.' @($PreFixEvidencePath)
Assert-Contract (@($fixture.cases).Count -eq 2 -and @($fixture.selectionPaths).Count -eq 3) 'fixture_shape' 'legacy chain, top-level @ chain and selector-group cases remain bound.' @($FixturePath)
Assert-Contract ($chainSplitStart -gt $chainStart -and $chainSplitEnd -gt $chainSplitStart -and $selectorSplitStart -ge 0 -and $selectorSplitEnd -gt $selectorSplitStart -and $groupSplitStart -ge 0 -and $groupSplitEnd -gt $groupSplitStart) 'splitter_boundaries' 'all three splitter helpers remain bounded.' @($analyzerPath)
$chainBody = $analyzer.Substring($chainSplitStart, $chainSplitEnd - $chainSplitStart)
$selectorBody = $analyzer.Substring($selectorSplitStart, $selectorSplitEnd - $selectorSplitStart)
$groupBody = $analyzer.Substring($groupSplitStart, $groupSplitEnd - $groupSplitStart)
Assert-Contract ($chainBody.Contains("if (c === '(' && bracketDepth === 0)") -and $chainBody.Contains("if (c === ')' && parenthesisDepth > 0 && bracketDepth === 0)")) 'legacy_chain_bracket_opaque' 'legacy @ chain splitting ignores parentheses inside regex/attribute brackets.' @($analyzerPath)
Assert-Contract ($selectorBody.Contains("if (character === '(' && bracketDepth === 0)") -and $selectorBody.Contains("if (character === ')' && parenthesisDepth > 0 && bracketDepth === 0)")) 'selector_chain_bracket_opaque' 'large-document @ splitting ignores parentheses inside regex/attribute brackets.' @($analyzerPath)
Assert-Contract ($groupBody.Contains("if (character === '(' && bracketDepth === 0)") -and $groupBody.Contains("else if (character === ')' && parenthesisDepth > 0 && bracketDepth === 0)")) 'selector_group_bracket_opaque' 'CSS group splitting ignores parentheses inside regex/attribute brackets.' @($analyzerPath)

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'post_fix_static_contract'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  preFixEvidencePath = $PreFixEvidencePath
  changedPaths = @($analyzerPath)
  affectedCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_regex_class_parenthesis_static_contract_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  closeCondition = 'R4 must execute both regex-parenthesis cases through legacy and large-document selector paths, the 243 affected set, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson -RelativePath $ResultPath -Value $result
$result | ConvertTo-Json -Depth 80
