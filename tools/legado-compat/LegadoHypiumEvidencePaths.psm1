Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-LegadoHypiumCanonicalEvidenceDirectory {
  param([Parameter(Mandatory = $true)][string]$ScriptRoot)
  return [System.IO.Path]::GetFullPath((Join-Path $ScriptRoot 'evidence\full-source-v2-hypium-device'))
}

function Get-LegadoHypiumEvidenceRoot {
  param([Parameter(Mandatory = $true)][string]$ScriptRoot)
  return [System.IO.Path]::GetFullPath((Join-Path $ScriptRoot 'evidence'))
}

function Get-LegadoHypiumSafeRunToken {
  param([string]$RunToken = '')
  $candidate = $RunToken.Trim()
  if ($candidate.Length -eq 0) {
    $candidate = '{0}-{1}-{2}' -f [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(), $PID, ([Guid]::NewGuid().ToString('N').Substring(0, 12))
  }
  if ($candidate -notmatch '^[A-Za-z0-9_-]{1,96}$') {
    throw 'HYPIUM_EVIDENCE_RUN_TOKEN_INVALID'
  }
  return $candidate
}

function New-LegadoHypiumRunEvidenceDirectory {
  param(
    [Parameter(Mandatory = $true)][string]$ScriptRoot,
    [string]$RunToken = ''
  )
  $token = Get-LegadoHypiumSafeRunToken -RunToken $RunToken
  $evidenceRoot = Get-LegadoHypiumEvidenceRoot -ScriptRoot $ScriptRoot
  $directory = [System.IO.Path]::GetFullPath((Join-Path $evidenceRoot ('full-source-v2-hypium-device-run-' + $token)))
  $canonical = Get-LegadoHypiumCanonicalEvidenceDirectory -ScriptRoot $ScriptRoot
  if ($directory.Equals($canonical, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'BASELINE_EVIDENCE_WRITE_FORBIDDEN'
  }
  return $directory
}

function Assert-LegadoHypiumRunEvidenceDirectory {
  param(
    [Parameter(Mandatory = $true)][string]$ScriptRoot,
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory
  )
  $directory = [System.IO.Path]::GetFullPath($EvidenceDirectory)
  $canonical = Get-LegadoHypiumCanonicalEvidenceDirectory -ScriptRoot $ScriptRoot
  if ($directory.Equals($canonical, [System.StringComparison]::OrdinalIgnoreCase) -or
      $directory.StartsWith($canonical + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'BASELINE_EVIDENCE_WRITE_FORBIDDEN'
  }
  return $directory
}

function Assert-LegadoHypiumEffectiveEvidenceDirectory {
  param(
    [Parameter(Mandatory = $true)][string]$EvidenceRoot,
    [Parameter(Mandatory = $true)][string]$BaselineEvidenceDirectory,
    [Parameter(Mandatory = $true)][string]$EffectiveEvidenceDirectory
  )
  $root = [System.IO.Path]::GetFullPath($EvidenceRoot).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  $baseline = [System.IO.Path]::GetFullPath($BaselineEvidenceDirectory).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  $effective = [System.IO.Path]::GetFullPath($EffectiveEvidenceDirectory).TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
  if ($effective.Equals($baseline, [System.StringComparison]::OrdinalIgnoreCase) -or
      $effective.StartsWith($baseline + [System.IO.Path]::DirectorySeparatorChar, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'EFFECTIVE_EVIDENCE_DIRECTORY_COLLIDES_WITH_BASELINE'
  }
  if ($effective.Equals($root, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'EFFECTIVE_EVIDENCE_DIRECTORY_INVALID'
  }
  $rootPrefix = $root + [System.IO.Path]::DirectorySeparatorChar
  if (-not $effective.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'EFFECTIVE_EVIDENCE_DIRECTORY_OUTSIDE_ROOT'
  }
  return $effective
}

function Assert-LegadoHypiumRunActivityPath {
  param(
    [Parameter(Mandatory = $true)][string]$EvidenceDirectory,
    [Parameter(Mandatory = $true)][string]$RunActivityPath
  )
  $directory = [System.IO.Path]::GetFullPath($EvidenceDirectory)
  $path = [System.IO.Path]::GetFullPath($RunActivityPath)
  $prefix = $directory + [System.IO.Path]::DirectorySeparatorChar
  if (-not $path.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'RUN_ACTIVITY_PATH_OUTSIDE_RUN_DIRECTORY'
  }
  return $path
}

function ConvertTo-LegadoHypiumEvidenceRelativePath {
  param(
    [Parameter(Mandatory = $true)][string]$ScriptRoot,
    [Parameter(Mandatory = $true)][string]$Path
  )
  $root = Get-LegadoHypiumEvidenceRoot -ScriptRoot $ScriptRoot
  return ([System.IO.Path]::GetRelativePath($root, [System.IO.Path]::GetFullPath($Path))).Replace('\', '/')
}

Export-ModuleMember -Function @(
  'Get-LegadoHypiumCanonicalEvidenceDirectory',
  'Get-LegadoHypiumEvidenceRoot',
  'Get-LegadoHypiumSafeRunToken',
  'New-LegadoHypiumRunEvidenceDirectory',
  'Assert-LegadoHypiumRunEvidenceDirectory',
  'Assert-LegadoHypiumEffectiveEvidenceDirectory',
  'Assert-LegadoHypiumRunActivityPath',
  'ConvertTo-LegadoHypiumEvidenceRelativePath'
)
