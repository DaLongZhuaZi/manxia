[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-direct-child-occurrence-marker-guard.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-direct-child-occurrence-marker-guard-pre-fix-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-direct-child-occurrence-marker-guard-post-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$analyzerRelativePath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$legadoRelativePath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
}
function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  $resolved = Get-RepoPath $Path
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Missing text: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($resolved)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return $strictUtf8.GetString($bytes)
}
function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Read-StrictText $Path | ConvertFrom-Json -Depth 100)
}
function Assert-Contract {
  param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @())
  if (-not $Condition) { throw "243 direct-child marker guard post-fix contract failed: $Detail" }
  $script:assertions++
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) })
}
function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $resolved = Get-RepoPath $Path
  $directory = Split-Path -Parent $resolved
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $resolved -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$analyzer = Read-StrictText $analyzerRelativePath
$legado = Read-StrictText $legadoRelativePath

Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'frozen machine baseline is unchanged.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Contract ([string]$state.governance.activeIssueId -eq $issueId -and [string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.status -eq 'running') 'queue' '243 remains the sole active static issue.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Contract ([string]$failure.status -eq 'failed' -and -not [bool]$failure.semanticMatchAllowed -and @($failure.runtimeActionsPerformed).Count -eq 0) 'failure_witness' 'pre-fix failure evidence remains failed and static-only.' @($FailureWitnessPath)
Assert-Contract ([string]$fixture.issueId -eq $issueId -and [string]$fixture.contract -eq 'legado_jsoup_direct_child_occurrence_marker_guard' -and @($fixture.cases).Count -eq 2) 'fixture' 'direct-child marker fixture remains bound.' @($FixturePath)

$directChildStart = $analyzer.IndexOf('private findElementsByDirectChildSelector(')
$directChildEnd = $analyzer.IndexOf('private getElementsByRegex(', $directChildStart)
Assert-Contract ($directChildStart -ge 0 -and $directChildEnd -gt $directChildStart) 'direct_child_boundary' 'direct-child method boundary is present.' @($analyzerRelativePath)
$directChild = $analyzer.Substring($directChildStart, $directChildEnd - $directChildStart)
Assert-Contract (-not $directChild.Contains('needsOccurrenceMarkers')) 'direct_child_scope' 'direct-child helper no longer reads the outer marker local.' @($analyzerRelativePath)
Assert-Contract ($directChild.Contains('return currentElements;') -and -not $directChild.Contains('stripStringSelectorOccurrenceMarker')) 'direct_child_preserve' 'direct-child helper preserves markers for nested occurrence mapping.' @($analyzerRelativePath)

$chainStart = $analyzer.IndexOf('private getElementsByCSSChain(')
$chainEnd = $analyzer.IndexOf('private splitSelectorWithJs(', $chainStart)
Assert-Contract ($chainStart -ge 0 -and $chainEnd -gt $chainStart) 'chain_boundary' 'outer CSS-chain method boundary is present.' @($analyzerRelativePath)
$chain = $analyzer.Substring($chainStart, $chainEnd - $chainStart)
Assert-Contract ($chain.Contains("const needsOccurrenceMarkers = selector.includes(':')") -and $chain.Contains('if (!needsOccurrenceMarkers)') -and $chain.Contains('return this.stripStringSelectorOccurrenceMarker(element);')) 'chain_cleanup' 'outer CSS chain strips markers exactly at its final return boundary.' @($analyzerRelativePath)
Assert-Contract ($chain.Contains('const selectionContextHtml = needsOccurrenceMarkers') -and $chain.Contains('findElementsBySingleSelector(element, part, selectionContextHtml)')) 'chain_context' 'marker state is propagated through each selector part.' @($analyzerRelativePath)
Assert-Contract ($analyzer.Contains('private stripStringSelectorOccurrenceMarker(value: string): string')) 'strip_helper' 'marker removal remains centralized in a typed helper.' @($analyzerRelativePath)
Assert-Contract ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'legado_consumer' 'pinned Legado selector handoff remains the reference contract.' @($legadoRelativePath)

$hashes = [ordered]@{}
foreach ($path in @($analyzerRelativePath, $legadoRelativePath)) { $hashes[$path] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $path)).Hash.ToUpperInvariant() }
$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'post_fix_static_contract'
  issueId = $issueId
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  failureWitnessPath = $FailureWitnessPath
  changedPaths = @($analyzerRelativePath)
  currentHeadHashes = $hashes
  affectedSourceOrdinals = @($fixture.affectedSourceOrdinals)
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_direct_child_occurrence_marker_guard_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  closeCondition = 'R4 must execute direct-child pseudo/group marker cases, the affected 243 source set, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
