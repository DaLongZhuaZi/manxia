[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$SourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-combination-r4-context.json',
  [string]$EvidencePath = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-combination-r4-fixture-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$script:assertions = 0

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing file: $Path" }
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

function Write-AtomicJson {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][object]$Value
  )
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Get-Sha256Text {
  param([Parameter(Mandatory = $true)][string]$Value)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    return (($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Value)) | ForEach-Object { $_.ToString('x2') }) -join '').ToUpperInvariant()
  } finally {
    $sha.Dispose()
  }
}

function Assert-Fixture {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "243 R4 fixture registration failed: $Message" }
  $script:assertions++
}

function Visit-SourceValue {
  param(
    [object]$Value,
    [string]$Path,
    [int]$Ordinal,
    [System.Collections.Generic.List[object]]$Hits
  )
  if ($null -eq $Value) { return }
  if ($Value -is [string]) {
    $complex = $Value -match '(?is):has\(' -and
      $Value -match '(?is):matchesOwn\(' -and
      $Value -match '(?is):not\(' -and
      $Value.Contains('~=') -and
      $Value.Contains('>')
    if (-not $complex) { return }
    foreach ($match in [regex]::Matches($Value, '(?i):only-child(?=\(|[\s>@,\)\]:]|$)')) {
      $start = [Math]::Max(0, $match.Index - 140)
      $length = [Math]::Min(360, $Value.Length - $start)
      $context = $Value.Substring($start, $length).Replace("`r", ' ').Replace("`n", ' ')
      [void]$Hits.Add([pscustomobject][ordered]@{
          ordinal = $Ordinal
          path = $Path
          occurrenceOffset = $match.Index
          ruleSha256 = Get-Sha256Text -Value $Value
          context = $context
          requiredCombinations = @('standard-only-child', 'has-relative-selector', 'text-matches-own', 'not-selector', 'regex-attribute', 'direct-child-or-sibling')
        })
    }
    return
  }
  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
    $index = 0
    foreach ($item in $Value) {
      Visit-SourceValue -Value $item -Path "$Path[$index]" -Ordinal $Ordinal -Hits $Hits
      $index++
    }
    return
  }
  foreach ($property in $Value.PSObject.Properties) {
    Visit-SourceValue -Value $property.Value -Path "$Path.$($property.Name)" -Ordinal $Ordinal -Hits $Hits
  }
}

$fixtureFullPath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot ($FixturePath.Replace('/', '\'))))
$evidenceFullPath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot ($EvidencePath.Replace('/', '\'))))
$evidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).TrimEnd('\') + '\'
if (-not $evidenceFullPath.StartsWith($evidenceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Fixture evidence must remain under the evidence directory.'
}

$state = Read-StrictJson -Path (Get-RepoPath 'tools/legado-compat/state/full-source-validation-state.json')
$sourceText = Read-StrictText -Path $SourcePackagePath
$sources = @($sourceText | ConvertFrom-Json -Depth 100)
$sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourcePackagePath).Hash.ToUpperInvariant()
Assert-Fixture ($sourceHash -eq $baselineHash) 'frozen source package hash drifted.'
Assert-Fixture ($sources.Count -eq 458) 'frozen source package count drifted.'
Assert-Fixture ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline drifted.'
Assert-Fixture ([string]$state.governance.activeIssueId -eq $issueId -and [string]$state.governance.status -eq 'running') '243 is not the active source issue.'
Assert-Fixture ((& git -C (Get-RepoPath 'legado') rev-parse HEAD 2>$null | Out-String).Trim() -eq $legadoCommit) 'Legado checkout is not pinned.'

$hits = New-Object 'System.Collections.Generic.List[object]'
foreach ($ordinal in @(357, 402)) {
  Visit-SourceValue -Value $sources[$ordinal - 1] -Path ('$[' + $ordinal + ']') -Ordinal $ordinal -Hits $hits
}
Assert-Fixture ($hits.Count -eq 5) 'expected exactly five exact nested-combination occurrences.'
Assert-Fixture (@($hits | Where-Object { $_.ordinal -eq 357 }).Count -eq 3) 'ordinal 357 occurrence count drifted.'
Assert-Fixture (@($hits | Where-Object { $_.ordinal -eq 402 }).Count -eq 2) 'ordinal 402 occurrence count drifted.'
Assert-Fixture (@($hits | Select-Object -ExpandProperty path -Unique).Count -eq 3) 'nested-combination source paths drifted.'

$cases = New-Object 'System.Collections.Generic.List[object]'
$caseIndex = 0
foreach ($hit in $hits) {
  $caseIndex++
  [void]$cases.Add([pscustomobject][ordered]@{
      id = ('ordinal-{0}-nested-occurrence-{1}' -f $hit.ordinal, $caseIndex)
      sourceOrdinal = $hit.ordinal
      sourcePath = $hit.path
      occurrenceOffset = $hit.occurrenceOffset
      ruleSha256 = $hit.ruleSha256
      selectorContext = $hit.context
      expectedStatus = 'deferred_to_r4_legado_runtime_diff'
      expected = $null
      semantics = 'Exact frozen source-node conjunction; do not infer runtime output from this static fixture.'
    })
}

$fixture = [pscustomobject][ordered]@{
  schemaVersion = 1
  fixtureKind = 'legado_jsoup_standard_pseudo_combination_r4_source_node_fixture'
  issueId = $issueId
  status = 'registered_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  sourceOrdinals = @(357, 402)
  sourceOccurrenceCount = $hits.Count
  requiredCombinationSet = @('standard-only-child', 'has-relative-selector', 'text-matches-own', 'not-selector', 'regex-attribute', 'direct-child-or-sibling')
  sourceOccurrences = @($hits.ToArray())
  cases = @($cases.ToArray())
  qualificationPolicy = 'source_node_exactness_only;expected_outputs_and_cross_engine_equivalence_deferred_to_R4'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  nextAction = 'Use these frozen source-node cases to construct the R4 Legado/V2 runtime differential; no production patch is justified by this registration alone.'
}
Write-AtomicJson -Path $fixtureFullPath -Value $fixture
$fixtureHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $fixtureFullPath).Hash.ToUpperInvariant()

$evidence = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'r4_source_node_fixture_registration'
  issueId = $issueId
  status = 'passed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  fixtureSha256 = $fixtureHash
  sourceOrdinals = @(357, 402)
  sourceOccurrenceCount = $hits.Count
  occurrenceCounts = [ordered]@{ ordinal357 = @($hits | Where-Object { $_.ordinal -eq 357 }).Count; ordinal402 = @($hits | Where-Object { $_.ordinal -eq 402 }).Count }
  assertions = $script:assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_fixture_registration_static_only;R4_runtime_and_legado_diff_deferred'
  nextGate = 'R4 must execute all five frozen source-node cases against Legado and every V2 consumer path before semantic qualification.'
}
Write-AtomicJson -Path $evidenceFullPath -Value $evidence
$evidence | ConvertTo-Json -Depth 100
