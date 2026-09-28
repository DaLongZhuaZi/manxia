[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$EvidenceDirectory = 'tools/legado-compat/evidence/r4-build-device-20260809-r4',
  [string]$OutputPath = 'tools/legado-compat/evidence/r4-build-device-20260809-r4/issue-009-build.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$sourceCount = 458
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-009'

function Get-RepositoryPath([string]$RelativePath) {
  if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $RelativePath }
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson([string]$RelativePath) {
  $path = Get-RepositoryPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing JSON: $RelativePath" }
  return ($strictUtf8.GetString([System.IO.File]::ReadAllBytes($path)) | ConvertFrom-Json)
}

function Set-PropertyValue([object]$Object, [string]$Name, [object]$Value) {
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
  else { $property.Value = $Value }
}

function Add-UniqueEvidence([object]$Issue, [string[]]$Paths) {
  $values = New-Object 'System.Collections.Generic.List[string]'
  $property = $Issue.PSObject.Properties['evidencePaths']
  if ($null -ne $property -and $null -ne $property.Value) {
    foreach ($value in @($property.Value)) {
      $normalized = ([string]$value).Replace('/', '\')
      if ($normalized.Length -gt 0 -and -not $values.Contains($normalized)) { [void]$values.Add($normalized) }
    }
  }
  foreach ($value in $Paths) {
    $normalized = ([string]$value).Replace('/', '\')
    if ($normalized.Length -gt 0 -and -not $values.Contains($normalized)) { [void]$values.Add($normalized) }
  }
  Set-PropertyValue $Issue 'evidencePaths' @($values.ToArray())
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepositoryPath $RelativePath
  [System.IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 80), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Get-FileSha256([string]$RelativePath) {
  return (Get-FileHash -LiteralPath (Get-RepositoryPath $RelativePath) -Algorithm SHA256).Hash.ToUpperInvariant()
}

$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$stdoutPath = Join-Path $EvidenceDirectory 'build.stdout.log'
$stderrPath = Join-Path $EvidenceDirectory 'build.stderr.log'
$hapPath = 'entry/build/default/outputs/default/entry-default-signed.hap'
$state = Read-StrictJson $statePath
$objective = Read-StrictJson $objectivePath
if ([int]$state.baseline.sourceCount -ne $sourceCount -or
    [string]$state.baseline.sourcePackageSha256 -ne $sourceHash -or
    [string]$state.baseline.legadoCommit -ne $legadoCommit) {
  throw 'ISSUE009_BUILD_BLOCKED: frozen baseline drifted.'
}
if (-not (Test-Path -LiteralPath (Get-RepositoryPath $stdoutPath) -PathType Leaf)) { throw 'ISSUE009_BUILD_BLOCKED: build stdout is missing.' }
if (-not (Test-Path -LiteralPath (Get-RepositoryPath $stderrPath) -PathType Leaf)) { throw 'ISSUE009_BUILD_BLOCKED: build stderr is missing.' }
$stdout = $strictUtf8.GetString([System.IO.File]::ReadAllBytes((Get-RepositoryPath $stdoutPath)))
$stderr = $strictUtf8.GetString([System.IO.File]::ReadAllBytes((Get-RepositoryPath $stderrPath)))
if ($stdout -notmatch 'BUILD SUCCESSFUL') { throw 'ISSUE009_BUILD_BLOCKED: BUILD SUCCESSFUL marker is missing.' }
if ($stderr -match 'COMPILE RESULT:FAIL|ArkTS Compiler Error|BUILD FAILED') { throw 'ISSUE009_BUILD_BLOCKED: compiler/build failure marker found.' }
if (-not (Test-Path -LiteralPath (Get-RepositoryPath $hapPath) -PathType Leaf)) { throw 'ISSUE009_BUILD_BLOCKED: signed HAP is missing.' }
$javaVersion = (& java -version 2>&1 | Out-String).Trim()
if ($javaVersion -notmatch 'version "21\.' -or [string]::IsNullOrWhiteSpace($env:JAVA_HOME)) {
  throw 'ISSUE009_BUILD_BLOCKED: build evidence must be recorded under JDK 21.'
}
$buildEvidence = [ordered]@{
  schemaVersion = 1
  kind = 'legado_issue_009_jdk21_hvigor_build'
  status = 'passed_static_only'
  issueId = $issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  toolchain = [ordered]@{ javaHome = $env:JAVA_HOME; javaVersion = $javaVersion; devecoSdkHome = $env:DEVECO_SDK_HOME; hvigor = 'F:\DevEco Studio\tools\hvigor\bin\hvigorw.bat' }
  build = [ordered]@{ task = 'assembleApp'; product = 'default'; buildMode = 'debug'; stdoutPath = $stdoutPath.Replace('\', '/'); stderrPath = $stderrPath.Replace('\', '/'); successMarker = 'BUILD SUCCESSFUL'; stderrFailureMarkers = @('COMPILE RESULT:FAIL', 'ArkTS Compiler Error', 'BUILD FAILED') }
  signedHap = [ordered]@{ path = $hapPath.Replace('\', '/'); sha256 = Get-FileSha256 $hapPath; bytes = (Get-Item -LiteralPath (Get-RepositoryPath $hapPath)).Length }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  nextGate = 'install-signed-hap-and-device-cold-start-smoke'
}
Write-AtomicJson $OutputPath $buildEvidence

$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId }) | Select-Object -First 1
if ($null -eq $issue) { throw 'ISSUE009_BUILD_BLOCKED: active issue is missing.' }
Add-UniqueEvidence -Issue $issue -Paths @($OutputPath, $hapPath, $stdoutPath, $stderrPath)
Set-PropertyValue $issue 'status' 'verifying'
Set-PropertyValue $issue 'summary' '009 源码静态合同已通过；JDK 21 Hvigor assembleApp debug 构建通过并生成 signed HAP，等待真机安装、冷启动和迁移 smoke。'
Set-PropertyValue $issue 'lastUpdatedAt' $buildEvidence.generatedAt
Set-PropertyValue $state.governance 'activeIssueId' $issueId
Set-PropertyValue $state.governance 'currentSourceClosureBoundary' $issueId
Set-PropertyValue $state.governance 'semanticMatchAllowed' $false
Set-PropertyValue $state.governance 'lastIssue009BuildEvidencePath' $OutputPath
Set-PropertyValue $state 'updatedAt' $buildEvidence.generatedAt

Import-Module -Name (Get-RepositoryPath 'tools/legado-compat/LegadoFullSourceState.psm1') -Force
Sync-LegadoStateDerivedFields -State $state
Write-AtomicJson $statePath $state
Set-PropertyValue $objective 'lastReviewedAt' $buildEvidence.generatedAt
Set-PropertyValue $objective 'nextAction' '安装最新 signed HAP，完成真机冷启动、数据库迁移和书源管理 smoke；设备证据通过后再进入全量 Harness 与 Legado 差分。'
Set-PropertyValue $objective.continuationTarget 'activeBoundary' 'ISSUE-COMPAT-009 保持 verifying：源码静态合同与 JDK 21 构建已通过，真机门禁待执行。'
Set-PropertyValue $objective.continuationTarget 'nextTransition' '安装 signed HAP 并执行冷启动/迁移 smoke；记录设备日志后再进入全量书源 Harness。'
Write-AtomicJson $objectivePath $objective
& pwsh -NoLogo -NoProfile -NonInteractive -File (Get-RepositoryPath 'tools/legado-compat/Invoke-LegadoCompatibility.ps1') -RefreshDocumentsOnly | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'ISSUE009_BUILD_BLOCKED: document refresh failed.' }
$buildEvidence | ConvertTo-Json -Depth 30
