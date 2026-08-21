[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-dom-matcher-selector-group-context.json',
  [string]$PreFixEvidencePath = 'tools/legado-compat/evidence/contract-legado-jsoup-dom-matcher-selector-group-pre-fix-20260810.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-dom-matcher-selector-group-post-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

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
function Assert-Contract {
  param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @())
  if (-not $Condition) { throw "243 DOM Matcher selector-group post-fix contract failed: $Detail" }
  $script:assertions++
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) })
}
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
$preFix = Read-StrictJson -RelativePath $PreFixEvidencePath
$state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$matcherPath = 'entry/src/main/ets/libs/htmlparser/Matcher.ets'
$matcher = Read-StrictText -RelativePath $matcherPath
$splitStart = $matcher.IndexOf('private static splitByComma(')
$splitEnd = $matcher.IndexOf('  /**', $splitStart + 1)
$sourcePackagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
$packageHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourcePackagePath).Hash.ToUpperInvariant()
$sourceObjects = @($strictUtf8.GetString([System.IO.File]::ReadAllBytes($sourcePackagePath)) | ConvertFrom-Json -Depth 100)
$representative = ($sourceObjects[356] | ConvertTo-Json -Depth 100 -Compress)

Assert-Contract ([int]$fixture.baseline.sourceCount -eq 458 -and [string]$fixture.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$fixture.baseline.legadoCommit -eq $legadoCommit) 'fixture_baseline' 'fixture remains bound to the frozen baselines.' @($FixturePath)
Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit -and $packageHash -eq $baselineHash -and $sourceObjects.Count -eq 458) 'machine_and_package_baseline' 'machine state and source package are unchanged.' @('tools/legado-compat/state/full-source-validation-state.json', $FixturePath)
Assert-Contract ([string]$preFix.status -eq 'failed' -and -not [bool]$preFix.semanticMatchAllowed -and @($preFix.runtimeActionsPerformed).Count -eq 0) 'failure_witness_preserved' 'the pre-fix failure witness remains failed and static-only.' @($PreFixEvidencePath)
Assert-Contract (@($fixture.cases).Count -eq 2 -and [string]$fixture.cases[0].selector -like '*[)]*' -and [string]$fixture.cases[1].selector -like '*:not(:matches*') 'fixture_shape' 'regex-class and nested-not selector-group cases remain bound.' @($FixturePath)
Assert-Contract ($representative.Contains('a:matches') -and $representative.Contains(':not(') -and $representative.Contains('href~=')) 'representative_source_binding' 'the frozen package representative still contains a nested selector group consumer.' @($FixturePath)
Assert-Contract ($splitStart -ge 0 -and $splitEnd -gt $splitStart) 'splitter_boundary' 'Matcher.splitByComma remains a bounded helper.' @($matcherPath)
$splitBody = $matcher.Substring($splitStart, $splitEnd - $splitStart)
Assert-Contract ($splitBody.Contains('let parenthesisDepth = 0') -and $splitBody.Contains('let bracketDepth = 0') -and $splitBody.Contains("let quote = ''") -and $splitBody.Contains('let escaped = false')) 'stateful_contexts' 'group splitting tracks parentheses, brackets, quotes and escapes independently.' @($matcherPath)
Assert-Contract ($splitBody.Contains("if (char === '(' && bracketDepth === 0)") -and $splitBody.Contains("if (char === ')' && parenthesisDepth > 0 && bracketDepth === 0)")) 'bracket_opaque_parentheses' 'parentheses inside regex/attribute brackets do not change pseudo depth.' @($matcherPath)
Assert-Contract ($splitBody.Contains("if (char === ',' && parenthesisDepth === 0 && bracketDepth === 0)")) 'top_level_comma_only' 'only a top-level comma is emitted as a selector-group delimiter.' @($matcherPath)
Assert-Contract (-not $splitBody.Contains("if (char === '(' || char === '[')") -and -not $splitBody.Contains("else if (char === ')' || char === ']')")) 'old_depth_removed' 'the one-integer depth implementation no longer controls group splitting.' @($matcherPath)

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'post_fix_static_contract'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  preFixEvidencePath = $PreFixEvidencePath
  changedPaths = @($matcherPath)
  affectedCases = @($fixture.cases | ForEach-Object { [string]$_.id })
  representativeSourceSet = $fixture.representativeSourceSet
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_dom_matcher_selector_group_static_contract_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  closeCondition = 'R4 must execute both DOM Matcher selector-group cases through V2, the representative frozen source, affected 243 sources, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson -RelativePath $ResultPath -Value $result
$result | ConvertTo-Json -Depth 100
