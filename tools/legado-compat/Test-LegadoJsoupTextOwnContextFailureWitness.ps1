[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-text-own-context.json',
  [string]$BridgeSnapshotPath = 'entry/src/main/ets/libs/htmlparser/LegadoHtmlBridge.ets.bak_20260810_issue243_text_own_context',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-text-own-context-pre-fix-20260810.json'
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
$script:textRuleHits = New-Object 'System.Collections.Generic.List[object]'

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }; return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "required file is missing: $Path" }; $bytes = [System.IO.File]::ReadAllBytes($resolved); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }; return $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100) }
function Assert-Witness { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 text own-context failure witness failed: $Message" }; $script:assertions++ }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }
function Find-TextRules { param([object]$Value, [string]$Path, [int]$Ordinal)
  if ($null -eq $Value) { return }
  if ($Value -is [string]) {
    foreach ($match in [regex]::Matches([string]$Value, $textRulePattern)) {
      [void]$script:textRuleHits.Add([pscustomobject][ordered]@{ ordinal = $Ordinal; path = $Path; rule = $match.Value })
    }
    return
  }
  if ($Value -is [System.Collections.IEnumerable]) {
    $index = 0
    foreach ($item in $Value) {
      Find-TextRules -Value $item -Path ($Path + '[' + $index + ']') -Ordinal $Ordinal
      $index++
    }
    return
  }
  foreach ($property in $Value.PSObject.Properties) {
    Find-TextRules -Value $property.Value -Path ($Path + '.' + $property.Name) -Ordinal $Ordinal
  }
}

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$bridgeSnapshot = Read-StrictText $BridgeSnapshotPath
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$legado = Read-StrictText $legadoPath
$sourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
$packageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePackagePath).Hash.ToUpperInvariant()
$sources = @($strictUtf8.GetString([System.IO.File]::ReadAllBytes($sourcePackagePath)) | ConvertFrom-Json -Depth 100)
for ($index = 0; $index -lt $sources.Count; $index++) { Find-TextRules -Value $sources[$index] -Path '$' -Ordinal ($index + 1) }
$sourceOrdinals = @($script:textRuleHits | ForEach-Object { [int]$_.ordinal } | Sort-Object -Unique)
$uniqueRules = @($script:textRuleHits | ForEach-Object { [string]$_.rule } | Sort-Object -Unique)
$representativeText = ($sources[7] | ConvertTo-Json -Depth 100 -Compress) + ($sources[13] | ConvertTo-Json -Depth 100 -Compress) + ($sources[54] | ConvertTo-Json -Depth 100 -Compress)

Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline drifted.'
Assert-Witness ($packageHash -eq $baselineHash -and $sources.Count -eq 458) 'frozen source package drifted.'
Assert-Witness ([string]$fixture.issueId -eq $issueId -and [string]$fixture.contract -eq 'legado_jsoup_text_rule_own_context' -and @($fixture.cases).Count -eq 4) 'fixture binding or case count changed.'
Assert-Witness ($script:textRuleHits.Count -eq [int]$fixture.affectedSourceSet.ruleOccurrenceCount -and $sourceOrdinals.Count -eq [int]$fixture.affectedSourceSet.sourceCount -and $uniqueRules.Count -eq [int]$fixture.affectedSourceSet.uniqueRuleCount) 'frozen text-rule capability scan drifted.'
foreach ($ordinal in @($fixture.affectedSourceSet.representativeSourceOrdinals)) { Assert-Witness ($sourceOrdinals -contains [int]$ordinal) "representative ordinal is absent from the frozen text-rule scan: $ordinal" }
foreach ($rule in @($fixture.affectedSourceSet.ruleStrings)) { Assert-Witness ($representativeText.Contains([string]$rule)) "representative text rule is missing: $rule" }
Assert-Witness ($bridgeSnapshot.Contains("const allElements = this.root.getElementsByTagName('*');") -and $bridgeSnapshot.Contains("const allElements = context.getElementsByTagName('*');") -and $bridgeSnapshot.Contains('if (elem.text.includes(searchText))') -and -not $bridgeSnapshot.Contains('elem.ownText.includes(searchText)')) 'pre-fix bridge does not expose descendant aggregate-text matching.'
Assert-Witness ($legado.Contains('temp.getElementsContainingOwnText(rules[1])')) 'pinned Legado text.xxx own-text collector is missing.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'failure_witness'
  issueId = $issueId
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  sourcePackagePath = 'redacted_pinned_package'
  sourcePackageHash = $packageHash
  sourcePaths = @($BridgeSnapshotPath, $legadoPath)
  snapshotHash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $BridgeSnapshotPath)).Hash.ToUpperInvariant()
  affectedSourceSet = $fixture.affectedSourceSet
  failureClass = 'v2_text_rule_uses_descendant_aggregate_text'
  failureWitness = [pscustomobject][ordered]@{
    branch = 'LegadoHtmlBridge.findByTextInContext -> HTMLElement.text'
    observed = 'V2 examines descendants only and compares aggregate element text. An ancestor can be selected solely because nested content contains the phrase, and a matching current context Element is omitted.'
    expected = 'Legado text.xxx uses getElementsContainingOwnText, which evaluates the current Element and descendants against own text only.'
  }
  rootCauseCategory = '规则解析或编译'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_text_own_context_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  assertions = $script:assertions
}
Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Depth 100
