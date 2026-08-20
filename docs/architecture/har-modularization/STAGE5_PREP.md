# 漫匣 HAR 模块化 — Stage 5（manxia-novel）实施记录

> 时间：2026-08-20 ~06:30（实施；M5 待编译）

## 闭包分析
- 目标域：Framework/{Novel,ReadAloud,Rss}
- 可迁 26 文件：Legado 叶子/解析/兼容层(HtmlFormatter/LegadoSourceParser/LegadoCookieStore/LegadoWebViewExecutor/NativeJsEngine 等)、LegadoCompatibilityCompiler、NovelCoverGenerator、RhinoWasmExecutor、ReadAloud 叶子、Rss schema。
- 阻塞 45 项：依赖 Models(NovelModels/TextReaderModels)/Managers/页面(SettingsManager/UIContextManager/VersionHistoryManager/ProxyManager 等) → 留 entry。

## 实施
- 新建 manxia-novel（manxia_novel HAR，依赖 manxia_core + manxia_network）。
- git mv 26 文件迁入；entry 48 文件 110 处 import 改 manxia_novel 深路径。
- 校验：residual=0、dangling=0。

## M5 验收
- 编译（先 ohpm install 同步新模块依赖）；回归：小说书架/详情/搜索/阅读/朗读/规则排错/RSS 订阅阅读/图源管理。
