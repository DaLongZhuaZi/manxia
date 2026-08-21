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
    throw "Legado ArkWeb dynamic eval probe contract failed: $Message"
  }
}

$page = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'entry\src\main\ets\pages\LegadoArkWebConformancePage.ets')
$runner = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'tools\legado-compat\Invoke-LegadoCompatibility.ps1')
Assert-Contract ($page.Contains('assertRuntimeDynamicEvalProbe')) 'ArkWeb conformance page must execute direct, source-scoped and source-comment eval probes.'
Assert-Contract ($page.Contains('fixture-runtime-dynamic-eval-probe')) 'ArkWeb probe must emit a stable trace marker.'
Assert-Contract ($runner.Contains('fixture-runtime-dynamic-eval-probe')) 'Stage 3 gate must require the dynamic eval probe marker.'
Assert-Contract ($page.Contains('assertRuntimeTocJsObjectProjection')) 'ArkWeb conformance page must exercise source-comment TOC object projection.'
Assert-Contract ($page.Contains('fixture-runtime-toc-js-object-projection')) 'ArkWeb TOC object probe must emit a stable trace marker.'
Assert-Contract ($runner.Contains('fixture-runtime-toc-js-object-projection')) 'Stage 3 gate must require the TOC object projection marker.'

[pscustomobject]@{
  status = 'passed'
  contract = 'arkweb_dynamic_eval_probe'
} | ConvertTo-Json -Compress
