[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$SourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-no-space-direct-child-fast-path-context.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/v2-jsoup-no-space-direct-child-fast-path-source-scope-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'

function Get-RepoPath([string]$RelativePath) { if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $RelativePath }; return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictJson([string]$Path) {
  $bytes = [System.IO.File]::ReadAllBytes((Get-RepoPath $Path))
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return ([System.Text.UTF8Encoding]::new($false, $true).GetString($bytes) | ConvertFrom-Json -Depth 100)
}
function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepoPath $RelativePath
  $temp = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try { [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temp -Destination $path -Force }
  finally { if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) } }
}
function Add-Candidate([string]$Value, [string]$Path, [int]$Ordinal) {
  foreach ($match in [regex]::Matches($Value, '(?im)(?:^|[\r\n|&])\s*(?:@css:)?[.#][^\r\n\s,@|&]+>[^\r\n\s,@|&]+')) {
    $selector = $match.Value.Trim()
    if ($selector.Length -gt 0 -and $selector -notmatch '(?i)replace\(|function|eval\(|=>|;|##|\$1|\\u|\bvar\b|\breturn\b|match\(|map\(') {
        [void]$script:candidates.Add([pscustomobject][ordered]@{ ordinal = $Ordinal; path = $Path; selector = $selector })
    }
  }
}
function Walk([object]$Value, [string]$Path, [int]$Ordinal) {
  if ($null -eq $Value) { return }
  if ($Value -is [string]) { if ($Path -match '\.(ruleSearch|ruleExplore|ruleBookInfo|ruleToc)\.') { Add-Candidate ([string]$Value) $Path $Ordinal }; return }
  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [System.Collections.IDictionary])) {
    $index = 0
    foreach ($item in $Value) { Walk $item "$Path[$index]" $Ordinal; $index++ }
    return
  }
  foreach ($property in $Value.PSObject.Properties) {
    $childPath = if ($Path) { "$Path.$($property.Name)" } else { $property.Name }
    Walk $property.Value $childPath $Ordinal
  }
}

$packageAbsolutePath = Get-RepoPath $SourcePackagePath
$packageBytes = [System.IO.File]::ReadAllBytes($packageAbsolutePath)
$actualHash = (Get-FileHash -LiteralPath $packageAbsolutePath -Algorithm SHA256).Hash.ToUpperInvariant()
if ($actualHash -ne $sourceHash) { throw 'Frozen source package hash drifted.' }
$sources = ([System.Text.UTF8Encoding]::new($false, $true).GetString($packageBytes) | ConvertFrom-Json -Depth 100)
if (@($sources).Count -ne 458) { throw 'Frozen source package count drifted.' }
$script:candidates = [System.Collections.Generic.List[object]]::new()
$ordinal = 1
foreach ($source in $sources) { Walk $source ('$[' + ($ordinal - 1) + ']') $ordinal; $ordinal++ }
$unique = @($script:candidates | Sort-Object ordinal,path,selector | Select-Object -Unique ordinal,path,selector)
$affectedOrdinals = @($unique | Select-Object -ExpandProperty ordinal -Unique | Sort-Object {[int]$_})
$fixture = Read-StrictJson $FixturePath
if ([string]$fixture.issueId -ne $issueId -or [int]$fixture.baseline.sourceCount -ne 458 -or [string]$fixture.baseline.sourcePackageSha256 -ne $sourceHash -or [string]$fixture.baseline.legadoCommit -ne $legadoCommit) { throw 'Fixture baseline or issue binding drifted.' }
if ($unique.Count -ne 30 -or $affectedOrdinals.Count -ne 18) { throw ('Unexpected no-space direct-child scope: rules={0};sources={1}' -f $unique.Count,$affectedOrdinals.Count) }
if ((@($fixture.affectedSourceOrdinals | ForEach-Object {[int]$_}) -join ',') -ne ($affectedOrdinals -join ',')) { throw 'Fixture affected source ordinals do not match the frozen package audit.' }

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'source_scope_static_audit'
  issueId = $issueId
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  sourcePackagePath = $SourcePackagePath
  sourcePackageSha256 = $actualHash
  selectionPolicy = 'ruleSearch/ruleExplore/ruleBookInfo/ruleToc strings; no-space class/id CSS candidate; top-level > match; exclude JS and replacement expressions.'
  affectedSourceOrdinals = $affectedOrdinals
  affectedRuleStringCount = $unique.Count
  rules = $unique
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_source_scope_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  closeCondition = 'R4 must replay this source-scope audit and execute the resulting 18-source/30-rule set before 243 can leave verifying.'
}
Write-AtomicJson $ResultPath $result
$result | ConvertTo-Json -Depth 80
