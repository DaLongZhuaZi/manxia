[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-nested-descendant-pseudo-direct-child-context.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-nested-descendant-pseudo-direct-child-pre-fix-20260810.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-nested-descendant-pseudo-direct-child-post-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) { $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path }
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$sourceHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'
$issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
$assertions = 0
$checks = [System.Collections.Generic.List[object]]::new()

function Get-RepoPath([string]$RelativePath) { return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictText([string]$RelativePath) { $path=Get-RepoPath $RelativePath; if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing file: $RelativePath"}; $bytes=[System.IO.File]::ReadAllBytes($path); if($bytes.Length -ge 3 -and $bytes[0]-eq 0xEF -and $bytes[1]-eq 0xBB -and $bytes[2]-eq 0xBF){throw "UTF-8 BOM is not allowed: $RelativePath"}; return $strictUtf8.GetString($bytes) }
function Read-StrictJson([string]$RelativePath) { return Read-StrictText $RelativePath | ConvertFrom-Json -Depth 100 }
function Assert-Contract([bool]$Condition,[string]$Id,[string]$Detail,[string[]]$Evidence=@()){if(-not $Condition){throw "243 nested descendant pseudo post-fix contract failed: $Detail"};$script:assertions++;[void]$script:checks.Add([pscustomobject][ordered]@{id=$Id;status='passed';detail=$Detail;evidencePaths=@($Evidence)})}
function Write-AtomicJson([string]$RelativePath,[object]$Value){$path=Get-RepoPath $RelativePath;$temp="$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())";try{[System.IO.File]::WriteAllText($temp,($Value|ConvertTo-Json -Depth 100),$noBomUtf8);Move-Item -LiteralPath $temp -Destination $path -Force}finally{if(Test-Path -LiteralPath $temp){[System.IO.File]::Delete($temp)}}}

$fixture=Read-StrictJson $FixturePath
$failure=Read-StrictJson $FailureWitnessPath
$sourceRelativePath='entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$source=Read-StrictText $sourceRelativePath
Assert-Contract ([int]$fixture.baseline.sourceCount -eq 458 -and [string]$fixture.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$fixture.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'fixture remains bound to the frozen package and pinned Legado commit.' @($FixturePath)
Assert-Contract ([string]$failure.status -eq 'failed' -and -not [bool]$failure.semanticMatchAllowed -and @($failure.runtimeActionsPerformed).Count -eq 0) 'failure_witness' 'the pre-fix witness remains failed and static-only.' @($FailureWitnessPath)
Assert-Contract (@($fixture.cases).Count -eq 4 -and @($fixture.affectedSourceOrdinals).Count -eq 1 -and [int]$fixture.affectedRuleStringCount -eq 1) 'fixture_scope' 'the four cases are bound to ordinal 223 and one source rule.' @($FixturePath)
Assert-Contract ($source.Contains('findElementsBySingleSelector(scopedParent, childSelector, effectiveContextHtml)')) 'full_dispatcher' 'the right operand uses the full selector dispatcher.' @($sourceRelativePath)
Assert-Contract ($source.Contains('const childSelectorParts = this.splitTopLevelCssDescendantSelector(childSelector);')) 'segment_split' 'descendant segments are split before pseudo context is applied.' @($sourceRelativePath)
Assert-Contract ($source.Contains('const firstSelector = childSelectorParts[0];') -and $source.Contains('qualifyingDirectStarts')) 'direct_child_qualification' 'only matches below a qualifying direct-child first segment are projected.' @($sourceRelativePath)
Assert-Contract ($source.Contains('const childEnd = childOccurrence.startIndex + childOccurrence.element.length;') -and $source.Contains('ownerStart')) 'descendant_projection' 'descendant results are mapped to their direct-child owner by occurrence range.' @($sourceRelativePath)

$result=[pscustomobject][ordered]@{
  schemaVersion=1
  evidenceType='post_fix_static_contract'
  issueId=$issueId
  status='passed'
  generatedAt=[DateTimeOffset]::UtcNow.ToString('o')
  baseline=[pscustomobject][ordered]@{sourceCount=458;sourcePackageSha256=$sourceHash;legadoCommit=$legadoCommit}
  fixturePath=$FixturePath
  failureWitnessPath=$FailureWitnessPath
  changedPaths=@($sourceRelativePath)
  currentHeadHashes=[pscustomobject][ordered]@{$sourceRelativePath=(Get-FileHash -LiteralPath (Get-RepoPath $sourceRelativePath) -Algorithm SHA256).Hash.ToUpperInvariant()}
  assertions=$assertions
  checks=$checks.ToArray()
  runtimeActionsPerformed=@()
  semanticMatchAllowed=$false
  verificationPolicy='r3_source_fix_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  closeCondition='R4 must execute all four segmented pseudo cases, ordinal 223, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $ResultPath $result
$result|ConvertTo-Json -Depth 80
