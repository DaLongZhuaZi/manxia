[CmdletBinding()]
param(
  [Alias('RepositoryRoot')]
  [string]$RepoRoot = '',
  [switch]$SkipWindowsPowerShellChild
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($RepoRoot.Length -eq 0) {
  $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

$flowPath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoV2RealDeviceFlow.ps1'
$controllerPath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoCompatibility.ps1'
$helperPath = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoNativeProcess.ps1'

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw "Stage 7 PowerShell 5.1 contract failed: $Message"
  }
}

function Read-Utf8Script {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path) "missing script: $Path"
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  Assert-Contract ($bytes.Length -ge 3) "empty script: $Path"
  Assert-Contract (
    $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
  ) "Windows PowerShell 5.1 requires a UTF-8 BOM: $Path"
  return [System.Text.UTF8Encoding]::new($true, $true).GetString($bytes)
}

function Get-ScriptAst {
  param([string]$Path)
  $tokens = $null
  $errors = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $Path,
    [ref]$tokens,
    [ref]$errors
  )
  Assert-Contract ($errors.Count -eq 0) "parser errors in $Path"
  return $ast
}

function Get-FunctionText {
  param(
    [System.Management.Automation.Language.ScriptBlockAst]$Ast,
    [string]$Name
  )
  $match = $Ast.Find(
    {
      param($node)
      return $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq $Name
    },
    $true
  )
  Assert-Contract ($null -ne $match) "missing function: $Name"
  return $match.Extent.Text
}

function Assert-Contains {
  param([string]$Text, [string]$Expected, [string]$Label)
  Assert-Contract (
    $Text.IndexOf($Expected, [System.StringComparison]::Ordinal) -ge 0
  ) "$Label missing marker: $Expected"
}

function Assert-NotContains {
  param([string]$Text, [string]$Forbidden, [string]$Label)
  Assert-Contract (
    $Text.IndexOf($Forbidden, [System.StringComparison]::Ordinal) -lt 0
  ) "$Label contains forbidden marker: $Forbidden"
}

$flowText = Read-Utf8Script -Path $flowPath
$controllerText = Read-Utf8Script -Path $controllerPath
$flowAst = Get-ScriptAst -Path $flowPath
$controllerAst = Get-ScriptAst -Path $controllerPath
$helperAst = Get-ScriptAst -Path $helperPath

$jsonArrayText = Get-FunctionText -Ast $flowAst -Name 'ConvertFrom-JsonArray'
$candidateText = Get-FunctionText -Ast $flowAst -Name 'Get-RealTextSourceCandidates'
$hdcText = Get-FunctionText -Ast $flowAst -Name 'Invoke-Hdc'
$nativeProcessText = Get-FunctionText -Ast $helperAst -Name 'Invoke-LegadoNativeProcess'
$stage7CallText = Get-FunctionText -Ast $controllerAst -Name 'Invoke-Stage7RealUserFlow'
$stage7WorkText = Get-FunctionText -Ast $controllerAst -Name 'Invoke-Stage7Work'

Assert-Contains $jsonArrayText 'ConvertFrom-Json -InputObject $Json' 'JSON array parser'
Assert-Contains $jsonArrayText '$trimmed.StartsWith(''['')' 'JSON array parser'
Assert-Contains $jsonArrayText '$trimmed.EndsWith('']'')' 'JSON array parser'
Assert-Contains $jsonArrayText '$parsed = ConvertFrom-Json -InputObject $Json' 'JSON array parser'
Assert-Contains $jsonArrayText '$null -ne $parsed' 'JSON array parser'
Assert-Contains $jsonArrayText '$parsed -is [System.Array]' 'JSON array parser'
Assert-Contains $candidateText '@(ConvertFrom-JsonArray -Json $raw' 'candidate parser'
Assert-NotContains $candidateText '$raw | ConvertFrom-Json' 'candidate parser'
Assert-Contains $candidateText 'Write-Host "STAGE7_CANDIDATE_SELECTION' 'candidate output isolation'

Assert-Contains $hdcText 'Invoke-LegadoNativeProcess' 'HDC wrapper'
Assert-Contains $hdcText '$result.timedOut' 'HDC wrapper'
Assert-Contains $hdcText '-TimeoutSeconds $TimeoutSeconds' 'HDC wrapper'
Assert-Contains $nativeProcessText 'ReadToEndAsync()' 'native process helper'
Assert-Contains $nativeProcessText 'Stop-LegadoNativeProcessTree' 'native process helper'
Assert-Contains $nativeProcessText "'timeout'" 'native process helper'
Assert-Contract (([regex]::Matches($flowText, '& \$HdcPath')).Count -eq 0) `
  'Stage 7 flow must not invoke HDC outside the bounded process helper'

Assert-Contains $stage7CallText 'Invoke-LegadoNativeProcess' 'Stage 7 call chain'
Assert-Contains $stage7CallText '-TimeoutSeconds 2700' 'Stage 7 call chain'
Assert-Contains $stage7CallText '$flowResult.timedOut' 'Stage 7 call chain'
Assert-Contains $stage7CallText '$flowResult.exitCode -ne 0' 'Stage 7 call chain'
Assert-Contains $stage7WorkText 'Test-LegadoStage7PowerShell51Contract.ps1' 'Stage 7 automatic gate'
Assert-Contains $stage7WorkText 'stage7-powershell51-contract.json' 'Stage 7 automatic gate'
Assert-Contains $stage7WorkText 'Windows PowerShell 5.1 自动化契约' 'Stage 7 automatic gate'
$powerShellGateIndex = $stage7WorkText.IndexOf(
  'Test-LegadoStage7PowerShell51Contract.ps1',
  [System.StringComparison]::Ordinal
)
$deviceGateIndex = $stage7WorkText.IndexOf(
  "Invoke-DeviceGate -StageKey 'stage7'",
  [System.StringComparison]::Ordinal
)
Assert-Contract ($powerShellGateIndex -ge 0 -and $powerShellGateIndex -lt $deviceGateIndex) `
  'Windows PowerShell 5.1 gate must fail fast before device work'

Invoke-Expression $jsonArrayText
$empty = @(ConvertFrom-JsonArray -Json '[]' -Label 'fixture')
$single = @(ConvertFrom-JsonArray -Json '[{"id":1}]' -Label 'fixture')
$multiple = @(ConvertFrom-JsonArray -Json '[{"id":1},{"id":2}]' -Label 'fixture')
Assert-Contract ($empty.Count -eq 0) 'empty top-level JSON array changed cardinality'
Assert-Contract ($single.Count -eq 1 -and [int]$single[0].id -eq 1) `
  'single-item top-level JSON array was unwrapped or rejected'
Assert-Contract ($multiple.Count -eq 2 -and [int]$multiple[1].id -eq 2) `
  'multi-item top-level JSON array changed cardinality'
$objectRejected = $false
try {
  [void](ConvertFrom-JsonArray -Json '{"id":1}' -Label 'fixture')
} catch {
  $objectRejected = $_.Exception.Message -match '顶层 JSON 数组'
}
Assert-Contract $objectRejected 'top-level JSON object was accepted as an array'

. $helperPath

$windowsPowerShell51Version = ''
if ($PSVersionTable.PSVersion.Major -eq 5) {
  $windowsPowerShell51Version = $PSVersionTable.PSVersion.ToString()
} elseif (-not $SkipWindowsPowerShellChild) {
  $windowsPowerShellPath = Join-Path $env:SystemRoot `
    'System32\WindowsPowerShell\v1.0\powershell.exe'
  Assert-Contract (Test-Path -LiteralPath $windowsPowerShellPath) `
    'Windows PowerShell 5.1 executable is missing'
  $windowsPowerShellRun = Invoke-LegadoNativeProcess `
    -FilePath $windowsPowerShellPath `
    -ArgumentList @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath, '-RepoRoot', $RepoRoot, '-SkipWindowsPowerShellChild') `
    -TimeoutSeconds 120
  Assert-Contract (-not $windowsPowerShellRun.timedOut) `
    'Windows PowerShell 5.1 child contract timed out'
  Assert-Contract ($windowsPowerShellRun.exitCode -eq 0) `
    "Windows PowerShell 5.1 child contract failed: $($windowsPowerShellRun.output.Trim())"
  $childJsonLines = @(
    $windowsPowerShellRun.stdout -split '[\r\n]+' | Where-Object {
      $_.Trim().StartsWith('{') -and $_.Trim().EndsWith('}')
    }
  )
  Assert-Contract ($childJsonLines.Count -gt 0) `
    'Windows PowerShell 5.1 child contract produced no JSON evidence'
  $childEvidence = ConvertFrom-Json -InputObject $childJsonLines[$childJsonLines.Count - 1]
  Assert-Contract ([string]$childEvidence.status -eq 'passed') `
    'Windows PowerShell 5.1 child contract did not pass'
  $windowsPowerShell51Version = [string]$childEvidence.powershellVersion
  Assert-Contract ($windowsPowerShell51Version.StartsWith('5.1.')) `
    'child contract did not run under Windows PowerShell 5.1'
}

[pscustomobject][ordered]@{
  status = 'passed'
  powershellVersion = $PSVersionTable.PSVersion.ToString()
  windowsPowerShell51Version = $windowsPowerShell51Version
  utf8BomScripts = 2
  parsedScripts = 2
  jsonArrayCardinalities = @($empty.Count, $single.Count, $multiple.Count)
  directHdcInvocationCount = ([regex]::Matches($flowText, '& \$HdcPath')).Count
  nativeTimeoutBoundary = $true
} | ConvertTo-Json -Compress
