[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-governance-active-issue-section-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0

function Get-RepoPath([string]$RelativePath) { return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }

function Read-StrictText([string]$RelativePath) {
  $path = Get-RepoPath $RelativePath
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $utf8Strict.GetString($bytes)
}

function Assert-Contract([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "CONTRACT_FAILED:$Message" }
  $script:assertions++
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepoPath $RelativePath
  $directory = Split-Path -Parent $path
  [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 30), $utf8NoBom)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Get-PropertyValue([object]$Object, [string]$Name, [object]$Default = $null) {
  if ($null -eq $Object) { return $Default }
  $property = $Object.PSObject.Properties[$Name]
  if ($null -eq $property -or $null -eq $property.Value) { return $Default }
  return $property.Value
}

function Read-ImplementationText([string]$RelativePath) {
  $path = Get-RepoPath $RelativePath
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    return $utf8Strict.GetString($bytes, 3, $bytes.Length - 3)
  }
  return $utf8Strict.GetString($bytes)
}

$fixtureRelative = 'tools/legado-compat/fixtures/legado-governance-active-issue-section-drift.json'
$stateRelative = 'tools/legado-compat/state/full-source-validation-state.json'
$ledgerRelative = 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'
$implementationRelative = 'tools/legado-compat/Invoke-LegadoCompatibility.ps1'
$fixture = Read-StrictText $fixtureRelative | ConvertFrom-Json
$state = Read-StrictText $stateRelative | ConvertFrom-Json
$ledger = Read-StrictText $ledgerRelative
$implementation = Read-ImplementationText $implementationRelative
$baseline = $state.baseline
Assert-Contract ([int]$baseline.sourceCount -eq 458) 'source count baseline drifted.'
Assert-Contract ([string]$baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'source package hash baseline drifted.'
Assert-Contract ([string]$baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'Legado commit baseline drifted.'
$governance = $state.governance
$activeTaskId = [string](Get-PropertyValue $governance 'activeTaskId' '')
$activeIssueId = [string](Get-PropertyValue $governance 'activeIssueId' '')
$activeIssue = @($governance.issues | Where-Object { [string](Get-PropertyValue $_ 'id' '') -eq $activeIssueId }) | Select-Object -First 1
Assert-Contract ($activeTaskId.Length -gt 0 -and $activeIssueId.Length -gt 0 -and $null -ne $activeIssue) 'machine active task/issue binding is incomplete.'
$activeStatus = [string](Get-PropertyValue $activeIssue 'status' 'unknown')
$summary = [string](Get-PropertyValue $activeIssue 'summary' '')
$closeCondition = [string](Get-PropertyValue $activeIssue 'closeCondition' '')
$startMarker = [string]$fixture.startMarker
$endMarker = [string]$fixture.endMarker
Assert-Contract (([regex]::Matches($ledger, [regex]::Escape($startMarker))).Count -eq 1) 'current issue start marker count must be one.'
Assert-Contract (([regex]::Matches($ledger, [regex]::Escape($endMarker))).Count -eq 1) 'current issue end marker count must be one.'
$startIndex = $ledger.IndexOf($startMarker, [System.StringComparison]::Ordinal)
$endIndex = $ledger.IndexOf($endMarker, [System.StringComparison]::Ordinal)
Assert-Contract ($endIndex -gt $startIndex) 'current issue markers must be ordered.'
$currentBlock = $ledger.Substring($startIndex, $endIndex + $endMarker.Length - $startIndex)
Assert-Contract ($currentBlock.Contains(('`{0}`' -f $activeTaskId))) 'current block does not project active task.'
Assert-Contract ($currentBlock.Contains(('`{0}`' -f $activeIssueId))) 'current block does not project active issue.'
Assert-Contract (-not $currentBlock.Contains('ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH')) 'current block still projects the historical 037 issue.'
Assert-Contract ($currentBlock.Contains(('（{0}）' -f $activeStatus))) 'current block does not project active status.'
Assert-Contract ($currentBlock.Contains($summary)) 'current block does not project active issue summary.'
Assert-Contract ($currentBlock.Contains($closeCondition)) 'current block does not project close condition.'
$semanticMatchAllowed = [bool](Get-PropertyValue $governance 'semanticMatchAllowed' $false)
$semanticMatchToken = ('`semanticMatchAllowed={0}`' -f $semanticMatchAllowed.ToString().ToLowerInvariant())
Assert-Contract ($currentBlock.Contains($semanticMatchToken) -and -not $semanticMatchAllowed) 'semantic match gate is not explicitly false.'
$outside = $ledger.Substring(0, $startIndex) + $ledger.Substring($endIndex + $endMarker.Length)
Assert-Contract ($outside.Contains([string]$fixture.historicalTokenOutsideGeneratedSection)) 'historical queue text was removed from outside the generated block.'
Assert-Contract ($implementation.Contains('function Update-CurrentSourceIssueSection')) 'refresh implementation lacks current issue projection function.'
Assert-Contract ($implementation.Contains('Update-CurrentSourceIssueSection -FullState $fullSourceValidationState')) 'refresh path does not invoke current issue projection.'
$evidence = [ordered]@{
  schemaVersion = 1
  kind = 'legado_governance_active_issue_section_contract'
  status = 'passed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  issueId = [string]$fixture.issueId
  activeTaskId = $activeTaskId
  activeIssueId = $activeIssueId
  activeIssueStatus = $activeStatus
  baseline = [ordered]@{
    sourceCount = [int]$baseline.sourceCount
    sourcePackageSha256 = [string]$baseline.sourcePackageSha256
    legadoCommit = [string]$baseline.legadoCommit
  }
  assertions = $script:assertions
  checks = @('marker uniqueness and ordering', 'active task and issue projection', 'status/summary/close-condition projection', 'semanticMatchAllowed=false projection', 'historical text preservation', 'atomic refresh implementation binding')
  failureWitnessPath = 'tools/legado-compat/evidence/contract-legado-governance-active-issue-section-drift-pre-fix-20260809.json'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = [string]$fixture.verificationPolicy
}
Write-AtomicJson $OutputPath $evidence
$evidence | ConvertTo-Json -Depth 30
