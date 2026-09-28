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
    throw "Legado runtime Jsoup enumeration contract failed: $Message"
  }
}

$runtime = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html')
$start = $runtime.IndexOf('function createRuntimeJsoupElement', [System.StringComparison]::Ordinal)
$end = $runtime.IndexOf('function toByteArray', [System.StringComparison]::Ordinal)
Assert-Contract ($start -ge 0 -and $end -gt $start) 'Runtime Jsoup bridge block must be present.'
$block = $runtime.Substring($start, $end - $start)

# Dynamic Explore rules rely on Jsoup Elements being an indexed collection
# whose helper methods are not yielded by for-in enumeration.
Assert-Contract ($block.Contains('querySelectorAll')) 'Runtime Jsoup select() must return actual matched elements.'
Assert-Contract ($block.Contains('attr: function')) 'Runtime Jsoup elements must expose attr().' 
Assert-Contract ($block.Contains('Object.defineProperty')) 'Runtime Jsoup list helpers must be non-enumerable.'
Assert-Contract ($block.Contains('enumerable: false')) 'Runtime Jsoup list helpers must not pollute for-in results.'
Assert-Contract ($block.Contains('var Jsoup = {')) 'Runtime Jsoup parser must use the indexed element bridge.'

[pscustomobject]@{
  status = 'passed'
  contract = 'runtime_jsoup_indexed_elements'
} | ConvertTo-Json -Compress
