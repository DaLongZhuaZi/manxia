[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$EvidenceDirectory = 'tools/legado-compat/evidence/r4-build-device-20260809-r2'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$utf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$sourceCount = 458
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-241-ARKTS-INLINE-OBJECT-TYPES'
$statePath = 'tools/legado-compat/state/full-source-validation-state.json'
$objectivePath = 'tools/legado-compat/state/refactor-objective.json'
$stdoutRelative = Join-Path $EvidenceDirectory 'build.stdout.log'
$stderrRelative = Join-Path $EvidenceDirectory 'build.stderr.log'
$hapRelative = 'entry/build/default/outputs/default/entry-default-signed.hap'

function Get-RepositoryPath([string]$RelativePath) {
  if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $RelativePath }
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}
function Read-StrictJson([string]$RelativePath) {
  $bytes = [System.IO.File]::ReadAllBytes((Get-RepositoryPath $RelativePath))
  return $utf8.GetString($bytes) | ConvertFrom-Json
}
function Set-PropertyValue([object]$Object, [string]$Name, [object]$Value) {
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
  else { $property.Value = $Value }
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

$state = Read-StrictJson $statePath
$objective = Read-StrictJson $objectivePath
if ([int]$state.baseline.sourceCount -ne $sourceCount -or [string]$state.baseline.sourcePackageSha256 -ne $sourceHash -or [string]$state.baseline.legadoCommit -ne $legadoCommit) { throw 'ISSUE241_BUILD_BLOCKED: frozen baseline drifted.' }
$stdout = [System.IO.File]::ReadAllText((Get-RepositoryPath $stdoutRelative), $utf8)
$stderr = [System.IO.File]::ReadAllText((Get-RepositoryPath $stderrRelative), $utf8)
if ($stdout -notmatch 'BUILD SUCCESSFUL' -or $stderr -match 'COMPILE RESULT:FAIL|ArkTS Compiler Error') { throw 'ISSUE241_BUILD_BLOCKED: build success contract failed.' }
$hapPath = Get-RepositoryPath $hapRelative
if (-not (Test-Path -LiteralPath $hapPath -PathType Leaf)) { throw 'ISSUE241_BUILD_BLOCKED: signed HAP is missing.' }
$hash = (Get-FileHash -LiteralPath $hapPath -Algorithm SHA256).Hash.ToUpperInvariant()
$buildEvidence = [ordered]@{
  schemaVersion = 1
  kind = 'legado_issue_241_arkts_inline_object_types_build_post_fix'
  status = 'passed_static_only'
  issueId = $issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  build = [ordered]@{
    task = 'assembleApp'
    product = 'default'
    buildMode = 'debug'
    stdoutPath = $stdoutRelative.Replace('\', '/')
    stderrPath = $stderrRelative.Replace('\', '/')
    successMarker = 'BUILD SUCCESSFUL'
    arktsCompileFailurePresent = $false
  }
  signedHap = [ordered]@{ path = $hapRelative; sha256 = $hash; bytes = (Get-Item -LiteralPath $hapPath).Length }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  nextGate = 'install-signed-hap-and-device-cold-start-smoke'
}
$postFixPath = Join-Path $EvidenceDirectory 'issue-241-build-post-fix.json'
Write-AtomicJson $postFixPath $buildEvidence

$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId }) | Select-Object -First 1
if ($null -eq $issue) { throw 'ISSUE241_BUILD_BLOCKED: issue missing from state.' }
Set-PropertyValue $issue 'status' 'verifying'
Set-PropertyValue $issue 'summary' '命名结果合同修复后，JDK 21 Hvigor assembleApp debug 构建通过，生成 signed HAP；仍待安装后的真机冷启动、数据库迁移和书源管理 smoke。'
Set-PropertyValue $issue 'evidencePaths' (@($issue.evidencePaths) + @($postFixPath, $hapRelative))
Set-PropertyValue $issue 'lastUpdatedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue $state.governance 'activeIssueId' $issueId
Set-PropertyValue $state.governance 'status' 'running'
Set-PropertyValue $state.governance 'currentSourceClosureBoundary' $issueId
Set-PropertyValue $state.governance 'semanticMatchAllowed' $false
Set-PropertyValue $state 'updatedAt' ([DateTimeOffset]::UtcNow.ToString('o'))

$objective.targetRevision = '2026-08-09-r4-issue241-build-passed-device-pending'
Set-PropertyValue $objective 'lastReviewedAt' ([DateTimeOffset]::UtcNow.ToString('o'))
Set-PropertyValue $objective 'nextAction' '安装最新 signed HAP，完成真机冷启动、迁移和书源管理 smoke；设备证据通过后再关闭 241。'
Set-PropertyValue $objective.continuationTarget 'activeBoundary' "$issueId 保持 verifying：构建已通过，真机门禁待执行。"
Set-PropertyValue $objective.continuationTarget 'nextTransition' '安装 signed HAP 并执行冷启动 smoke；记录设备日志后决定 241 是否关闭。'
Set-PropertyValue $objective.continuationTarget.queueAudit 'status' 'r4_build_passed_device_pending'
Set-PropertyValue $objective.continuationTarget.queueAudit 'currentAnchor' $issueId
Set-PropertyValue $objective.continuationTarget.queueAudit 'candidateStatus' 'build_passed'
Set-PropertyValue $objective.continuationTarget.queueAudit 'candidateCurrentHeadAuditEvidencePath' $postFixPath

Import-Module -Name (Get-RepositoryPath 'tools/legado-compat/LegadoFullSourceState.psm1') -Force
Sync-LegadoStateDerivedFields -State $state
Write-LegadoStateCheckpoint -Path (Get-RepositoryPath $statePath) -State $state -Depth 80
Write-AtomicJson $objectivePath $objective
& pwsh -NoLogo -NoProfile -NonInteractive -File (Get-RepositoryPath 'tools/legado-compat/Invoke-LegadoCompatibility.ps1') -RefreshDocumentsOnly | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Issue 241 build document refresh failed.' }
$buildEvidence | ConvertTo-Json -Depth 20
