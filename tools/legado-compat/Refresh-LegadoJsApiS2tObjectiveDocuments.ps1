[CmdletBinding()]
param(
  [string]$RepositoryRoot = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
  $RepositoryRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
}
$RepositoryRoot = (Resolve-Path -LiteralPath $RepositoryRoot).Path
$utf8Strict = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$targetRevision = '2026-08-09-actual-docs-source-refactor-js-api-s2t-default-runtime'
$objectiveRelative = 'docs/analysis/Legado书源V2源码重构持续目标.md'
$governanceRelative = 'tools/legado-compat/LEGADO_V2_GOVERNANCE_TASKS.md'

function Get-RepoPath {
  param([string]$RelativePath)
  return Join-Path $RepositoryRoot ($RelativePath.Replace('/', '\'))
}

function Write-AtomicText {
  param([string]$RelativePath, [string]$Value)
  $path = Get-RepoPath $RelativePath
  $temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
  try {
    [System.IO.File]::WriteAllText($temporaryPath, $Value, $utf8NoBom)
    Move-Item -LiteralPath $temporaryPath -Destination $path -Force
  } finally {
    if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
  }
}

function Replace-Section {
  param([string]$Text, [string]$StartMarker, [string]$EndMarker, [string]$Replacement)
  $pattern = '(?s)' + [regex]::Escape($StartMarker) + '.*?(?=' + [regex]::Escape($EndMarker) + ')'
  if (-not [regex]::IsMatch($Text, $pattern)) { throw "document section marker missing: $StartMarker" }
  return [regex]::Replace($Text, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $Replacement })
}

$objectivePath = Get-RepoPath $objectiveRelative
$governancePath = Get-RepoPath $governanceRelative
$objectiveDoc = $utf8Strict.GetString([System.IO.File]::ReadAllBytes($objectivePath))
$governanceDoc = $utf8Strict.GetString([System.IO.File]::ReadAllBytes($governancePath))

$objectiveSection = @"
## R3-JS-API-CAPABILITY-SETTLEMENT-PREFLIGHT

当前目标修订为 $targetRevision。静态 JS API 结算已完成：118 个 API token 中 44 个未注册命中已逐个绑定到固定 458 条书源的 140 次出现，并完成固定 Legado 实现、V2 默认 runtime、Native JSVM、工作流和输出消费者分类。结算结果为 SUPPORTED=6、UNSUPPORTED_API=24、NEEDS_INTERACTION=1、NAMESPACE_OR_IMPORT=7、STATIC_MEMBER_REFERENCE=6；这些数字只表示静态证据，不表示运行时兼容。

本轮唯一活动源码议题为 ISSUE-COMPAT-JSAPI-JAVA-S2T-DEFAULT-RUNTIME（verifying）。java.s2t 的源码修复和静态闭环已完成：固定 Legado JsExtensions.kt:551-552 的 ChineseUtils.s2t(text) 语义、4 条受影响 Search 书源、失败见证、V2 六层消费者矩阵、post-fix contract、source-fix 和 current-head 哈希均已登记。037 与所有历史源码议题保持 verifying，只等待 R4。

### S2T 源码静态闭合

1. tools/legado-compat/evidence/contract-legado-jsapi-s2t-default-runtime-pre-fix-20260809.json 的失败状态已保留；不得用 Native JSVM shim、旧执行器或空结果掩盖历史缺口。
2. legado_runtime.html 的默认 java 对象已补齐 s2t，复用现有 t2s 的映射边界，并在 LegadoJsApiContractRegistry.ets 登记为 SUPPORTED；Analyzer、Rule IR、脚本作用域、工作流和输出消费者保持同一结构化错误契约。
3. 静态 post-fix contract、UTF-8/JSON/哈希和证据隔离检查已通过，状态保持 verifying；不启动 458 条批次、网络、构建、安装、设备或 Legado 运行时差分。
4. R4 统一入口保留为唯一关闭条件：定向/全量 Harness、同输入 Legado 差分、构建和真机证据完成后，才允许改变 passed 或 semantic_match。

证据：tools/legado-compat/evidence/r3-jsapi-s2t-default-runtime-target-20260809.json、tools/legado-compat/evidence/contract-legado-jsapi-s2t-default-runtime-pre-fix-20260809.json、tools/legado-compat/evidence/contract-legado-jsapi-s2t-default-runtime-20260809.json、tools/legado-compat/evidence/v2-jsapi-s2t-default-runtime-source-fix-20260809.json、tools/legado-compat/evidence/v2-jsapi-s2t-default-runtime-current-head-audit-20260809-r1/current-head-hash-audit.json、tools/legado-compat/evidence/r3-jsapi-s2t-static-closure-consistency-20260809/consistency.json、tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/semantic-settlement.json、tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/semantic-contract.json、tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/reference-mapping.json。

"@
$objectiveDoc = Replace-Section -Text $objectiveDoc -StartMarker '## R3-JS-API-CAPABILITY-SETTLEMENT-PREFLIGHT' -EndMarker '## 单议题执行规则' -Replacement $objectiveSection
Write-AtomicText -RelativePath $objectiveRelative -Value $objectiveDoc

$governanceSection = @"
## R3 JS API 能力结算与 S2T 源码修复目标（2026-08-09）

当前目标修订为 $targetRevision。静态结算已完成并绑定固定 458 条书源、源包 SHA-256 和 Legado 提交：118 个 API token、44 个未注册 token、140 次出现；分类为 SUPPORTED=6、UNSUPPORTED_API=24、NEEDS_INTERACTION=1、NAMESPACE_OR_IMPORT=7、STATIC_MEMBER_REFERENCE=6。证据：tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/semantic-settlement.json、tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/semantic-contract.json、tools/legado-compat/evidence/r3-js-api-capability-settlement-preflight-20260809/reference-mapping.json。

java.s2t 已完成五项候选门禁和源码静态闭合，当前唯一活动源码议题 ISSUE-COMPAT-JSAPI-JAVA-S2T-DEFAULT-RUNTIME 保持 verifying：固定 Legado JsExtensions.kt:551-552、4 条 Search 书源、默认 ArkWeb 修复、V2 六层消费者矩阵、post-fix contract、source-fix 和 current-head 哈希均已登记。037 及旧议题保持 verifying，R4 运行时、原版差分、构建、安装和设备继续延期。

当前只允许保留静态证据链和队列门禁；默认 runtime 与 registry 的源码修复及 post-fix contract 已完成。禁止 Native shim 回退、空结果伪通过、458 条运行时批次和真实网络；下一议题必须独立通过五项证据门禁。

候选证据：tools/legado-compat/evidence/r3-jsapi-s2t-default-runtime-target-20260809.json、tools/legado-compat/evidence/contract-legado-jsapi-s2t-default-runtime-pre-fix-20260809.json、tools/legado-compat/evidence/contract-legado-jsapi-s2t-default-runtime-20260809.json、tools/legado-compat/evidence/v2-jsapi-s2t-default-runtime-source-fix-20260809.json、tools/legado-compat/evidence/v2-jsapi-s2t-default-runtime-current-head-audit-20260809-r1/current-head-hash-audit.json、tools/legado-compat/evidence/r3-jsapi-s2t-static-closure-consistency-20260809/consistency.json、tools/legado-compat/fixtures/legado-jsapi-s2t-default-runtime.json。

"@
$governanceDoc = Replace-Section -Text $governanceDoc -StartMarker '## R3 JS API 能力结算与 S2T 源码修复目标（2026-08-09）' -EndMarker '<!-- LEGADO_V2_GOVERNANCE_TASK_MIRROR:START -->' -Replacement $governanceSection
Write-AtomicText -RelativePath $governanceRelative -Value $governanceDoc

foreach ($relative in @($objectiveRelative, $governanceRelative)) {
  $text = $utf8Strict.GetString([System.IO.File]::ReadAllBytes((Get-RepoPath $relative)))
  if ($text.IndexOf([char]0) -ge 0 -or $text.IndexOf([char]9) -ge 0 -or $text.IndexOf([char]11) -ge 0) {
    throw "control character found after refresh: $relative"
  }
  if (-not $text.Contains($targetRevision)) { throw "target revision missing after refresh: $relative" }
}

[pscustomobject][ordered]@{ status = 'refreshed'; targetRevision = $targetRevision; documents = @($objectiveRelative, $governanceRelative); runtimeActionsPerformed = @(); semanticMatchAllowed = $false } | ConvertTo-Json -Depth 10
