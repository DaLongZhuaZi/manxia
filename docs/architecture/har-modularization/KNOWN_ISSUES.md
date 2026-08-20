# 已知问题 / 遗留事项（Stage 6 收尾登记）

> 维护：2026-08-21｜随 HAR 模块化推进发现的问题登记；修不修、何时修由用户决定。

## #1 FTP/WebDAV 连接测试 ANR（主线程阻塞）
- 现象：运行期 THREAD_BLOCK_6S。点击 FTP/WebDAV 源“测试连接”（或网络文件夹 FTP 入口）时主线程阻塞约 6 秒后系统判 ANR（可能伴随原生转储）。
- 调用链：JsClickFunction::Execute → async FTPNativeClient.testConnection()（manxia_network/.../FTP/FTPNativeClient.ets:203/170）→ libcurl select（curl_easy_perform）同步阻塞 → THREAD_BLOCK_6S。listWithResult（263/226）同理。
- 根因：FTP 原生适配层把阻塞式网络 I/O 放在主线程（无超时下探）；非模块化引入（manxia_network 为 Stage4 既有、本轮未动，功能等价）。
- 建议修法（后续独立任务）：将 testConnection/listWithResult 移出主线程（TaskPool/工作线程封装 + 超时），修完补 UI 回归。
- 状态：2026-08-21 决定暂不修，仅登记。

## 其它登记
- M42（NetworkFolderManager 迁 core）因 ./SMBClientAdapter（native .so）回退 entry：SMB 适配需原生库绑定，core 不可承载；若未来将 SMB 适配整体迁入可承载 native 的网络 HAR 模块再议。

## #2 EPUB Web 划线批注不渲染（待取证定位）
- 现象：EPUB WebView 阅读器划线批注后，页面文字上无下划线；阅读进度恢复正常。
- 分析：逻辑链（保存→查询 HIGHLIGHT→ranges，UnifiedAnnotationManager/EBookDataManager 已迁 core、diff 验证行为等价）与 UI 链（@Watch→runJs __mnxApplyEpubHighlights→__mnxFindTextBoundary 偏移回映→画 div 下划线）均完整；故障收敛于运行时 count/applied。
- 待取证：贴回 `刷新 EPUB Web 划线渲染数据成功…count=` 与 `渲染完成…result={"count":N,"applied":M}` 两行 → 定位 offset 回映/视口坐标/数据之某环。
- 定性：既有 EPUB WebView 标注绘制问题，与 HAR 模块化无因果（非回归）。
- 根因（2026-08-21 取证定版）：注入桥 JS 里 5 处 SafeUtils.parseObj 依赖的 `window.SafeUtils` 从未在页面定义 → 全部 ReferenceError 被 catch 静默退化默认（划线恒 count0、分页退默认）。
- 修复（M47）：BridgeJsBuilder 注入 JS 顶部加 JS 端 SafeUtils.parseObj shim（JSON.parse 封装）。
- 状态：已修复（M47 门禁确认划线恢复）。

## #3 MOBI 无法阅读（转换缓存路径被残留文件占用）
- 现象：导入 MOBI 后无法阅读；[MobiParser] MOBI转换失败: 路径已存在但不是目录: …/__mobi_conv_<base>_<hash>。
- 根因：MobiParser.ensureDirectory 在“目标路径存在但为文件”时直接抛错（不恢复），旧失败产物（同名文件）阻塞目录创建 → 转换失败（懒转换也读不了）。
- 修复（M48）：存在且非目录时，warn + unlink 残留文件 + mkdir 重建。
- 状态：修复待 M48 门禁确认。



