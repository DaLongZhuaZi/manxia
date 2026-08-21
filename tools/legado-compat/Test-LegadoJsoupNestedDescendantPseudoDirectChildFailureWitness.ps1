[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-nested-descendant-pseudo-direct-child-context.json',
  [string]$PreFixSourcePath = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets.bak_20260810_nested_descendant_pseudo_direct_child',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-nested-descendant-pseudo-direct-child-pre-fix-20260810.json'
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

function Get-RepoPath([string]$RelativePath) { return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\')) }
function Read-StrictText([string]$RelativePath) { $path=Get-RepoPath $RelativePath; if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing file: $RelativePath"}; $bytes=[System.IO.File]::ReadAllBytes($path); if($bytes.Length -ge 3 -and $bytes[0]-eq 0xEF -and $bytes[1]-eq 0xBB -and $bytes[2]-eq 0xBF){throw "UTF-8 BOM is not allowed: $RelativePath"}; return $strictUtf8.GetString($bytes) }
function Read-StrictJson([string]$RelativePath) { return Read-StrictText $RelativePath | ConvertFrom-Json -Depth 100 }
function Assert-Witness([bool]$Condition,[string]$Message) { if(-not $Condition){throw "243 nested descendant pseudo failure witness failed: $Message"}; $script:assertions++ }
function Write-AtomicJson([string]$RelativePath,[object]$Value) { $path=Get-RepoPath $RelativePath; $temp="$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try{[System.IO.File]::WriteAllText($temp,($Value|ConvertTo-Json -Depth 100),$noBomUtf8);Move-Item -LiteralPath $temp -Destination $path -Force}finally{if(Test-Path -LiteralPath $temp){[System.IO.File]::Delete($temp)}} }

$fixture=Read-StrictJson $FixturePath
$source=Read-StrictText $PreFixSourcePath
Assert-Witness ([string]$fixture.issueId -eq $issueId -and @($fixture.cases).Count -eq 4) 'fixture is not bound to the four segmented pseudo cases.'
Assert-Witness ([int]$fixture.baseline.sourceCount -eq 458 -and [string]$fixture.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$fixture.baseline.legadoCommit -eq $legadoCommit) 'fixture baseline drifted.'
Assert-Witness ($source.Contains('findElementsBySimpleSelector(scopedParent, childSelector, effectiveContextHtml)')) 'the pre-fix simple-selector right-operand call is missing.'
Assert-Witness (-not $source.Contains('const childSelectorParts = this.splitTopLevelCssDescendantSelector(childSelector);')) 'the pre-fix source already has segmented descendant projection.'
Assert-Witness ($source.Contains('filterElementsByPseudoClasses(filtered, pseudo.name, contextHtml, argument)') -or $source.Contains('filterElementsByStandardChildPseudo(filtered, pseudo.name, contextHtml, argument)')) 'standard pseudo dispatch is not present for the witness path.'

$result=[pscustomobject][ordered]@{
  schemaVersion=1
  evidenceType='failure_witness'
  issueId=$issueId
  status='failed'
  generatedAt=[DateTimeOffset]::UtcNow.ToString('o')
  baseline=[pscustomobject][ordered]@{sourceCount=458;sourcePackageSha256=$sourceHash;legadoCommit=$legadoCommit}
  fixturePath=$FixturePath
  preFixSourcePath=$PreFixSourcePath
  preFixSourceSha256=(Get-FileHash -LiteralPath (Get-RepoPath $PreFixSourcePath) -Algorithm SHA256).Hash.ToUpperInvariant()
  failureClass='v2_direct_child_right_operand_ancestor_pseudo_context_loss'
  selectionPath=[string]$fixture.selectionPath
  affectedSourceOrdinals=@($fixture.affectedSourceOrdinals)
  affectedRuleStringCount=[int]$fixture.affectedRuleStringCount
  failureWitness=[pscustomobject][ordered]@{
    branch='findElementsByDirectChildSelector'
    observed='findElementsBySimpleSelector collects :nth-child and :first-child from the whole right operand, then filters only the final descendant element.'
    sourcePattern='findElementsBySimpleSelector(scopedParent, childSelector, effectiveContextHtml)'
    expected='split the right operand into descendant segments, evaluate each segment with its own pseudo context, and project descendants below qualifying direct-child occurrences.'
  }
  assertions=$assertions
  runtimeActionsPerformed=@()
  semanticMatchAllowed=$false
  verificationPolicy='r3_failure_witness_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
}
Write-AtomicJson $ResultPath $result
$result|ConvertTo-Json -Depth 80
