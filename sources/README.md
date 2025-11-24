# ManXia 图源插件格式说明

## 概述

ManXia使用JSON格式定义图源插件，支持通过配置文件方式添加新的漫画源，无需编写代码。

## 目录结构

```
sources/
├── source-schema.json          # JSON Schema定义
├── komiic.json                 # Komiic图源示例
├── komiic/                     # 图源资源文件夹（可选）
│   └── icon.png               # 图源图标
└── README.md                   # 本文档
```

## JSON格式说明

### 1. metadata（元数据）

定义图源的基本信息：

```json
{
  "metadata": {
    "id": "komiic",                    // 唯一标识符（小写字母、数字、下划线、连字符）
    "name": "Komiic",                  // 显示名称
    "version": "1.0.0",                // 版本号（语义化版本）
    "language": "zh-CN",               // 语言代码
    "baseUrl": "https://komiic.com",   // 基础URL
    "description": "描述文字",          // 图源描述
    "author": "作者名",                 // 作者
    "icon": "icon.png",                // 图标文件名
    "nsfw": false,                     // 是否成人内容
    "tags": ["Chinese", "Manga"],      // 标签
    "updateStrategy": "latest_chapter" // 更新策略
  }
}
```

### 2. network（网络配置）

定义网络请求相关配置：

```json
{
  "network": {
    "userAgent": "Mozilla/5.0...",     // User-Agent
    "headers": {                        // 默认HTTP头
      "Referer": "https://example.com/",
      "Accept": "application/json"
    },
    "timeout": 30000,                   // 超时时间（毫秒）
    "retryCount": 3,                    // 重试次数
    "retryDelay": 1000,                 // 重试延迟（毫秒）
    "rateLimit": {                      // 速率限制
      "requestsPerSecond": 2,           // 每秒请求数
      "burstSize": 5                    // 突发大小
    }
  }
}
```

### 3. api（API配置）

定义API类型和端点：

```json
{
  "api": {
    "type": "graphql",                  // API类型：rest/graphql/html/custom
    "endpoint": "https://api.example.com/query",
    "authentication": {                 // 认证配置
      "type": "none"                    // none/basic/bearer/oauth2/custom
    }
  }
}
```

### 4. features（功能定义）

定义图源支持的功能：

#### 4.1 popular（热门漫画）

```json
{
  "features": {
    "popular": {
      "enabled": true,
      "method": "POST",
      "url": "{{baseUrl}}/api/query",
      "body": {
        "query": "...",
        "variables": {}
      },
      "responseType": "json",
      "parser": {
        "type": "json",
        "listPath": "$.data.popular",
        "item": {
          "id": "$.id",
          "title": "$.title",
          "author": "$.author",
          "coverUrl": "$.cover"
        }
      },
      "pagination": {
        "type": "offset",
        "limitParam": "limit",
        "offsetParam": "offset",
        "defaultLimit": 20
      }
    }
  }
}
```

#### 4.2 latest（最新更新）

类似popular，但通常按更新时间排序。

#### 4.3 search（搜索）

```json
{
  "search": {
    "enabled": true,
    "method": "POST",
    "url": "{{baseUrl}}/api/search",
    "body": {
      "keyword": "{{keyword}}"
    },
    "filters": [
      {
        "type": "text",
        "id": "keyword",
        "name": "关键词",
        "placeholder": "输入搜索关键词"
      },
      {
        "type": "select",
        "id": "category",
        "name": "分类",
        "options": [
          { "value": "all", "label": "全部" },
          { "value": "action", "label": "动作" }
        ]
      }
    ]
  }
}
```

#### 4.4 detail（漫画详情）

```json
{
  "detail": {
    "enabled": true,
    "method": "GET",
    "url": "{{baseUrl}}/comic/{{comicId}}",
    "parser": {
      "type": "json",
      "root": "$.data",
      "fields": {
        "id": "$.id",
        "title": "$.title",
        "description": "$.description",
        "chapters": {
          "listPath": "$.chapters",
          "item": {
            "id": "$.id",
            "title": "$.title",
            "url": "{{baseUrl}}/chapter/{{id}}"
          }
        }
      }
    }
  }
}
```

#### 4.5 pages（章节图片）

```json
{
  "pages": {
    "enabled": true,
    "method": "GET",
    "url": "{{baseUrl}}/chapter/{{chapterId}}",
    "parser": {
      "type": "json",
      "listPath": "$.images",
      "item": {
        "url": "$.url",
        "width": "$.width",
        "height": "$.height"
      }
    },
    "imageHeaders": {
      "Referer": "{{baseUrl}}/"
    }
  }
}
```

### 5. settings（用户设置）

定义可配置的用户设置：

```json
{
  "settings": {
    "imageQuality": {
      "type": "select",
      "name": "图片质量",
      "default": "high",
      "options": [
        { "value": "low", "label": "低" },
        { "value": "high", "label": "高" }
      ]
    },
    "showNSFW": {
      "type": "boolean",
      "name": "显示成人内容",
      "default": false
    }
  }
}
```

## 变量替换

支持在URL和请求体中使用变量：

- `{{baseUrl}}` - 基础URL
- `{{comicId}}` - 漫画ID
- `{{chapterId}}` - 章节ID
- `{{keyword}}` - 搜索关键词
- `{{limit}}` - 分页限制
- `{{offset}}` - 分页偏移
- `{{page}}` - 页码
- 自定义设置变量：`{{settings.imageQuality}}`

## JSONPath表达式

使用JSONPath解析JSON响应：

- `$` - 根节点
- `$.data` - data字段
- `$.items[*]` - items数组的所有元素
- `$.items[0]` - items数组的第一个元素
- `$.author.name` - 嵌套字段

## 解析器类型

### JSON解析器

```json
{
  "parser": {
    "type": "json",
    "listPath": "$.data.items",
    "item": {
      "id": "$.id",
      "title": "$.title"
    }
  }
}
```

### HTML解析器（待实现）

```json
{
  "parser": {
    "type": "html",
    "selector": ".manga-item",
    "item": {
      "title": {
        "selector": ".title",
        "attr": "text"
      },
      "coverUrl": {
        "selector": "img",
        "attr": "src"
      }
    }
  }
}
```

## 打包格式

### 方式1：单个JSON文件

```
komiic.json
```

### 方式2：ZIP压缩包

```
komiic.zip
├── source.json          # 主配置文件
├── icon.png            # 图标（可选）
└── README.md           # 说明文档（可选）
```

## 示例

参考 `komiic.json` 获取完整示例。

## 验证

使用JSON Schema验证图源配置：

```bash
# 使用在线工具
https://www.jsonschemavalidator.net/

# 或使用命令行工具
ajv validate -s source-schema.json -d komiic.json
```

## 最佳实践

1. **命名规范**：使用小写字母和连字符
2. **版本管理**：遵循语义化版本规范
3. **错误处理**：提供清晰的错误信息
4. **性能优化**：合理设置速率限制
5. **测试**：在多种场景下测试图源
6. **文档**：在notes中说明特殊要求

## 限制和注意事项

1. 不支持JavaScript执行
2. 不支持复杂的认证流程
3. 图片URL必须是直接链接
4. 某些反爬虫机制可能无法绕过

## 待实现功能

参见 `MISSING_FEATURES.md`
