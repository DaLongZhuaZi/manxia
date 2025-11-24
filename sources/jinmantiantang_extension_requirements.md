# 禁漫天堂图源系统扩展需求文档

## 📋 概述

本文档详细说明为支持禁漫天堂图源所需的系统级扩展功能。这些扩展不仅适用于禁漫天堂，也可以为其他具有类似需求的图源提供支持。

---

## 1️⃣ 图片解扰系统 (Image Descrambler System)

### 1.1 需求背景

许多漫画网站为了防止爬虫和盗图，会对图片进行加密处理。禁漫天堂使用了一种基于 MD5 哈希的图片分割打乱算法，需要在客户端进行还原。

### 1.2 功能需求

#### **核心功能**

1. **算法注册系统**
   - 支持多种解扰算法（jinmantiantang, custom, etc.）
   - 动态注册和卸载算法
   - 算法版本管理

2. **图片拦截器**
   - 拦截特定 URL 模式的图片请求
   - 在图片加载前/后进行处理
   - 支持同步和异步处理

3. **算法执行引擎**
   - MD5/SHA256 等哈希计算
   - 图片分割和重组
   - 像素级操作支持

4. **缓存管理**
   - 解扰后图片缓存
   - LRU 缓存策略
   - 缓存大小限制

#### **配置结构**

```typescript
interface ImageDescramblerConfig {
  // 基础配置
  enabled: boolean;
  algorithm: string;  // 'jinmantiantang' | 'custom'
  
  // URL 匹配
  urlPattern: string | RegExp;
  
  // 算法参数
  parameters: {
    scrambleIdThreshold?: number;
    modulusRules?: Array<{
      minAid: number;
      modulus: number;
    }>;
    [key: string]: any;
  };
  
  // 输出配置
  outputFormat: 'jpeg' | 'png' | 'webp';
  outputQuality: number;  // 1-100
  
  // 性能配置
  cacheEnabled: boolean;
  cacheSizeLimit: number;  // MB
  parallelProcessing: boolean;
  maxWorkers: number;
}
```

#### **API 设计**

```typescript
// 注册解扰算法
interface DescramblerAlgorithm {
  name: string;
  version: string;
  descramble(
    imageData: ArrayBuffer,
    parameters: any
  ): Promise<ArrayBuffer>;
}

class ImageDescramblerRegistry {
  register(algorithm: DescramblerAlgorithm): void;
  unregister(name: string): void;
  get(name: string): DescramblerAlgorithm | null;
  list(): string[];
}

// 图片拦截器
class ImageInterceptor {
  addInterceptor(
    sourceId: string,
    config: ImageDescramblerConfig
  ): void;
  
  removeInterceptor(sourceId: string): void;
  
  intercept(
    url: string,
    sourceId: string,
    imageData: ArrayBuffer
  ): Promise<ArrayBuffer>;
}
```

### 1.3 实现优先级

**P0 (必须):**
- 基础拦截器框架
- 禁漫天堂算法实现
- 缓存系统

**P1 (重要):**
- 并行处理支持
- 性能监控
- 错误恢复

**P2 (可选):**
- 自定义算法支持
- 算法热更新
- 统计分析

### 1.4 技术挑战

1. **性能问题**
   - 图片解扰是 CPU 密集型操作
   - 需要优化内存使用
   - 考虑使用 Worker 线程

2. **兼容性**
   - 不同设备的图像处理能力差异
   - 需要降级方案

3. **调试困难**
   - 算法错误难以定位
   - 需要完善的日志系统

---

## 2️⃣ Base64 解码系统 (Base64 Decoding System)

### 2.1 需求背景

部分网站使用 Base64 编码隐藏页面内容，需要在 WebView 中动态解码并注入 DOM。

### 2.2 功能需求

#### **核心功能**

1. **脚本查找**
   - 支持 CSS 选择器查找
   - 支持正则表达式匹配
   - 支持多个脚本标签

2. **内容提取**
   - 提取 Base64 编码字符串
   - 支持多种编码格式
   - 验证编码有效性

3. **DOM 注入**
   - 支持多种注入位置
   - 保持页面结构完整
   - 触发必要的事件

4. **错误处理**
   - 解码失败回退
   - 注入失败恢复
   - 详细错误日志

#### **配置结构**

```typescript
interface Base64DecodeConfig {
  // 查找配置
  selector: string;  // CSS 选择器
  pattern: string | RegExp;  // 提取模式
  
  // 注入配置
  injectTarget: string;  // 注入目标选择器
  injectPosition: 'beforebegin' | 'afterbegin' | 'beforeend' | 'afterend';
  
  // 选项
  multiple: boolean;  // 是否处理多个匹配
  validateHtml: boolean;  // 验证 HTML 有效性
  triggerEvents: boolean;  // 触发 DOM 事件
}
```

#### **工作流动作**

```json
{
  "type": "base64Decode",
  "selector": "#wrapper > script:contains(base64DecodeUtf8)",
  "pattern": "base64DecodeUtf8\\(\"([^\"]+)\"\\)",
  "injectTarget": "body",
  "injectPosition": "beforeend",
  "multiple": true,
  "validateHtml": true,
  "triggerEvents": false
}
```

#### **JavaScript 实现**

```javascript
function base64Decode(config) {
  const scripts = document.querySelectorAll(config.selector);
  let decodedCount = 0;
  
  for (const script of scripts) {
    const code = script.innerHTML;
    const regex = new RegExp(config.pattern);
    const match = code.match(regex);
    
    if (match && match[1]) {
      try {
        const decoded = atob(match[1]);
        
        // 验证 HTML
        if (config.validateHtml) {
          const parser = new DOMParser();
          const doc = parser.parseFromString(decoded, 'text/html');
          if (doc.body.querySelector('parsererror')) {
            throw new Error('Invalid HTML');
          }
        }
        
        // 注入 DOM
        const target = document.querySelector(config.injectTarget);
        if (target) {
          target.insertAdjacentHTML(config.injectPosition, decoded);
          decodedCount++;
          
          // 触发事件
          if (config.triggerEvents) {
            target.dispatchEvent(new Event('contentLoaded'));
          }
        }
        
        if (!config.multiple) break;
      } catch (error) {
        console.error('[Base64解码] 失败:', error);
      }
    }
  }
  
  return {
    success: decodedCount > 0,
    count: decodedCount
  };
}
```

### 2.3 实现优先级

**P0 (必须):**
- 基础解码功能
- DOM 注入
- 错误处理

**P1 (重要):**
- HTML 验证
- 多脚本支持
- 性能优化

**P2 (可选):**
- 自定义解码函数
- 解码结果缓存
- 调试工具

---

## 3️⃣ 动态域名管理系统 (Dynamic Domain Management)

### 3.1 需求背景

许多漫画网站因为版权和监管原因频繁更换域名，需要自动更新和切换域名的能力。

### 3.2 功能需求

#### **核心功能**

1. **域名池管理**
   - 静态域名配置
   - 动态域名更新
   - 域名优先级

2. **自动更新**
   - 从远程 URL 获取域名列表
   - 定期自动更新
   - 手动触发更新

3. **故障转移**
   - 自动检测域名可用性
   - 失败时自动切换
   - 用户手动切换

4. **持久化存储**
   - 保存域名列表
   - 保存当前域名
   - 保存更新时间

#### **配置结构**

```typescript
interface DomainConfig {
  // 静态域名
  staticDomains: Array<{
    value: string;
    label: string;
    priority: number;
  }>;
  
  // 动态更新
  autoUpdate: {
    enabled: boolean;
    url: string;
    format: 'text' | 'json';
    separator?: string;
    updateInterval: number;  // 毫秒
  };
  
  // 故障转移
  failover: {
    enabled: boolean;
    autoSwitch: boolean;
    testTimeout: number;
    notifyUser: boolean;
  };
}
```

#### **API 设计**

```typescript
class DomainManager {
  // 初始化
  constructor(sourceId: string, config: DomainConfig);
  async initialize(): Promise<void>;
  
  // 域名管理
  getCurrentDomain(): string;
  getAvailableDomains(): string[];
  async switchDomain(domain: string): Promise<void>;
  
  // 更新
  async updateDomains(): Promise<string[]>;
  async testDomain(domain: string): Promise<boolean>;
  
  // 故障转移
  async autoFailover(): Promise<string>;
  
  // 事件
  onDomainChanged(callback: (domain: string) => void): void;
  onUpdateCompleted(callback: (domains: string[]) => void): void;
}
```

#### **远程域名列表格式**

**文本格式：**
```
domain1.com,domain2.com,domain3.com
```

**JSON 格式：**
```json
{
  "domains": [
    {"url": "domain1.com", "priority": 1},
    {"url": "domain2.com", "priority": 2}
  ],
  "updateTime": "2024-11-24T12:00:00Z"
}
```

### 3.3 实现优先级

**P0 (必须):**
- 域名池管理
- 手动切换
- 持久化存储

**P1 (重要):**
- 自动更新
- 故障转移
- 域名测试

**P2 (可选):**
- 智能选择（根据延迟）
- 域名统计
- 用户反馈

---

## 4️⃣ 速率限制系统 (Rate Limiting System)

### 4.1 需求背景

防止请求过于频繁导致 IP 被封禁，需要限制请求速率。

### 4.2 功能需求

#### **核心功能**

1. **请求计数**
   - 时间窗口内的请求数
   - 支持滑动窗口
   - 支持固定窗口

2. **限制策略**
   - 全局限制
   - 按图源限制
   - 按请求类型限制

3. **等待机制**
   - 自动等待
   - 队列管理
   - 优先级支持

4. **配置管理**
   - 动态调整限制
   - 用户自定义
   - 预设方案

#### **配置结构**

```typescript
interface RateLimitConfig {
  // 基础配置
  enabled: boolean;
  requests: number;  // 请求数
  period: number;  // 时间窗口（毫秒）
  
  // 策略
  scope: 'global' | 'per-source' | 'per-type';
  strategy: 'sliding' | 'fixed';
  
  // 行为
  behavior: 'wait' | 'reject' | 'queue';
  queueSize?: number;
  
  // 优先级
  priorities?: {
    [requestType: string]: number;
  };
}
```

#### **API 设计**

```typescript
class RateLimiter {
  constructor(config: RateLimitConfig);
  
  // 检查
  canRequest(sourceId: string, type?: string): boolean;
  
  // 记录
  recordRequest(sourceId: string, type?: string): void;
  
  // 等待
  async waitForSlot(sourceId: string, type?: string): Promise<void>;
  
  // 配置
  updateConfig(config: Partial<RateLimitConfig>): void;
  getStats(sourceId: string): RateLimitStats;
}

interface RateLimitStats {
  currentRequests: number;
  maxRequests: number;
  resetTime: number;
  queueLength: number;
}
```

#### **使用示例**

```typescript
// 在请求前检查
if (!rateLimiter.canRequest('jinmantiantang')) {
  await rateLimiter.waitForSlot('jinmantiantang');
}

// 发起请求
const response = await http.request(url);

// 记录请求
rateLimiter.recordRequest('jinmantiantang');
```

### 4.3 实现优先级

**P0 (必须):**
- 基础限流功能
- 等待机制
- 配置管理

**P1 (重要):**
- 队列管理
- 优先级支持
- 统计信息

**P2 (可选):**
- 自适应限流
- 智能调整
- 可视化监控

---

## 5️⃣ 标签过滤系统 (Genre Filter System)

### 5.1 需求背景

用户希望屏蔽某些不感兴趣或不适宜的内容标签。

### 5.2 功能需求

#### **核心功能**

1. **标签匹配**
   - 精确匹配
   - 模糊匹配
   - 正则表达式

2. **过滤规则**
   - 黑名单模式
   - 白名单模式
   - 组合规则

3. **应用范围**
   - 列表页过滤
   - 搜索结果过滤
   - 推荐过滤

4. **用户配置**
   - 自定义标签列表
   - 预设方案
   - 导入导出

#### **配置结构**

```typescript
interface GenreFilterConfig {
  // 基础配置
  enabled: boolean;
  mode: 'blacklist' | 'whitelist';
  
  // 标签列表
  genres: string[];
  
  // 匹配选项
  caseSensitive: boolean;
  fuzzyMatch: boolean;
  useRegex: boolean;
  
  // 应用范围
  applyTo: {
    list: boolean;
    search: boolean;
    recommendation: boolean;
  };
}
```

#### **API 设计**

```typescript
class GenreFilter {
  constructor(config: GenreFilterConfig);
  
  // 过滤
  filterMangas(mangas: Manga[]): Manga[];
  shouldBlock(manga: Manga): boolean;
  
  // 配置
  updateConfig(config: Partial<GenreFilterConfig>): void;
  addGenre(genre: string): void;
  removeGenre(genre: string): void;
  
  // 预设
  loadPreset(name: string): void;
  savePreset(name: string): void;
}
```

#### **在工作流中使用**

```json
{
  "type": "extract",
  "selector": ".manga-item",
  "multiple": true,
  "fields": {
    "title": ".title::text",
    "genre": ".genre::text"
  },
  "postProcess": {
    "filterGenres": "{{settings.blockGenres}}",
    "filterMode": "blacklist"
  }
}
```

### 5.3 实现优先级

**P0 (必须):**
- 基础过滤功能
- 黑名单模式
- 用户配置

**P1 (重要):**
- 白名单模式
- 模糊匹配
- 预设方案

**P2 (可选):**
- 正则表达式
- 智能推荐
- 统计分析

---

## 6️⃣ 递归分页处理系统 (Recursive Pagination System)

### 6.1 需求背景

某些章节内容分布在多个页面，需要自动获取所有页面的内容。

### 6.2 功能需求

#### **核心功能**

1. **分页检测**
   - 自动检测下一页链接
   - 支持多种分页模式
   - 防止循环

2. **内容合并**
   - 自动合并结果
   - 去重处理
   - 保持顺序

3. **性能控制**
   - 限制最大页数
   - 并发控制
   - 超时处理

4. **进度反馈**
   - 实时进度
   - 取消支持
   - 错误恢复

#### **配置结构**

```typescript
interface RecursivePaginationConfig {
  // 基础配置
  enabled: boolean;
  nextPageSelector: string;
  
  // 限制
  maxPages: number;
  timeout: number;
  
  // 行为
  mergeResults: boolean;
  deduplicate: boolean;
  parallel: boolean;
  maxConcurrency?: number;
  
  // 停止条件
  stopOnError: boolean;
  stopOnEmpty: boolean;
}
```

#### **API 设计**

```typescript
class RecursivePaginator {
  constructor(config: RecursivePaginationConfig);
  
  // 执行
  async fetchAllPages(
    startUrl: string,
    extractor: (doc: Document) => any[]
  ): Promise<any[]>;
  
  // 控制
  cancel(): void;
  
  // 事件
  onProgress(callback: (current: number, total: number) => void): void;
  onPageFetched(callback: (page: number, items: any[]) => void): void;
}
```

#### **在工作流中使用**

```json
{
  "type": "extract",
  "selector": ".image-item",
  "multiple": true,
  "recursive": {
    "enabled": true,
    "nextPageSelector": "a.next-page",
    "maxPages": 50,
    "mergeResults": true,
    "deduplicate": true
  }
}
```

### 6.3 实现优先级

**P0 (必须):**
- 基础递归功能
- 内容合并
- 最大页数限制

**P1 (重要):**
- 并发控制
- 进度反馈
- 错误处理

**P2 (可选):**
- 智能预测
- 缓存优化
- 断点续传

---

## 7️⃣ 实施路线图

### 阶段 1：核心功能（4-6周）

**Week 1-3: 图片解扰系统**
- 拦截器框架
- 禁漫天堂算法
- 基础缓存

**Week 4-5: Base64 解码系统**
- 工作流扩展
- DOM 注入
- 错误处理

**Week 6: 集成测试**
- 端到端测试
- 性能测试
- 问题修复

### 阶段 2：高级功能（3-4周）

**Week 7-8: 动态域名管理**
- 域名池管理
- 自动更新
- 故障转移

**Week 9-10: 速率限制和标签过滤**
- 速率限制器
- 标签过滤器
- 用户配置

### 阶段 3：优化和完善（2-3周）

**Week 11-12: 性能优化**
- 并行处理
- 内存优化
- 缓存策略

**Week 13: 文档和发布**
- API 文档
- 用户手册
- 发布准备

---

## 8️⃣ 技术栈要求

### 必需技术

- **ArkTS**: 核心业务逻辑
- **@ohos.image**: 图片处理
- **@ohos.crypto**: 加密算法
- **@ohos.net.http**: 网络请求
- **@ohos.data.preferences**: 数据持久化

### 可选技术

- **Worker**: 并行处理
- **@ohos.taskpool**: 任务调度
- **@ohos.file.fs**: 文件缓存

---

## 9️⃣ 风险评估

### 高风险

1. **图片解扰性能**
   - 影响：用户体验差
   - 缓解：使用原生模块，优化算法

2. **内存占用**
   - 影响：应用崩溃
   - 缓解：及时释放资源，限制缓存大小

### 中风险

1. **域名更新失败**
   - 影响：无法访问
   - 缓解：本地域名池，手动切换

2. **速率限制过严**
   - 影响：加载缓慢
   - 缓解：可配置，智能调整

### 低风险

1. **标签过滤误判**
   - 影响：内容缺失
   - 缓解：用户可关闭，提供预览

---

## 🔟 总结

本文档详细描述了支持禁漫天堂图源所需的 6 个系统级扩展功能。这些功能不仅适用于禁漫天堂，也为其他图源提供了通用的解决方案。

**关键要点：**

1. **图片解扰是最大挑战**，需要在原生层实现
2. **模块化设计**，每个功能独立可测试
3. **性能优先**，考虑并行处理和缓存
4. **用户友好**，提供丰富的配置选项
5. **错误恢复**，完善的降级和重试机制

**预估工作量：** 9-13 周

**建议优先级：**
1. 图片解扰（P0）
2. Base64 解码（P0）
3. 动态域名管理（P1）
4. 速率限制（P1）
5. 标签过滤（P2）
6. 递归分页（P2）

---

**文档版本：** 1.0
**最后更新：** 2024-11-24
**作者：** ManXia Team
