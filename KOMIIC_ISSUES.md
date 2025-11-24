# Komiic API 问题分析

## ① 搜索功能问题

### 现象
日志显示GraphQL查询仍然使用`searchComicsByKeyword`：
```
"query": "query searchComics(...) { searchComicsByKeyword(...) }"
```

### 原因
**应用缓存了旧的配置文件**。虽然`komiic_api.json`已经修改为`searchComics`，但应用可能从缓存中加载了旧配置。

### 解决方案
**请完全卸载应用并重新安装**，或者清除应用数据缓存。

---

## ② 图片加载问题（400错误）

### 根本原因
Komiic使用**Cloudflare保护**，图片API需要以下认证：

1. **Cookie**: `cf_clearance` (Cloudflare验证token)
2. **Cookie**: `__stripe_mid`, `__stripe_sid` 
3. **Cookie**: `komiic-image-view-type`, `komiic_direction_tip`

你提供的headers显示：
```
cookie: __stripe_mid=...; cf_clearance=YrZ1bP34nlRktZ3WkjzVCoJ4LvNe7xO35HV8teWS7cU-...
```

### 问题
**HarmonyOS的http模块无法获取或设置这些Cookie**，因为：
1. Cloudflare的`cf_clearance`需要通过浏览器JavaScript challenge获取
2. 这个cookie是动态生成的，有时效性
3. 普通HTTP请求无法通过Cloudflare验证

### 可能的解决方案

#### 方案1: 使用WebView加载图片（推荐）
让WebView处理Cloudflare验证和Cookie管理：

```typescript
// 在WebView中加载图片
webview.loadUrl(imageUrl);
// 然后截图或获取图片数据
```

**优点**: WebView可以自动处理Cloudflare验证
**缺点**: 性能较差，每张图片都需要WebView实例

#### 方案2: 使用代理服务器
搭建一个中转服务器，服务器端处理Cloudflare验证：

```
App -> 你的服务器 -> Komiic API
```

**优点**: 可以完全控制请求
**缺点**: 需要额外的服务器资源

#### 方案3: 修改Komiic源码（不推荐）
如果有Komiic的API密钥或其他认证方式，可以绕过Cloudflare。

**缺点**: 需要Komiic官方支持

---

## 当前状态

### ✅ 已完成
- GraphQL查询已修改为`searchComics`
- 图片URL构建正确
- 添加了完整的HTTP headers

### ❌ 待解决
- **搜索**: 需要清除应用缓存或重新安装
- **图片**: 需要实现方案1（WebView）或方案2（代理服务器）

---

## 建议

### 短期方案（测试用）
1. **卸载应用并重新安装**，测试搜索功能
2. 暂时禁用Komiic图源，或者提示用户"该图源需要浏览器访问"

### 长期方案（生产环境）
实现**方案1: WebView图片加载**：
- 为Komiic图源创建专门的图片加载器
- 使用WebView加载图片，然后转换为PixelMap
- 缓存已加载的图片

---

## 测试命令

测试搜索API（需要先清除缓存）：
```powershell
# 重新安装应用后测试
```

测试图片API（会失败，因为缺少Cookie）：
```powershell
curl "https://komiic.com/api/image/5ac123d2-0b57-469c-8e3f-4b51f6723de7" `
  -H "Referer: https://komiic.com/" `
  -H "User-Agent: Mozilla/5.0..."
# 返回: 400 Bad Request
```
