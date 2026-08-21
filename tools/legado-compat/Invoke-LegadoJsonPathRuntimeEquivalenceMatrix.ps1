[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$SourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json',
  [string]$AffectedSetPath = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($AffectedSetPath)) {
  $AffectedSetPath = Join-Path $PSScriptRoot 'evidence\legado-jsonpath-runtime-affected-source-set-20260807.json'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $PSScriptRoot 'evidence\legado-jsonpath-runtime-equivalence-matrix-20260807.json'
}

function Get-Sha256Text {
  param([Parameter(Mandatory = $true)][string]$Value)
  $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Value)
  $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
  return ([BitConverter]::ToString($hash) -replace '-', '').ToUpperInvariant()
}

function Add-SourceString {
  param(
    [object]$Value,
    [System.Collections.Generic.Dictionary[string,string]]$Values
  )
  if ($Value -isnot [string]) { return }
  $text = [string]$Value
  if ($text -notmatch '(?i)java\.(getString|getStringList)' -or $text -notmatch '\$[.\[]') { return }
  $Values[(Get-Sha256Text -Value $text)] = $text
}

function Visit-SourceValue {
  param(
    [object]$Value,
    [System.Collections.Generic.Dictionary[string,string]]$Values
  )
  if ($null -eq $Value) { return }
  if ($Value -is [string]) {
    Add-SourceString -Value $Value -Values $Values
    return
  }
  if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
    foreach ($item in $Value) { Visit-SourceValue -Value $item -Values $Values }
    return
  }
  foreach ($property in @($Value.PSObject.Properties)) {
    Visit-SourceValue -Value $property.Value -Values $Values
  }
}

function Add-Family {
  param([System.Collections.Generic.List[string]]$Families, [string]$Family)
  if (-not $Families.Contains($Family)) { [void]$Families.Add($Family) }
}

function Get-RuleFamilies {
  param([string[]]$Patterns, [string]$RuleText)
  $families = New-Object 'System.Collections.Generic.List[string]'
  foreach ($pattern in @($Patterns)) {
    if ($pattern -match '\.\.') { Add-Family -Families $families -Family 'recursive_descent' }
    if ($pattern -match '\[\*\]') { Add-Family -Families $families -Family 'wildcard' }
    if ($pattern -match '\[\d+\]') { Add-Family -Families $families -Family 'array_index' }
  }
  $pathTokens = [regex]::Matches($RuleText, '\$(?:\.|\[)[A-Za-z0-9_$.\[\]\-:*?,''"@=<>!&|]+') | ForEach-Object { $_.Value }
  foreach ($pathToken in @($pathTokens)) {
    if ($pathToken -match '\|\|\s*\$') { Add-Family -Families $families -Family 'alternative_or' }
    if ($pathToken -match '&&\s*\$') { Add-Family -Families $families -Family 'concatenation_and' }
    if ($pathToken -match '%%\s*\$') { Add-Family -Families $families -Family 'zip_merge' }
    if ($pathToken -match '##') { Add-Family -Families $families -Family 'regex_replacement' }
    if ($pathToken -match '\[\?\(') { Add-Family -Families $families -Family 'filter_predicate' }
    if ($pathToken -match '\[[^\]]*:\s*[^\]]*\]') { Add-Family -Families $families -Family 'array_slice' }
    if ($pathToken -match '\[[''\"]') { Add-Family -Families $families -Family 'quoted_key' }
  }
  if ($families.Count -eq 0) { Add-Family -Families $families -Family 'scalar_path' }
  return $families.ToArray()
}

$raw = [System.IO.File]::ReadAllText($SourcePackagePath, [System.Text.UTF8Encoding]::new($false, $true))
$sources = @($raw | ConvertFrom-Json)
$affected = Get-Content -LiteralPath $AffectedSetPath -Raw -Encoding utf8 | ConvertFrom-Json
if ($sources.Count -ne 458 -or [int]$affected.sourceCount -ne 458) { throw 'JSONPath matrix baseline is not the pinned 458-source package' }
if ((Get-Sha256Text -Value $raw) -ne [string]$affected.sourcePackageSha256) { throw 'JSONPath matrix source package hash mismatch' }

$sourceStrings = [System.Collections.Generic.Dictionary[string,string]]::new([System.StringComparer]::Ordinal)
foreach ($source in $sources) { Visit-SourceValue -Value $source -Values $sourceStrings }

$coveredFamilies = @('scalar_path', 'wildcard', 'array_index', 'array_slice', 'recursive_descent', 'alternative_or', 'concatenation_and', 'zip_merge', 'regex_replacement', 'quoted_key')
$records = New-Object 'System.Collections.Generic.List[object]'
foreach ($record in @($affected.records)) {
  $families = New-Object 'System.Collections.Generic.List[string]'
  $missingRawRule = $false
  foreach ($hit in @($record.hits)) {
    $hash = [string]$hit.valueSha256
    $ruleText = ''
    if ($sourceStrings.ContainsKey($hash)) { $ruleText = $sourceStrings[$hash] } else { $missingRawRule = $true }
    foreach ($family in @(Get-RuleFamilies -Patterns @($hit.jsonPathPatterns) -RuleText $ruleText)) {
      Add-Family -Families $families -Family $family
    }
  }
  $unsupportedFamilies = @($families | Where-Object { $_ -notin $coveredFamilies })
  $coverage = if ($missingRawRule) {
    'unclassified_raw_rule_missing'
  } elseif ($unsupportedFamilies.Count -gt 0) {
    'requires_runtime_extension'
  } else {
    'covered_by_deterministic_runtime_fixture'
  }
  [void]$records.Add([pscustomobject][ordered]@{
    ordinal = [int]$record.ordinal
    sourceId = [string]$record.sourceId
    sourceNameSha256 = Get-Sha256Text -Value ([string]$record.sourceName)
    hitCount = [int]$record.hitCount
    syntaxFamilies = $families.ToArray()
    unsupportedFamilies = $unsupportedFamilies
    coverage = $coverage
    semanticStatus = 'reference_pending'
  })
}

$familyCounts = [ordered]@{}
foreach ($family in @($records | ForEach-Object { $_.syntaxFamilies } | Sort-Object -Unique)) {
  $familyCounts[$family] = @($records | Where-Object { $_.syntaxFamilies -contains $family }).Count
}
$coverageCounts = [ordered]@{}
foreach ($coverage in @($records.coverage | Sort-Object -Unique)) {
  $coverageCounts[$coverage] = @($records | Where-Object { $_.coverage -eq $coverage }).Count
}
$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  generatedAt = [DateTime]::UtcNow.ToString("yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'")
  sourcePackageSha256 = Get-Sha256Text -Value $raw
  sourceCount = $sources.Count
  affectedSourceCount = $records.Count
  sourceNamePolicy = 'sha256_only'
  grammarBasis = @(
    'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSonPath.kt',
    'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeRule.kt'
  )
  deterministicFixtureContracts = @(
    'legado_jsonpath_runtime_execution',
    'legado_jsonpath_runtime_extended_execution'
  )
  familyCounts = $familyCounts
  coverageCounts = $coverageCounts
  referenceInstrumentation = 'pending_fresh_androidtest_apk'
  records = $records.ToArray()
}
$directory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
$temporaryPath = "$OutputPath.tmp-$PID"
[System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 16), [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::Move($temporaryPath, $OutputPath, $true)
$result | Select-Object schemaVersion,sourceCount,affectedSourceCount,familyCounts,coverageCounts,referenceInstrumentation | ConvertTo-Json -Depth 8 -Compress
