[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$RelativePath); return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Write-AtomicUtf8 {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Text)
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try { [System.IO.File]::WriteAllText($temporaryPath, $Text, $utf8NoBom); Move-Item -LiteralPath $temporaryPath -Destination $Path -Force }
  finally { if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) } }
}

$path = Get-RepoPath 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$text = [System.IO.File]::ReadAllText($path, [System.Text.UTF8Encoding]::new($false, $true))
$pattern = '(?s)  private matchesStringNestedSelector\(element: string, selector: string\): boolean \{.*?\r?\n  \}\r?\n\r?\n  private normalizeLegadoPseudoArgument'
$replacement = @'
  private matchesStringNestedSelector(
    element: string,
    selector: string,
    contextHtml: string
  ): boolean {
    const normalizedSelector = selector.trim();
    if (normalizedSelector.length === 0) {
      return false;
    }

    const occurrences = this.mapStringElementOccurrences(contextHtml, [element]);
    if (occurrences.length === 0) {
      return this.matchesStringNestedSelectorWithoutContext(element, normalizedSelector);
    }

    const target = occurrences[0];
    const parentStart = this.findParentStartTag(contextHtml, target.startIndex);
    if (parentStart < 0 || parentStart === target.startIndex) {
      return this.matchesStringNestedSelectorWithoutContext(element, normalizedSelector);
    }
    const parentTag = this.extractTagNameAt(contextHtml, parentStart);
    if (parentTag.length === 0) {
      return this.matchesStringNestedSelectorWithoutContext(element, normalizedSelector);
    }
    const parentElement = this.extractElement(contextHtml, parentStart, parentTag);
    if (parentElement === null) {
      return this.matchesStringNestedSelectorWithoutContext(element, normalizedSelector);
    }

    // Keep the candidate's parent and ancestor-visible sibling context in the
    // synthetic document. This lets complex :not selectors use the same
    // ancestor/combinator semantics as Jsoup Element.select.
    const wrapper = `<legado-not-root>${parentElement}</legado-not-root>`;
    const matches = this.findElementsBySingleSelector(wrapper, normalizedSelector);
    const matchedOccurrences = this.mapStringElementOccurrences(wrapper, matches);
    const wrapperOpeningEnd = this.findHtmlTagEnd(wrapper, 0);
    if (wrapperOpeningEnd < 0) {
      return false;
    }
    const targetRelativeStart = wrapperOpeningEnd + 1 + (target.startIndex - parentStart);
    for (const match of matchedOccurrences) {
      if (match.startIndex === targetRelativeStart) {
        return true;
      }
    }
    return false;
  }

  private matchesStringNestedSelectorWithoutContext(element: string, selector: string): boolean {
    const wrapper = `<legado-not-root>${element}</legado-not-root>`;
    const matches = this.findElementsBySingleSelector(wrapper, selector);
    return matches.some((match: string): boolean => match === element);
  }

  private normalizeLegadoPseudoArgument
'@
$matches = [regex]::Matches($text, $pattern)
if ($matches.Count -ne 1) { throw "Expected one candidate-only :not method, found $($matches.Count)." }
$text = [regex]::Replace($text, $pattern, $replacement.TrimEnd("`r", "`n"), 1)
$oldCall = 'this.matchesStringNestedSelector(element, argument)'
$newCall = 'this.matchesStringNestedSelector(element, argument, contextHtml)'
$callCount = ([regex]::Matches($text, [regex]::Escape($oldCall))).Count
if ($callCount -ne 1) { throw "Expected one :not call without context, found $callCount." }
$text = $text.Replace($oldCall, $newCall)
Write-AtomicUtf8 -Path $path -Text $text
[pscustomobject][ordered]@{
  status = 'applied'
  changedPaths = @('entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets')
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
} | ConvertTo-Json -Depth 20
