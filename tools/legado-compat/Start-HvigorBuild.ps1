[CmdletBinding()]
param(
  [ValidateSet('assembleApp', 'assembleHap')]
  [string]$Task = 'assembleApp',
  [string]$Product = 'default',
  [string]$BuildMode = 'debug',
  [string]$EvidenceDirectory = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($EvidenceDirectory.Length -eq 0) {
  $EvidenceDirectory = Join-Path $PSScriptRoot 'evidence\hvigor-detached-build'
}
$projectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$hvigorPath = 'F:\DevEco Studio\tools\hvigor\bin\hvigorw.bat'
if (-not (Test-Path -LiteralPath $hvigorPath)) {
  throw "HVIGOR_MISSING:$hvigorPath"
}
New-Item -ItemType Directory -Path $EvidenceDirectory -Force | Out-Null
$manifestPath = Join-Path $EvidenceDirectory 'build-manifest.json'
$stdoutPath = Join-Path $EvidenceDirectory 'build.stdout.log'
$stderrPath = Join-Path $EvidenceDirectory 'build.stderr.log'

if (Test-Path -LiteralPath $manifestPath) {
  $prior = [System.IO.File]::ReadAllText($manifestPath, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
  if ($null -ne $prior.PSObject.Properties['processId']) {
    $active = Get-Process -Id ([int]$prior.processId) -ErrorAction SilentlyContinue
    if ($null -ne $active) {
      throw "HVIGOR_BUILD_ALREADY_ACTIVE:pid=$($active.Id)"
    }
  }
}

Remove-Item -LiteralPath $stdoutPath -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
$env:DEVECO_SDK_HOME = 'F:\DevEco Studio\sdk'
$arguments = [System.Collections.Generic.List[string]]::new()
[void]$arguments.Add($Task)
if ($Task -eq 'assembleApp') {
  [void]$arguments.Add('-p')
  [void]$arguments.Add("product=$Product")
  [void]$arguments.Add('-p')
  [void]$arguments.Add("buildMode=$BuildMode")
}
[void]$arguments.Add('--no-daemon')
[void]$arguments.Add('--stacktrace')
$process = Start-Process -FilePath $hvigorPath -ArgumentList $arguments.ToArray() -WorkingDirectory $projectRoot -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -WindowStyle Hidden -PassThru
$manifest = [pscustomobject][ordered]@{
  schemaVersion = 1
  startedAt = [DateTimeOffset]::UtcNow.ToString('o')
  processId = $process.Id
  task = $Task
  product = $Product
  buildMode = $BuildMode
  stdoutPath = 'build.stdout.log'
  stderrPath = 'build.stderr.log'
}
$temporaryPath = "$manifestPath.tmp-$PID"
[System.IO.File]::WriteAllText($temporaryPath, ($manifest | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $manifestPath -Force
$manifest | ConvertTo-Json -Depth 8
