# 哔咔漫画 API 问题分析与修复

## 问题描述

哔咔漫画（PicaComic）API 在获取漫画列表时返回空数据，表现为：
- 登录成功，返回有效的 JWT Token
- API 请求返回 HTTP 200 状态码
- 但响应内容只有 `{"code": 200, "message": "success"}`，没有 `data` 字段

## 问题根源（已确认）

### 签名计算时必须包含查询参数！

通过详细测试发现，**签名计算时必须包含 URL 中的查询参数**。

| API | 签名不含查询参数 | 签名包含查询参数 |
|-----|-----------------|-----------------|
| `/comics?page=1&s=dd` | ❌ 返回空 | ✅ 返回数据 |
| `/comics/{id}/eps?page=1` | ❌ 返回空 | ✅ 返回数据 |
| `/comics/advanced-search?page=1` | ❌ 返回空 | ✅ 返回数据 |

### Kotlin 版本的实现

```kotlin
private fun encrpt(url: String, time: Long, method: String, nonce: String): String {
    val hmacSha256Key = "~d}\$Q7\$eIni=V)9\\RK/P.RM4;9[7|@/CA}b~OW!3?EV`:<>M7pddUBL5n|0/*Cn"
    val apiKey = basicHeaders["api-key"]
    // 关键：substringAfter 不会去掉查询参数！
    val path = url.substringAfter("$baseUrl/")  // 例如: "comics?page=1&s=dd"
    val raw = "$path$time$nonce${method}$apiKey".lowercase(Locale.ROOT)
    return hmacSHA256(hmacSha256Key, raw).convertToString()
}
```

### 错误的实现（之前）

```typescript
// 错误：正则表达式去掉了查询参数
const pathMatch = url.match(/^https?:\/\/[^\/]+\/([^?]*)/);
// 对于 URL: https://picaapi.picacomic.com/comics?page=1&s=dd
// 提取结果: "comics" （错误！）
```

### 正确的实现（修复后）

```typescript
// 正确：保留查询参数
const pathMatch = url.match(/^https?:\/\/[^\/]+\/(.*)$/);
// 对于 URL: https://picaapi.picacomic.com/comics?page=1&s=dd
// 提取结果: "comics?page=1&s=dd" （正确！）
```

## 修复内容

### 文件修改

**`SignatureHandler.ets`**:
- 修改 `generatePicaSignature` 函数中的正则表达式
- 从 `/^https?:\/\/[^\/]+\/([^?]*)/` 改为 `/^https?:\/\/[^\/]+\/(.*)$/`
- 确保签名计算时包含完整的路径和查询参数

### 3. 封面无法显示
PicaComic 返回的封面字段 `thumb` 是一个对象，包含 `fileServer` 和 `path`，需要拼接。
由于配置解析器不支持复杂的 JavaScript 表达式，我们在代码中进行了特殊处理。

**修改**: `MangaSourceEngine.ets` 的 `transformToMangaInfo` 方法。
**配置**: `picacomic_api.json` 中将 `cover` 字段提取改为 `thumb`，提取整个对象。

### 4. 筛选功能缺失
`picacomic_api.json` 中缺少 `filter` 工作流。

**修复**: 在 `picacomic_api.json` 中添加 `filter` 工作流，调用 `/comics` 接口并支持分类和排序参数。

### 6. 章节列表/阅读报错 (HTTP 500)
日志显示 `getPageList` 请求返回 500 错误，提示 `Cast to number failed for value "NaN" at path "order"`.
原因是 `picacomic_api.json` 中使用了 `{{chapterOrder}}` 变量，但代码中实际提供的变量是 `{{chapterId}}`。

**修复**: 修改 `picacomic_api.json` 的 `getPageList` 工作流，将 `{{chapterOrder}}` 改为 `{{chapterId}}`。

### 7. 漫画状态和标签显示不正确
PicaComic 返回的 `finished` 是布尔值，而 `extract` 不支持 JS 表达式。
`tags` 和 `categories` 是两个独立的数组。

**修复**:
- `picacomic_api.json`: 提取 `finished` (boolean), `tags`, `categories`。
- `MangaSourceEngine.ets`: 在 `transformToMangaInfo` 中处理 boolean 状态转换，并将 `categories` 和 `tags` 合并到 `genres`。

### 8. 最新更新 (Latest) 返回 401
日志显示 `Latest` 工作流请求头中的 `{{token}}` 未被替换。
原因是该操作使用的是新的 `sourceId=5`，而该 ID 尚未执行登录流程，因此上下文中没有 `token`。

**解决方案**: 用户需重新登录或重新添加图源以触发登录流程。`picacomic_api.json` 的版本更新 (1.0.2) 会强制刷新配置，可能导致需要重新登录。

## 测试验证

使用 Python 脚本 `pica_test_full.py` 进行完整测试：

```bash
cd sources
python pica_test_full.py
```

### 测试结果

修复后所有 API 都能正常返回数据：

| API | 状态 |
|-----|------|
| 登录 | ✅ |
| 分类列表 | ✅ |
| 热门漫画 | ✅ |
| 随机漫画 | ✅ |
| 排行榜 | ✅ |
| 搜索 | ✅ |
| 漫画详情 | ✅ |
| 章节列表 | ✅ |
| 页面列表 | ✅ |

## 其他注意事项

### 分流服务器
PicaComic 提供了分流服务器机制：

1. 从 `http://68.183.234.72/init` 获取分流服务器地址
2. 响应格式：
   ```json
   {
     "status": "ok",
     "addresses": ["104.19.53.76"],
     "waka": "https://pica-ad-api.diwodiwo.xyz",
     "adKeyword": "diwodiwo"
   }
   ```
3. 使用返回的 IP 地址直接连接，但需要设置正确的 `Host` 头

### 方案 3：自定义 DNS
在应用中实现自定义 DNS 解析，将 `picaapi.picacomic.com` 解析到分流服务器的 IP 地址。

## 技术实现参考

### Tachiyomi 扩展实现
参考 `keiyoushi-extensions-source/src/zh/picacomic/src/eu/kanade/tachiyomi/extension/zh/picacomic/ChannelDns.kt`：

```kotlin
class ChannelDns(
    private val baseHost: String,
    private val client: OkHttpClient,
    private val preferences: SharedPreferences,
) : Dns {

    private val defaultInitUrl = "http://68.183.234.72/init"

    override fun lookup(hostname: String): List<InetAddress> {
        if (!hostname.endsWith(baseHost)) {
            return Dns.SYSTEM.lookup(hostname)
        }
        val ch = preferences.getString(APP_CHANNEL, "2")!!
        return when (ch) {
            "2" -> listOf(InetAddress.getByName(getChannelHost(0)))
            "3" -> listOf(InetAddress.getByName(getChannelHost(1)))
            else -> Dns.SYSTEM.lookup(hostname)
        }
    }
}
```

### HarmonyOS 实现建议
在 HarmonyOS 中，可以通过以下方式实现：

1. **应用启动时获取分流服务器地址**
2. **在 HTTP 请求中设置自定义 Host 头**
3. **或者使用系统代理设置**

## 验证方法

使用 Python 脚本测试：
```python
# 测试登录
python sources/pica_debug.py
```

如果登录成功但获取漫画列表返回 0 条结果，说明是网络限制问题。

## 当前状态

- ✅ 登录功能正常
- ✅ 签名计算正确
- ✅ Token 管理正常
- ❌ 漫画列表获取受网络限制影响

## 后续工作

1. 在应用中添加网络诊断功能
2. 实现分流服务器自动切换
3. 添加代理设置选项
4. 在 UI 中显示网络状态提示
