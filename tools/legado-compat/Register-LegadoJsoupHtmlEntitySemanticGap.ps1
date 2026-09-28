[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-html-entity-semantics-gap.json',
  [string]$DiscoveryEvidencePath = 'tools/legado-compat/evidence/v2-jsoup-html-entity-semantics-gap-discovery-20260811.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-COMPAT-244-JSOUP-HTML-ENTITY-SEMANTICS'
$taskId = 'COMPAT-006'
$activeIssueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) {
    return $Path
  }
  return Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  $resolved = Get-RepoPath -Path $Path
  if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
    throw "required file is missing: $Path"
  }
  $bytes = [System.IO.File]::ReadAllBytes($resolved)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and
    $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  return Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100
}

function Set-PropertyValue {
  param(
    [Parameter(Mandatory = $true)][object]$Object,
    [Parameter(Mandatory = $true)][string]$Name,
    [AllowNull()][object]$Value
  )
  if ($null -eq $Object.PSObject.Properties[$Name]) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
  } else {
    $Object.$Name = $Value
  }
}

function Write-AtomicJson {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][object]$Value
  )
  $resolved = Get-RepoPath -Path $Path
  $directory = Split-Path -Parent $resolved
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText(
      $temporary,
      ($Value | ConvertTo-Json -Depth 100),
      $noBomUtf8
    )
    Move-Item -LiteralPath $temporary -Destination $resolved -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) {
      [System.IO.File]::Delete($temporary)
    }
  }
}

function Assert-Discovery {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Detail
  )
  if (-not $Condition) {
    throw "244 HTML entity discovery failed: $Detail"
  }
}

function Get-OfficialSource {
  param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$ExpectedSha256
  )
  $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
  $content = [string]$response.Content
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
  $sha256 = [Convert]::ToHexString(
    [System.Security.Cryptography.SHA256]::HashData($bytes)
  )
  Assert-Discovery (
    [int]$response.StatusCode -eq 200 -and $sha256 -eq $ExpectedSha256
  ) "official source hash drifted: $Url"
  return $content
}

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$state = Read-StrictJson -Path $statePath
$objective = Read-StrictJson -Path $objectivePath
$fixture = Read-StrictJson -Path $FixturePath

Assert-Discovery (
  [int]$state.baseline.sourceCount -eq 458 -and
  [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and
  [string]$state.baseline.legadoCommit -eq $legadoCommit
) 'frozen baseline drifted.'
Assert-Discovery (
  [string]$state.governance.status -eq 'running' -and
  [string]$state.governance.activeTaskId -eq $taskId -and
  [string]$state.governance.activeIssueId -eq $activeIssueId -and
  -not [bool]$state.governance.semanticMatchAllowed
) '243 must remain the sole active issue while 244 is only discovered.'
Assert-Discovery (
  [string]$fixture.contract -eq 'legado_jsoup_html_entity_semantic_gap' -and
  [string]$fixture.issueId -eq $issueId -and
  @($fixture.cases).Count -eq 5 -and
  [int]$fixture.officialReference.extendedEntityCount -eq 2125
) 'entity gap fixture drifted.'

$entitiesSource = Get-OfficialSource -Url ([string]$fixture.officialReference.entitiesSourceUrl) -ExpectedSha256 ([string]$fixture.officialReference.entitiesSourceSha256)
$entitiesDataSource = Get-OfficialSource -Url ([string]$fixture.officialReference.entitiesDataSourceUrl) -ExpectedSha256 ([string]$fixture.officialReference.entitiesDataSourceSha256)
Assert-Discovery (
  $entitiesSource.Contains('extended(EntitiesData.fullPoints, 2125)') -and
  $entitiesDataSource.Contains('NotEqualTilde=6rm,mw') -and
  $entitiesDataSource.Contains('CounterClockwiseContourIntegral=6r7') -and
  $entitiesDataSource.Contains('Afr=2kn8') -and
  $entitiesDataSource.Contains('fjlig=2u,2y')
) 'official Jsoup extended entity evidence is incomplete.'

$htmlEntitiesPath = 'entry/src/main/ets/libs/htmlparser/HtmlEntities.ets'
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$jsEnginePath = 'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets'
$rhinoStandalonePath = 'entry/src/main/resources/rawfile/rhino_sandbox/jsoup_impl.js'
$htmlEntities = Read-StrictText -Path $htmlEntitiesPath
$analyzer = Read-StrictText -Path $analyzerPath
$jsEngine = Read-StrictText -Path $jsEnginePath
$rhinoStandalone = Read-StrictText -Path $rhinoStandalonePath

$typedNamedCount = [regex]::Matches($htmlEntities, "m\.set\('([^']+)'").Count
$jsVmNamedCount = [regex]::Matches(
  $jsEngine,
  "entity === '(nbsp|lt|gt|amp|quot|apos)'"
).Count
$namedMapStart = $rhinoStandalone.IndexOf('        const named = {')
$namedMapEnd = if ($namedMapStart -ge 0) {
  $rhinoStandalone.IndexOf('        };', $namedMapStart)
} else {
  -1
}
Assert-Discovery (
  $namedMapStart -ge 0 -and $namedMapEnd -gt $namedMapStart
) 'Rhino fallback named entity map cannot be located.'
$rhinoNamedMap = $rhinoStandalone.Substring(
  $namedMapStart,
  $namedMapEnd - $namedMapStart
)
$rhinoNamedCount = [regex]::Matches(
  $rhinoNamedMap,
  '(?m)^\s{12}[A-Za-z][A-Za-z0-9]*:'
).Count
$missingNames = @('NotEqualTilde', 'CounterClockwiseContourIntegral', 'Afr', 'fjlig')
foreach ($missingName in $missingNames) {
  Assert-Discovery (
    -not $htmlEntities.Contains("m.set('$missingName'") -and
    -not $jsEngine.Contains("entity === '$($missingName.ToLowerInvariant())'") -and
    -not $rhinoNamedMap.Contains(($missingName + ':'))
  ) "local fallback unexpectedly contains the planned missing entity: $missingName"
}
Assert-Discovery (
  $typedNamedCount -eq 122 -and
  $analyzer.Contains('/&(nbsp|lt|gt|amp|quot|apos);/gi') -and
  $jsVmNamedCount -eq 6 -and
  $rhinoNamedCount -eq 33
) 'local named entity capability counts drifted.'
Assert-Discovery (
  $htmlEntities.Contains('return String.fromCharCode(code);') -and
  $analyzer.Contains('return String.fromCharCode(parseInt(dec, 10));') -and
  $analyzer.Contains('return String.fromCharCode(parseInt(hex, 16));') -and
  $jsEngine.Contains('numeric <= 65535')
) 'local non-BMP numeric gap is no longer reproducible.'

$localPaths = @($htmlEntitiesPath, $analyzerPath, $jsEnginePath, $rhinoStandalonePath)
$localHashes = @(
  foreach ($localPath in $localPaths) {
    [pscustomobject][ordered]@{
      path = $localPath
      sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (
          Get-RepoPath -Path $localPath
        )).Hash.ToUpperInvariant()
    }
  }
)
$discovery = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'static_capability_gap_discovery'
  issueId = $issueId
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = $fixture.baseline
  fixturePath = $FixturePath
  officialReference = $fixture.officialReference
  verifiedOfficialFacts = [pscustomobject][ordered]@{
    extendedEntityCount = 2125
    multipointEntity = 'NotEqualTilde -> U+2242 U+0338'
    longNamedEntity = 'CounterClockwiseContourIntegral -> U+2233'
    nonBmpEntity = 'Afr -> U+1D504'
    ordinaryMultipointEntity = 'fjlig -> U+0066 U+006A'
  }
  localObservedLimits = [pscustomobject][ordered]@{
    typedHtmlEntitiesNamedEntries = $typedNamedCount
    analyzerFastNamedEntries = 6
    generatedJsvmNamedEntries = $jsVmNamedCount
    rhinoStandaloneFallbackNamedEntries = $rhinoNamedCount
    numericNonBmp = 'fromCharCode truncation or U+FFFF cap'
  }
  localHeadHashes = $localHashes
  cases = $fixture.cases
  impactScope = $fixture.impactScope
  classification = 'rules_and_html_entity_decoding'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  disposition = 'planned_separate_root_cause;active_issue_remains_243'
  closeCondition = 'Implement one typed complete entity table/decoder shared by typed DOM, Analyzer string fallback, generated JSVM and Rhino fallback; add pre-fix/post-fix contracts, then execute R4 runtime, fixed-Legado differential, affected response fixtures, 458-source Harness, build and device gates.'
}
Write-AtomicJson -Path $DiscoveryEvidencePath -Value $discovery

Set-PropertyValue -Object $objective -Name 'lastReviewedAt' -Value ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue -Object $objective -Name 'nextAction' -Value 'ISSUE-COMPAT-244 is registered as planned from official Jsoup 1.16.2 entity sources; keep 243 as the sole active issue and continue its remaining source audit.'
Write-AtomicJson -Path $objectivePath -Value $objective

$registerPath = 'tools/legado-compat/Register-LegadoJsoupHtmlEntitySemanticGap.ps1'
$sourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-terminal-text-projection-source-fix-20260811.json'
$evidence = @(
  $FixturePath,
  $DiscoveryEvidencePath,
  $registerPath,
  $sourceFixPath,
  $htmlEntitiesPath,
  $analyzerPath,
  $jsEnginePath,
  $rhinoStandalonePath,
  'legado/gradle/libs.versions.toml'
)
$summary = 'Official Jsoup 1.16.2 loads 2125 extended entities, including multi-codepoint and non-BMP values. V2 typed/string fallbacks expose only 122/33/6-entry subsets and use fromCharCode or a U+FFFF cap. Impact is response-dependent; 244 is planned and must not replace active issue 243.'
$updateScript = Get-RepoPath -Path 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
$updateOutput = & (Get-Command pwsh).Source -NoLogo -NoProfile -NonInteractive -File $updateScript -StatePath (Get-RepoPath -Path $statePath) -IssueId $issueId -IssueStatus planned -TaskId $taskId -TaskStatus running -Severity P1 -Summary $summary -CloseCondition ([string]$discovery.closeCondition) -EvidencePath ([string]::Join(',', $evidence)) -CreateIfMissing 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) {
  throw ('Update-LegadoGovernanceState failed:' + [Environment]::NewLine + $updateOutput)
}

[pscustomobject][ordered]@{
  status = 'registered_planned'
  issueId = $issueId
  activeIssueId = $activeIssueId
  discoveryEvidencePath = $DiscoveryEvidencePath
  governanceUpdate = $updateOutput.Trim()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
} | ConvertTo-Json -Depth 100
