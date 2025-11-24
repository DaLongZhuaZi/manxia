# 不可见WebView使用指南

## 概述

不可见WebView系统提供了一个在后台运行WebView的解决方案，适用于网页自动化、数据抓取等场景。该系统完全符合HarmonyOS API 18规范。

## 核心组件

### 1. InvisibleWebView 组件
不可见的WebView组件，特点：
- 尺寸为1x1像素，完全透明
- 位于屏幕外（负坐标）
- 支持完整的WebView功能
- 提供事件回调机制

### 2. WebViewContainer 容器
用于承载多个不可见WebView实例的容器组件。

### 3. GlobalWebViewContainer 全局管理器
提供便捷的API来操作WebView容器。

## 使用方法

### 步骤1: 在主页面中添加WebView容器

在您的主页面或应用入口页面中添加WebView容器：

```typescript
import { WebViewContainer, GlobalWebViewContainer } from '../Framework/WebView/WebViewContainerPage';

@Entry
@Component
struct MainPage {
  // WebView容器引用
  private webViewContainerRef: WebViewContainer | null = null;

  aboutToAppear() {
    // 在组件出现时设置全局容器引用
    if (this.webViewContainerRef) {
      GlobalWebViewContainer.setContainer(this.webViewContainerRef);
    }
  }

  build() {
    Stack() {
      // 您的主要UI内容
      Column() {
        // ...
      }
      
      // 不可见的WebView容器（放在最后）
      WebViewContainer()
        .onAppear(() => {
          // 保存容器引用
          // 注意：这里需要通过其他方式获取组件引用
        })
    }
  }
}
```

### 步骤2: 使用WebViewSourceManager创建WebView实例

```typescript
import { WebViewSourceManager } from '../Framework/WebView/WebViewSourceManager';
import { ComicSourceDatabaseRecord } from '../Framework/Database/DatabaseTypes';

// 初始化源管理器
const sourceManager = WebViewSourceManager.getInstance();
await sourceManager.initialize();

// 初始化一个漫画源
const sourceRecord: ComicSourceDatabaseRecord = {
  id: 'source_001',
  name: '示例漫画源',
  baseUrl: 'https://example.com',
  // ... 其他配置
};

sourceManager.initializeSource(sourceRecord);

// 获取WebView实例（会自动创建并添加到容器）
const controller = sourceManager.getWebViewInstance('source_001');

if (controller) {
  // 使用控制器进行操作
  controller.loadUrl('https://example.com');
  
  // 执行JavaScript
  const result = await controller.runJavaScript('document.title');
  console.log('页面标题:', result);
}

// 使用完毕后释放
sourceManager.releaseWebViewInstance('source_001');
```

### 步骤3: 直接使用GlobalWebViewContainer

如果不使用WebViewSourceManager，也可以直接使用GlobalWebViewContainer：

```typescript
import { webview } from '@kit.ArkWeb';
import { GlobalWebViewContainer, WebViewEventCallbacks } from '../Framework/WebView/WebViewContainerPage';
import { WebViewSourceConfig } from '../Framework/WebView/WebViewImageLoader';

// 创建控制器
const controller = new webview.WebviewController();

// 配置
const config: WebViewSourceConfig = {
  sourceId: 'custom_001',
  userAgent: 'Mozilla/5.0 ...',
  enableJavaScript: true,
  enableImages: true,
  cookiePolicy: 'default',
  timeout: 30000
};

// 事件回调
const callbacks: WebViewEventCallbacks = {
  onPageBegin: (url) => {
    console.log('开始加载:', url);
  },
  onPageEnd: (url) => {
    console.log('加载完成:', url);
  },
  onError: (error) => {
    console.error('加载错误:', error);
  }
};

// 添加到容器
GlobalWebViewContainer.addWebView('custom_001', controller, config, callbacks, 'https://example.com');

// 使用控制器
setTimeout(async () => {
  const title = await controller.runJavaScript('document.title');
  console.log('标题:', title);
}, 3000);

// 移除
GlobalWebViewContainer.removeWebView('custom_001');
```

## 事件回调

WebView支持以下事件回调：

```typescript
interface WebViewEventCallbacks {
  /** 页面开始加载 */
  onPageBegin?: (url: string) => void;
  
  /** 页面加载完成 */
  onPageEnd?: (url: string) => void;
  
  /** 页面加载进度 */
  onProgressChange?: (progress: number) => void;
  
  /** 页面加载错误 */
  onError?: (error: string) => void;
  
  /** 控制台消息 */
  onConsoleMessage?: (message: string, level: string) => void;
}
```

## 最佳实践

### 1. 容器初始化时机
在应用启动时尽早初始化WebView容器，确保后续操作能够正常进行。

### 2. 资源管理
- 及时释放不再使用的WebView实例
- 避免同时创建过多WebView实例（建议不超过3-5个）
- 使用`releaseWebViewInstance`标记实例为空闲状态

### 3. 错误处理
始终提供错误回调，处理加载失败的情况：

```typescript
const callbacks: WebViewEventCallbacks = {
  onError: (error) => {
    console.error('WebView错误:', error);
    // 实现重试逻辑或错误上报
  }
};
```

### 4. JavaScript执行
执行JavaScript时注意：
- 确保页面已加载完成（在`onPageEnd`回调中执行）
- `runJavaScript`返回的是字符串，需要手动解析
- 添加超时处理

```typescript
async function executeJavaScriptSafely(
  controller: webview.WebviewController,
  script: string,
  timeout: number = 5000
): Promise<string> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      reject(new Error('JavaScript执行超时'));
    }, timeout);
    
    controller.runJavaScript(script)
      .then(result => {
        clearTimeout(timer);
        resolve(result);
      })
      .catch(error => {
        clearTimeout(timer);
        reject(error);
      });
  });
}
```

## 与MangaSourceEngine集成

不可见WebView系统已经与MangaSourceEngine完全集成：

```typescript
import { MangaSourceEngine, EngineConfig } from '../Framework/WebView/MangaSourceEngine';
import { webview } from '@kit.ArkWeb';

// 获取WebView控制器
const controller = sourceManager.getWebViewInstance('source_001');

if (controller) {
  // 创建引擎配置
  const engineConfig: EngineConfig = {
    webViewController: controller,
    antiCrawlerConfig: {
      cloudflare: { enabled: true },
      captcha: { enabled: false },
      ipBlock: { enabled: true }
    },
    debug: true,
    timeout: 30000,
    caseSensitive: false
  };

  // 创建引擎
  const engine = new MangaSourceEngine(engineConfig);

  // 加载配置
  await engine.loadConfig(jsonConfigContent);

  // 执行搜索
  const result = await engine.searchManga('关键词', 1);
  console.log('搜索结果:', result);
}
```

## 注意事项

### 1. 生命周期管理
- WebView容器应该在应用的整个生命周期中保持存在
- 不要频繁创建和销毁容器
- 在应用退出时清理所有WebView实例

### 2. 内存管理
- 每个WebView实例会占用约50-100MB内存
- 定期清理不再使用的实例
- 监控内存使用情况

### 3. 线程安全
- WebView操作必须在UI线程执行
- 使用`runJavaScript`时注意异步处理

### 4. 权限配置
确保在`module.json5`中配置了必要的权限：

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

## 故障排除

### 问题1: WebView不工作
**原因**: 容器未正确初始化
**解决**: 确保在使用前调用`GlobalWebViewContainer.setContainer()`

### 问题2: JavaScript执行失败
**原因**: 页面未加载完成或JavaScript未启用
**解决**: 在`onPageEnd`回调中执行，确保`enableJavaScript: true`

### 问题3: 内存泄漏
**原因**: WebView实例未正确释放
**解决**: 使用完毕后调用`removeWebView`或`releaseWebViewInstance`

## 性能优化

### 1. 启用页面缓存（API 12+）
```typescript
const cacheOptions = new webview.BackForwardCacheOptions();
cacheOptions.size = 5;
cacheOptions.timeToLive = 300;

const controller = new webview.WebviewController({
  backForwardCacheOptions: cacheOptions
});
```

### 2. 资源拦截
在Web组件中使用`onLoadIntercept`拦截不必要的资源加载。

### 3. 复用实例
尽可能复用WebView实例，通过`loadUrl`切换页面而不是创建新实例。

## 总结

不可见WebView系统提供了一个强大且灵活的后台WebView解决方案，完全符合HarmonyOS API 18规范。通过正确使用该系统，可以实现高效的网页自动化和数据抓取功能。
