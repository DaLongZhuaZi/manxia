[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-index-pseudo-selectors.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-index-pseudo-selectors-pre-fix-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$fixtureFullPath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot ($FixturePath.Replace('/', '\'))))
$resultFullPath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot ($ResultPath.Replace('/', '\'))))
$evidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).TrimEnd('\') + '\'
if (-not $resultFullPath.StartsWith($evidenceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'failure witness must remain under the evidence directory.'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Assert-Witness {
  param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @())
  if (-not $Condition) { throw "237 pre-fix witness failed: $Detail" }
  $script:assertions++
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) })
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "missing JSON: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return ($strictUtf8.GetString($bytes) | ConvertFrom-Json)
}

function Get-GitSnapshot {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $gitPath = 'HEAD:' + $RelativePath.Replace('\', '/')
  $text = (& git -C $RepositoryRoot show $gitPath 2>$null | Out-String)
  if ($LASTEXITCODE -ne 0) { throw "git HEAD snapshot is missing: $RelativePath" }
  return $text
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 40), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$paths = @(
  'entry/src/main/ets/libs/htmlparser/HTMLElement.ets',
  'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
  'entry/src/main/resources/rawfile/legado_runtime.html'
)
$result = $null
$exitCode = 0
try {
  $fixture = Read-StrictJson -Path $fixtureFullPath
  $legadoHead = (& git -C (Join-Path $RepositoryRoot 'legado') rev-parse HEAD 2>$null | Out-String).Trim()
  Assert-Witness ($legadoHead -eq $legadoCommit) 'legado_commit' 'Legado checkout is pinned to the fixed commit.' @('tools/legado-compat/state/full-source-validation-state.json')
  Assert-Witness (@($fixture.cases).Count -eq 6) 'fixture_cases' 'fixture contains all six index-pseudo cases.' @($FixturePath)
  Assert-Witness ($FixturePath.EndsWith('legado-jsoup-index-pseudo-selectors.json')) 'fixture_identity' 'fixture identity is the fixed index-pseudo selector fixture.' @($FixturePath)

  $legadoSource = [System.IO.File]::ReadAllText((Join-Path $RepositoryRoot 'legado\app\src\main\java\io\legado\app\model\analyzeRule\AnalyzeByJSoup.kt'), $strictUtf8)
  Assert-Witness ($legadoSource.Contains('temp.select(ruleStr)') -and $legadoSource.Contains('getStringList')) 'legado_handoff' 'Legado delegates CSS selection and text projection to Jsoup.' @('legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt')

  $observations = New-Object 'System.Collections.Generic.List[object]'
  foreach ($path in $paths) {
    $snapshot = Get-GitSnapshot -RelativePath $path
    $hasIndexSemantics = $snapshot.Contains("pseudo.name === 'nth-of-type'") -or
      $snapshot.Contains("pseudo.name === 'eq'") -or
      $snapshot.Contains("pseudo.name === 'lt'") -or
      $snapshot.Contains('getElementTypeIndex') -or
      $snapshot.Contains('findDirectChildOccurrences') -or
      $snapshot.Contains('legadoMatchNthExpression')
    Assert-Witness (-not $hasIndexSemantics) ('head_missing_' + $path.Replace('/', '_')) ('baseline HEAD lacks the 237 index-pseudo implementation in ' + $path) @($path)
    [void]$observations.Add([pscustomobject][ordered]@{ path = $path; baselineHeadContainsIndexSemantics = $hasIndexSemantics })
  }

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    evidenceType = 'failure_witness'
    issueId = 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    baseline = [pscustomobject][ordered]@{ sourcePackageSha256 = $baselineHash; sourceCount = 458; legadoCommit = $legadoCommit; projectHead = ((& git -C $RepositoryRoot rev-parse HEAD 2>$null | Out-String).Trim()) }
    failureClass = 'v2_project_head_missing_index_pseudo_semantics'
    semantics = [pscustomobject][ordered]@{ nthOfType = '1-based same-tag an+b'; eq = '0-based elementSiblingIndex equality'; lt = 'elementSiblingIndex less than numeric argument' }
    fixture = $FixturePath
    impact = [pscustomobject][ordered]@{ ruleStringCount = 16; affectedSourceCount = 9; nthOfTypeMatchCount = 14; eqMatchCount = 2; ltMatchCount = 4 }
    observations = $observations.ToArray()
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    evidenceType = 'failure_witness'
    issueId = 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS'
    status = 'contract_error'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred'
  }
}

Write-AtomicJson -Path $resultFullPath -Value $result
$result | ConvertTo-Json -Depth 40
if ($exitCode -ne 0) { exit $exitCode }
