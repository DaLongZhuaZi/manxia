# Cross-process device lease used by the Legado compatibility automation.
# Keep this module Windows PowerShell 5.1 compatible.

Set-StrictMode -Version Latest

$script:LeaseStreams = @{}
$script:LeaseTokens = @{}
$script:Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:Utf8Strict = New-Object System.Text.UTF8Encoding($false, $true)

function Get-LegadoDeviceLeaseSha256 {
  param([string]$Value)
  $algorithm = [System.Security.Cryptography.SHA256]::Create()
  try {
    $bytes = $script:Utf8NoBom.GetBytes($Value)
    return ([System.BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-', '')
  } finally {
    $algorithm.Dispose()
  }
}

function Get-LegadoDeviceLeaseProperty {
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

function Get-LegadoDeviceLeasePurpose {
  param(
    [string]$Transport,
    [string[]]$ArgumentList,
    [string]$ExplicitPurpose
  )
  if ($ExplicitPurpose.Length -gt 0) {
    return $ExplicitPurpose
  }

  $joinedArguments = [string]::Join(' ', @($ArgumentList))
  if ($Transport -eq 'harmony' -and $joinedArguments -match '(?i)(^|\s)aa\s+test(\s|$)') {
    return 'harmony_aa_test'
  }

  foreach ($frame in @(Get-PSCallStack)) {
    $scriptName = [string](Get-LegadoDeviceLeaseProperty -Object $frame -Name 'ScriptName')
    if ($scriptName.Length -eq 0) {
      $invocationInfo = Get-LegadoDeviceLeaseProperty -Object $frame -Name 'InvocationInfo'
      $scriptName = [string](Get-LegadoDeviceLeaseProperty -Object $invocationInfo -Name 'ScriptName')
    }
    $leafName = [System.IO.Path]::GetFileName($scriptName)
    switch ($leafName) {
      'Invoke-LegadoV2RealDeviceFlow.ps1' {
        return 'harmony_v2_real_device_flow'
      }
      'Invoke-LegadoCompatibility.ps1' {
        return 'harmony_compatibility_controller'
      }
      'Capture-LegadoUiAuditScreenshot.ps1' {
        return 'harmony_ui_audit'
      }
      'Invoke-LegadoFullDeviceReadinessAudit.ps1' {
        return 'harmony_full_source_readiness'
      }
      'Invoke-LegadoSingleSourceReference.ps1' {
        return 'android_legado_single_source_reference'
      }
      'Invoke-LegadoLiveReference.ps1' {
        return 'android_legado_live_reference'
      }
    }
  }

  if ($Transport -eq 'harmony') {
    return 'harmony_native_session'
  }
  return 'android_native_session'
}

function Get-LegadoNativeDeviceDescriptor {
  param(
    [string]$FilePath,
    [string[]]$ArgumentList,
    [string]$Purpose
  )
  $commandName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath).ToLowerInvariant()
  $transport = ''
  $selector = ''
  if ($commandName -eq 'hdc') {
    $transport = 'harmony'
    $selector = '-t'
  } elseif ($commandName -eq 'adb') {
    $transport = 'android'
    $selector = '-s'
  } else {
    return [pscustomobject][ordered]@{
      applicable = $false
      transport = ''
      purpose = ''
      deviceKeySha256 = ''
    }
  }

  $device = ''
  for ($index = 0; $index -lt $ArgumentList.Count - 1; $index++) {
    if ([string]::Equals(
      [string]$ArgumentList[$index],
      $selector,
      [System.StringComparison]::OrdinalIgnoreCase
    )) {
      $device = ([string]$ArgumentList[$index + 1]).Trim()
      break
    }
  }
  if ($device.Length -eq 0) {
    return [pscustomobject][ordered]@{
      applicable = $false
      transport = $transport
      purpose = ''
      deviceKeySha256 = ''
    }
  }

  $deviceKeySha256 = Get-LegadoDeviceLeaseSha256 -Value (
    "{0}:{1}" -f $transport, $device.ToLowerInvariant()
  )
  return [pscustomobject][ordered]@{
    applicable = $true
    transport = $transport
    purpose = Get-LegadoDeviceLeasePurpose `
      -Transport $transport `
      -ArgumentList $ArgumentList `
      -ExplicitPurpose $Purpose
    deviceKeySha256 = $deviceKeySha256
  }
}

function Get-LegadoDeviceLeaseRoot {
  $configuredRoot = [Environment]::GetEnvironmentVariable(
    'MANXIA_LEGADO_DEVICE_LEASE_ROOT',
    [EnvironmentVariableTarget]::Process
  )
  if ($null -ne $configuredRoot -and $configuredRoot.Trim().Length -gt 0) {
    return [System.IO.Path]::GetFullPath($configuredRoot.Trim())
  }
  return Join-Path ([System.IO.Path]::GetTempPath()) 'manxia-legado-device-leases'
}

function Read-LegadoDeviceLeaseOwner {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    return $null
  }
  try {
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $text = $script:Utf8Strict.GetString($bytes)
    if ($text.Trim().Length -eq 0) {
      return $null
    }
    return ConvertFrom-Json -InputObject $text
  } catch {
    return $null
  }
}

function Write-LegadoDeviceLeaseOwner {
  param([string]$Path, [object]$Owner)
  $nonce = "{0}.{1}" -f $PID, ([Guid]::NewGuid().ToString('N'))
  $temporaryPath = "$Path.tmp.$nonce"
  try {
    [System.IO.File]::WriteAllText(
      $temporaryPath,
      [string]($Owner | ConvertTo-Json -Depth 5 -Compress),
      $script:Utf8NoBom
    )
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
  }
}

function New-LegadoDeviceLeaseResult {
  param(
    [bool]$Applicable,
    [bool]$Acquired,
    [string]$Classification,
    [string]$Ownership,
    [string]$Transport,
    [string]$Purpose,
    [string]$DeviceKeySha256,
    [int]$OwnerPid,
    [string]$OwnerPurpose,
    [string]$OwnerAcquiredAt,
    [int]$WaitedMs
  )
  return [pscustomobject][ordered]@{
    applicable = $Applicable
    acquired = $Acquired
    classification = $Classification
    ownership = $Ownership
    transport = $Transport
    purpose = $Purpose
    deviceKeySha256 = $DeviceKeySha256
    ownerPid = $OwnerPid
    ownerPurpose = $OwnerPurpose
    ownerAcquiredAt = $OwnerAcquiredAt
    waitedMs = $WaitedMs
  }
}

function Enter-LegadoNativeDeviceLease {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [string[]]$ArgumentList = @(),
    [ValidateRange(1, 60)]
    [int]$TimeoutSeconds = 3,
    [string]$Purpose = ''
  )

  $startedAt = [DateTimeOffset]::UtcNow
  $descriptor = Get-LegadoNativeDeviceDescriptor `
    -FilePath $FilePath `
    -ArgumentList $ArgumentList `
    -Purpose $Purpose
  if (-not [bool]$descriptor.applicable) {
    return New-LegadoDeviceLeaseResult `
      -Applicable $false `
      -Acquired $true `
      -Classification 'not_applicable' `
      -Ownership 'none' `
      -Transport ([string]$descriptor.transport) `
      -Purpose '' `
      -DeviceKeySha256 '' `
      -OwnerPid 0 `
      -OwnerPurpose '' `
      -OwnerAcquiredAt '' `
      -WaitedMs 0
  }

  $deviceKeySha256 = [string]$descriptor.deviceKeySha256
  if ($script:LeaseStreams.ContainsKey($deviceKeySha256)) {
    return New-LegadoDeviceLeaseResult `
      -Applicable $true `
      -Acquired $true `
      -Classification 'acquired' `
      -Ownership 'process' `
      -Transport ([string]$descriptor.transport) `
      -Purpose ([string]$descriptor.purpose) `
      -DeviceKeySha256 $deviceKeySha256 `
      -OwnerPid $PID `
      -OwnerPurpose ([string]$descriptor.purpose) `
      -OwnerAcquiredAt '' `
      -WaitedMs ([int]([DateTimeOffset]::UtcNow - $startedAt).TotalMilliseconds)
  }

  $leaseRoot = Get-LegadoDeviceLeaseRoot
  [System.IO.Directory]::CreateDirectory($leaseRoot) | Out-Null
  $lockPath = Join-Path $leaseRoot "$deviceKeySha256.lock"
  $ownerPath = Join-Path $leaseRoot "$deviceKeySha256.owner.json"
  $tokenVariableName = "MANXIA_LEGADO_DEVICE_LEASE_$deviceKeySha256"
  $inheritedToken = [Environment]::GetEnvironmentVariable(
    $tokenVariableName,
    [EnvironmentVariableTarget]::Process
  )
  $deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
  $lastOwner = $null

  while ($true) {
    $stream = $null
    try {
      $stream = [System.IO.File]::Open(
        $lockPath,
        [System.IO.FileMode]::OpenOrCreate,
        [System.IO.FileAccess]::ReadWrite,
        [System.IO.FileShare]::None
      )
      $token = [Guid]::NewGuid().ToString('N')
      $owner = [pscustomobject][ordered]@{
        schemaVersion = 1
        deviceKeySha256 = $deviceKeySha256
        transport = [string]$descriptor.transport
        ownerPid = $PID
        ownerPurpose = [string]$descriptor.purpose
        acquiredAt = [DateTimeOffset]::UtcNow.ToString('o')
        token = $token
      }
      Write-LegadoDeviceLeaseOwner -Path $ownerPath -Owner $owner
      [Environment]::SetEnvironmentVariable(
        $tokenVariableName,
        $token,
        [EnvironmentVariableTarget]::Process
      )
      $script:LeaseStreams[$deviceKeySha256] = $stream
      $script:LeaseTokens[$deviceKeySha256] = $token
      return New-LegadoDeviceLeaseResult `
        -Applicable $true `
        -Acquired $true `
        -Classification 'acquired' `
        -Ownership 'process' `
        -Transport ([string]$descriptor.transport) `
        -Purpose ([string]$descriptor.purpose) `
        -DeviceKeySha256 $deviceKeySha256 `
        -OwnerPid $PID `
        -OwnerPurpose ([string]$descriptor.purpose) `
        -OwnerAcquiredAt ([string]$owner.acquiredAt) `
        -WaitedMs ([int]([DateTimeOffset]::UtcNow - $startedAt).TotalMilliseconds)
    } catch [System.IO.IOException] {
      if ($null -ne $stream) {
        $stream.Dispose()
      }
      $lastOwner = Read-LegadoDeviceLeaseOwner -Path $ownerPath
      $ownerToken = [string](Get-LegadoDeviceLeaseProperty -Object $lastOwner -Name 'token')
      if (
        $null -ne $inheritedToken -and
        $inheritedToken.Length -gt 0 -and
        [string]::Equals($inheritedToken, $ownerToken, [System.StringComparison]::Ordinal)
      ) {
        return New-LegadoDeviceLeaseResult `
          -Applicable $true `
          -Acquired $true `
          -Classification 'acquired' `
          -Ownership 'inherited' `
          -Transport ([string]$descriptor.transport) `
          -Purpose ([string]$descriptor.purpose) `
          -DeviceKeySha256 $deviceKeySha256 `
          -OwnerPid ([int](Get-LegadoDeviceLeaseProperty -Object $lastOwner -Name 'ownerPid')) `
          -OwnerPurpose ([string](Get-LegadoDeviceLeaseProperty -Object $lastOwner -Name 'ownerPurpose')) `
          -OwnerAcquiredAt ([string](Get-LegadoDeviceLeaseProperty -Object $lastOwner -Name 'acquiredAt')) `
          -WaitedMs ([int]([DateTimeOffset]::UtcNow - $startedAt).TotalMilliseconds)
      }
    } catch {
      if ($null -ne $stream) {
        $stream.Dispose()
      }
      return New-LegadoDeviceLeaseResult `
        -Applicable $true `
        -Acquired $false `
        -Classification 'device_lease_error' `
        -Ownership 'none' `
        -Transport ([string]$descriptor.transport) `
        -Purpose ([string]$descriptor.purpose) `
        -DeviceKeySha256 $deviceKeySha256 `
        -OwnerPid 0 `
        -OwnerPurpose '' `
        -OwnerAcquiredAt '' `
        -WaitedMs ([int]([DateTimeOffset]::UtcNow - $startedAt).TotalMilliseconds)
    }

    if ([DateTimeOffset]::UtcNow -ge $deadline) {
      return New-LegadoDeviceLeaseResult `
        -Applicable $true `
        -Acquired $false `
        -Classification 'device_lease_conflict' `
        -Ownership 'none' `
        -Transport ([string]$descriptor.transport) `
        -Purpose ([string]$descriptor.purpose) `
        -DeviceKeySha256 $deviceKeySha256 `
        -OwnerPid ([int](Get-LegadoDeviceLeaseProperty -Object $lastOwner -Name 'ownerPid')) `
        -OwnerPurpose ([string](Get-LegadoDeviceLeaseProperty -Object $lastOwner -Name 'ownerPurpose')) `
        -OwnerAcquiredAt ([string](Get-LegadoDeviceLeaseProperty -Object $lastOwner -Name 'acquiredAt')) `
        -WaitedMs ([int]([DateTimeOffset]::UtcNow - $startedAt).TotalMilliseconds)
    }
    Start-Sleep -Milliseconds 50
  }
}

function Exit-LegadoNativeDeviceLeases {
  [CmdletBinding()]
  param()
  foreach ($deviceKeySha256 in @($script:LeaseStreams.Keys)) {
    $stream = $script:LeaseStreams[$deviceKeySha256]
    $token = [string]$script:LeaseTokens[$deviceKeySha256]
    try {
      $stream.Dispose()
    } catch {
    }
    $leaseRoot = Get-LegadoDeviceLeaseRoot
    $ownerPath = Join-Path $leaseRoot "$deviceKeySha256.owner.json"
    $owner = Read-LegadoDeviceLeaseOwner -Path $ownerPath
    $ownerToken = [string](Get-LegadoDeviceLeaseProperty -Object $owner -Name 'token')
    if ([string]::Equals($token, $ownerToken, [System.StringComparison]::Ordinal)) {
      Remove-Item -LiteralPath $ownerPath -Force -ErrorAction SilentlyContinue
    }
    $tokenVariableName = "MANXIA_LEGADO_DEVICE_LEASE_$deviceKeySha256"
    [Environment]::SetEnvironmentVariable(
      $tokenVariableName,
      $null,
      [EnvironmentVariableTarget]::Process
    )
    [void]$script:LeaseStreams.Remove($deviceKeySha256)
    [void]$script:LeaseTokens.Remove($deviceKeySha256)
  }
}

$moduleInfo = $ExecutionContext.SessionState.Module
if ($null -ne $moduleInfo) {
  $moduleInfo.OnRemove = {
    Exit-LegadoNativeDeviceLeases
  }
}

Export-ModuleMember -Function @(
  'Enter-LegadoNativeDeviceLease',
  'Exit-LegadoNativeDeviceLeases'
)
