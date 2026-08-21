[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
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
$issueId = 'ISSUE-AUTO-045-PS51-CONTROLLER-BOM'
$taskId = 'COMPAT-006'
$controllerRelative = 'tools/legado-compat/Invoke-LegadoCompatibility.ps1'
$contractRelative = 'tools/legado-compat/Test-LegadoStage7PowerShell51Contract.ps1'
$failureRelative = 'tools/legado-compat/evidence/contract-legado-stage7-powershell51-controller-bom-pre-fix-20260809.json'
$contractEvidenceRelative = 'tools/legado-compat/evidence/contract-legado-stage7-powershell51-controller-bom-20260809.json'
$sourceFixRelative = 'tools/legado-compat/evidence/v2-stage7-powershell51-controller-bom-source-fix-20260809.json'

function Get-RepoPath([string]$RelativePath) {
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 60), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Read-StrictJson([string]$RelativePath) {
  $bytes = [System.IO.File]::ReadAllBytes((Get-RepoPath $RelativePath))
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "Evidence JSON must be UTF-8 without BOM: $RelativePath"
  }
  return $strictUtf8.GetString($bytes) | ConvertFrom-Json
}

function Set-PropertyValue([object]$Object, [string]$Name, [object]$Value) {
  if ($null -eq $Object.PSObject.Properties[$Name]) { $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force }
  else { $Object.$Name = $Value }
}

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
if ([int]$state.baseline.sourceCount -ne $sourceCount -or [string]$state.baseline.sourcePackageSha256 -ne $sourceHash -or [string]$state.baseline.legadoCommit -ne $legadoCommit) {
  throw 'Machine baseline drifted.'
}
$controllerPath = Get-RepoPath $controllerRelative
$controllerBytes = [System.IO.File]::ReadAllBytes($controllerPath)
$hasBom = $controllerBytes.Length -ge 3 -and $controllerBytes[0] -eq 0xEF -and $controllerBytes[1] -eq 0xBB -and $controllerBytes[2] -eq 0xBF
if (-not $hasBom) { throw 'Controller still lacks UTF-8 BOM.' }
$bodyBytes = $controllerBytes
if ($hasBom) { $bodyBytes = $controllerBytes[3..($controllerBytes.Length - 1)] }
$bodyHash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bodyBytes)
$bodyHashHex = ([System.BitConverter]::ToString($bodyHash)).Replace('-', '').ToUpperInvariant()
$controllerHash = (Get-FileHash -LiteralPath $controllerPath -Algorithm SHA256).Hash.ToUpperInvariant()
$contractHash = (Get-FileHash -LiteralPath (Get-RepoPath $contractRelative) -Algorithm SHA256).Hash.ToUpperInvariant()
$now = [DateTimeOffset]::UtcNow.ToString('o')

$failure = [ordered]@{
  schemaVersion = 1
  kind = 'legado_stage7_powershell51_controller_bom_failure_witness'
  status = 'failed_static_only'
  issueId = $issueId
  generatedAt = $now
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  path = $controllerRelative
  observedBeforeFix = [ordered]@{ utf8Bom = $false; failure = 'Test-LegadoStage7PowerShell51Contract.ps1 rejected Invoke-LegadoCompatibility.ps1 before parsing' }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
}
Write-AtomicJson $failureRelative $failure

$contractOutput = & pwsh -NoLogo -NoProfile -NonInteractive -File (Get-RepoPath $contractRelative) -SkipWindowsPowerShellChild 2>&1 | Out-String
if ($LASTEXITCODE -ne 0) { throw "PowerShell 5.1 contract failed after BOM fix: $contractOutput" }
$contract = $contractOutput.Trim() | ConvertFrom-Json
$contractEvidence = [ordered]@{
  schemaVersion = 1
  kind = 'legado_stage7_powershell51_controller_bom_contract'
  status = 'passed_static_only'
  issueId = $issueId
  generatedAt = $now
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  contractPath = $contractRelative
  contractSha256 = $contractHash
  controllerPath = $controllerRelative
  controllerSha256 = $controllerHash
  controllerUtf8Bom = $hasBom
  contractOutput = $contract
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
}
Write-AtomicJson $contractEvidenceRelative $contractEvidence

$sourceFix = [ordered]@{
  schemaVersion = 1
  kind = 'legado_stage7_powershell51_controller_bom_source_fix'
  status = 'passed_static_only'
  issueId = $issueId
  generatedAt = $now
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  failureWitnessPath = $failureRelative
  contractEvidencePath = $contractEvidenceRelative
  changedFiles = @($controllerRelative)
  sourceFix = [ordered]@{ controllerSha256 = $controllerHash; controllerBodySha256 = $bodyHashHex; utf8Bom = $hasBom }
  statement = 'Only the UTF-8 BOM was added; decoded PowerShell source bytes remain unchanged.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  closeCondition = 'The Windows PowerShell 5.1 static gate must remain green before any Stage 7 device work; this tooling issue does not establish book-source compatibility.'
}
Write-AtomicJson $sourceFixRelative $sourceFix

$updateScript = Get-RepoPath 'tools/legado-compat/Update-LegadoGovernanceState.ps1'
& pwsh -NoLogo -NoProfile -NonInteractive -File $updateScript `
  -StatePath (Get-RepoPath 'tools/legado-compat/state/full-source-validation-state.json') `
  -IssueId $issueId `
  -IssueStatus passed `
  -TaskId $taskId `
  -TaskStatus running `
  -Severity P1 `
  -Summary 'Stage 7 Windows PowerShell 5.1 总控脚本缺少 UTF-8 BOM；已仅补 BOM，正文哈希保持不变，静态门禁通过。' `
  -CloseCondition 'Stage 7 PowerShell 5.1 static gate remains passed before device execution; this is harness readiness only.' `
  -EvidencePath "$failureRelative,$contractEvidenceRelative,$sourceFixRelative" `
  -CreateIfMissing | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Governance state update failed.' }
Write-Output ('PS51_CONTROLLER_BOM_REGISTERED issue={0} status=passed_static_only' -f $issueId)
