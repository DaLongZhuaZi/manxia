[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-text-own-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-text-own-context-pre-fix-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-text-own-context-post-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$textRulePattern = "(?<![A-Za-z0-9_])text\.[^@\r\n`"']+@[A-Za-z][A-Za-z0-9_-]*"
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'
$script:textRuleHits = New-Object 'System.Collections.Generic.List[object]'

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }; return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "required file is missing: $Path" }; $bytes = [System.IO.File]::ReadAllBytes($resolved); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }; return $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100) }
function Assert-Contract { param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @()); if (-not $Condition) { throw "243 text own-context post-fix contract failed: $Detail" }; $script:assertions++; [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) }) }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }
function Find-TextRules { param([object]$Value, [string]$Path, [int]$Ordinal)
  if ($null -eq $Value) { return }
  if ($Value -is [string]) {
    foreach ($match in [regex]::Matches([string]$Value, $textRulePattern)) { [void]$script:textRuleHits.Add([pscustomobject][ordered]@{ ordinal = $Ordinal; path = $Path; rule = $match.Value }) }
    return
  }
  if ($Value -is [System.Collections.IEnumerable]) {
    $index = 0
    foreach ($item in $Value) { Find-TextRules -Value $item -Path ($Path + '[' + $index + ']') -Ordinal $Ordinal; $index++ }
    return
  }
  foreach ($property in $Value.PSObject.Properties) { Find-TextRules -Value $property.Value -Path ($Path + '.' + $property.Name) -Ordinal $Ordinal }
}

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$bridgePath = 'entry/src/main/ets/libs/htmlparser/LegadoHtmlBridge.ets'
$elementPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$bridge = Read-StrictText $bridgePath
$element = Read-StrictText $elementPath
$legado = Read-StrictText $legadoPath
$sourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
$packageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePackagePath).Hash.ToUpperInvariant()
$sources = @($strictUtf8.GetString([System.IO.File]::ReadAllBytes($sourcePackagePath)) | ConvertFrom-Json -Depth 100)
for ($index = 0; $index -lt $sources.Count; $index++) { Find-TextRules -Value $sources[$index] -Path '$' -Ordinal ($index + 1) }
$sourceOrdinals = @($script:textRuleHits | ForEach-Object { [int]$_.ordinal } | Sort-Object -Unique)
$uniqueRules = @($script:textRuleHits | ForEach-Object { [string]$_.rule } | Sort-Object -Unique)
$textStart = $bridge.IndexOf('  private findByTextInContext(context: HTMLElement, searchText: string): HTMLElement[] {')
$textEnd = $bridge.IndexOf("`r`n  /**", $textStart + 1)
if ($textEnd -lt 0) { $textEnd = $bridge.IndexOf("`n  /**", $textStart + 1) }
$textBody = if ($textStart -ge 0 -and $textEnd -gt $textStart) { $bridge.Substring($textStart, $textEnd - $textStart) } else { '' }

Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit -and $packageHash -eq $baselineHash -and $sources.Count -eq 458) 'baseline' 'machine state and frozen package remain bound to the same baseline.' @('tools/legado-compat/state/full-source-validation-state.json', $FixturePath)
Assert-Contract ([string]$fixture.issueId -eq $issueId -and [string]$fixture.contract -eq 'legado_jsoup_text_rule_own_context' -and @($fixture.cases).Count -eq 4) 'fixture_shape' 'the text-own-context fixture retains all semantic cases.' @($FixturePath)
Assert-Contract ([string]$failure.status -eq 'failed' -and @($failure.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed) 'failure_witness_preserved' 'the pre-fix witness remains failed and static-only.' @($FailureWitnessPath)
Assert-Contract ($script:textRuleHits.Count -eq [int]$fixture.affectedSourceSet.ruleOccurrenceCount -and $sourceOrdinals.Count -eq [int]$fixture.affectedSourceSet.sourceCount -and $uniqueRules.Count -eq [int]$fixture.affectedSourceSet.uniqueRuleCount) 'frozen_capability_matrix' 'the frozen text.xxx usage matrix remains 144 occurrences across 96 sources and 48 unique shapes.' @($FixturePath)
Assert-Contract ($bridge.Contains('return this.findByTextInContext(this.root, searchText);')) 'root_text_delegation' 'root text lookup shares the same context-aware own-text implementation.' @($bridgePath)
Assert-Contract ($textBody.Contains("const allElements = context.select('*');") -and $textBody.Contains('if (elem.ownText.includes(searchText))') -and -not $textBody.Contains('context.getElementsByTagName') -and -not $textBody.Contains('elem.text.includes(searchText)')) 'own_text_context_selection' 'text.xxx evaluates the current normal context plus descendants using own text only.' @($bridgePath)
Assert-Contract ($element.Contains('  get ownText(): string {') -and $element.Contains('const accumulator = new LegadoTextAccumulator();')) 'own_text_projection' 'the bridge uses the existing typed Jsoup-style ownText projection.' @($elementPath)
Assert-Contract ($legado.Contains('temp.getElementsContainingOwnText(rules[1])')) 'legado_reference' 'the pinned Legado text.xxx collector remains the semantic reference.' @($legadoPath)

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'post_fix_static_contract'
  issueId = $issueId
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  failureWitnessPath = $FailureWitnessPath
  changedPaths = @($bridgePath)
  affectedSourceSet = $fixture.affectedSourceSet
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_text_own_context_post_fix_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  closeCondition = 'R4 must execute all four text-own-context cases, the 96-source/144-occurrence text.xxx matrix, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Depth 100
