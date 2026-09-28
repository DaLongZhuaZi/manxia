[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$SourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-combination-r4-context.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-combination-r4-fixture-20260810.json'
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
$script:checks = New-Object 'System.Collections.Generic.List[object]'

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
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
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
  try { return (($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Value)) | ForEach-Object { $_.ToString('x2') }) -join '').ToUpperInvariant() }
  finally { $sha.Dispose() }
}

function Add-Check {
  param([string]$Id, [bool]$Passed, [string]$Detail)
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; passed = $Passed; detail = $Detail })
  $script:assertions++
  if (-not $Passed) { throw "243 R4 fixture contract failed: $Id; $Detail" }
}

function Visit-SourceValue {
  param([object]$Value, [string]$Path, [int]$Ordinal, [System.Collections.Generic.List[object]]$Hits)
  if ($null -eq $Value) { return }
  if ($Value -is [string]) {
    $complex = $Value -match '(?is):has\(' -and $Value -match '(?is):matchesOwn\(' -and $Value -match '(?is):not\(' -and $Value.Contains('~=') -and $Value.Contains('>')
    if (-not $complex) { return }
    foreach ($match in [regex]::Matches($Value, '(?i):only-child(?=\(|[\s>@,\)\]:]|$)')) {
      $start = [Math]::Max(0, $match.Index - 140)
      $length = [Math]::Min(360, $Value.Length - $start)
      [void]$Hits.Add([pscustomobject][ordered]@{
          ordinal = $Ordinal
          path = $Path
          occurrenceOffset = $match.Index
          ruleSha256 = Get-Sha256Text -Value $Value
          context = $Value.Substring($start, $length).Replace("`r", ' ').Replace("`n", ' ')
        })
    }
    return
  }
  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
    $index = 0
    foreach ($item in $Value) { Visit-SourceValue -Value $item -Path "$Path[$index]" -Ordinal $Ordinal -Hits $Hits; $index++ }
    return
  }
  foreach ($property in $Value.PSObject.Properties) { Visit-SourceValue -Value $property.Value -Path "$Path.$($property.Name)" -Ordinal $Ordinal -Hits $Hits }
}

$outputFullPath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot ($OutputPath.Replace('/', '\'))))
$evidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidenceRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Fixture contract evidence must remain under the evidence directory.' }

$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -Path (Get-RepoPath 'tools/legado-compat/state/full-source-validation-state.json')
  $fixture = Read-StrictJson -Path (Get-RepoPath $FixturePath)
  $sourceText = Read-StrictText -Path $SourcePackagePath
  $sources = @($sourceText | ConvertFrom-Json -Depth 100)
  $sourceHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourcePackagePath).Hash.ToUpperInvariant()

  Add-Check 'baseline' ($sourceHash -eq $baselineHash -and $sources.Count -eq 458 -and [int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen source, machine baseline and Legado commit agree.'
  Add-Check 'active_issue' ([string]$state.governance.activeIssueId -eq $issueId -and [string]$state.governance.status -eq 'running') '243 remains the sole active source issue.'
  Add-Check 'fixture_identity' ([string]$fixture.fixtureKind -eq 'legado_jsoup_standard_pseudo_combination_r4_source_node_fixture' -and [string]$fixture.issueId -eq $issueId -and [string]$fixture.status -eq 'registered_static_only') 'fixture identity and static-only status are explicit.'
  Add-Check 'fixture_policy' (-not [bool]$fixture.semanticMatchAllowed -and @($fixture.runtimeActionsPerformed).Count -eq 0 -and [string]$fixture.qualificationPolicy -match 'deferred_to_R4') 'fixture cannot claim runtime qualification.'
  Add-Check 'fixture_shape' (@($fixture.sourceOrdinals).Count -eq 2 -and @($fixture.sourceOrdinals) -contains 357 -and @($fixture.sourceOrdinals) -contains 402 -and [int]$fixture.sourceOccurrenceCount -eq 5) 'fixture contains the required 357/402 source shape.'

  $hits = New-Object 'System.Collections.Generic.List[object]'
  foreach ($ordinal in @(357, 402)) { Visit-SourceValue -Value $sources[$ordinal - 1] -Path ('$[' + $ordinal + ']') -Ordinal $ordinal -Hits $hits }
  Add-Check 'source_occurrence_count' ($hits.Count -eq 5 -and @($hits | Where-Object { $_.ordinal -eq 357 }).Count -eq 3 -and @($hits | Where-Object { $_.ordinal -eq 402 }).Count -eq 2) 'frozen source occurrence counts are 357=3 and 402=2.'
  $fixtureOccurrences = @($fixture.sourceOccurrences)
  Add-Check 'source_occurrence_records' ($fixtureOccurrences.Count -eq $hits.Count) 'fixture occurrence record count matches frozen source extraction.'
  for ($index = 0; $index -lt $hits.Count; $index++) {
    $actual = $hits[$index]
    $record = $fixtureOccurrences[$index]
    Add-Check ("occurrence_{0}" -f $index) ([int]$record.ordinal -eq [int]$actual.ordinal -and [string]$record.path -eq [string]$actual.path -and [int]$record.occurrenceOffset -eq [int]$actual.occurrenceOffset -and [string]$record.ruleSha256 -eq [string]$actual.ruleSha256 -and [string]$record.context -eq [string]$actual.context) 'fixture occurrence is byte-derived from the frozen rule node.'
  }
  $cases = @($fixture.cases)
  Add-Check 'case_shape' ($cases.Count -eq 5 -and @($cases | Where-Object { [string]$_.expectedStatus -ne 'deferred_to_r4_legado_runtime_diff' }).Count -eq 0 -and @($cases | Where-Object { $null -ne $_.expected }).Count -eq 0) 'all cases remain explicitly deferred without inferred output.'

  $fixtureFullPath = Get-RepoPath $FixturePath
  $fixtureHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $fixtureFullPath).Hash.ToUpperInvariant()
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    evidenceType = 'r4_source_node_fixture_contract'
    issueId = $issueId
    status = 'passed_static_only'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
    fixturePath = $FixturePath
    fixtureSha256 = $fixtureHash
    sourceOccurrenceCount = $hits.Count
    assertions = $script:assertions
    checks = @($script:checks.ToArray())
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_fixture_contract_static_only;R4_runtime_and_legado_diff_deferred'
    nextGate = 'R4 must execute all five source-node cases against Legado and every V2 consumer path.'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{ schemaVersion = 1; evidenceType = 'r4_source_node_fixture_contract'; issueId = $issueId; status = 'failed'; generatedAt = [DateTimeOffset]::UtcNow.ToString('o'); failure = $_.Exception.Message; assertions = $script:assertions; checks = @($script:checks.ToArray()); runtimeActionsPerformed = @(); semanticMatchAllowed = $false }
}
Write-AtomicJson -Path $outputFullPath -Value $result
$result | ConvertTo-Json -Depth 100
if ($exitCode -ne 0) { exit $exitCode }
