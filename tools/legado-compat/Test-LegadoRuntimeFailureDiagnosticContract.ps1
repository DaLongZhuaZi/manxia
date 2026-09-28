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
    throw "Legado runtime failure diagnostic contract failed: $Message"
  }
}

$sourceRuntime = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoSourceScriptRuntime.ets')
$runtimeHtml = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html')
$orchestrator = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoWorkflowOrchestrator.ets')

Assert-Contract ($sourceRuntime.Contains('buildStableRuntimeDiagnostic')) 'Source-script failures must retain a safe structural diagnostic instead of only SCRIPT_RUNTIME.'
Assert-Contract ($sourceRuntime.Contains('errorDigest=') -and $sourceRuntime.Contains('codeLength=')) 'Diagnostic must bind the failure to the script without persisting source text.'
Assert-Contract ($runtimeHtml.Contains('sourceComment=') -and $runtimeHtml.Contains('domParser=')) 'Runtime envelope must record safe source/DOM capability state on errors.'
Assert-Contract ($orchestrator.Contains('diagnostic=') -and $orchestrator.Contains('execution.errorMessage')) 'Explore trace output must persist the structural diagnostic.'

[pscustomobject]@{
  status = 'passed'
  contract = 'runtime_failure_structural_diagnostic'
} | ConvertTo-Json -Compress
