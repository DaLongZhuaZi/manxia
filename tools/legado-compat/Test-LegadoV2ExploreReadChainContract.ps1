[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Read-Utf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

function Assert-Contract {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Message
  )
  if (-not $Condition) {
    throw "Legado V2 Explore/read chain contract failed: $Message"
  }
}

$navigationPath = Join-Path $RepositoryRoot 'tools\legado-compat\Invoke-LegadoV2HypiumNavigation.py'
$runnerPath = Join-Path $RepositoryRoot 'tools\legado-compat\Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1'
$navigation = Read-Utf8Text -Path $navigationPath
$runner = Read-Utf8Text -Path $runnerPath

Assert-Contract ($navigation.Contains('"--explore-read-path"')) 'the Hypium driver must expose an explicit Explore-to-read continuation flag.'
Assert-Contract ($navigation.Contains('continue_read_path')) 'Explore execution must carry an explicit continuation decision.'
Assert-Contract ($navigation.Contains('execute_safe_read_path(') -and $navigation.Contains('result_component')) 'Explore continuation must reuse the guarded BookInfo/Toc/Content path after selecting a result.'
Assert-Contract ($navigation.Contains('explore_read_path')) 'the driver evidence must identify Explore-to-read execution separately from search.'
Assert-Contract ($runner.Contains('--explore-read-path')) 'the PowerShell runner must request Explore-to-read continuation.'
Assert-Contract ($runner.Contains('explore_read_path') -and $runner.Contains('exploreAttempt')) 'the source evidence must retain both Explore and chained read evidence.'
Assert-Contract ($runner.Contains('Set-HypiumFullWorkflowExploreReadWorkflowsRunning')) 'the chained BookInfo/Toc/Content workflows must enter running state and increment attempts before the device path starts.'

[pscustomobject]@{
  status = 'passed'
  contract = 'explore_to_book_info_toc_content_chain'
  assertions = 7
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
} | ConvertTo-Json -Compress
