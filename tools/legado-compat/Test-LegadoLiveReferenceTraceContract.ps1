[CmdletBinding()]
param([string]$RepoRoot = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($RepoRoot.Length -eq 0) {
  $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}

$scriptPath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoLiveReference.ps1'
$singleReferencePath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoSingleSourceReference.ps1'
$parserPath = Join-Path $RepoRoot 'tools\legado-compat\LegadoReferenceTraceParser.psm1'
if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
  throw "Live reference script is missing: $scriptPath"
}
if (-not (Test-Path -LiteralPath $parserPath -PathType Leaf)) {
  throw "Reference trace parser is missing: $parserPath"
}
if (-not (Test-Path -LiteralPath $singleReferencePath -PathType Leaf)) {
  throw "Single-source reference script is missing: $singleReferencePath"
}

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
if ($errors.Count -ne 0) {
  throw 'Live reference trace contract failed: PowerShell parse error.'
}
$functionAst = $ast.Find({
  param($node)
  return $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-LiveReferenceTraces'
}, $true)
if ($null -eq $functionAst) {
  throw 'Live reference trace contract failed: Get-LiveReferenceTraces is missing.'
}
$text = $functionAst.Extent.Text
$singleReferenceText = [System.IO.File]::ReadAllText($singleReferencePath, [System.Text.UTF8Encoding]::new($false))
$requiredMarkers = @(
  "'logcat', '-d', '-v', 'raw'",
  "'^[A-F0-9]{64}/[0-3]$'",
  'Read-LegadoReferenceTraceRecords'
)
foreach ($marker in $requiredMarkers) {
  if ($text.IndexOf($marker, [System.StringComparison]::Ordinal) -lt 0) {
    throw "Live reference trace contract failed: missing $marker"
  }
}
if ($singleReferenceText.IndexOf('reference_trace_legacy_log_truncated', [System.StringComparison]::Ordinal) -lt 0 -or
  $singleReferenceText.IndexOf('logResult.output.Length -ge 4000', [System.StringComparison]::Ordinal) -lt 0) {
  throw 'Live reference trace contract failed: stale single-line Android log truncation must be explicitly classified.'
}
Import-Module -Name $parserPath -Force -ErrorAction Stop
$hash = ('A' * 64)
$attemptId = "$hash/2"
$payload = ('{"attemptId":"' + $attemptId + '","stage":"content","outcome":"complete"}')
$firstLength = [Math]::Floor($payload.Length / 2)
$parts = @(
  ('LEGADO_LIVE_TRACE_PART:1/2:' + $payload.Substring(0, $firstLength)),
  ('LEGADO_LIVE_TRACE_PART:2/2:' + $payload.Substring($firstLength))
)
$fragmented = Read-LegadoReferenceTraceRecords -Lines $parts -AttemptIdPattern '^[A-F0-9]{64}/[0-3]$'
if (-not $fragmented.ContainsKey($attemptId) -or [string]$fragmented[$attemptId].outcome -ne 'complete') {
  throw 'Live reference trace contract failed: complete ordered fragments were not reconstructed.'
}
$partial = Read-LegadoReferenceTraceRecords -Lines @($parts[0]) -AttemptIdPattern '^[A-F0-9]{64}/[0-3]$'
if ($partial.Count -ne 0) {
  throw 'Live reference trace contract failed: an incomplete fragment set was accepted.'
}
$outOfOrder = Read-LegadoReferenceTraceRecords -Lines @($parts[1], $parts[0]) -AttemptIdPattern '^[A-F0-9]{64}/[0-3]$'
if ($outOfOrder.Count -ne 0) {
  throw 'Live reference trace contract failed: an out-of-order fragment sequence was accepted.'
}
$legacy = Read-LegadoReferenceTraceRecords -Lines @('LEGADO_LIVE_TRACE:' + $payload) -AttemptIdPattern '^[A-F0-9]{64}/[0-3]$'
if (-not $legacy.ContainsKey($attemptId)) {
  throw 'Live reference trace contract failed: legacy single-line traces no longer parse.'
}
$oversized = Read-LegadoReferenceTraceRecords -Lines @('LEGADO_LIVE_TRACE_PART:1/33:' + $payload) -AttemptIdPattern '^[A-F0-9]{64}/[0-3]$'
if ($oversized.Count -ne 0) {
  throw 'Live reference trace contract failed: an oversized fragment declaration was accepted.'
}
$empty = Read-LegadoReferenceTraceRecords -Lines @('') -AttemptIdPattern '^[A-F0-9]{64}/[0-3]$'
if ($empty.Count -ne 0) {
  throw 'Live reference trace contract failed: an empty raw-log record was accepted.'
}

[pscustomobject][ordered]@{
  status = 'passed'
  assertions = $requiredMarkers.Count + 6
  script = $scriptPath
  parser = $parserPath
} | ConvertTo-Json -Depth 3
