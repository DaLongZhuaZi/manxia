[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$DeviceSn = '2UCUT24724009680',
  [string]$EvidencePath = 'tools/legado-compat/evidence/r3-source-closure-device-smoke-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$hdc = 'F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe'
$hapRelative = 'entry/build/default/outputs/default/entry-default-signed.hap'
$buildEvidenceDirectory = 'tools/legado-compat/evidence/r3-source-closure-build-20260809'
$sourceCount = 458
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)

function Get-RepoPath([string]$RelativePath) { return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepoPath $RelativePath
  [System.IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 30), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

if (-not (Test-Path -LiteralPath $hdc -PathType Leaf)) { throw "HDC_MISSING:$hdc" }
$hapPath = Get-RepoPath $hapRelative
if (-not (Test-Path -LiteralPath $hapPath -PathType Leaf)) { throw "SIGNED_HAP_MISSING:$hapRelative" }
$targets = @(& $hdc list targets 2>&1 | ForEach-Object { ([string]$_).Trim() } | Where-Object { $_.Length -gt 0 })
if ($targets -notcontains $DeviceSn) { throw "DEVICE_NOT_CONNECTED:$DeviceSn" }
$installOutput = (& $hdc -t $DeviceSn install -r $hapPath 2>&1 | Out-String).Trim()
$installExit = $LASTEXITCODE
$startOutput = (& $hdc -t $DeviceSn shell aa start -a EntryAbility -b com.dlzz.manxia -m entry 2>&1 | Out-String).Trim()
$startExit = $LASTEXITCODE
Start-Sleep -Seconds 4
$pidOutput = (& $hdc -t $DeviceSn shell pidof com.dlzz.manxia 2>&1 | Out-String).Trim()
$pidExit = $LASTEXITCODE
$hapHash = (Get-FileHash -LiteralPath $hapPath -Algorithm SHA256).Hash.ToUpperInvariant()
$stdoutHash = (Get-FileHash -LiteralPath (Get-RepoPath (Join-Path $buildEvidenceDirectory 'build.stdout.log')) -Algorithm SHA256).Hash.ToUpperInvariant()
$stderrHash = (Get-FileHash -LiteralPath (Get-RepoPath (Join-Path $buildEvidenceDirectory 'build.stderr.log')) -Algorithm SHA256).Hash.ToUpperInvariant()
$status = if ($installExit -eq 0 -and $startExit -eq 0 -and $pidExit -eq 0 -and $pidOutput.Length -gt 0) { 'passed' } else { 'failed' }
$evidence = [ordered]@{
  schemaVersion = 1
  kind = 'legado_v2_source_closure_build_device_smoke'
  status = $status
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  device = [ordered]@{ deviceSn = $DeviceSn; targets = $targets; package = 'com.dlzz.manxia'; ability = 'EntryAbility' }
  build = [ordered]@{ task = 'assembleApp'; buildMode = 'debug'; signedHap = $hapRelative; signedHapSha256 = $hapHash; stdoutSha256 = $stdoutHash; stderrSha256 = $stderrHash }
  install = [ordered]@{ exitCode = $installExit; outputClass = if ($installOutput -match 'successfully') { 'success' } else { 'unclassified' } }
  coldStart = [ordered]@{ exitCode = $startExit; outputClass = if ($startOutput -match 'successfully') { 'success' } else { 'unclassified' } }
  process = [ordered]@{ exitCode = $pidExit; pidPresent = $pidOutput.Length -gt 0 }
  semanticMatchAllowed = $false
  statement = 'Fresh debug build installed and launched on the connected device; this smoke proves only build/install/cold-start health and does not qualify any book source.'
  runtimeRegression = 'not_run'
  fullSourceHarness = 'not_run'
  legadoDifferential = 'not_run'
}
Write-AtomicJson $EvidencePath $evidence
if ($status -ne 'passed') { throw "DEVICE_SMOKE_FAILED:$($evidence | ConvertTo-Json -Compress)" }
Write-Output ($evidence | ConvertTo-Json -Depth 20 -Compress)
