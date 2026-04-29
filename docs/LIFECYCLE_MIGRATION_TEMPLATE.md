# 页面生命周期管理 - 快速迁移模板

## 通用迁移步骤

### 步骤 1: 添加导入

```typescript
import { PageLifecycleManager, CancellationError } from '../Framework/Lifecycle';
```

### 步骤 2: 添加生命周期管理器

```typescript
@Component
export struct YourPage {
  // 添加生命周期管理器（在其他属性之后）
  private lifecycle = new PageLifecycleManager('YourPageName', {
    enableDebug: true  // 开发模式下启用
  });
  
  // ... 其他代码
}
```

### 步骤 3: 替换定时器

**查找所有 setTimeout/setInterval 调用并替换：**

```typescript
// ❌ 旧代码
setTimeout(() => {
  this.doSomething();
}, 1000);

// ✅ 新代码
this.lifecycle.setTimeout(() => {
  this.doSomething();
}, 1000);
```

```typescript
// ❌ 旧代码
this.timerId = setInterval(() => {
  this.update();
}, 1000);

// ✅ 新代码
this.lifecycle.setInterval(() => {
  this.update();
}, 1000);
```

### 步骤 4: 包装异步操作

**对于长时间运行的异步操作：**

```typescript
// ❌ 旧代码
async loadData() {
  const data = await fetchFromServer();
  this.data = data;
}

// ✅ 新代码
async loadData() {
  try {
    const data = await this.lifecycle.registerPromise(
      fetchFromServer()
    );
    this.data = data;
  } catch (error) {
    if (error instanceof CancellationError) {
      return; // 正常取消
    }
    // 处理其他错误
  }
}
```

### 步骤 5: 注册资源清理

**对于需要显式清理的资源：**

```typescript
// 在初始化资源后立即注册清理逻辑
initSomeResource() {
  this.resource = createResource();
  
  // 注册清理
  this.lifecycle.registerResource({
    dispose: () => {
      if (this.resource) {
        this.resource.destroy?.();
        this.resource = null;
      }
    }
  });
}
```

### 步骤 6: 更新 aboutToDisappear

```typescript
aboutToDisappear(): void {
  logger.lifecycle(TAG, 'aboutToDisappear - 开始清理资源');
  
  // 自动清理所有资源
  this.lifecycle.destroy();
  
  // 其他清理代码（如主题清理）
  ThemeAwareHelper.cleanupThemeAware(this.componentId);
  
  logger.lifecycle(TAG, 'aboutToDisappear - 资源清理完成');
}
```

---

## 特定场景模板

### MangaReaderPage / NovelReaderPage 模板

```typescript
import { PageLifecycleManager, CancellationError } from '../Framework/Lifecycle';

@Component
export struct MangaReaderPage {
  private lifecycle = new PageLifecycleManager('MangaReaderPage', {
    enableDebug: true
  });
  
  // 替换所有定时器
  private startAutoPageTurn() {
    // ❌ this.autoTurnTimer = setTimeout(...)
    this.lifecycle.setTimeout(() => {
      this.turnNextPage();
    }, this.autoTurnInterval);
  }
  
  // 包装长时间操作
  private async loadChapter() {
    try {
      const chapter = await this.lifecycle.registerPromise(
        this.chapterService.load(this.chapterId)
      );
      this.chapter = chapter;
    } catch (error) {
      if (error instanceof CancellationError) {
        return;
      }
      this.handleError(error);
    }
  }
  
  aboutToDisappear() {
    this.lifecycle.destroy();
    // 其他清理...
  }
}
```

### MangaDetailPage 模板

```typescript
import { PageLifecycleManager, CancellationError } from '../Framework/Lifecycle';

@Component
export struct MangaDetailPage {
  private lifecycle = new PageLifecycleManager('MangaDetailPage', {
    enableDebug: true
  });
  
  // 替换防抖定时器
  private onSearchInput(text: string) {
    // ❌ clearTimeout(this.searchDebounceTimer);
    // ❌ this.searchDebounceTimer = setTimeout(...)
    
    this.lifecycle.setTimeout(() => {
      this.performSearch(text);
    }, 300);
  }
  
  // 包装网络请求
  private async loadMangaInfo() {
    try {
      const info = await this.lifecycle.registerPromise(
        this.mangaService.getInfo(this.mangaId)
      );
      this.mangaInfo = info;
    } catch (error) {
      if (error instanceof CancellationError) {
        return;
      }
      this.showError(error);
    }
  }
  
  aboutToDisappear() {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }
}
```

### NovelSourceDebugPage 模板

```typescript
import { PageLifecycleManager, CancellationError } from '../Framework/Lifecycle';

@Component
export struct NovelSourceDebugPage {
  private lifecycle = new PageLifecycleManager('NovelSourceDebugPage', {
    enableDebug: true
  });
  
  // 包装书源校验（长时间操作）
  private async validateSource() {
    try {
      const result = await this.lifecycle.registerPromise(
        this.sourceValidator.validate(this.source)
      );
      this.validationResult = result;
    } catch (error) {
      if (error instanceof CancellationError) {
        logger.info(TAG, '校验已取消');
        return;
      }
      this.showError(error);
    }
  }
  
  // 注册 WebView 清理
  initWebView() {
    this.webViewController = new webview.WebviewController();
    
    this.lifecycle.registerResource({
      dispose: () => {
        if (this.webViewController) {
          this.webViewController.clearHistory();
          this.webViewController.clearCache();
        }
      }
    });
  }
  
  aboutToDisappear() {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }
}
```

---

## 检查清单

迁移完成后，使用此清单验证：

- [ ] 已导入 `PageLifecycleManager` 和 `CancellationError`
- [ ] 已创建 `lifecycle` 实例
- [ ] 所有 `setTimeout` 已替换为 `lifecycle.setTimeout`
- [ ] 所有 `setInterval` 已替换为 `lifecycle.setInterval`
- [ ] 长时间异步操作已用 `registerPromise` 包装
- [ ] 需要清理的资源已用 `registerResource` 注册
- [ ] `aboutToDisappear` 中调用了 `lifecycle.destroy()`
- [ ] 测试页面快速切换（10次）
- [ ] 测试异步操作中途退出
- [ ] 检查日志确认资源已清理

---

## 常见问题

### Q: 如何处理保存的定时器 ID？

**A**: 不需要保存 ID，生命周期管理器会自动管理：

```typescript
// ❌ 旧代码
private timerId: number = -1;
this.timerId = setTimeout(...);
clearTimeout(this.timerId);

// ✅ 新代码
this.lifecycle.setTimeout(...);  // 无需保存 ID
// destroy() 时自动清理
```

### Q: 如何处理条件清理？

**A**: 使用 `onDestroy` 回调：

```typescript
this.lifecycle.onDestroy(() => {
  if (this.shouldSave) {
    this.saveData();
  }
});
```

### Q: 如何处理嵌套组件？

**A**: 每个组件都应有自己的生命周期管理器：

```typescript
@Component
struct ChildComponent {
  private lifecycle = new PageLifecycleManager('ChildComponent');
  
  aboutToDisappear() {
    this.lifecycle.destroy();
  }
}
```

---

**文档版本**: 1.0  
**最后更新**: 2025-12-30
