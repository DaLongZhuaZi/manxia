[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RunId = 'r3-static-gate-20260808-run-015',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($RepositoryRoot.Length -eq 0) {
  $RepositoryRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path

$evidenceRoot = (Resolve-Path -LiteralPath (Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).Path
$runDirectory = Join-Path $evidenceRoot $RunId
if ($OutputPath.Length -eq 0) {
  $OutputPath = Join-Path $runDirectory 'r3-source-closure-static-gate.json'
}
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$evidenceRootPrefix = $evidenceRoot.TrimEnd('\') + '\'
if (-not $outputFullPath.ToLowerInvariant().StartsWith($evidenceRootPrefix.ToLowerInvariant())) {
  throw 'R3 static gate output must remain under the evidence directory.'
}
if ($outputFullPath -match '\\full-source-v2-hypium-device(?:\\|$)' -or
    $outputFullPath -match '\\effective-full-source-v2-hypium-device(?:\\|$)') {
  throw 'R3 static gate cannot write to a canonical full-source evidence directory.'
}

if (-not (Test-Path -LiteralPath $runDirectory)) {
  [System.IO.Directory]::CreateDirectory($runDirectory) | Out-Null
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:checks = New-Object 'System.Collections.Generic.List[object]'
$script:evidencePaths = New-Object 'System.Collections.Generic.List[string]'
$script:assertions = 0

function Add-Check {
  param(
    [string]$Id,
    [string]$Status,
    [string]$Detail,
    [string[]]$Evidence = @()
  )
  $script:checks.Add([pscustomobject][ordered]@{
    id = $Id
    status = $Status
    detail = $Detail
    evidencePaths = @($Evidence)
  })
  foreach ($path in @($Evidence)) {
    if ($path.Length -gt 0 -and -not $script:evidencePaths.Contains($path)) {
      $script:evidencePaths.Add($path)
    }
  }
  if ($Status -eq 'passed') {
    $script:assertions++
  }
}

function Read-StrictUtf8Text {
  param([Parameter(Mandatory = $true)][string]$Path)
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) {
    throw "Required JSON is missing: $Path"
  }
  $text = Read-StrictUtf8Text -Path $Path
  try {
    return $text | ConvertFrom-Json
  } catch {
    throw "Invalid JSON: $Path; $($_.Exception.Message)"
  }
}

function Get-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Default = $null)
  if ($null -eq $Object) {
    return $Default
  }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) {
    return $Default
  }
  return $property.Value
}

function Assert-Gate {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) {
    throw $Message
  }
}

function Get-Sha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-RelativePath {
  param([string]$Path)
  return [System.IO.Path]::GetRelativePath($RepositoryRoot, $Path).Replace('\', '/')
}

function Test-ContainsValue {
  param([object]$Value, [string]$Expected)
  if ($null -eq $Value) {
    return $false
  }
  if ($Value -is [string]) {
    return [string]$Value -eq $Expected
  }
  if ($Value -is [System.Collections.IEnumerable]) {
    foreach ($item in $Value) {
      if (Test-ContainsValue -Value $item -Expected $Expected) {
        return $true
      }
    }
    return $false
  }
  foreach ($property in $Value.PSObject.Properties) {
    if (Test-ContainsValue -Value $property.Value -Expected $Expected) {
      return $true
    }
  }
  return $false
}

function Test-PowerShellSyntax {
  $files = @(Get-ChildItem -LiteralPath (Join-Path $RepositoryRoot 'tools\legado-compat') -Filter '*.ps1' -File -Recurse)
  $syntaxErrors = New-Object 'System.Collections.Generic.List[string]'
  foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    if ($null -ne $errors -and $errors.Count -gt 0) {
      foreach ($errorRecord in $errors) {
        $syntaxErrors.Add("$($file.FullName):$($errorRecord.Extent.StartLineNumber):$($errorRecord.Message)")
      }
    }
  }
  Assert-Gate ($syntaxErrors.Count -eq 0) ('PowerShell syntax errors: ' + ($syntaxErrors -join ' | '))
  Add-Check -Id 'powershell_syntax' -Status 'passed' -Detail ("Parsed {0} PowerShell files with no syntax errors." -f $files.Count)
}

function Invoke-StaticContract {
  param(
    [string]$Name,
    [string]$ScriptPath,
    [string]$ResultPath,
    [int]$ExpectedAssertions
  )
  $pwsh = Get-Command 'pwsh' -ErrorAction SilentlyContinue
  $runner = if ($null -ne $pwsh) { $pwsh.Source } else { Join-Path $PSHOME 'powershell.exe' }
  & $runner -NoProfile -File $ScriptPath -RepoRoot $RepositoryRoot -ResultPath $ResultPath | Out-Null
  if ($LASTEXITCODE -ne 0) {
    throw "$Name contract exited with code $LASTEXITCODE"
  }
  $result = Read-StrictJson -Path $ResultPath
  Assert-Gate ([string](Get-PropertyValue -Object $result -Name 'status') -eq 'passed') "$Name contract did not pass."
  Assert-Gate ([string](Get-PropertyValue -Object $result -Name 'issueId') -eq 'ISSUE-COMPAT-014') "$Name contract is not bound to ISSUE-COMPAT-014."
  Assert-Gate ([int](Get-PropertyValue -Object $result -Name 'assertions') -eq $ExpectedAssertions) "$Name assertion count changed."
  $phase = [string](Get-PropertyValue -Object $result -Name 'phase')
  if ($phase.Length -gt 0) {
    Assert-Gate ($phase -eq 'source_closure_static_verified_pending_r4') "$Name phase must remain pending R4."
  }
  Add-Check -Id $Name -Status 'passed' -Detail ("{0} assertions; runtime verification remains deferred." -f $ExpectedAssertions) -Evidence @((Get-RelativePath -Path $ResultPath))
}

$gateStatus = 'passed'
$failure = ''
$sourceHash = ''
$legadoCommit = ''
$state = $null
$objective = $null
$summary = $null

try {
  $statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
  $objectivePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\refactor-objective.json'
  $packagePath = 'F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json'
  $state = Read-StrictJson -Path $statePath
  $objective = Read-StrictJson -Path $objectivePath
  Assert-Gate ([int]$state.baseline.sourceCount -eq 458) 'Machine state source count is not 458.'
  Assert-Gate ([int]$objective.baseline.sourceCount -eq 458) 'Refactor objective source count is not 458.'
  Assert-Gate ([string]$state.baseline.sourcePackageSha256 -eq [string]$objective.baseline.sourcePackageSha256) 'State and objective source hashes differ.'
  Assert-Gate ([string]$state.baseline.legadoCommit -eq [string]$objective.baseline.legadoCommit) 'State and objective Legado commits differ.'
  Assert-Gate ([string]$objective.status -eq 'active') 'Refactor objective is not active.'
  Assert-Gate ([string]$objective.continuationMode -eq 'R2-R3_SOURCE_CLOSURE_ONLY') 'Refactor objective continuation mode drifted.'
  $sourceHash = Get-Sha256 -Path $packagePath
  Assert-Gate ($sourceHash -eq [string]$state.baseline.sourcePackageSha256) 'Source package hash does not match the frozen baseline.'
  $legadoRoot = Join-Path $RepositoryRoot 'legado'
  $legadoCommit = (& git -C $legadoRoot rev-parse HEAD 2>$null | Out-String).Trim()
  Assert-Gate ($legadoCommit -eq [string]$state.baseline.legadoCommit) 'Legado commit does not match the frozen baseline.'
  Add-Check -Id 'baseline_binding' -Status 'passed' -Detail ("458 sources; source SHA-256={0}; Legado={1}." -f $sourceHash, $legadoCommit)

  $governance = $state.governance
  Assert-Gate ([string]$governance.activeTaskId -eq 'COMPAT-006') 'Active task drifted from COMPAT-006.'
  Assert-Gate ([string]$governance.activeIssueId -eq 'ISSUE-COMPAT-014') 'Active issue drifted from ISSUE-COMPAT-014.'
  $issues = @($governance.issues)
  $issue014 = @($issues | Where-Object { [string]$_.id -eq 'ISSUE-COMPAT-014' })[0]
  $issue015 = @($issues | Where-Object { [string]$_.id -eq 'ISSUE-COMPAT-015' })[0]
  Assert-Gate ($null -ne $issue014 -and [string]$issue014.status -eq 'verifying') 'ISSUE-COMPAT-014 must remain verifying.'
  Assert-Gate ($null -ne $issue015 -and [string]$issue015.status -eq 'planned') 'ISSUE-COMPAT-015 must remain planned.'
  Assert-Gate ([string]$governance.refactorObjective.targetRevision -eq [string]$objective.targetRevision) 'Attached objective revision differs from objective file.'
  Add-Check -Id 'queue_anchor' -Status 'passed' -Detail 'COMPAT-006 active; ISSUE-COMPAT-014=verifying; ISSUE-COMPAT-015=planned.'

  $governanceUpdaterPath = Join-Path $RepositoryRoot 'tools\legado-compat\Update-LegadoGovernanceState.ps1'
  $governanceUpdaterText = Read-StrictUtf8Text -Path $governanceUpdaterPath
  Assert-Gate ($governanceUpdaterText.Contains('existingEvidenceProperty') -and
    $governanceUpdaterText.Contains('rawEvidenceValues.ToArray()') -and
    $governanceUpdaterText.Contains('normalizedEvidence.ToArray()')) 'Governance evidence update must merge existing paths before writing.'
  $issueEvidencePaths = @($issue014.evidencePaths | ForEach-Object { [string]$_ })
  $requiredEvidencePaths = @(
    'tools/legado-compat/evidence/r3-static-gate-20260808-run-015/r3-source-closure-static-gate.json',
    'tools/legado-compat/evidence/v2-image-error-storm-source-fix-20260808-r4.json',
    'tools/legado-compat/evidence/v2-image-error-copied-file-cleanup-source-fix-20260808-r3.json',
    'tools/legado-compat/evidence/v2-image-error-log-path-alignment-source-fix-20260808-r1.json'
  )
  foreach ($requiredEvidencePath in $requiredEvidencePaths) {
    Assert-Gate ($issueEvidencePaths -contains $requiredEvidencePath) "Issue 014 evidence ledger lost required path: $requiredEvidencePath"
  }
  Add-Check -Id 'governance_evidence_append' -Status 'passed' -Detail 'The governance writer merges prior evidence and ISSUE-COMPAT-014 retains the current gate plus all three source-fix evidence paths.' -Evidence @('tools/legado-compat/Update-LegadoGovernanceState.ps1')

  Test-PowerShellSyntax

  $jsonPaths = @(
    $statePath,
    $objectivePath,
    (Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-image-error-storm.json'),
    (Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-image-error-file-cleanup.json'),
    (Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-image-error-copied-file-cleanup.json'),
    (Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-image-error-log-path-alignment.json'),
    (Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\v2-governance-task-mirror.json'),
    (Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-image-error-storm-source-fix-20260808-r4.json'),
    (Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-image-error-copied-file-cleanup-source-fix-20260808-r3.json'),
    (Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-image-error-log-path-alignment-source-fix-20260808-r1.json'),
    (Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-manga-reader-source-identity-contract-20260808-post-fix.json')
  )
  foreach ($jsonPath in $jsonPaths) { Read-StrictJson -Path $jsonPath | Out-Null }
  Add-Check -Id 'json_utf8' -Status 'passed' -Detail ("Parsed {0} JSON inputs as strict UTF-8 without BOM." -f $jsonPaths.Count) -Evidence @($jsonPaths | ForEach-Object { Get-RelativePath -Path $_ })

  $objectiveDocument = Join-Path $RepositoryRoot 'docs\analysis\Legado书源V2源码重构持续目标.md'
  $documentText = Read-StrictUtf8Text -Path $objectiveDocument
  Assert-Gate ($documentText.Contains([string]$objective.targetRevision)) 'Objective document revision does not match machine objective.'
  Add-Check -Id 'objective_document_binding' -Status 'passed' -Detail 'Objective Markdown revision matches the machine-readable objective.' -Evidence @('docs/analysis/Legado书源V2源码重构持续目标.md')

  $sourceFixPaths = @(
    (Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-image-error-storm-source-fix-20260808-r4.json'),
    (Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-image-error-copied-file-cleanup-source-fix-20260808-r3.json'),
    (Join-Path $RepositoryRoot 'tools\legado-compat\evidence\v2-image-error-log-path-alignment-source-fix-20260808-r1.json')
  )
  foreach ($sourceFixPath in $sourceFixPaths) {
    $sourceFix = Read-StrictJson -Path $sourceFixPath
    Assert-Gate ([string]$sourceFix.status -eq 'source_closure_static_verified_pending_r4') "Source-fix evidence has an invalid status: $sourceFixPath"
    Assert-Gate ([string]$sourceFix.issueId -eq 'ISSUE-COMPAT-014') "Source-fix evidence is not bound to 014: $sourceFixPath"
    Assert-Gate ([int]$sourceFix.baseline.sourceCount -eq 458) "Source-fix evidence source count drifted: $sourceFixPath"
    Assert-Gate ([string]$sourceFix.baseline.sourcePackageSha256 -eq [string]$state.baseline.sourcePackageSha256) "Source-fix evidence package hash drifted: $sourceFixPath"
    Assert-Gate ([string]$sourceFix.baseline.legadoCommit -eq [string]$state.baseline.legadoCommit) "Source-fix evidence Legado commit drifted: $sourceFixPath"
    Assert-Gate (-not [bool]$sourceFix.semanticMatchAllowed) "Source-fix evidence must not allow semantic match: $sourceFixPath"
  }
  $errorMonitorPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Debug\ErrorMonitorService.ets'
  $errorManagementPath = Join-Path $RepositoryRoot 'entry\src\main\ets\pages\settings\ErrorManagementSubPage.ets'
  $copiedFix = Read-StrictJson -Path $sourceFixPaths[1]
  $pathFix = Read-StrictJson -Path $sourceFixPaths[2]
  Assert-Gate ([string]$copiedFix.changes.sha256 -eq (Get-Sha256 -Path $errorMonitorPath)) 'ErrorMonitorService source hash is not bound.'
  Assert-Gate ([string]$pathFix.changes.sha256 -eq (Get-Sha256 -Path $errorManagementPath)) 'ErrorManagementSubPage source hash is not bound.'
  Add-Check -Id 'source_fix_hash_binding' -Status 'passed' -Detail '014 source-fix evidence binds the current ErrorMonitorService and ErrorManagementSubPage hashes.' -Evidence @($sourceFixPaths | ForEach-Object { Get-RelativePath -Path $_ })

  Invoke-StaticContract -Name 'image_error_storm' -ScriptPath (Join-Path $RepositoryRoot 'tools\legado-compat\Test-LegadoImageErrorStormContract.ps1') -ResultPath (Join-Path $runDirectory 'image-error-storm-post-fix.json') -ExpectedAssertions 46
  Invoke-StaticContract -Name 'image_error_file_cleanup' -ScriptPath (Join-Path $RepositoryRoot 'tools\legado-compat\Test-LegadoImageErrorFileCleanupContract.ps1') -ResultPath (Join-Path $runDirectory 'image-error-file-cleanup-post-fix.json') -ExpectedAssertions 18
  Invoke-StaticContract -Name 'image_error_copied_file_cleanup' -ScriptPath (Join-Path $RepositoryRoot 'tools\legado-compat\Test-LegadoImageErrorCopiedFileCleanupContract.ps1') -ResultPath (Join-Path $runDirectory 'image-error-copied-file-cleanup-post-fix.json') -ExpectedAssertions 27
  Invoke-StaticContract -Name 'image_error_log_path_alignment' -ScriptPath (Join-Path $RepositoryRoot 'tools\legado-compat\Test-LegadoImageErrorLogPathAlignmentContract.ps1') -ResultPath (Join-Path $runDirectory 'image-error-log-path-alignment-post-fix.json') -ExpectedAssertions 13

  $mirrorScript = Join-Path $RepositoryRoot 'tools\legado-compat\Test-LegadoV2GovernanceTaskMirrorContract.ps1'
  $pwsh = Get-Command 'pwsh' -ErrorAction SilentlyContinue
  $runner = if ($null -ne $pwsh) { $pwsh.Source } else { Join-Path $PSHOME 'powershell.exe' }
  $mirrorOutput = (& $runner -NoProfile -File $mirrorScript -RepositoryRoot $RepositoryRoot | Out-String).Trim()
  if ($LASTEXITCODE -ne 0) {
    throw "governance_task_mirror contract exited with code $LASTEXITCODE"
  }
  $mirrorResult = $mirrorOutput | ConvertFrom-Json
  Assert-Gate ([string]$mirrorResult.status -eq 'passed') 'Governance task mirror did not pass.'
  Assert-Gate ([int]$mirrorResult.assertions -eq 430) 'Governance task mirror assertion count changed.'
  $mirrorPath = Join-Path $runDirectory 'governance-task-mirror.json'
  [System.IO.File]::WriteAllText($mirrorPath, ($mirrorResult | ConvertTo-Json -Depth 12), [System.Text.UTF8Encoding]::new($false))
  Add-Check -Id 'governance_task_mirror' -Status 'passed' -Detail '430 task and issue mirror assertions passed.' -Evidence @((Get-RelativePath -Path $mirrorPath))

  $summary = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_source_closure_static_gate'
    status = 'passed'
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    machineFactSource = 'tools/legado-compat/state/full-source-validation-state.json'
    baseline = [pscustomobject][ordered]@{
      sourceCount = [int]$state.baseline.sourceCount
      sourcePackageSha256 = [string]$state.baseline.sourcePackageSha256
      legadoCommit = [string]$state.baseline.legadoCommit
    }
    queue = [pscustomobject][ordered]@{
      activeTaskId = [string]$governance.activeTaskId
      activeIssueId = [string]$governance.activeIssueId
      issue014 = [string]$issue014.status
      issue015 = [string]$issue015.status
    }
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = $script:evidencePaths.ToArray()
    runtimeActionsPerformed = @()
    verificationPolicy = 'static_source_contract_only;R4_runtime_build_device_and_legado_diff_deferred'
    semanticMatchAllowed = $false
  }
} catch {
  $gateStatus = 'failed'
  $failure = $_.Exception.Message
  $summary = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_source_closure_static_gate'
    status = 'failed'
    objectiveId = 'LEGADO-V2-SOURCE-CLOSURE-R3-20260808'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    machineFactSource = 'tools/legado-compat/state/full-source-validation-state.json'
    failure = $failure
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = $script:evidencePaths.ToArray()
    runtimeActionsPerformed = @()
    verificationPolicy = 'static_source_contract_only;R4_runtime_build_device_and_legado_diff_deferred'
    semanticMatchAllowed = $false
  }
}

$temporaryPath = "$outputFullPath.tmp.$PID.$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
[System.IO.File]::WriteAllText($temporaryPath, ($summary | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $temporaryPath -Destination $outputFullPath -Force
Write-Output ($summary | ConvertTo-Json -Depth 20)
if ($gateStatus -eq 'failed') {
  exit 1
}
