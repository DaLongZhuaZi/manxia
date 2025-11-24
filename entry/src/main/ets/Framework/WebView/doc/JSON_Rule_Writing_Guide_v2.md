# JSON规则编写完全指南 v2.0

## 🎉 v2.0新特性

本指南已更新以包含WebView系统v2.0的所有新功能。

**主要更新**:
- ✅ 13个新操作类型
- ✅ 2个新选择器类型
- ✅ 错误恢复机制
- ✅ 性能监控
- ✅ 数据验证

## 📚 新增操作类型快速索引

| 操作 | 用途 | 优先级 |
|------|------|--------|
| [loop](#loop-循环操作) | 翻页、批量操作 | ⭐⭐⭐⭐⭐ |
| [parallel](#parallel-并行操作) | 并发执行 | ⭐⭐⭐⭐⭐ |
| [scroll](#scroll-滚动操作) | 懒加载 | ⭐⭐⭐⭐ |
| [variableSet](#variableset-变量设置) | 动态变量 | ⭐⭐⭐⭐ |
| [variableGet](#variableget-变量获取) | 获取变量 | ⭐⭐⭐⭐ |
| [hover](#hover-悬停操作) | 悬停菜单 | ⭐⭐⭐ |
| [select](#select-下拉选择) | 下拉框 | ⭐⭐⭐ |
| [cookieSet](#cookieset-cookie设置) | Cookie管理 | ⭐⭐⭐ |
| [cookieGet](#cookieget-cookie获取) | Cookie读取 | ⭐⭐⭐ |
| [storageSet](#storageset-storage设置) | Storage管理 | ⭐⭐ |
| [storageGet](#storageget-storage获取) | Storage读取 | ⭐⭐ |
| [screenshot](#screenshot-截图) | 调试辅助 | ⭐⭐ |

## 🔥 高优先级新功能详解

### loop - 循环操作

**最常用场景**: 翻页爬取

#### 基础循环

```json
{
  "type": "loop",
  "maxIterations": 10,
  "actions": [
    {
      "type": "extract",
      "selector": ".item",
      "multiple": true,
      "fields": {"title": ".title"}
    },
    {
      "type": "click",
      "selector": ".next-page"
    },
    {
      "type": "wait",
      "condition": "networkidle"
    }
  ]
}
```

#### 带跳出条件的循环

```json
{
  "type": "loop",
  "maxIterations": 100,
  "actions": [...],
  "breakCondition": {
    "selector": ".no-more-data",
    "exists": true
  },
  "description": "爬取所有页面直到没有更多数据"
}
```

#### 遍历元素

```json
{
  "type": "loop",
  "selector": ".chapter-item",
  "actions": [
    {
      "type": "variableSet",
      "name": "chapterUrl",
      "source": "selector",
      "selector": "a",
      "attribute": "href"
    },
    {
      "type": "navigate",
      "url": "{{chapterUrl}}"
    },
    {
      "type": "extract",
      "selector": ".page-image",
      "multiple": true,
      "fields": {"imageUrl": "@src"}
    }
  ],
  "description": "遍历所有章节并提取图片"
}
```

### parallel - 并行操作

**最常用场景**: 批量下载、提升性能

#### 并行下载多个页面

```json
{
  "type": "parallel",
  "actions": [
    [
      {"type": "navigate", "url": "{{baseUrl}}/page1"},
      {"type": "extract", "selector": ".data", "fields": {...}}
    ],
    [
      {"type": "navigate", "url": "{{baseUrl}}/page2"},
      {"type": "extract", "selector": ".data", "fields": {...}}
    ],
    [
      {"type": "navigate", "url": "{{baseUrl}}/page3"},
      {"type": "extract", "selector": ".data", "fields": {...}}
    ]
  ],
  "waitAll": true,
  "maxConcurrent": 3,
  "description": "并行下载3个页面"
}
```

#### 并行执行不同任务

```json
{
  "type": "parallel",
  "actions": [
    [
      {"type": "extract", "selector": ".manga-info", "fields": {...}}
    ],
    [
      {"type": "extract", "selector": ".chapter-list", "multiple": true, "fields": {...}}
    ],
    [
      {"type": "extract", "selector": ".comments", "multiple": true, "fields": {...}}
    ]
  ],
  "waitAll": true,
  "description": "并行提取漫画信息、章节列表和评论"
}
```

### scroll - 滚动操作

**最常用场景**: 懒加载内容

#### 滚动到底部

```json
{
  "type": "scroll",
  "direction": "bottom",
  "smooth": true,
  "description": "滚动到页面底部触发懒加载"
}
```

#### 滚动指定距离

```json
{
  "type": "scroll",
  "direction": "down",
  "distance": 1000,
  "smooth": true,
  "description": "向下滚动1000像素"
}
```

#### 滚动到元素

```json
{
  "type": "scroll",
  "toElement": ".load-more-btn",
  "smooth": true,
  "description": "滚动到加载更多按钮"
}
```

#### 无限滚动加载

```json
{
  "type": "loop",
  "maxIterations": 10,
  "actions": [
    {
      "type": "scroll",
      "direction": "bottom"
    },
    {
      "type": "wait",
      "condition": "time",
      "duration": 2000
    },
    {
      "type": "extract",
      "selector": ".new-items",
      "multiple": true,
      "fields": {...}
    }
  ],
  "breakCondition": {
    "selector": ".end-of-list",
    "exists": true
  }
}
```

### variableSet / variableGet - 变量操作

**最常用场景**: 动态数据传递

#### 从常量设置

```json
{
  "type": "variableSet",
  "name": "pageSize",
  "value": "20",
  "source": "constant"
}
```

#### 从选择器提取

```json
{
  "type": "variableSet",
  "name": "mangaId",
  "source": "selector",
  "selector": ".manga-detail",
  "attribute": "data-id",
  "description": "提取漫画ID到变量"
}
```

#### 从脚本提取

```json
{
  "type": "variableSet",
  "name": "csrfToken",
  "source": "script",
  "value": "return document.querySelector('meta[name=csrf-token]').content;",
  "description": "提取CSRF令牌"
}
```

#### 使用变量

```json
[
  {
    "type": "variableSet",
    "name": "chapterId",
    "source": "selector",
    "selector": ".chapter",
    "attribute": "data-id"
  },
  {
    "type": "navigate",
    "url": "{{baseUrl}}/chapter/{{chapterId}}"
  }
]
```

## 🎯 新增选择器类型

### regex - 正则表达式选择器

**用途**: 复杂文本匹配和提取

```json
{
  "type": "extract",
  "selector": {
    "type": "regex",
    "pattern": "/manga/(\\d+)",
    "group": 1
  },
  "fields": {
    "mangaId": "text()"
  }
}
```

### composite - 组合选择器

**用途**: 复杂逻辑组合

#### AND组合（同时满足）

```json
{
  "type": "composite",
  "operator": "AND",
  "selectors": [
    {"type": "css", "value": ".manga-item"},
    {"type": "text", "value": "完结", "exact": false}
  ]
}
```

#### OR组合（满足任一）

```json
{
  "type": "composite",
  "operator": "OR",
  "selectors": [
    {"type": "css", "value": ".title"},
    {"type": "css", "value": ".name"},
    {"type": "css", "value": ".heading"}
  ]
}
```

#### NOT组合（排除）

```json
{
  "type": "composite",
  "operator": "NOT",
  "selectors": [
    {"type": "css", "value": ".advertisement"},
    {"type": "css", "value": ".sponsored"}
  ]
}
```

## 🛡️ 错误恢复机制

**所有操作都支持错误恢复**

### 基础错误恢复

```json
{
  "type": "extract",
  "selector": ".data",
  "fields": {...},
  "errorRecovery": {
    "maxRetries": 3,
    "retryDelay": 1000,
    "skipOnError": false
  }
}
```

### 带降级操作的错误恢复

```json
{
  "type": "navigate",
  "url": "{{primaryUrl}}",
  "errorRecovery": {
    "maxRetries": 2,
    "retryDelay": 2000,
    "fallbackActions": [
      {
        "type": "navigate",
        "url": "{{backupUrl}}"
      }
    ]
  },
  "description": "主URL失败时使用备用URL"
}
```

### 跳过错误继续执行

```json
{
  "type": "extract",
  "selector": ".optional-data",
  "fields": {...},
  "errorRecovery": {
    "skipOnError": true
  },
  "description": "提取失败时跳过，不中断流程"
}
```

## 📊 性能监控

### 启用性能监控

```json
{
  "performance": {
    "enabled": true,
    "metrics": ["timing", "memory", "network"],
    "reportInterval": 5000,
    "thresholds": {
      "loadTime": 3000,
      "memoryUsage": 100000000,
      "networkLatency": 500
    }
  }
}
```

### 性能指标说明

- **timing**: 页面加载时间
- **memory**: 内存使用情况
- **network**: 网络请求统计
- **fps**: 帧率（动画性能）

## ✅ 数据验证

### Extract操作中的验证

```json
{
  "type": "extract",
  "selector": ".manga-item",
  "fields": {
    "title": ".title",
    "url": "a@href",
    "chapters": ".chapter-count"
  },
  "validation": [
    {
      "field": "title",
      "type": "required",
      "message": "标题不能为空"
    },
    {
      "field": "url",
      "type": "format",
      "pattern": "^https?://",
      "message": "URL必须以http或https开头"
    },
    {
      "field": "chapters",
      "type": "range",
      "min": 1,
      "max": 10000,
      "message": "章节数必须在1-10000之间"
    }
  ]
}
```

### 全局验证规则

```json
{
  "validation": [
    {
      "field": "title",
      "type": "required"
    },
    {
      "field": "cover",
      "type": "format",
      "pattern": "\\.(jpg|png|webp)$"
    }
  ]
}
```

## 🎨 完整示例：高级翻页爬取

```json
{
  "workflows": {
    "search": [
      {
        "type": "navigate",
        "url": "{{baseUrl}}/search?q={{keyword}}"
      },
      {
        "type": "variableSet",
        "name": "totalPages",
        "source": "selector",
        "selector": ".total-pages",
        "attribute": "text"
      },
      {
        "type": "loop",
        "maxIterations": "{{totalPages}}",
        "actions": [
          {
            "type": "wait",
            "condition": "element",
            "selector": ".manga-list"
          },
          {
            "type": "extract",
            "selector": ".manga-item",
            "multiple": true,
            "fields": {
              "title": ".title",
              "url": "a@href",
              "cover": "img@src"
            },
            "validation": [
              {
                "field": "title",
                "type": "required"
              },
              {
                "field": "url",
                "type": "format",
                "pattern": "^https?://"
              }
            ],
            "errorRecovery": {
              "skipOnError": true
            }
          },
          {
            "type": "condition",
            "selector": ".next-page",
            "exists": true,
            "then": [
              {
                "type": "click",
                "selector": ".next-page"
              },
              {
                "type": "wait",
                "condition": "networkidle",
                "timeout": 5000
              }
            ],
            "else": []
          }
        ],
        "breakCondition": {
          "selector": ".no-more-data",
          "exists": true
        }
      }
    ]
  }
}
```

## 📝 最佳实践 v2.0

### 1. 优先使用循环而非手动重复

❌ **不推荐**:
```json
[
  {"type": "click", "selector": ".next"},
  {"type": "extract", ...},
  {"type": "click", "selector": ".next"},
  {"type": "extract", ...}
]
```

✅ **推荐**:
```json
{
  "type": "loop",
  "maxIterations": 10,
  "actions": [
    {"type": "extract", ...},
    {"type": "click", "selector": ".next"}
  ]
}
```

### 2. 使用并行提升性能

❌ **不推荐**（顺序执行）:
```json
[
  {"type": "navigate", "url": "{{url1}}"},
  {"type": "extract", ...},
  {"type": "navigate", "url": "{{url2}}"},
  {"type": "extract", ...}
]
```

✅ **推荐**（并行执行）:
```json
{
  "type": "parallel",
  "actions": [
    [{"type": "navigate", "url": "{{url1}}"}, {"type": "extract", ...}],
    [{"type": "navigate", "url": "{{url2}}"}, {"type": "extract", ...}]
  ]
}
```

### 3. 添加错误恢复

✅ **推荐**:
```json
{
  "type": "extract",
  "selector": ".data",
  "errorRecovery": {
    "maxRetries": 3,
    "retryDelay": 1000
  }
}
```

### 4. 使用数据验证

✅ **推荐**:
```json
{
  "type": "extract",
  "selector": ".item",
  "fields": {...},
  "validation": [
    {"field": "title", "type": "required"},
    {"field": "url", "type": "format", "pattern": "^https?://"}
  ]
}
```

### 5. 使用变量实现动态逻辑

✅ **推荐**:
```json
[
  {
    "type": "variableSet",
    "name": "pageId",
    "source": "selector",
    "selector": ".page-id",
    "attribute": "data-id"
  },
  {
    "type": "navigate",
    "url": "{{baseUrl}}/page/{{pageId}}"
  }
]
```

## 🔄 从v1.0升级

### 完全兼容

所有v1.0配置在v2.0中都能正常工作，无需修改。

### 推荐升级步骤

1. **保持现有配置不变**
2. **逐步添加新功能**:
   - 第一步：添加错误恢复
   - 第二步：使用循环替代重复操作
   - 第三步：使用并行提升性能
   - 第四步：添加数据验证
3. **测试验证**

---

**文档版本**: v2.0.0  
**更新日期**: 2025-11-17  
**适用版本**: WebView System v2.0+
