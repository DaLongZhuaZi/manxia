# Komiic 图源配置迁移说明

## 📋 配置版本对比

### 旧版本（HTTP格式）- `komiic.json`
- **类型**: HTTP + JSONPath
- **执行器**: SourceExecutor
- **特点**: 
  - ✅ 简单直接
  - ✅ 性能好
  - ❌ 不支持复杂交互
  - ❌ 无法处理动态内容

### 新版本（WebView格式）- `komiic_webview.json`
- **类型**: WebView + JavaScript
- **执行器**: MangaSourceEngine
- **特点**:
  - ✅ 支持JavaScript执行
  - ✅ 可以调用GraphQL API
  - ✅ 支持复杂交互
  - ❌ 性能略低
  - ❌ 内存占用更大

---

## 🔄 配置结构对比

### HTTP格式（旧）
```json
{
  "metadata": {
    "type": "http" // 或不指定
  },
  "api": {
    "type": "graphql",
    "endpoint": "..."
  },
  "features": {
    "popular": {
      "method": "POST",
      "url": "...",
      "body": {...},
      "parser": {
        "listPath": "$.data.recentUpdate",
        "item": {...}
      }
    }
  }
}
```

### WebView格式（新）
```json
{
  "metadata": {
    "type": "webview" // 必须指定
  },
  "baseUrl": "...",
  "workflows": {
    "search": {
      "actions": [
        {
          "type": "navigate",
          "url": "..."
        },
        {
          "type": "script",
          "code": "...",
          "resultVariable": "..."
        },
        {
          "type": "extract",
          "source": "variable",
          "variable": "...",
          "fields": {...}
        }
      ]
    }
  }
}
```

---

## 🎯 Komiic 的特殊性

### API 特点
Komiic 使用 **GraphQL API**，这意味着：

1. **单一端点**: 所有请求都发送到 `/api/query`
2. **POST 方法**: 使用 POST 请求，body 包含 query 和 variables
3. **结构化查询**: 需要编写 GraphQL 查询语句
4. **类型安全**: 返回的数据结构是固定的

### 为什么需要 WebView？

虽然 Komiic 是 GraphQL API，理论上可以用 HTTP 方式调用，但使用 WebView 有以下优势：

1. **更真实的环境**: 模拟真实浏览器行为
2. **处理认证**: 可以处理 Cookie、Token 等
3. **绕过限制**: 某些网站可能检测非浏览器请求
4. **统一架构**: 与其他需要 WebView 的图源保持一致

---

## 📝 WebView 配置详解

### 1. 搜索功能 (search)

```json
{
  "type": "script",
  "code": "async function searchKomiic(keyword) { 
    const query = `query searchComicByKeyword($keyword: String!, $pagination: Pagination!) { 
      searchComicByKeyword(keyword: $keyword, pagination: $pagination) { 
        id title authors { name } imageUrl 
      } 
    }`;
    const response = await fetch('https://komiic.com/api/query', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        operationName: 'searchComicByKeyword',
        query: query,
        variables: { 
          keyword: keyword, 
          pagination: { limit: 20, offset: 0 } 
        }
      })
    });
    const data = await response.json();
    return data.data.searchComicByKeyword;
  } 
  return await searchKomiic('{{keyword}}');",
  "resultVariable": "searchResults"
}
```

**说明**:
- 在 WebView 中执行 JavaScript
- 使用 `fetch` API 调用 GraphQL
- 返回结果存储到 `searchResults` 变量
- 后续的 `extract` 操作从该变量提取数据

### 2. 数据提取 (extract)

```json
{
  "type": "extract",
  "source": "variable",
  "variable": "searchResults",
  "fields": {
    "id": "$.id",
    "title": "$.title",
    "author": "$.authors[0].name",
    "cover": "$.imageUrl",
    "url": "{{baseUrl}}/comic/{{id}}"
  }
}
```

**说明**:
- `source: "variable"` 表示从 JavaScript 变量提取
- 使用 JSONPath 语法提取字段
- 支持模板变量 `{{baseUrl}}` 和 `{{id}}`

---

## 🔧 配置转换步骤

### 步骤 1: 更新 metadata

```json
// 旧
"metadata": {
  "id": "komiic",
  "version": "1.0.0"
}

// 新
"metadata": {
  "id": "komiic",
  "version": "2.0.0",
  "type": "webview"  // ← 关键：标记为 WebView 类型
}
```

### 步骤 2: 移除 api 配置

```json
// 旧 - 删除这部分
"api": {
  "type": "graphql",
  "endpoint": "https://komiic.com/api/query"
}
```

### 步骤 3: 转换 features 为 workflows

```json
// 旧
"features": {
  "popular": {
    "method": "POST",
    "url": "...",
    "body": {...},
    "parser": {...}
  }
}

// 新
"workflows": {
  "popular": {
    "actions": [
      { "type": "navigate", "url": "..." },
      { "type": "script", "code": "...", "resultVariable": "..." },
      { "type": "extract", "source": "variable", "variable": "...", "fields": {...} }
    ]
  }
}
```

### 步骤 4: 将 GraphQL 查询转为 JavaScript

```javascript
// 旧的 body 配置
{
  "operationName": "recentUpdate",
  "query": "query recentUpdate($pagination: Pagination!) { ... }",
  "variables": { "pagination": { "limit": 20 } }
}

// 转为 JavaScript
async function getPopular() {
  const query = `query recentUpdate($pagination: Pagination!) { ... }`;
  const response = await fetch('https://komiic.com/api/query', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      operationName: 'recentUpdate',
      query: query,
      variables: { pagination: { limit: 20, offset: 0 } }
    })
  });
  const data = await response.json();
  return data.data.recentUpdate;
}
return await getPopular();
```

---

## 🧪 测试步骤

### 1. 备份旧配置
```bash
cp sources/komiic.json sources/komiic_http_backup.json
```

### 2. 导入新配置
1. 删除旧的 Komiic 图源
2. 导入 `komiic_webview.json`
3. 查看日志确认类型检测

### 3. 验证功能
- [ ] 搜索功能
- [ ] 热门列表
- [ ] 最新更新
- [ ] 漫画详情
- [ ] 章节列表
- [ ] 图片加载

### 4. 查看日志
```
预期日志：
✅ "检测到WebView类型图源，初始化WebView系统"
✅ "WebView引擎初始化成功"
✅ "使用WebView系统加载漫画列表"
✅ "WebView搜索成功，找到 X 条结果"
```

---

## ⚠️ 注意事项

### 1. JavaScript 代码格式
- 必须是单行字符串（JSON 不支持多行）
- 使用模板字符串 `` ` `` 包裹 GraphQL 查询
- 正确转义引号

### 2. 变量替换
- `{{keyword}}` - 搜索关键词
- `{{mangaId}}` - 漫画ID
- `{{chapterId}}` - 章节ID
- `{{baseUrl}}` - 基础URL

### 3. 性能考虑
- WebView 初始化需要时间（~2秒）
- 每次请求都需要执行 JavaScript
- 建议添加缓存机制

### 4. 错误处理
- JavaScript 执行失败会自动降级到 HTTP 系统
- 确保 GraphQL 查询语法正确
- 检查返回数据结构

---

## 📊 性能对比

| 指标 | HTTP 格式 | WebView 格式 |
|------|-----------|--------------|
| 初始化时间 | < 100ms | ~2000ms |
| 请求延迟 | 500-1000ms | 1000-2000ms |
| 内存占用 | +5MB | +30MB |
| CPU 使用 | 低 | 中 |
| 兼容性 | 高 | 高 |
| 可维护性 | 中 | 高 |

---

## 🚀 推荐策略

### 短期（当前）
保留两个版本：
- `komiic.json` - HTTP 格式（默认）
- `komiic_webview.json` - WebView 格式（测试）

### 中期（1-2周）
根据测试结果选择：
- 如果 WebView 版本稳定 → 迁移到 WebView
- 如果性能问题明显 → 继续使用 HTTP

### 长期（1个月+）
统一到 WebView 格式：
- 所有图源使用统一架构
- 便于维护和扩展
- 支持更复杂的网站

---

## 📚 相关文档

- [WebView 系统设计](../entry/src/main/ets/Framework/WebView/doc/README.md)
- [配置编写指南](../entry/src/main/ets/Framework/WebView/doc/JSON_Rule_Writing_Guide_v2.md)
- [SourceDetailPage 重构报告](../SOURCEPAGE_REFACTOR_COMPLETE.md)

---

**文档版本**: 1.0  
**最后更新**: 2025-11-17 22:50  
**状态**: 待测试
