# CopyManga图源移植分析报告

## 一、CopyManga图源概述

### 基本信息
- **名称**: 拷贝漫画 (CopyManga)
- **当前版本**: v1.4.76
- **基础URL**: https://www.mangacopy.com (原https://www.copy20.com)
- **语言**: 中文 (zh)
- **类型**: Tachiyomi扩展插件 (Android APK)
- **NSFW**: 是
- **维护状态**: 活跃（社区维护版本）

### 技术架构
- **原始格式**: Tachiyomi Extension (Kotlin/Java)
- **当前形式**: 反编译的Smali代码
- **包名**: `eu.kanade.tachiyomi.extension.zh.copymanga`
- **主类**: `CopyManga`

### 特点
1. 支持热辣漫画（可切换API域名）
2. 支持获取源站书柜漫画（需登录）
3. 处理简繁转换
4. 需要特定User-Agent避免限制（只能看5页问题）
5. 支持单行本和普通章节

## 二、移植可行性分析

### 🔴 **直接移植：不可行**

#### 原因
1. **平台差异**
   - 源代码：Android (Kotlin/Java) + Tachiyomi框架
   - 目标平台：HarmonyOS (ArkTS)
   - 无法直接运行APK或Smali代码

2. **代码形式**
   - 当前只有反编译的Smali代码
   - 没有原始Kotlin/Java源码
   - Smali代码难以理解和转换

3. **框架依赖**
   - 依赖Tachiyomi扩展框架
   - 使用Android特定API
   - 我们的系统是JSON配置驱动

### 🟢 **逆向工程后重新实现：可行**

#### 方法
通过分析APK的网络请求和API调用，重新实现为我们的JSON配置格式。

## 三、需要的增强设计

### 当前系统能力评估

#### ✅ 已支持的功能
1. **API类型**
   - REST API
   - GraphQL API
   - HTML解析
   - 自定义API

2. **认证方式**
   - Cookie管理（已修复）
   - 自定义Headers
   - User-Agent设置

3. **数据提取**
   - JSON路径提取
   - HTML选择器
   - 正则表达式

4. **工作流**
   - 初始化流程
   - 多步骤操作
   - 条件判断

#### ❌ 缺失的功能

### 1. **动态域名切换**
**需求**: CopyManga支持在拷贝漫画和热辣漫画之间切换API域名

**当前问题**: 
- 我们的`baseUrl`是静态的
- 没有运行时切换域名的机制

**增强方案**:
```json
{
  "metadata": {
    "baseUrl": "https://www.mangacopy.com",
    "alternativeUrls": {
      "hotmanga": "https://www.hotmanga.com"
    }
  },
  "settings": {
    "apiDomain": {
      "type": "select",
      "name": "API域名",
      "default": "mangacopy",
      "options": [
        {"value": "mangacopy", "label": "拷贝漫画"},
        {"value": "hotmanga", "label": "热辣漫画"}
      ]
    }
  }
}
```

### 2. **简繁转换支持**
**需求**: 自动处理简体/繁体中文转换

**当前问题**: 
- 没有文本转换功能
- 可能导致章节匹配失败

**增强方案**:
```json
{
  "textProcessing": {
    "chineseConversion": {
      "enabled": true,
      "direction": "auto",  // auto, s2t, t2s
      "applyTo": ["title", "description", "chapterTitle"]
    }
  }
}
```

### 3. **高级Cookie管理**
**需求**: 
- 登录后获取书柜漫画
- 处理会话过期
- 自动刷新Cookie

**当前状态**: 
- 基础Cookie管理已实现
- 缺少会话管理

**增强方案**:
```json
{
  "authentication": {
    "type": "session",
    "loginUrl": "{{baseUrl}}/login",
    "sessionRefresh": {
      "enabled": true,
      "url": "{{baseUrl}}/auth/refresh",
      "interval": 3600000,
      "checkExpiry": true
    },
    "bookshelf": {
      "enabled": true,
      "requiresLogin": true,
      "url": "{{baseUrl}}/api/user/bookshelf"
    }
  }
}
```

### 4. **User-Agent轮换**
**需求**: 避免被限制（5页问题）

**当前问题**: 
- User-Agent是静态的
- 没有轮换机制

**增强方案**:
```json
{
  "network": {
    "userAgentRotation": {
      "enabled": true,
      "pool": [
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36...",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)...",
        "Mozilla/5.0 (X11; Linux x86_64)..."
      ],
      "strategy": "random"  // random, sequential, adaptive
    }
  }
}
```

### 5. **分页策略增强**
**需求**: 支持多种分页方式

**当前问题**: 
- 分页逻辑较简单
- 不支持基于cursor的分页

**增强方案**:
```json
{
  "pagination": {
    "type": "cursor",  // offset, page, cursor
    "cursorField": "nextCursor",
    "hasMoreField": "hasNext",
    "pageSize": 20,
    "maxPages": 100
  }
}
```

### 6. **错误处理和重试策略**
**需求**: 处理各种错误情况

**增强方案**:
```json
{
  "errorHandling": {
    "retryOn": [401, 403, 429, 500, 502, 503],
    "retryStrategy": {
      "type": "exponential",
      "baseDelay": 1000,
      "maxDelay": 30000,
      "maxRetries": 3
    },
    "fallback": {
      "enabled": true,
      "alternativeUrl": "{{alternativeUrls.hotmanga}}"
    }
  }
}
```

### 7. **图片URL解密/处理**
**需求**: 某些图源的图片URL需要特殊处理

**增强方案**:
```json
{
  "imageProcessing": {
    "urlDecryption": {
      "enabled": true,
      "method": "base64",  // base64, aes, custom
      "script": "function decrypt(url) { return atob(url); }"
    },
    "urlTransform": {
      "enabled": true,
      "pattern": "/thumb/",
      "replacement": "/original/"
    }
  }
}
```

### 8. **WebView增强**
**需求**: 处理需要JavaScript的页面

**当前状态**: 
- 已有WebView系统
- 需要增强配置能力

**增强方案**:
```json
{
  "webview": {
    "required": false,
    "executeScript": [
      "document.querySelector('.anti-bot').remove();",
      "window.scrollTo(0, document.body.scrollHeight);"
    ],
    "waitFor": {
      "selector": ".manga-list",
      "timeout": 10000
    },
    "captureRequests": {
      "enabled": true,
      "patterns": ["/api/*", "/image/*"]
    }
  }
}
```

## 四、实施计划

### Phase 1: 逆向分析 (1-2天)
1. ✅ 分析APK结构
2. 🔄 抓包分析API请求
3. 🔄 识别认证机制
4. 🔄 理解数据格式

### Phase 2: 系统增强 (3-5天)
1. 实现动态域名切换
2. 添加简繁转换支持
3. 增强Cookie/会话管理
4. 实现User-Agent轮换
5. 改进分页策略
6. 完善错误处理

### Phase 3: 创建CopyManga配置 (2-3天)
1. 编写JSON配置文件
2. 配置API端点
3. 设置认证流程
4. 定义数据提取规则
5. 配置图片加载

### Phase 4: 测试验证 (2-3天)
1. 功能测试
2. 性能测试
3. 边界情况测试
4. 用户体验优化

## 五、技术难点

### 1. API逆向工程
**难度**: ⭐⭐⭐⭐
- 需要抓包分析真实请求
- 可能有反爬虫机制
- 需要理解加密/签名逻辑

**解决方案**:
- 使用Charles/Fiddler抓包
- 分析Smali代码中的网络请求
- 测试不同场景的API调用

### 2. 认证和会话管理
**难度**: ⭐⭐⭐
- 登录流程可能复杂
- Cookie/Token管理
- 会话过期处理

**解决方案**:
- 实现完整的认证流程
- 自动刷新机制
- 错误恢复策略

### 3. 反爬虫对抗
**难度**: ⭐⭐⭐⭐⭐
- User-Agent检测
- 频率限制
- 可能的验证码

**解决方案**:
- User-Agent轮换
- 请求频率控制
- WebView fallback

### 4. 数据格式兼容
**难度**: ⭐⭐
- 简繁转换
- 字段映射
- 数据清洗

**解决方案**:
- 实现文本转换工具
- 灵活的字段映射
- 数据验证和清洗

## 六、风险评估

### 高风险
1. **API变更** - 图源可能随时更改API
   - 缓解：版本控制，快速更新机制

2. **反爬虫升级** - 可能加强反爬虫措施
   - 缓解：多种绕过策略，WebView备用

### 中风险
1. **性能问题** - 复杂的处理可能影响性能
   - 缓解：优化算法，异步处理

2. **兼容性** - 不同版本的兼容性
   - 缓解：充分测试，向后兼容

### 低风险
1. **用户体验** - 功能复杂度增加
   - 缓解：合理的默认值，清晰的文档

## 七、建议

### 短期（立即实施）
1. ✅ 完成Cookie管理修复（已完成）
2. 🔄 实现抓包分析CopyManga API
3. 🔄 创建基础JSON配置框架

### 中期（1-2周）
1. 实现核心增强功能
2. 创建CopyManga图源配置
3. 进行功能测试

### 长期（1个月+）
1. 完善所有增强功能
2. 支持更多图源
3. 建立图源社区

## 八、总结

**CopyManga无法直接移植**，但可以通过以下方式实现：

1. **逆向工程** - 分析APK和API调用
2. **系统增强** - 添加必要的新功能
3. **重新实现** - 用JSON配置重写

**关键成功因素**:
- 完整的API逆向分析
- 健壮的系统增强
- 充分的测试验证

**预期时间**: 8-13天
**成功概率**: 85%（取决于API复杂度）

**下一步行动**:
1. 使用抓包工具分析CopyManga的真实API请求
2. 实现优先级最高的系统增强
3. 创建初始版本的JSON配置
