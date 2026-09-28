[CmdletBinding()]
param(
  [string]$SourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/r3-issue-011-url-attribute-preflight-20260809/affected-source-set.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceCount = 458
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$repositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path

function Get-RepositoryPath([string]$Path) {
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return Join-Path $repositoryRoot ($Path.Replace('/', '\'))
}

function Get-Sha256Text([string]$Value) {
  $bytes = $utf8NoBom.GetBytes($Value)
  $hash = [System.Security.Cryptography.SHA256]::Create()
  try { return ([System.BitConverter]::ToString($hash.ComputeHash($bytes))).Replace('-', '').ToUpperInvariant() }
  finally { $hash.Dispose() }
}

function Write-AtomicJson([string]$Path, [object]$Value) {
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 40), $utf8NoBom)
    Move-Item -LiteralPath $temporary -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Add-Hit(
  [System.Collections.Generic.List[object]]$Hits,
  [int]$Ordinal,
  [string]$SourceHashPrefix,
  [string]$FieldPath,
  [string]$Rule,
  [string]$Attribute,
  [string]$RuleKind
) {
  $normalized = $Rule.Trim()
  [void]$Hits.Add([ordered]@{
    ordinal = $Ordinal
    sourceIdHashPrefix = $SourceHashPrefix
    fieldPath = $FieldPath
    ruleHash = Get-Sha256Text $normalized
    ruleLength = $normalized.Length
    attribute = $Attribute.ToLowerInvariant()
    ruleKind = $RuleKind
  })
}

function Visit-Value(
  [object]$Value,
  [int]$Ordinal,
  [string]$SourceHashPrefix,
  [string]$FieldPath,
  [System.Collections.Generic.List[object]]$Hits
) {
  if ($null -eq $Value) { return }
  if ($Value -is [string]) {
    $rule = [string]$Value
    if ($rule.Trim().Length -eq 0) { return }
    $attributePattern = '(?i)(?:^|[@/])(?<attribute>href|src|data-src|data-original|data-lazy-src|data-original-src|data-url|data-img|data-cover|srcset|data-srcset)(?=$|[.@#]|##)'
    foreach ($match in [regex]::Matches($rule, $attributePattern)) {
      $prefix = $rule.Substring(0, $match.Index)
      $kind = if ($prefix -match '(?i)/@?$') { 'xpath-attribute' } else { 'css-attribute' }
      Add-Hit -Hits $Hits -Ordinal $Ordinal -SourceHashPrefix $SourceHashPrefix -FieldPath $FieldPath -Rule $rule -Attribute $match.Groups['attribute'].Value -RuleKind $kind
    }
    return
  }
  if ($Value -is [pscustomobject]) {
    foreach ($property in $Value.PSObject.Properties) {
      $childPath = if ($FieldPath.Length -eq 0) { [string]$property.Name } else { "$FieldPath.$($property.Name)" }
      Visit-Value -Value $property.Value -Ordinal $Ordinal -SourceHashPrefix $SourceHashPrefix -FieldPath $childPath -Hits $Hits
    }
    return
  }
  if ($Value -is [System.Collections.IEnumerable]) {
    $index = 0
    foreach ($item in $Value) {
      Visit-Value -Value $item -Ordinal $Ordinal -SourceHashPrefix $SourceHashPrefix -FieldPath "$FieldPath[$index]" -Hits $Hits
      $index++
    }
  }
}

$resolvedSourcePackagePath = Get-RepositoryPath $SourcePackagePath
if (-not (Test-Path -LiteralPath $resolvedSourcePackagePath -PathType Leaf)) { throw "Missing source package: $resolvedSourcePackagePath" }
$packageBytes = [System.IO.File]::ReadAllBytes($resolvedSourcePackagePath)
$packageHash = ([System.BitConverter]::ToString(([System.Security.Cryptography.SHA256]::Create()).ComputeHash($packageBytes))).Replace('-', '').ToUpperInvariant()
if ($packageHash -ne $sourceHash) { throw "Frozen source package hash drifted: $packageHash" }
$raw = $utf8Strict.GetString($packageBytes)
if ($packageBytes.Length -ge 3 -and $packageBytes[0] -eq 0xEF -and $packageBytes[1] -eq 0xBB -and $packageBytes[2] -eq 0xBF) {
  $raw = $raw.Substring(1)
}
$sources = [System.Collections.Generic.List[object]]::new()
$parsedSources = ConvertFrom-Json -InputObject $raw
foreach ($parsedSource in $parsedSources) { [void]$sources.Add($parsedSource) }
if ($sources.Count -ne $sourceCount) { throw "Unexpected source count: $($sources.Count)" }

$hits = [System.Collections.Generic.List[object]]::new()
for ($ordinal = 0; $ordinal -lt $sources.Count; $ordinal++) {
  $source = $sources[$ordinal]
  $sourceUrl = [string]$source.bookSourceUrl
  $sourceHashPrefix = (Get-Sha256Text $sourceUrl).Substring(0, 16)
  Visit-Value -Value $source -Ordinal $ordinal -SourceHashPrefix $sourceHashPrefix -FieldPath '' -Hits $hits
}

$records = @($hits | Sort-Object ordinal,fieldPath,attribute,ruleHash)
$ordinals = @($records | ForEach-Object { [int]$_.ordinal } | Sort-Object -Unique)
$result = [ordered]@{
  schemaVersion = 1
  kind = 'legado_issue_011_url_attribute_affected_source_set'
  status = 'passed_static_only'
  issueId = 'ISSUE-COMPAT-011'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $packageHash; legadoCommit = $legadoCommit }
  affectedSourceCount = $ordinals.Count
  affectedRuleOccurrenceCount = $records.Count
  affectedSourceOrdinals = @($ordinals)
  attributeCounts = [ordered]@{}
  ruleKindCounts = [ordered]@{}
  records = @($records)
  redaction = 'source ordinal, source URL hash prefix, JSON field path, rule SHA-256, length and attribute token only; raw source values omitted'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_static_affected_set_only;R4_runtime_build_device_and_legado_diff_deferred'
}
foreach ($record in $records) {
  $attribute = [string]$record.attribute
  if (-not $result.attributeCounts.Contains($attribute)) { $result.attributeCounts[$attribute] = 0 }
  $result.attributeCounts[$attribute] = [int]$result.attributeCounts[$attribute] + 1
  $kind = [string]$record.ruleKind
  if (-not $result.ruleKindCounts.Contains($kind)) { $result.ruleKindCounts[$kind] = 0 }
  $result.ruleKindCounts[$kind] = [int]$result.ruleKindCounts[$kind] + 1
}
$output = Get-RepositoryPath $OutputPath
Write-AtomicJson -Path $output -Value $result
$result | ConvertTo-Json -Depth 40
