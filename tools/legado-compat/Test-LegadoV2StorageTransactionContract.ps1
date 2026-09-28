[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}

function Read-Utf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)

  $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
  return [System.IO.File]::ReadAllText($Path, $utf8)
}

function Assert-Contract {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Message
  )

  if (-not $Condition) {
    throw "V2 storage transaction contract failed: $Message"
  }
}

function Assert-Contains {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$Token,
    [Parameter(Mandatory = $true)][string]$Message
  )

  Assert-Contract ($Text.Contains($Token)) $Message
}

function Assert-Ordered {
  param(
    [Parameter(Mandatory = $true)][string]$Text,
    [Parameter(Mandatory = $true)][string]$First,
    [Parameter(Mandatory = $true)][string]$Second,
    [Parameter(Mandatory = $true)][string]$Message
  )

  $firstIndex = $Text.IndexOf($First)
  $secondIndex = $Text.IndexOf($Second)
  Assert-Contract (($firstIndex -ge 0) -and ($secondIndex -ge 0) -and ($firstIndex -lt $secondIndex)) $Message
}

$dataManagerPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\NovelDataManager.ets'
Assert-Contract (Test-Path -LiteralPath $dataManagerPath -PathType Leaf) 'NovelDataManager must exist.'
$dataManager = Read-Utf8Text -Path $dataManagerPath

Assert-Contains $dataManager 'async saveSourceWithCompatibilityRecord(' 'lossless source persistence boundary must exist.'
Assert-Contains $dataManager 'store.beginTransaction();' 'real-device-compatible transaction must start before either write.'
Assert-Contains $dataManager 'await store.executeSql(sourceSql, [' 'legacy normalized row must participate in the transaction.'
Assert-Contains $dataManager 'await store.executeSql(compatibilitySql, [' 'raw JSON compatibility row must participate in the transaction.'
Assert-Contains $dataManager 'store.commit();' 'both rows must commit together.'
Assert-Contains $dataManager 'store.rollBack();' 'failed writes must rollback together.'
Assert-Ordered $dataManager 'store.beginTransaction();' 'await store.executeSql(sourceSql, [' 'transaction must start before source write.'
Assert-Ordered $dataManager 'await store.executeSql(compatibilitySql, [' 'store.commit();' 'compatibility record must be written before commit.'
Assert-Contract (-not $dataManager.Contains('beginTrans()')) 'transaction-id beginTrans is unsupported on the verified physical device.'
Assert-Contract (-not $dataManager.Contains('transactionId')) 'transaction-id APIs must not remain in the V2 write boundary.'
Assert-Contract (-not $dataManager.Contains('store.execute(compatibilitySql')) 'transaction-id execute overload must not remain in the V2 write boundary.'

[PSCustomObject]@{
  status = 'passed'
  atomicWriteBoundary = $true
  physicalDeviceCompatibleTransactionApi = $true
  deprecatedTransactionIdApiRemoved = $true
} | ConvertTo-Json -Compress
