[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$RunId = 'r3-jsoup-text-pseudo-235-post-registration-20260809',
  [string]$OutputPath = '',
  [string]$GateEvidencePath = 'tools/legado-compat/evidence/r3-jsoup-regex-234-to-text-pseudo-235-transition-20260809/transition-consistency.json',
  [string]$RegistrationEvidencePath = 'tools/legado-compat/evidence/r3-jsoup-regex-234-to-text-pseudo-235-transition-20260809/registration.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$evidenceRoot = [System.IO.Path]::GetFullPath((Join-Path $RepositoryRoot 'tools\legado-compat\evidence')).TrimEnd('\') + '\'
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $evidenceRoot (Join-Path $RunId 'post-registration-consistency.json')
}
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
if (-not $outputFullPath.StartsWith($evidenceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'post-registration evidence must remain under the evidence directory.'
}
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required JSON is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  try { return ($strictUtf8.GetString($bytes) | ConvertFrom-Json) }
  catch { throw "invalid JSON: $RelativePath; $($_.Exception.Message)" }
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required text is missing: $RelativePath" }
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

function Get-Issue {
  param([object[]]$Issues, [string]$Id)
  foreach ($issue in $Issues) {
    if ([string](Get-PropertyValue -Object $issue -Name 'id') -eq $Id) { return $issue }
  }
  return $null
}

function Contains-Evidence {
  param([object]$Issue, [string]$Path)
  foreach ($value in @((Get-PropertyValue -Object $Issue -Name 'evidencePaths' -Default @()))) {
    if ([string]$value -eq $Path) { return $true }
  }
  return $false
}

function Assert-Gate {
  param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @())
  if (-not $Condition) { throw "post-registration consistency blocked: $Detail" }
  $script:assertions++
  [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) })
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 40), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

$baseline = $null
$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
  $objective = Read-StrictJson -RelativePath 'tools/legado-compat/state/refactor-objective.json'
  $gate = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/r3-jsoup-regex-234-to-text-pseudo-235-transition-20260809/transition-consistency.json'
  $registration = Read-StrictJson -RelativePath 'tools/legado-compat/evidence/r3-jsoup-regex-234-to-text-pseudo-235-transition-20260809/registration.json'
  $baseline = $state.baseline
  $baselineEvidence = @('tools/legado-compat/state/full-source-validation-state.json','tools/legado-compat/state/refactor-objective.json')
  Assert-Gate ([int]$baseline.sourceCount -eq 458 -and [string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'baseline' 'fixed 458-source, package hash and Legado commit are unchanged.' $baselineEvidence
  Assert-Gate ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -and [string]$state.governance.status -eq 'running') 'machine_queue' 'machine governance queue is active on 235.' $baselineEvidence

  $issues = @($state.governance.issues)
  $issue233 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION'
  $issue234 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
  $issue235 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
  $issue236 = Get-Issue -Issues $issues -Id 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR'
  Assert-Gate ($null -ne $issue233 -and [string]$issue233.status -eq 'verifying' -and $null -ne $issue234 -and [string]$issue234.status -eq 'verifying' -and $null -ne $issue235 -and [string]$issue235.status -eq 'verifying' -and $null -ne $issue236 -and [string]$issue236.status -eq 'verifying') 'queue_statuses' '233, 234, 235 and 236 retain verifying-only source-closure statuses.' @('tools/legado-compat/state/full-source-validation-state.json')
  Assert-Gate ([string]$objective.authority.activeIssueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -and [string]$objective.executionTarget.currentIssue -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -and @($objective.executionTarget.nextIssues) -contains 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR') 'objective_queue' 'objective authority, current issue and next candidate match machine state.' @('tools/legado-compat/state/refactor-objective.json')
  Assert-Gate ([string]$objective.targetRevision -eq '2026-08-09-actual-docs-source-refactor-continuation-jsoup-text-pseudo-235-031' -and @($objective.continuationPlan | Where-Object { [string]$_.id -eq '235-TP-01' -and [string]$_.status -eq 'completed' }).Count -eq 1 -and @($objective.continuationPlan | Where-Object { [string]$_.id -eq '235-TP-03' -and [string]$_.status -eq 'in_progress' }).Count -eq 1) 'objective_plan' 'objective revision and 235 continuation plan are current.' @('tools/legado-compat/state/refactor-objective.json')
  Assert-Gate ([string]$gate.status -eq 'passed' -and [int]$gate.assertions -eq 26 -and [string]$gate.transition.fromIssue -eq 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR' -and [string]$gate.transition.toIssue -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -and [string]$gate.transition.nextCandidateAfterRegistration -eq 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR' -and -not [bool]$gate.semanticMatchAllowed -and @($gate.runtimeActionsPerformed).Count -eq 0) 'transition_gate' '234→235 gate is a 26-assertion static-only pass.' @('tools/legado-compat/evidence/r3-jsoup-regex-234-to-text-pseudo-235-transition-20260809/transition-consistency.json')
  Assert-Gate ([string]$registration.status -eq 'registered' -and [string]$registration.previousIssueId -eq 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR' -and [string]$registration.issueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS' -and [string]$registration.nextIssueId -eq 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR' -and -not [bool]$registration.semanticMatchAllowed -and @($registration.runtimeActionsPerformed).Count -eq 0) 'registration_evidence' 'registration is bound to 234→235→236 with no runtime claim.' @('tools/legado-compat/evidence/r3-jsoup-regex-234-to-text-pseudo-235-transition-20260809/registration.json')

  $requiredEvidence = @($GateEvidencePath, $RegistrationEvidencePath, 'tools/legado-compat/evidence/v2-jsoup-text-pseudo-selectors-source-fix-20260807.json', 'tools/legado-compat/evidence/contract-legado-jsoup-text-pseudo-selectors.json', 'tools/legado-compat/fixtures/legado-jsoup-text-pseudo-selectors.json')
  foreach ($path in $requiredEvidence) {
    Assert-Gate (Contains-Evidence -Issue $issue235 -Path $path) ('evidence_' + $path.Replace('/','_')) ('235 evidence path is registered: ' + $path) @('tools/legado-compat/state/full-source-validation-state.json')
  }

  $objectiveDocument = Read-StrictText -RelativePath 'docs/analysis/Legado书源V2源码重构持续目标.md'
  $governanceDocument = Read-StrictText -RelativePath 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
  Assert-Gate ($objectiveDocument.Contains('当前唯一活动源码锚点为 `ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS`') -and $objectiveDocument.Contains('下一候选唯一为 `ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR`') -and -not $objectiveDocument.Contains('下一步只允许先执行 234→235 专用静态转移门禁') -and -not $objectiveDocument.Contains('在 234→235 专用静态转移门禁通过前不激活 235')) 'objective_document' 'objective Markdown has no stale pre-registration queue claims.' @('docs/analysis/Legado书源V2源码重构持续目标.md')
  Assert-Gate ($governanceDocument.Contains('当前唯一活动根因议题为 `ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS`') -and $governanceDocument.Contains('235 的注册脚本具备重启后幂等恢复')) 'governance_document' 'governance narrative and mirror point to 235.' @('tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md')

  $changedPaths = @('entry/src/main/ets/libs/htmlparser/Matcher.ets','entry/src/main/ets/libs/htmlparser/HTMLElement.ets','entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets','entry/src/main/resources/rawfile/legado_runtime.html','legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt')
  foreach ($path in $changedPaths) {
    $filePath = Get-RepoPath -RelativePath $path
    $bytes = [System.IO.File]::ReadAllBytes($filePath)
    Assert-Gate (-not ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)) ('no_bom_' + $path.Replace('/','_')) ('source has no UTF-8 BOM: ' + $path) @($path)
    $currentHash = (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToUpperInvariant()
    $expectedHash = [string](Get-PropertyValue -Object $gate.candidateCurrentHeadAudit.currentHeadHashes -Name $path)
    Assert-Gate ($expectedHash.Length -gt 0 -and $currentHash -eq $expectedHash) ('head_hash_' + $path.Replace('/','_')) ('current HEAD hash matches the 235 transition audit: ' + $path) @($GateEvidencePath)
  }
  $scriptPath = Get-RepoPath -RelativePath 'tools/legado-compat/Register-LegadoR3JsoupRegex234ToTextPseudo235Transition.ps1'
  $parseErrors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$parseErrors) | Out-Null
  Assert-Gate ($parseErrors.Count -eq 0) 'registration_script_ast' 'registration script parses under PowerShell AST.' @('tools/legado-compat/Register-LegadoR3JsoupRegex234ToTextPseudo235Transition.ps1')

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_jsoup_text_pseudo_235_post_registration_consistency'
    status = 'passed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    objectiveId = [string]$objective.objectiveId
    targetRevision = [string]$objective.targetRevision
    baseline = [pscustomobject][ordered]@{ sourceCount = [int]$baseline.sourceCount; sourcePackageSha256 = [string]$baseline.sourcePackageSha256; legadoCommit = [string]$baseline.legadoCommit }
    activeIssueId = 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
    nextIssueId = 'ISSUE-COMPAT-236-JSOUP-HAS-PSEUDO-SELECTOR'
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_post_registration_static_consistency_only;R4_runtime_build_device_and_legado_diff_deferred'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_jsoup_text_pseudo_235_post_registration_consistency'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_post_registration_static_consistency_only;R4_runtime_build_device_and_legado_diff_deferred'
  }
}

Write-AtomicJson -Path $outputFullPath -Value $result
$result | ConvertTo-Json -Depth 40
if ($exitCode -ne 0) { exit $exitCode }
