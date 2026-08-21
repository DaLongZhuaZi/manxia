[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$ExpectedEvidencePath = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if ([string]::IsNullOrWhiteSpace($ExpectedEvidencePath)) {
  $ExpectedEvidencePath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-image-012-source-fix-20260808.json'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-image-012-current-head-drift-audit-20260808\current-head-hash-audit.json'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:assertions = 0

function Assert-Audit {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "Legado IMAGE 012 current-head audit failed: $Message"
  }
  $script:assertions++
}

function Read-StrictText {
  param([string]$Path)
  Assert-Audit (Test-Path -LiteralPath $Path -PathType Leaf) "missing file: $Path"
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  Assert-Audit (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) "UTF-8 BOM is not allowed: $Path"
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([string]$Path)
  try {
    return (Read-StrictText -Path $Path) | ConvertFrom-Json
  } catch {
    throw "invalid JSON: $Path; $($_.Exception.Message)"
  }
}

function Get-RelativePath {
  param([string]$Path)
  return [System.IO.Path]::GetRelativePath($RepositoryRoot, $Path).Replace('\', '/')
}

function Get-Sha256 {
  param([string]$Path)
  Assert-Audit (Test-Path -LiteralPath $Path -PathType Leaf) "missing implementation file: $Path"
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Write-AtomicJson {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) {
    [void][System.IO.Directory]::CreateDirectory($directory)
  }
  $temporaryPath = "$Path.tmp-$PID"
  [System.IO.File]::WriteAllText($temporaryPath, [string]($Value | ConvertTo-Json -Depth 16), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

$result = $null
try {
  $expected = Read-StrictJson -Path $ExpectedEvidencePath
  Assert-Audit ([string]$expected.issueId -eq 'ISSUE-COMPAT-012') 'expected evidence must belong to ISSUE-COMPAT-012.'
  Assert-Audit ([int]$expected.sourceCount -eq 458) 'expected evidence must bind sourceCount=458.'
  Assert-Audit ([string]$expected.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'expected evidence source hash is not the frozen baseline.'
  Assert-Audit ([string]$expected.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'expected evidence Legado commit is not the frozen baseline.'

  $sourceHashes = $expected.PSObject.Properties['sourceHashes']
  Assert-Audit ($null -ne $sourceHashes -and $null -ne $sourceHashes.Value) 'expected evidence has no sourceHashes map.'
  $currentHashes = [ordered]@{}
  $mismatches = New-Object 'System.Collections.Generic.List[object]'
  $checkedPaths = New-Object 'System.Collections.Generic.List[string]'
  foreach ($property in $sourceHashes.Value.PSObject.Properties) {
    $relativePath = [string]$property.Name
    $implementationPath = Join-Path $RepositoryRoot ($relativePath.Replace('/', '\'))
    $expectedHash = ([string]$property.Value).ToUpperInvariant()
    $currentHash = Get-Sha256 -Path $implementationPath
    $currentHashes[$relativePath] = $currentHash
    [void]$checkedPaths.Add($relativePath)
    if ($currentHash -ne $expectedHash) {
      [void]$mismatches.Add([pscustomobject][ordered]@{
        path = $relativePath
        expectedSha256 = $expectedHash
        currentHeadSha256 = $currentHash
        classification = 'current_head_drift_requires_attribution'
      })
    }
  }

  $status = if ($mismatches.Count -eq 0) { 'passed' } else { 'failed' }
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_image_012_current_head_hash_audit'
    issueId = 'ISSUE-COMPAT-012'
    status = $status
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    baseline = [pscustomobject][ordered]@{
      sourceCount = [int]$expected.sourceCount
      sourcePackageSha256 = [string]$expected.sourcePackageSha256
      legadoCommit = [string]$expected.legadoCommit
    }
    expectedEvidence = Get-RelativePath -Path (Resolve-Path -LiteralPath $ExpectedEvidencePath).Path
    checkedImplementationPaths = $checkedPaths.ToArray()
    expectedSourceHashes = $sourceHashes.Value
    currentHeadSourceHashes = $currentHashes
    mismatches = $mismatches.ToArray()
    assertions = $script:assertions
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'static_current_head_audit_only;runtime_regression_deferred_to_R4'
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_image_012_current_head_hash_audit'
    issueId = 'ISSUE-COMPAT-012'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'static_current_head_audit_only;runtime_regression_deferred_to_R4'
  }
}

Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Compress
if ([string]$result.status -ne 'passed') { exit 1 }
