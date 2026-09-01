# 漫匣 HSP 迁移实施计划 v2

> ## ⛔ 状态：已放弃（2026-06-09 用户决策）
>
> **最终决定**：放弃 HSP 模式，全部模块维持 HAR。P1 试点（manxia_reader_ui）已完整回滚为 HAR，工程恢复到迁移前形态。
>
> **中止原因（按权重排序）**：
>
> 1. **运行时 record 解析不匹配（阻断性）**：P1 实测中，entry abc 请求带版本号的 record（`&manxia_reader_ui/src/main/ets/...&1.0.0`），而 HSP abc 提供的是无版本号 record（`&manxia_reader_ui/src/main/ets/...&`），运行时 hole 解析失败 → ReferenceError → 启动瞬间闪退且无传统 crash 日志。全量清理重建（build 目录 / .hvigor / 全局 daemon workspace）后未再验证通过即决策中止，工具链 6.1.0(23) 下"深度路径导入 HSP"的运行时可靠性存疑。同一问题族见华为问答 0204171913115533008、官方 FAQ faqs-package-structure-66。
> 2. **安装工作流复杂化（确定性成本）**：HSP 必须随 HAP 联合安装（9568305），IDE 需勾选 Auto Dependencies / Deploy Multi Hap，hdc 冒烟脚本需改为多包目录安装，每次新增 HSP 都要维护安装清单。
> 3. **收益与成本不匹配（本质原因）**：4 个候选模块合计约 3.3 万行，entry 自身 53.3 万行——包体基本无变化，启动收益需额外的动态 import() 改造（P4）才可能出现，而依赖治理这一最大收益已由 P0 独立达成并保留。
> 4. **配套基础设施脆弱（运维成本）**：type/hvigorfile.ts 双文件联动、daemon workspace 缓存、多包签名与部署，每一环都有独立故障面；本次试点即实际触发了 00303278、00308018 两类基础设施故障。
>
> **保留的资产（不受放弃影响）**：
> - **P0 依赖显式化治理已生效并保留**：entry oh-package 8 依赖补齐、network→source_engine 类型解耦（core 新增 WebViewSourceTypes）、4 组冗余声明清理、依赖审计通过（docs/module-deps-audit.md）。
> - 经验沉淀：AGENTS.md §2.0（模块依赖与 OhmUrl 解析规则、HAR↔HSP 转换配套清单、record 不匹配排查法）。
> - 全部备份文件（*.bak_20260609_*）保留在原位。
>
> **回滚记录**：manxia-reader-ui 的 module.json5（type: har）与 hvigorfile.ts（harTasks）已从备份恢复；已核验 10 个模块 type 与 hvigorfile system 全部一致。**设备上如仍装着 HSP 版本，需先卸载再安装 HAR 版本**。
>
> **若未来重启此方案的前提**：官方文档明确支持 HSP 深度路径导入（或接受全量 index.ets 桶导出模式）；在干净工具链环境完成 P1 全流程验证；重新评估收益（届时应优先评估 P4 动态 import() 的独立可行性）。
>
> 以下为原方案正文（保留作为分析与决策依据存档）：

---

## 0. 结论速览（TL;DR）

1. **可以做，但收益要摆正**：本工程 4 个 HSP 候选模块合计约 **3.3 万行**，而 entry 自身有 **53.3 万行**（占绝对大头）。HSP 化的真实收益排序是：**依赖治理显式化 > 增量编译改善 > 启动/延迟加载收益（需额外改造才有）> 包体（基本无变化）**。v1 中"entry HAP 显著瘦身"的预期需要下调。
2. **v1 的分期方案有一个顺序问题**：v1 二期只转 manxia_source_engine，此时 manxia_reader_ui / manxia_features_ui 仍是 HAR 并声明依赖它，manxia_network 还真实 import 了它一次——产生 **HAR→HSP 边**。官方对 HAR 依赖 HSP 长期表述为不支持。v2 通过**先做依赖清理（P0）**保证任意时刻不存在 HAR→HSP 边，再按"叶子模块优先"顺序转换。
3. **实测发现比 v1 乐观的事实**：4 个候选模块 **0 处 $r('app.*') 资源引用、0 个 Worker/TaskPool、0 个页面、0 个 UIAbility**；实际跨模块 import 也比 oh-package 声明少得多（多的是冗余声明）。迁移面远小于 v1 估计。
4. **实测发现的 3 个真实隐患**（v1 未发现）：
   - manxia-network 有 **1 处未声明的 manxia_source_engine 导入**（WebViewDataCacheManager.ets:8），是当前唯一的"真实传递依赖"；
   - manxia-features-ui 的 ContentPanel.ets 通过**宿主 context** 读取本模块 rawfile，HAR 阶段资源合并进 entry 所以能用，转 HSP 后会**运行时读取失败**（需改 createModuleContext）；
   - entry 的**启动链**（EntryAbility/MyAbilityStage/MainMenuPage/SplashPage）静态 import 了 4 个候选模块中的多个——不改造导入方式，HSP 在启动期就会加载，**按需加载不会自动生效**。
5. **两处官方文档不确定点，不用假设，用实测门（P1 spike）确认**：a) HSP 深度路径导入（hsp名/src/main/ets/...）是否与 HAR 一样可用；b) HAR 依赖 HSP 在当前工具链下的实际行为（设计上已避开，spike 顺带确认）。本环境无法直接抓取官方文档原文（网络策略限制），故以"官方文档结论 + 项目内实测"双轨确认。

---

## 1. 与 v1 分析的差异校正

| # | v1 表述 | 实测结论（2026-06-09） | 影响 |
|---|---|---|---|
| 1 | §1.1 依赖表：network 被 novel/features_ui/entry 依赖；reader_ui 依赖 core/theme/source_engine | **全部过时**：reader_ui 现在依赖 core/theme/**network**；声明与真实 import 均有出入（见 §2.2） | 依赖清理清单重制 |
| 2 | §1.3 依赖图无传递依赖 | **存在 1 处真实未声明依赖**：network → source_engine（WebViewDataCacheManager.ets:8） | P0 必须解耦 |
| 3 | §2/§7 分期：二期先转 source_engine，reader_ui/features_ui 保持 HAR | 会产生 **HAR→HSP 边**，按官方约束不可行 | 分期顺序重排：先清理依赖，叶子模块优先 |
| 4 | §6 so 按需加载：把 so 的 devDependencies 从 entry 挪到 novel/features_ui 的 oh-package | **不可行**：.so 打包归属由"哪个模块构建/包含它"决定，改依赖声明不会让 .so 进 HSP；需把 CMake/so 迁入 HSP 模块内部重建 | so 迁移降级为 P4 独立 spike，不阻塞主线 |
| 5 | §8 预期对比：entry HAP 显著瘦身、启动只加载核心 HAR | 候选 4 模块合计 ≈3.3 万行 vs entry 53.3 万行；且 entry 启动链静态 import 了候选模块，**不改导入方式则启动照样全量加载** | 收益预期修正（§2.4），延迟加载单列为 P4 |
| 6 | §9 资源审查"需 grep 确认" | 已完成：候选模块 $r('app.*') 为 0；唯一风险点是 features-ui 的 rawfile 经宿主 context 读取（3 处，见 §2.5） | P2 带小修 |
| 7 | §1.2 "entry 隐式依赖 7 个模块" | 确认属实，且 entry 启动链也引用了候选模块（EntryAbility: network/features_ui/reader_ui；MainMenuPage: source_engine/novel/features_ui） | P0 补声明；P4 延迟加载依据 |

---

## 2. 当前工程实况（全部为实测数据）

### 2.1 模块与类型

| 模块 | 目录 | type | 体量（.ets 行数） |
|---|---|---|---|
| entry（HAP） | ./entry | entry | **533,467**（581 文件） |
| manxia_core | ./manxia-core | har | 46,037 |
| manxia_theme | ./manxia-theme | har | 14,133 |
| manxia_network | ./manxia-network | har | 15,102 |
| manxia_source_engine | ./manxia-source-engine | har | 13,542 |
| manxia_novel | ./manxia-novel | har | 12,744 |
| manxia_features_ui | ./manxia-features-ui | har | 4,576 |
| manxia_reader_ui | ./manxia-reader-ui | har | 1,938 |
| manxia_ui_resources | ./manxia-ui-resources | har | 660 |
| manxia_native | ./manxia-native | har（纯 native，0 ets import） | — |

所有 9 个 HAR 的 module.json5 均极简：无 UIAbility、无 pages、无 routerMap；候选 4 模块 **0 Worker/TaskPool**。

### 2.2 oh-package 声明 vs 真实 import（重点差异）

真实 import 图（from 'manxia_xxx/src/main/ets/...' 深度路径；各模块 index.ets 均为占位，**无桶导出**）：

```
entry            → core(1320), theme(734), features_ui(213), novel(115),
                   network(92), source_engine(82), reader_ui(55), ui_resources(12)
manxia_theme     → core(34), ui_resources(3)
manxia_source_engine → core(34)
manxia_network   → core(55), source_engine(1)   ⚠️ 未声明依赖
manxia_novel     → core(23)                      声明了 network 但 0 使用
manxia_reader_ui → core(8), theme(2), network(1) 声明了 source_engine 但 0 使用
manxia_features_ui → theme(20), core(11)         声明了 network/novel/source_engine 但均 0 使用
```

| 模块 | 声明依赖 | 真实使用 | 差异处理（P0） |
|---|---|---|---|
| entry | ui_resources | 全部 8 个 | **补齐声明** |
| source_engine | core | core | ✅ 一致 |
| network | core | core + **source_engine(1处)** | **解耦该处导入**（见 P0-2） |
| novel | core, network | core | 移除 network 声明 |
| theme | core, ui_resources | core, ui_resources | ✅ 一致 |
| reader_ui | core, theme, source_engine, network | core, theme, network | 移除 source_engine 声明 |
| features_ui | core, theme, network, novel, source_engine | core, theme | 移除 network/novel/source_engine 声明 |

### 2.3 启动链静态导入现状（按需加载的现实约束）

| 启动文件 | import 的模块 |
|---|---|
| MyAbilityStage | core(1), theme(1) |
| SplashPage | core(4), theme(4) |
| EntryAbility | core(13), theme(5), **network(4), features_ui(1), reader_ui(1)** |
| MainMenuPage | core(29), theme(18), ui_resources(1), **source_engine(3), features_ui(3), network(3), novel(1)** |

结论：4 个候选模块都已被启动链静态引用。**只转 HSP 不改导入方式 = 启动期照样全量加载**（ArkTS 静态 import 在宿主页面模块加载时即解析依赖）。真正的"按需加载"必须把启动链对这些模块的引用改为使用点动态 import()——本项目已有 26 处动态 import 先例（含跨模块 await import('manxia_theme/.../FontManager')），模式可行，但属于独立改造（P4）。

### 2.4 收益校准（诚实版）

| 收益项 | 预期 | 依据 |
|---|---|---|
| 依赖治理 | ★★★★★ | entry 隐式依赖 + 4 组冗余声明 + 1 处未声明依赖全部清零，构建可复现性恢复 |
| 增量编译速度 | ★★★☆☆ | HSP 独立产物，改动 HSP 内代码不重编 entry 全量；但 entry 自身 53 万行才是编译大头 |
| 启动性能 | ★☆☆☆☆（P3 后）→ ★★★☆☆（P4a 后） | 见 §2.3；P4a 动态 import 后启动链不再加载 4 个 HSP |
| 包体 | ≈0 | 单 HAP 场景 HSP 跟随 App 打包，总体积不变（官方一致结论）；混淆（未开启）才是减包手段 |
| 稳定性风险 | 中 | 全部转换均为官方支持操作 + 每期可独立回滚 |

### 2.5 资源 / rawfile 审计结果

- 候选模块 $r('app.*')：**0 处**（无跨模块资源引用风险）。
- features-ui：20 处 $r('sys.*')（系统资源，HSP 内可用 ✅）；2 处 $rawfile('code_editor/*.html') + 1 处 context.resourceManager.getRawFileContent()。
- code_editor/*.html 等文件**物理存在于 features-ui 自己的 rawfile 目录**。HAR 阶段资源合并进 entry，ContentPanel.ets:581-583 用宿主 UIAbilityContext.resourceManager 能读到；**转 HSP 后宿主资源表不再包含这些文件，该处会运行时失败**。
- 修复方案（P2 执行）：改用 context.getApplicationContext().createModuleContext('manxia_features_ui').resourceManager，或把 ContentPanel 的读取改为与另 2 处一致的组件内 $rawfile 方案（Web 组件 src 场景可直接用）。

---

## 3. 官方规则依据与两处实测门

### 3.1 官方结论（约束类，直接采纳）

依据：《应用内HSP》（in-app-hsp）、《共享包概述》（shared-packages-overview）、《HSP转HAR指导》（hsp-to-har）、《module.json5 配置文件说明》。核心规则：

1. HSP 不能独立安装/运行，必须随宿主 HAP 一起打包安装；版本号与 HAP 一致。
2. HSP 不支持声明**入口** UIAbility；本项目候选模块无任何 Ability ✅。
3. HSP 可以依赖 HAR 或其他 HSP；**禁止循环依赖**；**不支持依赖传递**（使用方必须自己显式声明被使用模块）。
4. HAR 为静态共享包（编译期合并进依赖方）；HSP 运行时动态加载、全局单实例。
5. HAR 依赖 HSP：官方文档长期表述为不支持。**v2 的设计原则：任意构建状态下不允许出现 HAR→HSP 边**（用 P0 依赖清理 + 分期顺序保证）。
6. HSP 内资源不与宿主合并；$r('app.*') / $rawfile 解析到 HSP 自身资源表；跨模块取 HSP 资源需 createModuleContext。
7. 转换机制官方支持且可逆：改 module.json5 的 type 为 shared（回退改回 har 即可，hsp-to-har 指南即逆操作）。

### 3.2 两处不确定点 → 用 P1 实测门确认（不靠假设）

| # | 问题 | 官方文档表述清晰度 | 验证方式 |
|---|---|---|---|
| U1 | HSP 深度路径导入（manxia_reader_ui/src/main/ets/...）在 useNormalizedOHMUrl: true 下是否与 HAR 一致可用 | 官方示例多用包名+index 导出，深度路径未明确承诺 | P1 试点直接实测：reader_ui 转 HSP 后 entry 的 55 处深度导入是否编译通过 |
| U2 | HAR 依赖 HSP 在 6.1.0(23) 工具链下的实际行为 | 不同版本文档表述有出入 | P0 完成后本项目已无该边；spike 期间顺带记录 |

> 若 U1 实测失败：降级方案 = 为目标模块补全 index.ets 桶导出，entry 侧导入改包名。规模可控（reader_ui 55 处/约 20-30 个符号；source_engine 82 处），但会显著增加 P2/P3 工作量，因此 P1 必须最先做。

---

## 4. 目标架构

### 4.1 P0 完成后的依赖图（转换前置态，全 HAR，行为零变化）

```
entry (HAP)  ──显式声明全部 8 个依赖──┐
   ├─ manxia_core          (HAR, 0 依赖)
   ├─ manxia_ui_resources  (HAR, 0 依赖)
   ├─ manxia_theme         (HAR → core, ui_resources)
   ├─ manxia_network       (HAR → core)            ← 解耦后不再引用 source_engine
   ├─ manxia_source_engine (HAR → core)            ← 依赖方仅剩 entry
   ├─ manxia_novel         (HAR → core)            ← 依赖方仅剩 entry
   ├─ manxia_reader_ui     (HAR → core, theme, network)  ← 依赖方仅剩 entry
   └─ manxia_features_ui   (HAR → core, theme)     ← 依赖方仅剩 entry
```

特点：**任意 HAR 不依赖任何 HSP 候选**；每个候选模块（reader_ui/novel/features_ui/source_engine）的唯一依赖方是 entry(HAP)。此后任何单个模块转 HSP 都不再牵连其他 HAR。

### 4.2 最终态（P3 完成后）

```
entry (HAP)
   ├─ core / ui_resources / theme / network   (HAR，启动地基)
   ├─ manxia_source_engine (HSP → core)         按需
   ├─ manxia_novel         (HSP → core)         按需
   ├─ manxia_reader_ui     (HSP → core, theme, network)  按需
   └─ manxia_features_ui   (HSP → core, theme)  按需
```

页面全部留在 entry（候选模块 0 页面，无需 routerMap，entry 的 main_pages 路由方式不变）。页面下沉 routerMap 列入 P4 可选项。

---

## 5. 分期实施计划

> 每期规则：改动前对目标文件做 *.bak 备份；每期一个独立提交点；**编译验证由用户在 DevEco Studio 执行**（遵守"代理不自动编译"约定）；每期附验收清单，验收不过不进下一期。

### P0：依赖显式化与解耦（不转 HSP，行为零变化）

> **执行状态（2026-06-09）**：代码改动已全部完成（P0-1/2/3/5），依赖审计通过（见 docs/module-deps-audit.md）。待用户在 IDE 内执行 ohpm sync/ohpm install 并构建验证后，P0 方可关闭。

| # | 改动 | 文件 |
|---|---|---|
| 1 | entry 显式声明 8 个依赖：core/theme/network/source_engine/novel/reader_ui/features_ui/ui_resources | entry/oh-package.json5 |
| 2 | 解耦 network→source_engine 的唯一导入：WebViewDataCacheManager.ets:8 只用 MangaInfo/ChapterInfo 两个类型。方案 A（首选）：把这两个纯类型接口下沉/复制到 manxia_core 的 Models（若 core 已有同构类型则复用并改 import）；方案 B：network 内部定义本地同构类型 | manxia-network/.../WebViewDataCacheManager.ets（+ 可能新增 core 类型文件） |
| 3 | 移除冗余声明：novel 删 manxia_network；reader_ui 删 manxia_source_engine；features_ui 删 network/novel/source_engine 三个声明 | 三个 oh-package.json5 |
| 4 | ohpm install 刷新 oh_modules（若 entry 锁文件被 IDE 占用 EPERM，由用户在 IDE 内 sync） | — |
| 5 | 建立依赖审计核对（声明集合 == 真实 import 集合，方法见 §7） | 文档记录 |

**验收门 P0**：用户 IDE 构建通过；真机冒烟（书库/阅读器/设置/小说入口）；审计输出"无未声明、无冗余"；git diff 仅含上述文件。
**规模**：约 6 个文件，半天内。

### P1：HSP 试点——manxia_reader_ui（最小模块，风险最低）

> **执行状态（2026-06-09，运行时排障中）**：
> 1. 编译 ✅：55 处深度路径导入对 HSP 编译通过（U1 编译层面成立）；hvigorfile.ts 曾报 00303278 已修复（教训已沉淀 AGENTS §2.0）。
> 2. 安装 ✅（需 Auto Dependencies / 多包部署，R4 已落地并更新 AGENTS §2.2）。
> 3. **运行时 ❌ 启动瞬间闪退**：`cannot find record '&manxia_reader_ui/src/main/ets/...&1.0.0'` → ReferenceError → 进程退出（无传统 crash 日志，需看 hilog 的 JS_ERROR/AppKit 行）。
> 4. **字节级取证结论**：entry abc 请求带版本号的 record（`&路径&1.0.0`），HSP abc 提供的 record 无版本号（`&路径&`）→ 名称不匹配。与社区案例一致（华为问答 0204171913115533008 等：模块类型/版本变更后旧缓存导致 record 不匹配；官方 FAQ faqs-package-structure-66 同族问题）。
> 5. **全量清理与基础设施恢复（已完成）**：① 全部模块 build 目录 + .hvigor 已删除；② 清理过程曾损坏全局 hvigor daemon workspace（`node_modules/@ohos/hvigor`、`@ohos/hvigor-ohos-plugin` junction，报 00308018 `Cannot find module '@ohos/hvigor'`），已通过重建 junction 全部修复（24/24，含其他项目）；③ `entry\.cxx\...\arm64-v8a` 旧 CMake 缓存因 IDE 锁定暂残留，若重建时报 generator 冲突，关闭 IDE 后手动删除即可。
> 6. **回滚已完成（2026-06-09 用户决策放弃 HSP）**：reader_ui 已恢复 HAR（module.json5 + hvigorfile.ts 从备份恢复），全部模块 type/system 核验一致。待用户重建 + 卸载设备旧应用 + 全新安装 + 回归。
> 7. **回滚遗留（IDE 运行配置，2026-06-09）**：`.idea/workspace.xml` 中运行配置残留试点设置（`DEPLOY_MULTI_HAP=true` 且 `MULTI_HAP_MODULE_DATA` 选中 manxia_reader_ui），回滚后 IDE 找不到 `.hsp` 产物 → 安装报 00401022 "本地HAP包不存在"。处理：Run > Edit Configurations → Deploy Multi Hap Packages 标签页取消勾选（或移除 manxia_reader_ui 选中项）；设备上先卸载 HSP 版应用再装 HAR 版。

改动清单：
1. manxia-reader-ui/src/main/module.json5："type": "shared"，新增 "deliveryWithInstall": true（其余不动）。
2. **manxia-reader-ui/hvigorfile.ts：harTasks → hspTasks（P1 实测发现的关键配套改动：module.json5 的 type 必须与 hvigorfile.ts 导出的 system 插件一致，否则报 00303278 Configuration Error。P2/P3 转换时同样必须改此文件）**。
3. ohpm install（刷新 oh_modules 中该模块的产物形态）。
4. entry 不需要新改（P0 已显式依赖）；MangaReaderAbility / NovelReaderAbility（entry 内 UIAbility）继续引用 reader_ui 组件——HAP→HSP 合法。

**P1 必须回答的验证问题（spike 清单）**：

- [ ] U1：entry 的 55 处 manxia_reader_ui/src/main/ets/... 深度导入编译是否通过？
- [ ] HSP→HAR（reader_ui→core/theme/network）编译是否通过？
- [ ] IDE 构建 + 安装 + 启动是否正常（观察 IDE 是否自动带上 .hsp）？
- [ ] **工作流变化确认**：hdc install -r entry-default-signed.hap 单包安装是否失效？若失效，记录正确的 hdc 多包安装命令或改用 IDE 运行（涉及 AGENTS §13 冒烟脚本流程）。
- [ ] 阅读器全链路（漫画/电子书/小说三种 ReaderAbility）真机回归。
- [ ] 包体记录：改造前后 entry-default-unsigned.hap 与 App 包大小（写入 §7 度量表）。

**回滚**：type 改回 har + ohpm install，零代码残留。
**若 U1 失败的降级**：补全 reader_ui index.ets 全量导出，entry 侧 55 处导入改包名，再继续。

### P2：manxia_novel + manxia_features_ui 转 HSP（两个独立提交点）

- novel：module.json5 同 P1 改法；依赖方仅 entry，独立可转。注意 jsvm/quickjs 等 so 仍由 entry 打包（.so 在 HAP 的 libs 中，运行时可加载，novel 功能不受影响）。
- features_ui：同上；**转换同时修 3 处 rawfile 访问**（ContentPanel.ets 宿主 context 读取改 createModuleContext('manxia_features_ui')；CodeEditorComponent / MarkdownViewerComponent 的 $rawfile 在 HSP 内解析自身资源，预期天然可用，真机验证）。
- 每转一个：构建 + 全功能冒烟（编辑器/设置页/书源管理）。

### P3：manxia_source_engine 转 HSP（最大模块，13.5k 行）

- 前置：P0-2 已解耦 network 对它的引用（此时依赖方仅 entry）。
- 改法同 P1；重点回归：图源浏览/搜索/详情/WebView 引擎全链路（entry 82 处导入）。

### P4（可选，独立立项）：真·按需加载与进阶优化

| 子项 | 内容 | 备注 |
|---|---|---|
| 4a 延迟加载 | EntryAbility / MainMenuPage 对 novel/source_engine/features_ui/reader_ui 的静态 import 改为使用点 await import()（项目已有 26 处先例） | 用 §7 启动基线对比验证收益 |
| 4b 页面下沉 | 将阅读器/设置类页面移入对应 HSP 并声明 routerMap | 改动大，仅在 4a 后仍有诉求时评估 |
| 4c so 分拆 | 把 jsvm/quickjs（novel 用）、transfer_rtc（传书用）的 native 构建迁入对应 HSP 模块 | 需在 HSP 内重建 CMake 构建，独立 spike；**不是改依赖声明** |
| 4d 混淆 | 开启 release 混淆（当前 enable: false），规则需覆盖 HSP 导出符号 | 与 HSP 无耦合，可先行单独做 |

---

## 6. 风险登记册

| ID | 风险 | 概率/影响 | 缓解 |
|---|---|---|---|
| R1 | HSP 深度路径导入不可用（U1） | 低-中/高 | P1 最先试点；降级方案 = index.ets 全量桶导出 + 导入改包名 |
| R2 | 过渡期出现 HAR→HSP 边导致构建失败 | 中/高 | 分期顺序保证不存在该边；P0 审计把门；每期只动一个模块 |
| R3 | HSP 资源不合并导致 rawfile 运行时失败 | 已定位（3 处）/中 | P2 修复 ContentPanel；编辑器组件真机回归 |
| R4 | hdc 单包安装流程失效 | 高/低 | P1 记录新安装方式；IDE 运行为主；更新 AGENTS §13 冒烟脚本安装步骤 |
| R5 | 启动收益不及预期 | 高/中 | 预期已在 §2.4 校准；真收益在 P4a，先打启动耗时基线 |
| R6 | HSP 全局单实例改变单例语义 | 低/低 | 本工程单 HAP，无多实例场景；core 单例仍在 HAR，无迁移 |
| R7 | 循环依赖（HSP↔HSP/HAR） | 低/高 | 目标图为 DAG；审计核对 |
| R8 | 混淆（未来开启）与 HSP 导出交互 | 中/中 | 混淆未开启；若开启需为 HSP 保留导出符号规则 |

---

## 7. 度量与验证方法

1. **启动基线（P0 期采集，用于 P4 对比）**：真机 hilog 过滤 EntryAbility/MyAbilityStage 冷启动时间戳，取 5 次中位数；或用 Profile 工具启动分析。
2. **包体记录（每期）**：记录 entry/build/default/outputs/default/entry-default-unsigned.hap 与 App 包（*.app）大小。
3. **依赖审计（每期）**：跑 §2.2 的导入统计（rg "from 'manxia_" 各模块 src），核对声明集合 == 使用集合。
4. **功能回归基线**：书库浏览 → 图源搜索 → 漫画详情 → 阅读（漫画/电子书/小说）→ 设置各子页 → 编辑器组件 → 局域网传书 → 备份恢复。P1-P3 每期至少覆盖与该模块直接相关链路 + 主路径冒烟。
5. **安装方式确认（P1）**：IDE 运行安装；hdc 场景验证 hdc install -r <hap> <hsp>（多文件）是否可用，结论回写 AGENTS §13。

---

## 8. 明确不做的事

1. 不转 manxia_core / manxia_theme / manxia_network / manxia_ui_resources（启动地基，转 HSP 收益低风险高）。
2. 不在本轮引入 integratedHsp（集成态 HSP 用于跨应用共享，单应用不需要）。
3. 不一次性把 entry 页面下沉到 HSP routerMap（P4b 可选）。
4. 不通过改依赖声明的方式搬运 .so（P4c 单独 spike）。
5. 不做运行时热更新类设计（官方 HSP 不支持独立更新）。

---

## 附录 A：官方文档链接

- 应用内 HSP：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/in-app-hsp
- 共享包概述：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/shared-packages-overview
- HSP 转 HAR 指导：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/hsp-to-har
- HAR 转 HSP FAQ（DevEco）：https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs-V5/faqs-project-management-7-V5
- HSP/HAR 快速切换 FAQ：https://developer.huawei.com/consumer/cn/doc/harmonyos-faqs-V5/faqs-package-structure-49-V5
- 如何正确引用 HAR/HSP 包模块 FAQ：https://developer.huawei.com/consumer/cn/doc/doccenter-dev-faq/faqs-package-structure-21
- module.json5 配置说明：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/module-configuration-file
- OpenHarmony 文档源（in-app-hsp.md 等）：https://gitee.com/openharmony/docs/tree/OpenHarmony-6.0-Release/zh-cn/application-dev/quick-start

## 附录 B：本计划的实测数据来源（2026-06-09）

- 各模块 oh-package.json5（dependencies 实读）
- 全仓 rg "from 'manxia_" 逐模块导入统计（entry 2623 处 + 各 HAR）
- SplashPage / EntryAbility / MyAbilityStage / MainMenuPage / MangaReaderAbility / NovelReaderAbility 导入清单
- 候选模块 $r('app.*') / $rawfile / resourceManager / Worker / TaskPool 扫描（结果：仅 features-ui 3 处 rawfile 相关）
- 候选模块 module.json5 全文（无 Ability/pages/routerMap）
- 代码体量统计（pwsh 逐目录行数）
- entry/build-profile.json5（混淆 enable: false）
- 依赖审计中发现的 manxia-network → manxia_source_engine 唯一未声明导入：manxia-network/src/main/ets/Framework/Cache/WebViewDataCacheManager.ets:8
