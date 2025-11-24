# ManXia 图源开发指南

## 快速开始

### 1. 创建基础配置

复制 `komiic.json` 作为模板，修改基本信息：

```json
{
  "metadata": {
    "id": "your-source-id",
    "name": "Your Source Name",
    "version": "1.0.0",
    "language": "zh-CN",
    "baseUrl": "https://your-site.com"
  }
}
```

### 2. 配置网络请求

根据目标网站的要求配置HTTP头：

```json
{
  "network": {
    "userAgent": "Mozilla/5.0...",
    "headers": {
      "Referer": "https://your-site.com/",
      "Accept": "application/json"
    }
  }
}
```

### 3. 实现核心功能

至少实现以下功能：
- `popular` - 热门漫画列表
- `search` - 搜索功能
- `detail` - 漫画详情
- `pages` - 章节图片

## 开发流程

### 步骤1：分析目标网站

1. **打开开发者工具**
   - Chrome: F12
   - 查看Network标签

2. **分析API请求**
   - 浏览热门页面，记录请求
   - 执行搜索，记录请求
   - 查看漫画详情，记录请求
   - 打开章节，记录图片请求

3. **记录关键信息**
   - API端点URL
   - 请求方法（GET/POST）
   - 请求头
   - 请求参数
   - 响应格式

### 步骤2：编写配置

#### 示例：热门列表

假设API请求如下：
```
POST https://example.com/api/popular
Content-Type: application/json

{
  "page": 1,
  "limit": 20
}
```

响应：
```json
{
  "code": 0,
  "data": {
    "items": [
      {
        "id": "123",
        "title": "漫画标题",
        "cover": "https://example.com/cover.jpg",
        "author": "作者名"
      }
    ]
  }
}
```

配置：
```json
{
  "features": {
    "popular": {
      "enabled": true,
      "method": "POST",
      "url": "{{baseUrl}}/api/popular",
      "body": {
        "page": "{{page}}",
        "limit": "{{limit}}"
      },
      "responseType": "json",
      "parser": {
        "type": "json",
        "listPath": "$.data.items",
        "item": {
          "id": "$.id",
          "title": "$.title",
          "coverUrl": "$.cover",
          "author": "$.author"
        }
      }
    }
  }
}
```

### 步骤3：测试配置

1. **验证JSON格式**
   ```bash
   # 使用在线工具或命令行
   ajv validate -s source-schema.json -d your-source.json
   ```

2. **测试API请求**
   - 使用Postman或curl测试
   - 验证响应数据结构
   - 确认JSONPath表达式正确

3. **导入到应用**
   - 在图源页面点击"导入"
   - 选择JSON文件
   - 查看导入结果

4. **功能测试**
   - 测试热门列表
   - 测试搜索
   - 测试详情页
   - 测试图片加载

## 常见场景

### 场景1：REST API

```json
{
  "api": {
    "type": "rest",
    "endpoint": "https://api.example.com"
  },
  "features": {
    "popular": {
      "method": "GET",
      "url": "{{baseUrl}}/v1/comics/popular?page={{page}}&limit={{limit}}"
    }
  }
}
```

### 场景2：GraphQL API

```json
{
  "api": {
    "type": "graphql",
    "endpoint": "https://api.example.com/graphql"
  },
  "features": {
    "popular": {
      "method": "POST",
      "url": "{{baseUrl}}/graphql",
      "body": {
        "query": "query Popular($limit: Int!) { popular(limit: $limit) { id title } }",
        "variables": {
          "limit": "{{limit}}"
        }
      }
    }
  }
}
```

### 场景3：需要特殊请求头

```json
{
  "network": {
    "headers": {
      "X-API-Key": "your-api-key",
      "X-Client-Version": "1.0.0",
      "Referer": "https://example.com/"
    }
  }
}
```

### 场景4：图片需要特殊请求头

```json
{
  "features": {
    "pages": {
      "imageHeaders": {
        "Referer": "{{baseUrl}}/chapter/{{chapterId}}",
        "User-Agent": "Mozilla/5.0..."
      }
    }
  }
}
```

### 场景5：分页

#### Offset分页
```json
{
  "pagination": {
    "type": "offset",
    "limitParam": "limit",
    "offsetParam": "offset",
    "defaultLimit": 20
  }
}
```

#### Page分页
```json
{
  "pagination": {
    "type": "page",
    "pageParam": "page",
    "limitParam": "pageSize",
    "defaultLimit": 20
  }
}
```

### 场景6：搜索过滤器

```json
{
  "features": {
    "search": {
      "filters": [
        {
          "type": "text",
          "id": "keyword",
          "name": "关键词",
          "placeholder": "输入搜索内容"
        },
        {
          "type": "select",
          "id": "category",
          "name": "分类",
          "default": "all",
          "options": [
            { "value": "all", "label": "全部" },
            { "value": "action", "label": "动作" },
            { "value": "romance", "label": "爱情" }
          ]
        },
        {
          "type": "select",
          "id": "status",
          "name": "状态",
          "options": [
            { "value": "all", "label": "全部" },
            { "value": "ongoing", "label": "连载中" },
            { "value": "completed", "label": "已完结" }
          ]
        }
      ]
    }
  }
}
```

## JSONPath速查

| 表达式 | 说明 | 示例 |
|--------|------|------|
| `$` | 根节点 | `$.data` |
| `.` | 子节点 | `$.user.name` |
| `[]` | 数组访问 | `$.items[0]` |
| `[*]` | 所有元素 | `$.items[*].title` |
| `..` | 递归查找 | `$..author` |
| `[?()]` | 过滤 | `$.items[?(@.price < 10)]` |

## 调试技巧

### 1. 使用日志

在开发过程中，查看应用日志：
```
hdc shell hilog | grep SourceParser
```

### 2. 验证JSONPath

使用在线工具测试JSONPath：
- https://jsonpath.com/
- https://jsonpath.herokuapp.com/

### 3. 测试HTTP请求

使用curl测试API：
```bash
curl -X POST https://api.example.com/search \
  -H "Content-Type: application/json" \
  -H "Referer: https://example.com/" \
  -d '{"keyword": "test"}'
```

### 4. 检查响应格式

使用jq格式化JSON：
```bash
curl ... | jq '.'
```

## 最佳实践

### 1. 命名规范
- ID使用小写字母和连字符：`my-source`
- 版本号遵循语义化：`1.0.0`
- 字段名使用驼峰命名：`coverUrl`

### 2. 错误处理
- 提供清晰的错误信息
- 在notes中说明已知问题
- 设置合理的超时时间

### 3. 性能优化
- 设置合理的速率限制
- 使用适当的分页大小
- 避免不必要的请求

### 4. 用户体验
- 提供有意义的设置选项
- 使用清晰的标签和描述
- 提供默认值

### 5. 维护性
- 添加详细的changelog
- 在notes中记录特殊要求
- 保持配置简洁

## 常见问题

### Q: 如何处理需要登录的网站？
A: 目前不支持复杂的登录流程，建议：
- 使用公开API
- 或在settings中让用户提供token

### Q: 如何处理动态加载的内容？
A: 目前不支持JavaScript执行，建议：
- 分析XHR请求
- 直接调用底层API

### Q: 如何处理图片防盗链？
A: 在imageHeaders中设置正确的Referer

### Q: 如何处理加密的图片URL？
A: 目前不支持，这是待实现功能

### Q: 如何处理分页？
A: 使用pagination配置，支持offset和page两种方式

## 示例图源

### 简单REST API
参考：`komiic.json`

### 复杂GraphQL API
参考：`komiic.json`

### HTML解析（待实现）
待补充

## 提交图源

### 1. 测试
- 完整测试所有功能
- 确保没有错误
- 验证图片可以加载

### 2. 文档
- 填写完整的metadata
- 添加changelog
- 在notes中说明特殊要求

### 3. 打包
- 准备icon.png（可选）
- 创建ZIP压缩包
- 或直接使用JSON文件

### 4. 分享
- 提交到图源市场（待实现）
- 或分享JSON文件

## 获取帮助

- 查看示例：`komiic.json`
- 阅读文档：`README.md`
- 查看缺失功能：`MISSING_FEATURES.md`
- 提交Issue：GitHub Issues

---

**版本**: 1.0.0  
**更新日期**: 2025-11-17  
**作者**: ManXia Team
