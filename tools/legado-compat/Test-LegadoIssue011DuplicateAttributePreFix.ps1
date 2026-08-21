[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$OutputPath = 'tools/legado-compat/evidence/contract-legado-url-attribute-duplicate-pre-fix-011-20260809.json'
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
$issueId = 'ISSUE-COMPAT-011'

function Get-RepositoryPath([string]$RelativePath) {
  if ([System.IO.Path]::IsPathRooted($RelativePath)) { return $RelativePath }
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText([string]$RelativePath) {
  $path = Get-RepositoryPath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing input: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-StrictJson([string]$RelativePath) {
  return (Read-StrictText $RelativePath | ConvertFrom-Json)
}

function Get-FileSha256([string]$RelativePath) {
  return (Get-FileHash -LiteralPath (Get-RepositoryPath $RelativePath) -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Assert-Contract([bool]$Condition, [string]$Message) {
  if (-not $Condition) { throw "ISSUE011_DUPLICATE_ATTRIBUTE_PRE_FIX_FAILED:$Message" }
}

function Write-AtomicJson([string]$RelativePath, [object]$Value) {
  $path = Get-RepositoryPath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporary = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporary, ($Value | ConvertTo-Json -Depth 40), $noBomUtf8)
    Move-Item -LiteralPath $temporary -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporary) { [System.IO.File]::Delete($temporary) }
  }
}

$fixturePath = 'tools/legado-compat/fixtures/legado-url-attribute-duplicate-011.json'
$legadoPath = 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
$v2Path = 'entry/src/main/ets/Framework/Novel/LegadoRuleAnalyzer.ets'
$fixture = Read-StrictJson $fixturePath
$legado = Read-StrictText $legadoPath
$v2 = Read-StrictText $v2Path
$case = @($fixture.cases) | Select-Object -First 1
$functionStart = $v2.IndexOf('private getResultByLastRule(')
$functionEnd = $v2.IndexOf('private isGenericCssAttributeName(', $functionStart)
Assert-Contract ($functionStart -ge 0 -and $functionEnd -gt $functionStart) 'V2 getResultByLastRule function boundary is missing'
$v2Function = $v2.Substring($functionStart, $functionEnd - $functionStart)

Assert-Contract ([int]$fixture.baseline.sourceCount -eq $sourceCount) 'fixture source count drifted'
Assert-Contract ([string]$fixture.baseline.sourcePackageSha256 -eq $sourceHash) 'fixture source hash drifted'
Assert-Contract ([string]$fixture.baseline.legadoCommit -eq $legadoCommit) 'fixture Legado commit drifted'
Assert-Contract ([string]$case.rule -eq '.primary@a@href') 'duplicate-value rule drifted'
Assert-Contract ([string]$case.expectedLegadoString -eq "/a`n/b") 'Legado expected projection drifted'
Assert-Contract ([string]$case.expectedV2PreFixString -eq "/a`n/a`n/b") 'V2 pre-fix projection drifted'
Assert-Contract ($legado.Contains('if (url.isBlank() || textS.contains(url)) continue')) 'Legado duplicate suppression is missing'
Assert-Contract ($legado.Contains('textS.add(url)')) 'Legado attribute projection add operation is missing'
Assert-Contract ($v2Function.Contains('const text = this.extractAttribute(el, lowerRule);')) 'V2 attribute extraction loop is missing'
Assert-Contract ($v2Function.Contains('results.push(text);')) 'V2 attribute projection push operation is missing'
Assert-Contract ($v2Function.Contains("results.join('\n')")) 'V2 pre-fix projection delimiter is missing'
Assert-Contract (-not $v2Function.Contains('results.includes(text)')) 'V2 source already contains the expected duplicate suppression; witness is stale'
Assert-Contract (-not $v2Function.Contains('new Set<string>')) 'V2 source already contains a value set; witness is stale'

$evidence = [ordered]@{
  schemaVersion = 1
  kind = 'legado_issue_011_url_attribute_duplicate_pre_fix_contract'
  status = 'failed_static_only'
  issueId = $issueId
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [ordered]@{ sourceCount = $sourceCount; sourcePackageSha256 = $sourceHash; legadoCommit = $legadoCommit }
  fixturePath = $fixturePath
  failureClass = 'selector_attribute_value_deduplication_mismatch'
  failureWitness = [ordered]@{
    mode = 'deterministic_static_projection'
    rule = [string]$case.rule
    htmlSha256 = [System.BitConverter]::ToString(([System.Security.Cryptography.SHA256]::Create()).ComputeHash($noBomUtf8.GetBytes([string]$fixture.html))).Replace('-', '').ToUpperInvariant()
    expectedLegadoSelectorValues = @($case.expectedLegadoSelectorValues)
    expectedLegadoString = [string]$case.expectedLegadoString
    observedV2PreFixSelectorValues = @($case.expectedV2PreFixSelectorValues)
    observedV2PreFixString = [string]$case.expectedV2PreFixString
    observationBasis = 'Legado getResultLast source path plus V2 getResultByLastRule current-head source path; no runtime or network action performed'
  }
  primaryCause = [ordered]@{
    classification = 'selector_extraction_vs_url_resolution_boundary'
    statement = 'Legado suppresses repeated nonblank Element.attr values in getResultLast; V2 pushes every nonblank value before newline joining, so duplicate href/src values remain observable.'
    legadoLocation = [ordered]@{ path = $legadoPath; lines = '272-276'; sha256 = Get-FileSha256 $legadoPath }
    v2Location = [ordered]@{ path = $v2Path; lines = '3638-3660'; sha256 = Get-FileSha256 $v2Path }
  }
  assertions = 13
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_static_failure_contract_only;runtime_build_device_and_legado_diff_deferred'
  reproductionCommand = "pwsh -NoLogo -NoProfile -NonInteractive -File tools/legado-compat/Test-LegadoIssue011DuplicateAttributePreFix.ps1"
  closeCondition = 'Add value-level deduplication at the shared V2 selector projection boundary, then produce post-fix static contract, current-head consumer audit and R4 runtime/Legado differential evidence; do not mark semantic_match from this static witness.'
}
Write-AtomicJson $OutputPath $evidence
$evidence | ConvertTo-Json -Depth 40
