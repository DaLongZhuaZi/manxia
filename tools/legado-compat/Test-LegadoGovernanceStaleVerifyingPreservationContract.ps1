[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-governance-stale-verifying-preservation.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-governance-stale-verifying-preservation-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$sourceCount = 458
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$assertions = 0

function Get-RepoPath([string]$RelativePath) {
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText([string]$Path) {
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $utf8Strict.GetString($bytes)
}

function Assert-Contract([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "Governance stale-verifying contract failed: $Message" }
  $script:assertions++
}

function Write-AtomicJson([string]$Path, [object]$Value) {
  $directory = Split-Path -Parent $Path
  [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  $temporary = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 20), $utf8NoBom)
    Move-Item -LiteralPath $temporary -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

$result = $null
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("manxia-legado-governance-" + [Guid]::NewGuid().ToString('N'))
try {
  $fixture = Read-StrictText (Get-RepoPath $FixturePath) | ConvertFrom-Json
  $modulePath = Get-RepoPath 'tools/legado-compat/LegadoFullSourceState.psm1'
  $moduleText = Read-StrictText $modulePath
  $resetStart = $moduleText.IndexOf('function Reset-LegadoStaleStatus', [System.StringComparison]::Ordinal)
  Assert-Contract ($resetStart -ge 0) 'Reset-LegadoStaleStatus must remain discoverable.'
  $resetEnd = $moduleText.IndexOf('function Recover-LegadoSupersededCompileBlock', $resetStart, [System.StringComparison]::Ordinal)
  Assert-Contract ($resetEnd -gt $resetStart) 'Reset-LegadoStaleStatus boundary must remain stable.'
  $resetSegment = $moduleText.Substring($resetStart, $resetEnd - $resetStart)
  Assert-Contract ($resetSegment.Contains("-ne 'running'")) 'Only running status may be reset after interruption.'
  Assert-Contract (-not $resetSegment.Contains("@('running', 'verifying')")) 'verifying must not be treated as stale execution.'
  $candidateGatePath = Get-RepoPath 'tools/legado-compat/Test-LegadoCurrentStaticSourceCandidateGate.ps1'
  $candidateGateText = Read-StrictText $candidateGatePath
  Assert-Contract ($candidateGateText.Contains('STALE_VERIFYING_STATUS_RECOVERY_REQUIRED')) 'candidate gate must hard-block stale verifying recovery drift.'
  Assert-Contract ($candidateGateText.Contains('priorStatus') -and $candidateGateText.Contains('stale_execution_recovered')) 'candidate gate must inspect the persisted recovery witness.'
  $moduleHash = (Get-FileHash -LiteralPath $modulePath -Algorithm SHA256).Hash.ToUpperInvariant()
  $candidateGateHash = (Get-FileHash -LiteralPath $candidateGatePath -Algorithm SHA256).Hash.ToUpperInvariant()

  [System.IO.Directory]::CreateDirectory($tempRoot) | Out-Null
  $packagePath = Join-Path $tempRoot 'package.json'
  $statePath = Join-Path $tempRoot 'state.json'
  $legacyPath = Join-Path $tempRoot 'legacy.json'
  $packageText = '[{"bookSourceName":"fixture","bookSourceUrl":"https://fixture.invalid","ruleSearch":{"bookList":".book","name":".name","bookUrl":".url"}}]'
  [System.IO.File]::WriteAllText($packagePath, $packageText, $utf8NoBom)
  $hashAlgorithm = [System.Security.Cryptography.SHA256]::Create()
  try { $packageHash = ([System.BitConverter]::ToString($hashAlgorithm.ComputeHash([System.IO.File]::ReadAllBytes($packagePath)))).Replace('-', '') } finally { $hashAlgorithm.Dispose() }
  $baseline = [pscustomobject][ordered]@{ sourcePackageSha256 = $packageHash; sourceCount = 1; legadoCommit = 'fixture' }
  $legacy = [pscustomobject][ordered]@{
    schemaVersion = 1
    baseline = $baseline
    status = 'planned'
    activeTaskId = ''
    tasks = @()
    issues = @(
      [pscustomobject][ordered]@{ id = 'ISSUE-FIXTURE-DURABLE'; status = [string]$fixture.statusTokens.durable; attempts = 2 },
      [pscustomobject][ordered]@{ id = 'ISSUE-FIXTURE-INTERRUPTED'; status = [string]$fixture.statusTokens.interrupted; attempts = 1 }
    )
  }
  [System.IO.File]::WriteAllText($legacyPath, ($legacy | ConvertTo-Json -Depth 12), $utf8NoBom)
  Import-Module -Name $modulePath -Force
  $state = Initialize-LegadoFullSourceState `
    -SourcePackagePath $packagePath `
    -StatePath $statePath `
    -LegacyGovernancePath $legacyPath `
    -ExpectedPackageSha256 $packageHash `
    -ExpectedSourceCount 1 `
    -LegadoCommit 'fixture' `
    -ExpectedLegadoCommit 'fixture'
  $durable = @($state.governance.issues | Where-Object { $_.id -eq 'ISSUE-FIXTURE-DURABLE' })[0]
  $interrupted = @($state.governance.issues | Where-Object { $_.id -eq 'ISSUE-FIXTURE-INTERRUPTED' })[0]
  Assert-Contract ([string]$durable.status -eq [string]$fixture.expected.durableStatusAfterRecovery) 'verifying governance issue must remain verifying.'
  Assert-Contract ($null -eq $durable.PSObject.Properties['lastRecovery']) 'durable verifying issue must not receive stale recovery metadata.'
  Assert-Contract ([string]$interrupted.status -eq [string]$fixture.expected.interruptedStatusAfterRecovery) 'running governance issue must become planned.'
  Assert-Contract ([string]$interrupted.lastRecovery.priorStatus -eq 'running') 'interrupted issue must retain its prior running status.'
  Assert-Contract ([int]$state.recovery.staleGovernanceCount -eq [int]$fixture.expected.staleGovernanceCount) 'only the interrupted governance issue may count as stale.'

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_governance_stale_verifying_preservation_contract'
    status = 'passed_static_and_deterministic'
    assertions = $assertions
    baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
    fixturePath = $FixturePath.Replace('\', '/')
    implementationPath = 'tools/legado-compat/LegadoFullSourceState.psm1'
    implementationSha256 = $moduleHash
    candidateGatePath = 'tools/legado-compat/Test-LegadoCurrentStaticSourceCandidateGate.ps1'
    candidateGateSha256 = $candidateGateHash
    restoredStatus = 'verifying'
    resetStatus = 'running_to_planned'
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    deviceRegression = 'not_run'
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_governance_stale_verifying_preservation_contract'
    status = 'failed'
    assertions = $assertions
    error = $_.Exception.Message
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
  }
} finally {
  if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
}

Write-AtomicJson (Get-RepoPath $ResultPath) $result
$result | ConvertTo-Json -Depth 20 -Compress
if ($result.status -ne 'passed_static_and_deterministic') { exit 1 }
