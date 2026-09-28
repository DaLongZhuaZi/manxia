[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-standard-pseudo-selector-mixed-descendant-direct-child-context.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-mixed-descendant-direct-child-post-fix-20260810.json',
  [string]$BackupPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets.bak_20260810_mixed_descendant_direct_child',
  [string]$OutputPath = 'tools/legado-compat/evidence/v2-jsoup-mixed-descendant-direct-child-current-head-audit-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }; return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); return $strictUtf8.GetString([System.IO.File]::ReadAllBytes((Get-RepoPath $Path))) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText -Path $Path | ConvertFrom-Json -Depth 100) }
function Assert-Audit { param([bool]$Condition, [string]$Message); if (-not $Condition) { throw "243 mixed-chain current-head audit failed: $Message" }; $script:assertions++ }
function Get-Hash { param([Parameter(Mandatory = $true)][string]$Path); return (Get-FileHash -LiteralPath (Get-RepoPath $Path) -Algorithm SHA256).Hash.ToUpperInvariant() }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; $temp = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temp -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) } } }

$state = Read-StrictJson -Path 'tools/legado-compat/state/full-source-validation-state.json'
$fixture = Read-StrictJson -Path $FixturePath
$contract = Read-StrictJson -Path $PostFixContractPath
$analyzerPath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$analyzer = Read-StrictText -Path $analyzerPath
$backup = Read-StrictText -Path $BackupPath

Assert-Audit ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and [string]$state.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'frozen baseline drifted.'
Assert-Audit ([string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and [string]$state.governance.status -eq 'running' -and -not [bool]$state.governance.semanticMatchAllowed) 'active issue or semantic gate drifted.'
Assert-Audit ([string]$fixture.issueId -eq 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS' -and @($fixture.cases).Count -eq 2 -and @($fixture.affectedSourceSet.sourceOrdinals) -contains 97) 'fixture binding drifted.'
Assert-Audit ([string]$contract.status -eq 'passed' -and @($contract.runtimeActionsPerformed).Count -eq 0 -and -not [bool]$contract.semanticMatchAllowed) 'post-fix contract is not static-only passed.'
Assert-Audit ($analyzer.Contains('let currentElements = this.findElementsBySingleSelector(html, firstSelector, effectiveContextHtml);')) 'current HEAD does not contain the mixed-chain fix.'
Assert-Audit (-not $analyzer.Contains('let currentElements = this.findElementsBySimpleSelector(html, firstSelector, effectiveContextHtml);')) 'current HEAD still contains the lossy call.'
Assert-Audit ($backup.Contains('let currentElements = this.findElementsBySimpleSelector(html, firstSelector, effectiveContextHtml);')) 'same-directory pre-fix backup does not preserve the failure state.'
Assert-Audit ((Get-Hash -Path $analyzerPath) -ne (Get-Hash -Path $BackupPath)) 'current HEAD and pre-fix backup unexpectedly have the same hash.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  kind = 'legado_jsoup_standard_pseudo_selector_mixed_descendant_direct_child_current_head_audit'
  issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  status = 'passed'
  assertions = $script:assertions
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  fixture = $FixturePath
  postFixContract = $PostFixContractPath
  changedPaths = @($analyzerPath)
  backupPath = $BackupPath
  hashes = [pscustomobject][ordered]@{ currentHead = Get-Hash -Path $analyzerPath; preFixBackup = Get-Hash -Path $BackupPath }
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
}
Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Depth 100
