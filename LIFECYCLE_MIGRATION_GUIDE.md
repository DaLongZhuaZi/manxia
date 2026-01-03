# 页面生命周期管理框架 - 迁移指南

## 快速开始

### 1. 基础迁移步骤

**第一步：导入框架**
```typescript
import { PageLifecycleManager, Disposable } from '../Framework/Lifecycle';
```

**第二步：创建生命周期管理器**
```typescript
@Component
export struct MyPage {
  // 添加生命周期管理器实例
  private lifecycle = new PageLifecycleManager('MyPage', {
    enableDebug: __DEBUG__  // 开发模式下启用调试
  })
  
  // ... 其他代码
}
```

**第三步：替换定时器调用**
```typescript
// ❌ 旧代码
setTimeout(() => {
  this.doSomething()
}, 1000)

// ✅ 新代码
this.lifecycle.setTimeout(() => {
  this.doSomething()
}, 1000)
```

**第四步：在 aboutToDisappear 中清理**
```typescript
aboutToDisappear(): void {
  // 自动清理所有资源
  this.lifecycle.destroy()
  
  // 其他清理代码...
  ThemeAwareHelper.cleanupThemeAware(this.componentId)
}
```

---

## 2. 详细迁移场景

### 场景 1: 定时器管理

#### 问题代码
```typescript
@Component
export struct MyPage {
  private timerId: number = -1
  
  someMethod() {
    // 可能忘记清理
    this.timerId = setTimeout(() => {
      this.updateData()
    }, 1000)
  }
  
  aboutToDisappear() {
    // 需要手动记住清理
    if (this.timerId !== -1) {
      clearTimeout(this.timerId)
    }
  }
}
```

#### 迁移后
```typescript
@Component
export struct MyPage {
  private lifecycle = new PageLifecycleManager('MyPage')
  
  someMethod() {
    // 自动管理，无需保存 ID
    this.lifecycle.setTimeout(() => {
      this.updateData()
    }, 1000)
  }
  
  aboutToDisappear() {
    // 自动清理所有定时器
    this.lifecycle.destroy()
  }
}
```

### 场景 2: 异步操作管理

#### 问题代码
```typescript
async loadData() {
  // 无法取消，页面销毁后仍在执行
  const data = await fetchFromServer()
  this.data = data  // 可能在页面销毁后执行
}
```

#### 迁移后
```typescript
async loadData() {
  try {
    // 可取消的 Promise
    const data = await this.lifecycle.registerPromise(
      fetchFromServer()
    )
    this.data = data
  } catch (error) {
    if (error instanceof CancellationError) {
      // 操作被取消，正常情况
      return
    }
    // 处理其他错误
  }
}
```

### 场景 3: 资源管理

#### 问题代码
```typescript
@Component
export struct JsvmPlaygroundPage {
  private quickjsInitialized: boolean = false
  private rhinoEngine: LegadoRhinoEngine | null = null
  
  aboutToDisappear() {
    // 容易遗漏清理步骤
    if (this.quickjsInitialized) {
      quickjs.destroy?.()
    }
    if (this.rhinoEngine) {
      this.rhinoEngine.destroy?.()
    }
  }
}
```

#### 迁移后
```typescript
@Component
export struct JsvmPlaygroundPage {
  private lifecycle = new PageLifecycleManager('JsvmPlaygroundPage')
  private quickjsInitialized: boolean = false
  private rhinoEngine: LegadoRhinoEngine | null = null
  
  initQuickJS() {
    quickjs.init()
    this.quickjsInitialized = true
    
    // 注册清理逻辑
    this.lifecycle.registerResource({
      dispose: () => {
        if (this.quickjsInitialized) {
          quickjs.destroy?.()
          this.quickjsInitialized = false
        }
      }
    })
  }
  
  async initRhinoEngine() {
    this.rhinoEngine = getLegadoRhinoEngine()
    await this.rhinoEngine.initialize()
    
    // 注册清理逻辑
    this.lifecycle.registerResource({
      dispose: () => {
        if (this.rhinoEngine) {
          this.rhinoEngine.destroy?.()
          this.rhinoEngine = null
        }
      }
    })
  }
  
  aboutToDisappear() {
    // 自动清理所有资源
    this.lifecycle.destroy()
  }
}
```

### 场景 4: 事件监听器管理

#### 问题代码
```typescript
@Component
export struct MyPage {
  private deviceListener = (event) => {
    this.handleDeviceChange(event)
  }
  
  aboutToAppear() {
    deviceManager.addEventListener('change', this.deviceListener)
  }
  
  aboutToDisappear() {
    // 容易忘记移除
    deviceManager.removeEventListener('change', this.deviceListener)
  }
}
```

#### 迁移后
```typescript
@Component
export struct MyPage {
  private lifecycle = new PageLifecycleManager('MyPage')
  
  aboutToAppear() {
    // 自动管理监听器
    this.lifecycle.addEventListener(
      deviceManager,
      'change',
      (event) => this.handleDeviceChange(event)
    )
  }
  
  aboutToDisappear() {
    // 自动移除所有监听器
    this.lifecycle.destroy()
  }
}
```

---

## 3. 高级用法

### 3.1 可取消的网络请求

```typescript
async searchBooks(keyword: string) {
  try {
    // 包装网络请求为可取消的 Promise
    const results = await this.lifecycle.registerPromise(
      this.bookService.search(keyword)
    )
    this.searchResults = results
  } catch (error) {
    if (error instanceof CancellationError) {
      // 搜索被取消（用户离开页面）
      console.log('搜索已取消')
      return
    }
    // 处理其他错误
    this.showError(error)
  }
}
```

### 3.2 带超时的操作

```typescript
import { CancellablePromise } from '../Framework/Lifecycle'

async validateSource() {
  const promise = this.lifecycle.registerPromise(
    this.sourceValidator.validate(this.source)
  )
  
  // 添加 30 秒超时
  const result = await CancellablePromise.withTimeout(
    promise,
    30000,
    '书源校验超时'
  )
  
  return result
}
```

### 3.3 批量异步操作

```typescript
async loadMultipleChapters() {
  const promises = this.chapterIds.map(id => 
    this.lifecycle.registerPromise(
      this.chapterService.load(id)
    )
  )
  
  // 等待所有章节加载完成
  const chapters = await CancellablePromise.all(promises)
  this.chapters = chapters
}
```

### 3.4 自定义资源类

```typescript
class WebViewResource implements Disposable {
  constructor(private controller: webview.WebviewController) {}
  
  async dispose() {
    this.controller.clearHistory()
    this.controller.clearCache()
    // 其他清理操作
  }
}

// 使用
const webViewResource = new WebViewResource(this.webViewController)
this.lifecycle.registerResource(webViewResource)
```

---

## 4. 常见问题

### Q1: 是否需要迁移所有页面？

**A**: 建议优先迁移以下页面：
1. 包含定时器的页面（必须）
2. 有长时间异步操作的页面（必须）
3. 管理外部资源的页面（必须）
4. 高频使用的页面（推荐）

### Q2: 性能影响如何？

**A**: 框架设计为轻量级：
- 定时器管理：几乎零开销（仅多一层映射）
- Promise 包装：轻量级包装，可忽略
- 内存占用：每个页面约 1-2KB

### Q3: 如何调试？

**A**: 启用调试模式：
```typescript
private lifecycle = new PageLifecycleManager('MyPage', {
  enableDebug: true,        // 启用调试日志
  enableStackTrace: true    // 记录调用栈（性能影响）
})

// 查看统计信息
console.log(this.lifecycle.getStats())

// 导出详细信息
console.log(this.lifecycle.dumpInfo())
```

### Q4: 与现有 BackgroundTaskManager 的关系？

**A**: 两者互补：
- **PageLifecycleManager**: 管理页面级的短期任务
- **BackgroundTaskManager**: 管理跨页面的长期后台任务

可以同时使用：
```typescript
// 页面级任务
this.lifecycle.setTimeout(() => {...}, 1000)

// 后台任务
const taskId = BackgroundTaskManager.getInstance().createTask(...)
```

### Q5: 如何处理组件而非页面？

**A**: 组件也可以使用：
```typescript
@Component
export struct MyComponent {
  private lifecycle = new PageLifecycleManager('MyComponent')
  
  aboutToDisappear() {
    this.lifecycle.destroy()
  }
}
```

---

## 5. 迁移检查清单

使用此清单确保迁移完整：

- [ ] 导入 `PageLifecycleManager`
- [ ] 创建生命周期管理器实例
- [ ] 替换所有 `setTimeout` 为 `lifecycle.setTimeout`
- [ ] 替换所有 `setInterval` 为 `lifecycle.setInterval`
- [ ] 包装长时间异步操作为 `registerPromise`
- [ ] 注册需要释放的资源
- [ ] 使用 `addEventListener` 管理事件监听器
- [ ] 在 `aboutToDisappear` 中调用 `lifecycle.destroy()`
- [ ] 测试页面快速切换场景
- [ ] 测试内存泄漏（连续打开/关闭 50 次）
- [ ] 验证异步操作可正确取消

---

## 6. 完整示例

### 迁移前（JsvmPlaygroundPage）

```typescript
@Component
export struct JsvmPlaygroundPage {
  @State isExecuting: boolean = false
  private quickjsInitialized: boolean = false
  private rhinoEngine: LegadoRhinoEngine | null = null
  private webViewController: webview.WebviewController = new webview.WebviewController()
  
  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId)
    // ❌ 缺少资源清理
  }
  
  async executeCode() {
    this.isExecuting = true
    // ❌ 无法取消
    const result = await engine.execute(this.codeInput)
    this.outputText = result.result
    this.isExecuting = false
  }
}
```

### 迁移后

```typescript
import { PageLifecycleManager, CancellationError } from '../Framework/Lifecycle'

@Component
export struct JsvmPlaygroundPage {
  // ✅ 添加生命周期管理器
  private lifecycle = new PageLifecycleManager('JsvmPlaygroundPage', {
    enableDebug: __DEBUG__
  })
  
  @State isExecuting: boolean = false
  private quickjsInitialized: boolean = false
  private rhinoEngine: LegadoRhinoEngine | null = null
  private webViewController: webview.WebviewController = new webview.WebviewController()
  
  aboutToDisappear(): void {
    // ✅ 自动清理所有资源
    this.lifecycle.destroy()
    ThemeAwareHelper.cleanupThemeAware(this.componentId)
  }
  
  initQuickJS() {
    quickjs.init()
    this.quickjsInitialized = true
    
    // ✅ 注册清理逻辑
    this.lifecycle.registerResource({
      dispose: () => {
        if (this.quickjsInitialized) {
          quickjs.destroy?.()
          this.quickjsInitialized = false
        }
      }
    })
  }
  
  async initRhinoEngine() {
    this.rhinoEngine = getLegadoRhinoEngine()
    await this.rhinoEngine.initialize()
    
    // ✅ 注册清理逻辑
    this.lifecycle.registerResource({
      dispose: async () => {
        if (this.rhinoEngine) {
          await this.rhinoEngine.destroy?.()
          this.rhinoEngine = null
        }
      }
    })
  }
  
  async executeCode() {
    this.isExecuting = true
    
    try {
      // ✅ 可取消的异步操作
      const result = await this.lifecycle.registerPromise(
        engine.execute(this.codeInput)
      )
      this.outputText = result.result
    } catch (error) {
      if (error instanceof CancellationError) {
        // 页面销毁导致的取消，正常情况
        return
      }
      this.outputText = `错误: ${error}`
    } finally {
      this.isExecuting = false
    }
  }
}
```

---

## 7. 性能优化建议

### 7.1 避免过度包装

```typescript
// ❌ 不必要的包装
this.lifecycle.registerPromise(Promise.resolve(123))

// ✅ 只包装真正需要取消的操作
const data = await this.lifecycle.registerPromise(
  this.fetchDataFromServer()  // 网络请求
)
```

### 7.2 合理使用定时器

```typescript
// ❌ 频繁创建定时器
for (let i = 0; i < 100; i++) {
  this.lifecycle.setTimeout(() => {...}, i * 100)
}

// ✅ 使用单个定时器 + 循环
let count = 0
const timerId = this.lifecycle.setInterval(() => {
  // 处理逻辑
  if (++count >= 100) {
    this.lifecycle.clearInterval(timerId)
  }
}, 100)
```

### 7.3 及时清理不需要的资源

```typescript
// 如果某个资源提前不需要了，可以手动注销
const resource = new MyResource()
this.lifecycle.registerResource(resource)

// 提前清理
this.lifecycle.unregisterResource(resource)
resource.dispose()
```

---

## 8. 故障排查

### 问题：页面销毁后仍有任务执行

**检查**：
1. 是否调用了 `lifecycle.destroy()`？
2. 是否所有异步操作都通过 `registerPromise` 包装？
3. 是否有直接使用全局 `setTimeout` 的地方？

### 问题：内存泄漏

**检查**：
1. 使用 `GlobalTaskCoordinator.getInstance().printDebugInfo()` 查看活跃任务
2. 检查是否有循环引用
3. 确认所有资源都实现了 `dispose` 方法

### 问题：性能下降

**检查**：
1. 是否启用了 `enableStackTrace`（仅用于调试）
2. 定时器数量是否过多（查看 `getStats()`）
3. 是否有不必要的 Promise 包装

---

## 9. 最佳实践

1. **统一命名**: 生命周期管理器变量统一命名为 `lifecycle`
2. **早期初始化**: 在 `aboutToAppear` 中初始化资源并注册清理
3. **防御性编程**: 在 `dispose` 中检查资源状态
4. **日志记录**: 开发模式下启用调试日志
5. **测试覆盖**: 为关键页面编写生命周期测试

---

**文档版本**: 1.0  
**最后更新**: 2025-12-30
