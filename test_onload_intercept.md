# ZLibrary 下载方案完整测试报告

## 测试环境
- 测试方式：代码分析 + JavaScript 行为验证 + curl 测试 + 日志分析
- 日期：2026-05-27
- 约束：不修改任何源代码

---

## 一、问题根因分析

### 1.1 方案 B（Cookie + HTTP）失败原因

```
21:50:15.745  从 WebView 获取到 cookies (125 chars)，尝试 HTTP 下载
21:50:16.704  HTTP 下载失败: 状态码=503
```

`WebCookieManager.fetchCookie()` 返回 125 chars = `siteLanguage` + `bsrv` + `c_token`（3 个 cookie）。

**结论**：Cloudflare 的 `cf_clearance` cookie 不存在于 cookie jar 中。ZLibrary 的 Cloudflare 防护使用了非 cookie 机制（JavaScript 挑战 token 存储在 WebView 内部状态中）。HTTP 下载无法绕过 Cloudflare。

### 1.2 方案 A（分块 JS 传输）失败原因

```
21:50:16.715  分块下载已启动，等待 fetch 完成...
21:50:17.222  分块下载异常: SyntaxError: Unexpected Text in JSON: Empty Text
```

时间线分析：
- 21:50:16.715：执行 startScript（async IIFE + `'started'`）
- 21:50:17.215：第一次轮询（sleep 500ms）
- 21:50:17.222：JSON.parse 失败

**根因**：`runJavaScript` 的回调返回了非预期值。轮询脚本 `window.__dlResult ? window.__dlResult : ''` 在 `window.__dlResult` 为 `undefined` 时应返回 `''`。但可能返回了：
- `"undefined"` 字符串（长度 9，跳出轮询，JSON.parse 失败）
- `"[object Promise]"` 字符串（长度 16，跳出轮询，JSON.parse 失败）
- 空字符串但 ArkTS 的 `JSON.parse("")` 抛出 "Empty Text"

JavaScript 测试验证：
```
JSON.parse("")        → Unexpected end of JSON input
JSON.parse("undefined") → "undefined" is not valid JSON
```

### 1.3 核心问题：runJavaScript 不支持 async 代码

从日志确认（间隔仅 7ms）：
```
21:27:02.929  检测到 /dl/ 链接
21:27:02.936  解析 fetch 结果失败
```

`runJavaScript` 立即返回同步结果（`'started'`），不等待 async IIFE 中的 `fetch()` 完成。

---

## 二、可用 API 分析

### 2.1 onLoadIntercept（可用）

代码库中已有 3 处使用：
- `InvisibleWebViewComponent.ets:173` — 拦截资源请求
- `AniListLoginPage.ets:308` — 拦截 OAuth 回调 URL
- `RhinoSandboxComponent.ets:164` — 拦截请求

```typescript
.onLoadIntercept((event) => {
  const url = event.data.getRequestUrl();
  return true;  // true = 拦截（阻止加载），false = 放行
})
```

**关键行为**：`onLoadIntercept` 在 WebView 开始加载 URL **之前**触发。对于 302 重定向，它会在重定向目标 URL 加载前再次触发。

### 2.2 request.agent（可用，已集成）

`DownloadManager.downloadFileWithAgent()` 已实现（line 769）：
```typescript
const agentConfig: request.agent.Config = {
  action: request.agent.Action.DOWNLOAD,
  url: url,
  saveas: saveas,
  headers: headers,  // 支持自定义 headers
  overwrite: true,
  network: request.agent.Network.ANY,
  mode: request.agent.Mode.BACKGROUND
};
```

支持：自定义 headers（含 Cookie）、进度回调、后台下载、覆盖写入。

### 2.3 onInterceptRequest（可用）

`LegadoWebViewComponent.ets:85` 使用：
```typescript
.onInterceptRequest((event) => {
  const url = event.request.getRequestUrl();
  return null;  // null = 不拦截，继续正常加载
})
```

可以返回自定义 `WebResourceResponse` 来替换响应内容。

---

## 三、推荐方案：onLoadIntercept + request.agent

### 3.1 原理

1. 在隐藏 WebView 上添加 `onLoadIntercept` 回调
2. 用户点击下载 → 通过 JS 触发 `window.location.href = '/dl/URL'`
3. `onLoadIntercept` 拦截 `/dl/URL` → 放行（return false）
4. WebView 内部处理 Cloudflare → 服务器返回 302 重定向到 CDN
5. `onLoadIntercept` 再次触发，拦截 CDN URL → 捕获并阻止（return true）
6. 使用 `request.agent` 从 CDN URL 下载文件

### 3.2 优势
- WebView 处理 Cloudflare（有内部 clearance state）
- 捕获重定向后的实际文件 URL（CDN 通常无 Cloudflare）
- 使用系统下载代理（支持进度、后台、通知）
- 不需要 runJavaScript 传输大文件
- 复用已有的 `downloadFileWithAgent` 方法

### 3.3 风险与应对

| 风险 | 概率 | 应对 |
|------|------|------|
| CDN 也有 Cloudflare | 低 | CDN 通常无 Cloudflare |
| /dl/ 不重定向，直接返回文件 | 中 | 检测 Content-Type，如果是文件则用 onInterceptRequest 捕获 |
| onLoadIntercept 不触发重定向 | 低 | 代码库中已有重定向拦截的使用模式 |
| WebView 挂起（导航后不触发回调） | 低 | 添加超时机制 |

### 3.4 实现计划

**OnlineEBookDetailPage.ets 修改：**
1. 在隐藏 Web 组件上添加 `onLoadIntercept` 回调
2. 添加状态变量 `pendingDownloadResolve` 用于回调通信
3. `handleFormatSelect` 中，对 `/dl/` URL：
   - 创建 Promise，存储 resolve 函数
   - 通过 `runJavaScript` 执行 `window.location.href = downloadUrl`
   - 等待 Promise resolve（由 onLoadIntercept 回调触发）
4. `onLoadIntercept` 回调中：
   - 如果是 `/dl/` URL：放行（return false）
   - 如果是其他 URL（重定向目标）：捕获 URL，阻止加载（return true），resolve Promise
5. 拿到 CDN URL 后，调用 `DownloadManager.downloadFileWithAgent()`

**DownloadManager.ets 修改：**
- 无需修改，`downloadFileWithAgent` 已存在

---

## 四、备选方案：同步 XMLHttpRequest

如果 onLoadIntercept 方案不可行，可以尝试同步 XHR：

```javascript
(() => {
  const xhr = new XMLHttpRequest();
  xhr.open('GET', dlUrl, false);  // false = 同步
  xhr.responseType = 'arraybuffer';
  xhr.send();
  if (xhr.status === 200) {
    const bytes = new Uint8Array(xhr.response);
    // 转 base64 分块传输
  }
})();
```

**优势**：同步执行，runJavaScript 会等待完成
**风险**：
- 同步 XHR 在某些 WebView 中被禁用
- 会阻塞 WebView（隐藏 WebView 无所谓）
- 大文件可能导致内存问题
- 仍然需要分块传输回原生层

---

## 五、测试验证清单

实施前需要验证：
1. [ ] `onLoadIntercept` 是否对 302 重定向的目标 URL 触发
2. [ ] ZLibrary `/dl/` 端点是 302 重定向还是直接返回文件
3. [ ] CDN URL 是否需要 Cloudflare clearance
4. [ ] `request.agent` 能否从 CDN URL 下载文件

---

## 六、最终建议

**优先尝试 onLoadIntercept + request.agent 方案**。这是最干净的解决方案：
- 利用 WebView 的 Cloudflare 处理能力
- 利用已有的 request.agent 下载基础设施
- 不需要在 JS 和原生之间传输大文件
- 复用已有的 DownloadManager 代码

如果 CDN 也有 Cloudflare 或 onLoadIntercept 不触发重定向，再考虑备选方案（同步 XHR）。
