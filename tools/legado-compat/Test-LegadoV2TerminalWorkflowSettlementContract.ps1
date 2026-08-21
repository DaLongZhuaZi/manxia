[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepoRoot)) {
  $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}
if ([string]::IsNullOrWhiteSpace($ResultPath)) {
  $ResultPath = Join-Path $RepoRoot 'tools\legado-compat\evidence\v2-terminal-workflow-settlement-contract.json'
}

$fixturePath = Join-Path $RepoRoot 'tools\legado-compat\fixtures\hypium-terminal-workflow-settlement.json'
$modulePath = Join-Path $RepoRoot 'tools\legado-compat\LegadoHypiumWorkflowSettlement.psm1'
$runnerPath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1'
$assertionCount = 0
$scenarioResults = [System.Collections.Generic.List[object]]::new()

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "V2 terminal workflow settlement contract failed: $Message"
  }
  $script:assertionCount++
}

function Write-ContractResult {
  param([object]$Value)
  $directory = Split-Path -Parent $ResultPath
  if (-not (Test-Path -LiteralPath $directory)) {
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
    if (Test-Path -LiteralPath $temporaryPath) {
      [System.IO.File]::Delete($temporaryPath)
    }
  }
}

try {
  Assert-Contract (Test-Path -LiteralPath $fixturePath -PathType Leaf) 'fixture must exist'
  Assert-Contract (Test-Path -LiteralPath $modulePath -PathType Leaf) 'workflow settlement module must exist'
  Assert-Contract (Test-Path -LiteralPath $runnerPath -PathType Leaf) 'full-source runner must exist'

  $fixtureText = [System.IO.File]::ReadAllText($fixturePath, [System.Text.UTF8Encoding]::new($false, $true))
  $fixture = $fixtureText | ConvertFrom-Json
  $runnerText = [System.IO.File]::ReadAllText($runnerPath, [System.Text.UTF8Encoding]::new($false, $true))
  Assert-Contract ($runnerText.Contains("Import-Module -Name `$workflowSettlementModulePath")) 'runner must import the tested settlement module'
  Assert-Contract ($runnerText.Contains('Get-LegadoHypiumExploreDependencySettlements')) 'runner must consume the tested settlement decision'
  Import-Module $modulePath -Force
  $command = Get-Command -Name 'Get-LegadoHypiumExploreDependencySettlements' -ErrorAction SilentlyContinue
  Assert-Contract ($null -ne $command) 'settlement function must be exported'

  foreach ($scenario in @($fixture.scenarios)) {
    $initialStatus = [string]$scenario.initialStatus
    $record = [pscustomobject][ordered]@{
      workflows = [pscustomobject][ordered]@{
        search = [pscustomobject][ordered]@{ status = 'policy_blocked' }
        explore = [pscustomobject][ordered]@{ status = 'failed' }
        bookInfo = [pscustomobject][ordered]@{ status = $initialStatus }
        toc = [pscustomobject][ordered]@{ status = $initialStatus }
        content = [pscustomobject][ordered]@{ status = $initialStatus }
        file = [pscustomobject][ordered]@{ status = 'policy_blocked' }
        review = [pscustomobject][ordered]@{ status = 'policy_blocked' }
      }
    }
    $settlements = @(
      Get-LegadoHypiumExploreDependencySettlements `
        -Record $record `
        -TerminalStatus ([string]$fixture.terminalStatus) `
        -TerminalOutcome ([string]$fixture.terminalOutcome)
    )
    Assert-Contract ($settlements.Count -eq @($fixture.dependentWorkflows).Count) "scenario $($scenario.name) must settle every dependent workflow"
    foreach ($name in @($fixture.dependentWorkflows)) {
      $matches = @($settlements | Where-Object { [string]$_.name -eq [string]$name })
      Assert-Contract ($matches.Count -eq 1) "scenario $($scenario.name) must settle $name exactly once"
      Assert-Contract ([string]$matches[0].status -eq [string]$fixture.terminalStatus) "scenario $($scenario.name) must make $name terminal"
      Assert-Contract ([string]$matches[0].outcome -eq [string]$fixture.terminalOutcome) "scenario $($scenario.name) must preserve the dependency outcome"
    }
    [void]$scenarioResults.Add([pscustomobject][ordered]@{
      name = [string]$scenario.name
      initialStatus = $initialStatus
      settlementCount = $settlements.Count
      status = 'passed'
    })
  }

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'passed'
    contract = [string]$fixture.contract
    assertions = $assertionCount
    scenarios = $scenarioResults.ToArray()
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
  Write-ContractResult -Value $result
  $result | ConvertTo-Json -Depth 10
} catch {
  $message = $_.Exception.Message
  $digestBytes = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($message))
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    status = 'failed'
    contract = 'full_workflow_no_search_explore_failure_terminal_settlement'
    assertions = $assertionCount
    scenarios = $scenarioResults.ToArray()
    errorCategory = 'terminal_workflow_settlement_contract_failed'
    errorDigest = [Convert]::ToHexString($digestBytes)
    message = $message
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  }
  Write-ContractResult -Value $result
  throw
}
