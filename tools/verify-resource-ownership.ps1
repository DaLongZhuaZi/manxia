[CmdletBinding()]
param(
  [string]$ProjectRoot = (Split-Path -Parent $PSScriptRoot)
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resourceModules = @(
  'entry',
  'manxia-ui-resources',
  'manxia-theme',
  'manxia-reader-ui',
  'manxia-features-ui',
  'manxia-source-engine',
  'manxia-network',
  'manxia-novel'
)

$owners = @{}
$hashOwners = @{}
$errors = [System.Collections.Generic.List[string]]::new()
$warnings = [System.Collections.Generic.List[string]]::new()

function Add-Owner([string]$key, [string]$owner) {
  if (-not $owners.ContainsKey($key)) {
    $owners[$key] = @()
  }
  $owners[$key] += $owner
}

function Add-HashOwner([string]$hash, [string]$owner) {
  if (-not $hashOwners.ContainsKey($hash)) {
    $hashOwners[$hash] = @()
  }
  $hashOwners[$hash] += $owner
}

function Get-ModuleName([string]$owner) {
  return $owner.Substring(0, $owner.IndexOf('/'))
}

function Test-ResourceOwner([string]$key, [string]$location) {
  if (-not $owners.ContainsKey($key)) {
    $errors.Add("Missing resource owner for $key referenced by $location")
  }
}

foreach ($module in $resourceModules) {
  $resourceRoot = Join-Path $ProjectRoot "$module/src/main/resources"
  if (-not (Test-Path -LiteralPath $resourceRoot)) {
    continue
  }

  $mediaRoot = Join-Path $resourceRoot 'base/media'
  if (Test-Path -LiteralPath $mediaRoot) {
    foreach ($file in @(Get-ChildItem -LiteralPath $mediaRoot -Recurse -File -Force)) {
      $relativePath = $file.FullName.Substring($resourceRoot.Length + 1).Replace('\', '/')
      Add-Owner "app.media.$($file.BaseName)" "$module/$relativePath"
      Add-HashOwner (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash "$module/$relativePath"
    }
  }

  foreach ($elementFile in @(Get-ChildItem -LiteralPath $resourceRoot -Recurse -File -Force | Where-Object {
    $_.FullName -match '[\\/]element[\\/]' -and $_.Extension -eq '.json'
  })) {
    $relativePath = $elementFile.FullName.Substring($resourceRoot.Length + 1).Replace('\', '/')
    try {
      $json = Get-Content -LiteralPath $elementFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
      foreach ($property in $json.psobject.Properties) {
        foreach ($item in @($property.Value)) {
          if ($null -ne $item.name) {
            Add-Owner "app.$($property.Name).$($item.name)" "$module/$relativePath"
          }
        }
      }
    } catch {
      $errors.Add("Invalid resource JSON: $module/$relativePath :: $($_.Exception.Message)")
    }
  }
}

foreach ($key in @($owners.Keys)) {
  $moduleSet = @($owners[$key] | ForEach-Object { Get-ModuleName $_ } | Sort-Object -Unique)
  if ($moduleSet.Count -gt 1) {
    $errors.Add("Resource key owned by multiple modules: $key :: $($owners[$key] -join ', ')")
  }
}

foreach ($hash in @($hashOwners.Keys)) {
  $moduleSet = @($hashOwners[$hash] | ForEach-Object { Get-ModuleName $_ } | Sort-Object -Unique)
  if ($moduleSet.Count -gt 1) {
    $errors.Add("Duplicate binary across modules: $hash :: $($hashOwners[$hash] -join ', ')")
  } elseif ($hashOwners[$hash].Count -gt 1) {
    $warnings.Add("Duplicate binary within one module: $($hashOwners[$hash] -join ', ')")
  }
}

$sourceRoots = @(
  'entry/src/main/ets',
  'manxia-core/src/main/ets',
  'manxia-ui-resources/src/main/ets',
  'manxia-theme/src/main/ets',
  'manxia-reader-ui/src/main/ets',
  'manxia-features-ui/src/main/ets',
  'manxia-source-engine/src/main/ets',
  'manxia-network/src/main/ets',
  'manxia-novel/src/main/ets'
)

foreach ($sourceRoot in $sourceRoots) {
  $absoluteRoot = Join-Path $ProjectRoot $sourceRoot
  if (-not (Test-Path -LiteralPath $absoluteRoot)) {
    continue
  }

  foreach ($sourceFile in @(Get-ChildItem -LiteralPath $absoluteRoot -Recurse -File -Filter '*.ets')) {
    $relativeSource = $sourceFile.FullName.Substring($ProjectRoot.Length + 1).Replace('\', '/')
    $text = Get-Content -LiteralPath $sourceFile.FullName -Raw -Encoding UTF8

    if ($text -match '\$r\s*\(\s*[\x27\"]app\.(?:media|color|string)\.[^\x27\"]+[\x27\"]\s*\)') {
      $staticMatches = [regex]::Matches($text, '\$r\s*\(\s*[\x27\"](?<key>app\.(?:media|color|string)\.[A-Za-z0-9_]+)[\x27\"]\s*\)')
      foreach ($match in $staticMatches) {
        Test-ResourceOwner $match.Groups['key'].Value $relativeSource
      }
    }

    if ($text -match '\$r\s*\(\s*`') {
      $errors.Add("Dynamic $r() expression is forbidden: $relativeSource")
    }
  }
}

$coreResources = Join-Path $ProjectRoot 'manxia-core/src/main/resources'
if (Test-Path -LiteralPath $coreResources) {
  $errors.Add('manxia-core must not contain src/main/resources')
}

$entryModule = Join-Path $ProjectRoot 'entry/src/main/module.json5'
if (Test-Path -LiteralPath $entryModule) {
  $moduleText = Get-Content -LiteralPath $entryModule -Raw -Encoding UTF8
  $moduleMatches = [regex]::Matches($moduleText, '\$(?<type>media|color|string):(?<name>[A-Za-z0-9_]+)')
  foreach ($match in $moduleMatches) {
    Test-ResourceOwner "app.$($match.Groups['type'].Value).$($match.Groups['name'].Value)" 'entry/src/main/module.json5'
  }
}

Write-Output "Resource keys checked: $($owners.Count)"
Write-Output "Binary hashes checked: $($hashOwners.Count)"
foreach ($warning in $warnings) {
  Write-Warning $warning
}

if ($errors.Count -gt 0) {
  foreach ($errorMessage in $errors) {
    Write-Error $errorMessage
  }
  exit 1
}

Write-Output 'Resource ownership verification passed.'
