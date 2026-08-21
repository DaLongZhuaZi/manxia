[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$PreFixEvidencePath = 'tools/legado-compat/evidence/contract-legado-jsoup-has-pseudo-selector-pre-fix-20260809.json',
  [string]$StaticContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-has-pseudo-selector.json',
  [string]$SourceFixEvidencePath = 'tools/legado-compat/evidence/v2-jsoup-has-pseudo-selector-source-fix-20260807.json',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-has-pseudo-selector.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/v2-jsoup-has-pseudo-selector-current-head-audit-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing JSON: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  try { return ($strictUtf8.GetString($bytes) | ConvertFrom-Json) } catch { throw "Invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing text: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}

function Get-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Assert-Audit {
  param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @())
  if (-not $Condition) { throw "236 current-head audit failed: $Detail" }
  $script:assertions++
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) })
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value)
  $absolute = Get-RepoPath -RelativePath $RelativePath
  $directory = Split-Path -Parent $absolute
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$absolute.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 40), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $absolute -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$result = $null
$exitCode = 0
try {
  $statePath = 'tools/legado-compat/state/full-source-validation-state.json'
  $state = Read-StrictJson -RelativePath $statePath
  $preFix = Read-StrictJson -RelativePath $PreFixEvidencePath
  $contract = Read-StrictJson -RelativePath $StaticContractPath
  $sourceFix = Read-StrictJson -RelativePath $SourceFixEvidencePath
  $fixture = Read-StrictJson -RelativePath $FixturePath
  Assert-Audit ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$state.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'baseline' 'Fixed 458-source baseline is unchanged.' @($statePath)
  Assert-Audit ([string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS') 'queue' '236 remains a candidate while 235 is the sole active issue.' @($statePath)
  Assert-Audit ([string]$preFix.issueId -eq 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR' -and [string]$preFix.status -eq 'failed' -and -not [bool]$preFix.semanticMatchAllowed -and @($preFix.runtimeActionsPerformed).Count -eq 0) 'pre_fix' 'Independent 236 failure witness is preserved as failed and static-only.' @($PreFixEvidencePath)
  Assert-Audit ([string]$contract.status -eq 'passed' -and [int]$contract.assertions -eq 15 -and -not [bool](Get-PropertyValue -Object $contract -Name 'semanticMatchAllowed' -Default $false)) 'static_contract' 'The existing 15-assertion :has static contract passed without runtime claims.' @($StaticContractPath)
  Assert-Audit ([string]$sourceFix.issueId -eq 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR' -and -not [bool]$sourceFix.semanticMatchAllowed) 'source_fix' 'Historical 236 source-fix evidence remains static-only.' @($SourceFixEvidencePath)
  Assert-Audit ([int]$fixture.cases.Count -eq 5 -and [int]$sourceFix.staticImpact.affectedSourceCount -eq 5 -and [int]$sourceFix.staticImpact.hasRuleStringCount -eq 70) 'impact' 'Fixture and 70-rule/5-source impact set are bound.' @($FixturePath, $SourceFixEvidencePath)

  $paths = @(
    'entry/src/main/ets/libs/htmlparser/HTMLElement.ets',
    'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
    'entry/src/main/resources/rawfile/legado_runtime.html'
  )
  $sourceHashes = [ordered]@{}
  $element = Read-StrictText -RelativePath $paths[0]
  $analyzer = Read-StrictText -RelativePath $paths[1]
  $runtime = Read-StrictText -RelativePath $paths[2]
  $sourceHashes[$paths[0]] = (Get-FileHash -LiteralPath (Get-RepoPath -RelativePath $paths[0]) -Algorithm SHA256).Hash.ToUpperInvariant()
  $sourceHashes[$paths[1]] = (Get-FileHash -LiteralPath (Get-RepoPath -RelativePath $paths[1]) -Algorithm SHA256).Hash.ToUpperInvariant()
  $sourceHashes[$paths[2]] = (Get-FileHash -LiteralPath (Get-RepoPath -RelativePath $paths[2]) -Algorithm SHA256).Hash.ToUpperInvariant()
  Assert-Audit ($element.Contains("pseudo.name === 'has'") -and $element.Contains("argument.startsWith('>')") -and $element.Contains('elem.querySelectorAll(argument)')) 'dom_has' 'Current DOM matcher has descendant and direct-child :has evaluation.' @($paths[0])
  Assert-Audit ($analyzer.Contains("pseudo.name === 'has'") -and $analyzer.Contains('matchesStringHasPseudo') -and $analyzer.Contains('findDirectChildren(innerHtml)')) 'string_has' 'Current large-document fallback evaluates nested and direct-child :has.' @($paths[1])
  Assert-Audit ($runtime.Contains("name === 'has'") -and $runtime.Contains('relativeSelector') -and $runtime.Contains('legadoSelectWithJsoupRegex(node')) 'arkweb_has' 'Current ArkWeb bridge evaluates and projects :has recursively.' @($paths[2])
  $legadoHead = (& git -C (Get-RepoPath -RelativePath 'legado') rev-parse HEAD 2>$null | Out-String).Trim()
  Assert-Audit ($legadoHead -eq [string]$state.baseline.legadoCommit) 'legado_commit' 'Legado checkout remains at the pinned reference commit.' @('legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt')

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_jsoup_has_pseudo_selector_current_head_audit'
    status = 'passed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    issueId = 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR'
    baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = [string]$state.baseline.sourcePackageSha256; legadoCommit = [string]$state.baseline.legadoCommit }
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    currentHeadHashes = $sourceHashes
    changedPaths = $paths
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_236_current_head_static_audit_only;runtime_build_device_and_legado_diff_deferred'
    nextAction = '236 仍为候选；补齐消费者矩阵与 235→236 专用静态转移登记后才可激活。'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_jsoup_has_pseudo_selector_current_head_audit'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_236_current_head_static_audit_only;runtime_build_device_and_legado_diff_deferred'
  }
}

Write-AtomicJson -RelativePath $OutputPath -Value $result
$result | ConvertTo-Json -Depth 40
if ($exitCode -ne 0) { exit $exitCode }
