# 漫画图源引擎规范文档

## 1. 系统概述

漫画图源引擎是一个完全由JSON配置文件驱动的WebView自动化系统，每个JSON文件定义一个图源网站的完整操作流程，包括：

- 网页导航和加载
- 弹窗处理和关闭
- 元素选择和交互
- 数据提取和解析
- 反爬虫机制绕过
- 错误处理和重试

## 2. JSON配置文件架构

### 2.1 基础结构

```json
{
  "metadata": {
    "name": "图源名称",
    "version": "1.0.0",
    "author": "作者",
    "description": "图源描述",
    "baseUrl": "https://example.com",
    "language": "zh-CN",
    "created": "2024-01-01T00:00:00Z",
    "updated": "2024-01-01T00:00:00Z"
  },
  "settings": {
    "userAgent": "自定义User-Agent",
    "timeout": 30000,
    "retryCount": 3,
    "enableJavaScript": true,
    "enableImages": true,
    "enableCookies": true,
    "bypassCloudflare": true
  },
  "workflows": {
    "initialize": [],
    "search": [],
    "getMangaList": [],
    "getMangaDetail": [],
    "getChapterList": [],
    "getPageList": [],
    "getImageUrl": []
  }
}
```

### 2.2 操作类型定义

#### 2.2.1 导航操作
```json
{
  "type": "navigate",
  "url": "https://example.com/search?q={query}",
  "waitFor": "networkidle",
  "timeout": 10000
}
```

#### 2.2.2 等待操作
```json
{
  "type": "wait",
  "condition": "element",
  "selector": ".manga-list",
  "timeout": 5000
}
```

#### 2.2.3 点击操作
```json
{
  "type": "click",
  "selector": ".popup-close",
  "optional": true,
  "waitAfter": 1000
}
```

#### 2.2.4 输入操作
```json
{
  "type": "input",
  "selector": "#search-input",
  "value": "{query}",
  "clear": true
}
```

#### 2.2.5 提取操作
```json
{
  "type": "extract",
  "selector": ".manga-item",
  "multiple": true,
  "fields": {
    "title": ".title",
    "url": "a@href",
    "cover": "img@src",
    "author": ".author",
    "status": ".status"
  }
}
```

#### 2.2.6 条件判断
```json
{
  "type": "condition",
  "selector": ".cloudflare-challenge",
  "exists": true,
  "then": [
    {
      "type": "wait",
      "condition": "time",
      "duration": 5000
    }
  ],
  "else": []
}
```

#### 2.2.7 脚本执行
```json
{
  "type": "script",
  "code": "document.querySelector('.ads').style.display = 'none';",
  "waitAfter": 500
}
```

### 2.3 选择器系统

#### 2.3.1 CSS选择器
```json
{
  "type": "css",
  "value": ".manga-list .item:nth-child(1)"
}
```

#### 2.3.2 XPath选择器
```json
{
  "type": "xpath",
  "value": "//div[@class='manga-list']//a[contains(text(), '漫画')]"
}
```

#### 2.3.3 文本匹配
```json
{
  "type": "text",
  "value": "关闭广告",
  "exact": false
}
```

#### 2.3.4 属性匹配
```json
{
  "type": "attribute",
  "attribute": "data-id",
  "value": "manga-123"
}
```

### 2.4 数据提取规则

#### 2.4.1 文本提取
```json
{
  "field": "title",
  "selector": ".manga-title",
  "attribute": "text",
  "transform": "trim"
}
```

#### 2.4.2 属性提取
```json
{
  "field": "imageUrl",
  "selector": "img.cover",
  "attribute": "src",
  "transform": "absoluteUrl"
}
```

#### 2.4.3 正则表达式处理
```json
{
  "field": "chapterId",
  "selector": "a.chapter-link",
  "attribute": "href",
  "regex": "/chapter/(\\d+)",
  "group": 1
}
```

## 3. 反爬虫机制处理

### 3.1 Cloudflare绕过
```json
{
  "type": "cloudflareBypass",
  "method": "wait",
  "maxWaitTime": 10000,
  "indicators": [
    ".cf-browser-verification",
    "#cf-wrapper"
  ]
}
```

### 3.2 验证码处理
```json
{
  "type": "captcha",
  "selector": ".captcha-image",
  "method": "manual",
  "timeout": 60000
}
```

### 3.3 IP限制处理
```json
{
  "type": "ipBlock",
  "indicators": [
    "访问频率过高",
    "IP被限制"
  ],
  "action": "retry",
  "delay": 5000
}
```

## 4. 错误处理机制

### 4.1 重试策略
```json
{
  "retry": {
    "maxAttempts": 3,
    "delay": 2000,
    "backoff": "exponential",
    "conditions": [
      "timeout",
      "networkError",
      "elementNotFound"
    ]
  }
}
```

### 4.2 降级策略
```json
{
  "fallback": {
    "selector": ".manga-list-alt",
    "workflow": "alternativeExtraction"
  }
}
```

## 5. 变量系统

### 5.1 内置变量
- `{query}`: 搜索关键词
- `{page}`: 页码
- `{mangaId}`: 漫画ID
- `{chapterId}`: 章节ID
- `{baseUrl}`: 基础URL

### 5.2 自定义变量
```json
{
  "variables": {
    "searchUrl": "{baseUrl}/search?keyword={query}&page={page}",
    "userAgent": "Mozilla/5.0 (compatible; MangaReader/1.0)"
  }
}
```

## 6. 工作流程定义

### 6.1 搜索流程
```json
{
  "search": [
    {
      "type": "navigate",
      "url": "{searchUrl}"
    },
    {
      "type": "wait",
      "condition": "element",
      "selector": ".search-results"
    },
    {
      "type": "condition",
      "selector": ".popup-ad",
      "exists": true,
      "then": [
        {
          "type": "click",
          "selector": ".popup-close"
        }
      ]
    },
    {
      "type": "extract",
      "selector": ".manga-item",
      "multiple": true,
      "fields": {
        "title": ".title",
        "url": "a@href",
        "cover": "img@src"
      }
    }
  ]
}
```

### 6.2 详情获取流程
```json
{
  "getMangaDetail": [
    {
      "type": "navigate",
      "url": "{mangaUrl}"
    },
    {
      "type": "cloudflareBypass"
    },
    {
      "type": "extract",
      "selector": ".manga-detail",
      "fields": {
        "title": ".manga-title",
        "author": ".manga-author",
        "description": ".manga-description",
        "status": ".manga-status",
        "genres": ".genre-tag"
      }
    }
  ]
}
```

## 7. 性能优化

### 7.1 缓存策略
```json
{
  "cache": {
    "enabled": true,
    "ttl": 3600000,
    "keys": ["mangaDetail", "chapterList"]
  }
}
```

### 7.2 并发控制
```json
{
  "concurrency": {
    "maxConcurrent": 3,
    "delay": 1000
  }
}
```

## 8. 调试支持

### 8.1 日志记录
```json
{
  "debug": {
    "enabled": true,
    "level": "info",
    "logActions": true,
    "logSelectors": true
  }
}
```

### 8.2 截图支持
```json
{
  "screenshot": {
    "onError": true,
    "onSuccess": false,
    "path": "/screenshots/"
  }
}
```

## 9. 安全考虑

### 9.1 URL验证
- 所有URL必须匹配baseUrl域名
- 禁止访问本地文件和内网地址

### 9.2 脚本限制
- 限制可执行的JavaScript代码
- 禁止访问敏感API

### 9.3 资源限制
- 限制单次操作的最大时间
- 限制内存使用量

## 10. 扩展机制

### 10.1 自定义操作
```json
{
  "customActions": {
    "waitForImageLoad": {
      "type": "script",
      "code": "return new Promise(resolve => { /* 等待图片加载完成 */ })"
    }
  }
}
```

### 10.2 插件系统
```json
{
  "plugins": [
    {
      "name": "adBlocker",
      "enabled": true,
      "config": {}
    }
  ]
}
```