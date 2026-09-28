# 漫匣项目 HAR 模块化拆分 — 现状分析

> 生成时间：2026-08-20 01:33
> 仓库根目录：F:\DevEcoStudioProject\manxia
> 关联文档：实施计划见 ./HAR_MODULARIZATION_PLAN.md，进度台账见 ./HAR_MODULARIZATION_PROGRESS.md

---

## 1. 现状基线

### 1.1 模块与构建

- 根 `build-profile.json5` 的 `modules` 只有 **`entry`** 一个模块：
```json5
"modules": [ { "name": "entry", "srcPath": "./entry", "targets": [{ "name": "default", "applyToProducts": ["default"] }] } ]
```
- 产品目标：`targetSdkVersion: 6.1.0(23)` / `compatibleSdkVersion: 6.1.0(23)`，runtimeOS HarmonyOS。
- 根 `oh-package.json5` 仅三个第三方依赖：`@ohos/oh7zip`、`@ohos/minizip`、`buffer`。
- git 基线：分支 `agent/supporters-json`；工作区有少量已修改文件（AppScope/app.json5、changelog 等）——**拆分前必须先落一个基线快照**（见 PLAN Stage 0）。

### 1.2 代码体量（全部在 entry 中）

| 部分 | 规模 | 明细 |
|---|---|---|
| ArkTS 源码 | **810 个 .ets ≈ 25MB** | Framework 529 文件/10.9MB；pages 134 文件/10.5MB；components 65 文件/2.1MB；Utils 33 文件/338KB；libs 14/167KB；Data 5/164KB；Models 14/158KB |
| 原生 C++ | **4 个 .so**，源码树极大 | libavif_decoder(avif，含 build_windows 产物，整个目录 63.8MB/2182 文件)；libjsvm_engine(quickjs，3.5MB/73 文件)；libwebdav_native(webdav/curl/mbedtls/libssh2，含 build-*/install-* 产物，整个目录 79MB/6645 文件)；libtransfer_rtc_native(libdatachannel 系，含 build-*/install-* 产物，98.7MB/7297 文件)。入口构建由 `entry/src/main/cpp/CMakeLists.txt` 统一串联；`cpp/types` 下四个子目录（libavif_decoder/libjsvm_engine/libtransfer_rtc_native/libwebdav_native）各含 index.d.ts + oh-package.json5 |
| resources | 283 文件 / 12.9MB | base + dark；rawfile 含 manga_sources、rhino_sandbox、wasm_modules、code_editor、help、localization、update、webview_config 等 |
| 页面/Ability | main_pages.json 16 页 | SplashPage、WelcomeGuidePage、MainMenuPage 及各 Ability 入口页 |
| Ability | 13 个 | EntryAbility + 12 个子 Ability（MangaReader/EBookReader/NovelReader/ReadAloudPlayer/FileEditor/ExternalFileTask/RemoteControl/SourceDetail/LegadoArkWebConformance）+ Backup/Form/Share 扩展能力，全部挂在 entry |

最大页面文件：MainMenuPage(1.3MB)、MangaReaderPage(570KB)、UnifiedDetailPage(510KB)、DataManagementPage(468KB)、SourceDetailPage(295KB)、ThemeSettingsPage(276KB)；pages/settings 整组 27 文件/1MB。

---

## 2. 代码组织（ets 目录树要点）

- `entry/src/main/ets/Framework`：529 个文件，按子系统分目录（Managers 33、Components 56、Novel 51、Reader 33、NGF 60、WebView 18、Services 18、Source 25、ReadAloud 15、Cache 12、Parsers 9、Search 9、Network 7、WebDAV 6、Rss 5、Download 8、Storage 7、Database 4、Distributed 7、Theme 5、…）。
- `entry/src/main/ets/pages`：134 个页面文件，主线为 MainMenuPage 聚合 + 各阅读器/设置/图源/小说/RSS 功能页，settings 子目录 27 个。
- `entry/src/main/ets/components`：65 个组件，30+ 个 `Manga*` 阅读器视图/规划器 + EBook/文本阅读组件 + 通用面板。
- `entry/src/main/ets/Utils`：33 个工具（Logger、SafeUtils、WindowManager 等）。
- `entry/src/main/ets/Data|Models|libs`：ResourceMap / 数据模型 / htmlparser 等。
- Native 依赖引用方式（ArkTS 侧）：按 .so 名称 import，例如：
  ```ts
  import quickjs from 'libquickjs_engine.so';
  import avifDecoderNativeImport from 'libavif_decoder.so';
  import webdavNativeModuleImport from 'libwebdav_native.so';
  import transferRtcNativeModuleImport from 'libtransfer_rtc_native.so';
  ```
  这些名称解析依赖 `entry/oh-package.json5` 的 devDependencies 映射：`libxxx.so: file:./src/main/cpp/types/xxx`。**拆分 native 时这一层解析方式是关键风险点**（详见 PLAN Stage 1）。

---

## 3. 依赖（import）关系分析

对全部 810 个 .ets 做了 import 全量解析，提取跨目录依赖边。核心结论：

### 3.1 底部存在依赖环（拆分首要障碍）

- `Utils ↔ Framework/Managers ↔ Framework/Data` 成环：
  - `Utils/WidgetDataSync` import `Services/DataService`、`Data/DataManager`、`Data/EBookDataManager`、`Novel/NovelDataManager` 等
  - `Utils/Logger` import `Framework/Debug/LogCollector`、`Framework/Utils/TimeUtils`
  - `Utils/WindowManager` import `Managers/ThemeManager`；`Utils/AvifTranscoder`、`Utils/CompressionUtils` import `Storage/SandboxManager`；`Utils/LogFloatingWindow` import `Components/ThemeAware`
  - 反向：Framework 侧共 100+ 处 import `../Utils/*`（其中 Managers 48 处、Components 48 处）
- 含义：**不能简单把 `Utils` 独立成底层模块**，必须先做约 8 个 Utils 文件的解耦/下沉（工作包见 PLAN Stage 2）。

### 3.2 业务层反向引用 UI 页面（领域不纯）

- `Framework/Novel` import `pages/MangaDetailPage`、`pages/NovelBookshelfPage`、`pages/settings`
- `Framework/Reader` import `pages/MangaReaderPage`、`pages/EBookReaderRouteTypes`
- `Framework/Source` import `pages/SourceDetailPage`
- `Framework/Adapters` import `pages/NovelBookshelfPage`、`pages/EBookReaderRouteTypes`
- 含义：把业务子系统抽成 HAR 时，这些反向引用必须率先改为接口/事件/store 转发（部分已有可复用模式，如 `SourceDetailAbilityParamStore`）。

### 3.3 近叶子 / 强内聚 / 纠缠 分档

| 档位 | 子系统 | 规模 | 说明 |
|---|---|---|---|
| 近叶子（可先抽） | Models | 14 文件 | 仅依赖 Fw/Types、Fw/Utils、Utils |
| 近叶子 | Fw/Types、Fw/Core、Fw/EventBus、Fw/Lifecycle、Fw/Database(框架) | ~13 文件 | 依赖面窄 |
| 近叶子 | Data(ResourceMap)、libs/htmlparser、Fw/Scraper、Fw/Compress、Fw/ImageProcessing | ~13 文件 | 依赖 Utils 为主 |
| 强内聚（整块可搬） | Fw/NGF（图源执行引擎） | 60 文件（14 层子目录，经 index.ets 收敛导出） | 对外主要依赖 Utils/Managers/DependencyContainer/EventBus/Storage |
| 强内聚 | Fw/WebView + Fw/Source + Fw/SourceEditor + Fw/Parsers | 61 文件 | webview↔source↔sourceeditor 互相依赖，需整组搬 |
| 强内聚 | Fw/Network + Fw/FTP + Fw/WebDAV + Fw/Download + Fw/Task + Fw/Cache + Fw/ExternalFile | ~37 文件 | 网络/传输域 |
| 强内聚 | Fw/Novel + Fw/ReadAloud + Fw/Rss | 71 文件 | 小说域（含 Legado JS 运行时） |
| 纠缠（最后） | pages 106 根 + settings 27 + components 65 + Fw/Reader + Fw/Components | ~250 文件/14MB | UI 层，几乎全部直连 Framework 单例，按功能域分组 |

---

## 4. HAR 边界与目标澄清

- **HAR = 静态共享库**：构建期全部编译进宿主 entry HAP。**不能减少最终包体积/启动耗时**；价值在：源码解耦、模块级增量/并行构建提速、复用、独立单测、仓库治理。
- 若未来目标变为"瘦身 App/按需加载/多应用共享"，需升级为 **HSP（动态共享包）** 评估，不在本计划范围内（但本计划的分层结构对 HSP 化是友好的前置）。
- HAR 能力覆盖：ArkTS 代码、ArkUI 页面（页面须登记进宿主 `main_pages.json`，以字符串路由访问；本项目 NavPathStack/GlobalNavStack 兼容）、资源（含 rawfile）、以及 Native C++（so 随 HAP 分发）。
- 跨模块共享：单例、AppStorage、EventBus 在静态链接下仍处于同一 HAP/进程，机制不变。

---

## 5. 拆分候选清单

### A 级（改动小、收益直接、建议最先）
1. **4 个 native 库 HAR 化**（avif/jsvm_engine/webdav/transfer_rtc）——独立模块、独立 CMake、独立增量构建；同时可把 `cpp` 下 build-*/install-*/build_windows 等历史产物目录剔除出源码树。
2. **manxia-core**：Models、Data、libs/htmlparser、Fw/Types、Fw/Core、Fw/EventBus、Fw/Lifecycle、Fw/Database(框架)、Storage/SandboxManager、Fw/Compress、Fw/ImageProcessing、Fw/Scraper —— 前置是解 Utils 环（3.1）。

### B 级（需一次小重构，属第二优先）
3. **manxia-source-engine**：NGF + WebView + Source + SourceEditor + Parsers + Search；前置：切断反向引用页（3.2 中 Source→SourceDetailPage 等）。
4. **manxia-network**：Network + FTP + WebDAV + Download + Task + Cache + ExternalFile。

### C 级（最重，最后做）
5. **manxia-novel**：Novel + ReadAloud + Rss；前置：断 Novel→pages 反向引用。
6. **manxia-reader-ui / manxia-features-ui**：Reader + components 阅读器 + 阅读类页面；settings(27) + backup/transfer/数据管理/图源管理页面组。

### 推荐目标结构

```text
entry                 （Abilities、MyAbilityStage、main_pages 索引、Splash、路由跳转，保持轻薄）
manxia-core           （Utils 纯工具/Logger、Models、Types、EventBus、Lifecycle、Database、Storage、Theme、Data、libs）
manxia-native         （avif / quickjs / webdav / transfer_rtc 4 个 so）
manxia-network        （Network / FTP / WebDAV / Download / Task / Cache / ExternalFile）
manxia-source-engine  （NGF / WebView / Source / SourceEditor / Parsers / Search）
manxia-novel          （Novel / ReadAloud / Rss）
manxia-reader-ui      （Reader + 阅读器组件 + 阅读类页面）
manxia-features-ui    （settings 组 + 备份/传输/数据管理/图源管理等页面）
```

---

## 6. 结论

- 最大现实价值与最低成本的切分点：**native 四件套** 与 **source-engine / network 引擎层**；其次是 **core 数据基础层**。
- pages 的 10.5MB 与"核心层"都依赖先打破 `Utils↔Managers↔Data` 环与业务层反向引用，属于第二阶段工作。
- 全程由用户在每个阶段门口编译 + 功能回归（计划强制门禁，避免"大爆炸式"重构一次性破坏功能）。
- 实施顺序、每阶段人员口径、验收用例、回滚预案详见 PLAN。
