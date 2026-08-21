[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-hypium-workflow-capability-dispatch-037.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-hypium-workflow-capability-dispatch-037.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$runnerRelativePath = 'tools/legado-compat/Invoke-LegadoV2HypiumFullSourceDeviceRunner.ps1'
$fixtureAbsolutePath = Join-Path $RepositoryRoot ($FixturePath.Replace('/', '\'))
$runnerAbsolutePath = Join-Path $RepositoryRoot ($runnerRelativePath.Replace('/', '\'))
$outputAbsolutePath = Join-Path $RepositoryRoot ($OutputPath.Replace('/', '\'))
$checks = New-Object 'System.Collections.Generic.List[object]'
$assertions = 0

function Add-ContractCheck {
  param([string]$Id, [string]$Detail, [string[]]$Evidence)
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; detail = $Detail; evidencePaths = @($Evidence) })
}

function Assert-Contract {
  param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence)
  $script:assertions++
  if (-not $Condition) { throw "workflow capability dispatch contract failed [$Id]: $Detail" }
  Add-ContractCheck -Id $Id -Detail $Detail -Evidence $Evidence
}

function Write-AtomicJson {
  param([string]$Path, [object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 30), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$result = $null
$exitCode = 0
try {
  if (-not (Test-Path -LiteralPath $fixtureAbsolutePath -PathType Leaf)) { throw "fixture missing: $FixturePath" }
  if (-not (Test-Path -LiteralPath $runnerAbsolutePath -PathType Leaf)) { throw "runner missing: $runnerRelativePath" }
  $fixtureText = [System.IO.File]::ReadAllText($fixtureAbsolutePath, $strictUtf8)
  $fixture = $fixtureText | ConvertFrom-Json
  $runner = [System.IO.File]::ReadAllText($runnerAbsolutePath, $strictUtf8)
  Assert-Contract ([int]$fixture.baseline.sourceCount -eq 458 -and [string]$fixture.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$fixture.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'baseline_binding' 'fixture is bound to the frozen baseline.' @($FixturePath)
  Assert-Contract (@($fixture.cases).Count -eq 6) 'fixture_cases' 'the dispatch fixture has three entry cases and three missing-capability cases.' @($FixturePath)

  $safetyStart = $runner.IndexOf('function Test-HypiumSafety')
  $safetyEnd = $runner.IndexOf('function Wait-HypiumRequestInterval')
  Assert-Contract ($safetyStart -ge 0 -and $safetyEnd -gt $safetyStart) 'safety_function_bound' 'the safety decision function remains present and bounded.' @($runnerRelativePath)
  $safety = $runner.Substring($safetyStart, $safetyEnd - $safetyStart)
  Assert-Contract ($safety.Contains('if ($searchUrl.Trim().Length -eq 0)') -and $safety.Contains("outcome = 'explore_only_path'")) 'explore_only_safety' 'missing Search is treated as an Explore-only entry decision, not a generic source rejection.' @($runnerRelativePath)
  Assert-Contract ($safety.Contains('$ExecutionProfile -in @(''safe_read_path'', ''full_workflow'')')) 'profile_scope' 'Explore-only safety is limited to profiles that can actually dispatch Explore.' @($runnerRelativePath)

  $recordStart = $runner.IndexOf('function Invoke-HypiumRecord')
  Assert-Contract ($recordStart -ge 0) 'record_dispatch_bound' 'the source dispatcher is present.' @($runnerRelativePath)
  $record = $runner.Substring($recordStart)
  Assert-Contract ($record.Contains('$fullWorkflow = $ExecutionProfile -eq ''full_workflow''')) 'full_workflow_branch' 'full_workflow remains an explicit orchestration profile.' @($runnerRelativePath)
  Assert-Contract ($record.Contains('Set-HypiumFullWorkflowPlanning')) 'capability_planning' 'capability planning precedes dispatch.' @($runnerRelativePath)
  Assert-Contract ($record.Contains('Invoke-HypiumSourceExplore') -and $record.Contains('Invoke-HypiumSourceSearch')) 'independent_entry_points' 'Explore and Search have separate execution entry points.' @($runnerRelativePath)
  Assert-Contract ($record.Contains('-ContinueReadPath:$continueExploreReadPath')) 'explore_read_continuation' 'Explore-only sources can continue into the guarded read path when a result is selected.' @($runnerRelativePath)
  Assert-Contract ($runner.Contains('Test-HypiumExploreReadCapabilitySet') -and $runner.Contains('safe_read_path_read_chain_capability_dependency_missing')) 'capability_independent_read_settlement' 'Explore-only continuation is gated by the complete read capability set and settles missing/dependent workflows explicitly.' @($runnerRelativePath)
  Assert-Contract (-not $record.Contains('$exploreWorkflow = $ExecutionProfile -eq ''safe_read_path'' -and $exploreCapability')) 'no_safe_read_capability_short_circuit' 'safe_read dispatch must not short-circuit solely because Explore exists.' @($runnerRelativePath)
  Assert-Contract ($runner.Contains('safe_read_path_explore_deferred') -and $runner.Contains('safe_read_path_explore_requested')) 'independent_explore_state' 'safe_read distinguishes deferred Explore from an Explore-only request.' @($runnerRelativePath)
  Assert-Contract ($record.Contains('search_workflow_missing')) 'missing_search_settlement' 'Explore-only sources settle missing Search explicitly.' @($runnerRelativePath)
  Assert-Contract ($record.Contains('safe_read_path_not_executed_after_search_terminal')) 'terminal_settlement' 'terminal Search outcomes settle only workflows that were actually scheduled.' @($runnerRelativePath)
  Assert-Contract (-not $record.Contains("Set-HypiumWorkflow -State `$State -Record `$Record -Name `$name -Status 'policy_blocked' -Outcome 'profile_explore_only'")) 'no_profile_explore_only_projection' 'the old batch-wide profile_explore_only projection is removed from dispatch.' @($runnerRelativePath)

  foreach ($case in @($fixture.cases)) {
    Assert-Contract ($null -ne $case.expected -and ([string]$case.expected.earlyReturn -eq 'False' -or [bool]$case.expected.earlyReturn -eq $false)) ('case_no_early_return_' + [string]$case.id) ('case ' + [string]$case.id + ' must not use an early-return batch projection.') @($FixturePath)
  }
  $capabilityCases = @($fixture.cases | Where-Object { [string]$_.id -like 'safe_read_explore_only_missing_*' })
  Assert-Contract ($capabilityCases.Count -eq 3) 'capability_cases' 'BookInfo, Toc and Content missing-capability cases are all represented.' @($FixturePath)
  foreach ($case in $capabilityCases) {
    Assert-Contract ([bool]$case.expected.continueReadPath -eq $false) ('case_no_capability_read_dispatch_' + [string]$case.id) ('case ' + [string]$case.id + ' must not start the Explore read chain.') @($FixturePath)
    Assert-Contract (([string]$case.expected.bookInfo -match '^(?:blocked|policy_blocked):') -and ([string]$case.expected.toc -match '^(?:blocked|policy_blocked):') -and ([string]$case.expected.content -match '^(?:blocked|policy_blocked):')) ('case_independent_capability_settlement_' + [string]$case.id) ('case ' + [string]$case.id + ' must settle every read workflow explicitly.') @($FixturePath)
  }
  Add-ContractCheck -Id 'static_only' -Detail 'No device, network, build or Legado runtime actions were performed.' -Evidence @()
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_v2_hypium_workflow_capability_dispatch_contract'
    status = 'passed'
    issueId = 'ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    fixturePath = $FixturePath
    runnerPath = $runnerRelativePath
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_static_contract_only;runtime_and_R4_deferred'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_v2_hypium_workflow_capability_dispatch_contract'
    status = 'failed'
    issueId = 'ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_static_contract_only;runtime_and_R4_deferred'
  }
}

Write-AtomicJson -Path $outputAbsolutePath -Value $result
$result | ConvertTo-Json -Depth 30
if ($exitCode -ne 0) { exit $exitCode }
