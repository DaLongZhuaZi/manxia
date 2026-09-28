[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-text-own-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-text-own-context-pre-fix-20260810.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-text-own-context-post-fix-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/v2-jsoup-text-own-context-current-head-audit-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$script:assertions = 0

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }; return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "required file is missing: $Path" }; $bytes = [System.IO.File]::ReadAllBytes($resolved); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }; return $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100) }
function Assert-Audit { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 text own-context current-head audit failed: $Message" }; $script:assertions++ }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$contract = Read-StrictJson $PostFixContractPath
$bridgePath = 'entry/src/main/ets/libs/htmlparser/LegadoHtmlBridge.ets'
$elementPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$bridge = Read-StrictText $bridgePath
$element = Read-StrictText $elementPath
$issue = @($state.governance.issues | Where-Object { [string]$_.id -eq $issueId })[0]
$textStart = $bridge.IndexOf('  private findByTextInContext(context: HTMLElement, searchText: string): HTMLElement[] {')
$textEnd = $bridge.IndexOf("`r`n  /**", $textStart + 1)
if ($textEnd -lt 0) { $textEnd = $bridge.IndexOf("`n  /**", $textStart + 1) }
$textBody = if ($textStart -ge 0 -and $textEnd -gt $textStart) { $bridge.Substring($textStart, $textEnd - $textStart) } else { '' }

Assert-Audit ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Audit ([string]$state.governance.status -eq 'running' -and [string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) '243 queue or semantic gate drifted.'
Assert-Audit ($null -ne $issue -and [string]$issue.status -eq 'verifying') '243 must remain verifying.'
Assert-Audit ([string]$fixture.contract -eq 'legado_jsoup_text_rule_own_context' -and @($fixture.cases).Count -eq 4 -and [int]$fixture.affectedSourceSet.ruleOccurrenceCount -eq 144 -and [int]$fixture.affectedSourceSet.sourceCount -eq 96) 'text-own-context fixture or capability matrix drifted.'
Assert-Audit ([string]$failure.status -eq 'failed' -and [string]$contract.status -eq 'passed' -and @($failure.runtimeActionsPerformed).Count -eq 0 -and @($contract.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$failure.semanticMatchAllowed -and -not [bool]$contract.semanticMatchAllowed) 'static evidence transition is incomplete.'
Assert-Audit ($textBody.Contains("const allElements = context.select('*');") -and $textBody.Contains('if (elem.ownText.includes(searchText))') -and -not $textBody.Contains('context.getElementsByTagName') -and -not $textBody.Contains('elem.text.includes(searchText)')) 'current bridge still uses aggregate descendant text.'
Assert-Audit ($bridge.Contains('return this.findByTextInContext(this.root, searchText);') -and $element.Contains('  get ownText(): string {') -and $element.Contains('  select(selector: string): HTMLElement[] {')) 'current head does not retain root delegation, typed ownText and Jsoup-style selection entry.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'current_head_static_audit'
  issueId = $issueId
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  failureWitnessPath = $FailureWitnessPath
  postFixContractPath = $PostFixContractPath
  changedPaths = @($bridgePath)
  currentHeadSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $bridgePath)).Hash.ToUpperInvariant()
  assertions = $script:assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_text_own_context_current_head_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
}
Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Depth 100
