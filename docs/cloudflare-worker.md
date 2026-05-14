# Cloudflare Worker 控制面说明

> 更新时间：2026-05-14  
> 适用范围：`manxia.top` 的 Deep Link / App Linking / 局域网传书帮助入口  
> 当前定位：**控制面与说明页**，不承载局域网文件数据平面

---

## 一、当前结论

局域网传书的第一阶段仍然坚持：

1. 文件数据直接走 APP 本地 HTTP / WebSocket 服务。
2. `manxia.top` 只负责：
   - `App Linking` 验证文件
   - 深链跳转页面
   - `https://manxia.top/transfer` 说明页与入口页
3. Worker **不负责**：
   - 扫描局域网设备
   - 代理本地上传
   - 第一阶段大文件中继

---

## 二、工程目录

已新增可部署 Worker 工程：

1. [cloudflare/manxia-worker/package.json](/F:/DevEcoStudioProject/manxia/cloudflare/manxia-worker/package.json)
2. [cloudflare/manxia-worker/wrangler.jsonc](/F:/DevEcoStudioProject/manxia/cloudflare/manxia-worker/wrangler.jsonc)
3. [cloudflare/manxia-worker/tsconfig.json](/F:/DevEcoStudioProject/manxia/cloudflare/manxia-worker/tsconfig.json)
4. [cloudflare/manxia-worker/src/index.ts](/F:/DevEcoStudioProject/manxia/cloudflare/manxia-worker/src/index.ts)
5. [cloudflare/manxia-worker/README.md](/F:/DevEcoStudioProject/manxia/cloudflare/manxia-worker/README.md)

---

## 三、当前路由职责

Worker 当前建议托管以下路由：

1. `/.well-known/applinking.json`
   - 提供 HarmonyOS App Linking 域名验证文件
2. `/`
   - 漫匣主页落地页
3. `/transfer`
   - 局域网传书控制面入口页
   - 只负责说明、拉起 APP、提示用户在 APP 内查看二维码和局域网地址
4. `/d/{source}/{contentId}`
   - 漫画内容 Deep Link 落地页
5. `/n?s=...&b=...`
   - 小说内容 Deep Link 落地页
6. `/s/{source}?type=...&query=...`
   - 搜索 Deep Link 落地页

---

## 四、与 APP 侧配合点

为让 `https://manxia.top/transfer` 能直接拉起 APP 内的传书页，APP 侧已同步补充：

1. `module.json5` 新增 `https://manxia.top/transfer` 的 App Linking 路由声明。
2. `DeepLinkRouter.ets` 已把网页路径 `/transfer` 映射到 `page/TransferPage`。
3. Worker 页面可直接使用 `manxia://page/TransferPage` 作为拉起目标。

---

## 五、部署建议

### 5.1 本地调试

进入 Worker 工程目录后执行：

```bash
npm install
npm run dev
```

### 5.2 正式部署

```bash
npm run deploy
```

### 5.3 域名绑定

部署后在 Cloudflare Dashboard 中将 Worker 绑定到：

1. `manxia.top`
2. `www.manxia.top`（如需要）

并确认：

1. `https://manxia.top/.well-known/applinking.json` 可直接访问
2. `https://manxia.top/transfer` 能打开传书说明页
3. `https://manxia.top/d/...` 能进入 Deep Link 跳转页

---

## 六、后续可继续补的控制面能力

当前这套 Worker 工程已经足够支撑第一阶段开发。后续如果确实需要再增强，可继续往下加：

1. 传书帮助页多语言文案
2. 版本公告与兼容性说明
3. 更明确的桌面端操作指引
4. 可选的一次性房间码页面

不建议在当前阶段直接把它扩成：

1. 局域网发现器
2. 公网文件中继
3. WebRTC 主信令核心

