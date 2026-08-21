[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-combination-r4-context.json',
  [string]$AuditPath = 'tools/legado-compat/evidence/v2-jsoup-standard-pseudo-combination-audit-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-standard-pseudo-combination-r4-consumer-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$Path)
  if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
  return Join-Path $RepositoryRoot ($Path.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing file: $Path" }
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

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Get-Sha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Add-Check {
  param([Parameter(Mandatory = $true)][string]$Id, [Parameter(Mandatory = $true)][bool]$Passed, [Parameter(Mandatory = $true)][string]$Detail)
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; passed = $Passed; detail = $Detail })
  $script:assertions++
  if (-not $Passed) { throw "243 R4 consumer coverage failed: $Id; $Detail" }
}

function Get-RequiredProperty {
  param([Parameter(Mandatory = $true)][object]$Object, [Parameter(Mandatory = $true)][string]$Name)
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property) { throw "Missing property '$Name'." }
  return $property.Value
}

$outputFullPath = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot ($OutputPath.Replace('/', '\'))))
$evidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).TrimEnd('\') + '\'
if (-not $outputFullPath.StartsWith($evidenceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Consumer coverage evidence must remain under the evidence directory.'
}

$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -Path (Get-RepoPath 'tools/legado-compat/state/full-source-validation-state.json')
  $fixture = Read-StrictJson -Path (Get-RepoPath $FixturePath)
  $audit = Read-StrictJson -Path (Get-RepoPath $AuditPath)

  Add-Check 'baseline' (
    [int]$state.baseline.sourceCount -eq 458 -and
    [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and
    [string]$state.baseline.legadoCommit -eq $legadoCommit -and
    [int]$fixture.baseline.sourceCount -eq 458 -and
    [string]$fixture.baseline.sourcePackageSha256 -eq $baselineHash -and
    [string]$fixture.baseline.legadoCommit -eq $legadoCommit -and
    [int]$audit.baseline.sourceCount -eq 458 -and
    [string]$audit.baseline.sourcePackageSha256 -eq $baselineHash -and
    [string]$audit.baseline.legadoCommit -eq $legadoCommit
  ) 'machine state, fixture and audit share the frozen baseline.'
  Add-Check 'active_issue' (
    [string]$state.governance.activeIssueId -eq $issueId -and
    [string]$state.governance.status -eq 'running' -and
    [string]$audit.issueId -eq $issueId
  ) '243 remains the active issue and the audit is bound to it.'
  Add-Check 'static_only_policy' (
    [string]$fixture.status -eq 'registered_static_only' -and
    [string]$audit.status -eq 'passed_static_only' -and
    -not [bool]$fixture.semanticMatchAllowed -and
    -not [bool]$audit.semanticMatchAllowed -and
    @($fixture.runtimeActionsPerformed).Count -eq 0 -and
    @($audit.runtimeActionsPerformed).Count -eq 0 -and
    -not [bool]$audit.newRootCauseFound
  ) 'fixture and audit remain static-only and cannot qualify runtime semantics.'
  Add-Check 'fixture_shape' (
    @($fixture.sourceOrdinals).Count -eq 2 -and
    @($fixture.sourceOrdinals) -contains 357 -and
    @($fixture.sourceOrdinals) -contains 402 -and
    [int]$fixture.sourceOccurrenceCount -eq 5 -and
    @($fixture.cases).Count -eq 5
  ) 'the exact five frozen ordinal 357/402 cases are present.'

  $requiredCombinations = @('standard-only-child', 'has-relative-selector', 'text-matches-own', 'not-selector', 'regex-attribute', 'direct-child-or-sibling')
  foreach ($combination in $requiredCombinations) {
    Add-Check ("fixture_combination_{0}" -f $combination) (@($fixture.requiredCombinationSet) -contains $combination) ("fixture declares required combination '$combination'.")
  }
  Add-Check 'fixture_cases_deferred' (
    @($fixture.cases | Where-Object { [string]$_.expectedStatus -ne 'deferred_to_r4_legado_runtime_diff' }).Count -eq 0 -and
    @($fixture.cases | Where-Object { $null -ne $_.expected }).Count -eq 0
  ) 'all five cases defer expected output to R4 and contain no inferred result.'

  $consumerMatrix = @($audit.consumerMatrix)
  Add-Check 'consumer_matrix_shape' ($consumerMatrix.Count -eq 5) 'audit declares exactly five consumer paths.'
  $consumerSpecs = @(
    [pscustomobject][ordered]@{
      id = 'string_fallback'
      path = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
      markers = @('getElementsByCSSWithBridge', 'getElementsByCSSChain', 'splitSelectorWithJs', 'parseCSSSelectorAndAttr')
    },
    [pscustomobject][ordered]@{
      id = 'dom_matcher'
      path = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
      markers = @('querySelectorAll', 'matchesPseudoClass', 'matchesHasDirectChildRelativeSelector', 'matchesSelectorChainAtElement')
    },
    [pscustomobject][ordered]@{
      id = 'selector_parser'
      path = 'entry/src/main/ets/libs/htmlparser/Matcher.ets'
      markers = @('static parseSelector', 'parsePseudoClass', 'isValidLegadoAttributeSelector', 'matchAttribute')
    },
    [pscustomobject][ordered]@{
      id = 'arkweb_runtime'
      path = 'entry/src/main/resources/rawfile/legado_runtime.html'
      markers = @('legadoMatchesJsoupSelector', 'legadoMatchesJsoupSelectorInContext', 'legadoSelectWithJsoupRegex', 'legadoSelectorHasInvalidRegexAttribute')
    },
    [pscustomobject][ordered]@{
      id = 'legado_reference'
      path = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
      markers = @('import org.jsoup.Jsoup', 'element.select(', 'temp.select(', 'RuleAnalyzer')
    }
  )

  foreach ($spec in $consumerSpecs) {
    $matrixEntry = @($consumerMatrix | Where-Object { [string]$_.id -eq $spec.id }) | Select-Object -First 1
    Add-Check ("consumer_matrix_{0}" -f $spec.id) ($null -ne $matrixEntry -and [string]$matrixEntry.status -in @('static_consumer_present', 'nested_parser_present', 'owning_compound_consumer_present', 'jsoup_select_reference_present')) ("audit matrix contains consumer '$($spec.id)'.")
    $path = Get-RepoPath $spec.path
    Add-Check ("consumer_file_{0}" -f $spec.id) (Test-Path -LiteralPath $path -PathType Leaf) ("consumer file exists for '$($spec.id)'.")
    $text = Read-StrictText -Path $path
    foreach ($marker in @($spec.markers)) {
      Add-Check ("consumer_marker_{0}_{1}" -f $spec.id, ($marker -replace '[^A-Za-z0-9]+', '_')) ($text.Contains($marker)) ("consumer '$($spec.id)' contains '$marker'.")
    }
  }

  $auditHashes = @{}
  foreach ($property in $audit.currentHeadHashes.PSObject.Properties) { $auditHashes[$property.Name] = [string]$property.Value }
  foreach ($spec in $consumerSpecs) {
    $path = Get-RepoPath $spec.path
    Add-Check ("consumer_hash_{0}" -f $spec.id) ($auditHashes.ContainsKey($spec.path) -and $auditHashes[$spec.path] -eq (Get-Sha256 -Path $path)) ("current-head hash matches audit for '$($spec.id)'.")
  }

  $fixtureHash = Get-Sha256 -Path (Get-RepoPath $FixturePath)
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    evidenceType = 'r4_consumer_coverage_static_contract'
    issueId = $issueId
    status = 'passed_static_only'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
    fixturePath = $FixturePath
    fixtureSha256 = $fixtureHash
    auditPath = $AuditPath
    consumerIds = @($consumerSpecs | ForEach-Object { $_.id })
    assertions = $script:assertions
    checks = @($script:checks.ToArray())
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r4_consumer_coverage_static_only;runtime_and_legado_diff_deferred'
    nextGate = 'Execute the five fixture cases through every listed consumer and fixed Legado before semantic qualification.'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    evidenceType = 'r4_consumer_coverage_static_contract'
    issueId = $issueId
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = @($script:checks.ToArray())
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
  }
}

Write-AtomicJson -Path $outputFullPath -Value $result
$result | ConvertTo-Json -Depth 100
if ($exitCode -ne 0) { exit $exitCode }
