[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = '',
  [switch]$UseCurrentWorkingTree
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $PSScriptRoot 'evidence\contract-legado-java-object-content-overload-pre-fix-20260809-r2.json'
}
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-java-object-content-overload-r2.json'
$enginePath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoJsEngine.ets'
$runtimePath = Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html'
foreach ($path in @($fixturePath, $enginePath, $runtimePath)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required 238 R2 contract input is missing: $path" }
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return $strictUtf8.GetString($bytes)
}

function Read-GitHeadText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $gitPath = $RelativePath.Replace('\', '/').TrimStart('/')
  $snapshot = (& git -C $RepositoryRoot show ("HEAD:" + $gitPath) 2>$null | Out-String)
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrEmpty($snapshot)) {
    throw "Git HEAD snapshot is missing: $RelativePath"
  }
  return $snapshot.TrimEnd("`r", "`n")
}

function Get-FunctionBlock {
  param([Parameter(Mandatory = $true)][string]$Text, [Parameter(Mandatory = $true)][string]$Marker, [Parameter(Mandatory = $true)][string]$EndMarker)
  $start = $Text.IndexOf($Marker, [System.StringComparison]::Ordinal)
  if ($start -lt 0) { return '' }
  $end = $Text.IndexOf($EndMarker, $start + $Marker.Length, [System.StringComparison]::Ordinal)
  if ($end -lt 0) { return $Text.Substring($start) }
  return $Text.Substring($start, $end - $start)
}

function Get-NextMarkerIndex {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][int]$Start,
    [Parameter(Mandatory = $true)][string[]]$Markers
  )
  $next = $Text.Length
  foreach ($marker in $Markers) {
    $candidate = $Text.IndexOf($marker, $Start, [System.StringComparison]::Ordinal)
    if ($candidate -ge 0 -and $candidate -lt $next) { $next = $candidate }
  }
  return $next
}

$fixture = (Read-StrictText -Path $fixturePath | ConvertFrom-Json)
$sourceSnapshotMode = if ($UseCurrentWorkingTree) { 'current_working_tree_counterfactual' } else { 'git_head_pinned_pre_fix' }
$engine = if ($UseCurrentWorkingTree) { Read-StrictText -Path $enginePath } else { Read-GitHeadText -RelativePath 'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets' }
$runtime = if ($UseCurrentWorkingTree) { Read-StrictText -Path $runtimePath } else { Read-GitHeadText -RelativePath 'entry/src/main/resources/rawfile/legado_runtime.html' }
$sourceRevision = if ($UseCurrentWorkingTree) { 'working-tree' } else { (& git -C $RepositoryRoot rev-parse HEAD).Trim() }
$checks = New-Object 'System.Collections.Generic.List[object]'
$failures = New-Object 'System.Collections.Generic.List[string]'
$assertions = 0
function Assert-Contract {
  param([bool]$Condition, [string]$Id, [string]$Detail)
  $script:assertions++
  $status = if ($Condition) { 'passed' } else { 'failed' }
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = $status; detail = $Detail })
  if (-not $Condition) { [void]$script:failures.Add($Detail) }
}

$firstNativeString = Get-FunctionBlock -Text $engine -Marker 'var __nativeGetStringFromContent = function' -EndMarker 'var __nativeGetStringFromCurrentResult = function'
$firstNativeList = Get-FunctionBlock -Text $engine -Marker 'var __nativeGetStringListFromContent = function' -EndMarker '// putLoginInfo函数（全局）'
$nativeStringBlocks = @()
$searchOffset = 0
while ($true) {
  $index = $engine.IndexOf('var __nativeGetStringFromContent = function', $searchOffset, [System.StringComparison]::Ordinal)
  if ($index -lt 0) { break }
  $endIndex = Get-NextMarkerIndex -Text $engine -Start $index -Markers @(
    'var __nativeGetStringFromCurrentResult = function',
    'var __nativeGetStringListFromCurrentResult = function',
    '// putLoginInfo函数（全局）'
  )
  $nativeStringBlocks += $engine.Substring($index, $endIndex - $index)
  $searchOffset = $endIndex + 1
}
$nativeListBlocks = @()
$searchOffset = 0
while ($true) {
  $index = $engine.IndexOf('var __nativeGetStringListFromContent = function', $searchOffset, [System.StringComparison]::Ordinal)
  if ($index -lt 0) { break }
  $endIndex = Get-NextMarkerIndex -Text $engine -Start $index -Markers @(
    'var __nativeGetStringListFromCurrentResult = function',
    'var __nativeGetStringFromCurrentResult = function',
    '// putLoginInfo函数（全局）'
  )
  $nativeListBlocks += $engine.Substring($index, $endIndex - $index)
  $searchOffset = $endIndex + 1
}

Assert-Contract ([string]$fixture.issueId -eq 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD' -and [int]$fixture.baselineSourceCount -eq 458 -and [string]$fixture.baselineSourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'baseline' 'R2 fixture is bound to the fixed 458-source baseline.'
Assert-Contract (@($fixture.cases).Count -eq 7) 'fixture_cases' 'R2 fixture contains all three consumers and the embedded helper regression cases.'
Assert-Contract ($runtime.Contains('legadoGetObjectContentValue') -and $runtime.Contains('legadoGetObjectContentList') -and $runtime.Contains('getStringList: function (rule, content)')) 'arkweb_consumers' 'ArkWeb exposes object-content helpers through both getString and getStringList.'
Assert-Contract ($engine.Contains('var __getObjectContentValue = function') -and $engine.Contains('var __getObjectContentList = function') -and $engine.Contains('var __nativeGetObjectContentValue = function') -and $engine.Contains('var __nativeGetObjectContentList = function')) 'runtime_helpers' 'standard and native ArkTS helper families are present.'
Assert-Contract ($nativeStringBlocks.Count -eq 2 -and $nativeListBlocks.Count -eq 2) 'native_helper_copies' 'both embedded native helper copies must be audited.'
Assert-Contract ($firstNativeString.Contains('var replacement = __nativeSplitRuleReplacement(rule);')) 'first_native_string_replacement' 'the embedded native getString helper must declare its replacement descriptor before composition.'
Assert-Contract ($firstNativeList.Contains('var replacement = __nativeSplitRuleReplacement(rule);')) 'first_native_list_replacement' 'the embedded native getStringList helper must declare its replacement descriptor.'
Assert-Contract ($firstNativeList.Contains('__nativeApplyRuleReplacement(value, replacement)')) 'first_native_list_projection' 'the embedded native list helper must apply replacement to CSS/JSONPath projections.'
Assert-Contract ($firstNativeString.Contains('__nativeJsonPathValues') -or $firstNativeString.Contains('__getJsonPathValues')) 'first_native_jsonpath' 'the embedded native getString helper must keep an explicit JSONPath bridge.'
Assert-Contract ($firstNativeList.Contains('__nativeJsonPathValues') -or $firstNativeList.Contains('__getJsonPathValues')) 'first_native_list_jsonpath' 'the embedded native getStringList helper must keep an explicit JSONPath bridge.'
Assert-Contract ($nativeStringBlocks | Where-Object { -not $_.Contains('var replacement = __nativeSplitRuleReplacement(rule);') } | Measure-Object).Count -eq 0 'all_native_string_replacements' 'every native getString helper copy declares a local replacement descriptor.'
Assert-Contract ($nativeListBlocks | Where-Object { -not $_.Contains('var replacement = __nativeSplitRuleReplacement(rule);') } | Measure-Object).Count -eq 0 'all_native_list_replacements' 'every native getStringList helper copy declares a local replacement descriptor.'
Assert-Contract ($nativeListBlocks | Where-Object { -not $_.Contains('__nativeApplyRuleReplacement(value, replacement)') } | Measure-Object).Count -eq 0 'all_native_list_projection' 'every native getStringList helper copy applies replacement to list output.'
Assert-Contract ($engine.Contains('getString: function(rule, content)') -and $engine.Contains('__getStringFromContent(rule, content)') -and $engine.Contains('__nativeGetStringFromContent(rule, content)')) 'entrypoint_handoff' 'standard/native java.getString entrypoints retain typed handoff.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'legado_java_object_content_overload_r2_pre_fix_contract'
  issueId = 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD'
  status = if ($failures.Count -eq 0) { 'passed' } else { 'failed' }
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'; legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd' }
  fixture = 'tools/legado-compat/fixtures/legado-java-object-content-overload-r2.json'
  assertions = $assertions
  checks = $checks.ToArray()
  failedAssertions = $failures.ToArray()
  currentHeadPaths = @('entry/src/main/resources/rawfile/legado_runtime.html', 'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets')
  sourceRevision = $sourceRevision
  sourceSnapshotMode = $sourceSnapshotMode
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_failure_witness_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  reproduction = 'pwsh -NoProfile -File tools/legado-compat/Test-LegadoJavaObjectContentOverloadPreFixContractR2.ps1'
}
$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) { [System.IO.Directory]::CreateDirectory($outputDirectory) | Out-Null }
$temporaryPath = "$OutputPath.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
try {
  [System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 60), $utf8NoBom)
  Move-Item -LiteralPath $temporaryPath -Destination $OutputPath -Force
} finally {
  if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
}
$result | ConvertTo-Json -Depth 60
if ($failures.Count -eq 0) { throw '238 R2 failure witness unexpectedly passed; do not continue without a real pre-fix witness.' }
exit 1
