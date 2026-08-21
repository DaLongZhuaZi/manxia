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
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\hypium-ordinal227-image-gate.json'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-ordinal227-image-workflow.json'
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Ordinal 227 IMAGE workflow contract failed: $Message" }
}

function Read-Utf8Json {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) "missing fixture: $Path"
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
}

$result = $null
try {
  $semanticsPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoContentSemantics.ets'
  $orchestratorPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoWorkflowOrchestrator.ets'
  $semantics = [System.IO.File]::ReadAllText($semanticsPath, [System.Text.UTF8Encoding]::new($false, $true))
  $orchestrator = [System.IO.File]::ReadAllText($orchestratorPath, [System.Text.UTF8Encoding]::new($false, $true))
  $fixture = Read-Utf8Json -Path $FixturePath
  Assert-Contract ([int]$fixture.sourceType -eq 2) 'fixture must describe an IMAGE source.'
  $content = @($fixture.detailTraceRecords | Where-Object { [string]$_.workflow -eq 'content' })[0]
  $bookInfo = @($fixture.detailTraceRecords | Where-Object { [string]$_.workflow -eq 'book_info' })[0]
  $toc = @($fixture.detailTraceRecords | Where-Object { [string]$_.workflow -eq 'toc' })[0]
  Assert-Contract ($null -ne $content) 'content trace must be present.'
  Assert-Contract ($null -ne $bookInfo) 'book_info trace must be present.'
  Assert-Contract ($null -ne $toc) 'toc trace must be present.'
  Assert-Contract ([string]$content.contentPresentation -eq 'readable') 'fixture must preserve the observed false-readable classification.'
  Assert-Contract ([string]$content.contentBridgeStatus -eq 'bridge_unavailable') 'fixture must preserve the unavailable image bridge witness.'
  Assert-Contract ([int]$content.imageNodeCount -eq 0) 'fixture must prove that no image node was produced.'
  Assert-Contract ([string]$fixture.expectedPostFixDiagnostics.bookInfo.outputKind -eq 'book_info_metadata_empty') 'IMAGE BookInfo must expose an explicit empty metadata output kind.'
  Assert-Contract ([string]$fixture.expectedPostFixDiagnostics.bookInfo.imageWorkflowOutcome -eq 'image_workflow_book_info_empty') 'IMAGE BookInfo must expose a structured empty-metadata outcome.'
  Assert-Contract ([string]$fixture.expectedPostFixDiagnostics.toc.outputKind -eq 'toc_nonempty_with_url_fallback') 'IMAGE Toc must retain Legado URL fallback chapters while exposing the fallback output kind.'
  Assert-Contract ([string]$fixture.expectedPostFixDiagnostics.toc.imageWorkflowOutcome -eq 'image_workflow_chapter_url_fallback') 'IMAGE Toc must expose URL fallback as a diagnostic, not silently drop entries.'
  Assert-Contract ([int]$fixture.expectedPostFixDiagnostics.toc.missingChapterUrlCount -eq [int]$toc.tocMissingChapterUrlCount) 'fixture must bind the expected missing URL count to the observed evidence.'
  Assert-Contract ([int]$fixture.expectedPostFixDiagnostics.toc.matchedElementCount -eq [int]$toc.tocMatchedElementCount) 'fixture must bind the expected matched element count to the observed evidence.'
  Assert-Contract ([int]$fixture.expectedPostFixDiagnostics.toc.droppedChapterUrlCount -eq 0) 'IMAGE URL fallback must not silently report dropped chapters.'
  Assert-Contract ($orchestrator.Contains('fallbackChapterUrlCount')) 'workflow must count Legado chapter URL fallbacks.'
  Assert-Contract ($orchestrator.Contains('droppedChapterUrlCount')) 'workflow must count unresolved chapter URL drops.'
  Assert-Contract ($orchestrator.Contains('image_workflow_chapter_url_fallback')) 'workflow must expose the IMAGE URL fallback outcome.'
  Assert-Contract ($orchestrator.Contains('bookVariable=${bookVariableState}')) 'TOC trace must expose whether the book variable carrier was present.'
  Assert-Contract ($orchestrator.Contains('outputKind=${outputKind}')) 'BookInfo/TOC traces must expose a structured output kind.'
  Assert-Contract ($semantics.Contains('INVALID_IMAGE')) 'content semantics must define an explicit invalid-image state.'
  Assert-Contract ($orchestrator.Contains('LegadoContentPresentationStatus.INVALID_IMAGE')) 'workflow orchestration must reject invalid IMAGE payloads instead of returning readable text.'
  Assert-Contract ($orchestrator.Contains('image_workflow_invalid_content')) 'workflow trace must expose a structured IMAGE rejection outcome.'

  $result = [pscustomobject][ordered]@{
    status = 'passed'
    contract = 'ordinal227_image_payload_gate'
    assertions = 22
    fixture = [System.IO.Path]::GetRelativePath($RepositoryRoot, $FixturePath).Replace('\\', '/')
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
} catch {
  $result = [pscustomobject][ordered]@{
    status = 'failed'
    contract = 'ordinal227_image_payload_gate'
    error = $_.Exception.Message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
}
$directory = Split-Path -Parent $ResultPath
if (-not (Test-Path -LiteralPath $directory)) { [void][System.IO.Directory]::CreateDirectory($directory) }
[System.IO.File]::WriteAllText($ResultPath, [string]($result | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
$result | ConvertTo-Json -Compress
if ($result.status -ne 'passed') { exit 1 }
