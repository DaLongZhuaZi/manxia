[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-dom-document-root-child-pseudo.json',
  [string]$FailureWitnessPath = 'tools/legado-compat/evidence/contract-legado-jsoup-dom-document-root-child-pseudo-pre-fix-20260810.json',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-dom-document-root-child-pseudo-post-fix-20260810.json'
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
$elementPath = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
$parserPath = 'entry/src/main/ets/libs/htmlparser/Parser.ets'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$script:assertions = 0
$script:checks = New-Object 'System.Collections.Generic.List[object]'

function Get-RepoPath { param([Parameter(Mandatory = $true)][string]$Path); if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }; return Join-Path $RepositoryRoot ($Path.Replace('/', '\')) }
function Read-StrictText { param([Parameter(Mandatory = $true)][string]$Path); $resolved = Get-RepoPath $Path; if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) { throw "Missing text: $Path" }; $bytes = [System.IO.File]::ReadAllBytes($resolved); if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }; return $strictUtf8.GetString($bytes) }
function Read-StrictJson { param([Parameter(Mandatory = $true)][string]$Path); return (Read-StrictText $Path | ConvertFrom-Json -Depth 100) }
function Assert-Contract { param([bool]$Condition, [string]$Id, [string]$Detail, [string[]]$Evidence = @()); if (-not $Condition) { throw "243 DOM document-root pseudo post-fix contract failed: $Detail" }; $script:assertions++; [void]$script:checks.Add([pscustomobject][ordered]@{ id = $Id; status = 'passed'; detail = $Detail; evidencePaths = @($Evidence) }) }
function Write-AtomicJson { param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value); $resolved = Get-RepoPath $Path; $directory = Split-Path -Parent $resolved; if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }; $temporary = "$resolved.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"; try { [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 100), $noBomUtf8); Move-Item -LiteralPath $temporary -Destination $resolved -Force } finally { if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) } } }

$fixture = Read-StrictJson $FixturePath
$failure = Read-StrictJson $FailureWitnessPath
$state = Read-StrictJson 'tools/legado-compat/state/full-source-validation-state.json'
$element = Read-StrictText $elementPath
$parser = Read-StrictText $parserPath
$legado = Read-StrictText $legadoPath

Assert-Contract ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'baseline' 'frozen machine baseline is unchanged.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Contract ([string]$state.governance.activeIssueId -eq $issueId -and [string]$state.governance.activeTaskId -eq 'COMPAT-006' -and [string]$state.governance.status -eq 'running') 'queue' '243 remains the sole active static issue.' @('tools/legado-compat/state/full-source-validation-state.json')
Assert-Contract ([string]$failure.status -eq 'failed' -and -not [bool]$failure.semanticMatchAllowed -and @($failure.runtimeActionsPerformed).Count -eq 0) 'failure_witness' 'pre-fix DOM root failure remains failed and static-only.' @($FailureWitnessPath)
Assert-Contract ([string]$fixture.issueId -eq $issueId -and @($fixture.htmlCases).Count -eq 3) 'fixture' 'DOM root fixture remains bound.' @($FixturePath)
Assert-Contract ($parser.Contains("new HTMLElement('root', null, '', null, rootRange)")) 'synthetic_root' 'parser synthetic root construction remains explicit.' @($parserPath)
$matchesStart = $element.IndexOf('private matchesPseudoClass(')
$matchesEnd = $element.IndexOf('private selectorContainsInvalidRegexAttribute(', $matchesStart)
Assert-Contract ($matchesStart -ge 0 -and $matchesEnd -gt $matchesStart) 'matcher_boundary' 'DOM pseudo matcher boundary is stable.' @($elementPath)
$matchesBody = $element.Substring($matchesStart, $matchesEnd - $matchesStart)
$guardStart = $matchesBody.IndexOf('const isSyntheticDocumentParent = parent !== null')
$guardEnd = $matchesBody.IndexOf("if (pseudo.name === 'first-child')", $guardStart)
Assert-Contract ($guardStart -ge 0 -and $guardEnd -gt $guardStart) 'synthetic_guard_boundary' 'synthetic root guard has a stable boundary before ordinary pseudo dispatch.' @($elementPath)
$guard = $matchesBody.Substring($guardStart, $guardEnd - $guardStart)
Assert-Contract ($guard.Contains('const isSyntheticDocumentParent = parent !== null') -and $guard.Contains("parent.tagName === 'root'") -and $guard.Contains('parent.parentNode === null')) 'synthetic_guard' 'synthetic root is recognized as a detached Document boundary.' @($elementPath)
foreach ($name in @('first-child', 'last-child', 'nth-child', 'only-child', 'first-of-type', 'last-of-type', 'only-of-type', 'nth-of-type', 'nth-last-of-type')) { Assert-Contract ($guard.Contains("pseudo.name === '$name'")) ("guard_$name") "synthetic Document guard covers :$name." @($elementPath) }
Assert-Contract ($guard.Contains('return false;') -and -not $guard.Contains("pseudo.name === 'eq'")) 'eq_lt_boundary' 'eq/lt sibling index semantics remain outside the Document-only guard.' @($elementPath)
Assert-Contract ($legado.Contains('temp.select(ruleStr)') -and $legado.Contains('element.select(ruleStrX.substring(0, lastIndex))')) 'legado_consumer' 'pinned Legado Jsoup selector handoff remains the reference.' @($legadoPath)

$hashes = [ordered]@{}
foreach ($path in @($elementPath, $parserPath, $legadoPath)) { $hashes[$path] = (Get-FileHash -Algorithm SHA256 -LiteralPath (Get-RepoPath $path)).Hash.ToUpperInvariant() }
$result = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'post_fix_static_contract'
  issueId = $issueId
  status = 'passed'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  fixturePath = $FixturePath
  failureWitnessPath = $FailureWitnessPath
  changedPaths = @($elementPath)
  currentHeadHashes = $hashes
  affectedSourceOrdinals = @($fixture.affectedSourceOrdinals)
  assertions = $script:assertions
  checks = $script:checks.ToArray()
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_243_dom_document_root_child_pseudo_static_only;runtime_build_device_and_legado_diff_deferred_to_R4'
  closeCondition = 'R4 must execute top-level and nested DOM child/of-type cases, the affected 243 source set, deterministic 458-source Harness, fixed-Legado differential, build and device gates before 243 can leave verifying.'
}
Write-AtomicJson $OutputPath $result
$result | ConvertTo-Json -Depth 100
