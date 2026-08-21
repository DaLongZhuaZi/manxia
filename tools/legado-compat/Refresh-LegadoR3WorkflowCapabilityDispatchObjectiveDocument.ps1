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
$relativePath = 'docs/analysis/Legado书源V2源码重构持续目标.md'
$path = Join-Path $RepositoryRoot ($relativePath.Replace('/', '\'))
$strictUtf8 = [System.Text.UTF8Encoding]::new($false, $true)
$utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$text = $strictUtf8.GetString([System.IO.File]::ReadAllBytes($path))
$startMarker = '## R3-SOURCE-QUEUE-CONTINUATION-037 队列审计'
$endMarker = '## 单议题执行规则'
$section = @'
## R3-SOURCE-QUEUE-CONTINUATION-037 队列审计

037 源码队列转移已完成：当前唯一活动源码锚点为 `ISSUE-COMPAT-HYPIUM-WORKFLOW-CAPABILITY-DISPATCH`，状态为 `verifying`；`ISSUE-COMPAT-238-JAVA-OBJECT-CONTENT-OVERLOAD` 保持 `verifying` 等待 R4，不重新打开或并行打补丁。037 合并并修复了 safe_read 的 Search/Explore 独立派发、Explore-only 完整读能力门控、缺失/依赖能力结构化结算和导航层非 profile-wide 证据投影。

固定包静态统计为 Search URL 447 条、Explore URL 362 条、双入口 351 条、Explore-only 11 条；6 案例 fixture、29 项静态合同、27 项 current-head 审计及 source-fix 哈希证据全部绑定固定 458 条基线。静态证据只证明源码闭合，不产生运行时兼容结论。

证据：`tools/legado-compat/evidence/r3-workflow-capability-dispatch-037-transition-20260809/transition-consistency.json`、`tools/legado-compat/evidence/r3-workflow-capability-dispatch-037-transition-20260809/registration.json`、`tools/legado-compat/evidence/v2-hypium-workflow-capability-dispatch-source-fix-20260809.json`。R4 的 fresh `full_workflow`/`safe_read`、真实端点、Legado 差分、构建、安装、设备和 458 条批次继续延期。

'@
$section = $section.Replace("`n", "`r`n")
$pattern = '(?s)' + [regex]::Escape($startMarker) + '.*?(?=' + [regex]::Escape($endMarker) + ')'
if (-not [regex]::IsMatch($text, $pattern)) { throw 'objective document queue section marker missing.' }
$updated = [regex]::Replace($text, $pattern, [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $section })
$temporaryPath = "$path.tmp-$PID-$([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())"
try {
  [System.IO.File]::WriteAllText($temporaryPath, $updated, $utf8NoBom)
  Move-Item -LiteralPath $temporaryPath -Destination $path -Force
} finally {
  if (Test-Path -LiteralPath $temporaryPath) { [System.IO.File]::Delete($temporaryPath) }
}
[pscustomobject][ordered]@{ status = 'refreshed'; path = $relativePath; runtimeActionsPerformed = @(); semanticMatchAllowed = $false } | ConvertTo-Json -Depth 10
