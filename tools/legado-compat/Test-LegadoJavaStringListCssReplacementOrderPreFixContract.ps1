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
  $FixturePath = Join-Path $RepositoryRoot 'tools\legado-compat\fixtures\legado-java-string-list-css-replacement-order.json'
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
  $OutputPath = Join-Path $RepositoryRoot 'tools\legado-compat\evidence\contract-legado-java-string-list-css-replacement-order-pre-fix-20260808.json'
}

$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Missing JSON fixture: $Path"
  }
  $bytes = [System.IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    throw "UTF-8 BOM is not allowed: $Path"
  }
  return ($strictUtf8.GetString($bytes) | ConvertFrom-Json)
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][object]$Value)
  $directory = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $directory)) {
    [System.IO.Directory]::CreateDirectory($directory) | Out-Null
  }
  $temporaryPath = "$Path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 20), [System.Text.UTF8Encoding]::new($false))
  Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

function Get-Sha256 {
  param([Parameter(Mandatory = $true)][string]$Path)
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToUpperInvariant()
}

function Get-ListForSelector {
  param([Parameter(Mandatory = $true)][string]$Selector)
  if ($Selector -eq '.primary@a@text') { return @('A', 'A') }
  if ($Selector -eq '.secondary@a@text') { return @('A', 'B') }
  throw "Unsupported fixture selector in pre-fix model: $Selector"
}

function Get-OldRuleParts {
  param([Parameter(Mandatory = $true)][string]$Rule)
  $composition = $Rule
  $replacement = $null
  $pattern = $null
  $replaceFirst = $false
  $marker = $Rule.IndexOf('##', [System.StringComparison]::Ordinal)
  if ($marker -ge 0) {
    $composition = $Rule.Substring(0, $marker)
    $suffix = $Rule.Substring($marker + 2)
    $parts = $suffix.Split('##', 3, [System.StringSplitOptions]::None)
    if ($parts.Count -ge 2) {
      $pattern = [string]$parts[0]
      $replacement = [string]$parts[1]
      # This is the old bug: any trailing single # was treated as the
      # replace-first marker instead of remaining literal replacement text.
      $replaceFirst = $suffix.EndsWith('#', [System.StringComparison]::Ordinal)
      if ($replaceFirst -and $replacement.EndsWith('#', [System.StringComparison]::Ordinal)) {
        $replacement = $replacement.Substring(0, $replacement.Length - 1)
      }
    }
  }
  return [pscustomobject][ordered]@{
    composition = $composition
    pattern = $pattern
    replacement = $replacement
    replaceFirst = $replaceFirst
  }
}

function Apply-OldReplacement {
  param(
    [Parameter(Mandatory = $true)][string[]]$Values,
    [Parameter(Mandatory = $true)][string]$Pattern,
    [Parameter(Mandatory = $true)][string]$Replacement,
    [Parameter(Mandatory = $true)][bool]$ReplaceFirst
  )
  $output = [System.Collections.Generic.List[string]]::new()
  $replaced = $false
  foreach ($value in $Values) {
    $matches = $value.Contains($Pattern, [System.StringComparison]::Ordinal)
    if ($matches -and $ReplaceFirst -and $replaced) {
      $output.Add($value)
      continue
    }
    if ($matches) {
      $output.Add($value.Replace($Pattern, $Replacement))
      $replaced = $true
    } else {
      $output.Add($value)
    }
  }
  return @($output.ToArray())
}

function Invoke-OldPreFixModel {
  param([Parameter(Mandatory = $true)][string]$Rule)
  $parts = Get-OldRuleParts -Rule $Rule
  $operands = @($parts.composition -split '&&')
  $merged = [System.Collections.Generic.List[string]]::new()
  foreach ($operand in $operands) {
    $values = @(Get-ListForSelector -Selector ([string]$operand))
    # The old analyzer applied replacement to each operand before merging.
    if ($null -ne $parts.pattern -and $null -ne $parts.replacement) {
      $values = @(Apply-OldReplacement -Values $values -Pattern ([string]$parts.pattern) -Replacement ([string]$parts.replacement) -ReplaceFirst ([bool]$parts.replaceFirst))
    }
    foreach ($value in $values) { $merged.Add($value) }
  }
  return @($merged.ToArray())
}

$result = $null
$exitCode = 1
try {
  $fixture = Read-StrictJson -Path $FixturePath
  $statePath = Join-Path $RepositoryRoot 'tools\legado-compat\state\full-source-validation-state.json'
  $state = Read-StrictJson -Path $statePath
  if ([int]$state.baseline.sourceCount -ne 458) { throw 'Frozen source count is not 458.' }
  if ([string]$state.baseline.sourcePackageSha256 -ne '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67') { throw 'Frozen source package hash drifted.' }
  if ([string]$state.baseline.legadoCommit -ne '95973d186b147fb9ab43a9240021d688e4304fbd') { throw 'Frozen Legado commit drifted.' }
  if ([string]$fixture.contract -ne 'legado_java_string_list_css_replacement_order') { throw 'Replacement-order fixture contract id changed.' }

  $cases = @($fixture.cases)
  if ($cases.Count -ne 4) { throw 'Replacement-order fixture must contain four cases.' }
  $mismatches = [System.Collections.Generic.List[object]]::new()
  foreach ($case in $cases) {
    $observed = @(Invoke-OldPreFixModel -Rule ([string]$case.rule))
    $expected = @($case.expected | ForEach-Object { [string]$_ })
    if (-not [System.Linq.Enumerable]::SequenceEqual([string[]]$observed, [string[]]$expected)) {
      $mismatches.Add([pscustomobject][ordered]@{
        id = [string]$case.id
        rule = [string]$case.rule
        expected = $expected
        observed = $observed
      })
    }
  }
  if ($mismatches.Count -ne 2) { throw "Pre-fix model produced $($mismatches.Count) mismatches; expected two stable witnesses." }
  if (-not (@($mismatches | Where-Object { $_.id -eq 'replacement-hash-is-literal' }).Count -eq 1)) { throw 'Literal trailing # witness did not fail.' }
  if (-not (@($mismatches | Where-Object { $_.id -eq 'composition-replace-first-after-merge' }).Count -eq 1)) { throw 'Post-composition replace-first witness did not fail.' }

  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_java_string_list_css_replacement_order_pre_fix_contract'
    issueId = 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION'
    status = 'failed'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    classification = 'v2_pre_fix_replacement_order_and_trailing_hash_mismatch'
    baseline = [pscustomobject][ordered]@{
      sourceCount = [int]$state.baseline.sourceCount
      sourcePackageSha256 = [string]$state.baseline.sourcePackageSha256
      legadoCommit = [string]$state.baseline.legadoCommit
    }
    fixture = 'tools/legado-compat/fixtures/legado-java-string-list-css-replacement-order.json'
    model = 'deterministic_pre_fix_analyzer_model'
    mismatches = @($mismatches.ToArray())
    rootCause = 'The pre-fix path applied replacement independently to composition operands and treated a single trailing # as replace-first. Legado composes the complete list first and only a trailing ## marks replaceFirst.'
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_java_string_list_css_replacement_order_pre_fix_witness_only;source_fix_and_runtime_regression_deferred'
    fixtureSha256 = Get-Sha256 -Path $FixturePath
  }
  # A pre-fix contract is intentionally a failing witness. Keep the
  # non-zero exit so callers cannot mistake it for a compatibility pass.
  $exitCode = 1
} catch {
  $result = [pscustomobject][ordered]@{
    schemaVersion = 1
    kind = 'legado_java_string_list_css_replacement_order_pre_fix_contract'
    issueId = 'ISSUE-COMPAT-233-JAVA-STRING-LIST-CSS-COMPOSITION'
    status = 'contract_error'
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    error = $_.Exception.Message
    runtimeActionsPerformed = @()
    semanticMatchAllowed = $false
    verificationPolicy = 'r3_java_string_list_css_replacement_order_pre_fix_witness_only;source_fix_and_runtime_regression_deferred'
  }
}

Write-AtomicJson -Path $OutputPath -Value $result
$result | ConvertTo-Json -Compress
exit $exitCode
