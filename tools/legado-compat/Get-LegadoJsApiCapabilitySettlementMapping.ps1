[CmdletBinding()]
param(
  [string]$SourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json',
  [string]$MatrixPath = '',
  [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'

function Write-Utf8Atomic {
  param([string]$Path, [string]$Content)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) {
    [void][System.IO.Directory]::CreateDirectory($directory)
  }
  $temporaryPath = "$Path.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, $Content, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      [System.IO.File]::Delete($temporaryPath)
    }
  }
}

function Get-Sha256Hex {
  param([string]$Value)
  $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Value)
  return [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes))
}

function Get-SourceHashPrefix {
  param([string]$SourceUrl)
  return (Get-Sha256Hex -Value $SourceUrl).Substring(0, 16)
}

function Mask-NonExecutableText {
  param([string]$Code)
  $urlMasked = [regex]::Replace($Code, 'https?://[^\s''"`\\<>{}]+', {
      param([System.Text.RegularExpressions.Match]$Match)
      return ' ' * $Match.Value.Length
    })
  $result = [System.Text.StringBuilder]::new()
  $mode = 0
  $escaped = $false
  $templateExpressionDepth = 0
  $returnToTemplate = $false
  for ($index = 0; $index -lt $urlMasked.Length; $index++) {
    $character = $urlMasked[$index]
    $next = if ($index + 1 -lt $urlMasked.Length) { $urlMasked[$index + 1] } else { [char]0 }
    if ($mode -eq 1 -or $mode -eq 2) {
      $maskedCharacter = ' '
      if ($character -eq "`n") { $maskedCharacter = "`n" }
      [void]$result.Append($maskedCharacter)
      if ($escaped) { $escaped = $false }
      elseif ($character -eq '\\') { $escaped = $true }
      elseif (($mode -eq 1 -and $character -eq "'") -or ($mode -eq 2 -and $character -eq '"')) { $mode = 0 }
      continue
    }
    if ($mode -eq 3) {
      if ($character -eq '`') {
        [void]$result.Append(' ')
        $mode = 0
        $returnToTemplate = $false
        $templateExpressionDepth = 0
      } elseif ($character -eq '$' -and $next -eq '{') {
        [void]$result.Append('  ')
        $index++
        $mode = 0
        $returnToTemplate = $true
        $templateExpressionDepth = 1
      } else {
        $maskedCharacter = ' '
        if ($character -eq "`n") { $maskedCharacter = "`n" }
        [void]$result.Append($maskedCharacter)
      }
      continue
    }
    if ($mode -eq 4) {
      $maskedCharacter = ' '
      if ($character -eq "`n") { $maskedCharacter = "`n" }
      [void]$result.Append($maskedCharacter)
      if ($character -eq "`n") { $mode = 0 }
      continue
    }
    if ($mode -eq 5) {
      $maskedCharacter = ' '
      if ($character -eq "`n") { $maskedCharacter = "`n" }
      [void]$result.Append($maskedCharacter)
      if ($character -eq '*' -and $next -eq '/') {
        [void]$result.Append(' ')
        $index++
        $mode = 0
      }
      continue
    }
    if ($character -eq "'") {
      [void]$result.Append(' ')
      $mode = 1
      $escaped = $false
      continue
    }
    if ($character -eq '"') {
      [void]$result.Append(' ')
      $mode = 2
      $escaped = $false
      continue
    }
    if ($character -eq '`') {
      [void]$result.Append(' ')
      $mode = 3
      continue
    }
    if ($character -eq '/' -and $next -eq '/') {
      [void]$result.Append('  ')
      $index++
      $mode = 4
      continue
    }
    if ($character -eq '/' -and $next -eq '*') {
      [void]$result.Append('  ')
      $index++
      $mode = 5
      continue
    }
    if ($returnToTemplate -and $character -eq '{') {
      $templateExpressionDepth++
    } elseif ($returnToTemplate -and $character -eq '}') {
      $templateExpressionDepth--
      if ($templateExpressionDepth -eq 0) {
        [void]$result.Append(' ')
        $mode = 3
        continue
      }
    }
    [void]$result.Append($character)
  }
  return $result.ToString()
}

function Get-RuleFamily {
  param([string]$Path)
  $parts = @($Path -split '\.')
  for ($index = $parts.Count - 1; $index -ge 0; $index--) {
    $part = $parts[$index] -replace '\[\d+\]$', ''
    if ($part -match '^(searchUrl|exploreUrl|bookInfo|toc|content|ruleSearch|ruleExplore|ruleBookInfo|ruleToc|ruleContent|ruleReview|ruleFile|preUpdateJs|formatJs|loginUrl|coverRule|chapterBaseUrl|downloadUrls|payAction|imageDecode)$') {
      return $part
    }
  }
  return (($parts[$parts.Count - 1]) -replace '\[\d+\]$', '')
}

function Get-ReferenceKind {
  param([string]$Path)
  $leaf = (($Path -split '\.')[-1]) -replace '\[\d+\]$', ''
  if ($leaf -match '^(bookSourceComment|bookSourceName|customOrder|weight|enabled)$') {
    return 'COMMENT_OR_METADATA'
  }
  if ($leaf -match '^(jsLib|loginCheckJs|loginUi|preUpdateJs|formatJs|callBackJs|imageDecode|payAction|searchUrl|exploreUrl|loginUrl|header|coverRule|chapterBaseUrl|downloadUrls|bookUrl|tocUrl|content|bookList|chapterList|rule.*)$') {
    return 'EXECUTABLE_OR_RULE_FIELD'
  }
  return 'OTHER_FIELD'
}

function Visit-SourceValue {
  param(
    [object]$Value,
    [string]$Path,
    [int]$Ordinal,
    [string]$SourceHashPrefix,
    [int]$BookSourceType,
    [System.Collections.Generic.HashSet[string]]$UnregisteredApis,
    [System.Collections.Generic.List[object]]$Matches
  )
  if ($null -eq $Value) { return }
  if ($Value -is [string]) {
    $text = [string]$Value
    $masked = Mask-NonExecutableText -Code $text
    $tokenMatches = [regex]::Matches($masked, '(?:Packages\.)?(?:java|source|android|javax|org)\.[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)*')
    foreach ($tokenMatch in $tokenMatches) {
      $api = [string]$tokenMatch.Value
      if ($api.StartsWith('Packages.')) { $api = $api.Substring('Packages.'.Length) }
      if (-not $UnregisteredApis.Contains($api)) { continue }
      $following = $tokenMatch.Index + $tokenMatch.Length
      while ($following -lt $masked.Length -and [char]::IsWhiteSpace($masked[$following])) { $following++ }
      $isCallLike = $following -lt $masked.Length -and $masked[$following] -eq '('
      [void]$Matches.Add([pscustomobject][ordered]@{
          api = $api
          sourceOrdinal = $Ordinal
          sourceHashPrefix = $SourceHashPrefix
          bookSourceType = $BookSourceType
          fieldPath = $Path
          ruleFamily = Get-RuleFamily -Path $Path
          referenceKind = Get-ReferenceKind -Path $Path
          callLike = $isCallLike
          occurrenceCount = 1
          valueLength = $text.Length
          maskedCodeSha256 = Get-Sha256Hex -Value $masked
        })
    }
    return
  }
  if ($Value -is [pscustomobject]) {
    foreach ($property in $Value.PSObject.Properties) {
      $childPath = if ($Path.Length -eq 0) { [string]$property.Name } else { "$Path.$($property.Name)" }
      Visit-SourceValue -Value $property.Value -Path $childPath -Ordinal $Ordinal -SourceHashPrefix $SourceHashPrefix -BookSourceType $BookSourceType -UnregisteredApis $UnregisteredApis -Matches $Matches
    }
    return
  }
  if ($Value -is [System.Collections.IEnumerable]) {
    $index = 0
    foreach ($item in $Value) {
      Visit-SourceValue -Value $item -Path "$Path[$index]" -Ordinal $Ordinal -SourceHashPrefix $SourceHashPrefix -BookSourceType $BookSourceType -UnregisteredApis $UnregisteredApis -Matches $Matches
      $index++
    }
  }
}

if ($MatrixPath.Length -eq 0) {
  $MatrixPath = Join-Path $PSScriptRoot 'evidence\legado-js-api-usage-matrix.json'
}
if ($ResultPath.Length -eq 0) {
  $ResultPath = Join-Path $PSScriptRoot 'evidence\r3-js-api-capability-settlement-preflight-20260809\reference-mapping.json'
}
if (-not (Test-Path -LiteralPath $SourcePackagePath -PathType Leaf)) { throw "Missing source package: $SourcePackagePath" }
if (-not (Test-Path -LiteralPath $MatrixPath -PathType Leaf)) { throw "Missing API matrix: $MatrixPath" }

$sourcePackageBytes = [System.IO.File]::ReadAllBytes($SourcePackagePath)
$sourcePackageHash = (Get-FileHash -LiteralPath $SourcePackagePath -Algorithm SHA256).Hash
if ($sourcePackageHash -ne $sourceHash) { throw "Source package hash drift: $sourcePackageHash" }
$raw = [System.Text.UTF8Encoding]::new($false, $true).GetString($sourcePackageBytes)
$sources = @($raw | ConvertFrom-Json)
if ($sources.Count -ne 458) { throw "Unexpected source count: $($sources.Count)" }
$matrix = [System.Text.UTF8Encoding]::new($false, $true).GetString([System.IO.File]::ReadAllBytes($MatrixPath)) | ConvertFrom-Json
if ([string]$matrix.sourcePackageSha256 -ne $sourceHash -or [int]$matrix.sourceCount -ne 458) { throw 'API matrix baseline drift.' }
$unregisteredRows = @($matrix.apiReferences | Where-Object { [string]$_.classification -eq 'unregistered' })
$unregisteredApis = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($row in $unregisteredRows) { [void]$unregisteredApis.Add([string]$row.api) }
if ($unregisteredApis.Count -ne 44) { throw "Unexpected unregistered API count: $($unregisteredApis.Count)" }

$matches = New-Object 'System.Collections.Generic.List[object]'
for ($ordinal = 0; $ordinal -lt $sources.Count; $ordinal++) {
  $source = $sources[$ordinal]
  $sourceUrl = [string]$source.bookSourceUrl
  $sourceHashPrefix = Get-SourceHashPrefix -SourceUrl $sourceUrl
  $bookSourceType = [int]$source.bookSourceType
  Visit-SourceValue -Value $source -Path '' -Ordinal $ordinal -SourceHashPrefix $sourceHashPrefix -BookSourceType $bookSourceType -UnregisteredApis $unregisteredApis -Matches $matches
}

$mappedApis = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($match in $matches) { [void]$mappedApis.Add([string]$match.api) }
$unmappedApis = @($unregisteredApis | Where-Object { -not $mappedApis.Contains($_) } | Sort-Object)
if ($unmappedApis.Count -gt 0) { throw ('Unmapped unregistered APIs: {0}' -f ($unmappedApis -join ', ')) }

$byApi = @{}
foreach ($api in ($mappedApis | Sort-Object)) {
  $apiMatches = @($matches | Where-Object { [string]$_.api -eq $api })
  $matrixOccurrences = [int](($unregisteredRows | Where-Object { [string]$_.api -eq $api }).occurrences | Measure-Object -Sum).Sum
  $mappedOccurrences = [int](($apiMatches | Measure-Object -Property occurrenceCount -Sum).Sum)
  if ($matrixOccurrences -ne $mappedOccurrences) {
    throw "Occurrence drift for ${api}: matrix=$matrixOccurrences mapping=$mappedOccurrences"
  }
  $byApi[$api] = [pscustomobject][ordered]@{
    occurrenceCount = $matrixOccurrences
    mappedOccurrenceCount = $mappedOccurrences
    sourceCount = @($apiMatches | Select-Object -ExpandProperty sourceOrdinal -Unique).Count
    executableReferenceCount = @($apiMatches | Where-Object { [string]$_.referenceKind -eq 'EXECUTABLE_OR_RULE_FIELD' }).Count
    metadataReferenceCount = @($apiMatches | Where-Object { [string]$_.referenceKind -eq 'COMMENT_OR_METADATA' }).Count
    callLikeReferenceCount = @($apiMatches | Where-Object { [bool]$_.callLike }).Count
    references = $apiMatches
  }
}

$referenceKindCounts = [pscustomobject][ordered]@{
  executableOrRuleField = @($matches | Where-Object { [string]$_.referenceKind -eq 'EXECUTABLE_OR_RULE_FIELD' }).Count
  commentOrMetadata = @($matches | Where-Object { [string]$_.referenceKind -eq 'COMMENT_OR_METADATA' }).Count
  otherField = @($matches | Where-Object { [string]$_.referenceKind -eq 'OTHER_FIELD' }).Count
  callLike = @($matches | Where-Object { [bool]$_.callLike }).Count
}

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_r3_js_api_capability_settlement_reference_mapping'
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  sourcePackageSha256 = $sourcePackageHash
  sourceCount = $sources.Count
  legadoCommit = $legadoCommit
  matrixPath = 'tools/legado-compat/evidence/legado-js-api-usage-matrix.json'
  unregisteredApiCount = $unregisteredApis.Count
  matrixUniqueApiCount = @($unregisteredRows).Count
  mappedApiCount = $mappedApis.Count
  mappedReferenceCount = $matches.Count
  matrixReferenceCount = [int](($unregisteredRows.occurrences | Measure-Object -Sum).Sum)
  referenceKindCounts = $referenceKindCounts
  unmappedApis = @($unmappedApis)
  apiMappings = $byApi
  redaction = [pscustomobject][ordered]@{
    excluded = @('raw JSON values', 'source names', 'URLs', 'script bodies', 'Cookie', 'account', 'book正文')
    retained = @('source ordinal', 'URL hash prefix', 'JSON field path', 'rule family', 'occurrence count', 'length', 'masked code SHA-256', 'bookSourceType')
  }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  candidateIssueCount = 0
  nextAction = '对已映射 API 逐项读取固定 Legado 实现并建立 V2 全消费者矩阵；证据齐全前保持 037 verifying。'
}
Write-Utf8Atomic -Path $ResultPath -Content ($result | ConvertTo-Json -Depth 30)
Write-Output ('JS_API_CAPABILITY_MAPPING status=passed apis={0} references={1} unmapped={2} evidence={3} runtimeActions=0 semanticMatchAllowed=false' -f $mappedApis.Count, $matches.Count, $unmappedApis.Count, $ResultPath)
