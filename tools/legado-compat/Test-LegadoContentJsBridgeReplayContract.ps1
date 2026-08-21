[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-content-033-source-fix-20260809.json'
}

$fixturePath = Join-Path $PSScriptRoot 'fixtures\legado-content-js-bridge-replay.json'
$runtimePath = Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html'
$fixture = Get-Content -LiteralPath $fixturePath -Raw -Encoding UTF8 | ConvertFrom-Json
$runtime = [System.IO.File]::ReadAllText($runtimePath, [System.Text.UTF8Encoding]::new($false))

$assertions = New-Object 'System.Collections.Generic.List[object]'
function Assert-Contract {
  param([bool]$Condition, [string]$Id, [string]$Detail)
  $status = if ($Condition) { 'passed' } else { 'failed' }
  [void]$assertions.Add([pscustomobject][ordered]@{ id = $Id; status = $status; detail = $Detail })
  if (-not $Condition) { throw ('CONTENT_033_CONTRACT_FAILED:{0}:{1}' -f $Id, $Detail) }
}

$sourceObjectStart = $runtime.IndexOf('var source = {', [System.StringComparison]::Ordinal)
$sourceGetStart = $runtime.IndexOf('get: function (key)', $sourceObjectStart, [System.StringComparison]::Ordinal)
$sourcePutStart = $runtime.IndexOf('put: function (key, value)', $sourceGetStart, [System.StringComparison]::Ordinal)
Assert-Contract ($sourceGetStart -ge 0 -and $sourcePutStart -gt $sourceGetStart) 'source_get_block_present' 'runtime source.get block is present'
$sourceGetBlock = $runtime.Substring($sourceGetStart, $sourcePutStart - $sourceGetStart)
$sourceDataIndex = $sourceGetBlock.IndexOf('if (sourceData[key] !== undefined)', [System.StringComparison]::Ordinal)
$bookSourceTypeIndex = $sourceGetBlock.IndexOf("if (key === 'bookSourceType') return source.bookSourceType", [System.StringComparison]::Ordinal)
$legacyShadowingIndex = $sourceGetBlock.IndexOf("if (key === 'type' || key === 'bookSourceType') return source.bookSourceType", [System.StringComparison]::Ordinal)
Assert-Contract ($sourceDataIndex -ge 0) 'source_data_lookup_present' 'source.get consults persisted source data'
Assert-Contract ($bookSourceTypeIndex -gt $sourceDataIndex) 'book_source_type_fallback_after_data' 'bookSourceType fallback does not shadow persisted data'
Assert-Contract ($legacyShadowingIndex -lt 0) 'type_shadowing_removed' 'type is not forced to numeric bookSourceType'

$requestBridgeStart = $runtime.IndexOf('function requestBridge(request)', [System.StringComparison]::Ordinal)
$requestBridgeReplay = $runtime.IndexOf('state.bridgeResponses && state.bridgeResponses[request.id]', [System.StringComparison]::Ordinal)
$ajaxIndex = $runtime.IndexOf('ajax: function (url)', [System.StringComparison]::Ordinal)
$jsonParseIndex = $runtime.IndexOf('JSON.parse(', [System.StringComparison]::Ordinal)
Assert-Contract ($requestBridgeStart -ge 0 -and $requestBridgeReplay -gt $requestBridgeStart) 'bridge_replay_lookup' 'resolved bridge responses are reused on replay'
Assert-Contract ($ajaxIndex -ge 0) 'java_ajax_bridge' 'java.ajax is exposed by the runtime bridge'
Assert-Contract ($jsonParseIndex -ge 0) 'json_parse_available' 'the runtime supports JSON.parse for ajax payloads'
Assert-Contract ($runtime.Contains('return buildResponse(''pending''')) 'pending_envelope' 'bridge requests produce a pending envelope'
Assert-Contract ($runtime.Contains('result: toText(value)')) 'completion_value_propagation' 'the final JavaScript completion value reaches the envelope'

foreach ($case in @($fixture.sourceDataCases)) {
  Assert-Contract ([string]$case.expectedSourceGetType -in @('', 'novel')) "fixture_case_$($case.name)" "fixture case $($case.name) is bounded to Legado source.get semantics"
}
Assert-Contract ([string]$fixture.bridgeReplay.expectedJsResult -eq 'non_empty_content') 'non_empty_result_expected' 'selected branch must yield non-empty content after replay'

$evidence = [pscustomobject][ordered]@{
  schemaVersion = 1
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  issueId = [string]$fixture.issueId
  fixturePath = [System.IO.Path]::GetRelativePath($RepositoryRoot, $fixturePath).Replace('\', '/')
  runtimePath = [System.IO.Path]::GetRelativePath($RepositoryRoot, $runtimePath).Replace('\', '/')
  status = 'passed'
  assertionCount = $assertions.Count
  assertions = $assertions.ToArray()
  execution = 'static_source_contract_only'
  runtimeRegression = 'not_run'
  deviceRegression = 'not_run'
}
$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory)) { [void][System.IO.Directory]::CreateDirectory($outputDirectory) }
$temporaryPath = "$OutputPath.tmp.$PID.$([Guid]::NewGuid().ToString('N'))"
try {
  [System.IO.File]::WriteAllText($temporaryPath, [string]($evidence | ConvertTo-Json -Depth 16), [System.Text.UTF8Encoding]::new($false))
  [System.IO.File]::Move($temporaryPath, $OutputPath, $true)
} finally {
  if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
}
$evidence | ConvertTo-Json -Compress
