[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-nested-descendant-pseudo-direct-child-context.json',
  [string]$PostFixContractPath = 'tools/legado-compat/evidence/contract-legado-jsoup-nested-descendant-pseudo-direct-child-post-fix-20260810.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/v2-jsoup-nested-descendant-pseudo-direct-child-current-head-audit-20260810.json'
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
function Assert-Audit([bool]$Condition,[string]$Id,[string]$Detail,[string[]]$Evidence=@()){if(-not $Condition){throw "243 nested descendant pseudo current-head audit failed: $Detail"};$script:assertions++;[void]$script:checks.Add([pscustomobject][ordered]@{id=$Id;status='passed';detail=$Detail;evidencePaths=@($Evidence)})}
function Write-AtomicJson([string]$RelativePath,[object]$Value){$path=Get-RepoPath $RelativePath;$temp="$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())";try{[System.IO.File]::WriteAllText($temp,($Value|ConvertTo-Json -Depth 100),$noBomUtf8);Move-Item -LiteralPath $temp -Destination $path -Force}finally{if(Test-Path -LiteralPath $temp){[System.IO.File]::Delete($temp)}}}

$state=Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$fixture=Read-StrictJson $FixturePath
$contract=Read-StrictJson $PostFixContractPath
$sourceRelativePath='entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$elementRelativePath='entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$runtimeRelativePath='entry/src/main/resources/rawfile/legado_runtime.html'
$legadoRelativePath='legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$source=Read-StrictText $sourceRelativePath
$element=Read-StrictText $elementRelativePath
$runtime=Read-StrictText $runtimeRelativePath
$legado=Read-StrictText $legadoRelativePath
Assert-Audit ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $sourceHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'machine_baseline' 'machine state remains bound to the frozen baseline.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Audit ([string]$state.governance.activeIssueId -eq $issueId -and -not [bool]$state.governance.semanticMatchAllowed) 'queue' '243 remains the sole active issue and semantic match remains disabled.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Audit ([string]$contract.status -eq 'passed' -and -not [bool]$contract.semanticMatchAllowed -and @($contract.runtimeActionsPerformed).Count -eq 0) 'post_fix_contract' 'the post-fix contract is static-only.' @($PostFixContractPath)
Assert-Audit (@($fixture.cases).Count -eq 4 -and @($fixture.affectedSourceOrdinals).Count -eq 1 -and [int]$fixture.affectedRuleStringCount -eq 1) 'fixture_scope' 'the four cases remain bound to ordinal 223.' @($FixturePath)
Assert-Audit ($source.Contains('findElementsBySingleSelector(scopedParent, childSelector, effectiveContextHtml)') -and $source.Contains('const childSelectorParts = this.splitTopLevelCssDescendantSelector(childSelector);')) 'segment_dispatch' 'the current analyzer preserves segment-level pseudo evaluation.' @($sourceRelativePath)
Assert-Audit ($source.Contains('qualifyingDirectStarts') -and $source.Contains('ownerStart')) 'occurrence_projection' 'descendant results remain tied to qualifying direct-child occurrences.' @($sourceRelativePath)
Assert-Audit ($element.Contains("pseudo.name === 'first-child'") -and $runtime.Contains('root.querySelectorAll(browserSelector)') -and $legado.Contains('temp.select(ruleStr)')) 'consumer_matrix' 'string fallback, DOM matcher, ArkWeb and pinned Legado selector consumers remain bound.' @($sourceRelativePath, $elementRelativePath, $runtimeRelativePath, $legadoRelativePath)
Assert-Audit ((& git -C (Get-RepoPath 'legado') rev-parse HEAD 2>$null | Out-String).Trim() -eq $legadoCommit) 'legado_head' 'the Legado checkout remains pinned.' @($legadoRelativePath)

$hashes=[ordered]@{}
foreach($path in @($sourceRelativePath,$elementRelativePath,$runtimeRelativePath)){$hashes[$path]=(Get-FileHash -LiteralPath (Get-RepoPath $path) -Algorithm SHA256).Hash.ToUpperInvariant()}
$result=[pscustomobject][ordered]@{
  schemaVersion=1
  evidenceType='current_head_static_audit'
  issueId=$issueId
  status='passed'
  generatedAt=[DateTimeOffset]::UtcNow.ToString('o')
  baseline=[pscustomobject][ordered]@{sourceCount=458;sourcePackageSha256=$sourceHash;legadoCommit=$legadoCommit}
  changedPaths=@($sourceRelativePath)
  currentHeadHashes=$hashes
  consumerMatrix=@(
    [pscustomobject][ordered]@{id='large_document_string_fallback';path=$sourceRelativePath;status='supported_static';semantics=@('segment-level ancestor pseudo','nested descendant result projection','direct-child occurrence identity')},
    [pscustomobject][ordered]@{id='dom_matcher';path=$elementRelativePath;status='supported_static';semantics=@('standard CSS descendant and child pseudo consumer')},
    [pscustomobject][ordered]@{id='arkweb_native_selector';path=$runtimeRelativePath;status='supported_static';semantics=@('browser querySelectorAll selector consumer')},
    [pscustomobject][ordered]@{id='legado_reference';path=$legadoRelativePath;status='pinned_static';semantics=@('Jsoup Element.select')}
  )
  affectedSourceOrdinals=@($fixture.affectedSourceOrdinals)
  affectedRuleStringCount=[int]$fixture.affectedRuleStringCount
  assertions=$assertions
  checks=$checks.ToArray()
  runtimeActionsPerformed=@()
  semanticMatchAllowed=$false
  verificationPolicy='r3_current_head_static_audit_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  nextGate='R4 must execute all four segmented pseudo cases, ordinal 223 and fixed-Legado differential before 243 can leave verifying.'
}
Write-AtomicJson $ResultPath $result
$result|ConvertTo-Json -Depth 80
