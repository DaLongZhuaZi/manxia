$ErrorActionPreference = 'Stop'

$httpProxy = 'http://127.0.0.1:7890'
$httpsProxy = 'http://127.0.0.1:7899'
$allProxy = 'socks5://127.0.0.1:7898'
$noProxy = '127.0.0.1,localhost'

$knownCodexDesktopPath = 'C:\Program Files\WindowsApps\OpenAI.CodexBeta_26.513.4821.0_x64__2p2nqsd0c76g0\app\Codex (Beta).exe'
$codexDesktopAumid = 'OpenAI.CodexBeta_2p2nqsd0c76g0!App'
$codexDesktopProcessName = 'Codex (Beta)'
$cachedPathFile = Join-Path $PSScriptRoot 'codex-desktop-path.txt'

function Show-LauncherMessage {
  param (
    [string]$Message
  )

  Write-Host ''
  Write-Host $Message -ForegroundColor Cyan
  Write-Host ''
}

function Wait-ForExit {
  param (
    [string]$Message = '按回车键退出...'
  )

  Read-Host $Message | Out-Null
}

function Read-Utf8TextFile {
  param (
    [string]$Path
  )

  if (-not (Test-Path -LiteralPath $Path)) {
    return ''
  }

  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false)).Trim()
}

function Write-Utf8TextFile {
  param (
    [string]$Path,
    [string]$Content
  )

  [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Get-RunningCodexDesktopProcess {
  $processes = Get-Process -Name $codexDesktopProcessName -ErrorAction SilentlyContinue
  if ($null -eq $processes) {
    return $null
  }

  foreach ($process in $processes) {
    if (($null -ne $process.Path) -and ($process.Path.Contains('OpenAI.CodexBeta'))) {
      return $process
    }
  }

  return $processes | Select-Object -First 1
}

function Wait-ForCodexDesktopStart {
  param (
    [int]$TimeoutSeconds = 12
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $process = Get-RunningCodexDesktopProcess
    if ($null -ne $process) {
      return $process
    }

    Start-Sleep -Milliseconds 350
  }

  return $null
}

function Get-CandidateExecutablePaths {
  $paths = New-Object 'System.Collections.Generic.List[string]'

  $cachedPath = Read-Utf8TextFile -Path $cachedPathFile
  if (($cachedPath.Length -gt 0) -and (Test-Path -LiteralPath $cachedPath)) {
    $paths.Add($cachedPath)
  }

  if (Test-Path -LiteralPath $knownCodexDesktopPath) {
    if (-not $paths.Contains($knownCodexDesktopPath)) {
      $paths.Add($knownCodexDesktopPath)
    }
  }

  return $paths
}

function Start-CodexDesktopByExecutable {
  param (
    [string]$ExecutablePath
  )

  if (-not (Test-Path -LiteralPath $ExecutablePath)) {
    return $null
  }

  Start-Process -FilePath $ExecutablePath | Out-Null
  return Wait-ForCodexDesktopStart
}

function Start-CodexDesktopByAumid {
  $shellPath = "shell:AppsFolder\$codexDesktopAumid"
  Start-Process -FilePath 'explorer.exe' -ArgumentList $shellPath | Out-Null
  return Wait-ForCodexDesktopStart
}

function Save-RunningCodexDesktopPath {
  param (
    [System.Diagnostics.Process]$Process
  )

  if (($null -ne $Process) -and ($null -ne $Process.Path) -and ($Process.Path.Length -gt 0)) {
    Write-Utf8TextFile -Path $cachedPathFile -Content $Process.Path
  }
}

$runningDesktop = Get-RunningCodexDesktopProcess
if ($null -ne $runningDesktop) {
  Show-LauncherMessage '检测到 Codex Desktop 已在运行。为了让代理环境生效，请先完全退出现有 Codex Desktop 再重新双击本启动器。'
  Wait-ForExit
  exit 1
}

$env:HTTP_PROXY = $httpProxy
$env:http_proxy = $httpProxy
$env:HTTPS_PROXY = $httpsProxy
$env:https_proxy = $httpsProxy
$env:ALL_PROXY = $allProxy
$env:all_proxy = $allProxy
$env:NO_PROXY = $noProxy
$env:no_proxy = $noProxy

Show-LauncherMessage "正在启动 Codex Desktop...`nHTTP 代理: $httpProxy`nHTTPS 代理: $httpsProxy`nSOCKS 代理: $allProxy"

$launchedProcess = $null
$candidatePaths = Get-CandidateExecutablePaths
foreach ($candidatePath in $candidatePaths) {
  $launchedProcess = Start-CodexDesktopByExecutable -ExecutablePath $candidatePath
  if ($null -ne $launchedProcess) {
    break
  }
}

if ($null -eq $launchedProcess) {
  $launchedProcess = Start-CodexDesktopByAumid
}

if ($null -eq $launchedProcess) {
  Show-LauncherMessage "Codex Desktop 启动失败。`n已尝试已知可执行路径与 AUMID 启动。`n如果 Codex 刚更新过版本，请先手动启动一次桌面版，再重新使用本启动器。"
  Wait-ForExit
  exit 1
}

Save-RunningCodexDesktopPath -Process $launchedProcess

$launchPath = ''
if ($null -ne $launchedProcess.Path) {
  $launchPath = $launchedProcess.Path
}

if ($launchPath.Length -gt 0) {
  Show-LauncherMessage "Codex Desktop 已启动。`n当前入口: $launchPath"
} else {
  Show-LauncherMessage 'Codex Desktop 已启动。'
}
