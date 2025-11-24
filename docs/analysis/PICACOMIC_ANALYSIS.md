# 哔咔漫画 (Picacomic) 图源分析

## 📋 基本信息

- **名称**: 哔咔漫画
- **语言**: 中文
- **baseUrl**: `https://picaapi.picacomic.com`
- **类型**: **API模式**（REST API）

## 🔐 认证机制

### 1. **HMAC-SHA256签名**
每个请求都需要计算签名：
```
raw = path + timestamp + nonce + method + apiKey (全部小写)
signature = HMAC-SHA256(hmacKey, raw)
```

### 2. **JWT Token认证**
- 需要用户名和密码登录获取token
- Token有过期时间，需要验证并自动刷新
- 每个请求（除登录外）都需要在header中携带token

### 3. **必需Headers**
```json
{
  "api-key": "C69BAF41DA5ABD1FFEDC6D2FEA56B",
  "app-channel": "2",
  "app-version": "2.2.1.3.3.4",
  "app-uuid": "defaultUuid",
  "app-platform": "android",
  "app-build-version": "44",
  "User-Agent": "okhttp/3.8.1",
  "accept": "application/vnd.picacomic.com.v1+json",
  "image-quality": "high",
  "Content-Type": "application/json; charset=UTF-8",
  "time": "<timestamp>",
  "nonce": "<random32chars>",
  "signature": "<hmac_signature>",
  "authorization": "<jwt_token>"
}
```

## 📡 API端点

### 登录
```
POST /auth/sign-in
Body: {"email": "username", "password": "password"}
Response: {data: {token: "jwt_token"}}
```

### 热门漫画
```
GET /comics?page={page}&s=dd
Response: {data: {comics: {docs: [], page, pages}}}
```

### 随机漫画（最新）
```
GET /comics/random
Response: {data: {comics: [...]}}
```

### 搜索
```
POST /comics/advanced-search?page={page}
Body: {"keyword": "...", "categories": [], "sort": "dd"}
```

### 榜单
```
GET /comics/leaderboard?tt=H24&ct=VC  // 24小时
GET /comics/leaderboard?tt=D7&ct=VC   // 7天
GET /comics/leaderboard?tt=D30&ct=VC  // 30天
```

### 漫画详情
```
GET /comics/{comicId}
Response: {data: {comic: {...}}}
```

### 章节列表
```
GET /comics/{comicId}/eps?page={page}
Response: {data: {eps: {docs: [], page, pages}}}
```

### 页面列表
```
GET /comics/{comicId}/order/{order}/pages?page={page}
Response: {data: {pages: {docs: [], page, pages, limit}}}
```

## 🚫 实现难点

### ❌ **无法直接移植的原因**

1. **复杂的签名算法**
   - 需要HMAC-SHA256加密
   - 需要生成随机nonce
   - 当前JSON图源不支持自定义加密逻辑

2. **JWT Token管理**
   - 需要解析JWT payload
   - 需要验证过期时间
   - 需要自动刷新token
   - 需要持久化存储

3. **用户认证**
   - 需要用户输入账号密码
   - 需要安全存储凭据
   - 当前框架没有用户认证UI

4. **自定义DNS**
   - Kotlin版本使用了ChannelDns进行分流
   - 需要动态获取分流地址

5. **分页递归**
   - 章节列表和页面列表需要递归获取所有页
   - 当前框架不支持在工作流中进行循环

## 💡 建议方案

### 方案A：扩展框架支持（推荐）
在`MangaSourceEngine`中添加：
1. **自定义加密函数支持**
   ```typescript
   interface CryptoConfig {
     type: "hmac-sha256" | "md5" | "sha1";
     key: string;
     input: string; // 支持模板变量
   }
   ```

2. **认证流程支持**
   ```json
   {
     "auth": {
       "type": "login",
       "endpoint": "/auth/sign-in",
       "method": "POST",
       "credentials": ["username", "password"],
       "tokenPath": "data.token",
       "tokenExpiry": "jwt" // 自动解析JWT
     }
   }
   ```

3. **动态Headers计算**
   ```json
   {
     "headers": {
       "signature": "{{crypto:hmac-sha256}}",
       "time": "{{timestamp}}",
       "nonce": "{{random:32}}",
       "authorization": "{{auth:token}}"
     }
   }
   ```

### 方案B：原生模块（备选）
创建专门的`PicacomicSource.ets`原生模块：
- 实现完整的签名逻辑
- 管理JWT token
- 提供统一的API接口
- 不使用JSON配置

## 📝 结论

**哔咔漫画不适合使用当前的JSON图源格式**，原因：
1. ✅ API结构清晰，但需要复杂的加密和认证
2. ❌ JSON配置无法实现HMAC-SHA256签名
3. ❌ 无法管理JWT token生命周期
4. ❌ 需要用户登录系统

**推荐**：
- 短期：暂不支持，等待框架扩展
- 长期：实现方案A，扩展框架支持加密和认证
- 替代：使用其他无需登录的图源（如已完成的dongmanmanhua）

## 🔄 与Dongman Manhua对比

| 特性 | Dongman Manhua | Picacomic |
|------|----------------|-----------|
| 认证 | ❌ 无需登录 | ✅ 需要账号密码 |
| 加密 | ❌ 无 | ✅ HMAC-SHA256 |
| API类型 | WebView + HTML解析 | REST API + JSON |
| 实现难度 | ⭐⭐ 简单 | ⭐⭐⭐⭐⭐ 极难 |
| 可移植性 | ✅ 完全支持 | ❌ 需要框架扩展 |
