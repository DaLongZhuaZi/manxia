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
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-jsoup-regex-attribute-selector.json'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-jsoup-regex-attribute-selector-pre-fix-20260808.json'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing JSON: $Path" }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $Path" }
  return ($strictUtf8.GetString($bytes) | ConvertFrom-Json)
}

function Read-GitHeadText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $text = (& git -C $RepositoryRoot show ("HEAD:{0}" -f $RelativePath) 2>$null | Out-String)
  if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($text)) { throw "Frozen source is missing: $RelativePath" }
  return $text
}

function Get-Sha256ForText {
  param([Parameter(Mandatory = $true)][string]$Text)
  $bytes = $strictUtf8.GetBytes($Text)
  $hash = [System.Security.Cryptography.SHA256]::Create()
  try { return ([System.BitConverter]::ToString($hash.ComputeHash($bytes))).Replace('-', '').ToUpperInvariant() }
  finally { $hash.Dispose() }
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

$result = $null
$exitCode = 1
try {
  $state = Read-StrictJson -Path (Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json')
  $fixture = Read-StrictJson -Path $FixturePath
  if ([int]$state.baseline.sourceCount -ne 458) { throw 'Frozen source count is not 458.' }
  if ([string]$state.baseline.sourcePackageSha256 -ne '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') { throw 'Frozen source package hash drifted.' }
  if ([string]$state.baseline.legadoCommit -ne '95973d186b147fb9ab43a9240021d688e4304fbd') { throw 'Frozen Legado commit drifted.' }
  if ([string]$fixture.contract -ne 'legado_jsoup_regex_attribute_selector' -or @($fixture.cases).Count -ne 7) { throw 'Jsoup regex fixture shape changed.' }

  $paths = @(
    'entry/src/main/ets/libs/htmlparser/Matcher.ets',
    'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets',
    'entry/src/main/resources/rawfile/legado_runtime.html'
  )
  $headHashes = [ordered]@{}
  foreach ($path in $paths) {
    $text = Read-GitHeadText -RelativePath $path
    $headHashes[$path] = Get-Sha256ForText -Text $text
    if ($text.Contains('parseLegadoRegexPrefix') -or $text.Contains('matchesLegadoAttributeSelector') -or $text.Contains('legadoParseRegexAttributeSelectors') -or $text.Contains('legadoSelectWithJsoupRegex')) {
      throw "Frozen HEAD unexpectedly contains the 234 regex selector fix: $path"
    }
  }

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_jsoup_regex_attribute_selector_pre_fix_contract'
    issueId = 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    classification = 'v2_pre_fix_jsoup_regex_attribute_selector_missing_semantics'
    baseline = [pscustomobject][ordered]@{ sourceCount = [int]$state.baseline.sourceCount; sourcePackageSha256 = [string]$state.baseline.sourcePackageSha256; legadoCommit = [string]$state.baseline.legadoCommit }
    fixture = 'tools/legado-compat/fixtures/legado-jsoup-regex-attribute-selector.json'
    failingCases = @('alternation-property', 'regex-character-class', 'escaped-digit', 'java-inline-case-insensitive-flag', 'multiple-attribute-predicates')
    frozenHeadHashes = $headHashes
    rootCause = 'Frozen V2 Matcher, large-document string fallback and ArkWeb runtime did not implement Legado Jsoup ~= regular-expression attributes; Java inline flags such as (?i), nested character classes and multiple attribute predicates were either rejected or treated as ordinary CSS tokens.'
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_jsoup_regex_attribute_selector_pre_fix_witness_only;source_fix_and_runtime_regression_deferred'
    fixtureSha256 = (Get-FileHash -LiteralPath $FixturePath -Algorithm SHA256).Hash.ToUpperInvariant()
  }
  # This command intentionally exits non-zero because the artifact is a
  # failed-before witness, not a compatibility pass.
  $exitCode = 1
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_jsoup_regex_attribute_selector_pre_fix_contract'
    issueId = 'ISSUE-COMPAT-234-JSOUP-REGEX-ATTRIBUTE-SELECTOR'
    status = 'contract_error'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    error = $_.Exception.Message
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_jsoup_regex_attribute_selector_pre_fix_witness_only;source_fix_and_runtime_regression_deferred'
  }
}

Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Compress
exit $exitCode
