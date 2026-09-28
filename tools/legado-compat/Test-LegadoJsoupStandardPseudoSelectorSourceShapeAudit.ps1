[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$SourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-selector-source-shape-audit-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$script:assertions = 0

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $RelativePath }
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing file: $Path" }
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
  if (-not $Condition) { throw "243 source-shape audit failed: $Message" }
  $script:assertions++
}

function Visit-SourceValue {
  param(
    [object]$Value,
    [string]$Path,
    [int]$Ordinal,
    [System.Collections.Generic.List[object]]$Hits
  )
  if ($null -eq $Value) { return }
  if ($Value -is [string]) {
    if ($Path -notmatch '(?i)\.(rule[A-Za-z0-9_]*|searchUrl|exploreUrl|loginUrl)(?:\.|\[|$)') {
      return
    }
    $pattern = '(?i):(?<name>first-child|last-child|nth-child|only-child|first-of-type|last-of-type|only-of-type|nth-of-type|nth-last-of-type|contains|containsown|matches|matchesown|has|not|eq|lt|empty)(?=\(|[\s>@,\)\]:]|$)'
    foreach ($match in [regex]::Matches($Value, $pattern)) {
      [void]$Hits.Add([pscustomobject][ordered]@{
          ordinal = $Ordinal
          path = $Path
          name = $match.Groups['name'].Value.ToLowerInvariant()
        })
    }
    return
  }
  if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [string])) {
    $index = 0
    foreach ($item in $Value) {
      Visit-SourceValue -Value $item -Path "$Path[$index]" -Ordinal $Ordinal -Hits $Hits
      $index++
    }
    return
  }
  foreach ($property in $Value.PSObject.Properties) {
    Visit-SourceValue -Value $property.Value -Path "$Path.$($property.Name)" -Ordinal $Ordinal -Hits $Hits
  }
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 80), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$sourcePath = [System.IO.Path]::GetFullPath($SourcePackagePath)
$resultFullPath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot ($ResultPath.Replace('/', '\'))))
$result = $null
$exitCode = 0
try {
  $statePath = Get-RepoPath 'tools/legado-compat/state/full-source-validation-state.json'
  $fixturePath = Get-RepoPath 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selectors.json'
  $state = Read-StrictJson -Path $statePath
  $fixture = Read-StrictJson -Path $fixturePath
  $sourceBytes = [System.IO.File]::ReadAllBytes($sourcePath)
  $sourceHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToUpperInvariant()
  $sources = @($strictUtf8.GetString($sourceBytes) | ConvertFrom-Json -Depth 100)
  Assert-Audit ($sourceHash -eq $baselineHash) 'frozen source package hash drifted.'
  Assert-Audit ($sources.Count -eq 458) 'frozen source package count drifted.'
  Assert-Audit ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline drifted.'
  Assert-Audit ([string]$state.governance.activeIssueId -eq $issueId -and [string]$state.governance.status -eq 'running') '243 is not the active source issue.'
  Assert-Audit ((& git -C (Get-RepoPath 'legado') rev-parse HEAD 2>$null | Out-String).Trim() -eq $legadoCommit) 'Legado checkout is not pinned.'

  $hits = New-Object 'System.Collections.Generic.List[object]'
  for ($index = 0; $index -lt $sources.Count; $index++) {
    Visit-SourceValue -Value $sources[$index] -Path ('$[' + ($index + 1) + ']') -Ordinal ($index + 1) -Hits $hits
  }

  $standardNames = @('first-child', 'last-child', 'nth-child', 'only-child', 'first-of-type', 'last-of-type', 'only-of-type', 'nth-of-type', 'nth-last-of-type')
  $expectedCounts = [ordered]@{
    'first-child' = 4
    'last-child' = 3
    'nth-child' = 40
    'only-child' = 5
    'first-of-type' = 0
    'last-of-type' = 1
    'only-of-type' = 0
    'nth-of-type' = 14
    'nth-last-of-type' = 0
  }
  $counts = [ordered]@{}
  foreach ($name in $standardNames) {
    $count = @($hits | Where-Object { $_.name -eq $name }).Count
    $counts[$name] = $count
    Assert-Audit ($count -eq [int]$expectedCounts[$name]) ("frozen count drifted for :$name (expected $($expectedCounts[$name]), got $count).")
  }
  $observedNames = @($hits | Select-Object -ExpandProperty name -Unique | Sort-Object)
  $unsupportedNames = @($observedNames | Where-Object { $_ -notin @($standardNames + @('contains', 'containsown', 'matches', 'matchesown', 'has', 'not', 'eq', 'lt')) })
  Assert-Audit ($unsupportedNames.Count -eq 0) 'source package contains a pseudo name outside the audited V2/Legado selector set.'
  Assert-Audit (@($hits | Where-Object { $_.name -eq 'empty' }).Count -eq 0) 'source package contains an unexpected :empty pseudo occurrence.'

  $affectedOrdinals = @($hits | Where-Object { $_.name -in $standardNames } | Select-Object -ExpandProperty ordinal -Unique | Sort-Object)
  $expectedOrdinals = @($fixture.affectedSourceOrdinals + @(21, 112, 123, 233) | ForEach-Object { [int]$_ } | Sort-Object -Unique)
  Assert-Audit (($affectedOrdinals -join ',') -eq ($expectedOrdinals -join ',')) 'standard pseudo affected-source set drifted.'
  Assert-Audit (($counts.Values | Measure-Object -Sum).Sum -eq 67) 'standard pseudo total drifted from 67 rule occurrences.'

  $analyzerPath = Get-RepoPath 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
  $elementPath = Get-RepoPath 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
  $matcherPath = Get-RepoPath 'entry/src/main/ets/libs/htmlparser/Matcher.ets'
  $runtimePath = Get-RepoPath 'entry/src/main/resources/rawfile/legado_runtime.html'
  $legadoPath = Get-RepoPath 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
  $analyzer = Read-StrictText -Path $analyzerPath
  $element = Read-StrictText -Path $elementPath
  $matcher = Read-StrictText -Path $matcherPath
  $runtime = Read-StrictText -Path $runtimePath
  $legado = Read-StrictText -Path $legadoPath
  Assert-Audit ($analyzer.Contains('filterElementsByPseudoClasses') -and $analyzer.Contains('filterElementsByStandardChildPseudo') -and $analyzer.Contains('filterElementsByIndexPseudo')) 'string fallback pseudo consumers are not present.'
  Assert-Audit ($element.Contains("pseudo.name === 'first-child'") -and $element.Contains("pseudo.name === 'nth-of-type'") -and $element.Contains("pseudo.name === 'has'") -and $element.Contains("pseudo.name === 'not'")) 'DOM pseudo consumer matrix is incomplete.'
  Assert-Audit ($matcher.Contains('static parseSelector') -and $matcher.Contains('parsePseudoClass') -and $matcher.Contains('parseAttributeSelector')) 'Matcher selector parser consumer matrix is incomplete.'
  Assert-Audit ($runtime.Contains('root.querySelectorAll(browserSelector)')) 'ArkWeb native CSS consumer is missing.'
  Assert-Audit ($legado.Contains('temp.select(ruleStr)')) 'pinned Legado Jsoup consumer is missing.'

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    evidenceType = 'source_shape_static_audit'
    issueId = $issueId
    status = 'passed_static_only'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
    observedPseudoCounts = $counts
    observedPseudoNames = $observedNames
    unsupportedPseudoNames = $unsupportedNames
    affectedRuleStringCount = 67
    affectedSourceCount = $affectedOrdinals.Count
    affectedSourceOrdinals = $affectedOrdinals
    consumerMatrix = @(
      [pscustomobject][ordered]@{ id = 'string_fallback'; path = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'; status = 'supported_static' }
      [pscustomobject][ordered]@{ id = 'dom_element_matcher'; path = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'; status = 'supported_static' }
      [pscustomobject][ordered]@{ id = 'dom_selector_matcher'; path = 'entry/src/main/ets/libs/htmlparser/Matcher.ets'; status = 'supported_static' }
      [pscustomobject][ordered]@{ id = 'arkweb_native_css'; path = 'entry/src/main/resources/rawfile/legado_runtime.html'; status = 'native_css_static' }
      [pscustomobject][ordered]@{ id = 'legado_reference'; path = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'; status = 'jsoup_select_static' }
    )
    assertions = $script:assertions
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_source_shape_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
    nextGate = '243 R4 must execute the 67-occurrence/25-source shape set and the full 458-source differential before changing status.'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    evidenceType = 'source_shape_static_audit'
    issueId = $issueId
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
  }
}
Write-AtomicJson -Path $resultFullPath -Value $result
$result | ConvertTo-Json -Depth 80
if ($exitCode -ne 0) { exit $exitCode }
