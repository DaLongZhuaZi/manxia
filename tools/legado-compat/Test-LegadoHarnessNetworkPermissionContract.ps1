[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($RepositoryRoot.Length -eq 0) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
} else {
  $RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
}
if ($OutputPath.Length -eq 0) {
  $OutputPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\legado-harness-network-permission-contract.json'
}

try {
  $path = Join-Path $RepositoryRoot 'entry\src\ohosTest\module.json5'
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "Missing ohosTest module manifest: $path"
  }
  $text = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false, $true))
  if (-not $text.Contains('"requestPermissions"')) {
    throw 'ohosTest module does not declare requestPermissions'
  }
  if (-not $text.Contains('"ohos.permission.INTERNET"')) {
    throw 'ohosTest module does not declare INTERNET permission'
  }
  $result = [pscustomobject][ordered]@{
    status = 'passed'
    assertions = 2
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
} catch {
  $result = [pscustomobject][ordered]@{
    status = 'failed'
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
}
$directory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $directory)) {
  [void][System.IO.Directory]::CreateDirectory($directory)
}
[System.IO.File]::WriteAllText($OutputPath, [string]($result | ConvertTo-Json -Depth 4), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Depth 4
if ($result.status -ne 'passed') {
  exit 1
}
