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
  param([Parameter(Mandatory = $true)][bool]$Condition, [Parameter(Mandatory = $true)][string]$Message)
  if (-not $Condition) {
    throw "Legado HTTP header contract failed: $Message"
  }
}

$path = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoRequestPipeline.ets'
$text = Read-Utf8Text -Path $path

Assert-Contract ($text.Contains('this.applyUpstreamHttpInterceptorDefaults(observableHeaders);')) 'HTTP execution must apply the upstream interceptor contract.'
Assert-Contract ($text.Contains("headers['Keep-Alive'] = '300';")) 'Missing Legado Keep-Alive default.'
Assert-Contract ($text.Contains("headers['Connection'] = 'Keep-Alive';")) 'Missing Legado Connection default.'
Assert-Contract ($text.Contains("headers['Cache-Control'] = 'no-cache';")) 'Missing Legado Cache-Control default.'
Assert-Contract ($text.Contains("const LEGADO_REFERENCE_DEFAULT_ACCEPT_ENCODING = 'gzip, deflate';")) 'Missing pinned Legado Accept-Encoding baseline.'
Assert-Contract ($text.Contains("this.putHeader(headers, 'Accept-Encoding', LEGADO_REFERENCE_DEFAULT_ACCEPT_ENCODING);")) 'Planner must inject Accept-Encoding before NetStack defaults are applied.'
Assert-Contract ($text.Contains("this.hasHeader(headers, 'Accept-Encoding')")) 'Explicit source Accept-Encoding must retain precedence.'
Assert-Contract ($text.Contains("'defaultAcceptEncoding'")) 'Trace must expose the default Accept-Encoding decision.'
Assert-Contract ($text.Contains("headers[i].name.toLowerCase() === 'user-agent' && headers[i].value === 'null'")) 'User-Agent null sentinel must be omitted like the upstream interceptor.'
Assert-Contract ($text.Contains('const effectiveHeaders = this.toHeaderEntries(observableHeaders);')) 'Trace must use the effective transport headers.'
Assert-Contract ($text.Contains('effectiveHeaders,')) 'ResponseEnvelope must receive effective transport headers.'

[pscustomobject]@{
  status = 'passed'
  contract = 'upstream_okhttp_interceptor_headers'
  defaults = @('keep-alive', 'connection', 'cache-control', 'accept-encoding')
  nullUserAgent = 'omitted'
  traceHeaders = 'effective'
} | ConvertTo-Json -Compress
