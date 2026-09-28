[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-dom-selector-group-document-order-context.json',
  [string]$PreFixEvidencePath = 'tools/legado-compat/evidence/contract-legado-jsoup-dom-selector-group-document-order-pre-fix-20260810.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-dom-selector-group-document-order-post-fix-20260810.json'
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
  if (-not $Condition) { throw "243 DOM selector-group document-order post-fix contract failed: $Detail" }
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
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8)
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
$elementPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$element = Read-StrictText -RelativePath $elementPath
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$legado = Read-StrictText -RelativePath $legadoPath
$sourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
$packageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePackagePath).Hash.ToUpperInvariant()
$sourceObjects = @($strictUtf8.GetString([System.IO.File]::ReadAllBytes($sourcePackagePath)) | ConvertFrom-Json -Depth 100)
$queryStart = $element.IndexOf('  querySelectorAll(selector: string): HTMLElement[] {')
$queryEnd = $element.IndexOf("`r`n  /**", $queryStart + 1)
if ($queryEnd -lt 0) { $queryEnd = $element.IndexOf("`n  /**", $queryStart + 1) }
$queryBody = if ($queryStart -ge 0 -and $queryEnd -gt $queryStart) { $element.Substring($queryStart, $queryEnd - $queryStart) } else { '' }
$representative = ($sourceObjects[96] | ConvertTo-Json -Depth 100 -Compress)

Assert-Contract ([int]$fixture.baseline.sourceCount -eq 458 -and [string]$fixture.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$fixture.baseline.legadoCommit -eq $legadoCommit) 'fixture_baseline' 'fixture remains bound to the frozen baselines.' @($FixturePath)
Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit -and $packageHash -eq $baselineHash -and $sourceObjects.Count -eq 458) 'machine_and_package_baseline' 'machine state and source package remain unchanged.' @('tools/legado-compat/state/full-source-validation-state.json', $FixturePath)
Assert-Contract ([string]$preFix.status -eq 'failed' -and -not [bool]$preFix.semanticMatchAllowed -and @($preFix.runtimeActionsPerformed).Count -eq 0) 'failure_witness_preserved' 'the pre-fix witness remains failed and static-only.' @($PreFixEvidencePath)
Assert-Contract ([string]$fixture.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and @($fixture.cases).Count -eq 2 -and [string]$fixture.cases[0].expectedIds[0] -eq 'first' -and [string]$fixture.cases[0].expectedIds[1] -eq 'second') 'fixture_shape' 'reverse-group and same-node cases preserve document-order expectations.' @($FixturePath)
Assert-Contract ($representative.Contains('.book_other:nth-child(4)') -and $representative.Contains('.book_other:nth-child(5)')) 'representative_source_binding' 'the frozen ordinal 97 selector-group binding remains present.' @($FixturePath)
Assert-Contract ($queryStart -ge 0 -and $queryEnd -gt $queryStart) 'query_selector_boundary' 'HTMLElement.querySelectorAll remains a bounded method.' @($elementPath)
Assert-Contract ($queryBody.Contains("const documentOrder = this.getElementsByTagName('*');") -and $queryBody.Contains('const documentPositions = new Map<HTMLElement, number>();')) 'document_position_map' 'DOM results are assigned deterministic source-order positions.' @($elementPath)
Assert-Contract ($queryBody.Contains('documentPositions.set(documentOrder[index], index);') -and $queryBody.Contains('results.sort((left: HTMLElement, right: HTMLElement): number => {')) 'document_order_projection' 'selector-group union is sorted by the current DOM traversal order.' @($elementPath)
Assert-Contract ($queryBody.Contains('const leftPosition = documentPositions.get(left);') -and $queryBody.Contains('const rightPosition = documentPositions.get(right);') -and $queryBody.Contains('return leftPosition - rightPosition;')) 'stable_position_comparator' 'the comparator handles missing positions and orders known elements by position.' @($elementPath)
Assert-Contract ($queryBody.Contains('if (!seen.has(match))') -and $queryBody.Contains('seen.add(match)')) 'identity_deduplication_preserved' 'same-node de-duplication remains identity-based.' @($elementPath)
Assert-Contract ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('AnalyzeByJSoup')) 'legado_reference' 'the pinned Legado path still delegates CSS selection to Jsoup select.' @($legadoPath)

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'post_fix_static_contract'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  preFixEvidencePath = $PreFixEvidencePath
  changedPaths = @($elementPath)
  affectedCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  affectedSourceSet = $fixture.representativeSourceSet
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  sourceHashes = [pscustomobject][ordered]@{ $elementPath = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $elementPath)).Hash.ToUpperInvariant(); $legadoPath = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $legadoPath)).Hash.ToUpperInvariant() }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_dom_selector_group_document_order_static_contract_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  closeCondition = 'R4 must execute both DOM selector-group cases, ordinal 97, the affected 243 set, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson -RelativePath $ResultPath -Value $result
$result | ConvertTo-Json -Depth 100
