# API图源实现方案

## 📋 总体架构

```
JSON配置 → 配置解析器 → API引擎 → 数据提取 → UI展示
          ↓
      识别API类型
          ↓
   MangaSourceAPIEngine (新)
          ↓
      HTTP/GraphQL请求
          ↓
      JSON数据提取
```

## 🎯 已完成的工作

### 1. ✅ 类型定义扩展 (`MangaSourceTypes.ets`)
- 添加 `ActionType.API_REQUEST` 和 `ActionType.HTTP_REQUEST`
- 定义 `APIRequestAction` 接口
- 定义 `HTTPRequestAction` 接口

### 2. ✅ API引擎创建 (`MangaSourceAPIEngine.ets`)
- HTTP请求支持（GET/POST/PUT/DELETE/PATCH）
- GraphQL查询支持
- JSON数据提取（支持路径和字段映射）
- 变量替换功能

### 3. ✅ API图源配置示例 (`komiic_api.json`)
- GraphQL查询定义
- 字段映射配置
- 完整的工作流定义

## 🔧 需要完成的工作

### 步骤1：增强配置解析器

**文件**: `MangaSourceConfigParser.ets`

**修改点**:
```typescript
// 1. 识别API类型工作流
private parseWorkflow(workflowData: ESObject): Action[] {
  // 检查是否是API类型
  if (workflowData['type'] === 'api') {
    return this.parseAPIWorkflow(workflowData);
  }
  
  // 原有的WebView工作流解析
  return this.parseWebViewWorkflow(workflowData);
}

// 2. 解析API工作流
private parseAPIWorkflow(workflowData: ESObject): Action[] {
  const action: APIRequestAction = {
    type: ActionType.API_REQUEST,
    method: workflowData['method'] as string,
    url: workflowData['url'] as string,
    headers: workflowData['headers'] as ESObject,
    body: workflowData['body'] as ESObject,
    extract: workflowData['extract'] as ESObject,
    description: workflowData['description'] as string
  };
  
  return [action];
}
```

### 步骤2：扩展ActionEngine支持API

**文件**: `MangaSourceActionEngine.ets`

**修改点**:
```typescript
import { MangaSourceAPIEngine } from './MangaSourceAPIEngine';

class MangaSourceActionEngine {
  private apiEngine: MangaSourceAPIEngine;
  
  constructor(...) {
    this.apiEngine = new MangaSourceAPIEngine();
  }
  
  async executeAction(action: Action, context: ActionContext): Promise<ActionResult> {
    switch (action.type) {
      case ActionType.API_REQUEST:
        return await this.executeAPIRequest(action as APIRequestAction, context);
      case ActionType.HTTP_REQUEST:
        return await this.executeHTTPRequest(action as HTTPRequestAction, context);
      // ... 其他类型
    }
  }
  
  private async executeAPIRequest(
    action: APIRequestAction, 
    context: ActionContext
  ): Promise<ActionResult> {
    // 替换URL中的变量
    const url = this.replaceVariables(action.url, context.variables);
    
    // 替换body中的变量
    const body = this.replaceObjectVariables(action.body, context.variables);
    
    // 执行请求
    const response = await this.apiEngine.request({
      method: action.method,
      url: url,
      headers: action.headers,
      body: body
    });
    
    // 提取数据
    if (action.extract) {
      const extracted = this.apiEngine.extractFromJSON(
        response.data as ESObject,
        action.extract
      );
      
      return {
        success: true,
        data: extracted,
        message: 'API请求成功'
      };
    }
    
    return {
      success: true,
      data: response.data,
      message: 'API请求成功'
    };
  }
}
```

### 步骤3：更新MangaSourceEngine

**文件**: `MangaSourceEngine.ets`

**修改点**:
```typescript
// 检测图源类型
private isAPISource(config: MangaSourceConfig): boolean {
  // 检查是否有API配置
  const searchWorkflow = config.workflows['search'];
  if (Array.isArray(searchWorkflow) && searchWorkflow.length > 0) {
    const firstAction = searchWorkflow[0] as ESObject;
    return firstAction['type'] === 'api' || firstAction['type'] === 'http';
  }
  return false;
}

// 搜索漫画时判断使用哪种引擎
async searchManga(keyword: string, page: number): Promise<EngineResult<SearchResult>> {
  if (this.isAPISource(this.config!)) {
    logger.info(TAG, '使用API模式搜索');
    // API模式：直接执行API请求
  } else {
    logger.info(TAG, '使用WebView模式搜索');
    // WebView模式：原有逻辑
  }
}
```

### 步骤4：更新SourceDetailPage

**文件**: `SourceDetailPage.ets`

**修改点**:
```typescript
private async loadMangaListWithAPI(): Promise<void> {
  try {
    logger.info(TAG, '使用API模式加载漫画列表');
    
    // 执行搜索
    const result = await this.mangaSourceEngine!.searchManga('', this.currentPage);
    
    if (result.success && result.data) {
      const mangas = result.data.mangas;
      logger.info(TAG, `API获取到 ${mangas.length} 条漫画`);
      
      // 转换并显示
      const comics = this.convertMangaInfoToComicInfo(mangas);
      this.comicList = [...this.comicList, ...comics];
      this.hasMore = result.data.hasNext;
    }
  } catch (error) {
    logger.error(TAG, `API加载失败: ${error}`);
    this.showError('加载失败');
  }
}

private async loadMangaList(): Promise<void> {
  // 判断图源类型
  if (this.isAPISource()) {
    await this.loadMangaListWithAPI();
  } else {
    await this.loadMangaListWithWebView();
  }
}
```

### 步骤5：更新MangaDetailPage

**文件**: `MangaDetailPage.ets`

**修改点**:
```typescript
private async loadMangaDetailWithAPI(mangaId: string): Promise<void> {
  try {
    logger.info(TAG, `使用API模式加载漫画详情: ${mangaId}`);
    
    // 创建API引擎
    const apiEngine = new MangaSourceAPIEngine();
    
    // 构建GraphQL查询
    const query = `
      query chapterByComicId($comicId: ID!) {
        comicById(comicId: $comicId) {
          id
          title
          description
          status
          imageUrl
          authors { name }
          categories { name }
        }
        chaptersByComicId(comicId: $comicId) {
          id
          serial
          type
          size
          dateCreated
        }
      }
    `;
    
    // 执行查询
    const response = await apiEngine.graphql(
      'https://komiic.com/api/query',
      query,
      { comicId: mangaId }
    );
    
    // 提取数据
    const data = response['data'] as ESObject;
    const comic = data['comicById'] as ESObject;
    const chapters = data['chaptersByComicId'] as ESObject[];
    
    // 更新UI
    this.mangaTitle = comic['title'] as string;
    this.mangaCover = comic['imageUrl'] as string;
    this.mangaDescription = comic['description'] as string;
    // ... 更新其他字段
    
  } catch (error) {
    logger.error(TAG, `API加载详情失败: ${error}`);
  }
}
```

### 步骤6：更新MangaReaderPage

**文件**: `MangaReaderPage.ets`

**修改点**:
```typescript
private async loadChapterPagesWithAPI(chapterId: string): Promise<void> {
  try {
    logger.info(TAG, `使用API模式加载章节图片: ${chapterId}`);
    
    const apiEngine = new MangaSourceAPIEngine();
    
    // GraphQL查询
    const query = `
      query imagesByChapterId($chapterId: ID!) {
        reachedImageLimit
        imagesByChapterId(chapterId: $chapterId) {
          kid
        }
      }
    `;
    
    const response = await apiEngine.graphql(
      'https://komiic.com/api/query',
      query,
      { chapterId: chapterId }
    );
    
    const data = response['data'] as ESObject;
    const images = data['imagesByChapterId'] as ESObject[];
    
    // 构建图片URL列表
    this.pageUrls = images.map((img: ESObject) => {
      const kid = img['kid'] as string;
      return `https://komiic.com/api/image/${kid}`;
    });
    
    logger.info(TAG, `获取到 ${this.pageUrls.length} 张图片`);
    
  } catch (error) {
    logger.error(TAG, `API加载图片失败: ${error}`);
  }
}
```

## 🎨 配置文件格式

### API模式配置示例

```json
{
  "metadata": {
    "name": "Komiic (API)",
    "version": "4.0.0"
  },
  
  "workflows": {
    "search": {
      "type": "api",
      "method": "POST",
      "url": "https://komiic.com/api/query",
      "headers": {
        "Content-Type": "application/json"
      },
      "body": {
        "query": "query hotComics($pagination: Pagination!) { ... }",
        "variables": {
          "pagination": {
            "limit": 30,
            "offset": "{{(page - 1) * 30}}"
          }
        }
      },
      "extract": {
        "path": "data.comics",
        "fields": {
          "id": "id",
          "title": "title",
          "cover": "imageUrl",
          "author": "authors[0].name"
        }
      }
    }
  }
}
```

### WebView模式配置（现有）

```json
{
  "workflows": {
    "search": [
      {
        "type": "navigate",
        "url": "{{baseUrl}}"
      },
      {
        "type": "wait",
        "duration": 5000
      },
      {
        "type": "extract",
        "selector": ".ComicCard",
        "fields": {
          "id": "@href",
          "title": ".text-subtitle-2::text",
          "cover": ".ComicCard__image img::attr(src)"
        }
      }
    ]
  }
}
```

## 🔄 执行流程对比

### WebView模式
```
导航 → 等待渲染 → 执行JS → 提取DOM → 解析数据
```

### API模式
```
构建请求 → 发送HTTP → 解析JSON → 提取字段
```

## 📊 优势对比

| 特性 | WebView模式 | API模式 |
|------|------------|---------|
| 速度 | 慢（需要渲染） | 快（直接请求） |
| 稳定性 | 低（依赖渲染） | 高（直接数据） |
| 资源占用 | 高 | 低 |
| 数据完整性 | 可能不完整 | 完整 |
| 维护成本 | 高（页面变化） | 低（API稳定） |

## 🎯 实施优先级

1. **高优先级**（核心功能）
   - ✅ API引擎创建
   - ⏳ 配置解析器增强
   - ⏳ ActionEngine扩展

2. **中优先级**（UI集成）
   - ⏳ SourceDetailPage更新
   - ⏳ MangaDetailPage更新

3. **低优先级**（完善功能）
   - ⏳ MangaReaderPage更新
   - ⏳ 错误处理优化
   - ⏳ 缓存机制

## 📝 测试计划

### 单元测试
- API引擎请求功能
- JSON数据提取功能
- 变量替换功能

### 集成测试
- 完整搜索流程
- 漫画详情加载
- 章节图片加载

### 用户测试
- UI响应速度
- 数据准确性
- 错误提示

## 🚀 下一步行动

1. 修改 `MangaSourceConfigParser.ets` 识别API工作流
2. 扩展 `MangaSourceActionEngine.ets` 支持API请求
3. 更新 `SourceDetailPage.ets` 支持API模式
4. 测试Komiic API图源
5. 根据测试结果优化

## 💡 注意事项

1. **向后兼容**：保持对现有WebView图源的支持
2. **错误处理**：API请求失败时的降级策略
3. **性能优化**：请求合并、数据缓存
4. **安全性**：API密钥管理、请求签名
