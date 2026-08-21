[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-no-space-direct-child-fast-path-context.json',
  [string]$PreFixSourcePath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets.bak_20260810_no_space_direct_child_fast_path',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-no-space-direct-child-fast-path-pre-fix-20260810.json'
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
$assertions = 0

function Get-RepoPath([string]$RelativePath) { return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictText([string]$RelativePath) {
  $path = Get-RepoPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing file: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}
function Read-StrictJson([string]$RelativePath) { return Read-StrictText $RelativePath | ConvertFrom-Json -Depth 100 }
function Assert-Witness([bool]$Condition, [string]$Message) { if (-not $Condition) { throw "243 no-space direct-child failure witness failed: $Message" }; $script:assertions++ }
function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepoPath $RelativePath
  $temp = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try { [System.IO.File]::WriteAllText($temp, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temp -Destination $path -Force }
  finally { if (Test-Path -LiteralPath $temp) { [System.IO.File]::Delete($temp) } }
}

$fixture = Read-StrictJson $FixturePath
$source = Read-StrictText $PreFixSourcePath
Assert-Witness ([string]$fixture.issueId -eq $issueId -and @($fixture.cases).Count -eq 5) 'fixture is not bound to the five no-space cases.'
Assert-Witness ([int]$fixture.baseline.sourceCount -eq 458 -and [string]$fixture.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$fixture.baseline.legadoCommit -eq $legadoCommit) 'fixture baseline drifted.'
Assert-Witness ($source.Contains("if ((isCssClassSelector || isCssIdSelector) && !hasDescendant)")) 'the pre-fix class/id fast-path condition is missing.'
Assert-Witness (-not $source.Contains('hasTopLevelDirectChildCombinator')) 'the pre-fix source already contains the direct-child fast-path guard.'
Assert-Witness ($source.Contains('const directChildParts = this.splitTopLevelDirectChildSelectors(selector);')) 'the direct-child splitter exists but is reached after the fast path.'

$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'failure_witness'
  issueId = $issueId
  status = 'failed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  preFixSourcePath = $PreFixSourcePath
  preFixSourceSha256 = (Get-FileHash -LiteralPath (Get-RepoPath $PreFixSourcePath) -Algorithm SHA256).Hash.ToUpperInvariant()
  failureClass = 'v2_no_space_class_id_fast_path_hides_top_level_direct_child'
  selectionPath = [string]$fixture.selectionPath
  affectedSourceOrdinals = @($fixture.affectedSourceOrdinals)
  affectedRuleStringCount = [int]$fixture.affectedRuleStringCount
  failureWitness = [pscustomobject][ordered]@{
    branch = 'findElementsBySingleSelector'
    observed = 'class/id selectors without whitespace return through findElementsBySimpleSelector before splitTopLevelDirectChildSelectors is consulted.'
    sourcePattern = "if ((isCssClassSelector || isCssIdSelector) && !hasDescendant)"
    expected = 'A top-level > must disable the simple fast path while nested > inside pseudo and attribute contexts remains local to that selector.'
  }
  assertions = $assertions
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
}
Write-AtomicJson $ResultPath $result
$result | ConvertTo-Json -Depth 80
