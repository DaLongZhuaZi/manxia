[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$relativePath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$analyzerPath = Join-Path $RepositoryRoot ($relativePath.Replace('/', '\'))
$backupPath = "$analyzerPath.bak_20260809_direct_child_regex_class"
$bytes = [System.IO.File]::ReadAllBytes($analyzerPath)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw 'source file must not contain a UTF-8 BOM.' }
$source = $strictUtf8.GetString($bytes)
$helperStart = $source.IndexOf('private splitTopLevelDirectChildSelectors(', [System.StringComparison]::Ordinal)
$helperEnd = $source.IndexOf('private findElementsByDirectChildSelector(', $helperStart, [System.StringComparison]::Ordinal)
if ($helperStart -lt 0 -or $helperEnd -le $helperStart) { throw 'source precondition failed: splitter boundary is missing.' }
$helper = $source.Substring($helperStart, $helperEnd - $helperStart)
$unguardedOpen = "if (character === '(') {"
$unguardedClose = "else if (character === ')' && parenthesisDepth > 0) {"
$guardedOpen = "if (character === '(' && bracketDepth === 0) {"
$guardedClose = "else if (character === ')' && parenthesisDepth > 0 && bracketDepth === 0) {"
$openCount = [regex]::Matches($helper, [regex]::Escape($unguardedOpen)).Count
$closeCount = [regex]::Matches($helper, [regex]::Escape($unguardedClose)).Count
if ($openCount -eq 0 -and $closeCount -eq 0) {
  Write-Output "SOURCE_FIX_ALREADY_APPLIED path=$relativePath helper=regex-class-bracket-guard"
  exit 0
}
if ($openCount -ne 1 -or $closeCount -ne 1) { throw "source precondition failed: unguardedOpen=$openCount unguardedClose=$closeCount" }
if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) { [System.IO.File]::Copy($analyzerPath, $backupPath, $false) }
$updatedHelper = $helper.Replace($unguardedOpen, $guardedOpen).Replace($unguardedClose, $guardedClose)
$updated = $source.Substring(0, $helperStart) + $updatedHelper + $source.Substring($helperEnd)
$temporaryPath = "$analyzerPath.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
try { [System.IO.File]::WriteAllText($temporaryPath, $updated, $noBomUtf8); Move-Item -LiteralPath $temporaryPath -Destination $analyzerPath -Force }
finally { if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) } }
$verified = $strictUtf8.GetString([System.IO.File]::ReadAllBytes($analyzerPath))
$verifiedHelperStart = $verified.IndexOf('private splitTopLevelDirectChildSelectors(', [System.StringComparison]::Ordinal)
$verifiedHelperEnd = $verified.IndexOf('private findElementsByDirectChildSelector(', $verifiedHelperStart, [System.StringComparison]::Ordinal)
$verifiedHelper = $verified.Substring($verifiedHelperStart, $verifiedHelperEnd - $verifiedHelperStart)
if (-not $verifiedHelper.Contains($guardedOpen) -or -not $verifiedHelper.Contains($guardedClose) -or $verifiedHelper.Contains($unguardedClose)) { throw 'source postcondition failed: regex-class guards were not installed.' }
Write-Output "SOURCE_FIX_APPLIED path=$relativePath backup=$backupPath helper=regex-class-bracket-guard"
