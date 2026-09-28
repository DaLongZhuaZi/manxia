[CmdletBinding()]
param(
  [int]$Port = 18765
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$listener = [System.Net.HttpListener]::new()
$listener.Prefixes.Add("http://127.0.0.1:$Port/")

function Write-FixtureResponse {
  param(
    [System.Net.HttpListenerContext]$Context,
    [int]$StatusCode,
    [string]$Body,
    [string]$ContentType = 'text/plain; charset=utf-8',
    [string[]]$Headers = @()
  )
  $response = $Context.Response
  $response.StatusCode = $StatusCode
  $response.ContentType = $ContentType
  foreach ($header in $Headers) {
    $separator = $header.IndexOf(':')
    if ($separator -gt 0) {
      $response.Headers.Add($header.Substring(0, $separator), $header.Substring($separator + 1).Trim())
    }
  }
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
  $response.ContentLength64 = $bytes.Length
  $response.OutputStream.Write($bytes, 0, $bytes.Length)
  $response.Close()
}

function Write-FixtureGzipJsonResponse {
  param(
    [System.Net.HttpListenerContext]$Context,
    [string]$Body
  )
  $response = $Context.Response
  $response.StatusCode = 200
  $response.ContentType = 'application/json; charset=utf-8'
  $response.Headers.Add('Content-Encoding', 'gzip')
  $plainBytes = [System.Text.Encoding]::UTF8.GetBytes($Body)
  $compressed = [System.IO.MemoryStream]::new()
  try {
    $gzip = [System.IO.Compression.GzipStream]::new($compressed, [System.IO.Compression.CompressionLevel]::SmallestSize, $true)
    try {
      $gzip.Write($plainBytes, 0, $plainBytes.Length)
    } finally {
      $gzip.Dispose()
    }
    $payload = $compressed.ToArray()
    $response.ContentLength64 = $payload.Length
    $response.OutputStream.Write($payload, 0, $payload.Length)
  } finally {
    $compressed.Dispose()
    $response.Close()
  }
}

function Get-RequestBody {
  param([System.Net.HttpListenerRequest]$Request)
  $reader = [System.IO.StreamReader]::new($Request.InputStream, $Request.ContentEncoding)
  try {
    return $reader.ReadToEnd()
  } finally {
    $reader.Dispose()
  }
}

function ConvertTo-FixtureJsonString {
  param([object]$Value)
  return $Value | ConvertTo-Json -Compress -Depth 8
}

function Get-FixtureWireValueDigest {
  param([string]$Value)
  if ([string]::IsNullOrEmpty($Value)) {
    return 'empty'
  }
  $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Value)
  return [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Get-FixtureWireObservation {
  param([System.Net.HttpListenerRequest]$Request)
  $allowedNames = @('User-Agent', 'Keep-Alive', 'Connection', 'Cache-Control', 'X-Legado-Header', 'Cookie', 'Accept-Encoding')
  $headers = New-Object 'System.Collections.Generic.List[object]'
  foreach ($name in $allowedNames) {
    $value = [string]$Request.Headers[$name]
    if ($value.Length -gt 0) {
      [void]$headers.Add([pscustomobject][ordered]@{
        name = $name.ToLowerInvariant()
        valueSha256 = Get-FixtureWireValueDigest -Value $value
      })
    }
  }
  return [pscustomobject][ordered]@{
    marker = 'fixture-wire-observation-v1'
    method = $Request.HttpMethod
    protocol = $Request.ProtocolVersion.ToString()
    headers = $headers.ToArray()
  }
}

function Get-FixtureConnectionObservation {
  param([System.Net.HttpListenerRequest]$Request)
  $endpoint = $Request.RemoteEndPoint
  $endpointText = if ($null -eq $endpoint) { 'missing' } else { "$($endpoint.Address):$($endpoint.Port)" }
  $headers = Get-FixtureWireObservation -Request $Request
  return [pscustomobject][ordered]@{
    marker = 'fixture-connection-observation-v1'
    protocol = $Request.ProtocolVersion.ToString()
    connectionFingerprint = Get-FixtureWireValueDigest -Value $endpointText
    headers = $headers.headers
  }
}

try {
  $listener.Start()
  Write-Output "LEGADO_FIXTURE_READY:$Port"
  while ($listener.IsListening) {
    $context = $listener.GetContext()
    $path = $context.Request.Url.AbsolutePath
    switch ($path) {
      '/health' {
        Write-FixtureResponse -Context $context -StatusCode 200 -Body 'fixture-health'
      }
      '/redirect' {
        $context.Response.StatusCode = 302
        $context.Response.RedirectLocation = '/final?from=redirect'
        $context.Response.Headers.Add('Set-Cookie', 'fixture_session=fixture-cookie; Path=/')
        $context.Response.Close()
      }
      '/final' {
        $cookie = $context.Request.Headers['Cookie']
        $cookieSeen = if ($cookie -and $cookie.Contains('fixture_session=fixture-cookie')) { 'true' } else { 'false' }
        Write-FixtureResponse -Context $context -StatusCode 200 -Body "fixture-final|cookie=$cookieSeen"
      }
      '/header-post' {
        $body = Get-RequestBody -Request $context.Request
        $result = [pscustomobject][ordered]@{
          marker = 'fixture-header-post'
          method = $context.Request.HttpMethod
          header = [string]$context.Request.Headers['X-Legado-Header']
          cookieJar = [string]$context.Request.Headers['CookieJar']
          contentType = [string]$context.Request.ContentType
          body = $body
        }
        Write-FixtureResponse -Context $context -StatusCode 200 -Body (ConvertTo-FixtureJsonString $result) -ContentType 'application/json; charset=utf-8'
      }
      '/wire-observation' {
        $observation = Get-FixtureWireObservation -Request $context.Request
        Write-FixtureResponse -Context $context -StatusCode 200 -Body (ConvertTo-FixtureJsonString $observation) -ContentType 'application/json; charset=utf-8'
      }
      '/connection-observation' {
        $observation = Get-FixtureConnectionObservation -Request $context.Request
        Write-FixtureResponse -Context $context -StatusCode 200 -Body (ConvertTo-FixtureJsonString $observation) -ContentType 'application/json; charset=utf-8'
      }
      '/compressed-observation' {
        $result = [pscustomobject][ordered]@{
          marker = 'fixture-compressed-observation-v1'
          payloadSha256 = Get-FixtureWireValueDigest -Value 'fixture-compressed-payload-v1'
        }
        Write-FixtureGzipJsonResponse -Context $context -Body (ConvertTo-FixtureJsonString $result)
      }
      '/search' {
        $body = '{"items":[{"name":"fixture-book","url":"/book/1","author":"fixture-author"}]}'
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $body -ContentType 'application/json; charset=utf-8'
      }
      '/search/request-carrier' {
        # The trailing URL option is deliberately part of the search item. It
        # must survive Search -> BookInfo and be parsed only when BookInfo
        # constructs its RequestSpec.
        $body = '{"items":[{"name":"fixture-request-carrier","url":"/book/request-carrier,{\"headers\":{\"X-Legado-Carrier\":\"fixture-carrier\"}}"}]}'
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $body -ContentType 'application/json; charset=utf-8'
      }
      '/search/variable-carrier' {
        # SearchBook.variable must retain this item-local value. A fresh V2
        # executor later uses only that snapshot to resolve ruleBookInfo.tocUrl.
        $body = '{"items":[{"name":"fixture-variable-carrier","url":"/book/variable-carrier","toc":"/toc/1"}]}'
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $body -ContentType 'application/json; charset=utf-8'
      }
      '/search/variable-carrier-isolation' {
        # Each item writes its own fixtureToc. Fresh executors must restore
        # the selected snapshot only; neither item may inherit the other's
        # @put value through a process-level or source-level map.
        $body = '{"items":[{"name":"fixture-variable-alpha","url":"/book/variable-carrier-alpha","toc":"/toc/isolation/alpha"},{"name":"fixture-variable-beta","url":"/book/variable-carrier-beta","toc":"/toc/isolation/beta"}]}'
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $body -ContentType 'application/json; charset=utf-8'
      }
      '/protected-login' {
        $body = '<!doctype html><html><head><title>Sign in</title></head><body><main><h1>Login required</h1><form id="login"><input name="account"></form></main></body></html>'
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $body -ContentType 'text/html; charset=utf-8'
      }
      '/search/book-list-finalization' {
        # Deliberately includes a duplicate URL and an empty URL. Original
        # BookList keeps the first duplicate, uses the effective response URL
        # for an empty detail URL, then reverses the final unique list when
        # ruleSearch.bookList starts with '-'.
        $body = '{"items":[{"name":"fixture-first","url":"/book/final-first"},{"name":"fixture-duplicate","url":"/book/final-first"},{"name":"fixture-empty","url":""},{"name":"fixture-last","url":"/book/final-last"}]}'
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $body -ContentType 'application/json; charset=utf-8'
      }
      '/search/multiple-links' {
        $body = '<article class="fixture-card"><a href="/book/multiple-links">fixture-first</a><a href="/book/incorrect">fixture-later</a></article>'
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $body -ContentType 'text/html; charset=utf-8'
      }
      '/book/1' {
        $body = '{"name":"fixture-book","author":"fixture-author","toc":"/toc/1","download":"/file/1"}'
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $body -ContentType 'application/json; charset=utf-8'
      }
      '/book/request-carrier' {
        $carrier = [string]$context.Request.Headers['X-Legado-Carrier']
        if ($carrier -ne 'fixture-carrier') {
          Write-FixtureResponse -Context $context -StatusCode 401 -Body '{"error":"missing-request-carrier"}' -ContentType 'application/json; charset=utf-8'
          continue
        }
        $body = '{"name":"fixture-request-carrier","author":"fixture-author","toc":"/toc/1"}'
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $body -ContentType 'application/json; charset=utf-8'
      }
      '/book/variable-carrier' {
        $body = '{"name":"fixture-variable-carrier","author":"fixture-author"}'
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $body -ContentType 'application/json; charset=utf-8'
      }
      '/book/variable-carrier-alpha' {
        $body = '{"name":"fixture-variable-alpha","author":"fixture-author"}'
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $body -ContentType 'application/json; charset=utf-8'
      }
      '/book/variable-carrier-beta' {
        $body = '{"name":"fixture-variable-beta","author":"fixture-author"}'
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $body -ContentType 'application/json; charset=utf-8'
      }
      '/book/multiple-links' {
        $body = '<main class="fixture-info"><h1>fixture-multiple-book</h1><section class="fixture-toc"><a href="/toc/multiple/root">fixture-toc-first</a><a href="/toc/incorrect">fixture-toc-later</a></section></main>'
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $body -ContentType 'text/html; charset=utf-8'
      }
      '/toc/1' {
        $body = '{"chapters":[{"name":"fixture-chapter","url":"/content/1"}]}'
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $body -ContentType 'application/json; charset=utf-8'
      }
      '/toc/multiple/root' {
        $body = '<article class="fixture-chapter"><a href="/content/root">fixture-root</a></article><nav class="fixture-next"><a href="/toc/multiple/one">fixture-next-one</a><a href="/toc/multiple/two">fixture-next-two</a></nav>'
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $body -ContentType 'text/html; charset=utf-8'
      }
      '/toc/multiple/one' {
        $body = '<article class="fixture-chapter"><a href="/content/one">fixture-one</a></article>'
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $body -ContentType 'text/html; charset=utf-8'
      }
      '/toc/multiple/two' {
        $body = '<article class="fixture-chapter"><a href="/content/two">fixture-two</a></article>'
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $body -ContentType 'text/html; charset=utf-8'
      }
      '/content/1' {
        $body = '{"title":"fixture-chapter","content":"fixture-content"}'
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $body -ContentType 'application/json; charset=utf-8'
      }
      '/content/html' {
        $body = '<section class="fixture-content"><p>fixture-html-content&nbsp;line</p><p>fixture-html-second-line</p></section>'
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $body -ContentType 'text/html; charset=utf-8'
      }
      '/content/multipage/one' {
        $body = '<section class="fixture-page"><p>fixture-page-one REMOVE_MARKER</p></section><a id="fixture-next" href="/content/multipage/two">next</a>'
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $body -ContentType 'text/html; charset=utf-8'
      }
      '/content/multipage/two' {
        $body = '<section class="fixture-page"><p>fixture-page-two REMOVE_MARKER</p></section>'
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $body -ContentType 'text/html; charset=utf-8'
      }
      '/file/1' {
        Write-FixtureResponse -Context $context -StatusCode 200 -Body 'fixture-file-payload' -ContentType 'application/octet-stream'
      }
      '/web' {
        $html = '<html><head><script>document.cookie="arkweb_fixture=arkweb-cookie; Path=/";</script><title>fixture-web-title</title><link rel="stylesheet" href="/asset/found.css"></head><body><a id="fixture-link" href="/final">fixture-web</a><img src="/asset/found.png"></body></html>'
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $html -ContentType 'text/html; charset=utf-8' -Headers @('Set-Cookie: arkweb_fixture=arkweb-cookie; Path=/')
      }
      '/web-cookie-echo' {
        $cookie = [string]$context.Request.Headers['Cookie']
        $title = if ($cookie.Contains('arkweb_fixture=arkweb-cookie')) { 'fixture-web-cookie-echo-true' } else { 'fixture-web-cookie-echo-false' }
        $html = "<html><head><title>$title</title></head><body>$title</body></html>"
        Write-FixtureResponse -Context $context -StatusCode 200 -Body $html -ContentType 'text/html; charset=utf-8'
      }
      '/asset/found.css' {
        Write-FixtureResponse -Context $context -StatusCode 200 -Body 'body{--fixture-arkweb:1}' -ContentType 'text/css; charset=utf-8'
      }
      '/asset/found.png' {
        Write-FixtureResponse -Context $context -StatusCode 200 -Body 'fixture-image' -ContentType 'image/png'
      }
      '/favicon.ico' {
        Write-FixtureResponse -Context $context -StatusCode 204 -Body '' -ContentType 'image/x-icon'
      }
      default {
        Write-FixtureResponse -Context $context -StatusCode 404 -Body 'fixture-not-found'
      }
    }
  }
} finally {
  if ($listener.IsListening) {
    $listener.Stop()
  }
  $listener.Close()
}
