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
    throw "Legado V2 BookInfo interaction classification contract failed: $Message"
  }
}

$runnerPath = Join-Path $RepositoryRoot 'tools\legado-compat\Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1'
$runner = Read-Utf8Text -Path $runnerPath
$functionStart = $runner.IndexOf('function Resolve-HypiumBookInfoTerminalOutcome')
$functionEnd = $runner.IndexOf('function Resolve-HypiumBookInfoPartialOutcome')
Assert-Contract ($functionStart -ge 0 -and $functionEnd -gt $functionStart) 'BookInfo terminal resolver must remain a separately testable function.'
$resolver = $runner.Substring($functionStart, $functionEnd - $functionStart)

# Stable fixture semantics: HTTP 200 login/challenge pages are interaction
# boundaries, not engine failures. This exact branch must run before the
# generic network/status branch so status=200 cannot erase errorCode.
$interactionBranch = $resolver.IndexOf("if (`$errorCode -eq 'needs_interaction')")
$networkBranch = $resolver.IndexOf("if (`$errorCode -eq 'network' -or `$errorCode -eq 'http' -or `$statusCode -ge 400)")
Assert-Contract ($interactionBranch -ge 0) 'BookInfo terminal resolver must explicitly handle needs_interaction.'
Assert-Contract ($networkBranch -gt $interactionBranch) 'needs_interaction classification must precede generic network/status classification.'
Assert-Contract ($resolver.Contains("status = 'needs_interaction'")) 'BookInfo interaction fixture must settle as needs_interaction.'
Assert-Contract ($resolver.Contains("outcome = 'protected_response_requires_interaction'")) 'BookInfo interaction outcome must be explicit and stable.'
Assert-Contract ($resolver.Contains("category = 'protected_response_requires_interaction'")) 'BookInfo interaction category must be explicit and stable.'

[pscustomobject]@{
  status = 'passed'
  contract = 'book_info_html_login_is_needs_interaction'
  fixture = [pscustomobject]@{
    statusCode = 200
    responseClass = 'html_login'
    errorCode = 'needs_interaction'
  }
} | ConvertTo-Json -Compress
