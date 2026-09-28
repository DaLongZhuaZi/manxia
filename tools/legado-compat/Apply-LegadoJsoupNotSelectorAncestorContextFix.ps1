[CmdletBinding()]
param([string]$RepositoryRoot = '')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$relativePath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$path = Join-Path $RepositoryRoot $relativePath
$text = $utf8Strict.GetString([System.IO.File]::ReadAllBytes($path))

function Replace-Required {
  param([Parameter(Mandatory = $true)][string]$Old, [Parameter(Mandatory = $true)][string]$New, [Parameter(Mandatory = $true)][string]$Label)
  if (-not $script:text.Contains($Old)) { throw "Missing source pattern: $Label" }
  $script:text = $script:text.Replace($Old, $New)
}

Replace-Required 'const found = this.findElementsBySingleSelector(element, part);' 'const found = this.findElementsBySingleSelector(element, part, this.content);' 'root context at CSS chain boundary'
Replace-Required 'private findElementsBySingleSelector(html: string, selector: string): string[] {' @'
private findElementsBySingleSelector(
    html: string,
    selector: string,
    selectorContextHtml: string = ''
  ): string[] {
    const effectiveContextHtml = selectorContextHtml.length > 0 ? selectorContextHtml : html;
'@ 'typed selector context'
Replace-Required 'const groupResults = this.findElementsBySingleSelector(html, group);' 'const groupResults = this.findElementsBySingleSelector(html, group, effectiveContextHtml);' 'selector group context'
Replace-Required 'return this.findElementsBySimpleSelector(html, selector);' 'return this.findElementsBySimpleSelector(html, selector, effectiveContextHtml);' 'simple selector context'
Replace-Required 'const directChildResults = this.findElementsByDirectChildSelector(html, selector);' 'const directChildResults = this.findElementsByDirectChildSelector(html, selector, effectiveContextHtml);' 'direct child selector context'
Replace-Required 'found = this.findElementsBySimpleSelector(element, part);' 'found = this.findElementsBySimpleSelector(element, part, effectiveContextHtml);' 'descendant selector context'

Replace-Required 'private findElementsBySimpleSelector(html: string, selector: string): string[] {' @'
private findElementsBySimpleSelector(
    html: string,
    selector: string,
    selectorContextHtml: string = ''
  ): string[] {
    const effectiveContextHtml = selectorContextHtml.length > 0 ? selectorContextHtml : html;
'@ 'typed simple selector context'
Replace-Required 'pseudoSelectors, html)' 'pseudoSelectors, effectiveContextHtml)' 'pseudo filter root context'

Replace-Required @'
        filtered = filtered.filter((element: string): boolean => {
          return !this.matchesStringNestedSelector(element, argument, contextHtml);
        });
'@ @'
        if (contextHtml.length === 0) {
          filtered = filtered.filter((element: string): boolean => {
            return !this.matchesStringNestedSelector(element, argument, contextHtml);
          });
        } else {
          const contextOccurrences = this.mapStringElementOccurrences(contextHtml, filtered);
          const contextFiltered: string[] = [];
          for (let elementIndex = 0; elementIndex < filtered.length; elementIndex++) {
            const element = filtered[elementIndex];
            if (contextOccurrences.length === filtered.length) {
              const occurrence = contextOccurrences[elementIndex];
              if (!this.matchesStringNestedSelectorAtOccurrence(element, argument, contextHtml, occurrence.startIndex)) {
                contextFiltered.push(element);
              }
            } else if (!this.matchesStringNestedSelector(element, argument, contextHtml)) {
              contextFiltered.push(element);
            }
          }
          filtered = contextFiltered;
        }
'@ 'occurrence-aware not dispatch'

Replace-Required @'
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
'@ @'
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
    return this.matchesStringNestedSelectorAtOccurrence(element, normalizedSelector, contextHtml, target.startIndex);
  }

  private matchesStringNestedSelectorAtOccurrence(
    element: string,
    selector: string,
    contextHtml: string,
    candidateStartIndex: number
  ): boolean {
    const normalizedSelector = selector.trim();
    if (normalizedSelector.length === 0) {
      return false;
    }
    if (contextHtml.length === 0 || candidateStartIndex < 0) {
      return this.matchesStringNestedSelectorWithoutContext(element, normalizedSelector);
    }
    const parentStart = this.findParentStartTag(contextHtml, candidateStartIndex);
    if (parentStart < 0 || parentStart === candidateStartIndex) {
      return this.matchesStringNestedSelectorWithoutContext(element, normalizedSelector);
    }
    const wrapper = `<legado-not-root>${contextHtml}</legado-not-root>`;
    const matches = this.findElementsBySingleSelector(wrapper, normalizedSelector, wrapper);
    const matchedOccurrences = this.mapStringElementOccurrences(wrapper, matches);
    const wrapperOpeningEnd = this.findHtmlTagEnd(wrapper, 0);
    if (wrapperOpeningEnd < 0) {
      return false;
    }
    const targetRelativeStart = wrapperOpeningEnd + 1 + candidateStartIndex;
    for (const match of matchedOccurrences) {
      if (match.startIndex === targetRelativeStart) {
        return true;
      }
    }
    return false;
  }
'@ 'full-root occurrence projection'

Replace-Required 'private findElementsByDirectChildSelector(html: string, selector: string): string[] {' @'
private findElementsByDirectChildSelector(
    html: string,
    selector: string,
    selectorContextHtml: string = ''
  ): string[] {
    const effectiveContextHtml = selectorContextHtml.length > 0 ? selectorContextHtml : html;
'@ 'direct-child context signature'
Replace-Required 'let currentElements = this.findElementsBySimpleSelector(html, firstSelector);' 'let currentElements = this.findElementsBySimpleSelector(html, firstSelector, effectiveContextHtml);' 'direct-child first context'
Replace-Required 'const matches = this.findElementsBySimpleSelector(scopedParent, childSelector);' 'const matches = this.findElementsBySimpleSelector(scopedParent, childSelector, effectiveContextHtml);' 'direct-child child context'

$temp = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
try {
  [System.IO.File]::WriteAllText($temp, $text, $utf8NoBom)
  Move-Item -LiteralPath $temp -Destination $path -Force
} finally {
  if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) }
}

[pscustomobject][ordered]@{
  status = 'applied'
  changedPath = $relativePath
  rootContext = $true
  occurrenceAwareNot = $true
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
} | ConvertTo-Json -Depth 20
