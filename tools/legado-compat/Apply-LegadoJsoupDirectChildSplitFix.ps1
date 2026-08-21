[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$relativePath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$analyzerPath = Join-Path $RepositoryRoot ($relativePath.Replace('/', '\'))
$backupPath = "$analyzerPath.bak_20260809_direct_child_split"

if (-not (Test-Path -LiteralPath $analyzerPath -PathType Leaf)) {
  throw "required source file is missing: $relativePath"
}
$sourceBytes = [System.IO.File]::ReadAllBytes($analyzerPath)
if ($sourceBytes.Length -ge 3 -and $sourceBytes[0] -eq 0xEF -and $sourceBytes[1] -eq 0xBB -and $sourceBytes[2] -eq 0xBF) {
  throw 'source file must not contain a UTF-8 BOM.'
}
$source = $strictUtf8.GetString($sourceBytes)
$marker = '  private findElementsByDirectChildSelector(html: string, selector: string): string[] {'
$oldSplit = "const parts = selector.split('>');"
$helperMarker = 'private splitTopLevelDirectChildSelectors(selector: string)'
$markerCount = [regex]::Matches($source, [regex]::Escape($marker)).Count
$oldSplitCount = [regex]::Matches($source, [regex]::Escape($oldSplit)).Count
$helperCount = [regex]::Matches($source, [regex]::Escape($helperMarker)).Count
if ($helperCount -gt 0) {
  Write-Output "SOURCE_FIX_ALREADY_APPLIED path=$relativePath helperCount=$helperCount"
  exit 0
}
if ($markerCount -ne 1 -or $oldSplitCount -ne 1) {
  throw "source precondition failed: markerCount=$markerCount oldSplitCount=$oldSplitCount helperCount=$helperCount"
}

if (-not (Test-Path -LiteralPath $backupPath -PathType Leaf)) {
  [System.IO.File]::Copy($analyzerPath, $backupPath, $false)
}

$newline = if ($source.Contains("`r`n")) { "`r`n" } else { "`n" }
$helper = @'
  private splitTopLevelDirectChildSelectors(selector: string): string[] {
    const parts: string[] = [];
    let current = '';
    let parenthesisDepth = 0;
    let bracketDepth = 0;
    let quote = '';
    let escaped = false;
    for (let index = 0; index < selector.length; index++) {
      const character = selector[index];
      if (escaped) {
        current += character;
        escaped = false;
        continue;
      }
      if (character === '\\') {
        current += character;
        escaped = true;
        continue;
      }
      if (quote.length > 0) {
        current += character;
        if (character === quote) {
          quote = '';
        }
        continue;
      }
      if (character === '"' || character === "'") {
        quote = character;
        current += character;
        continue;
      }
      if (character === '(') {
        parenthesisDepth++;
      } else if (character === ')' && parenthesisDepth > 0) {
        parenthesisDepth--;
      } else if (character === '[') {
        bracketDepth++;
      } else if (character === ']' && bracketDepth > 0) {
        bracketDepth--;
      }
      if (character === '>' && parenthesisDepth === 0 && bracketDepth === 0) {
        parts.push(current.trim());
        current = '';
      } else {
        current += character;
      }
    }
    parts.push(current.trim());
    return parts;
  }
'@
$helper = $helper.TrimEnd("`r", "`n") + $newline

$markerIndex = $source.IndexOf($marker, [System.StringComparison]::Ordinal)
$updated = $source.Substring(0, $markerIndex) + $helper + $source.Substring($markerIndex)
$updated = $updated.Replace($oldSplit, "const parts = this.splitTopLevelDirectChildSelectors(selector);")

$temporaryPath = "$analyzerPath.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
try {
  [System.IO.File]::WriteAllText($temporaryPath, $updated, $noBomUtf8)
  Move-Item -LiteralPath $temporaryPath -Destination $analyzerPath -Force
} finally {
  if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
}

$verified = $strictUtf8.GetString([System.IO.File]::ReadAllBytes($analyzerPath))
$verifiedFunctionStart = $verified.IndexOf($marker, [System.StringComparison]::Ordinal)
$verifiedFunctionEnd = $verified.IndexOf('private getElementsByRegex(', $verifiedFunctionStart, [System.StringComparison]::Ordinal)
if ($verifiedFunctionStart -lt 0 -or $verifiedFunctionEnd -le $verifiedFunctionStart) {
  throw 'source postcondition failed: direct-child function boundary is missing.'
}
$verifiedFunction = $verified.Substring($verifiedFunctionStart, $verifiedFunctionEnd - $verifiedFunctionStart)
if (-not $verifiedFunction.Contains('splitTopLevelDirectChildSelectors(selector)') -or $verifiedFunction.Contains($oldSplit)) {
  throw 'source postcondition failed: top-level-aware split was not installed.'
}
Write-Output "SOURCE_FIX_APPLIED path=$relativePath backup=$backupPath helper=$helperMarker"
