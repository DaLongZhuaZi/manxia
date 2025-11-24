# Cookie管理系统问题分析与修复方案

## 问题概述

当前软件的Cookie获取、管理、使用流程存在严重混乱，导致以下问题：
1. **无法获取Cookie** - 从服务器获取Cookie失败
2. **无法添加到请求头** - Cookie未正确添加到HTTP请求
3. **WebView请求失败** - 服务器返回401/402等认证错误

## 核心问题分析

### 1. Cookie管理器重复与职责不清

**问题：** 存在两个Cookie管理器，职责重叠且不协调

- **CookieManager** (`Framework/Managers/CookieManager.ets`)
  - 负责Cookie的数据库存储和读取
  - 提供HTTP请求的Cookie字符串构建
  - 支持从HTTP响应获取Set-Cookie
  
- **WebViewAuthManager** (`Framework/WebView/WebViewAuthManager.ets`)
  - 负责WebView的Cookie注入和捕获
  - 处理登录相关的Cookie操作
  - 与WebView控制器交互

**影响：** 两个管理器之间缺乏协调，导致Cookie数据不同步

### 2. Cookie存储格式不一致

**问题：** Cookie在不同位置使用不同的存储格式

**CookieManager存储格式：**
```typescript
interface CookieEntry {
  name: string;
  value: string;
  domain?: string;
  path?: string;
  expires?: number;
  httpOnly?: boolean;
  secure?: boolean;
}
```

**WebViewAuthManager存储格式：**
```typescript
// 相同的接口定义，但解析和序列化逻辑独立
```

**影响：** 
- 数据迁移逻辑复杂（见CookieManager.ets #104-121行）
- 可能导致Cookie丢失或格式错误

### 3. Cookie获取流程混乱

**问题：** 多个Cookie获取路径，优先级不明确

**获取路径：**

1. **从数据库读取** (`CookieManager.getCookieString`)
   ```typescript
   const srcRecord = await this.dataManager.getComicSourceById(sourceId);
   let cookiesJson = srcRecord.cookies ? String(srcRecord.cookies) : '';
   ```

2. **从旧配置迁移** (同一方法内 #104-121行)
   ```typescript
   const old = await this.dataManager.getWebViewSourceConfigRecord(sourceId);
   // 迁移逻辑
   ```

3. **从WebView捕获** (`WebViewAuthManager.captureCookiesFromController`)
   ```typescript
   const cookieStr = await controller.runJavaScript('document.cookie');
   ```

4. **从HTTP响应获取** (`CookieManager.fetchCookiesByDefaultRequest`)
   ```typescript
   const response = await httpRequest.request(url, options);
   // 解析Set-Cookie头
   ```

**影响：** 
- 重复的迁移检查降低性能
- 多个获取路径可能返回不一致的结果

### 4. Cookie注入到请求头的问题

**问题：** Cookie添加到HTTP请求头的逻辑分散且不完整

**MangaSourceActionEngine (API请求)：**
```typescript
// Line 981-1025: 复杂的Cookie处理逻辑
const useCookiesFlag = context.variables['useCookies'];
const shouldUseCookies = useCookiesFlag === 'true';
if (shouldUseCookies && sidStr) {
  const cookieStr = await CookieManager.getInstance().getCookieString(Number(sidStr));
  if (cookieStr.length > 0) {
    headers['Cookie'] = cookieStr;
    // 复杂的引号清理和去重逻辑 (Line 989-1020)
  }
}
```

**问题点：**
- 依赖`useCookies`变量，但该变量可能未设置
- 复杂的字符串清理逻辑（去引号、去重）表明数据格式不规范
- 缺少错误处理和日志

**ImageCacheManager (图片请求)：**
```typescript
// Line 425: 直接从options.headers.cookie读取
const cookieHdr = options && options.headers && options.headers.cookie 
  ? String(options.headers.cookie) : '';
```

**问题点：**
- 完全依赖调用方传入Cookie
- 没有主动从CookieManager获取
- 如果调用方忘记传入，Cookie就会丢失

### 5. Cookie过期时间处理不当

**问题：** Cookie过期检查逻辑存在缺陷

**CookieManager.hasCookie：**
```typescript
// Line 162-178: 过期检查
const now = Date.now();
let anyValid = false;
for (const e of entries) {
  const exp = e.expires;
  if (exp === undefined) {
    anyValid = true;  // 没有过期时间就认为有效
    break;
  }
  if (now < exp) {
    anyValid = true;
    break;
  }
}
```

**问题点：**
- 没有过期时间的Cookie被认为永久有效（不符合HTTP Cookie规范）
- 过期的Cookie没有被自动清理
- `fetchCookiesByDefaultRequest`设置的默认过期时间为7天（Line 266），但缺少更新机制

### 6. WebView Cookie同步问题

**问题：** WebView和HTTP请求的Cookie不同步

**WebViewAuthManager.applyCookiesToController：**
```typescript
// Line 144-161: 注入Cookie到WebView
const cookies = this.deserializeCookies(cookiesJson);
for (const c of cookies) {
  const js = `document.cookie = '${c.name}=${c.value}; path=${c.path || '/'}'; true;`;
  await controller.runJavaScript(js);
}
```

**问题点：**
- 注入时机不明确（应该在页面加载前）
- 没有验证注入是否成功
- 缺少domain、secure、httpOnly等属性的处理

**WebViewAuthManager.captureCookiesFromController：**
```typescript
// Line 166-179: 从WebView捕获Cookie
const cookieStr = await controller.runJavaScript('document.cookie');
const incoming = this.parseDocumentCookieString(cookieStr);
const merged = this.mergeCookies(existing, incoming);
```

**问题点：**
- `document.cookie`只能获取非httpOnly的Cookie
- 捕获时机不明确
- 合并逻辑可能导致旧Cookie覆盖新Cookie

### 7. 401/402错误的根本原因

**分析：** 服务器返回401/402通常是因为：

1. **Cookie未发送**
   - `useCookies`变量未设置为`true`
   - Cookie获取失败但没有错误提示
   - ImageCacheManager没有主动获取Cookie

2. **Cookie格式错误**
   - 包含多余的引号（见Line 989-1020的清理逻辑）
   - Cookie名称或值被错误编码
   - 多个同名Cookie导致服务器拒绝

3. **Cookie已过期**
   - 过期的Cookie仍然被发送
   - 服务器拒绝过期的认证Cookie

4. **缺少其他必要的请求头**
   - Referer、Origin等防盗链头缺失
   - User-Agent不匹配

## 修复方案

### 方案1: 统一Cookie管理器

**目标：** 合并两个Cookie管理器，建立清晰的职责分工

**实施：**
1. 保留`CookieManager`作为唯一的Cookie管理器
2. 将`WebViewAuthManager`的Cookie相关功能迁移到`CookieManager`
3. `WebViewAuthManager`只负责登录流程，Cookie操作委托给`CookieManager`

### 方案2: 规范Cookie存储格式

**目标：** 统一Cookie的存储和序列化格式

**实施：**
1. 定义标准的Cookie存储接口
2. 所有Cookie操作使用统一的序列化/反序列化方法
3. 移除旧配置迁移逻辑（一次性迁移脚本）

### 方案3: 简化Cookie获取流程

**目标：** 建立清晰的Cookie获取优先级

**实施：**
1. 主流程：从数据库读取 → 检查过期 → 返回
2. 如果数据库无Cookie或已过期：
   - WebView场景：从WebView捕获
   - HTTP场景：发送无Cookie请求获取Set-Cookie
3. 移除重复的迁移检查

### 方案4: 自动注入Cookie到所有HTTP请求

**目标：** 确保所有HTTP请求都携带正确的Cookie

**实施：**

**MangaSourceActionEngine：**
```typescript
// 移除useCookies检查，始终尝试获取Cookie
const sidStr = context.variables['sourceId'];
if (sidStr) {
  const cookieStr = await CookieManager.getInstance().getCookieString(Number(sidStr));
  if (cookieStr.length > 0) {
    headers['Cookie'] = cookieStr;  // 简化，移除复杂的清理逻辑
  }
}
```

**ImageCacheManager：**
```typescript
// 主动获取Cookie，而不是依赖调用方
if (options?.sourceId) {
  const cookieStr = await CookieManager.getInstance().getCookieString(options.sourceId);
  if (cookieStr.length > 0) {
    headerObj['Cookie'] = cookieStr;
  }
}
```

### 方案5: 完善Cookie过期处理

**目标：** 正确处理Cookie过期时间

**实施：**
1. 解析Set-Cookie头的Expires和Max-Age属性
2. 没有过期时间的Cookie设置为Session Cookie（浏览器关闭时过期）
3. 定期清理过期Cookie（后台任务）
4. `hasCookie`方法同时清理过期Cookie

### 方案6: 改进WebView Cookie同步

**目标：** 确保WebView和HTTP请求使用相同的Cookie

**实施：**

**注入时机：**
```typescript
// 在WebView加载URL之前注入
await cookieManager.applyCookiesToWebView(sourceId, controller);
controller.loadUrl(url);
```

**注入方法改进：**
```typescript
// 使用WebView的Cookie API而不是JavaScript
// 如果HarmonyOS支持的话
```

**捕获时机：**
```typescript
// 在页面加载完成后捕获
onPageEnd: async (event) => {
  await cookieManager.captureCookiesFromWebView(sourceId, controller);
}
```

### 方案7: 增强错误处理和日志

**目标：** 快速定位Cookie相关问题

**实施：**
1. 所有Cookie操作添加详细日志
2. Cookie获取失败时记录原因
3. HTTP请求失败时输出Cookie状态
4. 添加Cookie调试工具（SourceSettingsPage）

## 实施优先级

### P0 (立即修复)
1. **修复ImageCacheManager的Cookie传递** - 图片加载失败的主要原因
2. **移除useCookies检查** - 确保API请求始终携带Cookie
3. **简化Cookie字符串处理** - 移除复杂的引号清理逻辑

### P1 (重要)
4. **统一Cookie存储格式** - 避免数据不一致
5. **改进Cookie过期处理** - 避免发送过期Cookie
6. **增强错误日志** - 快速定位问题

### P2 (优化)
7. **合并Cookie管理器** - 长期架构优化
8. **WebView Cookie同步改进** - 提升用户体验

## 测试验证

### 测试场景
1. **新用户首次访问** - 无Cookie → 获取Cookie → 保存
2. **已登录用户** - 读取Cookie → 添加到请求 → 成功访问
3. **Cookie过期** - 检测过期 → 重新获取
4. **WebView登录** - 捕获Cookie → 同步到HTTP请求
5. **图片加载** - 携带Cookie → 成功加载

### 验证指标
- Cookie获取成功率 > 95%
- HTTP 401/402错误率 < 5%
- 图片加载成功率 > 90%
- Cookie同步延迟 < 1秒

## 风险评估

### 高风险
- **数据迁移** - 可能导致现有Cookie丢失
  - 缓解：备份数据库，提供回滚机制

### 中风险
- **API兼容性** - 修改可能影响现有图源配置
  - 缓解：保持向后兼容，逐步迁移

### 低风险
- **性能影响** - Cookie操作增加延迟
  - 缓解：优化数据库查询，添加缓存

## 总结

当前Cookie管理系统的核心问题是**职责分散、格式不统一、流程混乱**。修复方案的核心思路是：

1. **统一管理** - 单一Cookie管理器
2. **自动注入** - 所有HTTP请求自动携带Cookie
3. **规范格式** - 统一存储和序列化
4. **完善处理** - 正确处理过期、同步、错误

通过系统性的修复，可以彻底解决Cookie相关的401/402错误和图片加载失败问题。
