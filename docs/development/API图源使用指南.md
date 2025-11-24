# API图源使用指南

## ✅ 已完成的集成

### 核心引擎层
1. **MangaSourceTypes.ets** - 类型定义
   - ✅ `ActionType.API_REQUEST`
   - ✅ `APIRequestAction` 接口

2. **MangaSourceAPIEngine.ets** - API请求引擎
   - ✅ HTTP请求（GET/POST/PUT/DELETE/PATCH）
   - ✅ GraphQL查询
   - ✅ JSON数据提取
   - ✅ 变量替换

3. **MangaSourceConfigParser.ets** - 配置解析
   - ✅ 识别API类型工作流（`type: "api"`）
   - ✅ `parseAPIWorkflow()` 方法

4. **MangaSourceActionEngine.ets** - 操作执行
   - ✅ `executeAPIRequest()` 方法
   - ✅ `executeHTTPRequest()` 方法
   - ✅ 变量替换支持

5. **MangaSourceEngine.ets** - 主引擎
   - ✅ `searchManga()` 支持API
   - ✅ `getMangaDetail()` 支持API
   - ✅ `getChapterList()` 支持API
   - ✅ `getPageList()` 支持API
   - ✅ `getImageUrl()` 支持API

### UI层
6. **SourceDetailPage.ets**
   - ✅ 已通过`mangaSourceEngine.searchManga()`自动支持
   - 无需修改，API模式透明集成

7. **MangaDetailPage.ets**
   - ✅ 已通过`mangaSourceEngine.getMangaDetail()`自动支持
   - 无需修改，API模式透明集成

8. **MangaReaderPage.ets**
   - ✅ 已通过`mangaSourceEngine.getPageList()`自动支持
   - 无需修改，API模式透明集成

## 🎯 如何使用API图源

### 步骤1：准备API配置文件

创建或使用 `komiic_api.json`：

```json
{
  "metadata": {
    "name": "Komiic (API)",
    "version": "4.0.0",
    "author": "ManXia Team",
    "description": "Komiic漫画图源 - 使用GraphQL API",
    "baseUrl": "https://komiic.com",
    "language": "zh-TW"
  },
  
  "settings": {
    "enableJavaScript": true,
    "enableImages": false,
    "enableCookies": true,
    "bypassCloudflare": false,
    "userAgent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"
  },
  
  "workflows": {
    "search": {
      "type": "api",
      "method": "POST",
      "url": "https://komiic.com/api/query",
      "headers": {
        "Content-Type": "application/json",
        "Accept": "application/json"
      },
      "body": {
        "query": "query hotComics($pagination: Pagination!) { comics: hotComics(pagination: $pagination) { id title description status imageUrl authors { id name } categories { id name } } }",
        "variables": {
          "pagination": {
            "limit": 30,
            "offset": "{{(page - 1) * 30}}",
            "orderBy": "MONTH_VIEWS"
          }
        }
      },
      "extract": {
        "path": "data.comics",
        "fields": {
          "id": "id",
          "title": "title",
          "cover": "imageUrl",
          "author": "authors[0].name",
          "description": "description",
          "status": "status",
          "genres": "categories[*].name"
        }
      }
    }
  }
}
```

### 步骤2：导入图源到数据库

使用现有的图源导入功能，将`komiic_api.json`导入到数据库。

### 步骤3：使用图源

在SourceDetailPage中选择"Komiic (API)"图源，系统会自动：

1. 解析配置，识别为API模式
2. 构建GraphQL请求
3. 发送HTTP POST请求到API端点
4. 解析JSON响应
5. 提取漫画数据
6. 显示在UI中

**完全透明，无需任何额外代码！**

## 📊 API配置格式说明

### 工作流配置

```json
{
  "type": "api",           // 必需：标识为API模式
  "method": "POST",        // HTTP方法
  "url": "...",           // API端点URL
  "headers": {...},       // 请求头
  "body": {...},          // 请求体（支持变量）
  "extract": {...}        // 数据提取配置
}
```

### 变量替换

在`url`和`body`中可以使用变量：

```json
{
  "url": "https://api.example.com/manga?page={{page}}",
  "body": {
    "variables": {
      "offset": "{{(page - 1) * 30}}"
    }
  }
}
```

可用变量：
- `{{page}}` - 当前页码
- `{{keyword}}` - 搜索关键词
- `{{mangaId}}` - 漫画ID
- `{{chapterId}}` - 章节ID

### 数据提取配置

```json
{
  "extract": {
    "path": "data.comics",        // JSON路径
    "fields": {
      "id": "id",                  // 简单字段
      "title": "title",
      "cover": "imageUrl",
      "author": "authors[0].name", // 数组索引
      "genres": "categories[*].name" // 数组聚合
    }
  }
}
```

## 🔄 执行流程

### 搜索漫画

```
用户点击搜索
  ↓
SourceDetailPage.loadComicsWithWebView()
  ↓
MangaSourceEngine.searchManga(keyword, page)
  ↓
ConfigParser.buildSearchActions() → 识别API模式
  ↓
ActionEngine.executeAPIRequest()
  ↓
APIEngine.request() → 发送HTTP请求
  ↓
APIEngine.extractFromJSON() → 提取数据
  ↓
transformToMangaInfo() → 转换为MangaInfo
  ↓
convertMangaInfoToComicInfo() → 转换为ComicInfo
  ↓
显示在UI中
```

### 获取漫画详情

```
用户点击漫画卡片
  ↓
MangaDetailPage.loadMangaDataWithWebView()
  ↓
MangaSourceEngine.getMangaDetail(mangaId)
  ↓
执行API请求 → 提取数据 → 显示详情
```

### 阅读章节

```
用户点击章节
  ↓
MangaReaderPage.loadChapterPages()
  ↓
MangaSourceEngine.getPageList(chapterId)
  ↓
执行API请求 → 获取图片列表 → 显示图片
```

## 🎨 支持的API类型

### 1. REST API
```json
{
  "type": "api",
  "method": "GET",
  "url": "https://api.example.com/manga/{{mangaId}}"
}
```

### 2. GraphQL
```json
{
  "type": "api",
  "method": "POST",
  "url": "https://api.example.com/graphql",
  "body": {
    "query": "query { manga(id: \"{{mangaId}}\") { title } }"
  }
}
```

### 3. 带认证的API
```json
{
  "type": "api",
  "method": "GET",
  "url": "https://api.example.com/manga",
  "headers": {
    "Authorization": "Bearer YOUR_TOKEN",
    "X-API-Key": "YOUR_API_KEY"
  }
}
```

## 🐛 调试技巧

### 查看日志

搜索以下日志标签：
- `[MangaSourceConfigParser]` - 配置解析
- `[MangaSourceActionEngine]` - 操作执行
- `[MangaSourceAPIEngine]` - API请求
- `[MangaSourceEngine]` - 主引擎

### 关键日志

```
ℹ️ 信息 [MangaSourceConfigParser] 工作流 search 使用API模式
ℹ️ 信息 [MangaSourceActionEngine] 执行API请求: POST https://...
🔍 调试 [MangaSourceAPIEngine] API响应状态: 200
ℹ️ 信息 [MangaSourceActionEngine] API数据提取完成
ℹ️ 信息 [MangaSourceEngine] 提取到 30 条漫画数据
```

## 📝 常见问题

### Q: API请求失败怎么办？
A: 检查：
1. URL是否正确
2. 请求头是否完整
3. 网络连接是否正常
4. API是否需要认证

### Q: 数据提取不到怎么办？
A: 检查：
1. `extract.path` 是否正确
2. `fields` 映射是否匹配API响应结构
3. 查看日志中的API响应内容

### Q: 如何支持分页？
A: 使用`{{page}}`变量：
```json
{
  "variables": {
    "pagination": {
      "offset": "{{(page - 1) * 30}}",
      "limit": 30
    }
  }
}
```

### Q: 如何处理嵌套数据？
A: 使用点号路径：
```json
{
  "path": "data.result.items",
  "fields": {
    "author": "author.name",
    "tags": "metadata.tags[*].name"
  }
}
```

## 🚀 下一步

现在你可以：
1. 导入`komiic_api.json`测试Komiic API图源
2. 创建其他网站的API图源配置
3. 享受更快、更稳定的漫画浏览体验！

API模式相比WebView模式的优势：
- ⚡ **速度快** - 无需渲染页面
- 🎯 **数据准确** - 直接从API获取
- 💪 **稳定可靠** - 不受页面变化影响
- 🔧 **易于维护** - API接口相对稳定
