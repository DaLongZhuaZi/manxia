# 漫匣项目 HAR 模块化拆分 — 实施计划（极周密版）

> 生成时间：2026-08-20 01:33
> 状态：以 ./HAR_MODULARIZATION_PROGRESS.md 为唯一实时进度真相源，本文件描述"怎么做"。
> 前置阅读：./HAR_MODULARIZATION_ANALYSIS.md（现状与依赖分析）

---

## 0. 总体执行原则（硬性约束，任何步骤不得违反）

| 编号 | 原则 | 说明 |
|---|---|---|
| P1 | **阶段门禁（用户验收）** | 每个 Stage 收尾必须有"用户编译 + 功能回归测试"，全部通过后才可进入下一 Stage。任何执行方不得越过该门禁自行继续。 |
| P2 | **功能等价** | 每一步都必须保持原有功能等价，禁止顺手改业务逻辑、禁止引入新第三方依赖、禁止改变资源/路由/单例的生命周期语义。 |
| P3 | **UTF-8 全程** | 所有文件读取、写入、改写统一 UTF-8（无 BOM）。 |
| P4 | **备份先行** | 每次侵入性改动前，对改动目标文件在**同目录**生成 `*.bak`；对整批移动，先做"回滚清单"（源→目标→可逆性记录）。 |
| P5 | **最小步进** | 每个 Stage 内部再拆分多个小步，每步改动可独立评审、独立回滚；禁止"目录搬家 + 改 import + 改配置"一次做完。 |
| P6 | **进度实时落盘** | 每完成/中断/失败一个工作包，立即更新 ./HAR_MODULARIZATION_PROGRESS.md（含日期时间、结果、证据）。 |
| P7 | **编译由用户执行** | 本计划中所有构建、真机/预览器运行、安装验证均由**用户**执行（与 AGENTS.md 一致：默认不自动编译）。执行方只做静态检查（import 解析核对、资源引用核对、main_pages 核对）并在交付单中列明"建议用户的验证命令与用例"。 |
| P8 | **单模块顺序串行** | 一次只处理一个目标模块；一个模块未验收，不开启下一个模块。 |

---

## 1. 阶段总览（里程碑）

| 里程碑 | 阶段 | 主题 | 目标模块 | 前置 | 出口门禁 |
|---|---|---|---|---|---|
| M0 | Stage 0 | 基线冻结与拆环预研 | — | 无 | 用户确认基线可用（当前 HAP 构建产物正常） |
| M1 | Stage 1 | 原生 Native 模块 HAR 化 | manxia-native | M0 | 用户编译 + 四类 native 功能回归 |
| M2 | Stage 2 | 核心基础层抽取 | manxia-core | M0（与 M1 互不依赖，可并行但按 P8 串行） | 用户编译 + 启动/日志/DB/缓存/主题回归 |
| M3 | Stage 3 | 图源引擎层抽取 | manxia-source-engine | M2 | 用户编译 + 图源全流程回归 |
| M4 | Stage 4 | 网络传输层抽取 | manxia-network | M2 | 用户编译 + 网络/下载/WebDAV/传书回归 |
| M5 | Stage 5 | 小说域抽取 | manxia-novel | M2、M3（依赖 Source/WebView 侧被抽出的部分） | 用户编译 + 小说全流程回归 |
| M6 | Stage 6 | UI 层拆分 | manxia-reader-ui / manxia-features-ui | M2~M5 | 用户编译 + 全功能冒烟（含各 Ability 入口） |
| M7 | Stage 7 | 收尾与归档 | — | M6 | 用户 release 构建验证 + 文档归档 + 清理 .bak |

> 依赖说明：Stage 1（native）与 Stage 2（core）互不依赖；Stage 3 依赖 core；Stage 4 依赖 core（部分依赖 source-engine 侧类型则顺延）；Stage 5 依赖 core + source-engine 中被 Novel 使用的部分；Stage 6 最后（UI 依赖全部下层）。
> **排序原则**：先 native（收益最大、与业务逻辑隔离最好）→ core → 引擎层 → UI。若用户希望先做 core 也可调整，但必须一个模块一个模块走完整门禁。

---

## 2. 统一阶段模板（每个阶段必须包含以下内容）

对下面的每个 Stage，均按此模板展开并落实：

1. **目标**：一句话
2. **范围清单**：精确到目录/文件（列出"搬入新模块的源路径清单"与"留在 entry 的路径清单"）
3. **前置与拆环工作包**：若本阶段依赖解环，先列出解环子任务及其验收
4. **操作步骤**：编号小步（S-x.y），每步包含：改动文件、改动方式、验证方式（静态）
5. **配置改动**：根 build-profile.json5 / 根 oh-package.json5 / 新模块 build-profile.json5 / 新模块 oh-package.json5 / 新模块 hvigorfile.ts / entry 的 oh-package.json5 与 main_pages.json5 的差异 diff 摘要
6. **资源处理**：涉及 resources/rawfile 的迁移与 `$`r/`$`rawfile 引用核对
7. **backup 与回滚预案**：备份路径 + 逐小步回滚命令/步骤
8. **完成标准（用户验收）**：给用户的编译命令 + 真机/预览器回归用例清单 + 通过定义
9. **出口条件**：验收通过确认后，才在 PROGRESS 中标记该阶段完成

---

## 3. Stage 0 — 基线冻结与拆环预研

### 3.0 目标
锁定"可运行基线"，为后续每一步提供对比基准；同时完成少量必要的预研，防止后面返工。

### 3.1 范围
- 记录当前 git 状态（branch / 已修改文件 / 未跟踪文件），快照关键配置（build-profile.json5、oh-package.json5、entry/module.json5、main_pages.json）。
- 确认当前本地构建产物：`entry/build/default/outputs/default/entry-default-signed.hap` 是否存在及时间戳（用户协助查看）。
- 预研 4 项（产出结论写入 PROGRESS）：
  - R0.1 Native 跨模块 .so 解析机制：`libxxx.so` 的 file: 依赖在移动进新模块后 entry 能否仍编译（需要 ohpm 传递解析；查官方文档"har 依赖 sdk/native 模块方 式"，给出 A/B 两套方案：方案A=每个 so 的 types 保留在 manxia-native 内并在其 oh-package.json5 声明，ent-entry 直接 file: 依赖 manxia-native；方案B=entry 沿用 file: 直指 manxia-native/src/main/cpp/types/xxx）。结论记档后阶段内验证。
  - R0.2 main_pages / NavPathStack 跨模块页面注册的实际写法样例（官方文档确认页面路径与可访问性）。
  - R0.3 资源迁移规则：rawfile 与 `$`r 资源在 HAR 中的引用约束（同名冲突、混淆未开启，低风险，仍需确认）。
  - R0.4 现有 `*.bak` 命名与回滚习惯盘点（与 AGENTS.md 的约定对齐）。

### 3.2 交付物
- `docs/architecture/har-modularization/baseline_snapshot.md`（基线快照）
- PROGRESS 更新到 M0 完成。

### 3.3 用户验收（门禁 M0）
- 用户确认当前 App 在该基线可正常编译并可启动到主界面（漫匣使用手册相关页面可用）。
- 验收通过后进入 Stage 1。

---

## 4. Stage 1 — Native 模块 HAR 化（目标模块 manxia-native）

> 目标：4 个 so（libavif_decoder / libjsvm_engine / libwebdav_native / libtransfer_rtc_native）从 entry 的 CMake 大树中独立成 `manxia-native` 模块，entry 只保留 thin 依赖。

### 4.1 范围清单
- **搬入 manxia-native**：
  - `entry/src/main/cpp/avif`（仅源码；排除 build_windows 及其产物）
  - `entry/src/main/cpp/quickjs`
  - `entry/src/main/cpp/webdav`（仅源码；排除 build-curl-*/install-*/libssh2 产物等）
  - `entry/src/main/cpp/transfer_rtc`（仅源码；排除 build-*/install-* 产物与 third_party 中评估可省项）
  - `entry/src/main/cpp/types/`（4 个 so 的 index.d.ts + oh-package.json5）
  - `entry/src/main/cpp/third_party/libsmb2`（SMB 支持，评估是否本阶段一并迁移或先留在 entry）
  - `entry/src/main/cpp/CMakeLists.txt` → 迁移为新模块的模块级 CMakeLists（保留各子项目 target 结构）
- **留在 entry**：`entry/src/main/cpp/types` 可能随工程调整；`build-transfer-rtc-native-test` 等测试/产物目录在本阶段先**删除**（属历史产物，放到 Stage 1 的清理子任务）。
- **entry 侧**：`entry/oh-package.json5` devDependencies 中 5 个 `lib*.so` file: 依赖按 R0.1 结论改写；`entry/build-profile.json5` 移除 `externalNativeOptions`（native 构建整体移出新模块）。

### 4.2 前置
- Stage 0 的 R0.1 结论（必须先行，作为方案选择依据）。

### 4.3 操作步骤（每步独立可回滚）
1. S1.1 建模块骨架：`manxia-native/` 下建 `build-profile.json5`、`oh-package.json5`、`hvigorfile.ts`(harTasks)、`hvigor/\仓库` 引用；读写全部 UTF-8。
2. S1.2 根 `build-profile.json5` 注册 `manxia-native` 模块（srcPath "./manxia-native"，targets default）；根 `oh-package.json5` 添加 `"manxia-native": "file:./manxia-native"`。
3. S1.3 产物目录清理备案：先登记 `entry/src/main/cpp` 下所有 build-*/install-*/build_windows/build-transfer-rtc-native-test 目录清单（列入 PROGRESS），经用户确认后删除（保留 .bak 清单以便需要时重建——这些目录本质是构建产物，可再生成）。
4. S1.4 物理迁移源码目录（avif/quickjs/webdav/transfer_rtc/types/third_party）至 manxia-native/src/main/cpp/。**大目录**（webdav 79MB、transfer_rtc 98MB，含巨量缓存/构建产物）迁移前必须先按 .gitignore 规则排除产物；迁移采用"逐目录 move + 校验文件数/哈希抽样"。
5. S1.5 改写 CMake：新模块 CMakeLists 各子 target 输出 so 名称不变（保证 ArkTS import 名不变）。entry 的 `externalNativeOptions` 移除。
6. S1.6 按 R0.1 方案调整 entry/oh-package.json5 对 4 个 so 的依赖；需要时在 manxia-native/oh-package.json5 声明 `lib*.so: file:./src/main/cpp/types/*`。
7. S1.7 静态核对：`grep 'lib*.so'` 全 ets，确认 ArkTS 侧 import 名一个都不变；核对 so 名与 target 输出名一一对应；`import` 解析表的 native 行回归比对。
8. S1.8 产物/引用残留检查：确保 entry 无对旧 cpp 路径的引用（CMakeLists、oh-package、hvigorfile、build-profile）。

### 4.4 备份与回滚
- 迁移前整块 `entry/src/main/cpp` 以 git 记录为回滚红线（当前在版本库中的路径为准）；未纳入 git 的历史产物目录单独列清单。
- 回滚=整模块恢复：git checkout 相应路径 + 还原根配置（改动前各配置文件先 `cp xxx xxx.bak_harmod`）。

### 4.5 用户验收（门禁 M1）— 建议命令与用例
- 编译：`hvigorw assembleHap --no-daemon`（用户在高版本入口执行，见 AGENTS.md 2.2）。
- 回归用例：
  1. AVIF：AvifTestPage / 漫画阅读含 avif 图片可正常加载（libavif_decoder）。
  2. JS 引擎：详情/图源经 NGF或 Novel 的 JS 脚本执行正常（libjsvm_engine）；JsvmPlaygroundPage 可运行。
  3. WebDAV：备份页 WebDAV 配置+上传/下载、远程书库（libwebdav_native）。
  4. 传输传书（RTC）：局域网传书/transfer 功能（libtransfer_rtc_native）。
  5. SMB（若本阶段迁移 libsmb2）：NetworkFolderPage 的 SMB 连接。
- 通过定义：以上全部可用且与拆分前的行为一致。

---

## 5. Stage 2 — 核心基础层抽取（目标模块 manxia-core）

> 目标：把"纯数据 + 基础能力"层抽成 manxia-core，供上层所有模块与 entry 共享。

### 5.1 前置拆环工作包（Stage 2 第一优先，单独验收）
- W2.1 处理 8 个反向 import Framework 的 Utils 文件：
  - `Utils/WidgetDataSync`：依赖 DataService/DataManager/EBookDataManager/NovelDataManager → 改为"通过已下沉的数据层接口 + 订阅/事件"访问，或随其依赖就近归入上层模块。
  - `Utils/Logger`：依赖 Debug/LogCollector 与 Utils/TimeUtils → LogCollector 下沉到 core（其自身依赖检查后），Logger 保持薄封装。
  - `Utils/WindowManager`：依赖 ThemeManager → 用主题抽象接口（core 内定义 ThemeProvider/ThemeColors），ThemeManager 实现注入。
  - `Utils/AvifTranscoder`、`Utils/CompressionUtils`：依赖 Storage/SandboxManager → SandboxManager 下沉进 core（它本身是纯文件沙箱工具，符合）。
  - `Utils/LogFloatingWindow`：依赖 ThemeAware/ThemeManager/Debug/LogCollector/Utils/TimeUtils → 该组件是 Debug 特性，整体归入 Debug 域（不留在 core），UI 依赖跟随。
  - `Utils/WelcomeGuideTestHelper`：依赖 Managers/WelcomeGuideManager → 是测试辅助，随 Guide 域走或留在 entry 测试路径。
- W2.2 校验环消除：对全量 810 文件重跑 import 解析，确认 core 候选集不再反向依赖上层，且上层只单向依赖 core（输出依赖矩阵快照存 PROGRESS）。

### 5.2 范围清单（搬入 manxia-core）
- `entry/src/main/ets/Utils`（解环后的纯工具子集+Logger）
- `entry/src/main/ets/Models`
- `entry/src/main/ets/Data`（ResourceMap）
- `entry/src/main/ets/libs`（htmlparser）
- `Framework/Types`、`Framework/Core`、`Framework/EventBus.ets`、`Framework/Lifecycle`、`Framework/Database`（框架层4文件）、`Framework/Storage/SandboxManager.ets`、`Framework/Compress`、`Framework/ImageProcessing`、`Framework/Scraper`（若其依赖允许）
- 视 W2 结果决定 `Framework/Theme` 是否进 core（若 Theme 依赖 Managers/Components 则留上层，只下沉抽象）。
- **不搬**：Managers、Components、Novel、Reader、NGF、WebView、Services、Data(业务管理器)、Initialization 等业务/UI 文件。

### 5.3 操作步骤
1. S2.1 建 manxia-core 模块骨架（同 4.3-S1.1 规范）。
2. S2.2 执行 W2.1/W2.2 解环（工作包内每个文件改完即静态核对）。
3. S2.3 注册模块（根 build-profile/根 oh-package 加 file: 依赖）；entry 与后续模块依赖 manxia-core。
4. S2.4 迁移文件：优先以"目录级 move + 全量 import 重写"两步走。import 重写策略：统一改用相对路径（跨模块用 `@manxia/core` 包名或文件相对路径——以 R0 预研与官方 best practice 为准），用脚本批量改写后逐文件核对；禁止手写 `any`/放宽类型。
5. S2.5 资源核对：若 rawfile（help/localization 等）随 core 资源迁移，逐一核对 `$`rawfile('*') 引用；资源同名冲突登记。
6. S2.6 静态验证：全量 import 解析重跑；`main_pages` 无变化；对迁出的符号做"导出面清单"，作为跨模块契约。
7. S2.7 写《模块契约说明》(API surface) 进 docs（供上层模块引用，避免重复定义）。

### 5.4 用户验收（门禁 M2）
- 编译通过（assembleHap）。
- 回归：冷启动到主界面、设置项持久化（SettingsManager/存储）、数据库（书架/历史/下载记录）、缓存、主题切换、日志面板可用。

---

## 6. Stage 3 — 图源引擎层抽取（目标模块 manxia-source-engine）

### 6.1 前置拆环
- W3.1 切断反向引用页：`Framework/Source` → `pages/SourceDetailPage` 改为 `SourceDetailAbilityParamStore`/回调路由（已有同类模式可复用）；`Framework/WebView` → `Framework/SourceEditor` 等如何处理按实际依赖（webview、source、sourceeditor 整组同进一个模块即可内部消化）。
- W3.2 确认 NGF 的 index.ets 导出面稳定（作为模块对外契约）；NGF 依赖的 Managers 中若有跨域单例，通过 DependencyContainer 注入而非直接 import。

### 6.2 范围清单（搬入 manxia-source-engine）
- `Framework/NGF`（60 文件，含 6 层子目录）
- `Framework/WebView`
- `Framework/Source`
- `Framework/SourceEditor`
- `Framework/Parsers`
- `Framework/Search`
- 视依赖：`Framework/Scraper`（若已在 core 则不动）
- **不搬**：SourceDetailPage 等 page 文件（留在 entry/features），经参数 store 沟通。

### 6.3 操作步骤
（同 S2 的"骨架→注册→迁移→改写→核对→契约"六步，针对本模块。）
特殊点：
- S3.x WebView 引擎含 `WebViewContainerPage` 等页面组件，确认是否为可注册页面（若是，登记进 entry main_pages 或改为不依赖 main_pages 的组件化用法）。
- S3.x 图源配置/rawfile（manga_sources、webview_config）若随模块迁移，逐一核对引用。

### 6.4 用户验收（门禁 M3）
- 编译通过。
- 回归：图源搜索→详情→章节→阅读→下载→图源管理→图源编辑器→WebView 在线阅读全链路；SourceDetailAbility 入口可用。

---

## 7. Stage 4 — 网络传输层抽取（目标模块 manxia-network）

### 7.1 范围清单（搬入 manxia-network）
- `Framework/Network`、`Framework/FTP`、`Framework/WebDAV`、`Framework/Download`、`Framework/Task`、`Framework/Cache`、`Framework/ExternalFile`
- 依赖 item 若在 core/source-engine 之外，先按依赖方向处理；网络层对 `libwebdav_native.so` 的 import 沿用 Stage 1 后的解析方式。

### 7.2 步骤与门禁
（同模板；验收 M4：编译 + 网络请求/代理/下载管理器/WebDAV 备份与远程库/局域网传书（FTP 部分）/外部文件任务回归。）

---

## 8. Stage 5 — 小说域抽取（目标模块 manxia-novel）

### 8.1 前置拆环
- W5.1 断 `Framework/Novel` → `pages/MangaDetailPage`、`pages/NovelBookshelfPage`、`pages/settings` 的反向引用：改为参数/回调/EventBus（种子已有 IEventPayload 事件机制）。
- W5.2 ReadAloud 对 Novel 的依赖在本模块内部消化；Rss 对 Novel/Models 依赖内部消化。

### 8.2 范围清单（搬入 manxia-novel）
- `Framework/Novel`（51 文件，含 Legado JS 运行时、Rhino/Wasm、Novel 数据/源管理）
- `Framework/ReadAloud`
- `Framework/Rss`
- 该域相关 rawfile（rhino_sandbox/wasm_modules 若本模块独占则随之迁移，否则留在 entry 由路径引用）

### 8.3 门禁 M5：编译 + 小说书架/详情/搜索/阅读/Source 管理/朗读/规则排错/RSS 订阅阅读全回归。

---

## 9. Stage 6 — UI 层拆分（目标模块 manxia-reader-ui / manxia-features-ui）

> 最重、最后。UI 层页面大量直连 Framework 单例；本阶段以"把页面与页面+组件按功能域整体搬到 HAR，并保持 main_pages 注册与 NavPathStack 字符串路由不变"为唯一目标，**不做任何 UI 重构**。

### 9.1 建议的分组（可按实际依赖再细化）
- manxia-reader-ui：`Framework/Reader` + components 中 Manga*/EBook*/文本阅读组件 + 阅读类页面（MangaReaderPage、EBook*、Novel* 阅读页、EpubWebViewReaderPage、Komga/Suwayomi Reader 等）。
- manxia-features-ui：`pages/settings` 组（27）+ DataManagement/DownloadSync/Transfer/Backup/Source*/NovelSource*/Rss*/设置类页面 + 对应 components（backup/editor/source 等）。

### 9.2 关键操作点
- S6.1 每个搬入 HAR 的页面，一律在 entry `main_pages.json` 保留同名字符串条目（跨模块页面注册），路由名（NavPathStack push 用的 name）不变。
- S6.2 页面间 import（如 MainMenuPage → 各页面）跨模块改写；MainMenuPage 本身可留在 entry 或随 features-ui，二者选其一根节点，避免跨模块循环菜单引用。
- S6.3 更新 imm板式/沉浸式公共组件引用的目标模块路径。
- S6.4 每个 Ability 的入口页（MangaReaderAbilityPage 等）与对应 Ability 的 srcEntry 保持 entry 内或显式声明跨模块，需逐一验证。

### 9.3 门禁 M6：编译 + 全功能冒烟（用户按验收清单逐项）：启动、导航/沉浸式、各阅读器、设置全部子页、备份、传输、数据管理、图源管理、小说域、RSS、各 Ability 的深链/文件打开入口。

---

## 10. Stage 7 — 收尾与归档

- S7.1 清理本计划引入的 `*.bak` 与 .bak_harmod（在确认全部验收后）。
- S7.2 移除残留：`Framework/Network.bak`、`Framework/ImageProcessing.bak` 等历史目录统一登记处理。
- S7.3 更新根 README/docs 索引：模块清单、构建入口、依赖图。
- S7.4 用户 release 构建（`assembleHap -p buildMode=release`）验证；可选安装真机冒烟。
- S7.5 归档 PROGRESS 最终状态，关闭本计划（更新目标状态为完成）。

---

## 11. 风险登记册（持续更新于 PROGRESS）

| 编号 | 风险 | 概率/影响 | 缓解 |
|---|---|---|---|
| R1 | Native 跨模块 .so 无法被 entry 解析/打包 | 中/高 | R0.1 预研先行；方案A/B 双选；保留 native 在 entry 的"最后回滚线" |
| R2 | 大目录迁移（webdav/transfer_rtc 共 177MB）慢/脏/误带产物 | 高/中 | 先清产物再迁移；哈希抽样校验；.gitignore 校验 |
| R3 | Utils↔Managers 环切不净导致 core 无法独立编译 | 高/高 | W2.1 逐个文件解耦 + W2.2 全量 import 复扫 + 单模块编译冒烟 |
| R4 | 业务层反向引用页（Novel/Source/Reader→pages）拆模块后循环依赖 | 中/中 | 每域前置拆环工作包；先于迁移完成 |
| R5 | 页面/资源跨模块注册或 `$`r/`$`rawfile 引用失效 | 中/中 | main_pages 不变式 + 资源引用 grep 全量核对 |
| R6 | 重置 import 引入类型放宽（违反 ArkTS 规范） | 中/中 | 机器改写 + 人工抽查 + 编译期 strict 校验 |
| R7 | hvigor daemon / .cxx 缓存冲突（生成器 mismatch） | 低/高 | 按 AGENTS.md：改模块隔离目录；遇 generator 报错先查缓存，不误判命令 |
| R8 | 单例/AppStorage 跨模块双份化（如路径变更导致同文件存在两份） | 低/高 | 迁移用 move（非 copy）；编译后 grep 重复定义 |
| R9 | Windows 编码/路径问题（含中文路径"漫匣"） | 中/低 | 全流程 pwsh + UTF-8；避免硬编码路径 |
| R10 | 门禁被跳过导致"大爆炸"回归失控 | — | P1/P8 硬性约束 + PROGRESS 门禁状态机记录 |

---

## 12. 用户验收清单模板（每阶段交付时附在 PROGRESS）

```text
阶段：Mx Stage x（模块：xxx）
编译：hvigorw assembleHap --no-daemon  →  通过 / 失败（贴报错）
启动：冷启动到主界面  →  通过 / 失败
回归用例：
  [ ] 用例1（预期行为）
  [ ] 用例2
  ...
结论：验收通过 / 需修复（问题清单：___）
验收人/日期：____
```

---

## 13. 执行顺序与"第一个实际动手"建议

- 建议第一个实际动手的 Stage 为 **Stage 1（native HAR 化）**：隔离度最好、不动任何业务代码、收益（构建提速）最直观，且最容易验证"App 功能不受影响"。
- 若用户更希望先消除最大的"重构风险"（Utils 环），则第二个选择为 Stage 2 的 W2.1 拆环工作包（可先行于 core 抽取单独验收）。
- 后续每开启一个 Stage 前，须回到本文件确认前置与本阶段范围清单，并已在 PROGRESS 标记"进入中"。
