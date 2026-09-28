# Shared native-process boundary for the Legado compatibility automation.
# Keep this file Windows PowerShell 5.1 compatible: do not use ArgumentList,
# Process.Kill(Boolean), or APIs introduced after .NET Framework 4.5.

Set-StrictMode -Version Latest

$deviceLeaseModulePath = Join-Path $PSScriptRoot 'LegadoDeviceLease.psm1'
if (-not (Test-Path -LiteralPath $deviceLeaseModulePath)) {
  throw "Native device lease module does not exist: $deviceLeaseModulePath"
}
$loadedDeviceLeaseModule = @(
  Get-Module | Where-Object {
    [string]::Equals(
      [string]$_.Path,
      $deviceLeaseModulePath,
      [System.StringComparison]::OrdinalIgnoreCase
    )
  }
) | Select-Object -First 1
if ($null -eq $loadedDeviceLeaseModule) {
  Import-Module -Name $deviceLeaseModulePath -ErrorAction Stop
}

if ($null -eq ('LegadoNativeProcessJob' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public sealed class LegadoNativeProcessJob : IDisposable
{
    private IntPtr handle;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateJobObject(IntPtr securityAttributes, string name);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool TerminateJobObject(IntPtr job, uint exitCode);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool CloseHandle(IntPtr handle);

    public LegadoNativeProcessJob()
    {
        handle = CreateJobObject(IntPtr.Zero, null);
        if (handle == IntPtr.Zero)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error());
        }
    }

    public bool Assign(IntPtr processHandle)
    {
        if (!AssignProcessToJobObject(handle, processHandle))
        {
            return false;
        }
        return true;
    }

    public bool Terminate(uint exitCode)
    {
        if (handle == IntPtr.Zero)
        {
            return false;
        }
        return TerminateJobObject(handle, exitCode);
    }

    public void Dispose()
    {
        if (handle != IntPtr.Zero)
        {
            CloseHandle(handle);
            handle = IntPtr.Zero;
        }
        GC.SuppressFinalize(this);
    }
}
'@
}

function ConvertTo-LegadoNativeArgument {
  param([AllowNull()][string]$Value)
  if ($null -eq $Value -or $Value.Length -eq 0) {
    return '""'
  }
  if ($Value -notmatch '[\s"]') {
    return $Value
  }

  # Quote according to the CommandLineToArgvW escaping rules used by the
  # Windows executables involved in the compatibility runners.
  $builder = New-Object System.Text.StringBuilder
  [void]$builder.Append('"')
  $backslashes = 0
  for ($index = 0; $index -lt $Value.Length; $index++) {
    $character = $Value[$index]
    if ($character -eq '\') {
      $backslashes++
      continue
    }
    if ($character -eq '"') {
      [void]$builder.Append(('\' * (($backslashes * 2) + 1)))
      [void]$builder.Append('"')
      $backslashes = 0
      continue
    }
    if ($backslashes -gt 0) {
      [void]$builder.Append(('\' * $backslashes))
      $backslashes = 0
    }
    [void]$builder.Append($character)
  }
  if ($backslashes -gt 0) {
    [void]$builder.Append(('\' * ($backslashes * 2)))
  }
  [void]$builder.Append('"')
  return $builder.ToString()
}

function ConvertTo-LegadoNativeCommandLine {
  param([string[]]$ArgumentList)
  if ($null -eq $ArgumentList -or $ArgumentList.Count -eq 0) {
    return ''
  }
  $parts = New-Object 'System.Collections.Generic.List[string]'
  foreach ($argument in $ArgumentList) {
    [void]$parts.Add((ConvertTo-LegadoNativeArgument -Value $argument))
  }
  return [string]::Join(' ', $parts.ToArray())
}

function ConvertTo-LegadoCmdToken {
  param([AllowNull()][string]$Value)
  if ($null -eq $Value) {
    return '""'
  }
  # Every token is quoted so cmd metacharacters stay data. Percent expansion
  # is disabled by doubling percent signs in the one-shot command string.
  $escaped = $Value.Replace('%', '%%').Replace('"', '""')
  return '"' + $escaped + '"'
}

function Stop-LegadoNativeProcessTree {
  param(
    [Parameter(Mandatory = $true)]
    [System.Diagnostics.Process]$Process
  )
  if ($Process.HasExited) {
    return
  }

  # taskkill is available on supported Windows hosts and is the only
  # PS5.1-safe way to terminate descendants of hdc/adb/Gradle wrappers.
  $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
  if (Test-Path -LiteralPath $taskkill) {
    try {
      $killer = New-Object System.Diagnostics.Process
      $killerInfo = New-Object System.Diagnostics.ProcessStartInfo
      $killerInfo.FileName = $taskkill
      $killerInfo.Arguments = "/PID $($Process.Id) /T /F"
      $killerInfo.UseShellExecute = $false
      $killerInfo.CreateNoWindow = $true
      $killer.StartInfo = $killerInfo
      [void]$killer.Start()
      if (-not $killer.WaitForExit(5000)) {
        try { $killer.Kill() } catch { }
      }
      $killer.Dispose()
    } catch {
      # Fall through to the direct process kill below.  The timeout result is
      # still reported even when Windows cannot enumerate descendants.
    }
  }
  try {
    if (-not $Process.HasExited) {
      $Process.Kill()
    }
  } catch {
  }
}

function Get-LegadoNativeHostExecutable {
  $candidateName = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
  $candidate = Join-Path $PSHOME $candidateName
  if (Test-Path -LiteralPath $candidate) {
    return $candidate
  }
  $process = Get-Process -Id $PID -ErrorAction SilentlyContinue
  if ($null -ne $process -and $process.Path -and (Test-Path -LiteralPath $process.Path)) {
    return [string]$process.Path
  }
  throw "Unable to locate the current PowerShell host: $candidateName"
}

function Invoke-LegadoNativeProcess {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [string[]]$ArgumentList = @(),
    [ValidateRange(1, 86400)]
    [int]$TimeoutSeconds = 30,
    [ValidateRange(1, 60)]
    [int]$DeviceLeaseTimeoutSeconds = 3,
    [string]$WorkingDirectory = '',
    [AllowNull()][string]$StandardInput = $null,
    [string]$RawArguments = ''
  )

  if (-not (Test-Path -LiteralPath $FilePath)) {
    throw "Native command does not exist: $FilePath"
  }

  $startedAt = [DateTimeOffset]::UtcNow
  $deviceLease = Enter-LegadoNativeDeviceLease `
    -FilePath $FilePath `
    -ArgumentList $ArgumentList `
    -TimeoutSeconds $DeviceLeaseTimeoutSeconds
  if ([bool]$deviceLease.applicable -and -not [bool]$deviceLease.acquired) {
    $leaseMessage = (
      "DEVICE_LEASE_FAILURE classification={0};transport={1};deviceKeySha256={2};" +
      "ownerPid={3};ownerPurpose={4};waitedMs={5}"
    ) -f @(
      [string]$deviceLease.classification,
      [string]$deviceLease.transport,
      [string]$deviceLease.deviceKeySha256,
      [int]$deviceLease.ownerPid,
      [string]$deviceLease.ownerPurpose,
      [int]$deviceLease.waitedMs
    )
    return [pscustomobject][ordered]@{
      command = [System.IO.Path]::GetFileName($FilePath)
      arguments = @($ArgumentList)
      stdout = ''
      stderr = $leaseMessage
      output = $leaseMessage
      exitCode = -1
      timedOut = $false
      classification = [string]$deviceLease.classification
      termination = 'not_started_device_lease_failure'
      processTreeIsolated = $false
      timeoutSeconds = $TimeoutSeconds
      durationMs = [int]([DateTimeOffset]::UtcNow - $startedAt).TotalMilliseconds
      deviceLease = $deviceLease
    }
  }

  $processInfo = New-Object System.Diagnostics.ProcessStartInfo
  $processInfo.FileName = $FilePath
  $processInfo.Arguments = if ($RawArguments.Length -gt 0) {
    $RawArguments
  } else {
    ConvertTo-LegadoNativeCommandLine -ArgumentList $ArgumentList
  }
  $processInfo.UseShellExecute = $false
  $processInfo.CreateNoWindow = $true
  $processInfo.RedirectStandardOutput = $true
  $processInfo.RedirectStandardError = $true
  $processInfo.RedirectStandardInput = $null -ne $StandardInput
  if ($WorkingDirectory.Length -gt 0) {
    $processInfo.WorkingDirectory = $WorkingDirectory
  }

  $process = New-Object System.Diagnostics.Process
  $process.StartInfo = $processInfo
  $timedOut = $false
  $exitCode = -1
  $termination = 'not_started'
  $processJob = $null
  $jobAssigned = $false
  $stdoutTask = $null
  $stderrTask = $null
  $stdout = ''
  $stderr = ''
  try {
    if (-not $process.Start()) {
      throw "Native command could not start: $FilePath"
    }
    try {
      $processJob = New-Object LegadoNativeProcessJob
      $jobAssigned = $processJob.Assign($process.Handle)
    } catch {
      $jobAssigned = $false
    }
    $termination = 'exited'
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if ($null -ne $StandardInput) {
      $process.StandardInput.Write($StandardInput)
      $process.StandardInput.Close()
    }
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
      $timedOut = $true
      $termination = 'timeout_terminated'
      if ($jobAssigned -and $null -ne $processJob) {
        [void]$processJob.Terminate(124)
      }
      Stop-LegadoNativeProcessTree -Process $process
      [void]$process.WaitForExit(5000)
    }
    if ($process.HasExited) {
      $exitCode = $process.ExitCode
      # A second wait flushes the asynchronous output callbacks without
      # blocking on a still-running child after timeout termination.
      [void]$process.WaitForExit(5000)
    }
    if ($null -ne $stdoutTask -and $stdoutTask.Wait(5000)) {
      $stdout = [string]$stdoutTask.Result
    }
    if ($null -ne $stderrTask -and $stderrTask.Wait(5000)) {
      $stderr = [string]$stderrTask.Result
    }
  } catch {
    if (-not $timedOut) {
      $termination = 'start_or_capture_error'
    }
    throw
  } finally {
    if ($null -ne $processJob) {
      $processJob.Dispose()
    }
    $process.Dispose()
  }

  $combined = if ($stderr.Length -eq 0) { $stdout } elseif ($stdout.Length -eq 0) { $stderr } else { "$stdout`r`n$stderr" }
  $classification = if ($timedOut) { 'timeout' } elseif ($exitCode -eq 0) { 'success' } else { 'nonzero_exit' }
  $durationMs = [int]([DateTimeOffset]::UtcNow - $startedAt).TotalMilliseconds
  return [pscustomobject][ordered]@{
    command = [System.IO.Path]::GetFileName($FilePath)
    arguments = @($ArgumentList)
    stdout = $stdout
    stderr = $stderr
    output = $combined
    exitCode = $exitCode
    timedOut = $timedOut
    classification = $classification
    termination = $termination
    processTreeIsolated = $jobAssigned
    timeoutSeconds = $TimeoutSeconds
    durationMs = $durationMs
    deviceLease = $deviceLease
  }
}

function Invoke-LegadoBatchProcess {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$FilePath,
    [string[]]$ArgumentList = @(),
    [ValidateRange(1, 86400)]
    [int]$TimeoutSeconds = 30,
    [string]$WorkingDirectory = '',
    [AllowNull()][string]$StandardInput = $null
  )
  if (-not (Test-Path -LiteralPath $FilePath)) {
    throw "Batch command does not exist: $FilePath"
  }
  $commandParts = New-Object 'System.Collections.Generic.List[string]'
  [void]$commandParts.Add('call')
  [void]$commandParts.Add((ConvertTo-LegadoCmdToken -Value $FilePath))
  foreach ($argument in $ArgumentList) {
    [void]$commandParts.Add((ConvertTo-LegadoCmdToken -Value $argument))
  }
  $command = [string]::Join(' ', $commandParts.ToArray())
  $rawArguments = '/d /s /c "' + $command + '"'
  $commandProcessor = Join-Path $env:SystemRoot 'System32\cmd.exe'
  $result = Invoke-LegadoNativeProcess `
    -FilePath $commandProcessor `
    -TimeoutSeconds $TimeoutSeconds `
    -WorkingDirectory $WorkingDirectory `
    -StandardInput $StandardInput `
    -RawArguments $rawArguments
  $result.command = [System.IO.Path]::GetFileName($FilePath)
  $result.arguments = @($ArgumentList)
  return $result
}
