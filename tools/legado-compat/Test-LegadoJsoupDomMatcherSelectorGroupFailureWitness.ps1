[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-dom-matcher-selector-group-context.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-dom-matcher-selector-group-pre-fix-20260810.json'
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
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "required file is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return $strictUtf8.GetString($bytes)
}
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100) }
function Assert-Witness { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 DOM Matcher selector-group witness failed: $Message" }; $script:assertions++ }
function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8)
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
$sourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
$matcherPath = Get-RepoPath 'entry/src/main/ets/libs/htmlparser/Matcher.ets'
$fixture = Read-StrictJson -Path $fixtureAbsolutePath
$state = Read-StrictJson -Path $statePath
$matcher = Read-StrictText -Path $matcherPath
$packageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePackagePath).Hash.ToUpperInvariant()
$packageBytes = [System.IO.File]::ReadAllBytes($sourcePackagePath)
$sourceObjects = @($strictUtf8.GetString($packageBytes) | ConvertFrom-Json -Depth 100)
$splitStart = $matcher.IndexOf('private static splitByComma(')
$splitEnd = $matcher.IndexOf('  /**', $splitStart + 1)
$representative = ($sourceObjects[356] | ConvertTo-Json -Depth 100 -Compress)

Assert-Witness ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine baseline drifted.'
Assert-Witness ($packageHash -eq $baselineHash -and $sourceObjects.Count -eq 458) 'frozen source package drifted.'
Assert-Witness ([string]$fixture.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and @($fixture.cases).Count -eq 2) 'fixture is not bound to the two DOM group cases.'
Assert-Witness ($representative.Contains('a:matches') -and $representative.Contains(':not(') -and $representative.Contains('href~=')) 'representative nested selector source binding is missing.'
Assert-Witness ($splitStart -ge 0 -and $splitEnd -gt $splitStart) 'Matcher.splitByComma boundary is missing.'
$splitBody = $matcher.Substring($splitStart, $splitEnd - $splitStart)
Assert-Witness ($splitBody.Contains("if (char === '(' || char === '[')") -and $splitBody.Contains("else if (char === ')' || char === ']')")) 'the single integer depth implementation is missing.'
Assert-Witness (-not $splitBody.Contains('let parenthesisDepth = 0') -and -not $splitBody.Contains('let bracketDepth = 0') -and -not $splitBody.Contains('let escaped = false')) 'the context-aware Matcher scanner already exists.'
Assert-Witness ([string]$fixture.failureCondition -match 'inside \[\)\]') 'fixture does not bind the closing-parenthesis regex-class failure.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'failure_witness'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  failureClass = 'v2_dom_matcher_selector_group_splitter_regex_character_class_parenthesis_depth_leaks_into_inner_comma'
  selectionPath = @($fixture.selectionPath)
  affectedCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  representativeSourceSet = $fixture.representativeSourceSet
  failureWitness = [pscustomobject][ordered]@{
    branch = 'Matcher.splitByComma'
    observed = 'The one integer depth counter decrements for ) inside [)] and exposes a comma that is still inside :matches or :not as a selector-group boundary.'
    sourcePattern = "if (char === '(' || char === '[') / else if (char === ')' || char === ']')"
    expected = 'Track parentheses, brackets, quotes and escapes independently; only a comma at zero parenthesis and bracket depth may split groups.'
  }
  assertions = $script:assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred'
}
Write-AtomicJson -Path $resultAbsolutePath -Value $result
$result | ConvertTo-Json -Depth 100
