[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-jsoup-terminal-text-projection-context.json',
  [string]$ResultPath = 'tools/legado-compat/evidence/contract-legado-jsoup-terminal-text-projection-pre-fix-20260810.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$noBomUtf8 = [System.Text.UTF8Encoding]::new($false)
$script:assertions = 0
$script:findings = New-Object 'System.Collections.Generic.List[object]'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  if ([System.IO.Path]::IsPathRooted($RelativePath)) {
    return $RelativePath
  }
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictText {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "required file is missing: $RelativePath"
  }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $RelativePath"
  }
  return $strictUtf8.GetString($bytes)
}

function Read-HistoricalUtf8Text {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    throw "required historical file is missing: $RelativePath"
  }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  $offset = 0
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    $offset = 3
  }
  return $strictUtf8.GetString($bytes, $offset, $bytes.Length - $offset)
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Read-StrictText -RelativePath $RelativePath | ConvertFrom-Json -Depth 100
}

function Assert-Witness {
  param(
    [Parameter(Mandatory = $true)][bool]$Condition,
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][string]$Detail,
    [string[]]$Evidence = @()
  )
  if (-not $Condition) {
    throw "terminal text projection pre-fix witness is incomplete: $Detail"
  }
  $script:assertions++
  [void]$script:findings.Add([pscustomobject][ordered]@{
      id = $Id
      status = 'failed_before_fix'
      detail = $Detail
      evidencePaths = @($Evidence)
    })
}

function Write-AtomicJson {
  param(
    [Parameter(Mandatory = $true)][string]$RelativePath,
    [Parameter(Mandatory = $true)][object]$Value
  )
  $path = Get-RepoPath -RelativePath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 80), $noBomUtf8)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) {
      [System.IO.File]::Delete($temporaryPath)
    }
  }
}

$result = $null
$exitCode = 0
try {
  $state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
  $fixture = Read-StrictJson -RelativePath $FixturePath
  $issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
  $jsEngineBackupPath = 'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets.bak_20260810_issue243_text_projection'
  $rhinoInlineBackupPath = 'entry/src/main/ets/Framework/Novel/RhinoWasmExecutor.ets.bak_20260810_issue243_text_projection'
  $rhinoStandaloneBackupPath = 'entry/src/main/resources/rawfile/rhino_sandbox/jsoup_impl.js.bak_20260810_issue243_text_projection'
  $jsEngineBackup = Read-HistoricalUtf8Text -RelativePath $jsEngineBackupPath
  $rhinoInlineBackup = Read-HistoricalUtf8Text -RelativePath $rhinoInlineBackupPath
  $rhinoStandaloneBackup = Read-HistoricalUtf8Text -RelativePath $rhinoStandaloneBackupPath
  $legado = Read-StrictText -RelativePath 'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt'
  $versions = Read-StrictText -RelativePath 'legado/gradle/libs.versions.toml'

  Assert-Witness (
    [int]$fixture.baseline.sourceCount -eq 458 -and
    [string]$fixture.baseline.sourcePackageSha256 -eq '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67' -and
    [string]$fixture.baseline.legadoCommit -eq '95973d186b147fb9ab43a9240021d688e4304fbd' -and
    [string]$fixture.baseline.jsoupVersion -eq '1.16.2'
  ) 'fixture_baseline' 'the terminal projection fixture is pinned to the frozen source package, Legado commit, and Jsoup version.' @($FixturePath)
  Assert-Witness (
    [string]$state.governance.activeIssueId -eq $issueId -and
    -not [bool]$state.governance.semanticMatchAllowed
  ) 'queue_precondition' 'the witness is attached to the active static-only issue and cannot be treated as semantic match.' @('tools/legado-compat/state/full-source-validation-state.json')
  Assert-Witness (
    $versions.Contains('jsoup = "1.16.2"') -and
    $legado.Contains('val text = element.text()') -and
    $legado.Contains('val contentEs = element.textNodes()') -and
    $legado.Contains('val text = item.text().trim { it <= '' '' }') -and
    $legado.Contains('tn.joinToString("\n")') -and
    $legado.Contains('val text = element.ownText()')
  ) 'legado_terminal_reference' 'the fixed Legado source routes text, textNodes, and ownText through three distinct terminal projections.' @(
    'legado/app/src/main/java/io/legado/app/model/analyzeRule/AnalyzeByJSoup.kt',
    'legado/gradle/libs.versions.toml'
  )
  Assert-Witness (
    $jsEngineBackup.Contains("if (attr === 'text' || attr === 'textNodes')") -and
    $jsEngineBackup.Contains("if (split.attr === 'text' || split.attr === 'textNodes') return elements.eachText();")
  ) 'standard_jsvm_terminal_collapse' 'the pre-fix standard JSVM shim collapsed textNodes into Element.text/eachText and had no ownText terminal branch.' @($jsEngineBackupPath)
  Assert-Witness (
    $rhinoInlineBackup.Contains('return this._el ? (this._el.textContent || '''') : '''';') -and
    $rhinoInlineBackup.Contains('return text.trim();') -and
    -not $rhinoInlineBackup.Contains('JsoupElement.prototype.textNodes')
  ) 'rhino_inline_projection_gap' 'the pre-fix inline Rhino shim used DOM textContent/raw direct concatenation and did not expose Jsoup textNodes().' @($rhinoInlineBackupPath)
  Assert-Witness (
    $rhinoStandaloneBackup.Contains('return this._el.textContent || '''';') -and
    $rhinoStandaloneBackup.Contains('return this.text();') -and
    $rhinoStandaloneBackup.Contains('.replace(/<[^>]+>/g, '''')')
  ) 'rhino_standalone_fallback_gap' 'the pre-fix standalone Rhino fallback stripped tags for text, mapped ownText to text, and could not return direct TextNode values.' @($rhinoStandaloneBackupPath)

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    evidenceType = 'pre_fix_static_failure_witness'
    issueId = $issueId
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    baseline = $fixture.baseline
    fixturePath = $FixturePath
    assertions = $script:assertions
    findings = $script:findings.ToArray()
    preFixPaths = @($jsEngineBackupPath, $rhinoInlineBackupPath, $rhinoStandaloneBackupPath)
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'static_pre_fix_witness_only;runtime_regression_build_device_and_legado_diff_deferred'
  }
} catch {
  $exitCode = 1
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    evidenceType = 'pre_fix_static_failure_witness'
    issueId = 'ISSUE-COMPAT-243-JSOUP-STANDARD-CSS-PSEUDO-SELECTORS'
    status = 'error'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    failure = $_.Exception.Message
    assertions = $script:assertions
    findings = $script:findings.ToArray()
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
  }
}

Write-AtomicJson -RelativePath $ResultPath -Value $result
$result | ConvertTo-Json -Depth 80
if ($exitCode -ne 0) { exit $exitCode }
