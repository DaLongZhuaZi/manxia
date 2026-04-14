# NGF Phase 1 Execution Board（Bootstrap）

## 1. 说明

- 版本: v1.0
- 周期: 2026-04-13 ~ 2026-05-03
- 状态字段: Todo / In Progress / Review / Done / Blocked

## 2. 当前看板

| Task ID | 模块 | 任务 | 风险 | 前置依赖 | 状态 | 验收标准 |
|---|---|---|---|---|---|---|
| NGF-P1-001 | core | 建立 LoggerFacade 并对接旧 Logger | 低 | Phase 0 接口冻结草案 | Done | 新 façade 可透传 debug/info/warn/error |
| NGF-P1-002 | core | 建立 EventBusFacade | 中 | NGF-P1-001 | Done | 不改旧事件调用即可接入新接口 |
| NGF-P1-003 | core | 建立 ErrorHandlerFacade | 中 | NGF-P1-001 | Done | 兼容旧错误处理链路 |
| NGF-P1-004 | core | 建立 LifecycleFacade | 中 | NGF-P1-001 | Done | 兼容旧初始化阶段模型 |
| NGF-P1-005 | core | 增加 NGF 模块聚合导出 | 低 | NGF-P1-001~004 | Done | `Framework/NGF/index.ets` 可统一导入 |
| NGF-P1-006 | core | 建立 ServiceContainerFacade | 低 | NGF-P1-001 | Done | `IServiceContainer` 契约具备默认实现 |
| NGF-P1-007 | verify | 执行阶段验证（静态检查） | 中 | NGF-P1-001~006 | Done | 无 `any/unknown`，无破坏性改动 |
| NGF-P1-008 | verify | 执行 hvigor 构建验证 | 中 | NGF-P1-007 | Blocked | 本机 hvigor 缓存/工具链问题修复后执行 |
| NGF-P1-009 | governance | 落地模块可检测性规范与注册表 | 低 | NGF-P1-005 | Done | 主计划+接口草案+注册表均已声明强制要求 |
| NGF-P1-010 | integration | 将 EntryAbility 初始化链路接入 NGF 生命周期与 Core 集成入口 | 中 | NGF-P1-001~006 | Done | 初始化流程通过 NGF façade 执行且旧路径保持兼容 |
| NGF-P1-011 | integration | 增加初始化事件/错误桥接并接入 EntryAbility 关键节点 | 中 | NGF-P1-010 | Done | 启动/关键失败/完成状态可通过 NGF EventBus 与 ErrorHandler 检测 |
| NGF-P1-012 | integration | SplashPage 接入 NGF 初始化事件订阅（观测模式） | 低 | NGF-P1-011 | Done | 启动页可接收 `ngf.app.initialization.*` 事件且不替换旧进度逻辑 |
| NGF-P1-013 | integration | EntryAbility 全阶段 complete/fail 事件上报覆盖 | 低 | NGF-P1-011 | Done | 所有初始化阶段的完成/失败都可通过 NGF 事件检测 |
| NGF-P1-014 | integration | ErrorMonitorService 接入 NGF 初始化失败事件消费 | 低 | NGF-P1-011 | Done | 错误监控服务可消费 `INIT_FAILED` 并登记系统错误记录 |
| NGF-P1-015 | integration | `ngf-platform-ohos` façade 与运行时注册接线（Window/Policy/Context） | 中 | NGF-P1-010 | Done | Platform façade 可通过 NGF 根导出与 DependencyContainer 检测 |
| NGF-P1-016 | integration | `ngf-ui-shell` façade 与运行时注册接线（Navigation/PagePolicy） | 中 | NGF-P1-015 | Done | UI Shell façade 可通过 NGF 根导出与 DependencyContainer 检测 |
| NGF-P1-017 | integration | `ngf-data` façade 第一批落地（Data/Settings/Cache/Storage/DbMigrator） | 中 | NGF-P1-010 | Done | Data façade 可通过 NGF 根导出与模块 README/注册表检测 |
| NGF-P1-018 | integration | `ngf-data` 运行时注册接线与状态页检测升级 | 中 | NGF-P1-017 | Done | Data 服务可通过 AppStorage + DependencyContainer + StatusPage 运行态检测 |
| NGF-P1-019 | integration | `ngf-data` 启动设置读取替换点接入（EntryAbility -> SettingsStoreFacade） | 低 | NGF-P1-018 | Done | 启动关键设置读取通过 NGF data façade 执行且旧设置初始化链路保持兼容 |
| NGF-P1-020 | integration | `ngf-content-workflow` façade 与运行时注册接线（engine/action/retry/rateLimit） | 中 | NGF-P1-010 | Done | Workflow façade 可通过 NGF 根导出与 DependencyContainer 检测 |
| NGF-P1-021 | integration | 状态页增加 `ngf-content-workflow` 运行态检测 | 低 | NGF-P1-020 | Done | StatusPage 可展示 content-workflow AppStorage 标记与服务注册计数 |
| NGF-P1-022 | integration | `ngf-content-source` façade 与运行时注册接线（repository/loader/registry） | 中 | NGF-P1-010 | Done | Content Source façade 可通过 NGF 根导出与 DependencyContainer 检测 |
| NGF-P1-023 | integration | 状态页增加 `ngf-content-source` 运行态检测 | 低 | NGF-P1-022 | Done | StatusPage 可展示 content-source AppStorage 标记与服务注册计数 |
| NGF-P1-024 | integration | `SourceRepositoryManager` 优先接入 `ngf-content-source` façade 读写路径 | 中 | NGF-P1-022 | Done | 图源索引读写/图源配置加载/图标解析优先走 façade，失败自动回退旧路径 |
| NGF-P1-025 | integration | `SourceManager` 接入 `ngf-content-source` registry 生命周期同步 | 低 | NGF-P1-024 | Done | 图源导入/更新时注册，删除时注销，失败不阻断原有业务流程 |
| NGF-P1-026 | integration | `WorkflowExecutor` 增加 `ngf-content-workflow` shadow 执行入口（开关控制） | 低 | NGF-P1-020 | Done | 打开 `ngf_content_workflow_shadow_mode` 后可并行触发 façade 执行验证，默认关闭不影响旧流程 |
| NGF-P1-027 | integration | 设置/协议页面接入 `ngf-ui-shell` 业务侧替换点（导航返回 + 页面策略 apply/reapply） | 低 | NGF-P1-016 | Done | `SettingsImmersiveTitleBar`、`SupportersPage`、`UserAgreementPage` 在 `ngf_ui_shell_integrated=true` 时优先走 façade，失败自动回退旧路径 |
| NGF-P1-028 | integration | `UnifiedDetailPage` 接入 `ngf-platform-ohos` 窗口模式替换点（setDisplayMode） | 低 | NGF-P1-015 | Done | 页面窗口模式切换优先走 `PlatformWindowControllerFacade`，不支持模式与异常自动回退 `WindowManager` |
| NGF-P1-029 | integration | `SplashPage` 接入 `ngf-platform-ohos` 开屏窗口模式替换点（setDisplayMode） | 低 | NGF-P1-015 | Done | 开屏沉浸式窗口模式优先走 `PlatformWindowControllerFacade`，异常自动回退 `WindowManager` |

## 3. 当前结论

1. Phase 1 核心 façade 已全部落盘，保持旧调用路径不变。
2. 已完成静态约束检查（未检出 `any/unknown`）。
3. 已定位到构建阻塞：hvigor 在本机执行 `tasks` 时触发缓存/安装异常，尚未完成构建级验证。
4. 可检测性规范已生效，后续新增模块和文件必须先注册、再导出、可追踪。
5. `EntryAbility` 已完成 NGF 生命周期 façade 与 Core 集成启动接线。
6. 初始化流程已接入 NGF 事件桥接，关键失败会同步走 NGF 错误上报。
7. `SplashPage` 已接入 NGF 初始化事件订阅，形成入口到页面的端到端链路。
8. `EntryAbility` 已实现全阶段初始化事件上报，阶段可观测性进一步完整。
9. `ErrorMonitorService` 已接入 NGF 初始化失败事件消费，形成错误监控闭环。
10. `EntryAbility` 已新增 Platform/UI Shell 集成入口，形成 `core -> platform -> ui-shell` 的连续接线。
11. `NGFFrameworkStatusPage` 已升级为运行时检测模式，可展示 platform/ui-shell 实际接入状态。
12. `ngf-data` 已完成第一批 façade 落地，保持旧数据链路不替换、低风险兼容。
13. `EntryAbility` 与 `NGFFrameworkStatusPage` 已补齐 `ngf-data` 运行时检测，形成 `core -> platform -> ui-shell -> data` 连续接线。
14. `EntryAbility.initializeAppStorage()` 已增加 `ngfSettingsStoreFacade` 读取路径，形成 `ngf-data` 的业务侧替换切入点。
15. `ngf-content-workflow` 已完成第一批 façade 与运行时注册，状态页可实时检测 workflow 模块健康度。
16. `ngf-content-source` 已完成第一批 façade 与运行时注册，状态页可实时检测 content-source 模块健康度。
17. `SourceRepositoryManager` 已接入 `ngf-content-source` 优先读写路径，形成可回退的业务侧替换点。
18. `SourceManager` 已接入 `ngfSourceRegistryFacade` 生命周期同步，图源导入/更新/删除可追踪到 NGF registry。
19. `WorkflowExecutor` 已新增 `ngf-content-workflow` shadow 入口，可通过开关做低风险并行验证。
20. `ngf-ui-shell` 已增加业务侧替换点：设置页通用标题栏优先走 `NavigationShellFacade` 返回，协议/支持者页面优先走 `PagePolicyHostFacade` 页面策略接线（均保留旧路径回退）。
21. `UnifiedDetailPage` 已新增 `ngf-platform-ohos` 业务侧替换点：`aboutToAppear/aboutToDisappear/onShown` 的窗口模式切换优先走 `PlatformWindowControllerFacade`，并保留旧模式自动回退。
22. `SplashPage` 已新增 `ngf-platform-ohos` 业务侧替换点：开屏页沉浸式窗口模式切换优先走 `PlatformWindowControllerFacade`，并保留异常自动回退。

## 4. 构建阻塞详情

1. 可执行已找到：`F:\DevEco Studio\tools\hvigor\bin\hvigorw.bat`。
2. `hvigorw.bat --version` 可执行。
3. `hvigorw.bat tasks` 报错：
   - `00308003 Operation Error`（缓存 workspace 缺失 hvigor.js）
   - 尝试切换 `HVIGOR_USER_HOME` 后报 `00308002`（pnpm install 失败）

## 5. 下一步

1. 修复 hvigor 构建链路后执行一次最小构建验证。
2. 继续 Phase 2-alpha：优先推进窗口策略与导航壳层的业务侧渐进替换点。
3. 推进 `ngf-data` façade 到更多业务调用替换点（设置/存储之外优先数据查询链路）。
4. 继续推进 `ngf-content-source` 与 `ngf-content-workflow` 的业务侧替换点（图源加载/执行入口）。
5. 后续每次新增模块/文件同步更新 `NGF_MODULE_REGISTRY.md`。
