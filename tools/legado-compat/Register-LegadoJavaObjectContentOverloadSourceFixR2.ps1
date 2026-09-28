[CmdletBinding()]
param(
  [string]$RepositoryRoot = '',
  [string]$CurrentHeadEvidencePath = 'tools/legado-compat/evidence/v2-java-object-content-overload-current-head-audit-20260809-r2.json',
  [string]$StaticContractPath = 'tools/legado-compat/evidence/contract-legado-java-object-content-overload.json',
  [string]$PreFixEvidencePath = 'tools/legado-compat/evidence/contract-legado-java-object-content-overload-pre-fix-20260809-r2.json',
  [string]$FixturePath = 'tools/legado-compat/fixtures/legado-java-object-content-overload-r2.json',
  [string]$SourceFixPath = 'tools/legado-compat/evidence/v2-java-object-content-overload-source-fix-20260809-r2.json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$baselineHash = '473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67'
$legadoCommit = '95973d186b147fb9ab43a9240021d688e4304fbd'

function Get-RepoPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Read-StrictJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $path = Get-RepoPath -RelativePath $RelativePath
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "required JSON is missing: $RelativePath" }
  $bytes = [System.IO.File]::ReadAllBytes($path)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "UTF-8 BOM is not allowed: $RelativePath" }
  return ($strictUtf8.GetString($bytes) | ConvertFrom-Json)
}

function Assert-SourceFix {
  param([Parameter(Mandatory = $true)][bool]$Condition, [Parameter(Mandatory = $true)][string]$Message)
  if (-not $Condition) { throw "238 source-fix registration blocked: $Message" }
}

function Write-AtomicJson {
  param([Parameter(Mandatory = $true)][string]$RelativePath, [Parameter(Mandatory = $true)][object]$Value)
  $path = Get-RepoPath -RelativePath $RelativePath
  $directory = Split-Path -Parent $path
  if (-not (Test-Path -LiteralPath $directory -PathType Container)) { [System.IO.Directory]::CreateDirectory($directory) | Out-Null }
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, ($Value | ConvertTo-Json -Depth 60), $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

$state = Read-StrictJson -RelativePath 'tools/legado-compat/state/full-source-validation-state.json'
$preFix = Read-StrictJson -RelativePath $PreFixEvidencePath
$currentHead = Read-StrictJson -RelativePath $CurrentHeadEvidencePath
$staticContract = Read-StrictJson -RelativePath $StaticContractPath
$fixture = Read-StrictJson -RelativePath $FixturePath

Assert-SourceFix ([int]$state.baseline.sourceCount -eq 458 -and [string]$state.baseline.sourcePackageSha256 -eq $baselineHash -and [string]$state.baseline.legadoCommit -eq $legadoCommit) 'fixed baseline drifted.'
Assert-SourceFix ([string]$preFix.status -eq 'failed' -and [string]$preFix.sourceSnapshotMode -eq 'git_head_pinned_pre_fix' -and -not [bool]$preFix.semanticMatchAllowed) 'pinned pre-fix witness is invalid.'
Assert-SourceFix ([string]$currentHead.status -eq 'passed' -and [string]$currentHead.issueId -eq 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD' -and -not [bool]$currentHead.semanticMatchAllowed -and @($currentHead.runtimeActionsPerformed).Count -eq 0) 'current-head static audit is invalid.'
$staticSemanticClaimAbsent = $staticContract.PSObject.Properties.Name -notcontains 'semanticMatchAllowed'
Assert-SourceFix ([string]$staticContract.status -eq 'passed' -and [int]$staticContract.assertions -eq 20 -and ($staticSemanticClaimAbsent -or -not [bool]$staticContract.semanticMatchAllowed)) 'base static contract is invalid.'
Assert-SourceFix (@($fixture.cases).Count -eq 7 -and [string]$fixture.issueId -eq 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD') 'R2 fixture drifted.'

$sourcePaths = @('entry/src/main/resources/rawfile/legado_runtime.html', 'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets')
$sourceHashes = [ordered]@{}
foreach ($path in $sourcePaths) {
  $sourceHashes[$path] = (Get-FileHash -LiteralPath (Get-RepoPath -RelativePath $path) -Algorithm SHA256).Hash.ToUpperInvariant()
}

$sourceFix = [pscustomobject][ordered]@{
  schemaVersion = 1
  evidenceType = 'legado_java_object_content_overload_source_fix_r2'
  issueId = 'ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD'
  status = 'source_closed_static_only'
  generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
  baseline = [pscustomobject][ordered]@{ sourceCount = 458; sourcePackageSha256 = $baselineHash; legadoCommit = $legadoCommit }
  failureEvidence = @($PreFixEvidencePath)
  staticContract = $StaticContractPath
  currentHeadAudit = $CurrentHeadEvidencePath
  fixture = $FixturePath
  rootCause = 'The first embedded native helper family had no local replacement descriptor and mixed the standard replacement function into list projection. This allowed an outer or undefined replacement reference and left duplicate native helper copies with different object, JSONPath, CSS and ## replacement semantics.'
  changes = @(
    [pscustomobject][ordered]@{ path = 'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets'; change = 'Align both embedded native getString helpers with the shared replacement descriptor, object-first lookup, JSONPath bridge and post-projection replacement contract.' },
    [pscustomobject][ordered]@{ path = 'entry/src/main/ets/Framework/Novel/LegadoJsEngine.ets'; change = 'Align both embedded native getStringList helpers with local replacement scope and native replacement application for composition, JSONPath and CSS projections.' },
    [pscustomobject][ordered]@{ path = 'tools/legado-compat/Test-LegadoJavaObjectContentOverloadPreFixContractR2.ps1'; change = 'Pin pre-fix witness to Git HEAD and terminate helper extraction at the nearest marker so the two embedded copies cannot be conflated.' }
  )
  affectedStaticSet = [pscustomobject][ordered]@{ candidateCallCount = 10; affectedSourceCount = 5; candidateSourceOrdinals = @(24, 214, 227, 239, 316); plainObjectCandidateCount = 0 }
  currentHeadHashes = $sourceHashes
  runtimeActionsPerformed = @()
  semanticMatchAllowed = $false
  verificationPolicy = 'r3_source_fix_static_only;238_verifying;runtime_build_device_and_legado_diff_deferred'
  followUp = 'Register 237-to-238 static transition only after the current-head audit, source-fix evidence and idempotent queue checks pass; R4 must still compare object, falsy, list, replacement, JSONPath and missing-key cases against fixed Legado before any passed or semantic_match state.'
}
Write-AtomicJson -RelativePath $SourceFixPath -Value $sourceFix
$sourceFix | ConvertTo-Json -Depth 60
