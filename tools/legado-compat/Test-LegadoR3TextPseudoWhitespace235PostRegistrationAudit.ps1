[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RunId = 'r3-jsoup-text-whitespace-235-static-audit-20260809',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$evidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).TrimEnd('\') + '\'
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $evidenceRoot (Join-Path $RunId 'post-registration-audit.json')
}
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
if (-not $outputFullPath.StartsWith($evidenceRoot, [System.StringComparison]::OrdinalIgnoreCase)) { throw 'Post-registration output must remain under evidence.' }

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Get-RelativePath {
  param([Parameter(Mandatory = $true)][string]$Path)
  $fullPath = [System.IO.Path]::GetFullPath($Path)
  $prefix = $RepositoryRoot.TrimEnd('\') + '\'
  if ($fullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) { return $fullPath.Substring($prefix.Length).Replace('\', '/') }
  return $fullPath.Replace('\', '/')
}

function Read-StrictBytes {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing file: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM found: $(Get-RelativePath -Path $Path)" }
  return $bytes
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return $strictUtf8.GetString((Read-StrictBytes -Path (Get-RepoPath -RelativePath $RelativePath)))
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $text = Read-StrictText -RelativePath $RelativePath
  try { return ($text | ConvertFrom-Json) } catch { throw "Invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Get-PropertyValue {
  param([object]$Object, [string]$Name, [object]$Default = $null)
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Assert-PostRegistration {
  param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @())
  if (-not $Condition) { throw "235 post-registration audit blocked: $Detail" }
  $script:assertions++
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) })
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 40), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$result = $null
$exitCode = 0
try {
  $statePath = 'tools/legado-compat/state/full-source-validation-state.json'
  $objectivePath = 'tools/legado-compat/state/refactor-objective.json'
  $targetPath = 'tools/legado-compat/evidence/r3-actual-docs-source-refactor-target-20260809-235-text-whitespace/target.json'
  $auditPath = 'tools/legado-compat/evidence/r3-jsoup-text-whitespace-235-static-audit-20260809/static-audit.json'
  $registrationPath = 'tools/legado-compat/evidence/r3-jsoup-text-whitespace-235-static-audit-20260809/registration.json'
  $sourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-text-whitespace-source-fix-20260809.json'
  $contractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-text-whitespace-20260809.json'
  $objectiveDocumentPath = 'docs/analysis/Legado书源V2源码重构持续目标.md'
  $governancePath = 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
  $ledgerPath = 'docs/analysis/Legado书源引擎兼容推进台账.md'
  $indexPath = 'docs/analysis/Legado书源引擎证据索引.md'
  $diffPath = 'docs/analysis/Legado书源引擎差分摘要.md'
  $issueId = 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
  $revision = '2026-08-09-actual-docs-source-refactor-continuation-jsoup-text-whitespace-235-032'
  $hash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
  $commit = '95973d186b147fb9ab43a9240021d688e4304fbd'

  $state = Read-StrictJson -RelativePath $statePath
  $objective = Read-StrictJson -RelativePath $objectivePath
  $target = Read-StrictJson -RelativePath $targetPath
  $audit = Read-StrictJson -RelativePath $auditPath
  $registration = Read-StrictJson -RelativePath $registrationPath
  $sourceFix = Read-StrictJson -RelativePath $sourceFixPath
  $contract = Read-StrictJson -RelativePath $contractPath

  Assert-PostRegistration ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $hash -and [string]$state.baseline.legadoCommit -eq $commit) 'baseline' 'Machine baseline remains fixed.' @($statePath)
  Assert-PostRegistration ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq $issueId -and [string]$state.governance.status -eq 'running') 'queue' 'Only issue 235 remains the active governance issue.' @($statePath)
  Assert-PostRegistration ([string]$target.targetRevision -eq $revision -and [string]$objective.targetRevision -eq $revision -and [string]$target.currentSubstage -eq '235-TRANSITION-PRECHECK') 'stage' 'Target and objective are at revision 032 and the transition precheck.' @($targetPath, $objectivePath)
  $targetStatuses = @($target.plan | Where-Object { [string]$_.id -in @('235-WS-01', '235-WS-02', '235-WS-03', '235-WS-04') } | ForEach-Object { [string]$_.status })
  Assert-PostRegistration ($targetStatuses.Count -eq 4 -and @($targetStatuses | Where-Object { $_ -ne 'completed' }).Count -eq 0 -and [string]$target.staticAuditStatus -eq 'passed_static_only') 'target_plan' 'WS-01 through WS-04 are completed only as static source stages.' @($targetPath, $auditPath)
  $objectiveStatuses = @($objective.continuationPlan | Where-Object { [string]$_.id -in @('235-TP-03', '235-WS-04') } | ForEach-Object { [string]$_.status })
  Assert-PostRegistration ($objectiveStatuses.Count -eq 2 -and @($objectiveStatuses | Where-Object { $_ -ne 'completed' }).Count -eq 0 -and [string]$objective.nextAction -like '审核 235→236*') 'objective_plan' 'TP-03/WS-04 are closed and the next action is the 235→236 precheck.' @($objectivePath)
  Assert-PostRegistration ([string]$audit.status -eq 'passed' -and -not [bool]$audit.semanticMatchAllowed -and @($audit.runtimeActionsPerformed).Count -eq 0 -and [string]$registration.status -eq 'registered' -and -not [bool]$registration.semanticMatchAllowed -and @($registration.runtimeActionsPerformed).Count -eq 0) 'static_only' 'Audit and registration contain no runtime or semantic-match claim.' @($auditPath, $registrationPath)
  Assert-PostRegistration ([string]$contract.status -eq 'passed' -and [int]$contract.assertions -eq 16 -and -not [bool]$contract.semanticMatchAllowed) 'contract' 'The 16-assertion whitespace contract remains the only contract result.' @($contractPath)

  foreach ($relativePath in @($sourceFix.changedPaths)) {
    $sourcePath = Get-RepoPath -RelativePath ([string]$relativePath)
    $currentHash = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToUpperInvariant()
    $expectedSourceHash = [string](Get-PropertyValue -Object $sourceFix.currentHeadHashes -Name ([string]$relativePath) -Default '')
    Assert-PostRegistration ($currentHash -eq $expectedSourceHash) ('head_' + ([string]$relativePath).Replace('/', '_')) ('Current source hash remains bound: ' + [string]$relativePath) @($sourceFixPath, [string]$relativePath)
  }

  $issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId }) | Select-Object -First 1
  $issueEvidence = @($issue.evidencePaths | ForEach-Object { [string]$_ })
  Assert-PostRegistration ([string]$issue.status -eq 'verifying' -and $issueEvidence -contains $auditPath -and $issueEvidence -contains $registrationPath -and [string]$issue.summary -like '235-WS-04 静态审计完成*') 'issue_evidence' 'Machine issue status and evidence include the completed WS-04 audit.' @($statePath, $auditPath, $registrationPath)

  $objectiveDocument = Read-StrictText -RelativePath $objectiveDocumentPath
  $governanceDocument = Read-StrictText -RelativePath $governancePath
  $ledger = Read-StrictText -RelativePath $ledgerPath
  $index = Read-StrictText -RelativePath $indexPath
  $diff = Read-StrictText -RelativePath $diffPath
  Assert-PostRegistration ($objectiveDocument.Contains('`235-WS-04` 静态证据与文档审计已完成；唯一下一步为 235→236 静态转移前置门禁，236 尚未激活。') -and $objectiveDocument.Contains($revision)) 'objective_document' 'Objective document reflects the transition precheck and revision 032.' @($objectiveDocumentPath)
  Assert-PostRegistration ($governanceDocument.Contains('235-WS-04 静态审计完成') -and $governanceDocument.Contains('下一步只审核 235→236 静态转移前置条件')) 'governance_document' 'Governance mirror and narrative reflect WS-04 completion.' @($governancePath)
  Assert-PostRegistration ($ledger.Contains('活跃任务：COMPAT-006') -and $ledger.Contains('持续治理台账 | running') -and $index.Contains($auditPath) -and $diff.Contains($auditPath)) 'document_evidence' 'Ledger reflects the active governance task; evidence index and diff summary contain the exact audit path.' @($ledgerPath, $indexPath, $diffPath)

  $historical = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/r3-jsoup-text-pseudo-235-post-registration-20260809/post-registration-consistency.json'
  Assert-PostRegistration ([string]$historical.targetRevision -ne $revision -and [string]$historical.status -eq 'passed') 'historical_preserved' 'The historical revision-031 post-registration evidence remains distinct and is not reused as current evidence.' @('tools/legado-compat/evidence/r3-jsoup-text-pseudo-235-post-registration-20260809/post-registration-consistency.json')

  $scriptPaths = @('tools/legado-compat/Test-LegadoR3TextPseudoWhitespace235StaticAudit.ps1', 'tools/legado-compat/Register-LegadoR3TextPseudoWhitespace235StaticAudit.ps1', 'tools/legado-compat/Test-LegadoR3TextPseudoWhitespace235PostRegistrationAudit.ps1')
  foreach ($relativePath in $scriptPaths) {
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile((Get-RepoPath -RelativePath $relativePath), [ref]$null, [ref]$parseErrors) | Out-Null
    Assert-PostRegistration ($null -ne $parseErrors -and $parseErrors.Count -eq 0) ('ast_' + $relativePath.Replace('/', '_')) ('PowerShell AST parses: ' + $relativePath) @($relativePath)
  }

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_jsoup_text_whitespace_235_post_registration_audit'
    status = 'passed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    objectiveId = [string]$objective.objectiveId
    targetRevision = $revision
    issueId = $issueId
    baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $hash; legadoCommit = $commit }
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_235_ws04_post_registration_static_only;235_verifying;235_to_236_precheck_pending;R4_deferred'
    nextAction = [string]$objective.nextAction
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_jsoup_text_whitespace_235_post_registration_audit'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_235_ws04_post_registration_static_only;235_verifying;235_to_236_precheck_pending;R4_deferred'
  }
}

Write-AtomicJson -Path $outputFullPath -Value $result
$result | ConvertTo-Json -Depth 40
if ($exitCode -ne 0) { exit $exitCode }
