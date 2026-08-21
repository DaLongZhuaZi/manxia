[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-trace-nested-array-preservation.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-trace-nested-array-preservation-pre-fix-20260809.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$sourceCount = 458
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-242-TRACE-BRIDGE-PRESERVATION'

function Get-RepoPath([string]$RelativePath) {
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText([string]$RelativePath) {
  $path = Get-RepoPath $RelativePath
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes)
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepoPath $RelativePath
  [System.IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 40), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

function Assert-Witness([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "Trace nested-array pre-fix witness failed: $Message" }
}

function Get-ClassSegment([string]$Source, [string]$ClassName) {
  $start = $Source.IndexOf("export class $ClassName", [System.StringComparison]::Ordinal)
  if ($start -lt 0) { throw "Class not found: $ClassName" }
  $next = $Source.IndexOf("`nexport class ", $start + 1, [System.StringComparison]::Ordinal)
  if ($next -lt 0) { return $Source.Substring($start) }
  return $Source.Substring($start, $next - $start)
}

$state = Read-StrictText 'tools/legado-compat/state/full-source-validation-state.json' | ConvertFrom-Json
$fixture = Read-StrictText $FixturePath | ConvertFrom-Json
$runtime = Read-StrictText ([string]$fixture.runtimePath)
Assert-Witness ([int]$state.baseline.sourceCount -eq $sourceCount -and
  [string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and
  [string]$state.baseline.legadoCommit -eq $legadoCommit) 'frozen baseline drifted.'
Assert-Witness ([string]$state.governance.activeIssueId -eq $issueId) '242 must remain the active source-closure issue.'
Assert-Witness ([string]$fixture.contract -eq 'legado_trace_nested_array_preservation') 'nested-array fixture contract changed.'

$fields = New-Object 'System.Collections.Generic.List[object]'
foreach ($class in @($fixture.classes)) {
  $segment = Get-ClassSegment $runtime ([string]$class.name)
  foreach ($field in @($class.fields)) {
    $directAssignment = [string]$field.directAssignment
    $defensiveAssignment = [string]$field.defensiveAssignment
    Assert-Witness ($segment.Contains($directAssignment)) ("pre-fix direct assignment missing for {0}.{1}." -f [string]$class.name, [string]$field.name)
    Assert-Witness (-not $segment.Contains($defensiveAssignment)) ("pre-fix defensive copy unexpectedly exists for {0}.{1}." -f [string]$class.name, [string]$field.name)
    [void]$fields.Add([pscustomobject]@{ className = [string]$class.name; fieldName = [string]$field.name })
  }
}

$result = [ordered]@{
  schemaVersion = 1
  kind = 'legado_trace_nested_array_preservation_pre_fix_contract'
  status = 'failed_static_only'
  issueId = $issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  runtimePath = [string]$fixture.runtimePath
  fixturePath = $FixturePath
  observedBeforeFix = [ordered]@{
    fields = $fields.ToArray()
    consequence = 'Request, response and nested bridge metadata arrays could be mutated after construction, changing the trace graph that later serialization consumes.'
  }
  reproduction = 'Inspect each listed constructor and append to the producer array after construction; the corresponding object field changes because it retains the same reference.'
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  runtimeRegression = 'not_run'
  deviceRegression = 'not_run'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 30
