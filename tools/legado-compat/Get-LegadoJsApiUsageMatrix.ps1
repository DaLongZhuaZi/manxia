[CmdletBinding()]
param(
  [string]$SourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json',
  [string]$RegistryPath = '',
  [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Utf8Atomic {
  param([string]$Path, [string]$Content)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) {
    [void][System.IO.Directory]::CreateDirectory($directory)
  }
  $temporary = "$Path.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  [System.IO.File]::WriteAllText($temporary, $Content, [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporary -Destination $Path -Force
}

function Get-SourceHashToken {
  param([string]$SourceUrl)
  $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($SourceUrl)
  return [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).Substring(0, 16)
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

function Get-NearestRegistration {
  param([string]$Api, [System.Collections.Generic.HashSet[string]]$Registrations)
  $candidate = $Api
  while ($candidate.Contains('.')) {
    if ($Registrations.Contains($candidate)) { return $candidate }
    $candidate = $candidate.Substring(0, $candidate.LastIndexOf('.'))
  }
  return ''
}

function Visit-SourceValue {
  param(
    [object]$Value,
    [string]$SourceToken,
    [hashtable]$Counts,
    [hashtable]$Samples
  )
  if ($null -eq $Value) { return }
  if ($Value -is [string]) {
    $masked = Mask-NonExecutableText -Code $Value
    $matches = [regex]::Matches($masked, '(?:Packages\.)?(?:java|source|android|javax|org)\.[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)*')
    foreach ($match in $matches) {
      $api = $match.Value
      if ($api.StartsWith('Packages.')) { $api = $api.Substring('Packages.'.Length) }
      if (-not $Counts.ContainsKey($api)) {
        $Counts[$api] = 0
        $Samples[$api] = $SourceToken
      }
      $Counts[$api] = [int]$Counts[$api] + 1
    }
    return
  }
  if ($Value -is [pscustomobject]) {
    foreach ($property in $Value.PSObject.Properties) {
      Visit-SourceValue -Value $property.Value -SourceToken $SourceToken -Counts $Counts -Samples $Samples
    }
    return
  }
  if ($Value -is [System.Collections.IEnumerable]) {
    foreach ($item in $Value) {
      Visit-SourceValue -Value $item -SourceToken $SourceToken -Counts $Counts -Samples $Samples
    }
  }
}

if ($RegistryPath.Length -eq 0) {
  $repoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
  $RegistryPath = Join-Path $repoRoot 'entry\src\main\ets\Framework\Novel\LegadoJsApiContractRegistry.ets'
}
if ($ResultPath.Length -eq 0) {
  $ResultPath = Join-Path $PSScriptRoot 'evidence\legado-js-api-usage-matrix.json'
}
if (-not (Test-Path -LiteralPath $SourcePackagePath -PathType Leaf)) { throw "Missing source package: $SourcePackagePath" }
if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) { throw "Missing registry: $RegistryPath" }

$raw = [System.IO.File]::ReadAllText($SourcePackagePath, [System.Text.UTF8Encoding]::new($false, $true))
$sources = @($raw | ConvertFrom-Json)
if ($sources.Count -ne 458) { throw "Unexpected source count: $($sources.Count)" }
$registryText = [System.IO.File]::ReadAllText($RegistryPath, [System.Text.UTF8Encoding]::new($false, $true))
$registrations = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
foreach ($match in [regex]::Matches($registryText, "this\.add\('([^']+)',\s*LegadoJsApiStatus\.([A-Z_]+)")) {
  $registrations[$match.Groups[1].Value] = $match.Groups[2].Value
}
$registrationNames = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
foreach ($registrationName in $registrations.Keys) {
  [void]$registrationNames.Add($registrationName)
}
$counts = @{}
$samples = @{}
foreach ($source in $sources) {
  $sourceUrl = [string]$source.bookSourceUrl
  Visit-SourceValue -Value $source -SourceToken (Get-SourceHashToken -SourceUrl $sourceUrl) -Counts $counts -Samples $samples
}

$rows = New-Object 'System.Collections.Generic.List[object]'
$exactCount = 0
$prefixCount = 0
$unregisteredCount = 0
$supportedExactCount = 0
$supportedPrefixCount = 0
$nonRunnableExactCount = 0
$nonRunnablePrefixCount = 0
$unsupportedExactCount = 0
$unsupportedPrefixCount = 0
foreach ($api in @($counts.Keys | Sort-Object)) {
  $registration = Get-NearestRegistration -Api $api -Registrations $registrationNames
  $classification = 'unregistered'
  $contractStatus = ''
  if ($registration.Length -gt 0) {
    $contractStatus = $registrations[$registration]
    if ($registration -eq $api) {
      $exactCount++
      if ($contractStatus -eq 'SUPPORTED') {
        $classification = 'supported_exact'
        $supportedExactCount++
      } elseif ($contractStatus -eq 'UNSUPPORTED_API') {
        $classification = 'unsupported_exact'
        $unsupportedExactCount++
      } else {
        $classification = 'non_runnable_exact'
        $nonRunnableExactCount++
      }
    } else {
      $prefixCount++
      if ($contractStatus -eq 'SUPPORTED') {
        $classification = 'supported_prefix'
        $supportedPrefixCount++
      } elseif ($contractStatus -eq 'UNSUPPORTED_API') {
        $classification = 'unsupported_prefix'
        $unsupportedPrefixCount++
      } else {
        $classification = 'non_runnable_prefix'
        $nonRunnablePrefixCount++
      }
    }
  } else {
    $unregisteredCount++
  }
  [void]$rows.Add([pscustomobject][ordered]@{
      api = $api
      occurrences = [int]$counts[$api]
      sourceHashPrefix = [string]$samples[$api]
      classification = $classification
      registeredContract = $registration
      contractStatus = $contractStatus
    })
}

$payload = [pscustomobject][ordered]@{
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  sourcePackageSha256 = (Get-FileHash -LiteralPath $SourcePackagePath -Algorithm SHA256).Hash
  sourceCount = $sources.Count
  registryPath = $RegistryPath
  registrationCount = $registrations.Count
  summary = [pscustomobject][ordered]@{
    apiReferenceCount = $rows.Count
    supportedExact = $supportedExactCount
    supportedPrefix = $supportedPrefixCount
    nonRunnableExact = $nonRunnableExactCount
    nonRunnablePrefix = $nonRunnablePrefixCount
    unsupportedExact = $unsupportedExactCount
    unsupportedPrefix = $unsupportedPrefixCount
    # Legacy registration counts remain for historical trend charts only.
    # They must never be interpreted as executable compatibility.
    registeredExact = $exactCount
    registeredPrefix = $prefixCount
    unregistered = $unregisteredCount
  }
  apiReferences = $rows.ToArray()
}
Write-Utf8Atomic -Path $ResultPath -Content ($payload | ConvertTo-Json -Depth 8)
$payload | ConvertTo-Json -Depth 8
