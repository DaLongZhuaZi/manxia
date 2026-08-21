[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$TargetEvidencePath = '',
  [string]$FailureEvidencePath = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if ([string]::IsNullOrWhiteSpace($TargetEvidencePath)) {
  $TargetEvidencePath = 'tools/legado-compat/evidence/r3-actual-docs-source-refactor-target-20260809-235-text-whitespace/target.json'
}
if ([string]::IsNullOrWhiteSpace($FailureEvidencePath)) {
  $FailureEvidencePath = 'tools/legado-compat/evidence/contract-legado-jsoup-text-whitespace-pre-fix-20260809.json'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = 'tools/legado-compat/evidence/contract-legado-jsoup-text-whitespace-consumers-pre-fix-20260809.json'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Assert-Contract {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Jsoup text whitespace consumer contract failed: $Message" }
}

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing JSON: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes) | ConvertFrom-Json
}

function Read-StrictText {
  param([string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing text: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return $strictUtf8.GetString($bytes)
}

function Write-AtomicJson {
  param([string]$Path, [object]$Value)
  $absolute = Get-RepoPath -RelativePath $Path
  $directory = Split-Path -Parent $absolute
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$absolute.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 30), [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $absolute -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$result = $null
$exitCode = 1
try {
  $state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
  $target = Read-StrictJson -RelativePath $TargetEvidencePath
  $failure = Read-StrictJson -RelativePath $FailureEvidencePath
  Assert-Contract ([string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS') '235 is not the active issue.'
  Assert-Contract ([string]$target.currentSubstage -eq '235-WS-02') 'target is not at WS-02.'
  Assert-Contract ([string]$failure.status -eq 'failed' -and -not [bool]$failure.semanticMatchAllowed) 'failure witness is not static-only.'

  $legadoAnalyze = Read-StrictText -RelativePath 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
  $legadoExtensions = Read-StrictText -RelativePath 'legado/app/src/main/java/io/legado/app/utils/JsoupExtensions.kt'
  $element = Read-StrictText -RelativePath 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'
  $analyzer = Read-StrictText -RelativePath 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
  $runtime = Read-StrictText -RelativePath 'entry/src/main/resources/rawfile/legado_runtime.html'

  $legadoAssertions = @(
    $legadoAnalyze.Contains('val text = element.text()'),
    $legadoAnalyze.Contains('val text = element.ownText()'),
    $legadoExtensions.Contains('StringUtil.appendNormalisedWhitespace'),
    $legadoExtensions.Contains('preserveWhitespace(textNode.parentNode())'),
    $legadoExtensions.Contains('textNode.wholeText')
  )
  Assert-Contract (($legadoAssertions | Where-Object { $_ }).Count -eq 5) 'fixed Legado text/ownText normalization evidence is incomplete.'

  $consumerMatrix = @(
    [pscustomobject][ordered]@{ consumer = 'DOM.HTMLElement.text'; path = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'; projection = 'descendant_text'; currentStatus = 'gap'; finding = 'textContent.trim does not collapse ordinary whitespace, insert Jsoup block/br boundaries, or preserve pre/textarea whitespace.' },
    [pscustomobject][ordered]@{ consumer = 'DOM.HTMLElement.ownText'; path = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'; projection = 'direct_text'; currentStatus = 'gap'; finding = 'direct TextNode concatenation plus trim has no shared whitespace state and ignores direct br line breaks.' },
    [pscustomobject][ordered]@{ consumer = 'StringFallback.text'; path = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'; projection = 'descendant_text'; currentStatus = 'partial_gap'; finding = 'stripHtmlTagsFast/normalizePlainText collapses a subset of whitespace but cannot preserve Jsoup whitespace tags or exact accumulator boundaries.' },
    [pscustomobject][ordered]@{ consumer = 'StringFallback.ownText'; path = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'; projection = 'direct_text'; currentStatus = 'gap'; finding = 'extractDirectTextNodes trims each fragment and joins with LF, diverging from Jsoup ownText across adjacent nodes and br.' },
    [pscustomobject][ordered]@{ consumer = 'ArkWeb.legadoOwnText'; path = 'entry/src/main/resources/rawfile/legado_runtime.html'; projection = 'direct_text'; currentStatus = 'gap'; finding = 'raw child node concatenation plus trim does not share Jsoup normalisation or preserve-whitespace state.' },
    [pscustomobject][ordered]@{ consumer = 'ArkWeb pseudo text'; path = 'entry/src/main/resources/rawfile/legado_runtime.html'; projection = 'pseudo_input'; currentStatus = 'gap'; finding = 'legadoMatchesJsoupPseudo uses raw textContent for descendant pseudo predicates instead of the Jsoup text projection.' }
  )
  Assert-Contract (($element.Contains('return this.textContent.trim();') -and $element.Contains('return text.trim();')) -and
    $analyzer.Contains("return directNodes.join('\n');") -and
    $runtime.Contains('var legadoOwnText = function (node)')) 'recorded V2 consumer gap no longer matches current source; regenerate the failure evidence.'

  $sourceHashes = [ordered]@{}
  foreach ($path in @(
    'entry/src/main/ets/libs/htmlparser/HTMLElement.ets',
    'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
    'entry/src/main/resources/rawfile/legado_runtime.html'
  )) {
    $sourceHashes[$path] = (Get-FileHash -LiteralPath (Get-RepoPath -RelativePath $path) -Algorithm SHA256).Hash.ToUpperInvariant()
  }

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_jsoup_text_whitespace_consumer_pre_fix_contract'
    issueId = 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    verification = 'static_consumer_mapping_only;runtime_regression_deferred'
    baseline = [pscustomobject][ordered]@{
      sourceCount = [int]$state.baseline.sourceCount
      sourcePackageSha256 = [string]$state.baseline.sourcePackageSha256
      legadoCommit = [string]$state.baseline.legadoCommit
    }
    fixedLegadoSemantics = @{
      normalisedWhitespace = @('space', 'tab', 'LF', 'CR', 'FF', 'NBSP')
      invisibleCharacters = @('U+200B', 'U+00AD')
      preserveWhitespaceTags = @('pre', 'plaintext', 'title', 'textarea', 'script', 'style')
      ownText = 'direct TextNode children only; normalised with shared state; br adds LF; Java trim removes <= U+0020 at final boundary.'
    }
    consumerMatrix = $consumerMatrix
    currentWorktreeSourceHashes = $sourceHashes
    rootCause = 'A single missing Jsoup-compatible text accumulator and preserve-whitespace policy is projected independently as trim/raw text across DOM, string fallback and ArkWeb; this remains one primary semantic cause, not three patch targets.'
    failureEvidence = $FailureEvidencePath
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_jsoup_text_whitespace_consumer_failure_contract;source_fix_and_runtime_regression_deferred'
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_jsoup_text_whitespace_consumer_pre_fix_contract'
    issueId = 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
    status = 'contract_error'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    error = $_.Exception.Message
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_jsoup_text_whitespace_consumer_failure_contract;source_fix_and_runtime_regression_deferred'
  }
}

Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Compress
exit $exitCode
