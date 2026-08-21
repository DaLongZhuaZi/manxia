[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-dom-matcher-selector-group-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-dom-matcher-selector-group-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-dom-matcher-selector-group-post-fix-20260810.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/v2-jsoup-dom-matcher-selector-group-current-head-audit-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$RelativePath); return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required file is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$RelativePath); return (Read-StrictText -RelativePath $RelativePath | ConvertFrom-Json -Depth 100) }
function Assert-Audit { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 DOM Matcher selector-group current-head audit failed: $Message" }; $script:assertions++ }
function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value)
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$fixture = Read-StrictJson -RelativePath $FixturePath
$failure = Read-StrictJson -RelativePath $FailureWitnessPath
$contract = Read-StrictJson -RelativePath $PostFixContractPath
$state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$matcherPath = 'entry/src/main/ets/libs/htmlparser/Matcher.ets'
$matcher = Read-StrictText -RelativePath $matcherPath
$splitStart = $matcher.IndexOf('private static splitByComma(')
$splitEnd = $matcher.IndexOf('  /**', $splitStart + 1)
$splitBody = $matcher.Substring($splitStart, $splitEnd - $splitStart)
$hash = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $matcherPath)).Hash.ToUpperInvariant()

Assert-Audit ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen machine baseline is unchanged.'
Assert-Audit ([string]$fixture.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and @($fixture.cases).Count -eq 2) 'fixture binding or case count changed.'
Assert-Audit ([string]$failure.status -eq 'failed' -and [string]$contract.status -eq 'passed' -and -not [bool]$failure.semanticMatchAllowed -and -not [bool]$contract.semanticMatchAllowed) 'failure and post-fix evidence are not static-only.'
Assert-Audit ($splitStart -ge 0 -and $splitEnd -gt $splitStart) 'Matcher.splitByComma boundary is missing.'
Assert-Audit ($splitBody.Contains('let parenthesisDepth = 0') -and $splitBody.Contains('let bracketDepth = 0') -and $splitBody.Contains("let quote = ''") -and $splitBody.Contains('let escaped = false')) 'context-aware group splitter is not present.'
Assert-Audit ($splitBody.Contains("if (char === ',' && parenthesisDepth === 0 && bracketDepth === 0)")) 'group splitter does not enforce top-level comma boundaries.'
Assert-Audit (-not $splitBody.Contains("if (char === '(' || char === '[')") -and -not $splitBody.Contains("else if (char === ')' || char === ']')")) 'legacy one-integer depth splitter is still active.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'current_head_static_audit'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  changedPaths = @($matcherPath)
  currentHeadHashes = [pscustomobject][ordered]@{ $matcherPath = $hash }
  fixturePath = $FixturePath
  failureWitnessPath = $FailureWitnessPath
  postFixContractPath = $PostFixContractPath
  assertions = $script:assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_dom_matcher_selector_group_current_head_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  nextGate = 'Register the DOM Matcher static source fix and keep 243 verifying until R4 runtime and Legado differential gates.'
}
Write-AtomicJson -RelativePath $ResultPath -Value $result
$result | ConvertTo-Json -Depth 100
