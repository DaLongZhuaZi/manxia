# WebView系统增强功能实施报告

## 执行时间
2024-11-21 18:48 - 进行中

## 实施状态总览

| 功能 | 状态 | 进度 | 预计完成时间 |
|------|------|------|------------|
| 1. 动态域名切换 | 🔄 进行中 | 20% | 1-2天 |
| 2. 简繁转换 | ⏳ 待开始 | 0% | 1-2天 |
| 3. Cookie/会话管理 | ✅ 已完成 | 100% | - |
| 4. User-Agent轮换 | 🔄 进行中 | 80% | 0.5天 |
| 5. 分页策略 | ⏳ 待开始 | 0% | 1天 |
| 6. 错误处理 | 🔄 进行中 | 80% | 0.5天 |

**总体进度**: 47%

---

## Phase 1: 集成UserAgentManager和ErrorHandler ✅ 80%

### 已完成的工作

#### 1.1 创建UserAgentManager ✅
**文件**: `Framework/Network/UserAgentManager.ets`

**功能**:
- ✅ 单例模式实现
- ✅ 三种轮换策略（random, sequential, adaptive）
- ✅ 会话持久化
- ✅ 请求计数和自动轮换
- ✅ 7种预定义User-Agent

**代码示例**:
```typescript
const uaManager = UserAgentManager.getInstance();
const config = {
  enabled: true,
  strategy: 'random',
  pool: UserAgentManager.getCommonUserAgents(),
  persistPerSession: true
};
const ua = uaManager.getUserAgent(sourceId, config);
```

#### 1.2 创建ErrorHandler ✅
**文件**: `Framework/Network/ErrorHandler.ets`

**功能**:
- ✅ 智能重试机制（exponential, linear, fixed）
- ✅ 可配置重试条件
- ✅ 降级策略框架
- ✅ 操作跟踪和日志

**代码示例**:
```typescript
const errorHandler = ErrorHandler.getInstance();
const config = ErrorHandler.createDefaultRetryConfig();
const result = await errorHandler.executeWithRetry(
  async () => await fetchData(),
  config
);
```

#### 1.3 集成到MangaSourceAPIEngine ✅
**文件**: `Framework/WebView/MangaSourceAPIEngine.ets`

**修改内容**:
```typescript
// 1. 导入模块
import UserAgentManager from '../Network/UserAgentManager';
import ErrorHandler from '../Network/ErrorHandler';

// 2. 修改request方法签名
async request(
  config: APIRequestConfig, 
  sourceId?: number, 
  uaRotationConfig?: any
): Promise<APIResponse>

// 3. 集成ErrorHandler包装请求
const errorHandler = ErrorHandler.getInstance();
const retryConfig = ErrorHandler.createDefaultRetryConfig();

return await errorHandler.executeWithRetry(async () => {
  // 原有请求逻辑
  
  // 4. 集成UserAgentManager
  if (sourceId !== undefined && uaRotationConfig) {
    const uaManager = UserAgentManager.getInstance();
    const ua = uaManager.getUserAgent(sourceId, uaRotationConfig);
    headers['User-Agent'] = ua;
  }
  
  // ... 其余请求逻辑
}, retryConfig);
```

### 待完成的工作

#### 1.4 更新调用方 ⏳
需要更新所有调用`MangaSourceAPIEngine.request()`的地方，传入`sourceId`和`uaRotationConfig`参数。

**影响文件**:
- `MangaSourceActionEngine.ets`
- `MangaSourceEngine.ets`
- 其他调用API引擎的地方

**修改示例**:
```typescript
// 旧代码
const response = await apiEngine.request(config);

// 新代码
const response = await apiEngine.request(
  config,
  sourceId,
  workflowConfig.userAgentRotation
);
```

---

## Phase 2: 实现动态域名切换 ⏳ 20%

### 设计方案

#### 2.1 扩展配置Schema
```typescript
// 在DynamicObject中添加
interface DynamicObject {
  baseUrl?: string;
  alternativeUrls?: Record<string, string>;
}

// 在配置中使用
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
      "default": "main",
      "options": [
        {"value": "main", "label": "主站"},
        {"value": "hotmanga", "label": "热辣漫画"},
        {"value": "mirror1", "label": "镜像站1"}
      ]
    }
  }
}
```

#### 2.2 创建DynamicUrlResolver
**新文件**: `Framework/Utils/DynamicUrlResolver.ets`

```typescript
export class DynamicUrlResolver {
  /**
   * 解析URL模板，替换变量
   */
  resolveUrl(
    template: string, 
    baseUrl: string,
    alternativeUrls: Record<string, string>,
    settings: Record<string, string>
  ): string {
    let url = template;
    
    // 解析域名选择
    const domainSetting = settings['apiDomain'] || 'main';
    const actualBaseUrl = domainSetting === 'main' 
      ? baseUrl 
      : alternativeUrls[domainSetting] || baseUrl;
    
    // 替换{{baseUrl}}
    url = url.replace(/\{\{baseUrl\}\}/g, actualBaseUrl);
    
    // 替换其他变量
    Object.keys(settings).forEach(key => {
      const pattern = new RegExp(`\\{\\{${key}\\}\\}`, 'g');
      url = url.replace(pattern, settings[key]);
    });
    
    return url;
  }
}
```

#### 2.3 集成到ConfigurationParser
修改`ConfigurationParser.ets`，在解析配置时使用`DynamicUrlResolver`。

### 实施步骤
1. ⏳ 创建DynamicUrlResolver类
2. ⏳ 扩展ConfigurationParser支持alternativeUrls
3. ⏳ 修改MangaSourceEngine使用动态URL
4. ⏳ 更新copymanga.json配置
5. ⏳ 测试域名切换功能

---

## Phase 3: 实现简繁转换 ⏳ 0%

### 设计方案

#### 3.1 创建ChineseConverter
**新文件**: `Framework/Utils/ChineseConverter.ets`

```typescript
export class ChineseConverter {
  private static s2tMap: Map<string, string> = new Map();
  private static t2sMap: Map<string, string> = new Map();
  
  /**
   * 初始化转换表
   */
  static initialize(): void {
    // 加载简繁转换映射表
    // 可以使用预定义的常用字符映射
  }
  
  /**
   * 简体转繁体
   */
  static simplifiedToTraditional(text: string): string {
    let result = text;
    this.s2tMap.forEach((traditional, simplified) => {
      result = result.replace(new RegExp(simplified, 'g'), traditional);
    });
    return result;
  }
  
  /**
   * 繁体转简体
   */
  static traditionalToSimplified(text: string): string {
    let result = text;
    this.t2sMap.forEach((simplified, traditional) => {
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

#### 3.2 配置Schema扩展
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

#### 3.3 集成到数据提取流程
在`MangaSourceActionEngine.ets`的数据提取方法中应用转换。

### 实施步骤
1. ⏳ 创建ChineseConverter类
2. ⏳ 准备简繁转换映射表
3. ⏳ 扩展配置Schema
4. ⏳ 集成到数据提取流程
5. ⏳ 测试转换功能

---

## Phase 4: 改进分页策略 ⏳ 0%

### 设计方案

#### 4.1 分页配置Schema
```typescript
interface PaginationConfig {
  type: 'offset' | 'page' | 'cursor';
  pageSize: number;
  maxPages?: number;
  
  // cursor分页特有
  cursorField?: string;
  hasMoreField?: string;
  initialCursor?: string | null;
}
```

#### 4.2 创建PaginationHandler
**新文件**: `Framework/Utils/PaginationHandler.ets`

```typescript
export interface PaginationResult {
  hasMore: boolean;
  nextCursor?: string;
  nextOffset?: number;
  currentPage?: number;
}

export class PaginationHandler {
  /**
   * 处理cursor分页
   */
  handleCursorPagination(
    response: any, 
    config: PaginationConfig
  ): PaginationResult {
    const nextCursor = this.extractField(response, config.cursorField!);
    const hasMore = this.extractField(response, config.hasMoreField!);
    
    return {
      hasMore: hasMore === true,
      nextCursor: nextCursor
    };
  }
  
  /**
   * 处理offset分页
   */
  handleOffsetPagination(
    currentOffset: number, 
    config: PaginationConfig
  ): PaginationResult {
    const nextOffset = currentOffset + config.pageSize;
    const maxItems = config.maxPages ? config.maxPages * config.pageSize : Infinity;
    
    return {
      hasMore: nextOffset < maxItems,
      nextOffset: nextOffset,
      currentPage: Math.floor(currentOffset / config.pageSize)
    };
  }
  
  /**
   * 处理page分页
   */
  handlePagePagination(
    currentPage: number, 
    config: PaginationConfig
  ): PaginationResult {
    const nextPage = currentPage + 1;
    
    return {
      hasMore: config.maxPages ? nextPage <= config.maxPages : true,
      currentPage: nextPage
    };
  }
}
```

### 实施步骤
1. ⏳ 创建PaginationHandler类
2. ⏳ 扩展配置Schema
3. ⏳ 修改MangaSourceEngine集成分页处理
4. ⏳ 更新现有图源配置
5. ⏳ 测试各种分页方式

---

## Phase 5: 添加会话管理 ⏳ 0%

### 设计方案

#### 5.1 创建SessionManager
**新文件**: `Framework/Managers/SessionManager.ets`

```typescript
export interface SessionRefreshConfig {
  enabled: boolean;
  interval: number;
  workflow: string;
  checkExpiry: boolean;
}

export class SessionManager {
  private static instance: SessionManager;
  private refreshTimers: Map<number, number> = new Map();
  
  /**
   * 启动会话自动刷新
   */
  async startSessionRefresh(
    sourceId: number, 
    config: SessionRefreshConfig
  ): Promise<void> {
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
   * 刷新会话
   */
  private async refreshSession(
    sourceId: number, 
    workflow: string
  ): Promise<void> {
    // 执行刷新工作流
    // 调用MangaSourceEngine执行指定workflow
  }
}
```

#### 5.2 配置Schema
```json
{
  "authentication": {
    "type": "session",
    "sessionRefresh": {
      "enabled": true,
      "workflow": "refreshSession",
      "interval": 3600000,
      "checkExpiry": true
    }
  },
  "workflows": {
    "refreshSession": [
      {
        "type": "api",
        "method": "POST",
        "url": "{{baseUrl}}/auth/refresh"
      }
    ]
  }
}
```

### 实施步骤
1. ⏳ 创建SessionManager类
2. ⏳ 扩展配置Schema
3. ⏳ 集成到WebViewAuthManager
4. ⏳ 添加会话过期检测
5. ⏳ 测试自动刷新功能

---

## 测试计划

### 单元测试
- [ ] UserAgentManager轮换策略测试
- [ ] ErrorHandler重试机制测试
- [ ] DynamicUrlResolver URL解析测试
- [ ] ChineseConverter转换准确性测试
- [ ] PaginationHandler分页逻辑测试

### 集成测试
- [ ] API请求带UA轮换测试
- [ ] 错误重试流程测试
- [ ] 域名切换功能测试
- [ ] 简繁转换端到端测试
- [ ] 分页加载测试

### 性能测试
- [ ] UA轮换性能影响
- [ ] 重试机制延迟测试
- [ ] 简繁转换性能测试

---

## 风险和问题

### 当前问题
1. ⚠️ MangaSourceAPIEngine的调用方需要更新
2. ⚠️ 简繁转换映射表需要准备
3. ⚠️ 分页策略变更可能影响现有图源

### 缓解措施
1. 保持向后兼容，参数设为可选
2. 使用常用字符映射表，逐步完善
3. 逐步迁移，保留旧的分页方式

---

## 下一步行动

### 立即执行
1. ✅ 完成UserAgentManager和ErrorHandler集成
2. 🔄 更新MangaSourceActionEngine调用API引擎的代码
3. 🔄 创建DynamicUrlResolver

### 今天完成
4. 创建ChineseConverter基础版本
5. 测试UA轮换和错误重试

### 明天完成
6. 完成动态域名切换
7. 完成简繁转换集成
8. 开始分页策略改进

---

## 总结

### 已完成
- ✅ UserAgentManager实现
- ✅ ErrorHandler实现
- ✅ 集成到MangaSourceAPIEngine
- ✅ Cookie管理系统（之前完成）

### 进行中
- 🔄 更新调用方代码
- 🔄 动态域名切换设计

### 待开始
- ⏳ 简繁转换
- ⏳ 分页策略改进
- ⏳ 会话管理

### 预计完成时间
- **Phase 1**: 今天晚上
- **Phase 2-3**: 明天
- **Phase 4-5**: 后天
- **总计**: 2-3天完成所有功能

**当前进度**: 47% → 预计明天达到80% → 后天完成100%
