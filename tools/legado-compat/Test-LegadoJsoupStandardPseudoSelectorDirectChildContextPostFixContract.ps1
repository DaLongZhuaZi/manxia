[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selector-direct-child-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-direct-child-context-pre-fix-20260809.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-direct-child-context-post-fix-20260809.json'
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
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "required file is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100)
}

function Assert-Contract {
  param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @())
  if (-not $Condition) { throw "243 direct-child context post-fix contract failed: $Detail" }
  $script:assertions++
  [void]$script:checks.Add([pscustomobject][ordered]@{
      id = $Id
      status = 'passed'
      detail = $Detail
      evidencePaths = @($Evidence)
    })
}

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
$statePath = Get-RepoPath 'tools/legado-compat/state/full-source-validation-state.json'
$analyzerRelativePath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$analyzerPath = Get-RepoPath $analyzerRelativePath
$fixture = Read-StrictJson -Path (Get-RepoPath $FixturePath)
$failure = Read-StrictJson -Path (Get-RepoPath $FailureWitnessPath)
$state = Read-StrictJson -Path $statePath
$analyzerBytes = [System.IO.File]::ReadAllBytes($analyzerPath)
$analyzer = $strictUtf8.GetString($analyzerBytes)
$functionStart = $analyzer.IndexOf('private findElementsByDirectChildSelector(')
$functionEnd = $analyzer.IndexOf('private getElementsByRegex(', $functionStart)
Assert-Contract ([string]$failure.status -eq 'failed' -and -not [bool]$failure.semanticMatchAllowed -and @($failure.runtimeActionsPerformed).Count -eq 0) 'failure_witness_preserved' 'the direct-child context failure witness remains failed and static-only.' @($FailureWitnessPath)
Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine_baseline' 'the frozen machine baseline remains unchanged.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Contract ([string]$fixture.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and @($fixture.cases).Count -eq 4) 'fixture_shape' 'the four direct-child pseudo cases remain bound to issue 243.' @($FixturePath)
Assert-Contract ($functionStart -ge 0 -and $functionEnd -gt $functionStart) 'function_boundary' 'the direct-child selector function is present.' @($analyzerRelativePath)
$functionBody = $analyzer.Substring($functionStart, $functionEnd - $functionStart)
Assert-Contract ($functionBody.Contains('findDirectChildOccurrences(innerHtml)')) 'occurrence_context' 'direct children are represented with source offsets.' @($analyzerRelativePath)
Assert-Contract ($functionBody.Contains('const scopedParent = `<legado-direct-parent>${innerHtml}</legado-direct-parent>`')) 'scoped_parent' 'selector evaluation receives a synthetic parent containing all siblings.' @($analyzerRelativePath)
Assert-Contract ($functionBody.Contains('mapStringElementOccurrences(scopedParent, matches)')) 'matched_occurrence_mapping' 'matched strings are mapped back to occurrence offsets.' @($analyzerRelativePath)
Assert-Contract ($functionBody.Contains('matchedRelativeStarts')) 'offset_filter' 'direct-child output is filtered by occurrence offset, preserving identical siblings.' @($analyzerRelativePath)
Assert-Contract (-not $functionBody.Contains('findElementsBySimpleSelector(child, childSelector)')) 'isolated_child_removed' 'the isolated-child pseudo evaluation call is removed.' @($analyzerRelativePath)
Assert-Contract ($functionBody.Contains('nextElements.push(childOccurrence.element)')) 'direct_child_projection' 'only matched direct-child occurrences are projected.' @($analyzerRelativePath)

$relativeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $analyzerPath).Hash.ToUpperInvariant()
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
  currentHeadHashes = [pscustomobject][ordered]@{ $analyzerRelativePath = $relativeHash }
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_source_fix_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  closeCondition = 'R4 must execute the four direct-child cases, the full 243 affected set, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson -Path (Get-RepoPath $ResultPath) -Value $result
$result | ConvertTo-Json -Depth 80
