[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selector-direct-child-split-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-direct-child-split-context-pre-fix-20260809.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-direct-child-split-context-post-fix-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required file is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return (Read-StrictText -RelativePath $RelativePath | ConvertFrom-Json -Depth 100)
}

function Assert-Contract {
  param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @())
  if (-not $Condition) { throw "243 direct-child split post-fix contract failed: $Detail" }
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
$analyzerRelativePath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$analyzer = Read-StrictText $analyzerRelativePath
$functionStart = $analyzer.IndexOf('private findElementsByDirectChildSelector(')
$functionEnd = $analyzer.IndexOf('private getElementsByRegex(', $functionStart)
$helperStart = $analyzer.IndexOf('private splitTopLevelDirectChildSelectors(')
$helperEnd = $analyzer.IndexOf('private findElementsByDirectChildSelector(', $helperStart)

Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine_baseline' 'the frozen 458-source package and Legado commit remain unchanged.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Contract ([string]$failure.status -eq 'failed' -and -not [bool]$failure.semanticMatchAllowed -and @($failure.runtimeActionsPerformed).Count -eq 0) 'failure_witness_preserved' 'the raw split failure witness remains failed and static-only.' @($FailureWitnessPath)
Assert-Contract ([string]$fixture.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and @($fixture.cases).Count -eq 4) 'fixture_shape' 'the four nested-selector split cases remain bound to 243.' @($FixturePath)
Assert-Contract ($helperStart -ge 0 -and $helperEnd -gt $helperStart) 'helper_boundary' 'the top-level-aware direct-child splitter is present before the direct-child fallback.' @($analyzerRelativePath)
$helperBody = $analyzer.Substring($helperStart, $helperEnd - $helperStart)
Assert-Contract ($helperBody.Contains('parenthesisDepth') -and $helperBody.Contains('bracketDepth') -and $helperBody.Contains('quote') -and $helperBody.Contains('escaped')) 'parser_state' 'splitter tracks pseudo parentheses, attribute brackets, quoted values, and escapes.' @($analyzerRelativePath)
Assert-Contract ($helperBody.Contains("character === '>' && parenthesisDepth === 0 && bracketDepth === 0")) 'top_level_guard' 'only a top-level greater-than is emitted as a direct-child boundary.' @($analyzerRelativePath)
Assert-Contract ($functionStart -ge 0 -and $functionEnd -gt $functionStart) 'function_boundary' 'the direct-child fallback function remains present.' @($analyzerRelativePath)
$functionBody = $analyzer.Substring($functionStart, $functionEnd - $functionStart)
Assert-Contract ($functionBody.Contains('this.splitTopLevelDirectChildSelectors(selector)')) 'helper_consumed' 'direct-child fallback consumes the top-level-aware splitter.' @($analyzerRelativePath)
Assert-Contract (-not $functionBody.Contains("selector.split('>')")) 'raw_split_removed' 'the raw greater-than split is removed from the direct-child path.' @($analyzerRelativePath)
Assert-Contract ($functionBody.Contains('parts.length < 2') -and $functionBody.Contains('findElementsBySimpleSelector(html, selector, effectiveContextHtml)')) 'nested_only_fallback' 'selectors with only nested greater-than characters fall back to ordinary pseudo evaluation while preserving selector context.' @($analyzerRelativePath)
Assert-Contract (@($fixture.cases | Where-Object { [string]$_.semantics -like 'ignore_*' }).Count -eq 3) 'nested_case_coverage' 'pseudo, attribute, and regex greater-than contexts are represented.' @($FixturePath)

$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $analyzerRelativePath)).Hash.ToUpperInvariant()
$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'post_fix_static_contract'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  failureWitnessPath = $FailureWitnessPath
  changedPaths = @($analyzerRelativePath)
  currentHeadHashes = [pscustomobject][ordered]@{ $analyzerRelativePath = $hash }
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_source_fix_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  closeCondition = 'R4 must execute nested pseudo, attribute, regex, direct-child and affected-source cases against fixed Legado before 243 can leave verifying.'
}
Write-AtomicJson -RelativePath $ResultPath -Value $result
$result | ConvertTo-Json -Depth 80
