[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-chain-regex-class-at-context.json',
  [string]$PreFixEvidencePath = 'tools/legado-compat/evidence/contract-legado-jsoup-chain-regex-class-at-pre-fix-20260810.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-chain-regex-class-at-post-fix-20260810.json'
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
  if (-not $Condition) { throw "243 regex-class @ post-fix contract failed: $Detail" }
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
$methodStart = $analyzer.IndexOf('class LegadoRuleChainAnalyzer')
$splitStart = $analyzer.IndexOf('splitByAt(): string[]', $methodStart)
$splitEnd = $analyzer.IndexOf('  /**', $splitStart + 1)
Assert-Contract ([int]$fixture.baseline.sourceCount -eq 458 -and [string]$fixture.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$fixture.baseline.legadoCommit -eq $legadoCommit) 'fixture_baseline' 'fixture is bound to the frozen baselines.' @($FixturePath)
Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine_baseline' 'machine fact baseline is unchanged.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Contract ([string]$preFix.status -eq 'failed' -and -not [bool]$preFix.semanticMatchAllowed -and @($preFix.runtimeActionsPerformed).Count -eq 0) 'failure_witness_preserved' 'the pre-fix failure witness remains failed and static-only.' @($PreFixEvidencePath)
Assert-Contract (@($fixture.cases).Count -eq 2 -and [string]$fixture.cases[0].rule -like '*[^)]*' -and [string]$fixture.cases[1].rule -like '*:not(:matches*') 'fixture_shape' 'both regex-character-class and nested-not cases remain bound.' @($FixturePath)
Assert-Contract ($methodStart -ge 0 -and $splitStart -gt $methodStart -and $splitEnd -gt $splitStart) 'splitter_boundary' 'the chain splitter remains a bounded helper.' @($analyzerPath)
$splitBody = $analyzer.Substring($splitStart, $splitEnd - $splitStart)
Assert-Contract ($splitBody.Contains('let parenthesisDepth = 0') -and $splitBody.Contains('let bracketDepth = 0') -and $splitBody.Contains("let quote = ''") -and $splitBody.Contains('let escaped = false')) 'stateful_contexts' 'chain splitting tracks parentheses, brackets, quotes and escapes.' @($analyzerPath)
Assert-Contract ($splitBody.Contains("if (c === '@' && parenthesisDepth === 0 && bracketDepth === 0)")) 'top_level_at_only' 'only a top-level @ is emitted as a Legado chain delimiter.' @($analyzerPath)
Assert-Contract ($splitBody.Contains("if (c === ']' && bracketDepth > 0)") -and $splitBody.Contains("if (c === ')' && parenthesisDepth > 0 && bracketDepth === 0)")) 'balanced_contexts' 'regex character classes close before pseudo parentheses are decremented.' @($analyzerPath)
Assert-Contract (-not $splitBody.Contains("this.skipBalanced('[', ']')") -and -not $splitBody.Contains("this.skipBalanced('(', ')')")) 'old_skip_removed' 'the same-delimiter skipBalanced path no longer controls chain splitting.' @($analyzerPath)

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
  verificationPolicy = 'r3_243_chain_regex_class_at_static_contract_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  closeCondition = 'R4 must execute both chain cases through V2, affected 243 sources, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson -RelativePath $ResultPath -Value $result
$result | ConvertTo-Json -Depth 80
