[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = '',
  [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
if ([string]::IsNullOrWhiteSpace($FixturePath)) {
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-output-handoff.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-output-handoff.json'
}

$assertions = 0
function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Legado output handoff contract failed: $Message" }
  $script:assertions++
}

function Read-Utf8Text {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) "missing file: $Path"
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

function Write-Result {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) {
    [void][System.IO.Directory]::CreateDirectory($directory)
  }
  $temporaryPath = "$Path.tmp-$PID"
  [System.IO.File]::WriteAllText($temporaryPath, [string]($Value | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

$result = $null
try {
  $fixture = (Read-Utf8Text -Path $FixturePath) | ConvertFrom-Json
  $typesPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoCompatibilityTypes.ets'
  $sourceTypesPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoSourceTypes.ets'
  $orchestratorPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoWorkflowOrchestrator.ets'
  $managerPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\NovelSourceManager.ets'
  $bridgePath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoMangaSourceBridge.ets'
  $readerPath = Join-Path $RepositoryRoot 'entry\src\main\ets\pages\NovelReaderPage.ets'
  $audioPagePath = Join-Path $RepositoryRoot 'entry\src\main\ets\pages\NovelReadAloudPage.ets'
  $audioSessionPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\ReadAloud\NovelAudioReadAloudSessionManager.ets'
  $types = Read-Utf8Text -Path $typesPath
  $sourceTypes = Read-Utf8Text -Path $sourceTypesPath
  $orchestrator = Read-Utf8Text -Path $orchestratorPath
  $manager = Read-Utf8Text -Path $managerPath
  $bridge = Read-Utf8Text -Path $bridgePath
  $reader = Read-Utf8Text -Path $readerPath
  $audioPage = Read-Utf8Text -Path $audioPagePath
  $audioSession = Read-Utf8Text -Path $audioSessionPath

  Assert-Contract ([string]$fixture.contract -eq 'legado_v2_output_handoff') 'fixture contract must identify the output boundary.'
  Assert-Contract ([int]$fixture.baseline.sourceCount -eq 458) 'fixture baseline source count must remain 458.'
  Assert-Contract ([string]$fixture.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'fixture must bind the fixed Legado commit.'
  Assert-Contract ([bool]$fixture.legadoSemantics.bookInfoFile.downloadUrlsRequired) 'FILE BookInfo must require downloadUrls.'
  Assert-Contract ([string]$fixture.legadoSemantics.bookInfoFile.emptyDownloadUrls -eq 'failure') 'empty FILE downloadUrls must be a failure.'
  Assert-Contract ($fixture.requiredPostFix.kinds.Count -eq 4) 'fixture must cover TEXT/AUDIO/IMAGE/FILE.'
  Assert-Contract ($fixture.requiredPostFix.forbidden -contains 'file_to_text_downgrade') 'fixture must forbid FILE to TEXT downgrade.'
  Assert-Contract ($types.Contains('LegadoWorkflowOutputKind')) 'typed workflow output kind must exist.'
  Assert-Contract ($types.Contains('LegadoWorkflowHandoffStatus')) 'typed handoff status must exist.'
  Assert-Contract ([string]$fixture.requiredPostFix.fileHandoff.nonEmptyCandidatesStatus -eq 'missing_consumer') 'FILE candidates without a downloader must be an explicit missing-consumer handoff.'
  Assert-Contract ([string]$fixture.requiredPostFix.fileHandoff.nonEmptyCandidatesReason -eq 'file_downloader_consumer_missing') 'FILE missing-consumer reason must be stable and machine-readable.'
  Assert-Contract ([string]$fixture.requiredPostFix.fileHandoff.emptyCandidatesStatus -eq 'empty') 'FILE without download URLs must remain empty/failure.'
  Assert-Contract ([string]$fixture.requiredPostFix.fileHandoff.emptyCandidatesReason -eq 'file_download_urls_empty') 'FILE empty reason must be stable and machine-readable.'
  Assert-Contract ($sourceTypes.Contains('downloadUrls')) 'book model must retain original downloadUrls.'
  Assert-Contract ($types.Contains('downloadCandidates')) 'BookInfo result must retain download candidates.'
  Assert-Contract ($types.Contains('textContent') -and $types.Contains('mediaUrl') -and $types.Contains('imageContent')) 'typed payload fields must exist.'
  Assert-Contract ($types.Contains('payAction') -or $types.Contains('pay_action')) 'typed result must expose payAction outcome.'
  Assert-Contract ($types.Contains('imageDecode') -or $types.Contains('image_decode')) 'typed result must expose imageDecode outcome.'
  Assert-Contract ($orchestrator.Contains('LegadoWorkflowOutputKind.FILE')) 'orchestrator must branch FILE explicitly.'
  Assert-Contract ($orchestrator.Contains('downloadUrls')) 'orchestrator must write parsed downloadUrls to the book result.'
  Assert-Contract ($orchestrator.Contains('file_download_urls_empty')) 'orchestrator must reject an empty FILE downloadUrls result.'
  Assert-Contract ($orchestrator.Contains('file_downloader_consumer_missing')) 'orchestrator must refuse FILE output until a downloader consumer exists.'
  Assert-Contract ($types.Contains('LegadoWorkflowHandoffStatus.MISSING_CONSUMER') -and $types.Contains("'file_downloader_consumer_missing'")) 'default FILE handoff must not claim READY when candidates have no consumer.'
  Assert-Contract ($orchestrator.Contains('createContentHandoff')) 'orchestrator must construct a typed content handoff.'
  Assert-Contract ($orchestrator.Contains('payAction') -and $orchestrator.Contains('imageDecode')) 'orchestrator must classify auxiliary rule outcomes.'
  Assert-Contract ($manager.Contains('getBookInfoWithResult')) 'manager must expose the typed BookInfo result.'
  Assert-Contract ($manager.Contains('getContentWithResult')) 'manager must expose the typed Content result.'
  Assert-Contract ($manager.Contains('V2_OUTPUT_HANDOFF_BLOCKED')) 'manager must reject an unconsumed or invalid handoff explicitly.'
  Assert-Contract ($manager.Contains('downloadCandidates')) 'manager must not discard FILE candidates.'
  Assert-Contract ($manager.Contains('getFileDownloadCandidates')) 'manager must expose an explicit FILE handoff boundary.'
  Assert-Contract ($bridge.Contains('getContentWithResult') -or $bridge.Contains('imageContent')) 'IMAGE bridge must consume a typed content handoff.'
  Assert-Contract ($reader.Contains('getContentWithResult') -or $reader.Contains('textContent')) 'TEXT reader must consume the typed content payload.'
  Assert-Contract ($audioPage.Contains('getContentWithResult') -or $audioPage.Contains('mediaUrl')) 'audio page must consume the typed media payload.'
  Assert-Contract ($audioSession.Contains('getContentWithResult') -or $audioSession.Contains('mediaUrl')) 'audio session must consume the typed media payload.'

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'passed'
    contract = [string]$fixture.contract
    assertions = $assertions
    fixture = [System.IO.Path]::GetRelativePath($RepositoryRoot, $FixturePath).Replace('\', '/')
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'failed'
    contract = 'legado_v2_output_handoff'
    assertions = $assertions
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
}

Write-Result -Path $ResultPath -Value $result
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') { exit 1 }
