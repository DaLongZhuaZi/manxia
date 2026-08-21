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
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $PSScriptRoot 'evidence\v2-java-object-content-overload-current-head-audit-20260809-r2.json'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$fixtureRelative = 'tools/legado-compat/fixtures/legado-java-object-content-overload-r2.json'
$preFixRelative = 'tools/legado-compat/evidence/contract-legado-java-object-content-overload-pre-fix-20260809-r2.json'
$staticContractRelative = 'tools/legado-compat/evidence/contract-legado-java-object-content-overload.json'

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required JSON is missing: $RelativePath" }
  return (Read-StrictText -Path $path | ConvertFrom-Json)
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

function Get-HelperBlocks {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$StartMarker,
    [Parameter(Mandatory = $true)][string[]]$EndMarkers
  )
  $blocks = New-Object 'System.Collections.Generic.List[string]'
  $searchOffset = 0
  while ($true) {
    $start = $Text.IndexOf($StartMarker, $searchOffset, [System.StringComparison]::Ordinal)
    if ($start -lt 0) { break }
    $end = Get-NextMarkerIndex -Text $Text -Start $start -Markers $EndMarkers
    [void]$blocks.Add($Text.Substring($start, $end - $start))
    $searchOffset = $end + 1
  }
  return $blocks.ToArray()
}

function Assert-Audit {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][string]$Detail,
    [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Checks
  )
  if (-not $Condition) { throw "238 current-head audit blocked: $Detail" }
  [void]$Checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail })
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 60), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$checks = New-Object 'System.Collections.Generic.List[object]'
$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
  $objective = Read-StrictJson -RelativePath 'tools/legado-compat/state/refactor-objective.json'
  $fixture = Read-StrictJson -RelativePath $fixtureRelative
  $preFix = Read-StrictJson -RelativePath $preFixRelative
  $staticContract = Read-StrictJson -RelativePath $staticContractRelative
  $enginePath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoJsEngine.ets'
  $runtimePath = Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html'
  $engine = Read-StrictText -Path $enginePath
  $runtime = Read-StrictText -Path $runtimePath

  Assert-Audit ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'fixed source and Legado baselines are unchanged.' $checks
  Assert-Audit ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS') 'queue' '237 remains the sole active queue anchor; 238 is audited without activating a second root cause.' $checks
  Assert-Audit ([string]$objective.executionTarget.currentIssue -eq 'ISSUE-COMPAT-237-JSOUP-INDEX-PSEUDO-SELECTORS' -and @($objective.executionTarget.nextIssues) -contains 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD') 'objective' 'the objective keeps 237 active and registers 238 as the next candidate.' $checks
  Assert-Audit ([string]$fixture.issueId -eq 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD' -and [int]$fixture.baselineSourceCount -eq 458 -and [string]$fixture.baselineSourcePackageSha256 -eq $baselineHash) 'fixture' '238 R2 fixture remains bound to the fixed 458-source baseline.' $checks
  Assert-Audit ([string]$preFix.status -eq 'failed' -and [string]$preFix.sourceSnapshotMode -eq 'git_head_pinned_pre_fix' -and -not [bool]$preFix.semanticMatchAllowed -and @($preFix.runtimeActionsPerformed).Count -eq 0) 'failure_witness' 'a pinned pre-fix source snapshot remains a static-only failing witness.' $checks
  $staticSemanticClaimAbsent = $staticContract.PSObject.Properties.Name -notcontains 'semanticMatchAllowed'
  Assert-Audit ([string]$staticContract.status -eq 'passed' -and [int]$staticContract.assertions -eq 20 -and ($staticSemanticClaimAbsent -or -not [bool]$staticContract.semanticMatchAllowed)) 'base_contract' 'the original object-content contract passes statically without a semantic-match claim.' $checks

  $engineStringBlocks = @(Get-HelperBlocks -Text $engine -StartMarker 'var __nativeGetStringFromContent = function' -EndMarkers @('var __nativeGetStringFromCurrentResult = function', 'var __nativeGetStringListFromCurrentResult = function', '// putLoginInfo函数（全局）'))
  $engineListBlocks = @(Get-HelperBlocks -Text $engine -StartMarker 'var __nativeGetStringListFromContent = function' -EndMarkers @('var __nativeGetStringListFromCurrentResult = function', 'var __nativeGetStringFromCurrentResult = function', '// putLoginInfo函数（全局）'))
  Assert-Audit ($engineStringBlocks.Count -eq 2 -and $engineListBlocks.Count -eq 2) 'helper_copies' 'both embedded native getString and getStringList helper copies are independently audited.' $checks
  Assert-Audit (($engineStringBlocks | Where-Object { $_.Contains('var replacement = __nativeSplitRuleReplacement(rule);') }).Count -eq 2) 'string_replacement_scope' 'every native getString helper declares its own replacement descriptor.' $checks
  Assert-Audit (($engineListBlocks | Where-Object { $_.Contains('var replacement = __nativeSplitRuleReplacement(rule);') }).Count -eq 2) 'list_replacement_scope' 'every native getStringList helper declares its own replacement descriptor.' $checks
  Assert-Audit (($engineListBlocks | Where-Object { $_.Contains('__nativeApplyRuleReplacement(value, replacement)') }).Count -eq 2) 'list_projection_replacement' 'every native list helper applies the descriptor to merged and projected values.' $checks
  Assert-Audit (($engineStringBlocks | Where-Object { $_.Contains('__nativeGetObjectContentValue(rule, contentValue)') -and ($_.Contains('__nativeJsonPathValues') -or $_.Contains('__getJsonPathValues')) }).Count -eq 2) 'string_object_jsonpath' 'every native string helper preserves object-first lookup and an explicit JSONPath bridge.' $checks
  Assert-Audit (($engineListBlocks | Where-Object { $_.Contains('__nativeGetObjectContentList(rule, contentValue)') -and ($_.Contains('__nativeJsonPathValues') -or $_.Contains('__getJsonPathValues')) }).Count -eq 2) 'list_object_jsonpath' 'every native list helper preserves object-first lookup and an explicit JSONPath bridge.' $checks
  Assert-Audit ($runtime.Contains('legadoGetObjectContentValue') -and $runtime.Contains('legadoGetObjectContentList') -and $runtime.Contains('getStringList: function (rule, content)')) 'arkweb' 'ArkWeb retains the typed object-content bridge.' $checks

  $sourcePaths = @('entry/src/main/resources/rawfile/legado_runtime.html', 'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets')
  $hashes = [ordered]@{}
  foreach ($relativePath in $sourcePaths) {
    $absolutePath = Join-Path $RepositoryRoot ($relativePath.Replace('/', '\'))
    $hashes[$relativePath] = (Get-FileHash -LiteralPath $absolutePath -Algorithm SHA256).Hash.ToUpperInvariant()
  }

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    evidenceType = 'legado_java_object_content_overload_r2_current_head_audit'
    issueId = 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD'
    status = 'passed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
    fixture = $fixtureRelative
    failureWitness = $preFixRelative
    staticContract = $staticContractRelative
    currentHeadPaths = $sourcePaths
    currentHeadHashes = $hashes
    consumerMatrix = @(
      [pscustomobject][ordered]@{ id = 'arkweb'; path = 'entry/src/main/resources/rawfile/legado_runtime.html'; semantics = @('object key lookup', 'falsy 0/false', 'array/newline list projection', '## replacement') },
      [pscustomobject][ordered]@{ id = 'standard_jsvm'; path = 'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets'; semantics = @('object key lookup', 'JSONPath/CSS dispatch', 'replacement scope') },
      [pscustomobject][ordered]@{ id = 'native_jsvm'; path = 'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets'; semantics = @('object key lookup', 'JSONPath/CSS dispatch', 'replacement scope') },
      [pscustomobject][ordered]@{ id = 'embedded_native_helper_copy'; path = 'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets'; semantics = @('duplicate helper parity', 'local replacement descriptor') }
    )
    assertions = $checks.Count
    checks = $checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_current_head_static_audit_only;runtime_build_device_and_legado_diff_deferred'
    nextGate = 'Complete 238 source-fix evidence and 237-to-238 static transition registration; do not activate 238 or start R4 until the queue gate is atomically updated.'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    evidenceType = 'legado_java_object_content_overload_r2_current_head_audit'
    issueId = 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $checks.Count
    checks = $checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_current_head_static_audit_only;runtime_build_device_and_legado_diff_deferred'
  }
}

$outputFullPath = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
  $OutputPath
} else {
  Join-Path $RepositoryRoot ($OutputPath.Replace('/', '\'))
}
Write-AtomicJson -Path $outputFullPath -Value $result
$result | ConvertTo-Json -Depth 60
if ($exitCode -ne 0) { exit $exitCode }
