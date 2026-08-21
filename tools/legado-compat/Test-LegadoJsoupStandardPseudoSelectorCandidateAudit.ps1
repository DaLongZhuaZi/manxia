[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selectors.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/r3-jsoup-standard-pseudo-selectors-candidate-20260809.json',
  [string]$SourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "required file is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100)
}

function Assert-Audit {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "243 candidate audit failed: $Message" }
  $script:assertions++
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 60), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$resultPath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot ($ResultPath.Replace('/', '\'))))
$evidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).TrimEnd('\') + '\'
if (-not $resultPath.StartsWith($evidenceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'candidate evidence must remain under the evidence directory.'
}

$fixture = Read-StrictJson -Path (Get-RepoPath -RelativePath $FixturePath)
$state = Read-StrictJson -Path (Get-RepoPath -RelativePath 'tools/legado-compat/state/full-source-validation-state.json')
$packageBytes = [System.IO.File]::ReadAllBytes($SourcePackagePath)
$packageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $SourcePackagePath).Hash.ToUpperInvariant()
$sources = $strictUtf8.GetString($packageBytes) | ConvertFrom-Json -Depth 100
$sourceObjects = @($sources)
$analyzerPath = Get-RepoPath -RelativePath 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$elementPath = Get-RepoPath -RelativePath 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$runtimePath = Get-RepoPath -RelativePath 'entry/src/main/resources/rawfile/legado_runtime.html'
$legadoPath = Get-RepoPath -RelativePath 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$analyzer = Read-StrictText -Path $analyzerPath
$element = Read-StrictText -Path $elementPath
$runtime = Read-StrictText -Path $runtimePath
$legado = Read-StrictText -Path $legadoPath

Assert-Audit ([int]$fixture.baseline.sourceCount -eq 458) 'fixture source count drifted.'
Assert-Audit ([string]$fixture.baseline.sourcePackageSha256 -eq $baselineHash) 'fixture source hash drifted.'
Assert-Audit ([string]$fixture.baseline.legadoCommit -eq $legadoCommit) 'fixture Legado commit drifted.'
Assert-Audit ($packageHash -eq $baselineHash) 'frozen source package hash drifted.'
Assert-Audit ($sourceObjects.Count -eq 458) 'frozen source package count drifted.'
Assert-Audit ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline drifted.'
Assert-Audit ((& git -C (Join-Path $RepositoryRoot 'legado') rev-parse HEAD 2>$null | Out-String).Trim() -eq $legadoCommit) 'Legado checkout is not pinned.'
Assert-Audit (@($fixture.cases).Count -eq 6) 'fixture case count drifted.'
Assert-Audit ([int]$fixture.largeDocument.fillerRepeat -gt 1000) 'fixture does not materialize a large-document branch.'
$materializedLength = [System.Text.Encoding]::UTF8.GetByteCount([string]$fixture.largeDocument.baseHtml) +
  ([System.Text.Encoding]::UTF8.GetByteCount([string]$fixture.largeDocument.fillerUnit) * [int]$fixture.largeDocument.fillerRepeat)
Assert-Audit ($materializedLength -gt [int]$fixture.largeDocument.thresholdBytesExclusive) 'materialized fixture is not above the string-fallback threshold.'

$pseudoNames = @(':first-child', ':last-child', ':nth-child', ':only-child')
$counts = [ordered]@{}
$affected = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($pseudo in $pseudoNames) {
  $count = 0
  for ($index = 0; $index -lt $sourceObjects.Count; $index++) {
    $sourceJson = $sourceObjects[$index] | ConvertTo-Json -Depth 100 -Compress
    $matches = [regex]::Matches($sourceJson, [regex]::Escape($pseudo))
    if ($matches.Count -gt 0) {
      $count += $matches.Count
      [void]$affected.Add($index + 1)
    }
  }
  $counts[$pseudo.Substring(1)] = $count
  Assert-Audit ($count -eq [int]$fixture.pseudoCounts.$($pseudo.Substring(1))) ("source package count drifted for $pseudo.")
}
Assert-Audit (($counts.Values | Measure-Object -Sum).Sum -eq [int]$fixture.pseudoCounts.total) 'standard pseudo total drifted.'
$expectedOrdinals = @($fixture.affectedSourceOrdinals | ForEach-Object { [int]$_ } | Sort-Object)
$actualOrdinals = @($affected | Sort-Object)
Assert-Audit (($actualOrdinals -join ',') -eq ($expectedOrdinals -join ',')) 'affected source ordinal set drifted.'

Assert-Audit ($analyzer.Contains('const HTML_SIZE_THRESHOLD = 50000') -and $analyzer.Contains('return this.getElementsByCSSChain(selector);')) 'large documents do enter the string fallback.'
$filterStart = $analyzer.IndexOf('private filterElementsByPseudoClasses(')
$filterEnd = $analyzer.IndexOf('private filterElementsByIndexPseudo(', $filterStart)
Assert-Audit ($filterStart -ge 0 -and $filterEnd -gt $filterStart) 'string pseudo filter boundaries are missing.'
$filterBody = $analyzer.Substring($filterStart, $filterEnd - $filterStart)
foreach ($name in @('first-child', 'last-child', 'nth-child', 'only-child')) {
  Assert-Audit (-not $filterBody.Contains("pseudo.name === '$name'")) "string fallback has no $name branch."
}
Assert-Audit ($filterBody.Contains('Do not silently widen selectors when a Jsoup pseudo class is unknown.') -and $filterBody.Contains('return [];')) 'unknown pseudo classes fail closed in string fallback.'
foreach ($name in @('first-child', 'last-child', 'nth-child', 'only-child')) {
  Assert-Audit ($element.Contains("pseudo.name === '$name'")) "DOM matcher already implements $name."
}
Assert-Audit ($runtime.Contains('root.querySelectorAll(browserSelector)') -and $runtime.Contains('legadoParseJsoupTextPseudos')) 'ArkWeb keeps standard CSS pseudos in the browser selector path.'
Assert-Audit ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('getStringList')) 'pinned Legado delegates CSS selection to Jsoup.'
foreach ($rule in @($fixture.representativeRules)) {
  $found = $false
  foreach ($sourceObject in $sourceObjects) {
    if (($sourceObject | ConvertTo-Json -Depth 100 -Compress).Contains([string]$rule)) { $found = $true; break }
  }
  Assert-Audit $found ("representative rule is missing from the frozen package: $rule")
}

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'candidate_static_boundary_audit'
  issueId = [string]$fixture.issueId
  status = 'candidate_observed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  failureClass = 'large_document_string_fallback_drops_standard_css_pseudo_selectors'
  rootCauseCategory = '规则解析或编译'
  impact = [pscustomobject][ordered]@{
    ruleStringCount = [int]$fixture.pseudoCounts.total
    affectedSourceCount = $actualOrdinals.Count
    pseudoCounts = $counts
    affectedSourceOrdinals = $actualOrdinals
  }
  consumerMatrix = @(
    [pscustomobject][ordered]@{ id = 'dom_matcher'; path = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'; status = 'supported_static'; semantics = @('first-child', 'last-child', 'nth-child', 'only-child') },
    [pscustomobject][ordered]@{ id = 'large_document_string_fallback'; path = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'; status = 'missing_standard_pseudo_branch_static'; semantics = @('first-child', 'last-child', 'nth-child', 'only-child') },
    [pscustomobject][ordered]@{ id = 'arkweb_browser_selector'; path = 'entry/src/main/resources/rawfile/legado_runtime.html'; status = 'native_css_path_static'; semantics = @('first-child', 'last-child', 'nth-child', 'only-child') },
    [pscustomobject][ordered]@{ id = 'legado_reference'; path = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'; status = 'jsoup_select_static'; semantics = @('first-child', 'last-child', 'nth-child', 'only-child') }
  )
  fixturePath = $FixturePath
  selectionPath = [string]$fixture.largeDocument.selectionPath
  assertions = $script:assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  candidateGateStatus = 'pending_queue_selection'
  verificationPolicy = 'r3_candidate_static_evidence_only;do_not_activate_while_242_is_active;runtime_build_device_and_legado_diff_deferred'
  nextRequired = '独立登记失败见证、source-fix 方案和队列转移；在 242 R4 统一验证前不得并行修改生产源码。'
}
Write-AtomicJson -Path $resultPath -Value $result
$result | ConvertTo-Json -Depth 60
