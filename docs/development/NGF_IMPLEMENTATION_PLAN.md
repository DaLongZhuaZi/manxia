# NGF 框架实施计划（基于 Manxia 当前版本）

## 1. 文档信息

- 文档名称: NGF 框架实施计划
- 文档版本: v0.1
- 维护范围: `manxia` 主仓库（HarmonyOS Next / ArkTS）
- 编写日期: 2026-04-13
- 状态: 可执行草案（可直接进入第一阶段）

## 2. 背景与目标

### 2.1 背景

当前 `manxia` 已形成完整应用能力栈，且在日志中已存在 NGF 标识（`[NGF]`），具备抽象为通用开发框架的基础。项目在运行时、数据、图源引擎、窗口策略、导航治理等方向已经成熟，但页面层和部分数据层存在高耦合与体量过大问题，不适合一次性拆分。

### 2.2 目标

构建一个可复用于新软件开发的 NGF（Next Generation Framework）框架，要求：

1. 可在不重写业务页面的前提下先行落地。
2. 保持当前功能等价，迁移过程中允许“旧实现 + 新接口”并行。
3. 能提供最小可用 Starter（新项目可起步）。
4. 对 HarmonyOS Next API 及 ArkTS 规则友好。

### 2.3 成功标准

1. 新建应用可基于 NGF 启动、记录日志、完成生命周期编排、接入窗口策略。
2. 图源仓库与 workflow 执行能力可在 NGF 中独立复用。
3. 迁移期间主应用可持续发布，不出现大范围回归。
4. 关键模块有明确接口契约、迁移清单与回滚路径。

## 3. 现状基线（代码梳理摘要）

### 3.1 基础设施已具备框架雏形

1. Logger 全局使用 `[NGF]` 前缀，调用覆盖面广。
2. 启动流程是阶段化管理（可监听、可失败分支、可完成态）。
3. 窗口显示模式与页面策略已有集中治理层。

### 3.2 高耦合热点

1. `DataManager` 职责面大（数据、缓存、存储、插件交叉）。
2. 页面层存在超大文件（例如 `MainMenuPage`、`UnifiedDetailPage`）。
3. 历史命名残留（如 `GameEvent`、`GameError`）影响框架语义清晰度。

### 3.3 可插件化资产

1. `manxia-extensions-source/index.main.json` 已形成仓库索引模型。
2. 单图源 `source.json` 具备 `metadata/capabilities/network/workflows` 分层。
3. WebView / API / Novel 三类内容引擎可向统一执行契约收敛。

## 4. NGF 目标架构与模块边界

采用“核心稳定层 + 平台适配层 + 能力插件层 + 业务接入层”的四层结构。

## 4.1 模块划分

### 4.1.1 `ngf-core`

职责:

1. 日志系统接口与默认实现（含等级、tag、格式化、埋点钩子）。
2. 事件总线（类型安全事件模型）。
3. 错误模型与错误恢复流程。
4. 生命周期与任务编排（初始化阶段、状态发布、失败处理）。
5. 轻量 DI 容器与服务注册协议。

输出:

1. `ILogger`、`IEventBus`、`IErrorHandler`、`ILifecycleOrchestrator`、`IServiceContainer`。

### 4.1.2 `ngf-platform-ohos`

职责:

1. HarmonyOS UIContext 适配。
2. 窗口模式与系统栏治理。
3. 页面窗口策略协调（DisplayMode、PagePolicy、Transition）。
4. 平台能力桥接（权限、能力上下文、主窗口句柄）。

输出:

1. `IPlatformWindowController`、`IPageWindowPolicyResolver`、`IOhosContextBridge`。

### 4.1.3 `ngf-data`

职责:

1. 数据访问抽象（Repository + Unit of Work 风格可选）。
2. 设置系统抽象（KV、Schema、默认值策略）。
3. 缓存与存储契约（内存缓存、磁盘缓存、沙箱目录）。
4. 数据迁移与版本策略。

输出:

1. `IDataFacade`、`ISettingsStore`、`ICacheStore`、`IStorageProvider`、`IDbMigrator`。

### 4.1.4 `ngf-content-workflow`

职责:

1. 通用 workflow 执行器（action pipeline）。
2. HTTP/API/脚本/提取器等动作执行协议。
3. 执行上下文、重试、限流、错误回退策略。

输出:

1. `IWorkflowEngine`、`IActionExecutor`、`IRetryPolicy`、`IRateLimitPolicy`。

### 4.1.5 `ngf-content-source`

职责:

1. 图源仓库索引管理、同步、校验。
2. 图源包加载（`pkg/source.json`）、图标资源解析。
3. 图源能力注册与按需激活。

输出:

1. `ISourceRepository`、`ISourceLoader`、`ISourceRegistry`。

### 4.1.6 `ngf-ui-shell`

职责:

1. 导航壳层协同（与 `NavPathStack` 模式兼容）。
2. 页面级策略注入（沉浸式、状态栏、生命周期回调）。

输出:

1. `INavigationShell`、`IPagePolicyHost`。

## 4.2 依赖方向约束

1. `ngf-core` 不依赖业务模块。
2. `ngf-platform-ohos` 只能依赖 `ngf-core`。
3. `ngf-data`、`ngf-content-*` 依赖 `ngf-core`，不得反向依赖页面。
4. `ngf-ui-shell` 可依赖 `ngf-core` 和 `ngf-platform-ohos`。
5. 业务页仅依赖 NGF 对外接口，不直接依赖底层实现细节。

## 5. 迁移总体策略

采用 Strangler Fig（绞杀者）渐进迁移策略。

1. 第一步抽接口与适配器，不改行为。
2. 第二步把旧实现挂到新接口后面，保证功能等价。
3. 第三步逐模块替换调用入口，分批去耦。
4. 全程保留回滚开关与兼容层。

## 6. 分阶段实施计划（完整）

## 6.1 Phase 0: 契约冻结与基线治理（1-2 周）

目标:

1. 固化 NGF 模块边界与接口草案。
2. 建立“现状功能清单 -> NGF 能力映射表”。
3. 明确兼容层策略与回滚策略。

任务:

1. 产出 `NGF Interface Draft` 文档（接口命名、输入输出、错误码规范）。
2. 产出 `Module Ownership` 文档（每个模块负责人、升级窗口）。
3. 产出 `Migration Impact Matrix`（按文件、按模块、按风险）。

DoD:

1. 关键接口命名冻结。
2. 所有迁移任务都有风险等级与回滚方案。
3. 评审通过后进入 Phase 1。

## 6.2 Phase 1: 低耦合核心抽离（2-3 周）

目标:

1. 先抽最稳定、复用最高的核心层。
2. 保持业务逻辑零变化。

优先对象:

1. Logger。
2. EventBus。
3. ErrorHandler。
4. AppInitialization 生命周期编排。
5. Task 基础执行器。

任务:

1. 定义 `ngf-core` 接口并提供默认实现。
2. 提供 compatibility facade（旧 API 委托到新实现）。
3. 为核心能力补最小集成测试（日志格式、事件派发、失败恢复）。

DoD:

1. 旧代码可无感切换到 `ngf-core` façade。
2. 日志、事件、初始化状态一致。
3. 无新增启动阻塞问题。

## 6.3 Phase 2: 平台壳层与窗口治理抽离（2-3 周）

目标:

1. 将窗口/沉浸式/策略注册机制沉淀到 `ngf-platform-ohos` + `ngf-ui-shell`。
2. 稳定跨页面的显示策略一致性。

任务:

1. 抽象 `DisplayMode` 与过渡策略接口。
2. 抽象 `PageWindowPolicy/Registry/Coordinator`。
3. 建立页面策略声明式接入点（页面名 -> 策略规范）。

DoD:

1. 主流程页面在新壳层下显示模式行为与现状一致。
2. 导航前后窗口模式切换不回退。
3. 页面策略配置可以独立演进。

## 6.4 Phase 3: 图源与 workflow 能力抽离（2-4 周）

目标:

1. 将图源仓库与 workflow 执行从业务层剥离为可复用插件能力。
2. 保持“图源隔离、按需激活、失败降级”原则。

任务:

1. 抽象 `ISourceRepository`、`ISourceLoader`、`IWorkflowEngine`。
2. 统一 WebView/API/Novel 三类执行入口契约。
3. 建立图源 schema 版本化机制与校验器。

DoD:

1. 基于 NGF 能独立加载 `index.main.json + pkg/source.json`。
2. 至少 3 个代表性图源通过回归（含 WebView/API/Novel 场景）。
3. 特殊图源失败可降级，不拖垮全局引擎。

## 6.5 Phase 4: 数据层解耦（4-6 周）

目标:

1. 分解 `DataManager` 的聚合职责。
2. 建立稳定数据契约，减少跨层直接依赖。

任务:

1. 先建立 `IDataFacade` 聚合门面。
2. 逐步拆出 Settings、Cache、Storage、DomainRepository。
3. 将数据库迁移与 schema 管理独立化。

DoD:

1. 关键业务路径不再直接依赖大一统 `DataManager` 实现细节。
2. 数据模块具备可单测能力。
3. 数据变更具备可追踪迁移记录。

## 6.6 Phase 5: NGF Starter 与示例工程（2-3 周）

目标:

1. 让 NGF 可以直接用于新软件开发。
2. 形成标准化项目骨架与接入手册。

任务:

1. 输出 `NGF Starter` 模板（启动、日志、窗口、设置、图源接入示例）。
2. 输出开发指南（模块接入、约束、测试、发布流程）。
3. 输出迁移模板（旧项目接入 NGF 的最短路径）。

DoD:

1. 新项目 1 天内可跑通基础壳层。
2. NGF 文档齐全，示例可运行。
3. 新项目不依赖 Manxia 业务代码即可启动。

## 7. 时间与人力建议

## 7.1 周期估算

1. 最短可用版本（MVP）: 8-10 周。
2. 完整迁移到稳定形态: 14-20 周。

## 7.2 角色配置

1. 架构负责人: 1 人（接口契约、边界控制、评审）。
2. 平台与基础设施: 1-2 人（core/platform/ui-shell）。
3. 图源与 workflow: 1-2 人。
4. 数据层迁移: 1-2 人。
5. QA/回归: 1 人。

## 8. 风险矩阵与缓解

| 风险 | 等级 | 触发条件 | 缓解策略 | 回滚策略 |
|---|---|---|---|---|
| DataManager 拆分引发回归 | 高 | 聚合逻辑拆散后行为偏差 | 先 facade 后拆分、关键路径回归集 | 切回旧 facade 绑定 |
| 页面层依赖复杂导致进度拖慢 | 高 | 巨型页面同时改动过多 | 页面暂不重构，只替换底层接口 | 保留旧调用路径 |
| 图源站点变更导致验证不稳定 | 中 | 站点结构变化/反爬升级 | 引擎级重试与降级、schema 校验 | 切换到旧执行器 |
| 平台 API 升级影响窗口策略 | 中 | SDK 升级后行为变化 | platform 层隔离适配 | 版本分支与策略开关 |
| 命名与历史债务影响认知 | 中 | 新旧术语并存 | 兼容期保留别名 + 逐步替换 | 保留旧类型导出 |

## 9. 质量保障与验收标准

## 9.1 工程质量门禁

1. ArkTS 类型约束通过（不引入 `any`/`unknown`）。
2. 新增接口覆盖最小单测与集成测试。
3. 每阶段有回归清单（启动、导航、窗口、图源、数据读写）。

## 9.2 阶段验收点

1. Phase 1 验收: core 能力可独立使用。
2. Phase 2 验收: 页面窗口治理一致。
3. Phase 3 验收: 图源加载与 workflow 可独立复用。
4. Phase 4 验收: 数据层依赖显著下降。
5. Phase 5 验收: Starter 可用于新项目起步。

## 10. 首周开工清单（可立即执行）

1. 建立 NGF 模块目录与命名约定（仅骨架，不迁移实现）。
2. 冻结核心接口命名（Logger/EventBus/Error/Lifecycle/Window/Source）。
3. 输出“旧实现 -> 新接口”映射表第一版。
4. 建立迁移任务看板（按 Phase + 风险级别）。
5. 选定 1 条演示链路做 PoC:
   - 启动阶段状态发布。
   - 页面窗口策略应用。
   - 单图源加载与 workflow 执行。

## 11. 非目标与边界声明

1. 本计划不要求一次性重写现有业务页面。
2. 本计划不要求在第一阶段重构全部数据模型。
3. 本计划不要求立即替换所有历史命名。
4. 本计划不在当前阶段引入大型第三方框架。

## 12. 里程碑与交付物列表

1. M1（Phase 0 结束）:
   - `NGF Interface Draft`
   - `Migration Impact Matrix`
2. M2（Phase 1 结束）:
   - `ngf-core` 可用版本
   - 兼容 façade
3. M3（Phase 2 结束）:
   - `ngf-platform-ohos` + `ngf-ui-shell` 可用版本
4. M4（Phase 3 结束）:
   - `ngf-content-workflow` + `ngf-content-source` 可用版本
5. M5（Phase 4 结束）:
   - `ngf-data` 初版
6. M6（Phase 5 结束）:
   - `NGF Starter` + 接入文档

## 13. 附录 A：当前能力到 NGF 映射（摘要）

| 当前能力域 | 代表模块（现有） | NGF 归属 | 迁移优先级 |
|---|---|---|---|
| 日志 | `Utils/Logger.ets` | `ngf-core` | 高 |
| 事件系统 | `Framework/EventBus.ets` | `ngf-core` | 高 |
| 错误恢复 | `Framework/Core/ErrorHandler.ets` | `ngf-core` | 高 |
| 初始化编排 | `Framework/Managers/AppInitializationManager.ets` | `ngf-core` | 高 |
| 窗口治理 | `Utils/WindowManager.ets` | `ngf-platform-ohos` | 高 |
| 页面策略 | `Utils/PageWindow*` | `ngf-ui-shell` | 高 |
| 图源仓库 | `Framework/Source/SourceRepositoryManager.ets` | `ngf-content-source` | 中高 |
| workflow 引擎 | `Framework/WebView/*Engine*.ets` | `ngf-content-workflow` | 中高 |
| 数据聚合 | `Framework/Data/DataManager.ets` | `ngf-data` | 中 |
| 业务页面 | `pages/*` | 业务层（暂不抽） | 低 |

## 14. 附录 B：执行原则

1. 先稳定边界，再迁移实现。
2. 先低耦合高复用，再高耦合高风险。
3. 迁移以功能等价为第一优先级。
4. 任何阶段出现不可控风险时，立即启用回滚路径。
5. 每阶段结束都要产出可复用资产（接口、模板、指南）。

---

该计划用于指导 NGF 从“概念”进入“可持续落地”。后续进入实施时，可按 Phase 拆成任务卡并逐项推进。

## 15. 执行编排细化（可直接落地）

## 15.1 执行节奏（按周）

### Week 1（Phase 0-A）

目标:

1. 冻结接口命名与模块边界。
2. 输出影响矩阵与风险分级。
3. 搭建 NGF 目录骨架（不迁移业务实现）。

必交付:

1. `NGF_INTERFACE_DRAFT.md`
2. `NGF_MIGRATION_IMPACT_MATRIX.md`
3. `NGF_MODULE_OWNERSHIP.md`
4. `NGF_PHASE0_EXECUTION_BOARD.md`
5. `entry/src/main/ets/Framework/NGF/` 目录骨架

### Week 2（Phase 0-B）

目标:

1. 形成接口评审结论与冻结版本。
2. 完成 PoC 链路设计（启动 -> 窗口策略 -> 单图源）。
3. 准备 Phase 1 的任务拆解与验收脚本。

必交付:

1. `NGF_INTERFACE_DRAFT.md` 升级至 v0.2（冻结）
2. `NGF_POC_SCENARIO.md`（后续新增）
3. Phase 1 Task Breakdown（后续新增）

## 15.2 阶段入口/出口条件

### Phase 0 Entry Criteria

1. 已确认 NGF 目标模块及边界。
2. 已确认不做全量页面重写。
3. 已确认优先做低耦合高复用模块。

### Phase 0 Exit Criteria

1. 接口命名冻结并通过评审。
2. 影响矩阵覆盖高风险模块。
3. 有可追踪的执行看板和责任人。
4. NGF 目录骨架完成。

### Phase 1 Entry Criteria

1. Phase 0 Exit 条件全部满足。
2. Logger/EventBus/Error/Lifecycle 接口已冻结。
3. 兼容 façade 策略已定义。

### Phase 1 Exit Criteria

1. `ngf-core` 可独立运行基础能力。
2. 旧调用路径可经 façade 透传到新接口。
3. 关键回归场景通过（启动、日志、事件）。

## 15.3 任务卡模板（用于看板）

任务字段:

1. Task ID
2. 模块
3. 目标文件
4. 变更类型（接口/实现/适配/测试/文档）
5. 风险等级（高/中/低）
6. 前置依赖
7. 验收标准
8. 回滚方案
9. 负责人
10. 状态（Todo/In Progress/Review/Done/Blocked）

完成定义（DoD）:

1. 功能等价。
2. 类型安全通过。
3. 日志可观测。
4. 回滚路径可执行。

## 15.4 风险阈值与升级机制

触发升级条件（任一命中即升级）:

1. 核心链路回归 >= 2 个。
2. 启动阶段新增阻塞异常 >= 1 个。
3. 图源执行成功率下降超过 10%。
4. 页面窗口策略出现跨页错乱 >= 1 个稳定复现案例。

升级动作:

1. 当日冻结新增迁移任务。
2. 仅保留修复与回滚任务。
3. 24 小时内补充根因分析与修复计划。
4. 架构负责人签字后恢复迁移节奏。

## 15.5 变更控制策略

1. 同一阶段内，优先小步提交，不做超大改动。
2. 变更必须带“影响面说明 + 回滚说明”。
3. 高风险改动必须有兼容层开关。
4. 新增接口优先向下兼容，禁止一次性破坏旧调用。

## 16. 立即执行清单（本仓库）

已执行/待执行定义:

1. 已执行: 文档与目录骨架已落盘。
2. 待执行: 核心接口代码化、兼容层接线、PoC 运行验证。

当前轮次必须完成:

1. 细化执行文档（本文件）。
2. 落地 Phase 0 交付文档。
3. 创建 NGF 模块骨架目录。

## 17. 实施跟踪方式

1. 每周更新一次里程碑状态。
2. 每阶段更新一次风险矩阵。
3. 每次关键迁移更新接口草案版本号。
4. 所有状态更新统一记录在 `docs/development/` 下 NGF 文档集中。

## 18. 执行进展快照（2026-04-13）

已完成:

1. 执行编排章节细化（第 15~17 节）。
2. Phase 0 文档交付:
   - `NGF_INTERFACE_DRAFT.md`
   - `NGF_MIGRATION_IMPACT_MATRIX.md`
   - `NGF_MODULE_OWNERSHIP.md`
   - `NGF_PHASE0_EXECUTION_BOARD.md`
3. NGF 模块骨架目录落盘（`entry/src/main/ets/Framework/NGF/`）。
4. 第一批契约接口文件落盘（core/platform/data/content/source/uiShell）。
5. Phase 1 先行链路启动:
   - 新增 `LoggerFacade`（仅新增，不改旧调用路径）。

待完成:

1. Phase 0 评审冻结（任务 `NGF-P0-010`）。
2. Phase 1 中其余 façade（EventBus/Error/Lifecycle）接线设计与落盘。

## 19. 执行进展快照（2026-04-13 第二次更新）

新增完成:

1. `ngf-core` façade 完整化：
   - `LoggerFacade`
   - `EventBusFacade`
   - `ErrorHandlerFacade`
   - `LifecycleOrchestratorFacade`
   - `ServiceContainerFacade`
2. NGF 根导出与各子模块 `index.ets` 聚合导出完成。
3. 静态规范检查完成（NGF 目录无 `any/unknown`）。

验证状态:

1. `hvigorw` 可执行路径已定位：`F:\DevEco Studio\tools\hvigor\bin\hvigorw.bat`。
2. 构建级验证受本机 hvigor 缓存/工具链异常阻塞，待链路修复后补跑。

## 20. 阶段状态更新

1. Phase 0 已完成（接口冻结 v0.2 + 文档与骨架交付完成）。
2. 当前处于 Phase 1（core façade 完整化 + 验证阶段）。
3. 构建级验证因 hvigor 工具链阻塞待修复。

## 21. 模块与文件可检测性规范（强制）

本节为 NGF 强制规范，自本文件版本起生效。

## 21.1 目标

1. 让 `ngf-core`、`ngf-platform-ohos`、`ngf-data`、`ngf-content-workflow`、`ngf-content-source`、`ngf-ui-shell` 均可被统一识别。
2. 让后续新增模块与文件都能被自动扫描、审计、追踪。

## 21.2 模块级可检测性要求（Mandatory）

每个 NGF 模块必须同时满足：

1. 模块根目录存在 `README.md`。
2. 模块根目录存在 `index.ets`（统一导出入口）。
3. 模块目录存在 `contracts/` 子目录（若该模块有契约）。
4. 模块被注册到 `docs/development/NGF_MODULE_REGISTRY.md`。
5. 模块被 `entry/src/main/ets/Framework/NGF/index.ets` 聚合导出。

## 21.3 文件级可检测性要求（Mandatory）

自本规范生效后，所有新建 NGF 文件（`.ets` / `.md`）必须满足：

1. 可从模块 `index.ets` 或文档注册表定位到该文件。
2. 文件路径遵循模块分层目录结构，不允许散落到未注册目录。
3. 契约文件放在 `contracts/`；兼容层文件放在 `facades/`；模块说明放在模块根 `README.md`。
4. 文档文件必须落在 `docs/development/` 并写入 UTF-8 编码。

## 21.4 检测基线（当前仓库）

当前 NGF 已满足以下可检测性基线：

1. `entry/src/main/ets/Framework/NGF/index.ets` 具备根导出入口。
2. 六大模块均存在目录、README、index 或 contracts 结构。
3. `ngf-core` 已存在 façade 与 contracts，可通过导出入口识别。
4. 执行看板与接口草案可追踪模块状态。

## 21.5 后续强制声明

1. 从现在开始，所有新增模块、子模块、契约、façade、说明文档都必须满足 21.2 与 21.3。
2. 不满足可检测性要求的文件，视为不合规，不进入评审通过状态。
3. 每次新增模块时，必须同步更新 `NGF_MODULE_REGISTRY.md` 与对应执行看板。

## 21.6 验收规则

以下任一不满足则该任务不通过：

1. 模块未在注册表登记。
2. 模块未出现在 NGF 根导出入口。
3. 文件无法从模块 README 或注册表定位。
4. 文档未使用 UTF-8 编码。

## 22. 集成进展更新（EntryAbility）

1. `EntryAbility.runManagedInitialization()` 已接入 `ngfLifecycleOrchestratorFacade`。
2. 上下文初始化阶段已增加 `ngfCoreIntegrationFacade.bootstrap()`，用于注册 NGF 核心服务到 `DependencyContainer`。
3. 集成策略保持低风险：旧管理器实现不移除，现有页面监听链路保持兼容。

## 23. 集成进展更新（初始化事件桥接）

1. 新增 `NGFCoreEventBridge`，统一发布初始化状态事件到 NGF EventBus。
2. 初始化关键失败阶段已接入 NGF 错误上报（通过 `ngfErrorHandlerFacade`）。
3. 当前已覆盖节点：初始化启动、核心集成结果、关键失败、初始化完成。

## 24. 集成进展更新（SplashPage 观测接入）

1. `SplashPage` 已增加对 `ngf.app.initialization.*` 事件的订阅。
2. 接入模式为观测增强，不替换原有 `AppInitializationManager` 进度监听逻辑。
3. 当前形成 `EntryAbility -> NGF Core -> SplashPage` 的端到端初始化事件链路。

## 25. 集成进展更新（阶段全覆盖与错误监控闭环）

1. `EntryAbility` 已将所有初始化阶段 `complete/fail` 统一接入 NGF 事件上报。
2. `ErrorMonitorService` 已接入 `NGFInitializationEventName.INIT_FAILED` 事件消费。
3. 当前形成 `EntryAbility(上报) -> NGF EventBus -> ErrorMonitorService(消费与登记)` 的错误监控闭环。

## 26. 集成进展更新（Platform/UI Shell 运行时接线）

1. `ngf-platform-ohos` 已新增 façade：
   - `PlatformWindowControllerFacade`
   - `PageWindowPolicyResolverFacade`
   - `OhosContextBridgeFacade`
   - `NGFPlatformOhosIntegrationFacade`
2. `ngf-ui-shell` 已新增 façade：
   - `NavigationShellFacade`
   - `PagePolicyHostFacade`
   - `NGFUiShellIntegrationFacade`
3. `EntryAbility` 在 `CONTEXT_SETUP` 阶段已新增 platform/ui-shell bootstrap 接线，失败策略保持“告警+兼容回退”。

## 27. 集成进展更新（模块可检测性增强）

1. `NGFFrameworkStatusPage` 已升级，新增 `ngf-platform-ohos` 与 `ngf-ui-shell` 运行态检测。
2. 检测通道覆盖：
   - `AppStorage` 集成标记（`ngf_platform_integrated`、`ngf_ui_shell_integrated`）
   - `DependencyContainer` 服务注册计数
3. `NGF_MODULE_REGISTRY.md` 已同步更新 platform/ui-shell 的 façade 与运行时接线信息。

## 28. 集成进展更新（Data 运行时接线）

1. `ngf-data` 已新增 façade：
   - `DataFacade`
   - `SettingsStoreFacade`
   - `CacheStoreFacade`
   - `StorageProviderFacade`
   - `DbMigratorFacade`
   - `NGFDataIntegrationFacade`
2. `EntryAbility` 在 `CONTEXT_SETUP` 阶段已新增 data bootstrap 接线，失败策略保持“告警+兼容回退”。
3. `ngf-data/index.ets` 已完成 façade 聚合导出，保持 NGF 根导出可检测链路。

## 29. 集成进展更新（Data 模块可检测性增强）

1. `NGFFrameworkStatusPage` 已升级，新增 `ngf-data` 运行态检测。
2. 检测通道覆盖：
   - `AppStorage` 集成标记（`ngf_data_integrated`）
   - `DependencyContainer` 数据服务注册计数（`ngf.data.*`）
3. `NGF_MODULE_REGISTRY.md` 已同步更新 `ngf-data` 的 façade 与 runtimeIntegration 声明。

## 30. 集成进展更新（Data 业务替换点接入）

1. `EntryAbility.initializeAppStorage()` 的关键设置读取已新增 `ngfSettingsStoreFacade` 读取路径。
2. 当前已覆盖启动关键设置：
   - `ADVANCED_MODE_ENABLED`
   - `BACKGROUND_BLUR_*`
   - `LOG_OUTPUT_LEVEL`
3. 替换策略保持低风险：旧 `SettingsManager.initialize()/syncToAppStorage()` 链路不移除，仅增加 NGF façade 读取入口。

## 31. 集成进展更新（Content Workflow 运行时接线与检测）

1. `ngf-content-workflow` 已新增 façade：
   - `WorkflowEngineFacade`
   - `ActionExecutorFacade`
   - `RetryPolicyFacade`
   - `RateLimitPolicyFacade`
   - `NGFContentWorkflowIntegrationFacade`
2. `EntryAbility` 在 `CONTEXT_SETUP` 阶段已新增 content-workflow bootstrap 接线，失败策略保持“告警+兼容回退”。
3. `NGFFrameworkStatusPage` 已新增 `ngf-content-workflow` 运行态检测，覆盖：
   - `AppStorage` 集成标记（`ngf_content_workflow_integrated`）
   - `DependencyContainer` 服务注册计数（`ngf.workflow.*`）
4. `WorkflowExecutor` 已新增 `ngf-content-workflow` shadow 执行入口（开关：`ngf_content_workflow_shadow_mode`）：
   - 开启时并行触发 façade 执行链路用于低风险验证
   - 默认关闭，保持现有执行结果与行为不变

## 32. 集成进展更新（Content Source 运行时接线与检测）

1. `ngf-content-source` 已新增 façade：
   - `SourceRepositoryFacade`
   - `SourceLoaderFacade`
   - `SourceRegistryFacade`
   - `NGFContentSourceIntegrationFacade`
2. `EntryAbility` 在 `CONTEXT_SETUP` 阶段已新增 content-source bootstrap 接线，失败策略保持“告警+兼容回退”。
3. `NGFFrameworkStatusPage` 已新增 `ngf-content-source` 运行态检测，覆盖：
   - `AppStorage` 集成标记（`ngf_content_source_integrated`）
   - `DependencyContainer` 服务注册计数（`ngf.source.*`）
4. `SourceRepositoryManager` 已新增业务侧替换点，以下能力优先走 `ngf-content-source` façade，失败时回退旧路径：
   - 仓库索引读写（`ngfSourceRepositoryFacade`）
   - 图源配置加载与图标路径解析（`ngfSourceLoaderFacade`）
5. `SourceManager` 已接入 `ngfSourceRegistryFacade` 生命周期同步：
   - 图源导入/更新时注册 `sourceId -> pkg`
   - 图源删除时注销 registry 记录

## 33. 集成进展更新（Phase 2-alpha：UI Shell 业务侧替换点）

1. `SettingsImmersiveTitleBar` 已新增 `ngfNavigationShellFacade.pop()` 优先返回路径：
   - 仅当 `AppStorage.ngf_ui_shell_integrated=true` 时启用
   - 失败时自动回退旧返回链路（`GlobalNavStack -> pathStack -> Router.back`）
2. `SupportersPage` 已新增页面策略接线：
   - `aboutToAppear` 优先调用 `ngfPagePolicyHostFacade.applyPolicy('SupportersPage')`
   - 失败时回退 `PageWindowCoordinator.applyPagePolicy(...)`
3. `UserAgreementPage` 已新增页面策略接线：
   - `aboutToAppear` / `onWillAppear` 优先调用 `ngfPagePolicyHostFacade.applyPolicy('UserAgreementPage')`
   - `onWillShow` 优先调用 `ngfPagePolicyHostFacade.reapplyPolicy('UserAgreementPage')`
   - 失败时回退 `PageWindowCoordinator.apply/reapplyPagePolicy(...)`
4. 当前替换策略保持低风险：
   - 不移除旧窗口策略与导航实现
   - 仅在模块集成标记为 true 时启用 NGF 优先路径
   - 异常自动回退，避免影响线上可用性

## 34. 集成进展更新（Phase 2-alpha：Platform 窗口模式业务替换点）

1. `UnifiedDetailPage` 已新增窗口模式切换适配层 `applyDisplayModeWithNgfFallback(...)`：
   - `aboutToAppear` 与 `onShown` 进入 `STATUS_SAFE_BOTTOM_IMMERSIVE` 时优先调用 `ngfPlatformWindowControllerFacade.setDisplayMode(...)`
   - `aboutToDisappear` 恢复 `previousDisplayMode` 时同样走 NGF 优先路径
2. 适配规则：
   - 仅当 `AppStorage.ngf_platform_integrated=true` 时尝试 NGF 路径
   - `DisplayMode.DEFAULT/FULL_IMMERSIVE/IMMERSIVE_WITH_BARS/STATUS_SAFE_BOTTOM_IMMERSIVE` 可映射到 `NGFDisplayMode`
   - `HIDE_STATUS_BAR/HIDE_NAVIGATION_BAR` 等不可映射模式自动回退旧 `WindowManager`，避免语义丢失
3. 风险控制：
   - `previousDisplayMode` 仍由 `WindowManager.getCurrentMode()` 采集，保证恢复行为与历史一致
   - NGF 路径出现异常时自动降级到旧链路，不阻断页面生命周期
4. `SplashPage` 同步完成开屏窗口模式替换点：
   - `aboutToAppear` 的 `STATUS_SAFE_BOTTOM_IMMERSIVE` 切换优先走 `ngfPlatformWindowControllerFacade`
   - 异常与不可映射模式自动回退旧 `WindowManager` 实现
