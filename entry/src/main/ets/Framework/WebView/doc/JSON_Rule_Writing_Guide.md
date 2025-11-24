# JSON规则编写完全指南

## 📚 目录

1. [快速开始](#快速开始)
2. [基础结构](#基础结构)
3. [操作类型详解](#操作类型详解)
4. [选择器系统](#选择器系统)
5. [工作流设计](#工作流设计)
6. [高级特性](#高级特性)
7. [最佳实践](#最佳实践)
8. [完整示例](#完整示例)

## 🚀 快速开始

### 最小配置示例

```json
{
  "metadata": {
    "name": "我的第一个图源",
    "version": "1.0.0",
    "author": "你的名字",
    "description": "简单的图源示例",
    "baseUrl": "https://example.com",
    "language": "zh-CN",
    "created": "2025-11-17",
    "updated": "2025-11-17"
  },
  "settings": {
    "timeout": 30000,
    "retryCount": 3,
    "enableJavaScript": true,
    "enableImages": true,
    "enableCookies": true,
    "bypassCloudflare": false
  },
  "workflows": {
    "search": [
      {
        "type": "navigate",
        "url": "{{baseUrl}}/search?q={{keyword}}"
      },
      {
        "type": "extract",
        "selector": ".manga-item",
        "multiple": true,
        "fields": {
          "title": ".title",
          "url": "a@href"
        }
      }
    ]
  }
}
```

## 📋 基础结构

### 1. metadata（元数据）- 必需

```json
{
  "metadata": {
    "name": "图源名称",           // 必需
    "version": "1.0.0",          // 必需，语义化版本
    "author": "作者名",          // 必需
    "description": "图源描述",   // 必需
    "baseUrl": "https://...",    // 必需，基础URL
    "language": "zh-CN",         // 必需，语言代码
    "created": "2025-11-17",     // 必需，创建日期
    "updated": "2025-11-17"      // 必需，更新日期
  }
}
```

### 2. settings（设置）- 必需

```json
{
  "settings": {
    "timeout": 30000,              // 超时时间（毫秒）
    "retryCount": 3,               // 重试次数
    "enableJavaScript": true,      // 启用JS
    "enableImages": true,          // 启用图片
    "enableCookies": true,         // 启用Cookie
    "bypassCloudflare": false,     // 绕过CF
    "userAgent": "Mozilla/5.0..."  // 可选，自定义UA
  }
}
```

### 3. workflows（工作流）- 必需

```json
{
  "workflows": {
    "initialize": [],      // 初始化（可选）
    "search": [],          // 搜索（必需）
    "getMangaList": [],    // 获取列表（可选）
    "getMangaDetail": [],  // 获取详情（必需）
    "getChapterList": [],  // 获取章节（必需）
    "getPageList": [],     // 获取页面（必需）
    "getImageUrl": []      // 获取图片（必需）
  }
}
```

## 🔧 操作类型详解

### 1. navigate - 页面导航

```json
{
  "type": "navigate",
  "url": "https://example.com/page",
  "waitFor": "load",        // load | networkidle | element
  "timeout": 30000,
  "description": "导航到目标页面"
}
```

**变量替换**:
```json
{
  "type": "navigate",
  "url": "{{baseUrl}}/search?q={{keyword}}"
}
```

### 2. wait - 等待操作

```json
{
  "type": "wait",
  "condition": "element",   // element | time | networkidle | load
  "selector": ".content",
  "timeout": 5000
}
```

**等待时间**:
```json
{
  "type": "wait",
  "condition": "time",
  "duration": 2000
}
```

### 3. click - 点击操作

```json
{
  "type": "click",
  "selector": "#login-btn",
  "waitAfter": 1000
}
```

### 4. input - 输入操作

```json
{
  "type": "input",
  "selector": "#search-box",
  "value": "{{keyword}}",
  "clear": true
}
```

### 5. extract - 数据提取

**简单提取**:
```json
{
  "type": "extract",
  "selector": ".title",
  "fields": {
    "title": "text()",
    "url": "@href"
  }
}
```

**多元素提取**:
```json
{
  "type": "extract",
  "selector": ".manga-item",
  "multiple": true,
  "fields": {
    "title": ".title",
    "url": "a@href",
    "cover": "img@src",
    "author": ".author"
  }
}
```

**高级提取**:
```json
{
  "type": "extract",
  "selector": ".manga-item",
  "multiple": true,
  "fields": [
    {
      "field": "title",
      "selector": ".title",
      "attribute": "text",
      "transform": "trim"
    },
    {
      "field": "id",
      "selector": "a",
      "attribute": "href",
      "regex": "/manga/(\\d+)",
      "group": 1
    }
  ]
}
```

### 6. condition - 条件判断

```json
{
  "type": "condition",
  "selector": ".login-required",
  "exists": true,
  "then": [
    {
      "type": "input",
      "selector": "#username",
      "value": "{{username}}"
    }
  ],
  "else": [
    {
      "type": "navigate",
      "url": "{{targetUrl}}"
    }
  ]
}
```

### 7. script - 脚本执行

```json
{
  "type": "script",
  "code": "document.querySelector('.ads').remove();"
}
```

### 8. cloudflareBypass - CF绕过

```json
{
  "type": "cloudflareBypass",
  "method": "wait",
  "maxWaitTime": 10000,
  "indicators": ["Checking your browser"]
}
```

### 9. captcha - 验证码处理

```json
{
  "type": "captcha",
  "selector": "#captcha-image",
  "method": "manual",
  "timeout": 60000
}
```

### 10. ipBlock - IP封禁处理

```json
{
  "type": "ipBlock",
  "indicators": ["Access denied", "IP blocked"],
  "action": "retry",
  "delay": 5000
}
```

## 🎯 选择器系统

### CSS选择器

```json
{
  "selector": ".manga-item"           // 类选择器
  "selector": "#manga-123"            // ID选择器
  "selector": "div.item"              // 标签+类
  "selector": ".item > .title"        // 子元素
  "selector": ".item .title"          // 后代元素
  "selector": ".item:first-child"     // 伪类
  "selector": "[data-id='123']"       // 属性选择器
}
```

### 属性提取

```json
{
  "selector": "img@src"               // 获取src属性
  "selector": "a@href"                // 获取href属性
  "selector": ".title@data-id"        // 获取data-id属性
  "selector": ".content"              // 获取文本内容（默认）
}
```

### XPath选择器

```json
{
  "type": "extract",
  "selector": {
    "type": "xpath",
    "value": "//div[@class='manga-item']"
  }
}
```

## 🔄 工作流设计

### 1. search - 搜索工作流

```json
{
  "workflows": {
    "search": [
      {
        "type": "navigate",
        "url": "{{baseUrl}}/search?keyword={{keyword}}",
        "description": "打开搜索页面"
      },
      {
        "type": "wait",
        "condition": "element",
        "selector": ".search-results",
        "description": "等待结果加载"
      },
      {
        "type": "extract",
        "selector": ".manga-item",
        "multiple": true,
        "fields": {
          "title": ".title",
          "url": "a@href",
          "cover": "img@src",
          "author": ".author",
          "status": ".status",
          "updated": ".update-time"
        },
        "description": "提取搜索结果"
      }
    ]
  }
}
```

### 2. getMangaDetail - 获取详情

```json
{
  "workflows": {
    "getMangaDetail": [
      {
        "type": "navigate",
        "url": "{{mangaUrl}}"
      },
      {
        "type": "extract",
        "selector": ".manga-detail",
        "fields": {
          "title": "h1.title",
          "cover": ".cover img@src",
          "author": ".author",
          "status": ".status",
          "description": ".description",
          "genres": ".genre-tag"
        }
      }
    ]
  }
}
```

### 3. getChapterList - 获取章节列表

```json
{
  "workflows": {
    "getChapterList": [
      {
        "type": "navigate",
        "url": "{{mangaUrl}}"
      },
      {
        "type": "extract",
        "selector": ".chapter-item",
        "multiple": true,
        "fields": {
          "title": ".chapter-title",
          "url": "a@href",
          "publishTime": ".publish-time"
        }
      }
    ]
  }
}
```

### 4. getPageList - 获取页面列表

```json
{
  "workflows": {
    "getPageList": [
      {
        "type": "navigate",
        "url": "{{chapterUrl}}"
      },
      {
        "type": "extract",
        "selector": ".page-item",
        "multiple": true,
        "fields": {
          "page": "@data-page",
          "imageUrl": "img@src"
        }
      }
    ]
  }
}
```

### 5. getImageUrl - 获取图片URL

```json
{
  "workflows": {
    "getImageUrl": [
      {
        "type": "navigate",
        "url": "{{pageUrl}}"
      },
      {
        "type": "extract",
        "selector": "#manga-image",
        "fields": {
          "imageUrl": "@src"
        }
      }
    ]
  }
}
```

## 🎨 高级特性

### 1. 变量系统

**定义变量**:
```json
{
  "variables": {
    "baseUrl": "https://example.com",
    "apiKey": "your-api-key",
    "userAgent": "Mozilla/5.0..."
  }
}
```

**使用变量**:
```json
{
  "type": "navigate",
  "url": "{{baseUrl}}/api?key={{apiKey}}"
}
```

### 2. 重试策略

```json
{
  "retry": {
    "maxAttempts": 3,
    "delay": 1000,
    "backoff": "exponential",
    "conditions": ["NETWORK_ERROR", "TIMEOUT_ERROR"]
  }
}
```

### 3. 缓存配置

```json
{
  "cache": {
    "enabled": true,
    "ttl": 3600000,
    "keys": ["search", "mangaDetail"]
  }
}
```

### 4. 并发控制

```json
{
  "concurrency": {
    "maxConcurrent": 3,
    "delay": 1000
  }
}
```

### 5. 调试配置

```json
{
  "debug": {
    "enabled": true,
    "level": "debug",
    "logActions": true,
    "logSelectors": true
  }
}
```

### 6. 反爬虫配置

```json
{
  "antiCrawler": {
    "cloudflare": {
      "enabled": true,
      "bypassMethod": "wait",
      "maxWaitTime": 10000
    },
    "captcha": {
      "enabled": true,
      "solverType": "manual"
    },
    "userAgentRotation": {
      "enabled": true,
      "agents": [
        "Mozilla/5.0...",
        "Mozilla/5.0..."
      ]
    }
  }
}
```

## 💡 最佳实践

### 1. 使用描述字段

```json
{
  "type": "navigate",
  "url": "{{baseUrl}}/search",
  "description": "导航到搜索页面"  // ✅ 添加描述
}
```

### 2. 合理使用等待

```json
[
  {
    "type": "click",
    "selector": "#load-more"
  },
  {
    "type": "wait",
    "condition": "networkidle",  // ✅ 等待网络空闲
    "timeout": 5000
  }
]
```

### 3. 错误处理

```json
{
  "type": "extract",
  "selector": ".manga-item",
  "optional": true,  // ✅ 标记为可选
  "multiple": true
}
```

### 4. 选择器优化

```json
{
  "selector": "#content .manga-item"  // ✅ 具体的选择器
  // 而不是
  "selector": ".item"  // ❌ 太宽泛
}
```

### 5. 变量命名

```json
{
  "variables": {
    "baseUrl": "...",      // ✅ 驼峰命名
    "apiKey": "...",       // ✅ 清晰的名称
    "maxRetries": 3        // ✅ 有意义的名称
  }
}
```

## 📝 完整示例

见下一个文档...

---

**文档版本**: v1.0.0  
**更新日期**: 2025-11-17  
**适用版本**: WebView System v1.0+
