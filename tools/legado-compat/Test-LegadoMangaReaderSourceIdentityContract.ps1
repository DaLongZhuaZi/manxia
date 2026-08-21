[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$FixturePath = '',
  [string]$ResultPath = '',
  [switch]$ExpectPreFix
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
if ([string]::IsNullOrWhiteSpace($FixturePath)) {
  $FixturePath = Join-Path $RepoRoot 'tools\legado-compat\fixtures\legado-manga-reader-source-identity.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $suffix = if ($ExpectPreFix) { 'pre-fix' } else { 'post-fix' }
  $ResultPath = Join-Path $RepoRoot ("tools\legado-compat\evidence\v2-manga-reader-source-identity-contract-20260808-{0}.json" -f $suffix)
}

function Read-Utf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

function Read-HeadText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $gitPath = $RelativePath.Replace('\', '/')
  $output = & git -C $RepoRoot show ("HEAD:" + $gitPath) 2>$null | Out-String
  if ($LASTEXITCODE -ne 0) {
    throw "Cannot read frozen HEAD source: $RelativePath"
  }
  return $output
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "Manga reader source identity contract failed: $Message"
  }
  $script:assertions++
}

function Get-SourceText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  if ($ExpectPreFix) {
    return Read-HeadText -RelativePath $RelativePath
  }
  return Read-Utf8Text -Path (Join-Path $RepoRoot $RelativePath)
}

$assertions = 0
$fixture = $null
$result = $null
try {
  $fixture = (Read-Utf8Text -Path $FixturePath) | ConvertFrom-Json
  Assert-Contract ([string]$fixture.contract -eq 'legado_manga_reader_source_identity') 'fixture contract must be explicit'
  Assert-Contract ([string]$fixture.issueId -eq 'ISSUE-COMPAT-015') 'fixture must bind ISSUE-COMPAT-015'
  Assert-Contract ([int]$fixture.baseline.sourceCount -eq 458) 'fixture must bind the frozen source count'
  Assert-Contract ([string]$fixture.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'fixture must bind the frozen source hash'
  Assert-Contract ([string]$fixture.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'fixture must bind the frozen Legado commit'
  Assert-Contract (@($fixture.requiredEntrances).Count -eq 3) 'fixture must cover all three route entrances'
  Assert-Contract (@($fixture.requiredIdentityFields).Count -eq 6) 'fixture must cover the six identity fields'
  Assert-Contract ([int]$fixture.affectedSourceSet.sourceType -eq 2) 'fixture must bind the Legado IMAGE source type'
  Assert-Contract ([int]$fixture.affectedSourceSet.sourceCount -eq 54) 'fixture must bind the frozen IMAGE affected-source count'
  Assert-Contract ([string]$fixture.affectedSourceSet.ordinalDigest -match '^[A-F0-9]{64}$') 'fixture must bind an ordinal affected-source digest'
  Assert-Contract ([string]$fixture.affectedSourceSet.sourceIdDigest -match '^[A-F0-9]{64}$') 'fixture must bind a source identity affected-source digest'
  Assert-Contract (@($fixture.legadoReference.bookIdentity).Count -ge 4) 'fixture must bind the Legado book identity implementation'
  Assert-Contract (@($fixture.legadoReference.chapterIdentity).Count -ge 2) 'fixture must bind the Legado chapter identity implementation'

  $readerPath = 'entry\src\main\ets\pages\MangaReaderPage.ets'
  $abilityPath = 'entry\src\main\ets\pages\MangaReaderAbilityPage.ets'
  $launcherPath = 'entry\src\main\ets\Framework\Reader\MangaReaderAbilityLauncher.ets'
  $storePath = 'entry\src\main\ets\Framework\Reader\MangaReaderAbilityParamStore.ets'
  $viewerPath = 'entry\src\main\ets\components\MangaViewer.ets'
  $contextPath = 'entry\src\main\ets\components\MangaAssetLoadContextResolver.ets'
  $factoryPath = 'entry\src\main\ets\Framework\Reader\MangaAssetRequestFactory.ets'
  $loaderPath = 'entry\src\main\ets\Framework\Reader\MangaAssetLoader.ets'

  $reader = Get-SourceText -RelativePath $readerPath
  $ability = Get-SourceText -RelativePath $abilityPath
  $launcher = Get-SourceText -RelativePath $launcherPath
  $store = Get-SourceText -RelativePath $storePath
  $viewer = Get-SourceText -RelativePath $viewerPath
  $context = Get-SourceText -RelativePath $contextPath
  $factory = Get-SourceText -RelativePath $factoryPath
  $loader = Get-SourceText -RelativePath $loaderPath

  if ($ExpectPreFix) {
    foreach ($marker in @($fixture.preFixMissingMarkers)) {
      Assert-Contract (-not $reader.Contains([string]$marker)) ("frozen HEAD must lack the repaired marker: {0}" -f $marker)
    }
    Assert-Contract (-not $viewer.Contains('legadoSourceRawSha256')) 'frozen HEAD must not have the raw SHA viewer handoff'
    Assert-Contract (-not $context.Contains('requestContext.legadoSourceRawSha256')) 'frozen HEAD must not have the raw SHA request context handoff'
    Assert-Contract (-not $factory.Contains('request.legadoSourceRawSha256')) 'frozen HEAD must not have the raw SHA request factory handoff'
    Assert-Contract (-not $loader.Contains('request.legadoSourceRawSha256')) 'frozen HEAD must not have the raw SHA asset trace handoff'
  } else {
    foreach ($marker in @(
      'const hasSourcePkg: boolean = rawKeys.includes(''sourcePkg'')',
      'const hasSkipDatabaseLookup: boolean = rawKeys.includes(''skipDatabaseLookup'')',
      'skipDatabaseLookup: hasSkipDatabaseLookup',
      'chapterTitle: hasChapterTitle',
      'sourcePkg: hasSourcePkg ? String(rawParamsObj[''sourcePkg'']) : undefined',
      'const hasSourcePkg: boolean = keys.includes(''sourcePkg'')',
      'const hasSkipDatabaseLookup: boolean = keys.includes(''skipDatabaseLookup'')',
      'sourcePkg: hasSourcePkg ? String(raw[''sourcePkg'']) : undefined',
      'skipDatabaseLookup: hasSkipDatabaseLookup',
      'chapterTitle: hasChapterTitle',
      'return latest as MangaReaderPageParams;',
      'if (hasContentType)',
      'else if (hasSourceId)',
      'params.sourcePkg = identityResult.sourcePkg;',
      'this.currentSourcePkg = identityResult.sourcePkg;',
      'await this.refreshLegadoV2ImageTraceIdentity();',
      'private async refreshLegadoV2ImageTraceIdentity(): Promise<void>'
    )) {
      Assert-Contract ($reader.Contains($marker)) ("current reader source must contain: {0}" -f $marker)
    }
    foreach ($field in @('sourcePkg', 'contentType', 'skipDatabaseLookup', 'chapterTitle')) {
      Assert-Contract ($ability.Contains("$field`: source.$field")) ("isolated Ability must copy $field")
    }
    Assert-Contract ($launcher.Contains('fallbackStack.pushPathByName(''MangaReaderPage'', params)')) 'Router fallback must forward complete params'
    Assert-Contract ($store.Contains('this.paramsMap.set(instanceId, params);')) 'Ability store must retain complete params'
    Assert-Contract ($store.Contains('payload.params = params;')) 'Ability payload must retain complete params'
    Assert-Contract ($viewer.Contains('input.legadoSourceRawSha256 = this.legadoSourceRawSha256;')) 'viewer must retain raw SHA'
    Assert-Contract ($context.Contains('requestContext.legadoSourceRawSha256 = input.legadoSourceRawSha256;')) 'load context must retain raw SHA'
    Assert-Contract ($factory.Contains('request.legadoSourceRawSha256 = context.legadoSourceRawSha256;')) 'request factory must retain raw SHA'
    Assert-Contract ($loader.Contains('request.legadoSourceRawSha256,')) 'asset loader must trace raw SHA'
  }

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'passed'
    contract = [string]$fixture.contract
    issueId = [string]$fixture.issueId
    phase = if ($ExpectPreFix) { 'failure_contract_pre_fix' } else { 'source_closure_static_verified_pending_r4' }
    assertions = $assertions
    baseline = $fixture.baseline
    routePayload = $fixture.routePayload
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'failed'
    contract = 'legado_manga_reader_source_identity'
    issueId = 'ISSUE-COMPAT-015'
    phase = if ($ExpectPreFix) { 'failure_contract_pre_fix' } else { 'source_closure_static_verified_pending_r4' }
    assertions = $assertions
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
}

$resultDirectory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $resultDirectory)) {
  [void][System.IO.Directory]::CreateDirectory($resultDirectory)
}
[System.IO.File]::WriteAllText($ResultPath, [string]($result | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') { exit 1 }
