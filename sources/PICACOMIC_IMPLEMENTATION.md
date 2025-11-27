# 哔咔漫画图源实现文档

## 概述

本文档描述了哔咔漫画（PicaComic）图源从Kotlin版本到JSON配置的移植过程。该图源使用JWT认证和HMAC-SHA256签名，是一个需要登录的高级图源。

## 原始Kotlin实现分析

### 核心特性

1. **JWT认证**
   - 用户通过邮箱和密码登录
   - 服务器返回JWT令牌
   - 令牌有过期时间，需要自动刷新

2. **HMAC-SHA256签名**
   - 每个API请求都需要签名
   - 签名格式: `path + time + nonce + method + apiKey`
   - 使用特定的HMAC密钥

3. **自定义DNS**
   - 支持多个分流线路
   - 通过配置选择不同的IP地址

4. **内容过滤**
   - 支持屏蔽特定分类和标签
   - 在客户端过滤不想看的内容

## 新增通用能力

为了支持哔咔漫画，我们在框架中新增了以下通用能力：

### 0. CredentialLoginDialog.ets

**位置**: `entry/src/main/ets/Framework/Components/CredentialLoginDialog.ets`

**功能**:
- 账号密码输入对话框
- 系统样式的自定义对话框
- 密码显示/隐藏切换
- 自动保存凭据到数据库

**使用场景**: 任何需要账号密码登录的图源

**能力声明**: 在JSON配置的`capabilities`中添加`"credentialLogin": true`

### 1. CryptoUtils.ets

**位置**: `entry/src/main/ets/Utils/CryptoUtils.ets`

**功能**:
- `hmacSHA256(key, data)`: HMAC-SHA256加密
- `generateRandomString(length)`: 生成随机字符串（用于nonce）
- `base64UrlDecode(str)`: Base64 URL安全解码
- `base64Encode(str)`: Base64编码
- `md5Hash(data)`: MD5哈希

**使用场景**: 任何需要加密签名的图源

### 2. JWTUtils.ets

**位置**: `entry/src/main/ets/Utils/JWTUtils.ets`

**功能**:
- `parseJWT(token)`: 解析JWT令牌
- `isJWTExpired(token, leeway)`: 检查JWT是否过期
- `validateJWT(token, leeway)`: 验证JWT有效性
- `getJWTRemainingTime(token)`: 获取剩余有效时间
- `extractUserInfo(token)`: 提取用户信息

**使用场景**: 任何使用JWT认证的图源

### 3. SignatureHandler.ets

**位置**: `entry/src/main/ets/Framework/Source/SignatureHandler.ets`

**功能**:
- 为API请求生成签名
- 支持HMAC-SHA256、MD5、SHA256等算法
- 支持自定义签名格式
- 自动生成时间戳和nonce

**使用场景**: 需要请求签名的图源

### 4. AuthenticationHandler.ets

**位置**: `entry/src/main/ets/Framework/Source/AuthenticationHandler.ets`

**功能**:
- 管理JWT令牌存储
- 自动验证令牌有效性
- 构建认证请求头
- 从响应中提取令牌

**使用场景**: 需要认证的图源

## JSON图源配置

### 文件位置

`sources/picacomic_api.json`

### 关键配置项

#### 0. 能力声明

```json
"capabilities": {
  "credentialLogin": true,  // 声明需要凭据登录
  "customAuthentication": true,
  "hmacSignature": true,
  "jwtToken": true
}
```

#### 1. 认证配置

```json
"authentication": {
  "type": "jwt",
  "loginUrl": "https://picaapi.picacomic.com/auth/sign-in",
  "loginMethod": "POST",
  "tokenStorageKey": "picacomic_token",
  "tokenLeeway": 10,
  "loginPayload": {
    "email": "{{username}}",
    "password": "{{password}}"
  },
  "tokenExtraction": {
    "type": "json",
    "path": "data.token"
  },
  "requiresLogin": true
}
```

#### 2. 签名配置

```json
"signature": {
  "enabled": true,
  "algorithm": "hmac-sha256",
  "key": "~d}$Q7$eIni=V)9\\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn",
  "headers": {
    "time": "{{timestamp}}",
    "nonce": "{{nonce}}",
    "signature": "{{signature}}"
  },
  "signatureFormat": "{{path}}{{time}}{{nonce}}{{method}}{{apiKey}}",
  "toLowerCase": true
}
```

#### 3. 网络配置

```json
"network": {
  "userAgent": "okhttp/3.8.1",
  "headers": {
    "api-key": "C69BAF41DA5ABD1FFEDC6D2FEA56B",
    "app-channel": "2",
    "app-version": "2.2.1.3.3.4",
    "app-uuid": "defaultUuid",
    "app-platform": "android",
    "app-build-version": "44",
    "accept": "application/vnd.picacomic.com.v1+json",
    "Content-Type": "application/json; charset=UTF-8"
  }
}
```

#### 4. 工作流示例

```json
"popular": {
  "description": "获取热门漫画",
  "actions": [
    {
      "type": "api",
      "method": "GET",
      "url": "https://picaapi.picacomic.com/comics",
      "params": {
        "page": "{{page}}",
        "s": "dd"
      },
      "headers": {
        "authorization": "{{token}}",
        "image-quality": "{{imageQuality}}",
        "signature": "{{computeSignature}}"
      },
      "extract": {
        "type": "json",
        "path": "data.comics.docs",
        "fields": {
          "id": "_id",
          "title": "title",
          "author": "author",
          "cover": "thumb.fileServer + '/static/' + thumb.path"
        }
      }
    }
  ]
}
```

## 与原Kotlin实现的对应关系

| Kotlin实现 | JSON配置 | 新增工具类 |
|-----------|---------|-----------|
| `hmacSHA256()` | `signature.algorithm` | `CryptoUtils.hmacSHA256()` |
| `isExpired()` | `authentication.tokenLeeway` | `JWTUtils.isJWTExpired()` |
| `getToken()` | `workflows.login` | `AuthenticationHandler` |
| `picaHeaders()` | `signature.headers` | `SignatureHandler` |
| `ChannelDns` | `settings.appChannel` | 配置项 |
| `parseJWT()` | - | `JWTUtils.parseJWT()` |

## 使用说明

### 用户配置

#### 凭据登录流程

1. **首次进入图源**: 自动弹出登录对话框
2. **输入凭据**: 输入哔咔账号（邮箱）和密码
3. **自动保存**: 凭据安全保存到本地数据库
4. **自动登录**: 下次进入自动使用保存的凭据

#### 其他设置

1. 选择图片质量（原图/低/中/高）
2. 选择分流线路（1/2/3）
3. 可选：配置屏蔽词列表

### 开发者集成

#### 在SourceExecutor中集成

```typescript
import { SignatureHandler } from './SignatureHandler';
import { AuthenticationHandler } from './AuthenticationHandler';

// 创建处理器
const signatureHandler = new SignatureHandler(config.signature);
const authHandler = new AuthenticationHandler(config.authentication, sourceId);

// 生成签名头
const signatureHeaders = await signatureHandler.generateSignatureHeaders({
  url: requestUrl,
  method: 'GET',
  apiKey: config.network.headers['api-key']
});

// 生成认证头
const authHeaders = await authHandler.buildAuthHeaders();

// 合并请求头
const headers = {
  ...config.network.headers,
  ...signatureHeaders,
  ...authHeaders
};
```

## 未实现的功能

以下Kotlin版本的功能在JSON配置中未完全实现，但保留了扩展接口：

1. **自定义DNS解析**
   - Kotlin版本使用`ChannelDns`类动态解析IP
   - JSON版本通过配置项选择分流，但不支持动态DNS
   - 未来可以在`NetworkManager`中添加DNS解析能力

2. **分流URL动态获取**
   - Kotlin版本可以从远程URL获取分流地址
   - JSON版本使用固定配置
   - 可以通过添加`initialize`工作流实现

## 凭据登录能力详解

### 工作原理

1. **能力声明**: 在JSON配置的`capabilities`中声明`"credentialLogin": true`
2. **自动检测**: `SourceDetailPage`在初始化时检查此能力
3. **凭据验证**: 检查数据库中是否已保存凭据
4. **显示对话框**: 如果未登录，自动显示`CredentialLoginDialog`
5. **保存凭据**: 用户输入后保存到`UserSettings`表
6. **继续初始化**: 登录成功后继续加载图源内容

### 实现文件

- **对话框组件**: `CredentialLoginDialog.ets`
- **页面逻辑**: `SourceDetailPage.ets`
  - `checkCredentialLogin()`: 检查是否需要登录
  - `handleCredentialLogin()`: 处理登录逻辑
  - `continueInitializationAfterLogin()`: 登录后继续初始化
- **数据存储**: `DataManager.ets`
  - `saveSourceCredentials()`: 保存凭据
  - `getSourceCredentials()`: 读取凭据

### 数据库存储

凭据存储在`UserSettings`表中：
- **键**: `source:{sourceId}:credentials`
- **值**: `{"username": "xxx", "password": "xxx"}`
- **类型**: `json`

### 安全性

- 凭据存储在本地数据库，不会上传到服务器
- 使用HarmonyOS的Preferences API安全存储
- 密码在对话框中可以隐藏显示

## 兼容性说明

### 不影响现有图源

所有新增的工具类和处理器都是**可选的**：

1. **CredentialLoginDialog.ets**: 仅在声明`credentialLogin`能力时使用
2. **CryptoUtils.ets**: 独立的加密工具，不影响其他模块
3. **JWTUtils.ets**: 独立的JWT工具，不影响其他模块
4. **SignatureHandler.ets**: 仅在配置中启用`signature.enabled`时使用
5. **AuthenticationHandler.ets**: 仅在配置中启用`authentication`时使用

### 向后兼容

- 现有的`copymanga_api.json`、`copymanga_webview.json`等图源不需要修改
- 新增的能力通过配置项启用，默认不启用
- 框架会检查配置项是否存在，不存在则跳过相关处理

## 测试建议

1. **单元测试**
   - 测试HMAC-SHA256签名生成
   - 测试JWT解析和验证
   - 测试令牌存储和读取

2. **集成测试**
   - 测试登录流程
   - 测试签名头生成
   - 测试API请求完整流程

3. **用户测试**
   - 测试登录界面
   - 测试漫画浏览
   - 测试章节阅读

## 后续优化方向

1. **性能优化**
   - 缓存签名计算结果
   - 批量请求优化

2. **功能增强**
   - 支持自动重新登录
   - 支持多账号切换
   - 支持离线令牌刷新

3. **用户体验**
   - 添加登录状态指示
   - 优化错误提示
   - 添加登录引导

## 总结

通过新增5个通用组件和工具类，我们成功将哔咔漫画的Kotlin实现移植到JSON配置格式：

1. **CredentialLoginDialog.ets**: 凭据登录对话框
2. **CryptoUtils.ets**: 加密工具（HMAC-SHA256）
3. **JWTUtils.ets**: JWT令牌管理
4. **SignatureHandler.ets**: 请求签名处理
5. **AuthenticationHandler.ets**: 认证管理

这些新增的能力是**通用的**，可以被其他需要类似功能的图源复用，同时**不影响**现有图源的正常运行。

### 新增能力声明

在JSON配置中声明`"credentialLogin": true`即可启用凭据登录功能，系统会自动：
- 检查是否已保存凭据
- 显示登录对话框（如果需要）
- 保存凭据到数据库
- 自动登录（下次进入）
