[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = '',
  [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
if ([string]::IsNullOrWhiteSpace($FixturePath)) {
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-java-string-list-css-composition.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-java-string-list-css-composition.json'
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Legado java.getStringList CSS composition contract failed: $Message" }
}

function Read-Utf8Json {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) "missing fixture: $Path"
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
}

$result = $null
try {
  $runtimePath = Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html'
  $runtime = [System.IO.File]::ReadAllText($runtimePath, [System.Text.UTF8Encoding]::new($false, $true))
  $fixture = Read-Utf8Json -Path $FixturePath

  Assert-Contract ($runtime.Contains('legadoCreateJavaList')) 'java list bridge must expose Legado collection methods.'
  Assert-Contract ($runtime.Contains('legadoNormalizeCssRule')) 'CSS rules must normalize the @CSS prefix.'
  Assert-Contract ($runtime.Contains('legadoGetStringListSingle')) 'CSS extraction must be separated from composition.'
  Assert-Contract ($runtime.Contains("legadoJsonPathSplitCombinators(text, ['&&', '||', '%%'])")) 'CSS list extraction must use the first-operator recursive splitter.'
  Assert-Contract (-not $runtime.Contains("String(rule || '').split('##')[0].split('&&')[0]")) 'legacy truncation of non-JSON CSS rules must be removed.'
  Assert-Contract ($runtime.Contains('var values = legadoGetStringList(rule, sourceText);')) 'java.getString must consume the same CSS list contract.'
  Assert-Contract ($runtime.Contains('return legadoGetStringList(rule, sourceText);')) 'java.getStringList must preserve replacement and composition input.'
  Assert-Contract (@($fixture.cases).Count -eq 5) 'fixture must cover fallback, merge, interleave, prefix and replacement.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.firstOperator -eq '||' }).Count -eq 1) 'fixture must cover CSS || fallback.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.firstOperator -eq '&&' }).Count -eq 1) 'fixture must cover CSS && merge.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.firstOperator -eq '%%' }).Count -eq 1) 'fixture must cover CSS %% interleave.'
  Assert-Contract (@($fixture.cases | Where-Object { [string]$_.rule -like '@css:*' }).Count -eq 1) 'fixture must cover @CSS prefix normalization.'

  $result = [pscustomobject][ordered]@{
    status = 'passed'
    contract = 'legado_java_string_list_css_composition'
    assertions = 12
    fixture = [System.IO.Path]::GetRelativePath($RepositoryRoot, $FixturePath).Replace('\\', '/')
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    verification = 'static_source_contract_only;runtime_regression_deferred'
  }
} catch {
  $result = [pscustomobject][ordered]@{
    status = 'failed'
    contract = 'legado_java_string_list_css_composition'
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
}

$directory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
[System.IO.File]::WriteAllText($ResultPath, [string]($result | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') { exit 1 }
