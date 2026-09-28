[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Legado JSONPath affected-set contract failed: $Message" }
}

$evidencePath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\legado-jsonpath-runtime-affected-source-set-20260807.json'
$evidence = Get-Content -LiteralPath $evidencePath -Raw -Encoding utf8 | ConvertFrom-Json
$targetId = '4B33C6BA1A7DC3AA12EFF8FA54B529A7B6510E692892093A38D98A15544119B1'
$target = @($evidence.records | Where-Object { [string]$_.sourceId -eq $targetId })

Assert-Contract ([int]$evidence.sourceCount -eq 458) 'evidence must remain bound to 458-source baseline'
Assert-Contract ([string]$evidence.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'source package hash changed'
Assert-Contract ([int]$evidence.affectedSourceCount -eq 60) 'affected set count changed without a baseline change'
Assert-Contract ($target.Count -eq 1) 'ordinal 227 source must be in the affected set'
$exploreHit = @($target[0].hits | Where-Object { $_.path -eq '$.ruleExplore.bookList' })
Assert-Contract ($exploreHit.Count -eq 1) 'ordinal 227 ruleExplore JSONPath hit missing'
Assert-Contract (@($exploreHit[0].jsonPathPatterns | Where-Object { $_ -eq '$.data[*].data[0].thumb' }).Count -eq 1) 'nested JSONPath witness missing'

[pscustomobject]@{
  status = 'passed'
  contract = 'legado_jsonpath_runtime_affected_set'
  assertions = 5
  sourceCount = [int]$evidence.sourceCount
  affectedSourceCount = [int]$evidence.affectedSourceCount
  targetSourceId = $targetId
} | ConvertTo-Json -Compress
