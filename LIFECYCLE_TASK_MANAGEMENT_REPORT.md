# 页面生命周期与任务管理系统 - 问题分析与重构方案

## 执行摘要

**问题严重性**: 🔴 高危 - 导致主线程阻塞6秒以上，触发 APP_INPUT_BLOCK 闪退

**根本原因**: 页面切换时未正确清理异步任务、定时器和长时间运行的操作，导致多个页面的任务在后台累积执行

**影响范围**: 全局性问题，影响所有包含异步操作的页面

---

## 一、问题分析

### 1.1 日志分析

**闪退时间线**:
```
18:15:20.536 → NovelBookshelfPage
18:15:21.542 → NovelSettingsPage  
18:15:25.402 → JsvmPlaygroundPage  ⚠️ 关键页面
18:16:14.767 → NovelSettingsPage
18:16:26.016 → NovelBookshelfPage
18:16:27.233 → MainMenuPage
18:16:30.736 → 主线程开始阻塞 (vSyncTask)
18:16:36.xxx → 触发 APP_INPUT_BLOCK 闪退
```

**关键发现**:
1. 用户在 **67秒内** 频繁切换了 **6个页面**
2. **JsvmPlaygroundPage** 在 18:15:25 访问后，用户在该页面停留了约 **49秒**
3. 离开 JsvmPlaygroundPage 后约 **65秒** 发生闪退
4. 主线程阻塞发生在 **MainMenuPage**，但根源可能是之前页面的未清理任务

### 1.2 代码审查发现

#### 问题 1: JsvmPlaygroundPage 生命周期管理缺失

**当前代码** (`JsvmPlaygroundPage.ets:293-295`):
```typescript
aboutToDisappear(): void {
  ThemeAwareHelper.cleanupThemeAware(this.componentId);
  // ❌ 仅清理了主题，没有清理 JS 引擎和 WebView
}
```

**存在的问题**:
- ✗ QuickJS 引擎初始化后未销毁 (`quickjs.init()` 无对应的 `destroy()`)
- ✗ Rhino 沙箱引擎未清理 (`this.rhinoEngine` 未调用 `destroy()`)
- ✗ WebView 控制器未销毁 (`this.webViewController`)
- ✗ 执行历史记录未清空 (`this.executionHistory`)
- ✗ 可能存在的定时器未清理

#### 问题 2: 全局 setTimeout/setInterval 泛滥

**统计结果**:
- 总计 **352** 处使用 `setTimeout/setInterval`
- 高频使用文件:
  - `MangaViewer.ets`: 52 处
  - `MangaReaderPage.ets`: 30 处
  - `TextReaderComponent.ets`: 19 处
  - `MangaDetailPage.ets`: 19 处

**典型问题代码**:
```typescript
// ❌ 定时器未保存引用，无法清理
setTimeout(() => {
  this.processPreloadQueue();
}, 10);

// ❌ 循环定时器未在 aboutToDisappear 中清理
this.scrollTimer = setTimeout(() => {
  this.isScrolling = false;
  this.updateVisiblePages();
  this.triggerWebtoonPreload();
}, 150);
```

#### 问题 3: 异步操作缺乏生命周期绑定

**示例 - NovelSourceValidator**:
```typescript
// ❌ 书源校验可能耗时很长，但没有取消机制
async validateSource(source: NovelSource): Promise<ValidationResult> {
  // 可能执行数十秒的网络请求和 HTML 解析
  // 用户离开页面后仍在后台执行
}
```

#### 问题 4: 现有 BackgroundTaskManager 功能不足

**当前实现的局限**:
- ✓ 支持长时间后台任务（PDF 导入、下载等）
- ✗ **不支持页面级任务管理**
- ✗ **不支持页面销毁时自动取消任务**
- ✗ **不支持定时器管理**
- ✗ **不支持 Promise 取消**

---

## 二、系统性问题根源

### 2.1 架构层面

1. **缺乏统一的页面生命周期管理框架**
   - 每个页面独立管理资源
   - 没有标准化的清理流程
   - 容易遗漏清理步骤

2. **异步操作与页面生命周期脱钩**
   - Promise/async 操作无法取消
   - 定时器散落在各处
   - 没有统一的任务注册机制

3. **资源清理依赖开发者记忆**
   - 需要手动记住每个资源
   - 容易在重构时遗漏
   - 没有编译时检查

### 2.2 具体技术问题

| 问题类型 | 影响 | 示例 |
|---------|------|------|
| 未清理的定时器 | 内存泄漏 + CPU 占用 | `setTimeout` 未 `clearTimeout` |
| 未取消的网络请求 | 网络资源浪费 | 书源校验、图片加载 |
| 未销毁的 JS 引擎 | 内存泄漏 | QuickJS、Rhino 引擎 |
| 未释放的 WebView | 内存泄漏 + 性能问题 | WebView 控制器 |
| 累积的事件监听器 | 内存泄漏 | 设备方向、主题变化监听 |

---

## 三、解决方案设计

### 3.1 核心设计原则

1. **自动化优先**: 资源清理应自动进行，减少人为错误
2. **类型安全**: 利用 TypeScript 类型系统确保正确性
3. **向后兼容**: 渐进式迁移，不破坏现有功能
4. **性能优先**: 最小化运行时开销
5. **可观测性**: 提供调试和监控能力

### 3.2 架构设计

```
┌─────────────────────────────────────────────────────────────┐
│                    Page Component                            │
│  ┌──────────────────────────────────────────────────────┐  │
│  │         PageLifecycleManager (每个页面一个实例)       │  │
│  │  ┌────────────┐  ┌────────────┐  ┌────────────┐     │  │
│  │  │ Timer      │  │ Promise    │  │ Resource   │     │  │
│  │  │ Manager    │  │ Manager    │  │ Manager    │     │  │
│  │  └────────────┘  └────────────┘  └────────────┘     │  │
│  │         ↓              ↓              ↓              │  │
│  │  ┌──────────────────────────────────────────────┐   │  │
│  │  │        Unified Cleanup on Destroy            │   │  │
│  │  └──────────────────────────────────────────────┘   │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│              GlobalTaskCoordinator (单例)                    │
│  - 跨页面任务协调                                            │
│  - 全局资源监控                                              │
│  - 内存压力管理                                              │
└─────────────────────────────────────────────────────────────┘
```

### 3.3 核心组件设计

#### 组件 1: PageLifecycleManager

**职责**: 管理单个页面的所有异步任务和资源

**核心 API**:
```typescript
class PageLifecycleManager {
  // 定时器管理
  setTimeout(callback: Function, delay: number): number
  setInterval(callback: Function, delay: number): number
  clearTimeout(id: number): void
  clearInterval(id: number): void
  
  // Promise 管理（支持取消）
  registerPromise<T>(promise: Promise<T>): CancellablePromise<T>
  
  // 资源管理
  registerResource(resource: Disposable): void
  
  // 事件监听器管理
  addEventListener(target: any, event: string, handler: Function): void
  
  // 生命周期钩子
  onDestroy(callback: () => void): void
  
  // 清理所有资源
  destroy(): void
}
```

#### 组件 2: CancellablePromise

**职责**: 可取消的 Promise 包装器

```typescript
class CancellablePromise<T> {
  constructor(
    executor: (
      resolve: (value: T) => void,
      reject: (reason?: any) => void,
      signal: AbortSignal
    ) => void
  )
  
  cancel(reason?: string): void
  isCancelled(): boolean
  then<U>(onFulfilled: (value: T) => U): CancellablePromise<U>
  catch(onRejected: (reason: any) => any): CancellablePromise<T>
}
```

#### 组件 3: ResourceManager

**职责**: 管理需要显式释放的资源

```typescript
interface Disposable {
  dispose(): void | Promise<void>
}

class ResourceManager {
  register(resource: Disposable): void
  unregister(resource: Disposable): void
  disposeAll(): Promise<void>
}
```

#### 组件 4: GlobalTaskCoordinator

**职责**: 全局任务协调和监控

```typescript
class GlobalTaskCoordinator {
  // 页面级管理器注册
  registerPage(pageId: string, manager: PageLifecycleManager): void
  unregisterPage(pageId: string): void
  
  // 全局监控
  getActiveTaskCount(): number
  getMemoryUsage(): MemoryStats
  
  // 紧急清理（内存压力时）
  emergencyCleanup(): Promise<void>
  
  // 调试支持
  dumpActiveTasks(): TaskDumpInfo[]
}
```

---

## 四、实施计划

### Phase 1: 核心框架实现 (优先级: P0)

**时间估算**: 2-3 天

**任务清单**:
- [ ] 实现 `PageLifecycleManager` 核心类
- [ ] 实现 `CancellablePromise` 包装器
- [ ] 实现 `ResourceManager` 资源管理
- [ ] 实现 `GlobalTaskCoordinator` 单例
- [ ] 编写单元测试

**交付物**:
- `Framework/Lifecycle/PageLifecycleManager.ets`
- `Framework/Lifecycle/CancellablePromise.ets`
- `Framework/Lifecycle/ResourceManager.ets`
- `Framework/Lifecycle/GlobalTaskCoordinator.ets`
- 测试用例

### Phase 2: 关键页面迁移 (优先级: P0)

**时间估算**: 3-4 天

**迁移优先级**:
1. **JsvmPlaygroundPage** (最高优先级 - 已知问题源)
2. **MangaReaderPage** (高频使用)
3. **NovelReaderPage** (高频使用)
4. **MangaDetailPage** (定时器密集)
5. **NovelSourceDebugPage** (长时间任务)

**每个页面的迁移步骤**:
```typescript
// 1. 添加生命周期管理器
private lifecycleManager: PageLifecycleManager = new PageLifecycleManager('PageName')

// 2. 替换所有 setTimeout
// 旧代码: setTimeout(() => {...}, 100)
// 新代码: this.lifecycleManager.setTimeout(() => {...}, 100)

// 3. 包装异步操作
// 旧代码: await someAsyncOperation()
// 新代码: await this.lifecycleManager.registerPromise(someAsyncOperation())

// 4. 注册资源
this.lifecycleManager.registerResource({
  dispose: () => this.cleanup()
})

// 5. 在 aboutToDisappear 中清理
aboutToDisappear(): void {
  this.lifecycleManager.destroy()
  ThemeAwareHelper.cleanupThemeAware(this.componentId)
}
```

### Phase 3: 批量迁移工具 (优先级: P1)

**时间估算**: 1-2 天

**工具功能**:
- 自动检测未清理的 `setTimeout/setInterval`
- 生成迁移建议
- 验证迁移完整性

**交付物**:
- `tools/lifecycle-migration-checker.ts`
- 迁移指南文档

### Phase 4: 全量迁移 (优先级: P1)

**时间估算**: 5-7 天

**迁移范围**:
- 所有 `pages/` 目录下的页面 (约 50+ 个)
- 所有 `components/` 中的复杂组件
- 所有使用定时器的工具类

### Phase 5: 监控与优化 (优先级: P2)

**时间估算**: 2-3 天

**功能**:
- 开发者模式下的任务监控面板
- 内存泄漏检测
- 性能指标收集
- 自动化测试

---

## 五、立即行动项 (紧急修复)

### 5.1 JsvmPlaygroundPage 紧急修复

**问题**: 多个 JS 引擎未清理

**修复代码**:
```typescript
aboutToDisappear(): void {
  logger.lifecycle(TAG, 'aboutToDisappear - 开始清理资源')
  
  // 1. 清理 QuickJS 引擎
  if (this.quickjsInitialized) {
    try {
      quickjs.destroy?.()
      this.quickjsInitialized = false
      logger.info(TAG, 'QuickJS 引擎已销毁')
    } catch (e) {
      logger.error(TAG, `QuickJS 销毁失败: ${e}`)
    }
  }
  
  // 2. 清理 Rhino 沙箱引擎
  if (this.rhinoEngine) {
    try {
      this.rhinoEngine.destroy?.()
      this.rhinoEngine = null
      logger.info(TAG, 'Rhino 引擎已销毁')
    } catch (e) {
      logger.error(TAG, `Rhino 销毁失败: ${e}`)
    }
  }
  
  // 3. 清理 WebView
  try {
    this.webViewController.clearHistory()
    this.webViewController.clearCache()
    logger.info(TAG, 'WebView 已清理')
  } catch (e) {
    logger.error(TAG, `WebView 清理失败: ${e}`)
  }
  
  // 4. 清理历史记录
  this.executionHistory = []
  this.expandedHistoryIds.clear()
  
  // 5. 清理主题
  ThemeAwareHelper.cleanupThemeAware(this.componentId)
  
  logger.lifecycle(TAG, 'aboutToDisappear - 资源清理完成')
}
```

### 5.2 MangaViewer 定时器清理

**问题**: `preloadQueueTimer` 和 `scrollTimer` 未清理

**修复代码**:
```typescript
// 添加清理方法
private cleanupTimers(): void {
  if (this.preloadQueueTimer !== -1) {
    clearTimeout(this.preloadQueueTimer)
    this.preloadQueueTimer = -1
  }
  if (this.scrollTimer !== -1) {
    clearTimeout(this.scrollTimer)
    this.scrollTimer = -1
  }
}

// 在组件销毁时调用
aboutToDisappear(): void {
  this.cleanupTimers()
  // ... 其他清理
}
```

---

## 六、验证与测试

### 6.1 测试场景

1. **快速页面切换测试**
   - 在 10 秒内切换 10 个不同页面
   - 验证无内存泄漏
   - 验证无主线程阻塞

2. **长时间任务中断测试**
   - 启动书源校验
   - 立即离开页面
   - 验证任务被正确取消

3. **内存压力测试**
   - 连续打开/关闭漫画阅读器 50 次
   - 监控内存使用
   - 验证内存稳定

4. **并发任务测试**
   - 同时打开多个包含异步任务的页面
   - 验证任务隔离
   - 验证清理正确性

### 6.2 监控指标

| 指标 | 目标值 | 当前值 | 优先级 |
|------|--------|--------|--------|
| 页面切换后残留定时器数 | 0 | 未知 | P0 |
| 页面销毁后内存释放率 | >95% | 未知 | P0 |
| 主线程阻塞时间 | <16ms | 6000ms+ | P0 |
| 异步任务取消成功率 | >99% | 0% | P0 |

---

## 七、风险与缓解

### 7.1 技术风险

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|----------|
| 现有代码破坏 | 高 | 中 | 渐进式迁移 + 充分测试 |
| 性能回归 | 中 | 低 | 性能基准测试 |
| API 不兼容 | 中 | 低 | 保留旧 API 作为过渡 |
| 学习曲线 | 低 | 高 | 详细文档 + 示例代码 |

### 7.2 项目风险

| 风险 | 影响 | 概率 | 缓解措施 |
|------|------|------|----------|
| 开发时间超期 | 中 | 中 | 分阶段交付 |
| 测试覆盖不足 | 高 | 中 | 自动化测试 + 人工测试 |
| 团队接受度 | 中 | 低 | 早期沟通 + 培训 |

---

## 八、成功标准

### 8.1 功能标准

- ✅ 所有页面实现统一的生命周期管理
- ✅ 零残留定时器
- ✅ 零内存泄漏
- ✅ 异步任务可取消

### 8.2 性能标准

- ✅ 页面切换流畅度 >60 FPS
- ✅ 内存使用稳定（无持续增长）
- ✅ 无主线程阻塞 >100ms

### 8.3 质量标准

- ✅ 单元测试覆盖率 >80%
- ✅ 集成测试通过率 100%
- ✅ 无 P0/P1 级别 Bug

---

## 九、后续优化方向

1. **智能资源管理**
   - 基于内存压力自动清理
   - 预测性资源加载

2. **开发者工具增强**
   - 实时任务监控面板
   - 内存泄漏自动检测
   - 性能热点分析

3. **框架级支持**
   - 提供装饰器简化使用
   - 编译时检查
   - IDE 插件支持

---

## 十、参考资料

### 相关文档
- HarmonyOS 生命周期文档
- ArkTS 内存管理最佳实践
- 现有 BackgroundTaskManager 实现

### 相似案例
- React useEffect cleanup
- Vue beforeUnmount hook
- Android ViewModel onCleared

---

**文档版本**: 1.0  
**创建日期**: 2025-12-30  
**最后更新**: 2025-12-30  
**负责人**: 开发团队  
**审核状态**: 待审核
