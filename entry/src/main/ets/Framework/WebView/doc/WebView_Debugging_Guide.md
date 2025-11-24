# WebView调试指南

## 问题诊断

### 症状
WebView测试页面按钮点击后没有反应，日志显示：
```
[18:08:27.535] 开始Web基础测试
[18:08:33.461] 开始Web基础测试
```

但没有后续的页面加载日志。

### 可能的原因

#### 1. WebView控制器未正确附加到Web组件
**检查方法：**
- 查看是否有 `✅ WebView控制器已附加到Web组件` 日志
- 如果没有，说明Web组件没有正确初始化

**解决方案：**
确保Web组件在页面显示时已经渲染：
```typescript
Web({ src: 'about:blank', controller: this.webviewController })
  .onControllerAttached(() => {
    logger.info(TAG, '✅ WebView控制器已附加到Web组件');
  })
```

#### 2. 网络权限未配置
**检查方法：**
查看 `module.json5` 是否包含网络权限：

```json
{
  "module": {
    "requestPermissions": [
      {
        "name": "ohos.permission.INTERNET",
        "reason": "访问网络内容",
        "usedScene": {
          "ability": ["EntryAbility"],
          "when": "always"
        }
      }
    ]
  }
}
```

#### 3. Web组件未正确渲染
**检查方法：**
- 确认Web组件有明确的宽度和高度
- 检查是否被其他组件遮挡
- 查看是否有visibility或opacity设置

**当前配置：**
```typescript
Web({ src: 'about:blank', controller: this.webviewController })
  .width('100%')
  .height(300)  // 明确的高度
```

#### 4. WebView初始化时机问题
**问题：**
WebView控制器在组件构造时创建，但Web组件可能还未渲染。

**解决方案：**
在 `onControllerAttached` 回调中执行初始化操作：

```typescript
Web({ src: 'about:blank', controller: this.webviewController })
  .onControllerAttached(() => {
    logger.info(TAG, 'WebView已就绪');
    // 可以在这里执行初始化操作
  })
```

#### 5. 异常未被捕获
**增强错误处理：**
```typescript
private startWebBasicTest(): void {
  try {
    logger.info(TAG, '🔵 开始Web基础测试');
    logger.info(TAG, `目标URL: ${this.webTestUrl}`);
    logger.info(TAG, `WebView控制器状态: ${this.webviewController ? '已初始化' : '未初始化'}`);
    
    this.webviewController.loadUrl(this.webTestUrl);
    logger.info(TAG, '🔵 loadUrl 调用完成');
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    logger.error(TAG, `❌ Web基础测试失败: ${msg}`);
    logger.error(TAG, `错误堆栈: ${e instanceof Error ? e.stack : '无堆栈信息'}`);
    this.jsOutput = `错误: ${msg}`;
  }
}
```

## 调试步骤

### 步骤1: 检查基础日志
运行应用后，查找以下关键日志：

1. **页面初始化**
   ```
   ✅ WebView控制器已附加到Web组件
   ```

2. **按钮点击**
   ```
   🔵 开始Web基础测试
   目标URL: https://www.bing.com/
   WebView控制器状态: 已初始化
   🔵 调用 loadUrl...
   🔵 loadUrl 调用完成
   ```

3. **页面加载**
   ```
   🟢 页面开始加载: https://www.bing.com/
   📊 加载进度: 10%
   📊 加载进度: 50%
   📊 加载进度: 100%
   🟢 页面加载完成: https://www.bing.com/
   📄 页面标题: Bing
   ```

### 步骤2: 如果没有"控制器已附加"日志

**原因：** Web组件未正确渲染

**检查：**
1. 确认页面布局中包含Web组件
2. 检查Web组件是否有足够的空间（宽度和高度）
3. 查看是否有布局错误

**解决：**
```typescript
Column() {
  Web({ src: 'about:blank', controller: this.webviewController })
    .width('100%')
    .height(300)  // 确保有明确的高度
    .backgroundColor(Color.White)  // 添加背景色便于调试
}
.width('100%')
```

### 步骤3: 如果有"控制器已附加"但loadUrl失败

**可能原因：**
1. 网络权限未配置
2. URL格式错误
3. WebView未完全初始化

**解决：**
```typescript
.onControllerAttached(() => {
  logger.info(TAG, '✅ WebView控制器已附加');
  
  // 延迟一小段时间确保完全初始化
  setTimeout(() => {
    logger.info(TAG, 'WebView初始化完成，可以开始使用');
  }, 100);
})
```

### 步骤4: 如果loadUrl调用成功但没有页面加载事件

**可能原因：**
1. 网络连接问题
2. URL被阻止
3. SSL证书问题

**添加错误监听：**
```typescript
.onErrorReceive((event) => {
  const errorInfo = event.error.getErrorInfo();
  logger.error(TAG, `❌ 页面加载错误: ${errorInfo}`);
  // 显示错误信息给用户
})
.onHttpErrorReceive((event) => {
  logger.error(TAG, `❌ HTTP错误: ${event.response.getResponseCode()}`);
})
.onSslErrorEventReceive((event) => {
  logger.error(TAG, `❌ SSL错误: ${event.error}`);
  // 开发环境可以选择继续，生产环境应该取消
  // event.handler.handleConfirm();  // 继续（不安全）
  event.handler.handleCancel();      // 取消（安全）
})
```

## 常见问题解决方案

### 问题1: WebView一直显示空白

**解决方案：**
1. 检查是否调用了 `loadUrl`
2. 确认URL格式正确（包含 `http://` 或 `https://`）
3. 检查网络权限
4. 查看是否有错误日志

### 问题2: JavaScript无法执行

**解决方案：**
```typescript
Web({ src: url, controller: this.controller })
  .javaScriptAccess(true)  // 必须启用
  .domStorageAccess(true)  // 建议启用
```

### 问题3: 页面加载缓慢

**解决方案：**
```typescript
.cacheMode(CacheMode.Default)  // 启用缓存
.imageAccess(true)             // 根据需要启用图片
.onProgressChange((event) => {
  // 显示加载进度
  console.log(`加载进度: ${event.newProgress}%`);
})
```

### 问题4: 控制器方法调用失败

**原因：** 在控制器附加之前调用方法

**解决方案：**
```typescript
private isWebViewReady: boolean = false;

Web({ src: 'about:blank', controller: this.controller })
  .onControllerAttached(() => {
    this.isWebViewReady = true;
  })

// 使用前检查
if (this.isWebViewReady) {
  this.controller.loadUrl(url);
} else {
  logger.warn(TAG, 'WebView未就绪');
}
```

## 最佳实践

### 1. 初始化顺序
```typescript
// 1. 创建控制器（在组件属性中）
private webviewController: webview.WebviewController = new webview.WebviewController();

// 2. 渲染Web组件
Web({ src: 'about:blank', controller: this.webviewController })

// 3. 等待控制器附加
.onControllerAttached(() => {
  // 4. 现在可以安全使用控制器
})
```

### 2. 错误处理
始终添加完整的错误处理：
```typescript
.onErrorReceive((event) => {
  logger.error(TAG, `加载错误: ${event.error.getErrorInfo()}`);
})
.onHttpErrorReceive((event) => {
  logger.error(TAG, `HTTP错误: ${event.response.getResponseCode()}`);
})
.onSslErrorEventReceive((event) => {
  logger.error(TAG, `SSL错误`);
  event.handler.handleCancel();
})
```

### 3. 生命周期管理
```typescript
aboutToAppear() {
  logger.info(TAG, 'WebView页面初始化');
}

aboutToDisappear() {
  logger.info(TAG, 'WebView页面销毁');
  // 清理资源
}
```

### 4. 日志记录
使用结构化的日志：
```typescript
logger.info(TAG, '🔵 操作开始');
logger.debug(TAG, '📊 进度信息');
logger.error(TAG, '❌ 错误信息');
logger.info(TAG, '✅ 操作完成');
```

## 性能优化

### 1. 启用缓存
```typescript
.cacheMode(CacheMode.Default)
```

### 2. 按需加载资源
```typescript
.imageAccess(false)  // 如果不需要图片
.fileAccess(false)   // 如果不需要文件访问
```

### 3. 使用页面缓存（API 12+）
```typescript
const cacheOptions = new webview.BackForwardCacheOptions();
cacheOptions.size = 5;
cacheOptions.timeToLive = 300;

const controller = new webview.WebviewController({
  backForwardCacheOptions: cacheOptions
});
```

## 总结

WebView调试的关键是：
1. ✅ 确保控制器正确附加
2. ✅ 添加完整的事件监听
3. ✅ 详细的日志记录
4. ✅ 完善的错误处理
5. ✅ 正确的初始化顺序

通过以上方法，可以快速定位和解决WebView相关问题。
