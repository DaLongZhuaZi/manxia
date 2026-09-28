[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RunId = 'v2-crypto-002-current-head-hash-audit-20260808-r1',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($RepositoryRoot.Length -eq 0) {
  $RepositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$evidenceRoot = (Resolve-Path -LiteralPath (Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).Path
$runDirectory = Join-Path $evidenceRoot $RunId
if ($OutputPath.Length -eq 0) {
  $OutputPath = Join-Path $runDirectory 'current-head-hash-audit.json'
}
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$evidencePrefix = $evidenceRoot.TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidencePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Crypto current-head evidence must remain under the evidence directory.'
}
if (-not (Test-Path -LiteralPath $runDirectory)) {
  [System.IO.Directory]::CreateDirectory($runDirectory) | Out-Null
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:checks = New-Object 'System.Collections.Generic.List[object]'
$script:assertions = 0

function Read-StrictUtf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { throw "Required file is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  try { return (Read-StrictUtf8Text -Path $Path | ConvertFrom-Json) } catch { throw "Invalid JSON: $Path; $($_.Exception.Message)" }
}

function Assert-Gate {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw $Message }
  $script:assertions++
}

function Add-Check {
  param([string]$Id, [string]$Detail, [string[]]$Evidence = @())
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) })
}

function Get-Sha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-AbsoluteRepositoryPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $candidate = Join-Path $RepositoryRoot ($RelativePath -replace '/', '\\')
  return (Resolve-Path -LiteralPath $candidate).Path
}

$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$objectivePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\refactor-objective.json'
$sourceFixPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-crypto-002-source-fix-20260808.json'
$staticContractPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-crypto-002-static-contract-20260808.json'
$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\v2-crypto-002-transformation-matrix.json'
$contractPath = Join-Path $RepositoryRoot 'tools\legado-compat\Test-LegadoCryptoTransformationContract.ps1'
$packagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'

$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -Path $statePath
  $objective = Read-StrictJson -Path $objectivePath
  $sourceFix = Read-StrictJson -Path $sourceFixPath
  $staticContract = Read-StrictJson -Path $staticContractPath
  $fixture = Read-StrictJson -Path $fixturePath
  $baseline = $state.baseline
  Assert-Gate ([int]$baseline.sourceCount -eq 458 -and [string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine baseline is not frozen.'
  Assert-Gate ((Get-Sha256 -Path $packagePath) -eq [string]$baseline.sourcePackageSha256) 'source package hash drifted.'
  $legadoHead = (& git -C (Join-Path $RepositoryRoot 'legado') rev-parse HEAD 2>$null | Out-String).Trim()
  Assert-Gate ($legadoHead -eq [string]$baseline.legadoCommit) 'Legado checkout is not at the frozen commit.'
  Add-Check -Id 'baseline_binding' -Detail 'State, source package and Legado checkout remain bound to the frozen baseline.' -Evidence @('tools/legado-compat/state/full-source-validation-state.json')

  Assert-Gate ([string]$sourceFix.issueId -eq 'ISSUE-COMPAT-CRYPTO-002' -and [string]$sourceFix.status -eq 'source_fix_applied_pending_verification' -and -not [bool]$sourceFix.semanticMatchAllowed) 'source-fix evidence is not static-only.'
  Assert-Gate ([string]$staticContract.issueId -eq 'ISSUE-COMPAT-CRYPTO-002' -and [string]$staticContract.status -eq 'passed' -and [int]$staticContract.assertions -eq 24 -and -not [bool]$staticContract.semanticMatchAllowed) 'static contract evidence is missing or semantically over-claimed.'
  Assert-Gate ([string]$fixture.issueId -eq 'ISSUE-COMPAT-CRYPTO-002' -and [string]$fixture.verificationPolicy -match 'runtime_regression_deferred_to_R4') 'fixture is not bound to the Crypto static policy.'
  Add-Check -Id 'static_closure_binding' -Detail 'Crypto failure fixture, source-fix evidence and 24-assertion static contract are all present without a semantic-match claim.' -Evidence @('tools/legado-compat/evidence/v2-crypto-002-pre-fix-static-contract-20260808.json', 'tools/legado-compat/evidence/v2-crypto-002-source-fix-20260808.json', 'tools/legado-compat/evidence/v2-crypto-002-static-contract-20260808.json')

  $hashes = New-Object 'System.Collections.Generic.List[object]'
  foreach ($property in $sourceFix.sourceHashes.PSObject.Properties) {
    $relativePath = [string]$property.Name
    $absolutePath = Get-AbsoluteRepositoryPath -RelativePath $relativePath
    $actualHash = Get-Sha256 -Path $absolutePath
    Assert-Gate ($actualHash -eq ([string]$property.Value).ToUpperInvariant()) ("source hash drifted: {0}" -f $relativePath)
    [void]$hashes.Add([pscustomobject][ordered]@{ path = $relativePath; sha256 = $actualHash })
  }
  $fixtureHash = Get-Sha256 -Path $fixturePath
  $contractHash = Get-Sha256 -Path $contractPath
  Assert-Gate ($fixtureHash -eq ([string]$sourceFix.fixtureSha256).ToUpperInvariant()) 'Crypto fixture hash drifted from source-fix evidence.'
  Assert-Gate ($contractHash -eq ([string]$sourceFix.contractSha256).ToUpperInvariant()) 'Crypto contract hash drifted from source-fix evidence.'
  Add-Check -Id 'current_head_hashes' -Detail 'All four implementation paths, the fixture and the static contract remain byte-bound to the Crypto source-fix evidence.' -Evidence @('tools/legado-compat/evidence/v2-crypto-002-source-fix-20260808.json')

  $implementationPaths = @($sourceFix.implementationPaths | ForEach-Object { [string]$_ })
  Assert-Gate ($implementationPaths.Count -eq 4 -and $implementationPaths -contains 'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets' -and $implementationPaths -contains 'entry/src/main/ets/Framework/Novel/LegadoRuntimeV2.ets' -and $implementationPaths -contains 'entry/src/main/resources/rawfile/legado_runtime.html' -and $implementationPaths -contains 'entry/src/main/ets/Framework/Novel/LegadoJsApiContractRegistry.ets') 'Crypto implementation scope is incomplete.'
  Add-Check -Id 'implementation_scope' -Detail 'Standard JSVM, Native JSVM, ArkWeb bridge and API registry are all included in the source closure scope.' -Evidence $implementationPaths

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_crypto_002_current_head_hash_audit'
    issueId = 'ISSUE-COMPAT-CRYPTO-002'
    status = 'current_head_bound_static_closure'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    baseline = [pscustomobject][ordered]@{ sourceCount = [int]$baseline.sourceCount; sourcePackageSha256 = [string]$baseline.sourcePackageSha256; legadoCommit = [string]$baseline.legadoCommit }
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    implementationHashes = $hashes.ToArray()
    fixtureSha256 = $fixtureHash
    contractSha256 = $contractHash
    staticContractAssertions = [int]$staticContract.assertions
    evidencePaths = @('tools/legado-compat/evidence/v2-crypto-002-pre-fix-static-contract-20260808.json', 'tools/legado-compat/evidence/v2-crypto-002-source-fix-20260808.json', 'tools/legado-compat/evidence/v2-crypto-002-static-contract-20260808.json', 'tools/legado-compat/fixtures/v2-crypto-002-transformation-matrix.json')
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_crypto_current_head_static_only;R4_runtime_build_device_and_legado_diff_deferred'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{ schemaVersion = 1; kind = 'legado_crypto_002_current_head_hash_audit'; issueId = 'ISSUE-COMPAT-CRYPTO-002'; status = 'failed'; generatedAt = [DateTimeOffset]::UtcNow.ToString('o'); failure = $_.Exception.Message; assertions = $script:assertions; checks = $script:checks.ToArray(); evidencePaths = @(); runtimeActionsPerformed = @(); semanticMatchAllowed = $false; verificationPolicy = 'r3_crypto_current_head_static_only;R4_runtime_build_device_and_legado_diff_deferred' }
}

$temporaryPath = "$outputFullPath.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
[System.IO.File]::WriteAllText($temporaryPath, ($result | ConvertTo-Json -Depth 24), [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $outputFullPath -Force
$result | ConvertTo-Json -Depth 24
if ($exitCode -ne 0) { exit $exitCode }
