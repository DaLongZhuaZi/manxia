[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$PythonPath = '',
  [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$assertionCount = 0

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}
if ([string]::IsNullOrWhiteSpace($PythonPath)) {
  $PythonPath = Join-Path $RepoRoot '.venv\Scripts\python.exe'
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepoRoot 'tools\legado-compat\evidence\v2-image-explore-harness-contract.json'
}

$fixturePath = Join-Path $RepoRoot 'tools\legado-compat\fixtures\hypium-image-explore-routing.json'
$driverPath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoV2HypiumNavigation.py'
$runnerPath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1'

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "V2 IMAGE Explore Harness contract failed: $Message"
  }
  $script:assertionCount++
}

function Write-ContractResult {
  param([object]$Value)
  $directory = Split-Path -Parent $ResultPath
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [void][System.IO.Directory]::CreateDirectory($directory)
  }
  $temporaryPath = $ResultPath + '.tmp-' + [Guid]::NewGuid().ToString('N')
  try {
    [System.IO.File]::WriteAllText(
      $temporaryPath,
      [string]($Value | ConvertTo-Json -Depth 10),
      [System.Text.UTF8Encoding]::new($false)
    )
    [System.IO.File]::Move($temporaryPath, $ResultPath, $true)
  } finally {
    if ([System.IO.File]::Exists($temporaryPath)) {
      [System.IO.File]::Delete($temporaryPath)
    }
  }
}

try {
  Assert-Contract (Test-Path -LiteralPath $fixturePath -PathType Leaf) 'fixture must exist'
  Assert-Contract (Test-Path -LiteralPath $driverPath -PathType Leaf) 'Hypium driver must exist'
  Assert-Contract (Test-Path -LiteralPath $runnerPath -PathType Leaf) 'full-source runner must exist'
  Assert-Contract (Test-Path -LiteralPath $PythonPath -PathType Leaf) 'Python runtime must exist'

  $fixture = [System.IO.File]::ReadAllText($fixturePath, [System.Text.UTF8Encoding]::new($false, $true)) | ConvertFrom-Json
  $driverText = [System.IO.File]::ReadAllText($driverPath, [System.Text.UTF8Encoding]::new($false, $true))
  $runnerText = [System.IO.File]::ReadAllText($runnerPath, [System.Text.UTF8Encoding]::new($false, $true))
  $exploreRunnerStart = $runnerText.IndexOf('function Invoke-HypiumSourceExplore')
  $exploreRunnerEnd = $runnerText.IndexOf('function Get-HypiumSafeAdditionalAttempt', $exploreRunnerStart)
  Assert-Contract ($exploreRunnerStart -ge 0 -and $exploreRunnerEnd -gt $exploreRunnerStart) 'runner Explore function must remain inspectable'
  $exploreRunnerText = $runnerText.Substring($exploreRunnerStart, $exploreRunnerEnd - $exploreRunnerStart)
  Assert-Contract ([int]$fixture.sourceType -eq 2) 'fixture must target IMAGE source type 2'
  Assert-Contract ($exploreRunnerText.Contains("[int]`$Record.sourceType -eq 2") -and $exploreRunnerText.Contains("[void]`$argumentList.Add('--image-workflow')")) 'runner must forward IMAGE type into Explore read-path Driver arguments'
  Assert-Contract ($exploreRunnerText.Contains("PSObject.Properties['image_trace']") -and -not $exploreRunnerText.Contains('imageTrace = $null')) 'runner must retain IMAGE trace from Explore attempts'
  Assert-Contract ($driverText.Contains('image_workflow=args.image_workflow')) 'CLI dispatch must forward the IMAGE mode into Explore orchestration'
  Assert-Contract ($driverText.Contains('image_workflow=image_workflow')) 'Explore orchestration must forward IMAGE mode into the guarded read path'
  Assert-Contract (-not $driverText.Contains('image_workflow=False,\n            hdc_path=hdc_path')) 'Explore read path must not hard-code text mode'

  $selfTestOutput = @(& $PythonPath $driverPath --image-explore-contract-self-test 2>&1)
  Assert-Contract ($LASTEXITCODE -eq 0) 'Driver IMAGE Explore self-test must exit zero'
  $selfTest = ($selfTestOutput -join [Environment]::NewLine) | ConvertFrom-Json
  Assert-Contract ([string]$selfTest.status -eq 'passed') 'Driver IMAGE Explore self-test must pass'
  Assert-Contract ([string]$selfTest.contract -eq [string]$fixture.contract) 'Driver and fixture contract identities must match'
  Assert-Contract (-not @($selfTest.imageReaderRootIds).Contains([string]$fixture.rejectedReaderRootId)) 'IMAGE mode must reject the novel reader root'
  foreach ($readerRootId in @($fixture.acceptedReaderRootIds)) {
    Assert-Contract (@($selfTest.imageReaderRootIds).Contains([string]$readerRootId)) "IMAGE mode must accept $readerRootId"
  }
  Assert-Contract ([string]$selfTest.requiredTraceEvent -eq [string]$fixture.requiredTraceEvent) 'IMAGE mode must require a terminal pipeline trace event'

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'passed'
    contract = [string]$fixture.contract
    assertions = $assertionCount
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
  Write-ContractResult -Value $result
  $result | ConvertTo-Json -Depth 8
} catch {
  $message = $_.Exception.Message
  $digest = [Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($message)))
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'failed'
    contract = 'image_explore_routes_to_manga_reader_and_requires_pipeline_trace'
    assertions = $assertionCount
    errorCategory = 'image_explore_harness_contract_failed'
    errorDigest = $digest
    message = $message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
  Write-ContractResult -Value $result
  throw
}
