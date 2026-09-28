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
    throw "Legado dynamic Explore network route contract failed: $Message"
  }
}

$enginePath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoJsEngine.ets'
$engine = Read-Utf8Text -Path $enginePath
$start = $engine.IndexOf('private needsNetworkCapability(code: string): boolean', [System.StringComparison]::Ordinal)
$end = $engine.IndexOf('async execute(code: string, context: JsContext = {}): Promise<JsExecuteResult>', [System.StringComparison]::Ordinal)
Assert-Contract ($start -ge 0 -and $end -gt $start) 'The engine must keep a bounded network-capability decision block.'
$decisionBlock = $engine.Substring($start, $end - $start)

# A source can put java.ajax inside source.bookSourceComment and execute it via
# eval(), as the pinned source at ordinal 77 does.  The decision must therefore
# route dynamic evaluation to the WebView before Native JSVM execution.
Assert-Contract ($decisionBlock.Contains("'eval('")) 'Dynamic eval() must force the WebView network route.'
Assert-Contract ($decisionBlock.Contains("'Function('")) 'Dynamic Function() must force the WebView network route.'
Assert-Contract ($decisionBlock.Contains("'source.bookSourceComment'")) 'Source-comment indirection must force the WebView network route.'

[pscustomobject]@{
  status = 'passed'
  contract = 'dynamic_explore_script_network_route'
} | ConvertTo-Json -Compress
