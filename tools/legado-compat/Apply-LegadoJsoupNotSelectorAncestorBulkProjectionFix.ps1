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
'@ @'
        } else {
          const contextOccurrences = this.mapStringElementOccurrences(contextHtml, filtered);
          const contextFiltered: string[] = [];
          if (contextOccurrences.length === filtered.length) {
            const matchedOffsets = this.collectNestedSelectorMatchOffsets(contextHtml, argument);
            for (let elementIndex = 0; elementIndex < filtered.length; elementIndex++) {
              const element = filtered[elementIndex];
              const occurrence = contextOccurrences[elementIndex];
              if (!matchedOffsets.has(occurrence.startIndex)) {
                contextFiltered.push(element);
              }
            }
          } else {
            for (const element of filtered) {
              if (!this.matchesStringNestedSelector(element, argument, contextHtml)) {
                contextFiltered.push(element);
              }
            }
          }
          filtered = contextFiltered;
        }
'@ 'bulk :not projection'

Replace-Required @'
  private matchesStringNestedSelector(
'@ @'
  private collectNestedSelectorMatchOffsets(contextHtml: string, selector: string): Set<number> {
    const matchedOffsets = new Set<number>();
    const selectorGroups = this.splitTopLevelCssSelectorGroups(selector);
    for (const selectorGroup of selectorGroups) {
      const matches = this.findElementsBySingleSelector(contextHtml, selectorGroup, contextHtml);
      const occurrences = this.mapStringElementOccurrences(contextHtml, matches);
      for (const occurrence of occurrences) {
        matchedOffsets.add(occurrence.startIndex);
      }
    }
    return matchedOffsets;
  }

  private matchesStringNestedSelector(
'@ 'bulk offset helper'

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
  bulkProjection = $true
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
} | ConvertTo-Json -Depth 20
