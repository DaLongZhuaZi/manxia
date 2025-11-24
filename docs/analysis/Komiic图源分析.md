# Komiic图源分析报告

## 问题根源

### WebView方案失败的原因

1. **Komiic是Vue 3单页应用**
   - HTML只是空壳，不包含实际数据
   - 所有内容通过JavaScript动态渲染
   - 图片元素在API数据加载后才创建

2. **为什么找不到img元素**
   ```
   imgCount: 0  // WebView中没有img元素
   ```
   - Vue组件还未渲染完成
   - 或者检测到WebView环境拒绝渲染
   - 数据通过API异步加载，不在HTML中

## Kotlin图源的正确实现

### 核心架构

```kotlin
class Komiic : HttpSource() {
    override val baseUrl = "https://komiic.com"
    private val apiUrl = "$baseUrl/api/query"
    
    // 使用GraphQL API，不解析HTML
    override fun popularMangaRequest(page: Int): Request {
        val query = """
            query hotComics($pagination: Pagination!) {
                comics: hotComics(pagination: $pagination) {
                    id
                    title
                    imageUrl  // 封面URL直接在API中
                    authors { name }
                    categories { name }
                }
            }
        """
        return POST(apiUrl, headers, buildRequestBody(query, variables))
    }
}
```

### GraphQL查询示例

#### 1. 获取热门漫画列表
```graphql
query hotComics($pagination: Pagination!) {
  comics: hotComics(pagination: $pagination) {
    id
    title
    description
    status
    imageUrl          # 封面URL
    authors {
      id
      name
    }
    categories {
      id
      name
    }
  }
}
```

**变量**:
```json
{
  "pagination": {
    "limit": 30,
    "offset": 0,
    "orderBy": "MONTH_VIEWS"
  }
}
```

#### 2. 获取漫画详情
```graphql
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
```

#### 3. 获取章节图片列表
```graphql
query imagesByChapterId($chapterId: ID!) {
  reachedImageLimit
  imagesByChapterId(chapterId: $chapterId) {
    kid
  }
}
```

#### 4. 图片URL
```
https://komiic.com/api/image/{kid}
```

### API响应示例

```json
{
  "data": {
    "comics": [
      {
        "id": "466",
        "title": "膽大黨 (超自然武裝噹噠噹)",
        "imageUrl": "https://public.komiic.com/comics/0fd0b50c31b694d260ca47a846bfb809/cover.jpg",
        "authors": [{"name": "作者名"}],
        "categories": [{"name": "冒險"}],
        "status": "ONGOING"
      }
    ]
  }
}
```

## 解决方案对比

### ❌ WebView方案（失败）
```
导航 → 等待渲染 → 查找img元素 → 提取src
问题：找不到img元素（imgCount: 0）
```

### ✅ API方案（推荐）
```
POST请求 → GraphQL查询 → JSON解析 → 直接获取imageUrl
优势：稳定、快速、数据完整
```

## 实现建议

### 方案1：纯API实现（推荐）
- 不使用WebView
- 直接HTTP请求GraphQL API
- 解析JSON响应
- 需要实现API调用引擎

### 方案2：混合方案
- 使用WebView获取Cookie/Token
- 然后用API获取数据
- 适合需要登录的场景

### 方案3：继续WebView（不推荐）
- 需要等待更长时间（10秒+）
- 可能需要执行JavaScript触发渲染
- 不稳定，容易被检测

## 关键技术点

### 1. Token刷新机制
```kotlin
private fun refreshToken(chain: Interceptor.Chain) {
    val cookie = client.cookieJar.loadForRequest(url)
        .find { it.name == "komiic-access-token" }
    // 检查token过期时间
    // 自动刷新token
}
```

### 2. 请求构建
```kotlin
private fun buildRequestBody(query: String, variables: JsonObject): RequestBody {
    val body = buildJsonObject {
        put("query", query)
        put("variables", variables)
    }
    return Json.encodeToString(body).toByteArray()
        .toRequestBody("application/json".toMediaType())
}
```

### 3. 响应解析
```kotlin
override fun popularMangaParse(response: Response): MangasPage {
    val data = response.parseAs<ResponseDto>().getData()
    val entries = data.comics.map { it.toSManga() }
    return MangasPage(entries, hasNextPage = entries.size == PAGE_SIZE)
}
```

## 结论

**Komiic必须使用API方案，WebView方案无法工作。**

原因：
1. Vue 3单页应用，HTML不包含数据
2. 图片元素动态渲染，WebView无法捕获
3. 官方提供了完整的GraphQL API
4. Kotlin图源已验证API方案可行

建议：
- 实现GraphQL API调用引擎
- 或者使用HTTP客户端直接调用API
- 放弃WebView HTML解析方案
