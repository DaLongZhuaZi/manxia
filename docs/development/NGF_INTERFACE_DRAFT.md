# NGF Interface Draft（Phase 0）

## 1. 文档信息

- 版本: v0.2-frozen
- 日期: 2026-04-13
- 状态: 已冻结（Phase 0 评审通过）
- 作用: 固化 NGF 第一批接口命名与职责，作为 Phase 1 实施基线

## 2. 设计原则

1. 接口优先于实现。
2. 先保证功能等价，再做结构优化。
3. 保持对现有 Manxia 调用路径兼容。
4. 接口保持最小闭包，避免过早扩展。

## 3. 接口命名冻结（第一批）

## 3.1 `ngf-core`

1. `ILogger`
2. `IEventBus`
3. `IErrorHandler`
4. `ILifecycleOrchestrator`
5. `IServiceContainer`

### `ILogger`（核心能力）

冻结签名:

1. `setLevel(level: NGFLogLevel): void`
2. `getLevel(): NGFLogLevel`
3. `debug(tag: string, message: string): void`
4. `info(tag: string, message: string): void`
5. `warn(tag: string, message: string): void`
6. `error(tag: string, message: string): void`
7. `lifecycle(tag: string, message: string): void`
8. `stateChange(tag: string, fromState: string, toState: string, reason: string): void`

兼容映射:

1. 现有 `Utils/Logger.ets` -> `ILogger`

### `IEventBus`

冻结签名:

1. `publish(eventName: string, payload: NGFEventPayload): void`
2. `subscribe(eventName: string, listenerId: string, listener: NGFEventListener): boolean`
3. `unsubscribe(eventName: string, listenerId: string): boolean`
4. `clear(eventName: string): void`

兼容映射:

1. 现有 `Framework/EventBus.ets` -> `IEventBus`

### `IErrorHandler`

冻结签名:

1. `handle(errorName: string, message: string, severity: NGFErrorSeverity, context: NGFErrorContext): Promise<boolean>`
2. `registerRecoverStrategy(strategyName: string): boolean`
3. `getRecentErrorCount(): number`

兼容映射:

1. 现有 `Framework/Core/ErrorHandler.ets` -> `IErrorHandler`

### `ILifecycleOrchestrator`

冻结签名:

1. `startInitialization(): void`
2. `beginPhase(phaseName: string): void`
3. `completePhase(phaseName: string): void`
4. `failPhase(phaseName: string, reason: string): void`
5. `markCompleted(): void`
6. `getCurrentState(): NGFPhaseState`
7. `isCompleted(): boolean`

兼容映射:

1. 现有 `Framework/Managers/AppInitializationManager.ets` -> `ILifecycleOrchestrator`

### `IServiceContainer`

冻结签名:

1. `registerSingleton(token: string, implementationName: string): void`
2. `resolve(token: string): string`
3. `contains(token: string): boolean`

兼容映射:

1. 现有 `Framework/DependencyContainer.ets` -> `IServiceContainer`

## 3.2 `ngf-platform-ohos`

1. `IPlatformWindowController`
2. `IPageWindowPolicyResolver`
3. `IOhosContextBridge`

## 3.3 `ngf-data`

1. `IDataFacade`
2. `ISettingsStore`
3. `ICacheStore`
4. `IStorageProvider`
5. `IDbMigrator`

## 3.4 `ngf-content-workflow`

1. `IWorkflowEngine`
2. `IActionExecutor`
3. `IRetryPolicy`
4. `IRateLimitPolicy`

## 3.5 `ngf-content-source`

1. `ISourceRepository`
2. `ISourceLoader`
3. `ISourceRegistry`

## 3.6 `ngf-ui-shell`

1. `INavigationShell`
2. `IPagePolicyHost`

## 4. 评审决议（Phase 0）

1. 第一批接口命名冻结，不再在 Phase 1 变更方法名。
2. 兼容层优先，旧路径保留，不进行破坏性替换。
3. `ngf-core` 先完成 façade 闭环，再做渐进接线。

## 5. 后续约束

1. 若要调整冻结接口，必须新增版本号并记录破坏性影响。
2. 任何接口扩展需补充兼容映射与回滚策略。
3. 接口实现继续遵循 ArkTS 类型安全约束。

## 6. 可检测性声明（强制）

1. 本接口草案中的每个模块接口必须可以通过以下路径被检测：
   - 模块 `index.ets` 导出
   - NGF 根导出 `entry/src/main/ets/Framework/NGF/index.ets`
   - 模块注册表 `docs/development/NGF_MODULE_REGISTRY.md`
2. 所有后续新增接口文件必须落在对应模块 `contracts/` 下，并同步更新模块导出。
3. 所有后续新增 façade 文件必须落在对应模块 `facades/` 下，并同步更新模块导出。
4. 从本版本起，未被导出与未被注册的模块/文件视为不合规。
