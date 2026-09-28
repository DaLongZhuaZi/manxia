# 漫匣 Legado 书源 V2 全局切换、语义兼容与真机验收实施计划

计划修订：2026-07-30（V11，全局路由、无损导入、原子证据、真实端点差分、直接私有文件传输、候选上限、失败证据、受支持模拟器端口与可恢复构建门禁版）  
唯一执行状态：`tools/legado-compat/state/legado-compatibility-state.json`。本文件描述目标、边界和自动执行规则；状态文件与自动生成台账才是每个阶段是否通过的事实来源。

## 1. 决策与目标

V2 不再是单条书源的调试执行器，也不再由某个页面临时决定是否使用。对于 Legado 书源，普通用户流量必须由 `NovelSourceManager` 在一次全局策略判定后统一进入 V2：搜索、批量搜索、发现、详情、目录、正文、阅读器、朗读、缓存、校验、调试页和 IMAGE 虚拟图源桥接都遵守同一决定。

这不是“给调试页增加 V2 开关”，而是生产路径的单一内核切换：页面不得自行选择执行器；书源是否可运行、是否需要交互、是否可进入阅读器都由 Manager 的 V2 编译结果和能力状态统一决定。调试页只观察同一条生产路径产生的 trace，不能成为绕过或替代入口。

默认策略是 `V2_FULL_CUTOVER`：

- 新安装、缺失值、损坏值及历史 `V2_FORCE_TEST` 都归一化为全量切换。
- 已无损编译且状态为 `READY` 的标准书源，普通流量只能走 V2；失败时留下 V2 trace 和结构化错误，不补发旧执行器请求。
- `LEGACY_ONLY` 仅保留为用户主动选择的事故恢复模式；它不是 V2 失败后的隐式回退。
- 缺少原始 JSON、登录/验证码/付费交互、外部插件类型、FILE、Review、`imageDecode`、未支持 JS API 等情况必须显示为可分类的阻断，不能以空结果、缓存详情或“导入成功”冒充可阅读。

全量切换表示“全量用户路径由 V2 负责决策”，不表示“458 条真实站点已经全部语义兼容”。后者必须逐种能力、逐个工作流给出真实 V2 与原版 Legado 的对照证据。

## 2. 固定基线与证据边界

- 书源包：`F:\Downloads-E\墨辰整理书源大全7.1（禁止倒卖）.【最新完整】.json`
- SHA-256：`473048A191DE4749FA9C15E0A2F2328A3E86B385A5FCE23EA30432D598D03A67`
- 数量：458；TEXT 339、AUDIO 35、IMAGE 54、FILE 15、外部/插件类型 15。
- 原版对照提交：Legado `95973d186b147fb9ab43a9240021d688e4304fbd`。

自动化只保存脱敏信息：哈希、数量、能力统计、请求计划摘要、状态码、传输类型、最终地址可观测性、规则输出摘要、变量变化计数和错误分类。不得写入原始书源、URL、Cookie、账号、正文、密钥、页面 XML 或截图正文。

任何书源包哈希或 Legado 提交变化都会重置状态机；不同基线的 trace 不允许混合比较。

## 3. 全局执行边界

| 用户路径 | 统一入口 | V2 成功证据 | V2 未接管时的可见结果 |
| --- | --- | --- | --- |
| 单源、全局、分批搜索 | `NovelSourceManager.search*` | `search` trace + 非空界面结果 | V2 错误分类，不回退旧请求 |
| 发现分类和列表 | `getExploreKinds*`、`explore` | 分类或 `explore` trace | V2 阻断/失败，不回退 |
| 详情、目录、正文 | `getBookInfo`、`getChapterList`、`getContent` | `book_info`、`toc`、`content` trace + 阅读器语义 | 不用搜索缓存或章节缓存伪造成功 |
| 阅读器、朗读、缓存 | 只消费上述 Manager 输出 | 同一源哈希绑定的 trace | 用户可见 V2 错误 |
| 校验和调试 | 仍调用 Manager | trace 与校验输出一致 | 不允许独立构造旧执行器 |
| IMAGE 虚拟图源桥接 | 桥接回到 Manager | IMAGE 工作流 trace | 图片解码/请求语义未实现时明确阻断 |
| FILE、Review | V2 公共工作流 + 下游消费者 | 下载或评论消费者和 trace | 当前不能宣称可用 |

静态门禁要求生产 ArkTS 中 `NovelSourceExecutor` 只允许在 `NovelSourceManager` 内构造。任何新增普通入口绕开 Manager 都会使阶段 6/7 失败。

## 4. 无损导入与迁移原则

1. 每个本地书源文件都走 `LargeFileJSONParser` 的 UTF-8 流式路径，不根据文件大小选择不同的解析器。
2. 流式解析器逐对象保留原始 JSON 文本；BOM、跨块多字节 UTF-8、转义引号、嵌套对象和数组均有 ArkTS conformance。
3. 手工文本、网络仓库、编辑器写回、备份恢复仍可从内存 JSON 编译，但必须统一落到 `importCompiledSource`。
4. `novel_source` 的归一化配置与 `novel_source_compatibility` 的原始 JSON、哈希、诊断在同一 relationalStore 事务中提交；任何一步失败均回滚。
5. 同一 source URL 的原始哈希变化会在事务中清除旧哈希的验证和 trace 摘要，避免旧证据给新书源背书。
6. 仅有历史 `configJson`、没有原始 JSON 的记录标为“旧记录/未无损验证”；在全量策略下它会被阻断而非悄然运行旧内核。

## 5. 分阶段交付与自动门禁

### 阶段 0：基线、工具链和 fixture

- 固化书源包哈希、数量、类型和能力矩阵。
- 探测 JDK 21、Android SDK、Android 参考端、HarmonyOS SDK/HDC、真机和 fixture 连通性。
- Android 参考端使用隔离 AVD，并固定在受 Emulator 支持的 5560/5561 console/ADB 端口对；主机重启后若旧实例已失联，总控仅清理该隔离实例的锁并重新启动，不触碰用户 AVD。
- 启动确定性 HTTP、重定向、Cookie 和 ArkWeb fixture；原版 Legado Android 与 HarmonyOS 都输出脱敏 trace。

通过条件：工具链、fixture、Android 参考端、HarmonyOS 测试端、固定输入与原版提交全部一致。

### 阶段 1：无损导入、原子存储和全入口收口

- 验证 458 条文档边界、未知字段、类型、`weight`、`customOrder` 与外部类型不丢失。
- 验证 UTF-8 一字节分块 conformance，避免“仅在 PowerShell 正确、应用内损坏”。
- 验证主书源管理页、备用书源管理页、主菜单分享/打开、外部文件任务都调用同一 V2 流式入口；禁止截断读取、Latin-1 式 `String.fromCharCode` 解码和大小阈值旁路。
- 验证归一化行和 V2 原始记录的同事务写入与哈希变更证据失效。

通过条件：编译、ohosTest、静态旁路扫描、数据库迁移/回滚检查均通过。

### 阶段 2：规则编译、请求计划和 HTTP 语义

- 为 CSS、XPath、JSONPath、Regex、`##`、`&&`、`@put/@get`、模板、JS、URL option 建立带来源位置的 Rule IR。
- 所有 Search、Explore、Info、Toc、Content、File、Review 请求经 `RequestPlanner` 生成不可变 `RequestSpec`，并由统一 transport 返回 `ResponseEnvelope`。
- 对 Header、charset、body、Cookie、redirect、retry、限速、最终 URL 和 option 执行结果产生 trace。

通过条件：fixture 与原版 Android 关键语义无未解释差分；每个 URL option 标注 executed、ignored 或 unsupported。

### 阶段 3：ArkWeb 统一传输

- ArkWeb 与 HTTP 使用相同请求/响应契约，由 Planner 决定 transport。
- 覆盖 `webView`、`webJs`、`sourceRegex`、`webViewDelayTime`、Cookie 回写、最终地址、超时与资源释放。

通过条件：ArkWeb fixture 在 Android/HarmonyOS 产生可复核成功 trace；没有 HTTP 偷偷代替 ArkWeb 的回退。

### 阶段 4：工作流和下游消费者闭环

- TEXT、AUDIO、IMAGE、FILE、Review 分别列出规则输入、V2 输出、下游消费者和错误状态。
- 验证 `preUpdateJs`、`formatJs`、`title`、分页目录/正文、`downloadUrls`、`payAction`、`imageDecode` 的执行或明确拒绝。
- 当前未完成能力不能以 TEXT 通过掩盖：FILE 下载器交接、Review UI、`imageDecode`、付费动作和交互恢复必须各自完成后才解除阻断。

通过条件：每个已保存字段都有消费者或可见结构化拒绝；类型间不互相冒充成功。

### 阶段 5：JS API 契约和交互恢复边界

- `JsApiContractRegistry` 为网络、变量、DOM、文件/二进制、编码加密、浏览器/UI API 建立 `SUPPORTED`、`UNSUPPORTED_API`、`NEEDS_INTERACTION`、`POLICY_BLOCKED` 状态。
- 未知 API 必须定位到规则节点；登录、验证码、付费不自动绕过。

通过条件：复杂 JS fixture 的变量、副作用和错误行为可与原版 trace 对照；禁止静默空值。

### 阶段 6：V2 全局路由封口和界面状态

- 默认策略、显式手动旧内核恢复、无隐式回退、普通入口旁路扫描、IMAGE 桥接、校验、调试、朗读和阅读器全部回归。
- 管理界面同时展示“实际下次请求使用的内核”和“全量切换受阻原因”；不能显示过时的持久化偏好来误导用户。
- 每个工作流完成前持久化按原始 SHA 绑定的脱敏 trace。

通过条件：所有普通入口与管理状态一致；旧内核唯一构造点受限；构建和双端测试通过。

### 阶段 7：真机普通用户连续路径

- 自动在 458 条中选择至多 8 条安全的 TEXT 候选，避免登录、付费、交互和有副作用请求。候选资格必须同时检查 `ruleSearch`、`ruleBookInfo`、`ruleToc`、`ruleContent`、`ruleExplore` 的完整嵌套规则树；仅检查顶层 URL 或声明字段不构成安全候选。包含 `@js`、`<js>`、`java.`、WebView、JavaScript/eval/function 调用的规则树不进入这一轮纯 HTTP 验收，但不得因此被标记为“不支持”。
- 在真机验证：全局 V2 开关、单源搜索、详情、目录、第一章、阅读器交付、四条 trace 回显、强制重启、四条 trace 恢复。
- UI 自动化按精确页面标识与当前标题栏控件定位，禁止用导航历史中的全局文本误判。
- 每次候选切换前，自动清除已恢复筛选框中的旧文本，再通过同一标题栏搜索操作关闭筛选框；输入框残留时不得把追加文本后的错误候选当作真实测试对象。失败只记录脱敏聚合分类（未就绪、无结果、API 阻断、传输/规则错误、空摘要、界面异常），不记录书源名称、URL、Cookie 或正文。
- 失败诊断同时保存候选的不可逆 SHA-256、关键字集合哈希和关键字序号、V2 结果分类、trace 收集状态；这些是阶段 7A 的唯一输入，不保存候选名称、站点地址、原始规则或用户可读正文。

通过条件：四个工作流 HTTP 2xx、`error=none`、非空摘要、阅读器可读、重启后 hash-bound trace 仍可恢复。阶段 7 未通过时保持 `failed` 或 `blocked`，不得被后续诊断改写为 `passed`。

### 阶段 7A：真实端点差分诊断（阶段 7 失败后自动进入）

- 每个候选路径无论在搜索、详情、目录、正文还是阅读器停止，都必须先返回管理页并采集该候选已持久化的 V2 工作流 trace；分类必须区分“目录未交付”“正文仍为 HTML”“正文为空”“界面超时”“缺少 trace”“trace 收集失败”和请求/规则错误，禁止把它们汇总成模糊的“失败”。
- 总控在阶段 7 失败后自动运行原版 Legado 的 test-only instrumentation：使用同一候选 SHA、同一关键字序号、独立 Cookie 容器和临时私有输入文件；输入在测试结束时由原版测试和总控双重删除。只允许无登录、无付费、无验证码、无写操作的安全 GET 候选。
- 原版测试仅输出候选 SHA、工作流停止阶段、搜索/目录/正文长度计数和错误分类；不输出书源名称、URL、Cookie、Header、书名、章节名或正文。
- 只有在“原版 Legado 同端点完成正文、漫匣 V2 对同一尝试失败”的差分被复现后，才把问题归因于 V2 并进入实现修复；两端同样失败时标记为端点失效、反爬或网络差异，不得以此证明 V2 不兼容。

阶段 7A 的 `passed` 只表示差分证据已完整生成，不表示 V2 用户路径通过；它与阶段 7 的失败状态并存，并自动阻断阶段 8。若 7A 自身因测试端、设备或脱敏边界失败，则仍写入不含端点内容的失败类别与证据文件，状态为 `blocked`/`failed`，同样不能推断引擎结论。

### 阶段 8：复杂能力矩阵和原版收敛

- 按 IMAGE、AUDIO、FILE、Review、JS/ArkWeb、Cookie、重定向、分页、登录和图片解码建立真实消费者、fixture、原版差分及真机回归。
- 允许自动请求只限幂等、安全端点；登录、验证码、付费和可能写入状态的样本仅做 fixture 和分类验证。
- 每项能力只有在原版对照、V2 fixture、真实用户路径和下游消费者都通过后才可由 `BLOCKED` 转为 `READY`。

通过条件：无未解释关键差分、可一键回退、旧阅读数据不丢失、debug 构建和设备回归通过。阶段 8 未完成前，产品不能声称“458 条书源全部可用”。

## 6. 自动执行协议

总控为 `tools/legado-compat/Invoke-LegadoCompatibility.ps1`。每阶段依次自动执行：

1. 基线与静态类型/旁路检查；
2. 定向 unit/ohosTest；
3. 数据库迁移与哈希失效检查；
4. Android 原版 instrumentation trace；
5. HarmonyOS fixture、ArkWeb 和真机流程；
6. trace golden diff、允许的真实端点烟测；
7. 构建、安装与报告刷新。

状态只允许 `planned`、`running`、`passed`、`failed`、`blocked`。开始、失败和结束都会原子写入状态 JSON；`finally` 自动刷新推进台账、证据索引、差分摘要和调查报告中的状态区块。失败保留脱敏证据并使总控返回非零；后续阶段自动标记阻断。

构建门禁只对已识别的环境瞬态故障执行有限恢复：当 Hvigor 明确报告工作区 `build.log` 的短暂 `EBUSY` 占用时，总控停止对应 Hvigor 守护进程、等待并重试该构建一次。第二次仍失败或出现任何其他错误，必须如实标记失败；重试本身绝不构成阶段通过证据。

## 7. 当前执行顺序

1. 以 V6 修订重置旧证据状态，重跑阶段 0 和阶段 1。
2. 编译并安装保持用户数据的 debug HAP。
3. 运行 stage 2–6 的 fixture、原版对照和旁路门禁。
4. 在真机运行 stage 7；若任意普通用户工作流失败，保存证据并停止，不使用旧内核掩盖结果。
5. 若阶段 7 失败，自动运行阶段 7A；只有“原版完成、V2 失败”的同端点记录才创建 V2 修复项。两端同失败的候选只进入端点/反爬观察集。
6. 仅在阶段 7 通过后进入 stage 8；再按能力矩阵继续实现 FILE、Review、`imageDecode`、交互恢复、JS API 和不同类型消费者；每次实现后自动重复对应阶段。

## 8. 最终验收标准

最终验收依据语义证据，而不是导入条数：原始字段可复核、请求语义可追踪、工作流字段有消费者、差异可复核、错误能定位、普通用户界面状态真实可见。只有达到这些条件，才可以说明漫匣的 V2 对应能力已与固定 Legado 基线兼容。
