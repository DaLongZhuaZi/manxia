[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selector-direct-child-context.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-selector-direct-child-context-pre-fix-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "required file is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100)
}

function Assert-Witness {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "243 direct-child context witness failed: $Message" }
  $script:assertions++
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 80), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$fixtureAbsolutePath = Get-RepoPath $FixturePath
$resultAbsolutePath = Get-RepoPath $ResultPath
$statePath = Get-RepoPath 'tools/legado-compat/state/full-source-validation-state.json'
$analyzerRelativePath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$analyzerPath = Get-RepoPath $analyzerRelativePath

$fixture = Read-StrictJson -Path $fixtureAbsolutePath
$state = Read-StrictJson -Path $statePath
$analyzer = Read-StrictText -Path $analyzerPath
$functionStart = $analyzer.IndexOf('private findElementsByDirectChildSelector(')
$functionEnd = $analyzer.IndexOf('private getElementsByRegex(', $functionStart)
Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline drifted.'
Assert-Witness ([string]$fixture.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and @($fixture.cases).Count -eq 4) 'fixture is not bound to the four direct-child cases.'
Assert-Witness ($functionStart -ge 0 -and $functionEnd -gt $functionStart) 'direct-child fallback function boundary is missing.'
$functionBody = $analyzer.Substring($functionStart, $functionEnd - $functionStart)
Assert-Witness ($functionBody.Contains('findElementsBySimpleSelector(child, childSelector)')) 'the isolated-child call was not found.'
Assert-Witness (-not $functionBody.Contains('legado-direct-parent')) 'the pre-fix witness must run before the scoped-parent fix.'
Assert-Witness ($analyzer.Contains('filterElementsByStandardChildPseudo(filtered, pseudo.name, contextHtml, argument)')) 'standard pseudo dispatch is not present for the witness path.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'failure_witness'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  failureClass = 'v2_large_document_string_fallback_direct_child_pseudo_context_loss'
  selectionPath = [string]$fixture.selectionPath
  affectedCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  failureWitness = [pscustomobject][ordered]@{
    branch = 'findElementsByDirectChildSelector'
    observed = 'each direct child is passed as both the selector input and pseudo context; siblingPosition cannot resolve the parent from an isolated child.'
    sourcePattern = 'findElementsBySimpleSelector(child, childSelector)'
    expected = 'evaluate childSelector against a scoped parent containing all direct element siblings, then retain only direct-child matches.'
  }
  assertions = $script:assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred'
}
Write-AtomicJson -Path $resultAbsolutePath -Value $result
$result | ConvertTo-Json -Depth 80
