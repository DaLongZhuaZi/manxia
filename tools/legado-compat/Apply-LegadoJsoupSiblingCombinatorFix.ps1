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

Replace-Required @'
    selector = indexResult.selector;

    if (selector.includes('>')) {
      const directChildResults = this.findElementsByDirectChildSelector(html, selector, effectiveContextHtml);
'@ @'
    selector = indexResult.selector;

    const siblingChain = this.splitTopLevelCssSiblingCombinatorSelector(selector);
    if (siblingChain !== null) {
      return this.findElementsByCssCombinatorChain(html, siblingChain, effectiveContextHtml);
    }

    if (selector.includes('>')) {
      const directChildResults = this.findElementsByDirectChildSelector(html, selector, effectiveContextHtml);
'@ 'sibling dispatch before direct-child path'

Replace-Required @'
  private splitTopLevelDirectChildSelectors(selector: string): string[] {
'@ @'
  private splitTopLevelCssSiblingCombinatorSelector(selector: string): StringCssCombinatorChain | null {
    const parts: string[] = [];
    const combinators: string[] = [];
    let current = '';
    let parenthesisDepth = 0;
    let bracketDepth = 0;
    let quote = '';
    let escaped = false;
    let hasSiblingCombinator = false;
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
      if (character === '(' && bracketDepth === 0) {
        parenthesisDepth++;
        current += character;
        continue;
      }
      if (character === ')' && parenthesisDepth > 0 && bracketDepth === 0) {
        parenthesisDepth--;
        current += character;
        continue;
      }
      if (character === '[') {
        bracketDepth++;
        current += character;
        continue;
      }
      if (character === ']' && bracketDepth > 0) {
        bracketDepth--;
        current += character;
        continue;
      }
      if (parenthesisDepth === 0 && bracketDepth === 0 &&
        (character === '>' || character === '+' || character === '~')) {
        const part = current.trim();
        if (part.length === 0) {
          return null;
        }
        parts.push(part);
        combinators.push(character);
        hasSiblingCombinator = hasSiblingCombinator || character === '+' || character === '~';
        current = '';
        continue;
      }
      current += character;
    }
    const lastPart = current.trim();
    if (!hasSiblingCombinator || lastPart.length === 0) {
      return null;
    }
    parts.push(lastPart);
    if (parts.length !== combinators.length + 1) {
      return null;
    }
    return { parts: parts, combinators: combinators };
  }

  private findElementsByCssCombinatorChain(
    html: string,
    chain: StringCssCombinatorChain,
    selectorContextHtml: string
  ): string[] {
    const effectiveContextHtml = selectorContextHtml.length > 0 ? selectorContextHtml : html;
    if (chain.parts.length < 2 || chain.combinators.length !== chain.parts.length - 1) {
      return [];
    }
    const firstMatches = this.findElementsBySingleSelector(html, chain.parts[0], effectiveContextHtml);
    let currentOccurrences = this.mapStringElementOccurrences(effectiveContextHtml, firstMatches);
    if (currentOccurrences.length !== firstMatches.length) {
      return [];
    }
    for (let partIndex = 1; partIndex < chain.parts.length; partIndex++) {
      const candidateMatches = this.findElementsBySingleSelector(
        effectiveContextHtml,
        chain.parts[partIndex],
        effectiveContextHtml
      );
      const candidateOccurrences = this.mapStringElementOccurrences(effectiveContextHtml, candidateMatches);
      if (candidateOccurrences.length !== candidateMatches.length) {
        return [];
      }
      const nextOccurrences: StringElementOccurrence[] = [];
      const seenOffsets = new Set<number>();
      const combinator = chain.combinators[partIndex - 1];
      for (const candidate of candidateOccurrences) {
        for (const previous of currentOccurrences) {
          if (this.matchesStringCombinatorRelation(effectiveContextHtml, previous, candidate, combinator)) {
            if (!seenOffsets.has(candidate.startIndex)) {
              seenOffsets.add(candidate.startIndex);
              nextOccurrences.push(candidate);
            }
            break;
          }
        }
      }
      currentOccurrences = nextOccurrences;
      if (currentOccurrences.length === 0) {
        return [];
      }
    }
    return currentOccurrences.map((occurrence: StringElementOccurrence): string => occurrence.element);
  }

  private matchesStringCombinatorRelation(
    contextHtml: string,
    previous: StringElementOccurrence,
    candidate: StringElementOccurrence,
    combinator: string
  ): boolean {
    const candidateParentStart = this.findParentStartTag(contextHtml, candidate.startIndex);
    if (candidateParentStart < 0) {
      return false;
    }
    if (combinator === '>') {
      return candidateParentStart === previous.startIndex;
    }
    const previousParentStart = this.findParentStartTag(contextHtml, previous.startIndex);
    if (previousParentStart < 0 || previousParentStart !== candidateParentStart) {
      return false;
    }
    const previousPosition = this.getStringElementSiblingPosition(contextHtml, previous);
    const candidatePosition = this.getStringElementSiblingPosition(contextHtml, candidate);
    if (previousPosition === null || candidatePosition === null) {
      return false;
    }
    if (combinator === '+') {
      return candidatePosition.siblingIndex === previousPosition.siblingIndex + 1;
    }
    if (combinator === '~') {
      return candidatePosition.siblingIndex > previousPosition.siblingIndex;
    }
    return false;
  }

  private splitTopLevelDirectChildSelectors(selector: string): string[] {
'@ 'sibling chain parser and relation matcher'

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
  siblingCombinators = @('+', '~')
  mixedChildCombinators = $true
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
} | ConvertTo-Json -Depth 20
