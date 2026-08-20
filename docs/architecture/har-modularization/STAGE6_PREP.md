# 漫匣 HAR 模块化 — Stage 6（UI 层）可行性评估（暂缓建议）

> 时间：2026-08-20 ~12:10

## 闭包结果
- reader-ui（Framework/Reader + 阅读器组件 + 阅读页）：46 候选 → 可迁 9（flow monitor/types、ReaderAbilityConstants、ReaderAbilityWindowLifecycleController 等）。
- features-ui（pages/settings + backup/editor/source + 功能页）：44 候选 → 可迁 3（components/editor 三文件）。
- 阻塞大头：MangaAssetLoader 系、BackupPage/settings 各页——依赖 entry 的 Managers/Components/页面互引。

## 结论与建议
1. 干净的 UI HAR 拆分需要先做页面↔Managers↔组件大规模解耦（远超当前收益）。
2. 建议：本计划在 Stage 5 收尾——已抽 5 层（native/core/source-engine/network/novel），UI 与业务管理器留 entry；Stage 6 标记为暂缓/待未来解耦后执行。
3. 可选轻量动作：components/editor 3 文件并入某模块（收益极小，不建议为此新建模块）。

## Stage 7（收尾）核对项
- 清理 entry/src/main/cpp 残留（transfer_rtc 产物、build-windows 等，ACL 后处理）。
- 移动失败留 entry 文件清单留档。
- 文档索引/README 更新；release 构建验证；.bak_harmod 清理；final ledger。
