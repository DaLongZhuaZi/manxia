[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($RepositoryRoot.Length -eq 0) {
  $RepositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}

$fixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\v2-governance-task-mirror.json'
$statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
$implementationPath = Join-Path $RepositoryRoot 'tools\legado-compat\Invoke-LegadoCompatibility.ps1'
$ledgerPath = Join-Path $RepositoryRoot 'tools\legado-compat\LEGADO_V2_GOVERNANCE_TASKS.md'

function Read-Utf8Json {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Required contract input is missing: $Path"
  }
  $text = [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
  return $text | ConvertFrom-Json
}

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "CONTRACT_FAILED:$Message"
  }
}

function Get-Value {
  param([object]$Object, [string]$Name, [object]$DefaultValue = '')
  if ($null -eq $Object) {
    return $DefaultValue
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) {
    return $DefaultValue
  }
  return $property.Value
}

$fixture = Read-Utf8Json -Path $fixturePath
$state = Read-Utf8Json -Path $statePath
$implementation = [System.IO.File]::ReadAllText($implementationPath, [System.Text.UTF8Encoding]::new($false))
$ledger = [System.IO.File]::ReadAllText($ledgerPath, [System.Text.UTF8Encoding]::new($false))
$startMarker = [string]$fixture.startMarker
$endMarker = [string]$fixture.endMarker
$assertions = 0

Assert-Contract ($implementation.Contains('$script:V2GovernanceTaskListPath')) 'implementation must declare the V2 governance ledger path'; $assertions++
Assert-Contract ($implementation.Contains('function Update-V2GovernanceTaskMirror')) 'implementation must expose the marker-driven mirror function'; $assertions++
Assert-Contract ($implementation.Contains('Update-V2GovernanceTaskMirror')) 'document refresh must invoke the V2 governance mirror'; $assertions++
Assert-Contract ($implementation.Contains('Write-Utf8Atomic -Path $script:V2GovernanceTaskListPath')) 'mirror must use the shared atomic UTF-8 writer'; $assertions++
Assert-Contract ($implementation.Contains('[System.Text.UTF8Encoding]::new($false)')) 'mirror reads must explicitly use UTF-8 without BOM'; $assertions++
Assert-Contract ($implementation.Contains('throw "V2 governance task ledger is missing')) 'missing ledger must fail the refresh'; $assertions++
Assert-Contract ($implementation.Contains('throw "Full-source machine state cannot be parsed')) 'invalid state must fail the refresh'; $assertions++
Assert-Contract ($implementation.Contains('if ($RefreshDocumentsOnly)') -and $implementation.Contains('Save-CompatibilityState')) 'refresh-only mode must traverse the same document save path'; $assertions++

$startCount = ([regex]::Matches($ledger, [regex]::Escape($startMarker))).Count
$endCount = ([regex]::Matches($ledger, [regex]::Escape($endMarker))).Count
Assert-Contract ($startCount -eq 1 -and $endCount -eq 1) 'ledger must contain exactly one generated mirror block'; $assertions++
$startIndex = $ledger.IndexOf($startMarker, [System.StringComparison]::Ordinal)
$endIndex = $ledger.IndexOf($endMarker, [System.StringComparison]::Ordinal)
Assert-Contract ($startIndex -ge 0 -and $endIndex -gt $startIndex) 'mirror markers must be ordered'; $assertions++
$mirror = $ledger.Substring($startIndex, $endIndex + $endMarker.Length - $startIndex)
$outside = $ledger.Substring(0, $startIndex) + $ledger.Substring($endIndex + $endMarker.Length)

$tasks = @($state.governance.tasks | Where-Object { $null -ne $_ })
$issues = @($state.governance.issues | Where-Object { $null -ne $_ })
$taskRows = @([regex]::Matches($mirror, '(?m)^\| task \| '))
$issueRows = @([regex]::Matches($mirror, '(?m)^\| issue \| '))
Assert-Contract ($taskRows.Count -eq $tasks.Count) 'mirror task row count must match machine state'; $assertions++
Assert-Contract ($issueRows.Count -eq $issues.Count) 'mirror issue row count must match machine state'; $assertions++

foreach ($task in $tasks) {
  $taskIdValue = [string](Get-Value -Object $task -Name 'id')
  $taskId = [regex]::Escape($taskIdValue)
  $status = [regex]::Escape([string](Get-Value -Object $task -Name 'status' -DefaultValue 'planned'))
  $attempts = [regex]::Escape([string](Get-Value -Object $task -Name 'attempts' -DefaultValue 0))
  Assert-Contract ([regex]::IsMatch($mirror, "(?m)^\| task \| $taskId \| $status \| - \| $attempts \|")) "task mirror mismatch: $taskIdValue"; $assertions++
}
foreach ($issue in $issues) {
  $issueIdValue = [string](Get-Value -Object $issue -Name 'id')
  $issueId = [regex]::Escape($issueIdValue)
  $status = [regex]::Escape([string](Get-Value -Object $issue -Name 'status' -DefaultValue 'planned'))
  $severity = [regex]::Escape([string](Get-Value -Object $issue -Name 'severity'))
  $attempts = [regex]::Escape([string](Get-Value -Object $issue -Name 'attempts' -DefaultValue 0))
  $taskId = [regex]::Escape([string](Get-Value -Object $issue -Name 'taskId'))
  Assert-Contract ([regex]::IsMatch($mirror, "(?m)^\| issue \| $issueId \| $status \| $severity \| $attempts \| $taskId \|")) "issue mirror mismatch: $issueIdValue"; $assertions++
}

$historicalToken = [string]$fixture.historicalTokenOutsideMirror
Assert-Contract ($outside.Contains($historicalToken)) 'historical task evidence outside generated mirror must remain untouched'; $assertions++
$ledgerBytes = [System.IO.File]::ReadAllBytes($ledgerPath)
$hasUtf8Bom = $ledgerBytes.Length -ge 3 -and $ledgerBytes[0] -eq 0xEF -and $ledgerBytes[1] -eq 0xBB -and $ledgerBytes[2] -eq 0xBF
Assert-Contract (-not $hasUtf8Bom) 'ledger must be UTF-8 without BOM'; $assertions++

[pscustomobject][ordered]@{
  schemaVersion = 1
  issueId = [string]$fixture.issueId
  status = 'passed'
  assertions = $assertions
  taskRows = $taskRows.Count
  issueRows = $issueRows.Count
  sourceOfTruth = [string]$fixture.sourceOfTruth
  mirrorPath = [string]$fixture.mirrorPath
  semanticMatchAllowed = [bool]$fixture.semanticMatchAllowed
  verificationPolicy = [string]$fixture.verificationPolicy
} | ConvertTo-Json -Depth 8
