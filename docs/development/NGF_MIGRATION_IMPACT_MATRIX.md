# NGF Migration Impact Matrix（Phase 0）

## 1. 文档信息

- 版本: v0.1
- 日期: 2026-04-13
- 状态: 执行中

## 2. 分级说明

1. 高: 影响启动、主流程、核心数据路径。
2. 中: 影响某一能力域，但有替代路径。
3. 低: 影响局部功能或仅文档/配置。

## 3. 模块影响矩阵

| 模块域 | 代表文件 | 当前耦合 | 风险 | 首批动作 | 回滚策略 |
|---|---|---|---|---|---|
| 日志 | `entry/src/main/ets/Utils/Logger.ets` | 全局高 | 中 | 提供 `ILogger` façade | 切回原 logger 入口 |
| 事件系统 | `entry/src/main/ets/Framework/EventBus.ets` | 中高 | 中 | 抽象 `IEventBus`，保留旧常量 | 保留旧事件发布路径 |
| 错误处理 | `entry/src/main/ets/Framework/Core/ErrorHandler.ets` | 中 | 中 | 抽象 `IErrorHandler` | 切回旧 ErrorHandler |
| 生命周期 | `entry/src/main/ets/Framework/Managers/AppInitializationManager.ets` | 中 | 中高 | 抽象 `ILifecycleOrchestrator` | 保留旧 init manager |
| 窗口治理 | `entry/src/main/ets/Utils/WindowManager.ets` | 高 | 高 | 抽象 `IPlatformWindowController` | 回滚到旧 WindowManager |
| 页面窗口策略 | `entry/src/main/ets/Utils/PageWindowCoordinator.ets` | 中高 | 中高 | 抽象 resolver/host | 保留旧策略注册 |
| 数据聚合 | `entry/src/main/ets/Framework/Data/DataManager.ets` | 极高 | 高 | 先建 `IDataFacade`，暂不拆实现 | façade 指回原 DataManager |
| 图源仓库 | `entry/src/main/ets/Framework/Source/SourceRepositoryManager.ets` | 中 | 中 | 抽象 `ISourceRepository` | 切回旧 repository manager |
| Workflow 引擎 | `entry/src/main/ets/Framework/WebView/MangaSourceEngine.ets` | 中高 | 中高 | 抽象 `IWorkflowEngine` | 切回旧 engine 入口 |
| 页面层 | `entry/src/main/ets/pages/MainMenuPage.ets` | 极高 | 高 | 第一阶段不迁移页面实现 | 不变更页面代码 |

## 4. 文件级优先级（Phase 1 候选）

### P1（优先）

1. `entry/src/main/ets/Utils/Logger.ets`
2. `entry/src/main/ets/Framework/EventBus.ets`
3. `entry/src/main/ets/Framework/Core/ErrorHandler.ets`
4. `entry/src/main/ets/Framework/Managers/AppInitializationManager.ets`

### P2（次优）

1. `entry/src/main/ets/Utils/WindowManager.ets`
2. `entry/src/main/ets/Utils/PageWindowCoordinator.ets`
3. `entry/src/main/ets/Utils/PageWindowRegistry.ets`

### P3（后续）

1. `entry/src/main/ets/Framework/Source/SourceRepositoryManager.ets`
2. `entry/src/main/ets/Framework/WebView/MangaSourceEngine.ets`
3. `entry/src/main/ets/Framework/Data/DataManager.ets`

## 5. 关键风险点与观察指标

1. 启动耗时变化: 目标不高于基线 +10%。
2. 首屏初始化失败率: 目标不高于当前基线。
3. 图源执行成功率: 目标不低于当前基线 -5%。
4. 页面窗口模式错配次数: 目标 0 个阻塞级问题。

## 6. 结论

1. NGF 可执行，推荐“core -> platform -> source/workflow -> data”顺序。
2. 页面层维持现状，避免在 Phase 1 引入巨量回归风险。
3. 数据层必须采用 façade 过渡，禁止直接硬拆。
