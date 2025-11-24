# 图源系统增强设计方案

## 概述

为了支持CopyManga等复杂图源，我们需要对现有系统进行增强。本文档详细说明了所需的增强功能及其实现方案。

## 一、动态配置系统

### 1.1 动态域名切换

**目的**: 支持运行时切换API域名（如拷贝漫画 ↔ 热辣漫画）

**Schema扩展**:
```json
{
  "metadata": {
    "baseUrl": "https://www.mangacopy.com",
    "alternativeUrls": {
      "hotmanga": "https://www.hotmanga.com",
      "mirror1": "https://mirror1.mangacopy.com"
    }
  },
  "settings": {
    "apiDomain": {
      "type": "select",
      "name": "API域名",
      "description": "选择要使用的API服务器",
      "default": "main",
      "options": [
        {"value": "main", "label": "主站 (mangacopy.com)"},
        {"value": "hotmanga", "label": "热辣漫画"},
        {"value": "mirror1", "label": "镜像站1"}
      ],
      "dynamic": true
    }
  }
}
```

**实现位置**: `Framework/WebView/ConfigurationParser.ets`

**实现代码**:
```typescript
class DynamicConfigResolver {
  resolveUrl(template: string, settings: Record<string, string>): string {
    // 替换 {{baseUrl}} 为实际选择的域名
    const domain = settings['apiDomain'] || 'main';
    const baseUrl = domain === 'main' 
      ? this.config.metadata.baseUrl 
      : this.config.metadata.alternativeUrls[domain];
    
    return template.replace(/\{\{baseUrl\}\}/g, baseUrl);
  }
}
```

### 1.2 运行时设置管理

**新增接口**: `Framework/Data/DataManager.ets`

```typescript
/**
 * 获取图源的动态设置值
 */
async getSourceDynamicSetting(sourceId: number, key: string): Promise<string | null> {
  const settingKey = `source:${sourceId}:dynamic:${key}`;
  const record = await this.getSetting(settingKey);
  return record?.settingValue || null;
}

/**
 * 保存图源的动态设置值
 */
async saveSourceDynamicSetting(sourceId: number, key: string, value: string): Promise<void> {
  const settingKey = `source:${sourceId}:dynamic:${key}`;
  await this.saveSetting(settingKey, value, 'string');
}
```

## 二、文本处理系统

### 2.1 简繁转换

**Schema扩展**:
```json
{
  "textProcessing": {
    "chineseConversion": {
      "enabled": true,
      "direction": "auto",
      "applyTo": ["title", "description", "chapterTitle", "tags"],
      "variant": "zh-CN"
    }
  }
}
```

**实现**: 新建 `Framework/Utils/ChineseConverter.ets`

```typescript
/**
 * 简繁转换工具类
 */
export class ChineseConverter {
  private static conversionMap: Map<string, string> = new Map();
  
  /**
   * 简体转繁体
   */
  static simplifiedToTraditional(text: string): string {
    // 实现简繁转换逻辑
    // 可以使用预定义的字符映射表
    let result = text;
    this.conversionMap.forEach((traditional, simplified) => {
      result = result.replace(new RegExp(simplified, 'g'), traditional);
    });
    return result;
  }
  
  /**
   * 繁体转简体
   */
  static traditionalToSimplified(text: string): string {
    let result = text;
    this.conversionMap.forEach((traditional, simplified) => {
      result = result.replace(new RegExp(traditional, 'g'), simplified);
    });
    return result;
  }
  
  /**
   * 自动检测并转换
   */
  static autoConvert(text: string, targetVariant: 'zh-CN' | 'zh-TW'): string {
    if (targetVariant === 'zh-CN') {
      return this.traditionalToSimplified(text);
    } else {
      return this.simplifiedToTraditional(text);
    }
  }
}
```

### 2.2 文本清洗

**Schema扩展**:
```json
{
  "textProcessing": {
    "cleaning": {
      "enabled": true,
      "rules": [
        {"type": "trim"},
        {"type": "removeHtml"},
        {"type": "normalizeWhitespace"},
        {"type": "removeEmoji", "optional": true}
      ]
    }
  }
}
```

## 三、高级认证系统

### 3.1 会话管理

**Schema扩展**:
```json
{
  "authentication": {
    "type": "session",
    "loginWorkflow": "login",
    "sessionRefresh": {
      "enabled": true,
      "workflow": "refreshSession",
      "interval": 3600000,
      "checkExpiry": true,
      "expiryIndicators": [
        {"type": "cookie", "name": "sid", "checkExpiry": true},
        {"type": "response", "statusCode": 401}
      ]
    },
    "logout": {
      "workflow": "logout",
      "clearCookies": true
    }
  },
  "workflows": {
    "login": [...],
    "refreshSession": [...],
    "logout": [...]
  }
}
```

**实现**: 扩展 `Framework/WebView/WebViewAuthManager.ets`

```typescript
/**
 * 会话管理器
 */
class SessionManager {
  private refreshTimers: Map<number, number> = new Map();
  
  /**
   * 启动会话自动刷新
   */
  async startSessionRefresh(sourceId: number, config: SessionRefreshConfig): Promise<void> {
    const interval = config.interval || 3600000; // 默认1小时
    
    const timerId = setInterval(async () => {
      try {
        await this.refreshSession(sourceId, config.workflow);
        logger.info('SessionManager', `会话刷新成功: sourceId=${sourceId}`);
      } catch (e) {
        logger.error('SessionManager', `会话刷新失败: ${e}`);
      }
    }, interval);
    
    this.refreshTimers.set(sourceId, timerId);
  }
  
  /**
   * 停止会话刷新
   */
  stopSessionRefresh(sourceId: number): void {
    const timerId = this.refreshTimers.get(sourceId);
    if (timerId) {
      clearInterval(timerId);
      this.refreshTimers.delete(sourceId);
    }
  }
  
  /**
   * 检查会话是否过期
   */
  async isSessionExpired(sourceId: number, indicators: ExpiryIndicator[]): Promise<boolean> {
    for (const indicator of indicators) {
      if (indicator.type === 'cookie') {
        const cookieInfo = await CookieManager.getInstance().getCookieInfo(sourceId);
        if (!cookieInfo.hasCookie) {
          return true;
        }
      }
    }
    return false;
  }
}
```

### 3.2 书柜同步

**Schema扩展**:
```json
{
  "features": {
    "bookshelf": {
      "enabled": true,
      "requiresLogin": true,
      "workflow": "getBookshelf",
      "syncInterval": 86400000
    }
  },
  "workflows": {
    "getBookshelf": [
      {
        "type": "api",
        "method": "GET",
        "url": "{{baseUrl}}/api/user/bookshelf",
        "requiresAuth": true,
        "extract": {
          "type": "json",
          "path": "data.comics",
          "fields": {
            "id": "id",
            "title": "title",
            "lastReadChapter": "lastReadChapter"
          }
        }
      }
    ]
  }
}
```

## 四、网络增强

### 4.1 User-Agent轮换

**Schema扩展**:
```json
{
  "network": {
    "userAgentRotation": {
      "enabled": true,
      "strategy": "random",
      "pool": [
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
      ],
      "rotateInterval": 10,
      "persistPerSession": true
    }
  }
}
```

**实现**: 新建 `Framework/Network/UserAgentManager.ets`

```typescript
export class UserAgentManager {
  private static instance: UserAgentManager;
  private currentIndex: Map<number, number> = new Map();
  private requestCount: Map<number, number> = new Map();
  
  /**
   * 获取User-Agent
   */
  getUserAgent(sourceId: number, config: UserAgentRotationConfig): string {
    if (!config.enabled || !config.pool || config.pool.length === 0) {
      return config.pool?.[0] || this.getDefaultUserAgent();
    }
    
    const count = this.requestCount.get(sourceId) || 0;
    this.requestCount.set(sourceId, count + 1);
    
    // 根据策略选择UA
    if (config.strategy === 'random') {
      const index = Math.floor(Math.random() * config.pool.length);
      return config.pool[index];
    } else if (config.strategy === 'sequential') {
      const index = this.currentIndex.get(sourceId) || 0;
      const ua = config.pool[index];
      
      // 根据轮换间隔更新索引
      if (count % (config.rotateInterval || 10) === 0) {
        this.currentIndex.set(sourceId, (index + 1) % config.pool.length);
      }
      
      return ua;
    }
    
    return config.pool[0];
  }
  
  private getDefaultUserAgent(): string {
    return 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36';
  }
}
```

### 4.2 请求频率控制

**Schema扩展**:
```json
{
  "network": {
    "rateLimit": {
      "enabled": true,
      "requestsPerSecond": 2,
      "burstSize": 5,
      "strategy": "token_bucket"
    }
  }
}
```

**实现**: 新建 `Framework/Network/RateLimiter.ets`

```typescript
export class RateLimiter {
  private tokens: Map<number, number> = new Map();
  private lastRefill: Map<number, number> = new Map();
  
  /**
   * 检查是否可以发送请求
   */
  async checkLimit(sourceId: number, config: RateLimitConfig): Promise<boolean> {
    if (!config.enabled) {
      return true;
    }
    
    const now = Date.now();
    const lastTime = this.lastRefill.get(sourceId) || now;
    const elapsed = now - lastTime;
    
    // 补充令牌
    const tokensToAdd = (elapsed / 1000) * config.requestsPerSecond;
    let currentTokens = (this.tokens.get(sourceId) || config.burstSize) + tokensToAdd;
    currentTokens = Math.min(currentTokens, config.burstSize);
    
    if (currentTokens >= 1) {
      this.tokens.set(sourceId, currentTokens - 1);
      this.lastRefill.set(sourceId, now);
      return true;
    }
    
    // 等待直到有令牌可用
    const waitTime = (1 - currentTokens) / config.requestsPerSecond * 1000;
    await this.sleep(waitTime);
    
    this.tokens.set(sourceId, 0);
    this.lastRefill.set(sourceId, Date.now());
    return true;
  }
  
  private async sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}
```

## 五、分页系统增强

### 5.1 多种分页类型

**Schema扩展**:
```json
{
  "pagination": {
    "type": "cursor",
    "config": {
      "cursorField": "nextCursor",
      "hasMoreField": "hasNext",
      "initialCursor": null,
      "pageSize": 20,
      "maxPages": 100
    }
  }
}
```

**实现**: 扩展 `Framework/WebView/MangaSourceActionEngine.ets`

```typescript
class PaginationHandler {
  /**
   * 处理基于cursor的分页
   */
  handleCursorPagination(response: any, config: CursorPaginationConfig): PaginationResult {
    const nextCursor = this.extractField(response, config.cursorField);
    const hasMore = this.extractField(response, config.hasMoreField);
    
    return {
      hasMore: hasMore === true,
      nextCursor: nextCursor,
      currentPage: null
    };
  }
  
  /**
   * 处理基于offset的分页
   */
  handleOffsetPagination(currentOffset: number, config: OffsetPaginationConfig): PaginationResult {
    const nextOffset = currentOffset + config.pageSize;
    const hasMore = nextOffset < (config.maxItems || Infinity);
    
    return {
      hasMore: hasMore,
      nextOffset: nextOffset,
      currentPage: Math.floor(currentOffset / config.pageSize)
    };
  }
}
```

## 六、错误处理增强

### 6.1 智能重试

**Schema扩展**:
```json
{
  "errorHandling": {
    "retry": {
      "enabled": true,
      "maxAttempts": 3,
      "strategy": "exponential",
      "baseDelay": 1000,
      "maxDelay": 30000,
      "retryOn": {
        "statusCodes": [408, 429, 500, 502, 503, 504],
        "errors": ["TIMEOUT", "NETWORK_ERROR"]
      }
    },
    "fallback": {
      "enabled": true,
      "strategies": [
        {"type": "alternativeUrl", "url": "{{alternativeUrls.mirror1}}"},
        {"type": "webview"},
        {"type": "cache"}
      ]
    }
  }
}
```

**实现**: 新建 `Framework/Network/ErrorHandler.ets`

```typescript
export class ErrorHandler {
  /**
   * 执行带重试的请求
   */
  async executeWithRetry<T>(
    operation: () => Promise<T>,
    config: RetryConfig
  ): Promise<T> {
    let lastError: Error | null = null;
    
    for (let attempt = 0; attempt < config.maxAttempts; attempt++) {
      try {
        return await operation();
      } catch (error) {
        lastError = error as Error;
        
        if (!this.shouldRetry(error, config, attempt)) {
          throw error;
        }
        
        const delay = this.calculateDelay(attempt, config);
        logger.warn('ErrorHandler', `请求失败，${delay}ms后重试 (${attempt + 1}/${config.maxAttempts})`);
        await this.sleep(delay);
      }
    }
    
    throw lastError;
  }
  
  /**
   * 计算重试延迟
   */
  private calculateDelay(attempt: number, config: RetryConfig): number {
    if (config.strategy === 'exponential') {
      const delay = config.baseDelay * Math.pow(2, attempt);
      return Math.min(delay, config.maxDelay);
    } else if (config.strategy === 'linear') {
      return config.baseDelay;
    }
    return config.baseDelay;
  }
  
  /**
   * 判断是否应该重试
   */
  private shouldRetry(error: any, config: RetryConfig, attempt: number): boolean {
    if (attempt >= config.maxAttempts - 1) {
      return false;
    }
    
    // 检查状态码
    if (error.statusCode && config.retryOn.statusCodes.includes(error.statusCode)) {
      return true;
    }
    
    // 检查错误类型
    if (error.type && config.retryOn.errors.includes(error.type)) {
      return true;
    }
    
    return false;
  }
}
```

## 七、图片处理增强

### 7.1 URL解密/转换

**Schema扩展**:
```json
{
  "imageProcessing": {
    "urlDecryption": {
      "enabled": true,
      "method": "custom",
      "script": "function decrypt(url) { return atob(url.replace(/-/g, '+').replace(/_/g, '/')); }"
    },
    "urlTransform": {
      "enabled": true,
      "rules": [
        {"pattern": "/thumb/", "replacement": "/original/"},
        {"pattern": "http://", "replacement": "https://"}
      ]
    },
    "headers": {
      "Referer": "{{baseUrl}}",
      "Accept": "image/avif,image/webp,image/png,image/jpeg,*/*"
    }
  }
}
```

**实现**: 新建 `Framework/Image/ImageUrlProcessor.ets`

```typescript
export class ImageUrlProcessor {
  /**
   * 处理图片URL
   */
  processImageUrl(url: string, config: ImageProcessingConfig): string {
    let processedUrl = url;
    
    // 解密
    if (config.urlDecryption?.enabled) {
      processedUrl = this.decryptUrl(processedUrl, config.urlDecryption);
    }
    
    // 转换
    if (config.urlTransform?.enabled) {
      processedUrl = this.transformUrl(processedUrl, config.urlTransform.rules);
    }
    
    return processedUrl;
  }
  
  /**
   * 解密URL
   */
  private decryptUrl(url: string, config: UrlDecryptionConfig): string {
    if (config.method === 'base64') {
      try {
        return atob(url);
      } catch (e) {
        logger.warn('ImageUrlProcessor', `Base64解密失败: ${e}`);
        return url;
      }
    } else if (config.method === 'custom' && config.script) {
      try {
        const decrypt = new Function('url', config.script);
        return decrypt(url);
      } catch (e) {
        logger.error('ImageUrlProcessor', `自定义解密失败: ${e}`);
        return url;
      }
    }
    return url;
  }
  
  /**
   * 转换URL
   */
  private transformUrl(url: string, rules: UrlTransformRule[]): string {
    let result = url;
    for (const rule of rules) {
      result = result.replace(new RegExp(rule.pattern, 'g'), rule.replacement);
    }
    return result;
  }
}
```

## 八、实施优先级

### P0 (立即实施)
1. ✅ Cookie管理修复（已完成）
2. 🔄 动态域名切换
3. 🔄 User-Agent轮换
4. 🔄 错误重试机制

### P1 (1周内)
5. 会话管理
6. 简繁转换
7. 请求频率控制
8. 分页增强

### P2 (2周内)
9. 图片URL处理
10. 书柜同步
11. 文本清洗
12. WebView增强

## 九、总结

这些增强功能将使我们的系统能够支持CopyManga等复杂图源。实施这些功能后，我们将拥有一个强大、灵活的图源系统，能够适应各种不同的图源需求。
