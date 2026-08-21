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
    throw "Legado V2 Explore interaction classification contract failed: $Message"
  }
}

$runnerPath = Join-Path $RepositoryRoot 'tools\legado-compat\Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1'
$runner = Read-Utf8Text -Path $runnerPath
$exploreStart = $runner.IndexOf('$exploreWorkflow =')
$exploreEnd = $runner.IndexOf('$safeReadPath =', $exploreStart)
Assert-Contract ($exploreStart -ge 0 -and $exploreEnd -gt $exploreStart) 'Explore dispatch branch must remain bounded and discoverable.'
$branch = $runner.Substring($exploreStart, $exploreEnd - $exploreStart)

# HTTP 403/404 login/challenge responses may carry errorCode=needs_interaction.
# Interaction classification must precede Test-HypiumExploreExternalBoundary,
# otherwise the status code erases the required manual-interaction state.
$interactionIndex = $branch.IndexOf('[string]$trace.errorCode -eq ''needs_interaction''')
$externalIndex = $branch.IndexOf('Test-HypiumExploreExternalBoundary -Attempt $attempt')
Assert-Contract ($interactionIndex -ge 0) 'Explore dispatch must explicitly handle needs_interaction.'
Assert-Contract ($externalIndex -gt $interactionIndex) 'Explore interaction classification must precede external-network classification.'
Assert-Contract ($branch.Contains("Set-HypiumWorkflow -State `$State -Record `$Record -Name 'explore' -Status 'needs_interaction'")) 'Explore workflow must settle as needs_interaction.'
Assert-Contract ($branch.Contains("Set-HypiumSource -State `$State -Record `$Record -Status 'needs_interaction'")) 'Explore source status must settle as needs_interaction.'

[pscustomobject]@{
  status = 'passed'
  contract = 'explore_http_error_with_interaction_code_is_needs_interaction'
  fixture = [pscustomobject]@{
    workflow = 'explore'
    statusCode = 403
    errorCode = 'needs_interaction'
  }
} | ConvertTo-Json -Compress
