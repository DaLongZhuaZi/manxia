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
    throw "Legado Jsoup element-list enumeration contract failed: $Message"
  }
}

$engine = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoJsEngine.ets')
$start = $engine.IndexOf('var __nativeEnhanceElementList = function', [System.StringComparison]::Ordinal)
$end = $engine.IndexOf('var __nativeSelectHtmlElements = function', [System.StringComparison]::Ordinal)
Assert-Contract ($start -ge 0 -and $end -gt $start) 'The DOM list bridge must have a bounded enhancement block.'
$listBlock = $engine.Substring($start, $end - $start)

# Legado source JS commonly uses `for (i in elements)`.  Bridge helper
# methods must not appear as enumerable list entries, otherwise `elements[i]`
# can be a function and a source rule that calls `.attr()` crashes.
Assert-Contract ($listBlock.Contains('Object.defineProperty')) 'Element-list helper methods must be defined through a non-enumerable property helper.'
Assert-Contract ($listBlock.Contains('enumerable: false')) 'Element-list helper methods must be non-enumerable.'

[pscustomobject]@{
  status = 'passed'
  contract = 'jsoup_element_list_non_enumerable_helpers'
} | ConvertTo-Json -Compress
