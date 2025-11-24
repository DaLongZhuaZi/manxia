# WebView系统迁移计划

## 📋 问题分析

### 当前架构问题
1. **SourceDetailPage使用错误的执行器**
   - 当前：`SourceManager` → `SourceExecutor` → 简单HTTP请求 + JSONPath解析
   - 应该：`MangaSourceEngine` → WebView自动化操作

2. **两套并行系统**
   - ❌ **HTTP系统**（应废弃）：
     - `SourceManager` - 基于HTTP
     - `SourceExecutor` - HTTP + JSONPath
     - `JSONSourceParser` - JSONPath配置解析
   
   - ✅ **WebView系统**（正确）：
     - `InvisibleWebView` - 不可见WebView组件
     - `WebViewContainer` - WebView容器管理
     - `WebViewSourceManager` - 源配置管理
     - `MangaSourceEngine` - 操作引擎
     - `MangaSourceActionEngine` - 动作执行器

3. **配置格式不兼容**
   - 旧格式：JSONPath + HTTP配置（`komiic.json`当前格式）
   - 新格式：WebView actions数组（操作流程定义）

---

## 🎯 修复目标

让所有图源操作都基于WebView系统，而不是简单的HTTP请求。

---

## 📝 实施计划

### ✅ 阶段1：基础设施准备（已完成）
- [x] `InvisibleWebView`组件 - 后台WebView
- [x] `WebViewContainer`容器 - 管理多个WebView实例
- [x] `WebViewSourceManager` - 源配置管理
- [x] `MangaSourceEngine` - 操作引擎
- [x] `MangaSourceActionEngine` - 动作执行
- [x] 在`MainMenuPage`中添加全局WebView容器

### 🔄 阶段2：SourceDetailPage重构（进行中）

#### 2.1 添加WebView支持
```typescript
// 在SourceDetailPage中添加
@State private webViewController: webview.WebviewController | null = null;
private mangaSourceEngine: MangaSourceEngine | null = null;
private webViewSourceManager: WebViewSourceManager = WebViewSourceManager.getInstance();
```

#### 2.2 初始化WebView引擎
```typescript
async aboutToAppear(): void {
  // ... 现有代码 ...
  
  // 初始化WebView引擎
  await this.initializeWebViewEngine();
  
  // 加载图源配置
  await this.loadSourceConfig();
}

private async initializeWebViewEngine(): Promise<void> {
  try {
    // 创建WebView控制器
    this.webViewController = new webview.WebviewController();
    
    // 配置引擎
    const engineConfig: EngineConfig = {
      webViewController: this.webViewController,
      antiCrawlerConfig: {
        enableCloudflareBypass: true,
        enableCaptchaDetection: true,
        enableIPBlockDetection: true
      },
      debug: true,
      timeout: 30000,
      caseSensitive: false
    };
    
    // 创建引擎实例
    this.mangaSourceEngine = new MangaSourceEngine(engineConfig);
    
    logger.info(TAG, 'WebView引擎初始化成功');
  } catch (error) {
    logger.error(TAG, 'WebView引擎初始化失败', String(error));
  }
}
```

#### 2.3 加载图源配置
```typescript
private async loadSourceConfig(): Promise<void> {
  try {
    // 从数据库获取图源配置
    const config = await this.dataManager.getSourceConfig(this.sourceId);
    if (!config) {
      throw new Error('图源配置不存在');
    }
    
    // 加载到引擎
    await this.mangaSourceEngine?.loadConfigFromObject(config);
    
    logger.info(TAG, '图源配置加载成功');
  } catch (error) {
    logger.error(TAG, '图源配置加载失败', String(error));
  }
}
```

#### 2.4 重写数据加载方法
```typescript
private async loadComics(): Promise<void> {
  if (this.isLoading || !this.mangaSourceEngine) return;

  try {
    this.isLoading = true;
    let result: EngineResult<SearchResult> | null = null;

    switch (this.currentTab) {
      case TabType.POPULAR:
        // 使用WebView引擎搜索热门
        result = await this.mangaSourceEngine.search('', 1, 20);
        break;
        
      case TabType.LATEST:
        // 使用WebView引擎搜索最新
        result = await this.mangaSourceEngine.search('', 1, 20);
        break;
        
      case TabType.SEARCH:
        if (this.searchKeyword) {
          // 使用WebView引擎搜索
          result = await this.mangaSourceEngine.search(this.searchKeyword, 1, 20);
        }
        break;
    }

    if (result && result.success && result.data) {
      // 转换MangaInfo到ComicInfo
      const comics = this.convertMangaInfoToComicInfo(result.data.mangas);
      
      if (this.currentPage === 1) {
        this.comicList = comics;
      } else {
        this.comicList = [...this.comicList, ...comics];
      }

      this.hasMore = result.data.hasNext;
    }
  } catch (error) {
    logger.error(TAG, '加载漫画列表失败', String(error));
  } finally {
    this.isLoading = false;
  }
}

private convertMangaInfoToComicInfo(mangas: MangaInfo[]): ComicInfo[] {
  return mangas.map(manga => ({
    id: manga.id,
    title: manga.title,
    author: manga.author || '',
    coverUrl: manga.coverUrl || '',
    description: manga.description || '',
    tags: manga.tags || [],
    status: manga.status || '',
    updateTime: manga.updateTime || 0
  }));
}
```

#### 2.5 添加WebView组件到页面
```typescript
build() {
  HdsNavDestination() {
    Stack() {
      // ... 现有内容 ...
      
      // 隐藏的WebView组件
      if (this.webViewController) {
        Web({ 
          src: 'about:blank', 
          controller: this.webViewController 
        })
          .width(1)
          .height(1)
          .opacity(0)
          .visibility(Visibility.None)
          .javaScriptAccess(true)
          .domStorageAccess(true)
      }
    }
  }
  // ... titleBar配置 ...
}
```

### 📄 阶段3：图源配置格式转换

#### 3.1 当前格式（JSONPath + HTTP）
```json
{
  "metadata": {
    "id": "komiic",
    "name": "Komiic",
    "version": "1.0.0"
  },
  "api": {
    "baseUrl": "https://komiic.com"
  },
  "features": {
    "popular": {
      "url": "/api/query",
      "method": "POST",
      "parser": {
        "listPath": "$.data.comics",
        "item": {
          "id": "$.id",
          "title": "$.title"
        }
      }
    }
  }
}
```

#### 3.2 新格式（WebView Actions）
```json
{
  "metadata": {
    "id": "komiic",
    "name": "Komiic",
    "version": "2.0.0",
    "type": "webview"
  },
  "baseUrl": "https://komiic.com",
  "workflows": {
    "search": {
      "actions": [
        {
          "type": "navigate",
          "url": "{{baseUrl}}/search?q={{keyword}}"
        },
        {
          "type": "wait",
          "condition": {
            "type": "element",
            "selector": ".manga-list"
          }
        },
        {
          "type": "extract",
          "selector": ".manga-item",
          "fields": {
            "id": { "selector": "@data-id" },
            "title": { "selector": ".title" },
            "coverUrl": { "selector": "img@src" }
          }
        }
      ]
    }
  }
}
```

#### 3.3 创建配置转换工具
需要创建一个工具来帮助用户转换旧格式到新格式，或者提供配置生成器。

### 🔧 阶段4：数据库适配

#### 4.1 更新数据库Schema
```typescript
// 在DatabaseSchema中添加字段
COMIC_SOURCE: `
  CREATE TABLE IF NOT EXISTS comic_source (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    baseUrl TEXT NOT NULL,
    version TEXT NOT NULL,
    description TEXT,
    language TEXT DEFAULT 'zh-CN',
    isEnabled INTEGER DEFAULT 1,
    priority INTEGER DEFAULT 0,
    lastUpdateTime INTEGER DEFAULT 0,
    configJson TEXT,
    configType TEXT DEFAULT 'http', -- 新增：'http' 或 'webview'
    createTime INTEGER NOT NULL
  )
`
```

#### 4.2 更新导入逻辑
```typescript
async importSourceFromJSON(jsonContent: string): Promise<number> {
  const config = JSON.parse(jsonContent);
  
  // 检测配置类型
  const configType = config.metadata?.type === 'webview' ? 'webview' : 'http';
  
  // 存储时标记类型
  const sourceData = {
    name: config.metadata.name,
    baseUrl: config.baseUrl || config.api?.baseUrl,
    version: config.metadata.version,
    description: config.metadata.description,
    language: config.metadata.language || 'zh-CN',
    isEnabled: true,
    priority: 0,
    configJson: jsonContent,
    configType: configType // 新增
  };
  
  return await this.addComicSource(sourceData);
}
```

### 🧪 阶段5：测试和验证

#### 5.1 单元测试
- [ ] WebView引擎初始化测试
- [ ] 配置加载测试
- [ ] 搜索功能测试
- [ ] 数据转换测试

#### 5.2 集成测试
- [ ] 完整的图源导入流程
- [ ] 图源详情页加载
- [ ] 热门/最新/搜索功能
- [ ] 多图源切换

#### 5.3 性能测试
- [ ] WebView内存占用
- [ ] 加载速度对比
- [ ] 并发请求处理

---

## 📊 进度跟踪

| 阶段 | 状态 | 完成度 |
|------|------|--------|
| 阶段1：基础设施 | ✅ 完成 | 100% |
| 阶段2：SourceDetailPage重构 | 🔄 进行中 | 20% |
| 阶段3：配置格式转换 | ⏳ 待开始 | 0% |
| 阶段4：数据库适配 | ⏳ 待开始 | 0% |
| 阶段5：测试验证 | ⏳ 待开始 | 0% |

---

## 🚀 快速开始

### 立即可做的事情

1. **修复数据库ID问题**（已完成）
   - 修复了`addComicSource`返回正确的插入ID

2. **用户操作**
   - 删除现有图源
   - 重新导入图源（获得正确的ID）
   - 测试HTTP系统是否正常工作

3. **开发者操作**
   - 完成SourceDetailPage的WebView集成
   - 创建示例WebView格式的图源配置
   - 测试WebView系统

---

## 📚 参考资料

### 相关文件
- `Framework/WebView/MangaSourceEngine.ets` - 主引擎
- `Framework/WebView/MangaSourceActionEngine.ets` - 动作执行
- `Framework/WebView/InvisibleWebViewComponent.ets` - WebView组件
- `Framework/WebView/WebViewContainerPage.ets` - 容器管理
- `pages/WebViewConfigurableSystemTestPage.ets` - 正确的WebView使用示例
- `pages/MangaSourceTestPage.ets` - 引擎使用示例

### 文档
- `Framework/WebView/doc/README.md` - WebView系统文档
- `Framework/WebView/doc/WebView_System_Design_Analysis.md` - 系统设计分析
- `Framework/WebView/doc/JSON_Rule_Writing_Guide_v2.md` - 配置编写指南

---

## ⚠️ 注意事项

1. **向后兼容性**
   - 需要同时支持HTTP和WebView两种格式
   - 根据`configType`字段选择执行器

2. **性能考虑**
   - WebView实例需要复用，避免频繁创建销毁
   - 使用WebView池管理多个图源

3. **错误处理**
   - WebView操作可能失败（网络、反爬虫等）
   - 需要完善的重试和降级机制

4. **用户体验**
   - 首次加载可能较慢（WebView初始化）
   - 需要提供加载进度反馈
   - 缓存机制优化性能

---

## 🎉 预期效果

完成迁移后：
- ✅ 所有图源操作基于WebView
- ✅ 支持复杂的网站交互（登录、验证码、反爬虫）
- ✅ 更好的兼容性和稳定性
- ✅ 统一的配置格式和管理方式
- ✅ 更强大的数据提取能力

---

**最后更新**: 2025-11-17 22:35
**状态**: 阶段2进行中
