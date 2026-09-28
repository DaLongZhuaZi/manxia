[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = '',
  [string]$OutputPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
if ([string]::IsNullOrWhiteSpace($FixturePath)) {
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-jsoup-text-whitespace.json'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-jsoup-text-whitespace-pre-fix-20260809.json'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Assert-Witness {
  param([bool]$Condition, [string]$Message)
  if (-not $Condition) { throw "Jsoup text whitespace pre-fix witness failed: $Message" }
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing JSON: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes) | ConvertFrom-Json
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing text: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return $strictUtf8.GetString($bytes)
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 24), [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$result = $null
$exitCode = 1
try {
  $statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
  $state = Read-StrictJson -Path $statePath
  $fixture = Read-StrictJson -Path $FixturePath
  Assert-Witness ([int]$state.baseline.sourceCount -eq 458) 'machine baseline source count drifted.'
  Assert-Witness ([string]$state.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') 'machine source hash drifted.'
  Assert-Witness ([string]$state.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd') 'machine Legado commit drifted.'
  Assert-Witness ([string]$state.governance.activeIssueId -eq 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS') '235 is not the active issue.'
  Assert-Witness ([string]$state.governance.activeTaskId -eq 'COMPAT-006') 'COMPAT-006 is not the active task.'
  Assert-Witness ([string]$fixture.contract -eq 'legado_jsoup_text_whitespace') 'whitespace fixture contract changed.'
  Assert-Witness (@($fixture.cases).Count -eq 8) 'whitespace fixture must contain eight cases.'
  Assert-Witness (@($fixture.cases | Where-Object { [string]$_.projection -eq 'ownText' }).Count -eq 3) 'fixture must include three ownText cases.'
  Assert-Witness (@($fixture.cases | Where-Object { [string]$_.id -eq 'pre-preserves-internal-whitespace' }).Count -eq 1) 'fixture must include a pre preserve-whitespace case.'
  Assert-Witness (@($fixture.cases | Where-Object { [string]$_.id -eq 'textarea-preserves-internal-whitespace' }).Count -eq 1) 'fixture must include a textarea preserve-whitespace case.'

  $elementPath = Join-Path $RepositoryRoot 'entry\src\main\ets\libs\htmlparser\HTMLElement.ets'
  $analyzerPath = Join-Path $RepositoryRoot 'entry\src\main\ets\Framework\Novel\LegadoRuleAnalyzer.ets'
  $runtimePath = Join-Path $RepositoryRoot 'entry\src\main\resources\rawfile\legado_runtime.html'
  $element = Read-StrictText -Path $elementPath
  $analyzer = Read-StrictText -Path $analyzerPath
  $runtime = Read-StrictText -Path $runtimePath

  $domWitness = @(
    $element.Contains('return this.textContent.trim();'),
    $element.Contains('return text.trim();'),
    -not $element.Contains('normalizeJsoupTextWhitespace')
  )
  $stringWitness = @(
    $analyzer.Contains("return directNodes.join('\n');"),
    $analyzer.Contains("return ownTextMatch ? ownTextMatch[1].trim() : '';"),
    $analyzer.Contains("const text = own ? this.extractDirectTextNodes(element) : this.extractAttribute(element, 'text');")
  )
  $arkWebWitness = @(
    $runtime.Contains('var legadoOwnText = function (node)'),
    $runtime.Contains('return text.trim();'),
    $runtime.Contains("if (attr === 'text') return String(node.textContent || '').trim();"),
    -not $runtime.Contains('legadoNormalizeJsoupTextWhitespace')
  )
  Assert-Witness ($domWitness -contains $true) 'DOM path no longer matches the recorded simple-trim witness; regenerate the failure contract.'
  Assert-Witness (($stringWitness | Where-Object { $_ }).Count -ge 2) 'string fallback no longer matches the recorded direct-node trim witness; regenerate the failure contract.'
  Assert-Witness (($arkWebWitness | Where-Object { $_ }).Count -ge 3) 'ArkWeb path no longer matches the recorded simple-trim witness; regenerate the failure contract.'

  $sourceHashes = [ordered]@{}
  foreach ($path in @($elementPath, $analyzerPath, $runtimePath)) {
    $relative = (Resolve-Path -LiteralPath $path).Path.Replace($RepositoryRoot + '\', '').Replace('\', '/')
    $sourceHashes[$relative] = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToUpperInvariant()
  }
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_jsoup_text_whitespace_pre_fix_contract'
    issueId = 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    classification = 'v2_text_projection_does_not_normalize_jsoup_whitespace'
    baseline = [pscustomobject][ordered]@{
      sourceCount = [int]$state.baseline.sourceCount
      sourcePackageSha256 = [string]$state.baseline.sourcePackageSha256
      legadoCommit = [string]$state.baseline.legadoCommit
    }
    fixture = 'tools/legado-compat/fixtures/legado-jsoup-text-whitespace.json'
    failingCases = @(
      'ordinary-text-collapses-ascii-and-nbsp',
      'ordinary-own-text-collapses-direct-nodes',
      'descendant-text-preserves-inline-order',
      'adjacent-text-nodes-share-normalization',
      'br-adds-own-text-line-break',
      'pre-preserves-internal-whitespace',
      'textarea-preserves-internal-whitespace',
      'pseudo-selector-uses-normalized-text'
    )
    staticWitnesses = @(
      [pscustomobject][ordered]@{ path = 'entry/src/main/ets/libs/htmlparser/HTMLElement.ets'; finding = 'text and ownText only decode entities and trim; they do not apply Jsoup appendNormalisedText state, block/br boundaries or preserve-whitespace rules.' },
      [pscustomobject][ordered]@{ path = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'; finding = 'large-document own-text extraction trims each direct fragment and joins with LF, while text projection uses a separate normalizer; neither shares Jsoup ownText state.' },
      [pscustomobject][ordered]@{ path = 'entry/src/main/resources/rawfile/legado_runtime.html'; finding = 'ArkWeb legadoOwnText and text attribute use raw textContent followed by trim, with no Jsoup whitespace or preserve-whitespace helper.' }
    )
    currentWorktreeSourceHashes = $sourceHashes
    rootCauseDecision = 'pending_failure_contract; keep under ISSUE-COMPAT-235 until the three path witnesses are closed or a distinct primary cause is registered.'
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_jsoup_text_whitespace_pre_fix_witness_only;source_fix_and_runtime_regression_deferred'
    fixtureSha256 = (Get-FileHash -LiteralPath $FixturePath -Algorithm SHA256).Hash.ToUpperInvariant()
  }
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_jsoup_text_whitespace_pre_fix_contract'
    issueId = 'ISSUE-COMPAT-235-JSOUP-TEXT-PSEUDO-SELECTORS'
    status = 'contract_error'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    error = $_.Exception.Message
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_jsoup_text_whitespace_pre_fix_witness_only;source_fix_and_runtime_regression_deferred'
  }
}

Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Compress
exit $exitCode
