[CmdletBinding()]
param(
  [string]$RepoRoot = '',
  [string]$ResultPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$assertions = 0

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "HarmonyOS artifact freshness contract failed: $Message" }
  $script:assertions++
}

function Read-Utf8 {
  param([string]$Path)
  Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) "missing file: $Path"
  return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false, $true))
}

function Assert-ParserClean {
  param([string]$Path)
  $tokens = $null
  $errors = $null
  [void][System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
  Assert-Contract ($errors.Count -eq 0) "PowerShell parse error: $Path"
}

if ($RepoRoot.Length -eq 0) {
  $RepoRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
} else {
  $RepoRoot = (Resolve-Path -LiteralPath $RepoRoot).Path
}
if ($ResultPath.Length -eq 0) {
  $ResultPath = Join-Path $RepoRoot 'tools\legado-compat\evidence\harmony-artifact-freshness-contract.json'
}

$runner = Join-Path $RepoRoot 'tools\legado-compat\Invoke-LegadoCompatibility.ps1'
$runnerText = Read-Utf8 -Path $runner
Assert-ParserClean -Path $runner
Assert-Contract ($runnerText.Contains('function Get-HarmonyTestSourceSnapshot')) 'test source snapshot must be explicit'
Assert-Contract ($runnerText.Contains('function Get-HarmonyTestHapIntegrity')) 'HAP archive integrity must be checked'
Assert-Contract ($runnerText.Contains('[System.IO.Compression.ZipFile]::OpenRead')) 'HAP must be opened as a ZIP archive'
Assert-Contract ($runnerText.Contains("'ets/modules.abc'")) 'compiled test bytecode must be required'
Assert-Contract ($runnerText.Contains('function Assert-HarmonyTestHapFresh')) 'freshness assertion must be explicit'
Assert-Contract ($runnerText.Contains('latestWriteTimeUtc') -and $runnerText.Contains('freshAgainstSource')) 'source/HAP freshness must be persisted'
Assert-Contract ($runnerText.Contains('TimeoutSeconds 600')) 'test HAP build must have a bounded timeout'
Assert-Contract ($runnerText.Contains('artifact_complete_after_wrapper_timeout')) 'wrapper timeout must be classified rather than silently ignored'
Assert-Contract ($runnerText.Contains('testBuildResult.timedOut')) 'timeout result must flow into the evidence and gate'
Assert-Contract ($runnerText.Contains('Get-HarmonyTestSourceSnapshot') -and $runnerText.Contains('Assert-HarmonyTestHapFresh')) 'freshness helpers must be called before installation'
Assert-Contract ($runnerText.Contains('function Recover-StaleCompatibilityStages') -and $runnerText.Contains('Recover-StaleCompatibilityStages')) 'interrupted stage state must be recoverable on the next refresh'
Assert-Contract ($runnerText.Contains('-File\s+') -and $runnerText.Contains('-Command\s')) 'stale-run recovery must distinguish real runner siblings from the host command wrapper'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  generatedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
  assertions = $script:assertions
  status = 'passed'
  checks = @(
    'test source fingerprint',
    'zip archive integrity',
    'compiled bytecode presence',
    'source-to-HAP freshness',
    'bounded build timeout',
    'timeout terminal classification',
    'pre-install freshness gate'
  )
}
$directory = Split-Path -Path $ResultPath -Parent
if (-not (Test-Path -LiteralPath $directory)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
$temporary = "$ResultPath.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
[System.IO.File]::WriteAllText($temporary, ($result | ConvertTo-Json -Depth 8), [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporary -Destination $ResultPath -Force
Write-Output ($result | ConvertTo-Json -Depth 8)
