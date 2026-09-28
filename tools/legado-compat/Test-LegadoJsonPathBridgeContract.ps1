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
    throw "Legado JSONPath bridge contract failed: $Message"
  }
}

$runtime = Read-Utf8Text -Path (Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html')
$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-jsonpath-bridge.json'
$fixture = (Read-Utf8Text -Path $fixturePath) | ConvertFrom-Json

Assert-Contract ($fixture.rule -eq '$.data[*].title') 'fixture must cover wildcard JSONPath extraction'
Assert-Contract ($fixture.expected.Count -eq 2) 'fixture must contain two expected values'
Assert-Contract ($fixture.nestedRule -eq '$.data[*].data[0].thumb') 'fixture must cover nested wildcard/index JSONPath extraction'
Assert-Contract ($fixture.nestedExpected.Count -eq 2) 'fixture must contain nested expected values'
Assert-Contract ($runtime.Contains('var legadoGetJsonPathValues = function')) 'V2 Runtime bridge must implement JSONPath traversal'
Assert-Contract ($runtime.Contains('legadoGetJsonPathValues(split.parts[stringIndex], content)') -and $runtime.Contains('legadoGetJsonPathValues(split.parts[listIndex], content)')) 'V2 Runtime java helpers must route each JSONPath alternative through the bridge'
Assert-Contract ($runtime.Contains('getStringList: function (rule, content)')) 'java.getStringList must remain available'
Assert-Contract ($runtime.Contains('legadoJsonPathValueText')) 'object JSONPath values must preserve JSON text'
Assert-Contract ($runtime.Contains('legadoJsonPathSplitCombinators') -and $runtime.Contains("split.separators.indexOf('%%')")) 'V2 Runtime must retain Legado JSONPath &&/||/%% composition'
Assert-Contract ($runtime.Contains("remaining.indexOf('..') === 0")) 'V2 Runtime must support recursive descent after a property segment'
Assert-Contract ($runtime.Contains("token.split(':')") -and $runtime.Contains('sliceStep')) 'V2 Runtime must support Jayway-style array slice tokens'

[pscustomobject]@{
  status = 'passed'
  contract = 'legado_jsonpath_bridge'
  assertions = 12
  fixture = 'tools/legado-compat/fixtures/legado-jsonpath-bridge.json'
} | ConvertTo-Json -Compress
