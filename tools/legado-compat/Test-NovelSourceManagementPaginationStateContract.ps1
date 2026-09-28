[CmdletBinding()]
param([string]$RepoRoot = '', [string]$ResultPath = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Novel source pagination state contract failed: $Message" }
}

function Read-Utf8Text {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) "missing file: $Path"
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

if ($RepoRoot.Length -eq 0) {
  $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}
if ($ResultPath.Length -eq 0) {
  $ResultPath = Join-Path $RepoRoot 'tools\legado-compat\evidence\novel-source-pagination-state-contract.json'
}

$pagePath = Join-Path $RepoRoot 'entry\src\main\ets\pages\NovelSourceManagementPage.ets'

try {
  $text = Read-Utf8Text -Path $pagePath
  Assert-Contract ($text.Contains('@State private hasMoreData: boolean = true;')) 'visible pagination completion must be reactive'
  Assert-Contract ($text.Contains('this.hasMoreData = endIndex < this.filteredSources.length;')) 'page completion must be recomputed after every page append'
  Assert-Contract ($text.Contains('if (this.hasMoreData && !this.isSortMode) {')) 'loading footer must remain conditional on additional data'
  Assert-Contract (-not ($text -match '(?m)^\s{2}private hasMoreData: boolean = true;$')) 'non-reactive pagination completion must not return'
  $result = [pscustomobject][ordered]@{ status = 'passed'; assertions = 4; generatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
} catch {
  $result = [pscustomobject][ordered]@{ status = 'failed'; error = $_.Exception.Message; generatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
}

$directory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
[System.IO.File]::WriteAllText($ResultPath, [string]($result | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Depth 5
if ($result.status -ne 'passed') { exit 1 }
