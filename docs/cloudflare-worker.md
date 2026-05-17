# Cloudflare Worker 控制面说明

> 更新时间：2026-05-16
>
> 适用范围：`manxia.top` 的 Deep Link / App Linking / 局域网传书帮助入口 / 可选信令控制面
>
> 当前定位：**控制面、说明页、WebRTC / Native RTC 可选信令层与局域网地址自动引导层**，不承载局域网文件数据平面；`/transfer` 已支持 8 位房间码自动验证连接，后续 DataChannel 文件数据仍应端到端走浏览器与 APP

---

## 一、当前结论

局域网传书的第一阶段仍然坚持：

1. 文件数据直接走 APP 本地 HTTP / WebSocket 服务。
2. `manxia.top` 只负责：
   - `App Linking` 验证文件
   - 深链跳转页面
   - `https://manxia.top/transfer` 说明页与入口页
   - 后续高级连接能力的房间码与 WebSocket 信令协调
   - 后续浏览器 peer 的 WebRTC / DataChannel 发送端页面
3. Worker **不负责**：
   - 扫描局域网设备
   - 代理本地上传
   - 第一阶段大文件中继
   - WebRTC DataChannel 文件片段中转

---

### 1.1 2026-05-15 源码核对结论

当前 `cloudflare/manxia-worker/` 已经实现控制面工程：`/.well-known/applinking.json`、主页、Deep Link 跳转页、`/transfer` 说明页。2026-05-15 已继续补充信令控制面：`TransferSignalRoom` Durable Object、房间码创建接口、状态查询接口、关闭房间接口和 `/signal/{roomCode}` WebSocket 信令路由；APP 侧已新增 `TransferSignalClientService.ets` 并接入传书页“公网”页签；浏览器 `/transfer` 已新增公网房间码 peer 面板。

因此，Worker 与两端基础信令控制面已经开始落实，但它不是当前 MVP 的剩余项，而是后续高级连接能力。要形成可用的房间码 / WebRTC 文件传输链路，还需要继续设计并实现 WebRTC DataChannel 或其他公网数据通道。

### 1.2 2026-05-16 Web 组件 WebRTC 方案下的 Worker 结论

用户已确认 HarmonyOS 侧可以通过 `Web` 组件嵌入 WebRTC 页面来使用 JavaScript `RTCDataChannel`。在这个方案下，Worker 的职责更加清晰：

1. 现有 Durable Object WebSocket 信令骨架可以继续使用。
2. Worker 不需要也不应该接收文件片段。
3. `/transfer` 页面需要从“房间码心跳测试面板”升级为“浏览器 peer WebRTC 发送端”。
4. APP 端 Web 组件作为 host，加载本地 `$rawfile(...)` WebRTC 页面；如真机验证发现 rawfile 安全上下文不满足 WebRTC，再由 Worker 提供受控 HTTPS `/transfer-host` 页面作为备用 host 页面。
5. 因此，当前缺口不是“Worker 端信令设计尚未实现”，而是：**浏览器 WebRTC 发送端、APP Web 组件 host 页面、信令 payload 对接、DataChannel 文件协议、ArkTS 桥接落盘和失败回退尚未实现。**

### 1.3 2026-05-16 Native RTC 方案下的 Worker 结论

继续评估 JSVM / 纯 JS / C 原生路线后，APP 侧优先路线已调整为 Native RTC：

1. Worker 现有 Durable Object 信令骨架仍然可复用，不需要为了 Native RTC 改成文件中继。
2. ArkTS 侧 `TransferSignalClientService.ets` 继续负责房间、Host WebSocket、`offer / answer / candidate / ping` 消息转发。
3. Native 模块只负责 PeerConnection / DataChannel 数据面；Worker 不感知 `libdatachannel`，也不解析 DataChannel 文件协议。
4. APP 已新增 `transfer_rtc_native` NAPI 模块、`TransferNativeRtcService.ets` 和传书页 Native RTC 状态卡，并完成 `libdatachannel` 后端接入，真机运行待验。
5. Worker 已配合把 `/transfer` 浏览器 peer 页面升级为 RTC 测试端；下一步是在该页面上继续补文件选择、分片发送、ACK / 背压和失败回退。

### 1.4 2026-05-16 Worker 部署核对结论

本次核对发现 Worker 代码“没有正确落地”的原因不是 Worker 信令代码不可构建，而是部署链路没有闭合：

1. `cloudflare/manxia-worker/` 是独立 Git 仓库，远端为 `https://github.com/DaLongZhuaZi/manxia-cloudflare-worker.git`；这些改动不会自动跟随主仓库 `manxia` 推送。
2. 本地 Worker 子仓库已有信令改动，但此前没有推送到 `DaLongZhuaZi/manxia-cloudflare-worker` 的 `main` 分支。
3. 本机没有全局 `wrangler`，正确调用方式是先在 Worker 工程内执行 `npm install`，再使用 `npm exec wrangler ...` 或 `npm run deploy`。
4. Cloudflare CLI 初始状态未登录，需要执行 `npm exec wrangler -- login` 完成 OAuth。
5. 原 `wrangler.jsonc` 只配置了 Durable Object，缺少自定义域触发器；已补充：
   - `workers_dev: false`
   - `routes: [{ pattern: "manxia.top", custom_domain: true }]`

已完成的部署动作：

1. Worker 子仓库提交并推送到 GitHub：`8bca8ad Add RTC peer signaling test to transfer page`。
2. Wrangler dry-run 通过，确认 `TRANSFER_SIGNAL_ROOM` Durable Object 绑定有效。
3. 使用 `npm run deploy` 成功部署到 Cloudflare Workers。
4. 当前 Cloudflare Version ID：`93c0956f-4a8c-4031-8c41-f05ee07a3586`。
5. 部署触发器已绑定：`manxia.top` custom domain。

已验证：

1. `https://manxia.top/transfer` 返回 200，页面包含公网房间码面板、8 位房间码自动验证连接逻辑和浏览器 RTC 测试 / 文件发送按钮。
2. `https://manxia.top/.well-known/applinking.json` 返回 200。
3. `POST https://manxia.top/api/transfer/rooms` 返回 201，并生成房间码、host token、host / peer WebSocket URL。
4. WebSocket 信令验证通过：peer 心跳收到 `pong`，peer 发送的 `candidate` 可转发到 host。

### 1.5 2026-05-16 局域网地址自动引导结论

在当前“Worker 房间码 + APP 本地 HTTP 服务”的混合链路下，已补齐从公网入口自动回到局域网直连入口的闭环：

1. Worker 信令消息类型新增 `lan_url`，仍只作为控制消息转发，不中转文件。
2. APP 端在公网房间已连接、浏览器 peer 已进入、本地传书服务已运行且配对码可用时，自动把主局域网地址和配对码下发给 peer。
3. `/transfer` 网页端收到 `lan_url` 后展示自动引导状态、局域网地址、配对码、立即打开 / 取消跳转 / 复制按钮，并在倒计时后执行顶层跳转。
4. 如果 Native RTC DataChannel 已打开，APP 会额外通过 DataChannel 补发同一类 `lan_url` 控制消息，用于验证 RTC 数据通道文本消息可达。
5. 本轮已在同一 `/transfer` 页面补上 RTC 文件发送 alpha：用户取消自动跳转后，可选择文件并通过 DataChannel 按 `mx-transfer-file/0.1` 发送到 APP；Worker 仍不接触文件内容。
6. `/transfer` 网页端已将房间码输入改为“输入或粘贴 8 位 -> 自动格式化 -> 自动查询房间 -> 自动连接 peer WebSocket”；从 `?room=` 进入时同样自动连接。
7. APP 端进入局域网传书页后会自动启动本地传书服务，并在服务就绪后自动创建公网信令房间；公网房间码、网页入口和地址下发状态已前置到顶部局域网传书卡片。
8. 当前文件协议 alpha 使用 JSON + Base64 文本分片承载，待 Native NAPI 增加二进制消息后再升级为真正 `ArrayBuffer` chunk。

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
   - 提供公网房间码 peer 面板，用于 8 位房间码自动验证、自动连接信令 WebSocket 和心跳测试
   - 提供 RTC 文件发送 alpha UI；文件只走浏览器与 APP 的 DataChannel，不经过 Worker
4. `/d/{source}/{contentId}`
   - 漫画内容 Deep Link 落地页
5. `/n?s=...&b=...`
   - 小说内容 Deep Link 落地页
6. `/s/{source}?type=...&query=...`
   - 搜索 Deep Link 落地页
7. `POST /api/transfer/rooms`
   - 创建一次性信令房间，返回房间码、host token、host WebSocket URL、peer WebSocket URL
8. `GET /api/transfer/rooms/{roomCode}`
   - 查询信令房间状态
9. `DELETE /api/transfer/rooms/{roomCode}`
   - 使用 `X-Host-Token` 或 `?token=` 关闭信令房间
10. `GET /signal/{roomCode}?role=host|peer`
   - WebSocket 信令通道，仅转发 offer / answer / candidate / bye / ping / lan_url 等控制消息

---

## 四、与 APP 侧配合点

为让 `https://manxia.top/transfer` 能直接拉起 APP 内的传书页，APP 侧已同步补充：

1. `module.json5` 新增 `https://manxia.top/transfer` 的 App Linking 路由声明。
2. `DeepLinkRouter.ets` 已把网页路径 `/transfer` 映射到 `page/TransferPage`。
3. Worker 页面可直接使用 `manxia://page/TransferPage` 作为拉起目标。
4. `TransferSignalClientService.ets` 已实现 APP 侧房间创建、Host WebSocket 连接、状态刷新、关闭房间和心跳测试。
5. `TransferPage.ets` 已新增“公网”页签，展示房间码、网页入口、Host / Peer 状态，并提供复制房间码 / 链接 / 指引。
6. `TransferNativeRtcService.ets` 已新增 APP 侧 Native RTC 能力检测和 Peer 操作外壳，传书页已显示 Native RTC 数据通道状态。
7. `TransferPage.ets` 已新增局域网地址自动下发状态：条件满足时通过 `lan_url` 把本地访问地址和配对码发送给 Worker 网页端，并保留手动重发入口。
8. `TransferRtcFileReceiverService.ets` 已新增 APP 侧 DataChannel 文件接收状态机，负责 ACK / error、Base64 分片解码、收件箱临时写盘和完成后刷新上传列表。
9. `TransferPage.ets` 进入页面即自动启动局域网传书服务，并在本地服务就绪后自动创建公网房间；顶部局域网传书卡片已前置公网房间码、网页入口、Peer 数量、有效期和下发状态。

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

## 六、信令接口草案

### 6.1 创建房间

`POST /api/transfer/rooms`

请求：

```json
{
  "ttlSeconds": 900,
  "clientName": "HUAWEI Phone"
}
```

返回：

```json
{
  "ok": true,
  "roomCode": "ABCD-2345",
  "protocolVersion": "mx-transfer-signal/0.1",
  "hostToken": "temporary-host-token",
  "expiresAt": 1778832000000,
  "hostWebSocketUrl": "wss://manxia.top/signal/ABCD-2345?role=host&token=temporary-host-token",
  "peerWebSocketUrl": "wss://manxia.top/signal/ABCD-2345?role=peer"
}
```

### 6.2 WebSocket 消息

客户端发送：

```json
{
  "type": "offer",
  "targetRole": "peer",
  "payload": "serialized-sdp-or-ice-message",
  "requestId": "optional-client-request-id"
}
```

服务端转发：

```json
{
  "type": "offer",
  "roomCode": "ABCD-2345",
  "fromRole": "host",
  "fromClientId": "generated-client-id",
  "targetRole": "peer",
  "targetClientId": "",
  "payload": "serialized-sdp-or-ice-message",
  "requestId": "optional-client-request-id",
  "sentAt": 1778832000000
}
```

约束：

1. Worker 只转发控制消息，不转发文件数据。
2. `host` 连接必须携带 `hostToken`。
3. 单房间最多 1 个 `host` 和 4 个 `peer`。
4. 房间默认 15 分钟过期，允许范围为 1 到 30 分钟。
5. 单条信令 payload 上限为 64KB。

---

## 七、后续可继续补的控制面能力

当前这套 Worker 工程已经足够支撑第一阶段开发，并已具备后续高级连接能力的 Worker 端信令骨架。后续如果确实需要再增强，可继续往下加：

1. 传书帮助页多语言文案
2. 版本公告与兼容性说明
3. 更明确的桌面端操作指引
4. 可选的一次性房间码页面
5. WebRTC DataChannel / 中继数据通道接入
6. 房间码链路与真实文件传输状态的联动

不建议在当前阶段直接把它扩成：

1. 局域网发现器
2. 公网文件中继
3. 文件数据平面

---

## 八、信令能力状态

当前已实现：

1. `TransferSignalRoom` Durable Object。
2. `/api/transfer/rooms` 创建房间。
3. `/api/transfer/rooms/{roomCode}` 查询和关闭房间。
4. `/signal/{roomCode}` WebSocket 信令通道。
5. offer / answer / candidate / bye / ping / lan_url 控制消息转发。
6. 房间码、host token、过期清理、基础连接数限制。
7. APP 侧 Worker 房间码 / Host 信令客户端。
8. 浏览器端 `/transfer` 公网房间码 peer 面板。
9. 浏览器端 `/transfer` RTC 测试端，可处理 offer / answer / candidate / bye，通过 DataChannel 发送测试文本，并提供文件发送 alpha。
10. APP 端自动下发局域网地址，Worker 网页端自动倒计时跳转到 APP 本地 HTTP 服务。
11. APP 侧 DataChannel 文件接收 alpha，可把 JSON + Base64 文本分片写入收件箱并回 ACK / error。
12. Worker `/transfer` 房间码输入已支持自动格式化、自动验证和自动连接；APP 端传书页已支持自动启动本地服务、自动创建公网房间并把房间码前置到顶部卡片。

当前未实现：

1. DataChannel 二进制 chunk、50MB 级大文件真机验收和失败恢复验收。
2. 公网文件中继。
3. TURN / 复杂网络回退与可选中继能力。
4. 房间权限细分、多 peer 策略、限流与滥用防护。

结论：以当前局域网直连 MVP 为范围，Worker 控制面和“公网房间 -> 自动打开局域网直连页”的引导已经完成；以未来高级连接能力为范围，Worker、APP、浏览器三端信令控制面已经落地并部署，且自动启动、自动建房、8 位房间码自动连接、自动下发地址与自动跳转已经闭合。APP 侧 Native RTC 已完成 `libdatachannel` 后端接入，DataChannel 文件协议 alpha 已接入收件箱。剩余是真机端到端验收、大文件稳定性、二进制 chunk、复杂网络回退和可能的中继能力。

---

## 九、Web 组件 WebRTC DataChannel 接入方案

> 当前优先级说明：本节仍保留为备用技术路线。2026-05-16 后，APP 侧优先推进 Native RTC + `libdatachannel`，Worker 的职责仍是同一套房间码与 SDP / ICE 信令转发。

### 9.1 Worker 保持控制面边界

后续 WebRTC 传书仍然坚持：

1. Worker 只维护房间、角色、WebSocket 连接与 SDP / ICE 转发。
2. Worker 不存储、不代理、不检查文件内容。
3. 文件数据只通过 `RTCDataChannel` 在浏览器 peer 与 APP Web 组件 host 之间传输。
4. P2P 失败时，页面提示回退 APP 局域网直连上传。

### 9.2 现有信令是否够用

当前 `/signal/{roomCode}` 已支持 `offer / answer / candidate / bye / ping`，单条 payload 上限 64KB，足够承载序列化后的 SDP 和 ICE candidate。

建议保持当前外壳格式：

```json
{
  "type": "candidate",
  "targetRole": "host",
  "targetClientId": "",
  "payload": "{\"candidate\":\"...\",\"sdpMid\":\"0\",\"sdpMLineIndex\":0}",
  "requestId": "browser_candidate_001"
}
```

后续只需补充：

1. 前端脚本对 `payload` 的结构化约定。
2. 更明确的错误码和日志文案。
3. `protocolVersion` 从 `mx-transfer-signal/0.1` 继续演进时的兼容判断。

### 9.3 `/transfer` 页面新增职责

`/transfer` 保留现有说明和打开 APP 能力，同时新增浏览器 peer 发送端：

1. 输入或从 URL 读取房间码。
2. 连接 `/signal/{roomCode}?role=peer`。
3. 创建 `RTCPeerConnection`。
4. 与 APP host 交换 SDP / ICE。
5. DataChannel 打开后允许选择文件。
6. 按 `mx-transfer-file/0.1` 协议发送文件元数据和分片。
7. 根据 APP ack 控制发送节奏。

### 9.4 可选 `/transfer-host`

优先方案是 APP Web 组件加载本地：

```text
$rawfile('transfer/webrtc_host.html')
```

如果真机验证发现 rawfile 页面无法使用 WebRTC 所需安全上下文，可由 Worker 增加：

```text
GET /transfer-host
```

约束：

1. 只作为 APP 内 Web 组件 host 页的 HTTPS 备用来源。
2. `javaScriptProxy` 必须限制可信 URL 权限。
3. 页面不暴露 host token 给浏览器 peer。
4. 页面只接收信令和 DataChannel 文件片段，不提供公网文件上传接口。

### 9.5 DataChannel 文件协议摘要

建议通道名：

```text
mx-transfer-file/0.1
```

控制消息：

1. `file_start`：文件名、大小、MIME、分片大小、总片数。
2. `file_chunk`：分片序号和数据；当前 alpha 使用 JSON + Base64 文本，后续升级为二进制 `ArrayBuffer`。
3. `file_end`：结束标记与可选校验值。
4. `ack`：APP 已写盘到指定序号。
5. `error`：拒绝原因或写盘失败原因。

Worker 不需要理解这些消息；这些消息只在 DataChannel 内流动。当前 `/transfer` 页面只是消息发送端，Cloudflare Worker 运行时不会接收文件内容。

### 9.6 待实现清单

1. APP WebRTC host 页面。
2. ArkTS `TransferWebRtcBridgeService.ets`。
3. `/transfer` 浏览器 peer WebRTC 发送端。（Native RTC 路线下已完成 alpha）
4. JS 与现有 Worker 信令消息的 offer / answer / candidate 双向桥接。
5. DataChannel 分片、ack、背压和失败清理。（Native RTC 路线下已完成 alpha，Web 组件备用路线未做）
6. 真机验证 rawfile / HTTPS host 页面两种加载方式。

---

## 十、Native RTC DataChannel 接入方案

### 10.1 Worker 仍只做信令

Native RTC 路线下，Worker 不需要知道 APP 端使用的是 ArkWeb 还是 C/C++ `libdatachannel`。它只继续处理：

1. 房间创建、查询、关闭。
2. Host / peer WebSocket 会话。
3. `offer / answer / candidate / bye / ping / lan_url` 转发。
4. 房间过期、连接数限制和 payload 大小限制。

### 10.2 APP 侧当前状态

已新增：

1. `entry/src/main/cpp/transfer_rtc/transfer_rtc_native.cpp`
2. `entry/src/main/cpp/types/libtransfer_rtc_native/`
3. `entry/src/main/ets/Framework/Services/TransferNativeRtcService.ets`
4. `TransferPage.ets` 公网页签 Native RTC 状态卡

当前 APP 侧后端代码已切到 `libdatachannel`。真机运行并成功加载依赖时，能力检测目标为：

```json
{
  "backend": "libdatachannel",
  "dataChannelSupported": true
}
```

这表示 ABI、服务封装、UI 入口和真实 Peer/DataChannel 后端接入代码都已完成；文件传输协议 alpha 已接入 APP 收件箱，后续仍需真机验证、二进制 chunk 和大文件稳定性闭环。

### 10.3 Worker 下一步需要配合的点

1. `/transfer` 页面已在当前 RTC 测试端基础上升级为浏览器 peer 文件发送 alpha。
2. 继续通过 `/signal/{roomCode}?role=peer` 发送 `offer / answer / candidate`。
3. 不新增文件分片上传接口。
4. 不把 DataChannel 文件协议放进 Worker 后端；文件协议只在浏览器 peer 页面和 APP Native RTC 后端之间流动。
5. 如后续加入 TURN 配置，可由 `/transfer` 页面读取公开 ICE 配置，但不要暴露 APP host token。
