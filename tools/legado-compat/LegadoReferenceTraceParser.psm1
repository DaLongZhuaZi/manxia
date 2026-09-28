Set-StrictMode -Version Latest

function Get-LegadoReferenceTraceProperty {
  param([object]$Object, [string]$Name)
  if ($null -eq $Object) {
    return $null
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) {
    return $null
  }
  return $property.Value
}

function Read-LegadoReferenceTraceRecords {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyCollection()]
    [AllowEmptyString()]
    [string[]]$Lines,
    [string]$AttemptIdPattern = '^[A-F0-9]{64}/[0-9]{1,2}$'
  )

  $records = [System.Collections.Generic.Dictionary[string, object]]::new([System.StringComparer]::Ordinal)
  $parts = @{}
  $expectedPartCount = 0
  $legacyPayload = ''
  $collectingLegacyPayload = $false

  foreach ($line in $Lines) {
    $text = [string]$line
    $partMatch = [regex]::Match($text, 'LEGADO_LIVE_TRACE_PART:(\d{1,2})/(\d{1,2}):(.*)$')
    if ($partMatch.Success) {
      $partIndex = [int]$partMatch.Groups[1].Value
      $partCount = [int]$partMatch.Groups[2].Value
      if ($partCount -le 0 -or $partCount -gt 32 -or $partIndex -le 0 -or $partIndex -gt $partCount) {
        continue
      }
      if ($partIndex -eq 1 -or ($expectedPartCount -ne 0 -and $expectedPartCount -ne $partCount)) {
        $parts = @{}
        $expectedPartCount = 0
      }
      $expectedPartCount = $partCount
      $parts[$partIndex] = $partMatch.Groups[3].Value
      if ($parts.Count -ne $expectedPartCount) {
        continue
      }

      $builder = New-Object System.Text.StringBuilder
      $complete = $true
      for ($index = 1; $index -le $expectedPartCount; $index++) {
        if (-not $parts.ContainsKey($index)) {
          $complete = $false
          break
        }
        [void]$builder.Append([string]$parts[$index])
      }
      if ($complete -and $builder.Length -le 98304) {
        try {
          $record = $builder.ToString() | ConvertFrom-Json
          $attemptId = [string](Get-LegadoReferenceTraceProperty -Object $record -Name 'attemptId')
          if ($attemptId -match $AttemptIdPattern) {
            $records[$attemptId] = $record
          }
        } catch {
          # A complete but malformed fragment sequence is not reference evidence.
        }
      }
      $parts = @{}
      $expectedPartCount = 0
      continue
    }

    $markerIndex = $text.IndexOf('LEGADO_LIVE_TRACE:', [System.StringComparison]::Ordinal)
    if ($markerIndex -ge 0) {
      $legacyPayload = $text.Substring($markerIndex + 'LEGADO_LIVE_TRACE:'.Length)
      $collectingLegacyPayload = $true
    } elseif ($collectingLegacyPayload) {
      # Legacy instrumentation emitted one payload. Android may split it into
      # raw continuation records; the JSON itself has no intentional newlines.
      $legacyPayload = $legacyPayload + $text.Trim()
    } else {
      continue
    }

    if ($legacyPayload.Length -gt 98304) {
      $legacyPayload = ''
      $collectingLegacyPayload = $false
      continue
    }
    try {
      $record = $legacyPayload | ConvertFrom-Json
      $attemptId = [string](Get-LegadoReferenceTraceProperty -Object $record -Name 'attemptId')
      if ($attemptId -match $AttemptIdPattern) {
        $records[$attemptId] = $record
      }
      $legacyPayload = ''
      $collectingLegacyPayload = $false
    } catch {
      # Continue only until a bounded payload can be parsed or a new marker
      # starts a replacement candidate.
    }
  }

  return ,$records
}

Export-ModuleMember -Function Read-LegadoReferenceTraceRecords
