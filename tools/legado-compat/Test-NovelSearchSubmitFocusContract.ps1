[CmdletBinding()]
param([string]$RepositoryRoot = '', [string]$ResultPath = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Novel search submit focus contract failed: $Message" }
}

function Read-Utf8Text {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) "missing file: $Path"
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

if ($RepositoryRoot.Length -eq 0) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
} else {
  $RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
}
if ($ResultPath.Length -eq 0) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\novel-search-submit-focus-contract.json'
}

$pagePath = Join-Path $RepositoryRoot 'entry\src\main\ets\pages\NovelSearchPage.ets'
try {
  $page = Read-Utf8Text -Path $pagePath
  $methodMarker = 'private dismissSearchInputFocus(): void {'
  $methodStart = $page.IndexOf($methodMarker)
  $searchStart = $page.IndexOf('async doSearch(): Promise<void> {')
  Assert-Contract ($methodStart -ge 0) 'dismiss helper must exist'
  Assert-Contract ($searchStart -gt $methodStart) 'search must follow the dismiss helper'
  Assert-Contract ($page.Contains('this.getUIContext().getFocusController().clearFocus();')) 'submit must clear the focused TextInput through UIContext'
  $searchBody = $page.Substring($searchStart, 1100)
  Assert-Contract ($searchBody.Contains('this.dismissSearchInputFocus();')) 'valid search submission must dismiss the IME before dispatch'
  $resultBranchStart = $page.IndexOf("} else if (this.singleSourceId && this.searchResults.length > 0) {")
  Assert-Contract ($resultBranchStart -ge 0) 'single-source result branch must exist'
  $resultBranch = $page.Substring($resultBranchStart, 1800)
  Assert-Contract ($resultBranch.Contains('List({ space: 8 })')) 'single-source results must use a top-anchored List instead of a centered Scroll viewport'
  Assert-Contract ($resultBranch.Contains(".height('100%')")) 'single-source results List must have an explicit bounded height'
  Assert-Contract ($resultBranch.Contains(".id('novel_search_single_source_results')")) 'single-source results must retain the Hypium evidence identity'
  $result = [pscustomobject][ordered]@{ status = 'passed'; assertions = 8; generatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
} catch {
  $result = [pscustomobject][ordered]@{ status = 'failed'; error = $_.Exception.Message; generatedAt = [DateTimeOffset]::UtcNow.ToString('o') }
}

$directory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
[System.IO.File]::WriteAllText($ResultPath, [string]($result | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Depth 5
if ($result.status -ne 'passed') { exit 1 }
