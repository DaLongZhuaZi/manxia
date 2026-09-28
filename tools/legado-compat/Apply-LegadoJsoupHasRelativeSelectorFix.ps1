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
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Write-AtomicUtf8 {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Text
  )
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, $Text, $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      [System.IO.File]::Delete($temporaryPath)
    }
  }
}

$analyzerPath = Get-RepoPath 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$analyzer = [System.IO.File]::ReadAllText($analyzerPath, [System.Text.UTF8Encoding]::new($false, $true))
$oldAnalyzer = "        if (matches.some((match: string): boolean => match === child)) {"
$newAnalyzer = @'
        // A relative :has selector may continue past the direct child, e.g.
        // `:has(>div span)`. Jsoup evaluates the whole relative selector from
        // the parent; requiring the result to equal the direct child rejects
        // valid descendant matches below that child.
        if (matches.some((match: string): boolean => match !== wrapper)) {
'@
$analyzerCount = ([regex]::Matches($analyzer, [regex]::Escape($oldAnalyzer))).Count
if ($analyzerCount -ne 1) {
  throw "Expected one string fallback :has equality check, found $analyzerCount."
}
$analyzer = $analyzer.Replace($oldAnalyzer, $newAnalyzer.TrimEnd("`r", "`n"))
Write-AtomicUtf8 -Path $analyzerPath -Text $analyzer

$elementPath = Get-RepoPath 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$element = [System.IO.File]::ReadAllText($elementPath, [System.Text.UTF8Encoding]::new($false, $true))
$oldElementPattern = '(?s)        for \(const child of elem\.children\) \{\r?\n          if \(child\.matches\(childSelector\)\) \{\r?\n            return true;\r?\n          \}\r?\n        \}\r?\n        return false;'
$newElement = @'
        return this.matchesHasDirectChildRelativeSelector(elem, childSelector);
'@
$elementMatches = [regex]::Matches($element, $oldElementPattern)
if ($elementMatches.Count -ne 1) {
  throw "Expected one DOM direct-child :has matcher, found $($elementMatches.Count)."
}
$element = [regex]::Replace($element, $oldElementPattern, $newElement.TrimEnd("`r", "`n"), 1)
$marker = "  private selectorContainsInvalidRegexAttribute(selector: string): boolean {"
$helper = @'
  /**
   * Evaluates a Jsoup relative selector against the direct children of an
   * element. The selector may continue below the direct child (for example
   * `>div span`), so matching only with child.matches() is insufficient.
   */
  private matchesHasDirectChildRelativeSelector(elem: HTMLElement, selector: string): boolean {
    const matches = elem.querySelectorAll(selector);
    for (const match of matches) {
      let current: HTMLElement | null = match;
      while (current !== null) {
        const parentNode = current.parentNode;
        if (parentNode === elem) {
          return true;
        }
        if (parentNode === null || parentNode.nodeType !== NodeType.ELEMENT_NODE) {
          break;
        }
        current = parentNode as HTMLElement;
      }
    }
    return false;
  }

'@
$markerCount = ([regex]::Matches($element, [regex]::Escape($marker))).Count
if ($markerCount -ne 1) {
  throw "Expected one DOM selector helper insertion marker, found $markerCount."
}
$element = $element.Replace($marker, $helper + $marker)
Write-AtomicUtf8 -Path $elementPath -Text $element

[pscustomobject][ordered]@{
  status = 'applied'
  changedPaths = @(
    'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
    'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
  )
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
} | ConvertTo-Json -Depth 20
