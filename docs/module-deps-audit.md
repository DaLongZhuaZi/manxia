# 模块依赖审计记录

> **终态说明（2026-06-09）**：HSP 迁移已放弃（原因见 docs/HSP_MIGRATION_PLAN.md 头部决策记录），全部模块维持 HAR。**本审计记录的 P0 状态即为长期有效状态**：各模块依赖必须与真实 import 一致，后续任何新增跨模块导入都必须同步更新所在模块的 oh-package.json5。
> 用途：各期执行前后，核对"每个模块 oh-package.json5 声明的依赖集合"与"该模块源码真实 import 的模块集合"完全一致。
> 依据：AGENTS.md §2.0（多模块依赖与 OhmUrl 解析）；HSP 不支持依赖传递，使用方必须显式声明被使用模块。

## 审计方法

1. 声明集合：读取各模块 oh-package.json5 的 dependencies 键集合。
2. 使用集合：对每个模块 src 目录执行（含单引号、双引号、动态 import 三种形态）：

\`\`\`powershell
# 以 manxia-network 为例
rg "from 'manxia_|from \"manxia_|import\(.*manxia_" <module>/src --type-add 'ets:*.ets' -t ets
\`\`\`

提取每条导入的模块名（manxia_[a-z_]+），与声明集合比对：
- 使用了未声明 → ❌ 未声明依赖（HAR 阶段靠提升侥幸编译，HSP 阶段必失败）
- 声明了未使用 → ❌ 冗余依赖（污染依赖图，应清理）

## 审计结果

### 2026-06-09 P0 执行后（当前状态）

| 模块 | 声明依赖 | 真实使用 | 结论 |
|---|---|---|---|
| entry | ui_resources, core, theme, network, source_engine, novel, reader_ui, features_ui | 同左（core 1320 / theme 734 / features_ui 213 / novel 115 / network 92 / source_engine 82 / reader_ui 55 / ui_resources 12） | ✅ |
| manxia-ui-resources | （无） | （无） | ✅ |
| manxia-native | （无） | （无） | ✅ |
| manxia-core | （无） | （无） | ✅ |
| manxia-source-engine | core | core(34) | ✅ |
| manxia-network | core | core(55) | ✅（原 source_engine 1 处已解耦） |
| manxia-novel | core | core(23) | ✅（原冗余 network 已移除） |
| manxia-theme | core, ui_resources | core(34), ui_resources(3) | ✅ |
| manxia-reader-ui | core, theme, network | core(8), theme(2), network(1) | ✅（原冗余 source_engine 已移除） |
| manxia-features-ui | core, theme | theme(20), core(11) | ✅（原冗余 network/novel/source_engine 已移除） |

结论：**声明集合 == 使用集合，全部通过**；当前依赖图为 DAG，无任何"HAR→(未来)HSP 候选"边，满足 P1 试点前置条件。

### 2026-06-09 P0 执行前（基线，供对照）

- entry：声明 [ui_resources]，实际使用 8 个模块 → ❌ 隐式依赖
- manxia-network：声明 [core]，实际使用 core + **source_engine(1处，未声明)** → ❌（WebViewDataCacheManager.ets:8）
- manxia-novel：声明 [core, network]，实际使用 core → ❌ 冗余
- manxia-reader-ui：声明 [core, theme, source_engine, network]，实际使用 core/theme/network → ❌ 冗余
- manxia-features-ui：声明 [core, theme, network, novel, source_engine]，实际使用 core/theme → ❌ 冗余×3

## P0 解耦方式记录（network → source_engine）

- 新建 ## manxia-core/src/main/ets/Models/WebViewSourceTypes.ets：下沉 MangaInfo/ChapterInfo 两个纯类型接口（字段与原 source_engine 定义逐字段一致）。
- ## manxia-source-engine/.../MangaSourceTypes.ets：删除本地定义，改为从 core 导入并重导出（保持全部既有导入路径兼容；source_engine 内部 3 个使用文件无需改动）。
- ## manxia-network/.../WebViewDataCacheManager.ets：import 改指向 core。
- 类型同一性：entry 侧（MangaDetailPage / MangaDetailLoader 等）经 source_engine 重导出获得的是同一个 core 类型，无任何调用点需要改动。

## 各期执行后请追加审计记录

每完成 HSP 迁移一期（P1/P2/P3），追加一节"YYYY-MM-DD Pn 执行后"审计表。
