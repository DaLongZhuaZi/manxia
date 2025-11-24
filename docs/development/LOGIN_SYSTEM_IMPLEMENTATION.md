# 登录系统实现总结

## 问题分析

### 原始问题
从日志 `komiic图源加载log.txt` 看到：
```
11-21 19:19:57.648 [DatabaseManager] SQL查询成功，结果数量: 0
11-21 19:19:57.648 [SourceSettingsPage] 未找到图源记录
```

**根本原因**：
1. `SourceSettingsPage.fetchCookieWithoutLogin()` 调用 `getComicSourceById(20)` 返回 null
2. Komiic图源（sourceId=20）的记录不在 `comic_source` 表中
3. 导致无法获取 `baseUrl`，进而无法获取Cookie

### Komiic登录机制（从Kotlin源码分析）

从 `keiyoushi-extensions-source/src/zh/komiic/src/eu/kanade/tachiyomi/extension/zh/komiic/Komiic.kt` 分析：

```kotlin
private fun refreshToken(chain: Interceptor.Chain) {
    val url = chain.request().url
    if (url.pathSegments[0] != "api") return
    val cookie = client.cookieJar.loadForRequest(url).find { it.name == "komiic-access-token" } ?: return
    val parts = cookie.value.split(".")
    if (parts.size != 3) throw IOException("Token 格式無效")
    val payload = Base64.decode(parts[1], Base64.DEFAULT).decodeToString()
    if (System.currentTimeMillis() + 3600_000 < payload.parseAs<JwtPayload>().exp * 1000) return
    val response = chain.proceed(POST("$baseUrl/auth/refresh", headers)).apply { close() }
    if (!response.isSuccessful) throw IOException("刷新 Token 失敗：HTTP ${response.code}")
}
```

**Komiic登录特点**：
1. 使用JWT Token认证（Cookie名称：`komiic-access-token`）
2. Token过期前1小时自动刷新（调用 `/auth/refresh` 端点）
3. 需要登录才能突破每日图片阅读限制
4. Token格式：标准JWT（三段式，Base64编码）

## 解决方案

### 1. 创建通用登录管理器

**文件**: `Framework/Authentication/LoginManager.ets`

**支持的登录类型**：
- **WebView登录**: 打开登录页面，用户手动登录，自动捕获Cookie
- **表单登录**: 程序化提交用户名密码，自动提取Cookie
- **OAuth登录**: 支持OAuth 2.0流程（预留接口）

**核心接口**：

```typescript
// 登录配置
export interface WebViewLoginConfig {
  type: 'webview';
  loginUrl: string;
  successUrlPattern?: string;
  cookieNames?: string[];
  timeout?: number;
}

export interface FormLoginConfig {
  type: 'form';
  loginUrl: string;
  method: 'GET' | 'POST';
  usernameField: string;
  passwordField: string;
  extraFields?: Record<string, string>;
  headers?: Record<string, string>;
  successIndicator?: string;
  cookieNames?: string[];
}

// 登录方法
async login(
  sourceId: number,
  config: LoginConfig,
  credentials?: { username: string; password: string }
): Promise<LoginResult>

// 从WebView提取Cookie
async extractCookiesFromWebView(
  controller: webview.WebviewController,
  sourceId: number,
  domain: string,
  cookieNames?: string[]
): Promise<Record<string, string>>

// 检查登录状态
async checkLoginStatus(sourceId: number, checkUrl: string): Promise<boolean>

// 清除登录
async logout(sourceId: number): Promise<void>
```

### 2. 修复SourceSettingsPage

**修改**: `pages/SourceSettingsPage.ets`

**问题修复**：
```typescript
// 原代码：直接从数据库查询，失败就退出
const srcRecord = await this.dataManager.getComicSourceById(sidFetch);
if (!srcRecord) { this.showToast('未找到图源记录'); return; }

// 修复后：尝试从配置文件获取
let baseUrl: string = '';
if (!srcRecord) {
  logger.info(TAG, '未找到图源记录，尝试从配置获取baseUrl');
  const config = this.webViewManager.getSourceConfig(String(sidFetch));
  if (config && config['baseUrl']) {
    baseUrl = String(config['baseUrl']);
  }
  if (baseUrl.length === 0) {
    this.showToast('未找到图源配置');
    return;
  }
} else {
  baseUrl = srcRecord.baseUrl;
}
```

### 3. Komiic图源JSON配置

**文件**: `sources/komiic_api.json`

**登录配置示例**：

```json
{
  "metadata": {
    "id": "komiic",
    "name": "Komiic",
    "baseUrl": "https://komiic.com",
    "version": "1.0.0",
    "language": "zh-TW"
  },

  "authentication": {
    "required": false,
    "type": "webview",
    "loginUrl": "https://komiic.com/login",
    "successUrlPattern": "https://komiic.com/",
    "cookieNames": ["komiic-access-token"],
    "tokenRefresh": {
      "enabled": true,
      "endpoint": "/auth/refresh",
      "method": "POST",
      "checkInterval": 3600000,
      "beforeExpire": 3600000
    }
  },

  "workflows": {
    "login": {
      "type": "webview",
      "config": {
        "loginUrl": "https://komiic.com/login",
        "successUrlPattern": "https://komiic.com/",
        "cookieNames": ["komiic-access-token"]
      }
    }
  }
}
```

## 使用方法

### 方法1：WebView登录（推荐用于Komiic）

```typescript
import LoginManager from '../Framework/Authentication/LoginManager';

// 1. 创建WebView登录配置
const loginConfig: WebViewLoginConfig = {
  type: 'webview',
  loginUrl: 'https://komiic.com/login',
  successUrlPattern: 'https://komiic.com/',
  cookieNames: ['komiic-access-token'],
  timeout: 300000  // 5分钟超时
};

// 2. 打开WebView让用户登录
// 在UI组件中：
const controller = this.webViewManager.getWebViewInstance('20');
// 加载登录页面
controller.loadUrl(loginConfig.loginUrl);

// 3. 登录成功后提取Cookie
const loginManager = LoginManager.getInstance();
const cookies = await loginManager.extractCookiesFromWebView(
  controller,
  20,  // sourceId
  'komiic.com',
  ['komiic-access-token']
);

// 4. Cookie已自动保存到数据库
console.log('登录成功，获取到Cookie:', cookies);
```

### 方法2：表单登录

```typescript
// 1. 创建表单登录配置
const loginConfig: FormLoginConfig = {
  type: 'form',
  loginUrl: 'https://example.com/api/login',
  method: 'POST',
  usernameField: 'username',
  passwordField: 'password',
  headers: {
    'Content-Type': 'application/json'
  },
  successIndicator: '"success":true',
  cookieNames: ['session_token']
};

// 2. 执行登录
const loginManager = LoginManager.getInstance();
const result = await loginManager.login(
  sourceId,
  loginConfig,
  { username: 'user@example.com', password: 'password123' }
);

if (result.success) {
  console.log('登录成功:', result.message);
  console.log('获取到的Cookie:', result.cookies);
} else {
  console.error('登录失败:', result.message);
}
```

### 方法3：检查登录状态

```typescript
const loginManager = LoginManager.getInstance();

// 检查是否已登录
const isLoggedIn = await loginManager.checkLoginStatus(
  sourceId,
  'https://komiic.com/api/account'
);

if (!isLoggedIn) {
  // 需要重新登录
  console.log('未登录或登录已过期');
}
```

### 方法4：清除登录

```typescript
const loginManager = LoginManager.getInstance();
await loginManager.logout(sourceId);
console.log('已清除登录状态');
```

## 集成到工作流系统

### 在WorkflowCapabilities中添加登录能力

```typescript
// Framework/Workflow/WorkflowCapabilities.ets

export type CapabilityType = 
  | 'urlResolver'
  | 'chineseConverter'
  | 'pagination'
  | 'userAgentRotation'
  | 'errorRetry'
  | 'sessionManagement'
  | 'authentication';  // 新增

// 初始化登录能力
if (this.hasCapability(sourceConfig, 'authentication')) {
  const authConfig = sourceConfig['authentication'] as Object;
  capabilities.set('authentication', authConfig);
  logger.info(TAG, '启用登录能力');
}
```

### 在图源配置中声明登录能力

```json
{
  "capabilities": {
    "urlResolver": true,
    "chineseConverter": true,
    "pagination": true,
    "userAgentRotation": true,
    "errorRetry": true,
    "sessionManagement": false,
    "authentication": true
  },

  "authentication": {
    "required": false,
    "type": "webview",
    "loginUrl": "https://komiic.com/login",
    "successUrlPattern": "https://komiic.com/",
    "cookieNames": ["komiic-access-token"]
  }
}
```

## Token自动刷新（Komiic专用）

### 实现Token刷新拦截器

```typescript
// Framework/Network/TokenRefreshInterceptor.ets

export class TokenRefreshInterceptor {
  async refreshKomiicToken(sourceId: number): Promise<boolean> {
    try {
      // 1. 获取当前token
      const cookieManager = CookieManager.getInstance();
      const cookieStr = await cookieManager.getCookieString(sourceId);
      
      // 2. 解析JWT payload检查过期时间
      const tokenMatch = cookieStr.match(/komiic-access-token=([^;]+)/);
      if (!tokenMatch) return false;
      
      const token = tokenMatch[1];
      const parts = token.split('.');
      if (parts.length !== 3) return false;
      
      // Base64解码payload
      const payloadStr = this.base64Decode(parts[1]);
      const payload = JSON.parse(payloadStr);
      
      // 3. 检查是否需要刷新（过期前1小时）
      const now = Date.now();
      const expireTime = payload.exp * 1000;
      if (now + 3600000 < expireTime) {
        return true;  // 还不需要刷新
      }
      
      // 4. 调用刷新接口
      const httpRequest = http.createHttp();
      const response = await httpRequest.request(
        'https://komiic.com/auth/refresh',
        {
          method: http.RequestMethod.POST,
          header: {
            'Cookie': cookieStr
          }
        }
      );
      
      // 5. 提取新token并保存
      if (response.responseCode === 200) {
        const newCookies = this.extractCookies(response);
        await this.saveCookies(sourceId, newCookies);
        return true;
      }
      
      return false;
    } catch (error) {
      logger.error('TokenRefreshInterceptor', `刷新token失败: ${String(error)}`);
      return false;
    }
  }
  
  private base64Decode(str: string): string {
    // 实现Base64解码
    // HarmonyOS可能需要使用util.Base64或其他方式
    return atob(str);
  }
}
```

## UI集成示例

### 在SourceSettingsPage添加登录按钮

```typescript
// 添加登录相关状态
@State isLoggedIn: boolean = false;
@State loginStatus: string = '未登录';
private loginManager: LoginManager = LoginManager.getInstance();

// 添加登录方法
private async openLoginPage(): Promise<void> {
  try {
    const sid = this.pageParams.sourceId;
    const controller = this.webViewManager.getWebViewInstance(String(sid));
    
    // 加载登录页面
    await controller.loadUrl('https://komiic.com/login');
    
    // 等待用户登录（可以监听URL变化）
    // 登录成功后提取Cookie
    setTimeout(async () => {
      const cookies = await this.loginManager.extractCookiesFromWebView(
        controller,
        sid,
        'komiic.com',
        ['komiic-access-token']
      );
      
      if (Object.keys(cookies).length > 0) {
        this.loginStatus = '已登录';
        this.isLoggedIn = true;
        this.showToast('登录成功');
      }
    }, 5000);
  } catch (error) {
    logger.error(TAG, `打开登录页面失败: ${String(error)}`);
    this.showToast('打开登录页面失败');
  }
}

// UI部分
Button('打开登录页面')
  .onClick(() => this.openLoginPage())
  .enabled(!this.isLoggedIn)

Text(this.loginStatus)
  .fontSize(14)
  .fontColor(this.isLoggedIn ? Color.Green : Color.Gray)
```

## 测试清单

### 基础功能测试
- [ ] WebView登录能否正常打开登录页面
- [ ] 登录成功后能否正确提取Cookie
- [ ] Cookie能否正确保存到数据库
- [ ] 表单登录能否正常提交
- [ ] 表单登录能否正确提取Cookie

### Komiic专项测试
- [ ] 能否获取komiic-access-token
- [ ] Token过期前能否自动刷新
- [ ] 刷新后的Token能否正常使用
- [ ] 未登录时是否有图片限制提示
- [ ] 登录后能否突破图片限制

### 集成测试
- [ ] SourceSettingsPage能否正确显示登录状态
- [ ] 能否从配置文件获取baseUrl
- [ ] Cookie状态能否正确刷新
- [ ] 清除登录后状态是否正确更新

## 后续优化

### 1. Token自动刷新
- 实现后台定时检查Token过期时间
- 自动调用刷新接口
- 刷新失败时提示用户重新登录

### 2. 多账号支持
- 支持同一图源多个账号
- 账号切换功能
- 账号管理界面

### 3. 登录状态同步
- WebView和HTTP请求共享Cookie
- 登录状态实时更新
- 跨页面登录状态同步

### 4. 安全性增强
- 密码加密存储
- Token安全存储
- 防止Cookie泄露

## 总结

1. **问题根源**：图源记录不在数据库中，导致无法获取baseUrl
2. **解决方案**：从配置文件获取baseUrl作为fallback
3. **新增功能**：完整的登录管理系统，支持WebView和表单登录
4. **工作流集成**：登录作为一种能力，可在JSON中声明
5. **Komiic支持**：专门适配JWT Token和自动刷新机制

现在图源设置页面应该能够正常获取Cookie了！
