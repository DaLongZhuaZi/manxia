# Komiic图源快速参考

## 基本信息

- **图源ID**: `komiic`
- **版本**: 5.0.0
- **基础URL**: https://komiic.com
- **API端点**: https://komiic.com/api/query
- **API类型**: GraphQL
- **语言**: 繁体中文 (zh-TW)

## GraphQL查询速查

### 1. 热门漫画
```graphql
query hotComics($pagination: Pagination!) {
  comics: hotComics(pagination: $pagination) {
    id title description status imageUrl
    authors { id name }
    categories { id name }
    monthViews
  }
}
```
**变量**:
```json
{
  "pagination": {
    "limit": 30,
    "offset": 0,
    "orderBy": "MONTH_VIEWS",
    "asc": false
  }
}
```

### 2. 最新更新
```graphql
query recentUpdate($pagination: Pagination!) {
  recentUpdate(pagination: $pagination) {
    id title description status imageUrl
    authors { id name }
    categories { id name }
    dateUpdated
  }
}
```
**变量**:
```json
{
  "pagination": {
    "limit": 30,
    "offset": 0,
    "orderBy": "DATE_UPDATED",
    "asc": false
  }
}
```

### 3. 搜索
```graphql
query searchComicAndAuthorQuery($keyword: String!) {
  searchComicsAndAuthors(keyword: $keyword) {
    comics {
      id title description status imageUrl
      authors { id name }
      categories { id name }
    }
  }
  allCategory { id name }
}
```
**变量**:
```json
{
  "keyword": "搜索关键词"
}
```

### 4. 按ID查询
```graphql
query comicByIds($comicIds: [ID]!) {
  comics: comicByIds(comicIds: $comicIds) {
    id title description status imageUrl
    authors { id name }
    categories { id name }
  }
}
```
**变量**:
```json
{
  "comicIds": ["comic_id_here"]
}
```

### 5. 分类筛选
```graphql
query comicByCategories($categoryId: [ID!]!, $pagination: Pagination!) {
  comics: comicByCategories(categoryId: $categoryId, pagination: $pagination) {
    id title description status imageUrl
    authors { id name }
    categories { id name }
  }
  allCategory { id name }
}
```
**变量**:
```json
{
  "categoryId": ["category_id"],
  "pagination": {
    "limit": 30,
    "offset": 0,
    "orderBy": "DATE_UPDATED",
    "asc": false,
    "status": "",
    "sexyLevel": null
  }
}
```

### 6. 漫画详情和章节
```graphql
query chapterByComicId($comicId: ID!) {
  comicById(comicId: $comicId) {
    id title description status imageUrl
    authors { id name }
    categories { id name }
  }
  chaptersByComicId(comicId: $comicId) {
    id serial type size dateCreated
  }
}
```
**变量**:
```json
{
  "comicId": "comic_id_here"
}
```

### 7. 图片列表
```graphql
query imagesByChapterId($chapterId: ID!) {
  reachedImageLimit
  imagesByChapterId(chapterId: $chapterId) {
    kid
  }
}
```
**变量**:
```json
{
  "chapterId": "chapter_id_here"
}
```

## 数据模型

### Comic (漫画)
```typescript
{
  id: string;              // 漫画ID
  title: string;           // 标题
  description: string;     // 描述
  status: string;          // 状态: ONGOING, END
  imageUrl: string;        // 封面URL
  authors: Author[];       // 作者列表
  categories: Category[];  // 分类列表
  monthViews?: number;     // 月浏览量（仅热门）
  dateUpdated?: string;    // 更新时间（仅最新）
}
```

### Chapter (章节)
```typescript
{
  id: string;          // 章节ID
  serial: string;      // 序号（如 "1", "2.5"）
  type: string;        // 类型: "chapter" (連載) 或 "book" (單行本)
  size: number;        // 页数
  dateCreated: string; // 创建时间 (ISO 8601)
}
```

### Image (图片)
```typescript
{
  kid: string;  // 图片ID
}
```

**图片URL格式**: `https://komiic.com/api/image/{kid}`

## 认证

### JWT Token
- **Cookie名称**: `komiic-access-token`
- **格式**: 标准JWT (三段式Base64)
- **刷新端点**: `POST /auth/refresh`
- **刷新时机**: 过期前1小时

### Token结构
```
{header}.{payload}.{signature}
```

**Payload示例**:
```json
{
  "exp": 1700000000,  // 过期时间（Unix时间戳，秒）
  "iat": 1699900000,  // 签发时间
  "sub": "user_id"    // 用户ID
}
```

### 登录流程
1. 打开 `https://komiic.com/login`
2. 用户输入账号密码
3. 登录成功后自动设置 `komiic-access-token` Cookie
4. 提取Cookie保存到数据库

## 用户设置

### 章节过滤 (chapterFilter)
- **类型**: list
- **默认值**: "all"
- **选项**:
  - `all`: 同時顯示卷和章節
  - `chapter`: 僅顯示章節
  - `book`: 僅顯示卷

### API限制检查 (checkApiLimit)
- **类型**: boolean
- **默认值**: true
- **说明**: 检查 `reachedImageLimit` 字段，达到限制时抛出错误

## 分页参数

### Pagination对象
```typescript
{
  offset: number;        // 偏移量（从0开始）
  limit: number;         // 每页数量（默认30）
  orderBy: OrderBy;      // 排序字段
  asc: boolean;          // 是否升序（默认false）
  status?: string;       // 状态筛选
  sexyLevel?: number;    // 色情等级筛选
}
```

### OrderBy枚举
```typescript
enum OrderBy {
  DATE_UPDATED,        // 更新时间
  DATE_CREATED,        // 创建时间
  VIEWS,              // 浏览量
  MONTH_VIEWS,        // 月浏览量
  ID,                 // ID
  COMIC_DATE_UPDATED, // 漫画更新时间
  FAVORITE_ADDED,     // 收藏添加时间
  FAVORITE_COUNT,     // 收藏数量
}
```

## 状态码

### 漫画状态
- `ONGOING`: 连载中
- `END`: 已完结
- 其他: 未知

### 章节类型
- `chapter`: 連載（话）
- `book`: 單行本（卷）

## 错误处理

### 图片限制
```json
{
  "data": {
    "reachedImageLimit": true,
    "imagesByChapterId": []
  }
}
```
**错误消息**: "今日圖片讀取次數已達上限，請登录或明天再來！"

### Token过期
**HTTP状态码**: 401
**处理**: 自动调用 `/auth/refresh` 刷新Token

### 网络错误
**重试策略**: 指数退避
- 最大重试次数: 3
- 基础延迟: 1000ms
- 最大延迟: 10000ms

## 常用URL

### 网站URL
- 首页: `https://komiic.com/`
- 登录: `https://komiic.com/login`
- 漫画详情: `https://komiic.com/comic/{id}`
- 章节阅读: `https://komiic.com/comic/{comicId}/chapter/{chapterId}`
- 章节图片: `https://komiic.com/comic/{comicId}/chapter/{chapterId}/images/all`

### API URL
- GraphQL端点: `https://komiic.com/api/query`
- Token刷新: `https://komiic.com/auth/refresh`
- 图片: `https://komiic.com/api/image/{kid}`

## 请求示例

### cURL示例
```bash
# 热门漫画
curl -X POST https://komiic.com/api/query \
  -H "Content-Type: application/json" \
  -H "Cookie: komiic-access-token=YOUR_TOKEN" \
  -d '{
    "query": "query hotComics($pagination: Pagination!) { comics: hotComics(pagination: $pagination) { id title imageUrl } }",
    "variables": {
      "pagination": {
        "limit": 30,
        "offset": 0,
        "orderBy": "MONTH_VIEWS",
        "asc": false
      }
    }
  }'

# 刷新Token
curl -X POST https://komiic.com/auth/refresh \
  -H "Cookie: komiic-access-token=YOUR_TOKEN"
```

### JavaScript示例
```javascript
// 执行GraphQL查询
async function queryKomiic(query, variables) {
  const response = await fetch('https://komiic.com/api/query', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    credentials: 'include', // 包含Cookie
    body: JSON.stringify({ query, variables })
  });
  
  const result = await response.json();
  if (result.errors) {
    throw new Error(result.errors[0].message);
  }
  
  return result.data;
}

// 刷新Token
async function refreshToken() {
  const response = await fetch('https://komiic.com/auth/refresh', {
    method: 'POST',
    credentials: 'include'
  });
  
  return response.ok;
}
```

## 调试技巧

### 1. 检查Token有效性
```typescript
function isTokenExpired(token: string): boolean {
  const parts = token.split('.');
  if (parts.length !== 3) return true;
  
  const payload = JSON.parse(atob(parts[1]));
  const now = Date.now() / 1000;
  
  return now >= payload.exp;
}
```

### 2. 解析JWT Payload
```typescript
function parseJwtPayload(token: string): any {
  const parts = token.split('.');
  const payload = atob(parts[1]);
  return JSON.parse(payload);
}
```

### 3. 格式化章节标题
```typescript
function formatChapterTitle(chapter: Chapter): string {
  const suffix = chapter.type === 'chapter' ? '話' : '卷';
  return `${chapter.serial}${suffix}（${chapter.size}P）`;
}
```

### 4. 检查图片限制
```typescript
async function checkImageLimit(chapterId: string): Promise<boolean> {
  const result = await queryKomiic(
    'query imagesByChapterId($chapterId: ID!) { reachedImageLimit }',
    { chapterId }
  );
  
  return result.reachedImageLimit;
}
```

## 常见问题

### Q: 为什么搜索没有分页？
A: Komiic的 `searchComicsAndAuthors` API不支持分页参数，返回所有匹配结果。

### Q: 章节如何排序？
A: 先按type降序（book > chapter），再按serial降序（数字大的在前）。

### Q: 图片限制如何突破？
A: 需要登录账号。未登录用户每天有图片请求限制。

### Q: Token多久过期？
A: 通常24小时，但会在过期前1小时自动刷新。

### Q: 如何获取所有分类？
A: 在任何查询中添加 `allCategory { id name }` 字段。

## 性能优化建议

1. **缓存Token**: 避免频繁刷新
2. **批量查询**: 使用 `comicByIds` 一次查询多个漫画
3. **分页加载**: 使用offset分页，避免一次加载过多数据
4. **图片预加载**: 提前加载下一页图片
5. **错误重试**: 使用指数退避策略

## 更新日志

### 5.0.0 (2024-11-21)
- 基于Kotlin版本完整移植
- 添加JWT Token认证
- 添加Token自动刷新
- 添加章节过滤
- 添加图片限制检查
- 添加用户设置
- 优化GraphQL查询
- 增强错误处理

### 4.0.0
- 基础GraphQL支持
- 基本工作流

---

**最后更新**: 2024-11-21
**维护者**: ManXia Team
