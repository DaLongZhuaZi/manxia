# JSON规则完整示例集

## 📚 示例索引

1. [基础示例](#基础示例)
2. [中级示例](#中级示例)
3. [高级示例](#高级示例)
4. [特殊场景示例](#特殊场景示例)

## 🌟 基础示例

### 示例1: 简单的静态网站

```json
{
  "metadata": {
    "name": "简单漫画站",
    "version": "1.0.0",
    "author": "示例作者",
    "description": "简单的静态漫画网站",
    "baseUrl": "https://simple-manga.com",
    "language": "zh-CN",
    "created": "2025-11-17",
    "updated": "2025-11-17"
  },
  "settings": {
    "timeout": 30000,
    "retryCount": 3,
    "enableJavaScript": false,
    "enableImages": true,
    "enableCookies": false,
    "bypassCloudflare": false
  },
  "workflows": {
    "search": [
      {
        "type": "navigate",
        "url": "{{baseUrl}}/search?q={{keyword}}",
        "description": "打开搜索页面"
      },
      {
        "type": "extract",
        "selector": ".manga-list .item",
        "multiple": true,
        "fields": {
          "title": ".title",
          "url": "a@href",
          "cover": "img@src"
        }
      }
    ],
    "getMangaDetail": [
      {
        "type": "navigate",
        "url": "{{mangaUrl}}"
      },
      {
        "type": "extract",
        "selector": ".manga-info",
        "fields": {
          "title": "h1",
          "author": ".author",
          "description": ".description"
        }
      }
    ],
    "getChapterList": [
      {
        "type": "navigate",
        "url": "{{mangaUrl}}"
      },
      {
        "type": "extract",
        "selector": ".chapter-list li",
        "multiple": true,
        "fields": {
          "title": ".chapter-title",
          "url": "a@href"
        }
      }
    ],
    "getPageList": [
      {
        "type": "navigate",
        "url": "{{chapterUrl}}"
      },
      {
        "type": "extract",
        "selector": ".page-image",
        "multiple": true,
        "fields": {
          "imageUrl": "@src"
        }
      }
    ]
  }
}
```

## 🎯 中级示例

### 示例2: 需要登录的网站

```json
{
  "metadata": {
    "name": "需要登录的漫画站",
    "version": "1.0.0",
    "author": "示例作者",
    "description": "需要登录才能访问的漫画网站",
    "baseUrl": "https://members-manga.com",
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
  "variables": {
    "username": "your_username",
    "password": "your_password"
  },
  "workflows": {
    "initialize": [
      {
        "type": "navigate",
        "url": "{{baseUrl}}/login",
        "description": "打开登录页面"
      },
      {
        "type": "condition",
        "selector": ".login-form",
        "exists": true,
        "then": [
          {
            "type": "input",
            "selector": "#username",
            "value": "{{username}}",
            "clear": true
          },
          {
            "type": "input",
            "selector": "#password",
            "value": "{{password}}",
            "clear": true
          },
          {
            "type": "click",
            "selector": "#login-btn"
          },
          {
            "type": "wait",
            "condition": "element",
            "selector": ".user-profile",
            "timeout": 5000
          }
        ]
      }
    ],
    "search": [
      {
        "type": "navigate",
        "url": "{{baseUrl}}/search?q={{keyword}}"
      },
      {
        "type": "wait",
        "condition": "element",
        "selector": ".search-results"
      },
      {
        "type": "extract",
        "selector": ".manga-item",
        "multiple": true,
        "fields": {
          "title": ".title",
          "url": "a@href",
          "cover": "img@data-src"
        }
      }
    ]
  }
}
```

### 示例3: 动态加载内容

```json
{
  "metadata": {
    "name": "动态加载漫画站",
    "version": "1.0.0",
    "author": "示例作者",
    "description": "使用AJAX动态加载内容的网站",
    "baseUrl": "https://dynamic-manga.com",
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
        "url": "{{baseUrl}}/search"
      },
      {
        "type": "input",
        "selector": "#search-input",
        "value": "{{keyword}}"
      },
      {
        "type": "click",
        "selector": "#search-btn"
      },
      {
        "type": "wait",
        "condition": "networkidle",
        "timeout": 5000,
        "description": "等待AJAX加载完成"
      },
      {
        "type": "extract",
        "selector": ".result-item",
        "multiple": true,
        "fields": {
          "title": ".title",
          "url": "@data-url",
          "cover": "img@data-lazy"
        }
      }
    ],
    "getPageList": [
      {
        "type": "navigate",
        "url": "{{chapterUrl}}"
      },
      {
        "type": "script",
        "code": "window.scrollTo(0, document.body.scrollHeight);",
        "description": "滚动到底部触发懒加载"
      },
      {
        "type": "wait",
        "condition": "time",
        "duration": 2000
      },
      {
        "type": "extract",
        "selector": ".page-image",
        "multiple": true,
        "fields": {
          "imageUrl": "@data-src"
        }
      }
    ]
  }
}
```

## 🚀 高级示例

### 示例4: 带Cloudflare防护的网站

```json
{
  "metadata": {
    "name": "CF防护漫画站",
    "version": "1.0.0",
    "author": "示例作者",
    "description": "使用Cloudflare防护的网站",
    "baseUrl": "https://protected-manga.com",
    "language": "zh-CN",
    "created": "2025-11-17",
    "updated": "2025-11-17"
  },
  "settings": {
    "timeout": 60000,
    "retryCount": 5,
    "enableJavaScript": true,
    "enableImages": true,
    "enableCookies": true,
    "bypassCloudflare": true
  },
  "workflows": {
    "initialize": [
      {
        "type": "navigate",
        "url": "{{baseUrl}}"
      },
      {
        "type": "cloudflareBypass",
        "method": "wait",
        "maxWaitTime": 15000,
        "indicators": [
          "Checking your browser",
          "Just a moment"
        ]
      },
      {
        "type": "wait",
        "condition": "element",
        "selector": ".main-content",
        "timeout": 5000
      }
    ],
    "search": [
      {
        "type": "navigate",
        "url": "{{baseUrl}}/search?q={{keyword}}"
      },
      {
        "type": "condition",
        "selector": ".cf-challenge",
        "exists": true,
        "then": [
          {
            "type": "cloudflareBypass",
            "method": "wait",
            "maxWaitTime": 15000
          }
        ]
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

### 示例5: 需要解密的图片URL

```json
{
  "metadata": {
    "name": "加密图片漫画站",
    "version": "1.0.0",
    "author": "示例作者",
    "description": "图片URL需要解密的网站",
    "baseUrl": "https://encrypted-manga.com",
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
    "getImageUrl": [
      {
        "type": "navigate",
        "url": "{{pageUrl}}"
      },
      {
        "type": "script",
        "code": "var encryptedUrl = document.querySelector('#image').getAttribute('data-encrypted'); var decryptedUrl = atob(encryptedUrl); document.querySelector('#image').src = decryptedUrl;",
        "description": "解密图片URL"
      },
      {
        "type": "wait",
        "condition": "time",
        "duration": 1000
      },
      {
        "type": "extract",
        "selector": "#image",
        "fields": {
          "imageUrl": "@src"
        }
      }
    ]
  },
  "customActions": {
    "decryptImage": {
      "type": "decryptImage",
      "code": "function decrypt(url) { return atob(url); }"
    }
  }
}
```

### 示例6: 多页翻页

```json
{
  "metadata": {
    "name": "分页漫画站",
    "version": "1.0.0",
    "author": "示例作者",
    "description": "搜索结果分页的网站",
    "baseUrl": "https://paginated-manga.com",
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
        "url": "{{baseUrl}}/search?q={{keyword}}&page=1"
      },
      {
        "type": "extract",
        "selector": ".manga-item",
        "multiple": true,
        "fields": {
          "title": ".title",
          "url": "a@href"
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
            "condition": "networkidle"
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
    ]
  }
}
```

## 🎨 特殊场景示例

### 示例7: API接口图源

```json
{
  "metadata": {
    "name": "API漫画站",
    "version": "1.0.0",
    "author": "示例作者",
    "description": "使用API接口的网站",
    "baseUrl": "https://api-manga.com",
    "language": "zh-CN",
    "created": "2025-11-17",
    "updated": "2025-11-17"
  },
  "settings": {
    "timeout": 30000,
    "retryCount": 3,
    "enableJavaScript": true,
    "enableImages": false,
    "enableCookies": true,
    "bypassCloudflare": false
  },
  "variables": {
    "apiKey": "your-api-key"
  },
  "workflows": {
    "search": [
      {
        "type": "navigate",
        "url": "{{baseUrl}}/api/search?q={{keyword}}&key={{apiKey}}"
      },
      {
        "type": "script",
        "code": "var data = JSON.parse(document.body.textContent); window.searchResults = data.results;",
        "description": "解析API响应"
      },
      {
        "type": "script",
        "code": "return JSON.stringify(window.searchResults);"
      }
    ]
  }
}
```

### 示例8: 需要验证码的网站

```json
{
  "metadata": {
    "name": "验证码漫画站",
    "version": "1.0.0",
    "author": "示例作者",
    "description": "需要验证码验证的网站",
    "baseUrl": "https://captcha-manga.com",
    "language": "zh-CN",
    "created": "2025-11-17",
    "updated": "2025-11-17"
  },
  "settings": {
    "timeout": 60000,
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
        "url": "{{baseUrl}}/search"
      },
      {
        "type": "condition",
        "selector": ".captcha-container",
        "exists": true,
        "then": [
          {
            "type": "captcha",
            "selector": "#captcha-image",
            "method": "manual",
            "timeout": 60000,
            "description": "等待用户手动输入验证码"
          }
        ]
      },
      {
        "type": "input",
        "selector": "#search-input",
        "value": "{{keyword}}"
      },
      {
        "type": "click",
        "selector": "#search-btn"
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

---

**文档版本**: v1.0.0  
**更新日期**: 2025-11-17  
**示例数量**: 8个
