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
  $OutputPath = Join-Path $evidenceRoot (Join-Path $RunId 'static-audit.json')
}
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
if (-not $outputFullPath.StartsWith($evidenceRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
  throw 'Static audit output must remain under tools/legado-compat/evidence.'
}

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
  if ($fullPath.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    return $fullPath.Substring($prefix.Length).Replace('\', '/')
  }
  return $fullPath.Replace('\', '/')
}

function Read-StrictBytes {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Required file is missing: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $(Get-RelativePath -Path $Path)"
  }
  return $bytes
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  return $strictUtf8.GetString((Read-StrictBytes -Path $path))
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $text = Read-StrictText -RelativePath $RelativePath
  try { return ($text | ConvertFrom-Json) }
  catch { throw "Invalid JSON: $RelativePath; $($_.Exception.Message)" }
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
  if (-not $Condition) { throw "235-WS-04 static audit blocked: $Detail" }
  $script:assertions++
  [void]$script:checks.Add([pscustomobject][ordered]@{
      id = $Id
      status = 'passed'
      detail = $Detail
      evidencePaths = @($Evidence)
    })
}

function Add-PathCheck {
  param([string]$RelativePath, [bool]$RequireJson = $false)
  $absolute = Get-RepoPath -RelativePath $RelativePath
  $bytes = Read-StrictBytes -Path $absolute
  if ($RequireJson) {
    try { $null = ($strictUtf8.GetString($bytes) | ConvertFrom-Json) }
    catch { throw "Invalid JSON: $RelativePath; $($_.Exception.Message)" }
  }
  Assert-Audit $true ('utf8_' + $RelativePath.Replace('/', '_')) ('UTF-8 without BOM and readable: ' + $RelativePath) @($RelativePath)
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
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
  $preFixPath = 'tools/legado-compat/evidence/contract-legado-jsoup-text-whitespace-pre-fix-20260809.json'
  $consumerPath = 'tools/legado-compat/evidence/contract-legado-jsoup-text-whitespace-consumers-pre-fix-20260809.json'
  $contractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-text-whitespace-20260809.json'
  $sourceFixPath = 'tools/legado-compat/evidence/v2-jsoup-text-whitespace-source-fix-20260809.json'
  $transitionPath = 'tools/legado-compat/evidence/r3-jsoup-regex-234-to-text-pseudo-235-transition-20260809/transition-consistency.json'
  $registrationPath = 'tools/legado-compat/evidence/r3-jsoup-regex-234-to-text-pseudo-235-transition-20260809/registration.json'
  $objectiveDocumentPath = 'docs/analysis/Legado书源V2源码重构持续目标.md'
  $governancePath = 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'

  $state = Read-StrictJson -RelativePath $statePath
  $objective = Read-StrictJson -RelativePath $objectivePath
  $target = Read-StrictJson -RelativePath $targetPath
  $preFix = Read-StrictJson -RelativePath $preFixPath
  $consumer = Read-StrictJson -RelativePath $consumerPath
  $contract = Read-StrictJson -RelativePath $contractPath
  $sourceFix = Read-StrictJson -RelativePath $sourceFixPath
  $transition = Read-StrictJson -RelativePath $transitionPath
  $registration = Read-StrictJson -RelativePath $registrationPath

  $baseline = $state.baseline
  $expectedHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
  $expectedCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
  $expectedRevision = '2026-08-09-actual-docs-source-refactor-continuation-jsoup-text-whitespace-235-032'
  $issueId = 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'

  Assert-Audit ([int]$baseline.sourceCount -eq 458 -and [string]$baseline.sourcePackageSha256 -eq $expectedHash -and [string]$baseline.legadoCommit -eq $expectedCommit) 'baseline' 'The frozen 458-source, package hash and Legado commit are unchanged.' @($statePath)
  Assert-Audit ([string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq $issueId -and [string]$state.governance.status -eq 'running') 'queue' 'Machine governance queue remains COMPAT-006 on issue 235.' @($statePath)
  Assert-Audit ([string]$objective.targetRevision -eq $expectedRevision -and [string]$target.targetRevision -eq $expectedRevision) 'revision' 'Objective and target are bound to the current actual-docs revision 032.' @($objectivePath, $targetPath)
  Assert-Audit ([string]$target.status -eq 'active' -and [string]$target.issueId -eq $issueId -and [string]$target.currentSubstage -eq '235-WS-04') 'target_stage' 'Target is active and currently executing 235-WS-04.' @($targetPath)

  $targetWs03 = @($target.plan | Where-Object { [string]$_.id -eq '235-WS-03' }) | Select-Object -First 1
  $targetWs04 = @($target.plan | Where-Object { [string]$_.id -eq '235-WS-04' }) | Select-Object -First 1
  Assert-Audit ($null -ne $targetWs03 -and [string]$targetWs03.status -eq 'completed' -and $null -ne $targetWs04 -and [string]$targetWs04.status -eq 'in_progress') 'target_plan' '235-WS-03 is closed and 235-WS-04 is the only active whitespace substage.' @($targetPath)

  $objectiveWs03 = @($objective.continuationPlan | Where-Object { [string]$_.id -eq '235-WS-03' }) | Select-Object -First 1
  $objectiveWs04 = @($objective.continuationPlan | Where-Object { [string]$_.id -eq '235-WS-04' }) | Select-Object -First 1
  Assert-Audit ($null -ne $objectiveWs03 -and [string]$objectiveWs03.status -eq 'completed' -and $null -ne $objectiveWs04 -and [string]$objectiveWs04.status -eq 'in_progress' -and [string]$objective.nextAction -like '执行 235-WS-04*') 'objective_plan' 'Machine objective points to the same 235-WS-04 audit stage.' @($objectivePath)

  Assert-Audit ([string]$preFix.status -eq 'failed' -and [string]$consumer.status -eq 'failed') 'failure_witnesses' 'Pre-fix and consumer failure witnesses remain failed and preserved.' @($preFixPath, $consumerPath)
  Assert-Audit ([string]$contract.status -eq 'passed' -and [int]$contract.assertions -eq 16 -and -not [bool]$contract.semanticMatchAllowed -and @($contract.runtimeActionsPerformed).Count -eq 0) 'static_contract' 'The 16-assertion whitespace contract passed without runtime actions or semantic-match claims.' @($contractPath)
  Assert-Audit ([string]$sourceFix.status -eq 'source_closed' -and -not [bool]$sourceFix.semanticMatchAllowed -and @($sourceFix.runtimeActionsPerformed).Count -eq 0) 'source_fix' 'Source-fix evidence is static-only and keeps the issue in verifying.' @($sourceFixPath)
  Assert-Audit ([string]$sourceFix.baseline.sourcePackageSha256 -eq $expectedHash -and [string]$sourceFix.baseline.legadoCommit -eq $expectedCommit -and [int]$sourceFix.baseline.sourceCount -eq 458) 'source_fix_baseline' 'Source-fix evidence is bound to the frozen baseline.' @($sourceFixPath)

  $jsonPaths = @($statePath, $objectivePath, $targetPath, $preFixPath, $consumerPath, $contractPath, $sourceFixPath, $transitionPath, $registrationPath)
  foreach ($path in $jsonPaths) { Add-PathCheck -RelativePath $path -RequireJson $true }
  $textPaths = @($objectiveDocumentPath, $governancePath)
  foreach ($path in $textPaths) { Add-PathCheck -RelativePath $path -RequireJson $false }

  $changedPaths = @($sourceFix.changedPaths)
  Assert-Audit ($changedPaths.Count -eq 5) 'changed_path_count' 'Source-fix evidence contains the five intended source paths.' @($sourceFixPath)
  foreach ($relativePath in $changedPaths) {
    $absolutePath = Get-RepoPath -RelativePath ([string]$relativePath)
    $bytes = Read-StrictBytes -Path $absolutePath
    $currentHash = (Get-FileHash -LiteralPath $absolutePath -Algorithm SHA256).Hash.ToUpperInvariant()
    $expectedSourceHash = [string](Get-PropertyValue -Object $sourceFix.currentHeadHashes -Name ([string]$relativePath) -Default '')
    Assert-Audit ($expectedSourceHash.Length -eq 64 -and $currentHash -eq $expectedSourceHash) ('head_hash_' + ([string]$relativePath).Replace('/', '_')) ('Current HEAD hash matches source-fix evidence: ' + [string]$relativePath) @($sourceFixPath, [string]$relativePath)
  }

  $scriptPaths = @(
    'tools/legado-compat/Register-LegadoR3TextPseudoWhitespace235SourceFix.ps1',
    'tools/legado-compat/Register-LegadoR3TextPseudoWhitespace235FailureWitness.ps1',
    'tools/legado-compat/Register-LegadoR3TextPseudoWhitespace235ConsumerContract.ps1',
    'tools/legado-compat/Test-LegadoJsoupTextWhitespacePreFixContract.ps1',
    'tools/legado-compat/Test-LegadoJsoupTextWhitespaceConsumerContract.ps1',
    'tools/legado-compat/Test-LegadoJsoupTextWhitespaceContract.ps1'
  )
  foreach ($relativePath in $scriptPaths) {
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile((Get-RepoPath -RelativePath $relativePath), [ref]$null, [ref]$parseErrors) | Out-Null
    Assert-Audit ($null -ne $parseErrors -and $parseErrors.Count -eq 0) ('ps_ast_' + $relativePath.Replace('/', '_')) ('PowerShell AST parses: ' + $relativePath) @($relativePath)
  }

  $objectiveDocument = Read-StrictText -RelativePath $objectiveDocumentPath
  $governanceDocument = Read-StrictText -RelativePath $governancePath
  Assert-Audit ($objectiveDocument.Contains($expectedRevision) -and $objectiveDocument.Contains('当前子阶段：`235-WS-01`/`235-WS-02` 失败证据与消费者矩阵已登记，`235-WS-03` 源码闭合；唯一下一步为 `235-WS-04` 静态证据与文档审计。')) 'objective_document' 'Objective Markdown is bound to revision 032 and records WS-04 as the sole next action.' @($objectiveDocumentPath)
  Assert-Audit ($governanceDocument.Contains('activeIssue=`' + $issueId + '`') -and $governanceDocument.Contains('235-WS-03 源码闭合')) 'governance_document' 'Governance mirror retains issue 235 and the current WS-03 source-closure statement before WS-04 registration.' @($governancePath)

  $issue235 = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId }) | Select-Object -First 1
  $requiredIssueEvidence = @($targetPath, $preFixPath, $consumerPath, $contractPath, $sourceFixPath)
  foreach ($path in $requiredIssueEvidence) {
    $evidencePaths = @($issue235.evidencePaths | ForEach-Object { [string]$_ })
    Assert-Audit ($evidencePaths -contains $path) ('issue_evidence_' + $path.Replace('/', '_')) ('Issue 235 includes evidence path: ' + $path) @($statePath)
  }

  $sourceFixText = Read-StrictText -RelativePath $sourceFixPath
  Assert-Audit (-not ($sourceFixText -match '(?i)rawCookie|Set-Cookie|Authorization|password|token|account|正文')) 'privacy' 'Source-fix evidence contains no raw credentials, cookies, account data or正文.' @($sourceFixPath)
  $outputRelative = Get-RelativePath -Path $outputFullPath
  Assert-Audit ($outputFullPath.StartsWith($evidenceRoot, [System.StringComparison]::OrdinalIgnoreCase) -and $outputRelative -notmatch '(?i)full-source-v2-hypium-device($|\\|/)|effective-full-source-v2-hypium-device') 'evidence_isolation' 'WS-04 output is run-scoped under evidence and cannot overwrite canonical device evidence.' @($outputRelative)

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_jsoup_text_whitespace_235_static_audit'
    status = 'passed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    objectiveId = [string]$objective.objectiveId
    targetRevision = $expectedRevision
    issueId = $issueId
    baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $expectedHash; legadoCommit = $expectedCommit }
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    evidencePaths = @($targetPath, $preFixPath, $consumerPath, $contractPath, $sourceFixPath, $statePath, $objectivePath)
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_235_ws04_static_audit_only;runtime_build_device_and_legado_diff_deferred'
    nextAction = '235-WS-04 可登记完成；继续执行 235→236 静态转移前置门禁，不激活 236。'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_r3_jsoup_text_whitespace_235_static_audit'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    checks = $script:checks.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_235_ws04_static_audit_only;runtime_build_device_and_legado_diff_deferred'
  }
}

Write-AtomicJson -Path $outputFullPath -Value $result
$result | ConvertTo-Json -Depth 40
if ($exitCode -ne 0) { exit $exitCode }
