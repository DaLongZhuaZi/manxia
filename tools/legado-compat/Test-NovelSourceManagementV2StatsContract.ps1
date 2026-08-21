[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-RepositoryRoot {
  param([string]$RequestedRoot)

  if (-not [string]::IsNullOrWhiteSpace($RequestedRoot)) {
    return (Resolve-Path -LiteralPath $RequestedRoot).Path
  }
  return (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\\..')).Path
}

function Read-Utf8Text {
  param([string]$Path)

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Novel source management V2 statistics contract failed: missing file $Path"
  }
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

function Assert-Contract {
  param(
    [bool]$Condition,
    [string]$Message
  )

  if (-not $Condition) {
    throw "Novel source management V2 statistics contract failed: $Message"
  }
}

function Assert-Contains {
  param(
    [string]$Text,
    [string]$Expected,
    [string]$Scope
  )

  Assert-Contract -Condition $Text.Contains($Expected) -Message "$Scope is missing '$Expected'"
}

function Get-Sha256 {
  param([string]$Path)

  return [string](Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function ConvertFrom-Utf8Base64 {
  param([string]$Base64)

  return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Base64))
}

function Get-MethodText {
  param(
    [string]$Text,
    [string]$StartMarker,
    [string]$EndMarker
  )

  $start = $Text.IndexOf($StartMarker, [System.StringComparison]::Ordinal)
  $end = $Text.IndexOf($EndMarker, $start + $StartMarker.Length, [System.StringComparison]::Ordinal)
  Assert-Contract -Condition ($start -ge 0) -Message "method start is missing: $StartMarker"
  Assert-Contract -Condition ($end -gt $start) -Message "method end is missing or out of order: $EndMarker"
  return $Text.Substring($start, $end - $start)
}

$root = Resolve-RepositoryRoot -RequestedRoot $RepositoryRoot
$pagePath = Join-Path $root 'entry\\src\\main\\ets\\pages\\NovelSourceManagementPage.ets'
$importObserverPath = Join-Path $root 'tools\\legado-compat\\Observe-LegadoV2Import.py'
$screenshotPath = Join-Path $root 'tools\\legado-compat\\device-evidence\\ui-audit\\frameidle-booksource-management-20260731.jpeg'
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $root 'tools\\legado-compat\\evidence\\ui-009-v2-validation-statistics-contract.json'
}

$pageText = Read-Utf8Text -Path $pagePath
$importObserverText = Read-Utf8Text -Path $importObserverPath
$statsText = Get-MethodText -Text $pageText -StartMarker 'private buildV2SourceValidationStats(' -EndMarker 'private applyV2SourceValidationStats('
$qualificationText = Get-MethodText -Text $pageText -StartMarker 'private async qualifySourceWithV2(' -EndMarker 'private hasActiveSourceFilter('
$v2PanelText = Get-MethodText -Text $pageText -StartMarker 'buildV2ExecutionPolicyPanel()' -EndMarker '@Builder'
$statsPanelText = Get-MethodText -Text $pageText -StartMarker 'buildStats()' -EndMarker 'if (this.sourceGroups.length > 0)'
$headlineLabel = ConvertFrom-Utf8Base64 -Base64 'VjIg5bey5a6M5pW06aqM6K+BIC8g5oC75Lmm5rqQ'
$legacyAmbiguousCopy = ConvertFrom-Utf8Base64 -Base64 '5q2j5bi45bel5L2cL+W3sumqjOivgQ=='
$readyLabel = ConvertFrom-Utf8Base64 -Base64 '5b6F5a6M5pW06aqM6K+B'
$preparingLabel = ConvertFrom-Utf8Base64 -Base64 '5YeG5aSH5Lit'
$needsInteractionLabel = ConvertFrom-Utf8Base64 -Base64 '6ZyA5Lqk5LqS'
$unsupportedLabel = ConvertFrom-Utf8Base64 -Base64 '5LiN5pSv5oyB'
$blockedLabel = ConvertFrom-Utf8Base64 -Base64 '5bey6Zi75pat'
$legacyLabel = ConvertFrom-Utf8Base64 -Base64 '5pen6K6w5b2V'
$completeVerificationDefinition = ConvertFrom-Utf8Base64 -Base64 '5b2T5YmN5Y6f5aeLIEpTT04g5ZOI5biM5LiA6Ie05LiU5omA6ZyAIFYyIOW3peS9nOa1geWdh+acieivgeaNrg=='
$batchValidationLimitation = ConvertFrom-Utf8Base64 -Base64 '5om56YeP5Y+v55So5oCn5qCh6aqM6L+b6KGM5Lit77yb5a6M5oiQ5LiN562J5ZCM5LqO5a6M5pW06aqM6K+B44CC'

Assert-Contains -Text $pageText -Expected 'class V2SourceValidationStats' -Scope 'single V2 statistics projection'
foreach ($status in @(
  'LegadoCompatibilityStatus.VERIFIED',
  'LegadoCompatibilityStatus.READY',
  'LegadoCompatibilityStatus.PARSED',
  'LegadoCompatibilityStatus.COMPILED',
  'LegadoCompatibilityStatus.NEEDS_INTERACTION',
  'LegadoCompatibilityStatus.UNSUPPORTED',
  'LegadoCompatibilityStatus.BLOCKED',
  'LegadoCompatibilityStatus.LEGACY_UNVERIFIABLE'
)) {
  Assert-Contains -Text $statsText -Expected $status -Scope 'V2 compatibility-state classifier'
}

Assert-Contains -Text $pageText -Expected 'const v2ValidationStats: V2SourceValidationStats = this.buildV2SourceValidationStats(this.allSources);' -Scope 'loadSources V2 statistics wiring'
Assert-Contains -Text $pageText -Expected 'this.totalSourceCount = v2ValidationStats.totalSourceCount;' -Scope 'shared V2 statistics denominator'
Assert-Contains -Text $pageText -Expected 'this.applyV2SourceValidationStats(v2ValidationStats);' -Scope 'loadSources V2 statistics wiring'
Assert-Contract -Condition (-not $pageText.Contains('workingSourceCount')) -Message 'historical working-group counter must not remain.'
Assert-Contract -Condition (-not $pageText.Contains('validatedSourceCount')) -Message 'historical validation-group counter must not remain.'
Assert-Contract -Condition (-not $pageText.Contains($legacyAmbiguousCopy)) -Message 'ambiguous historical verification copy must not remain.'

Assert-Contains -Text $pageText -Expected 'private getV2VerificationHeadline(): string' -Scope 'shared V2 headline helper'
Assert-Contains -Text $v2PanelText -Expected 'this.getV2VerificationHeadline()' -Scope 'V2 policy panel shared headline'
Assert-Contains -Text $statsPanelText -Expected 'this.getV2VerificationHeadline()' -Scope 'summary shared headline'
Assert-Contains -Text $statsPanelText -Expected ".id('novel_source_total_count')" -Scope 'summary total count automation identity'
Assert-Contains -Text $statsPanelText -Expected ".id('novel_source_v2_verified_count')" -Scope 'summary verified count automation identity'
Assert-Contains -Text $importObserverText -Expected "SOURCE_TOTAL_COUNT_ID: str = 'novel_source_total_count'" -Scope 'import observation total-count fallback'
Assert-Contains -Text $importObserverText -Expected "SOURCE_SEARCH_TOGGLE_ID: str = 'title_action_search'" -Scope 'import observation overview restore control'
Assert-Contains -Text $importObserverText -Expected "V2_VERIFIED_COUNT_ID: str = 'novel_source_v2_verified_count'" -Scope 'import observation verified-count evidence'
Assert-Contains -Text $importObserverText -Expected 'count_component = total_count_component' -Scope 'import observation must prefer persisted total count'
Assert-Contains -Text $importObserverText -Expected "count_source = 'filtered_fallback'" -Scope 'import observation filter result is only a fallback'
Assert-Contains -Text $importObserverText -Expected "'restore_unfiltered_management_overview'" -Scope 'import observation must restore a transient text filter before asserting totals'
Assert-Contains -Text $importObserverText -Expected "count_source == 'total'" -Scope 'import observation must not pass on a filtered count'
Assert-Contains -Text $importObserverText -Expected "result['observed_source_count_scope'] = count_source" -Scope 'import evidence must identify its count scope'
Assert-Contains -Text $statsPanelText -Expected ("Text('" + $headlineLabel + "')") -Scope 'summary verification meaning'
Assert-Contains -Text $v2PanelText -Expected 'this.getV2VerificationStatusLabel()' -Scope 'ready versus verified status copy'
Assert-Contains -Text $v2PanelText -Expected 'this.getV2BlockerStatusLabel()' -Scope 'blocker status copy'
Assert-Contains -Text $v2PanelText -Expected 'this.getV2ValidationActivityLabel()' -Scope 'validation activity copy'
Assert-Contains -Text $pageText -Expected $readyLabel -Scope 'READY semantics'
Assert-Contains -Text $pageText -Expected $preparingLabel -Scope 'PARSED and COMPILED semantics'
Assert-Contains -Text $pageText -Expected $needsInteractionLabel -Scope 'interaction semantics'
Assert-Contains -Text $pageText -Expected $unsupportedLabel -Scope 'unsupported semantics'
Assert-Contains -Text $pageText -Expected $blockedLabel -Scope 'blocked semantics'
Assert-Contains -Text $pageText -Expected $legacyLabel -Scope 'legacy semantics'

Assert-Contains -Text $qualificationText -Expected 'this.isV2QualificationRunning = true;' -Scope 'qualification activity start'
Assert-Contains -Text $qualificationText -Expected 'this.v2QualificationTargetName = source.name;' -Scope 'qualification target name'
Assert-Contains -Text $qualificationText -Expected 'finally {' -Scope 'qualification cleanup'
Assert-Contains -Text $qualificationText -Expected 'this.isV2QualificationRunning = false;' -Scope 'qualification activity cleanup'
Assert-Contains -Text $qualificationText -Expected "this.v2QualificationTargetName = '';" -Scope 'qualification target cleanup'
Assert-Contains -Text $pageText -Expected $completeVerificationDefinition -Scope 'complete verification definition'
Assert-Contains -Text $pageText -Expected $batchValidationLimitation -Scope 'batch validation limitation'

Assert-Contract -Condition (Test-Path -LiteralPath $screenshotPath -PathType Leaf) -Message "baseline real-device screenshot is missing: $screenshotPath"
$screenshotInfo = Get-Item -LiteralPath $screenshotPath
Assert-Contract -Condition ([int64]$screenshotInfo.Length -ge 4096) -Message 'baseline screenshot is unexpectedly small.'

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) {
  [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null
}

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  status = 'static_passed_device_pending'
  scope = 'ISSUE-UI-009 V2 validation-statistics semantic contract'
  source = [pscustomobject][ordered]@{
    file = 'entry/src/main/ets/pages/NovelSourceManagementPage.ets'
    sha256 = Get-Sha256 -Path $pagePath
  }
  staticSemanticContract = [pscustomobject][ordered]@{
    v2SingleSourceOfTruth = $true
    allCompatibilityStatesClassified = $true
    historicalGroupCountersRemoved = $true
    sharedVerificationHeadline = $true
    readyIsNotVerified = $true
    qualificationActivityHasFinallyCleanup = $true
    completeVerificationDefinitionVisible = $true
    importedTotalIsHypiumObservable = $true
  }
  baselineScreenshot = [pscustomobject][ordered]@{
    file = 'frameidle-booksource-management-20260731.jpeg'
    bytes = [int64]$screenshotInfo.Length
    sha256 = Get-Sha256 -Path $screenshotPath
  }
  deviceRegression = [pscustomobject][ordered]@{
    status = 'pending'
    requiredChecks = @(
      'The summary and V2 policy panel use the same complete-verification numerator and denominator.',
      'The historical validation-group wording is absent.',
      'READY is not presented as verified or working.',
      'Interaction, blocked, unsupported, and legacy records are distinguishable.',
      'New status copy does not overflow or overlap.'
    )
  }
  reviewMethod = 'static semantic contract plus pre-change real-device baseline screenshot; post-change device regression remains required'
}

$temporaryPath = Join-Path $outputDirectory ('.' + [System.IO.Path]::GetFileName($OutputPath) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
try {
  [System.IO.File]::WriteAllText(
    $temporaryPath,
    ($result | ConvertTo-Json -Depth 10),
    [System.Text.UTF8Encoding]::new($false)
  )
  Move-Item -LiteralPath $temporaryPath -Destination $OutputPath -Force
} finally {
  if (Test-Path -LiteralPath $temporaryPath) {
    Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
  }
}

Write-Output ($result | ConvertTo-Json -Compress -Depth 10)
