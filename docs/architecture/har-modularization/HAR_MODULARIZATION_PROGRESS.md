# 漫匣项目 HAR 模块化拆分 — 实时进度台账（PROGRESS / 唯一真相源）

> 最后更新：2026-08-20 21:30（收口：M14 复检✅（3df35054）；R2 平台期；STAGE6_SUMMARY 重写为完整版 v2 + FORWARD_PLAN 状态更新；待推 4+1 提交由用户推送）
> 规则（对齐 PLAN P6）：每完成/中断/失败一个工作包，**立即**在本文件追加时间戳条目；
> 阶段门禁等待用户验收时，对应阶段状态置 ⏸ 待验证，并把"建议验证命令+用例"写全；
> 用户回填验收结果后，由执行方核验并推进到下一阶段。
> 关联文档：ANALYSIS（现状分析） / PLAN（实施计划）

---

## 1. 总状态

| 项 | 值 |
|---|---|
| 当前阶段 | **Stage 6 收口完成：模块抽取 + SettingsManager/ProxyManager/DataManager 契约化（R1/R2 已提交）；文档已同步；待用户推送** |
| 总体进度 | barrel 版 M2 首编报 468 错（日志10505001/10605150：Utils/Logger 与 NamingConventions 重名 LogLevel 被 barrel 合并冲突）→ 改为深路径导入（manxia_core/src/main/ets/...，符号保持原文件身份，index.ets 最小化）重做：525+ 文件、996+ 处改写
| 上次变更 | 2026-08-20 05:05：深路径 pivot 完成并通过静态校验 |
| 当前阻塞 | 等待用户：M2 二次编译（§9 指令不变） |
| 目标 | 见 PLAN §1（M0→M7） |

## 2. 阶段状态表

| 里程碑 | 阶段 | 模块 | 状态 | 上次更新 | 备注 |
|---|---|---|---|---|---|
| M0 | Stage 0 | — | ✅ 已落据（凭 01:11 构建产物） | 2026-08-20 | 基线 signed HAP 2026-08-20 01:11 成功产出（拆分前）；若 M1 编译出现非本次改动引起的问题，按基线问题回退处理 |
| M1 | Stage 1 | manxia-native | ✅ 已验收 | 2026-08-20 | 用户确认功能正常；构建产物含 5 个 so；提交 46db83d6 |
| M2 | Stage 2 | manxia-core | ⏸ 待用户编译验收 | 2026-08-20 | 已实施：67 文件迁入 + barrel + 525 文件改写；验收清单 §9 |
| M2 | Stage 2 | manxia-core | ⚪ 未开始 | — | 前置 M0 |
| M3 | Stage 3 | manxia-source-engine | ⚪ 未开始 | — | 前置 M2 |
| M4 | Stage 4 | manxia-network | ⚪ 未开始 | — | 前置 M2 |
| M5 | Stage 5 | manxia-novel | ⚪ 未开始 | — | 前置 M2、M3 |
| M6 | Stage 6 | manxia-reader-ui / features-ui | ⚪ 未开始 | — | 前置 M2~M5 |
| M7 | Stage 7 | — | ⚪ 未开始 | — | 前置 M6 |

状态图例：🔵 进行中 / ⏸ 待用户验证 / ✅ 已验收 / ⚠️ 需修复 / ⚪ 未开始 / 🔴 已回滚

## 3. 用户验收记录（门禁回填表）

| 日期 | 阶段 | 编译结果 | 测试结果 | 结论 | 备注 |
|---|---|---|---|---|---|
| 2026-08-20 | M0 | ✅ 前置基线（01:11 signed HAP 成功，拆分前产物） | 未单独复跑 | 已落据 | 建议在 M1 编译时一并对上基线新产物 |
| 2026-08-20 | M1 | 待用户回填 | 待用户回填 | ⏸ | Stage 1 最小实验：见 §8 验收指令 |

## 4. 变更台账（本计划引起的工程改动）

| 日期 | 文件/路径 | 改动类别 | 说明 |
|---|---|---|---|
| 2026-08-20 | docs/architecture/har-modularization/HAR_MODULARIZATION_ANALYSIS.md | 新增 | 现状分析落盘 |
| 2026-08-20 | docs/architecture/har-modularization/HAR_MODULARIZATION_PLAN.md | 新增 | 实施计划（极周密版）落盘 |
| 2026-08-20 | docs/architecture/har-modularization/HAR_MODULARIZATION_PROGRESS.md | 新增 | 本台账建立 |
| 2026-08-20 | docs/architecture/har-modularization/baseline_snapshot.md | 新增 | Stage 0 基线快照 + R0.1~R0.4 预研结论落盘（含官方文档来源链接） |
| 2026-08-20 | docs/architecture/har-modularization/STAGE1_PREP.md | 新增 | Stage 1 实操前实证调查：迁移范围 349 文件、CMake→so 映射、最小实验方案、骨架草稿、决策项 D1~D4 |
| 2026-08-20 | manxia-native（build-profile/oh-package/hvigorfile/src_main_cpp_CMakeLists） | 新增模块 | Stage 1 最小实验骨架（harTasks） |
| 2026-08-20 | entry/src/main/cpp/quickjs → manxia-native/src/main/cpp/quickjs | git mv | 72 个已跟踪文件搬入新模块（保留历史） |
| 2026-08-20 | entry/src/main/cpp/CMakeLists.txt | 修改 | 删除 add_subdirectory(quickjs)（备份 .bak_harmod） |
| 2026-08-20 | entry/oh-package.json5 | 修改 | libquickjs_engine.so 指向 ../manxia-native/...（备份 .bak_harmod） |
| 2026-08-20 | 根 build-profile.json5（gitignore 仅本地） | 修改 | 注册 manxia-native 模块（备份 .bak_harmod） |
| 2026-08-20 | 根 oh-package.json5 | 修改 | 增加 manxia-native: file:./manxia-native（备份 .bak_harmod） |
| 2026-08-20 | manxia-native/src/main/module.json5 | 新增 | M1 首轮编译反馈修复：HAR 模块必须含 type=har 的 module.json5 |
| 2026-08-20 | 模块标识 manxia-native → manxia_native | 修改 | M1 二轮反馈 00303038：module.name 禁止连字符；同步改 build-profile/oh-package/module.json5/依赖 key（目录名 manxia-native 保留） |
| 2026-08-20 | entry/src/main/cpp/{avif,webdav,transfer_rtc,third_party,types,jsvm_engine.cpp} → manxia-native/src/main/cpp/ | git mv | Stage 1b：其余 4 个 so + libsmb2 迁入（transfer_rtc 因目录被进程锁改用文件级 git mv；其 install-libdatachannel-arm64 头文件 robocopy 迁移） |
| 2026-08-20 | entry/src/main/cpp/CMakeLists.txt | git rm | entry 无原生代码，删除顶层 CMake（tracked） |
| 2026-08-20 | entry/build-profile.json5 | 修改 | 移除 externalNativeOptions（native 整体迁出 entry） |
| 2026-08-20 | manxia-native/src/main/cpp/CMakeLists.txt | 重写 | jsvm_engine target + 4 个子项目 add_subdirectory；新增 MANXIA_ENTRY_LIBS_DIR=../../../entry/libs/${OHOS_ARCH}（预编译库因 ACL 原地保留，改相对引用） |
| 2026-08-20 | avif/webdav/transfer_rtc 的 CMakeLists.txt | 修改 | 预编译库路径 ${CMAKE_SOURCE_DIR}/.../libs 统一改为 ${MANXIA_ENTRY_LIBS_DIR} |
| 2026-08-20 | entry/oh-package.json5 | 修改 | 5 个 lib*.so 依赖全部改指 ../manxia-native/...（备份 .bak_harmod） |
| 2026-08-20 | docs/architecture/har-modularization/STAGE2_PREP.md | 新增 | Stage 2 实证：core 必然大规模改写（Logger 530 引用等）；执行方案与决策项 |
| 2026-08-20 | manxia-core（build-profile/oh-package/hvigorfile/module.json5/index.ets） | 新增模块 | manxia_core HAR；barrel main=index.ets（344 导出符号） |
| 2026-08-20 | entry/src/main/ets → manxia-core/src/main/ets | git mv ×66 | 67 计划迁入中因文件锁回退 1（ReaderSafeAreaUtils 留 entry） |
| 2026-08-20 | entry/src/main/ets/* | 批量改写 | 525+ 文件 1014 处 import → from 'manxia_core'（仅 specifier，不改符号） |
| 2026-08-20 | entry 保留清单 | 确认 | WindowManager/MoveState/WidgetDataSync/LogFloatingWindow/WelcomeGuideTestHelper/Models/FrameworkUtils/ReaderSafeAreaUtils 留 entry |

## 5. 基线记录（Stage 0 产出物 progressive）

### 5.1 git 基线（2026-08-20 01:33 采集）
- 分支：`agent/supporters-json`
- 工作区已修改：AppScope/app.json5、entry/src/main/resources/rawfile/changelog.md、changelog_brief.md、manxia-legado-runtime(submodule)
- 未跟踪：docs/API26 升级分析报告、docs/analysis/Legado* 若干、docs/deep-link-test.html、docs/feedback-center-deployment.md、docs/manga-continuation-fixes-*.md、reasonix.toml、tools/legado-compat/、*.tmp*.txt
- 末尾提交：bcbff26f chore: stop tracking agent tool dirs and hvigor tmp caches
- **注意**：当前工作区并非"干净"基线；拆分前建议先把无关改动确认或提交/暂存，以免与模块搬迁混在一起难以回滚。

### 5.2 关键配置快照路径
- 根 build-profile.json5 / 根 oh-package.json5 / entry/build-profile.json5 / entry/oh-package.json5 / entry/module.json5 / entry/.../main_pages.json
- 产物目录：entry/build（构建输出，不入库）
- **备份约定**：侵入性改动前 `copy <file> <file>.bak_harmod`；回滚红线=git 跟踪路径。

### 5.3 预研 R0（已完成 2026-08-20 01:45，详细见 baseline_snapshot.md §3）
- R0.1 Native 跨模块 .so 解析 → ✅ 已产结论：暂定方案A（types 跟随 manxia-native，entry 只依赖模块；先以 jsvm_engine 做最小实验）；备选方案B（entry 跨模块 file: 直引）。官方依据：developer.huawei.com best-practices-V5/bpta-cross-module-reference-V5
- R0.2 main_pages / NavPathStack 跨模块页面 → ✅ 已产结论：保持 entry main_pages 16 条字符串不变；页面文件移入 HAR，路由 push 名不变；官方依据 arkts-navigation-cross-package
- R0.3 HAR 资源（`$r`/`rawfile）迁移规则 → ✅ 已产结论：迁移前全量 grep 引用表、冲突登记、优先保 entry；release 未开混淆风险低
- R0.4 现有 `*.bak` 约定盘点 → ✅ 已完成：既有 `.bak`/`.bak_<ts>`/`.codex-<ts>.bak`/`dir.bak`；本计划统一 `.bak_harmod`

## 6. 风险登记册（活动状态）

| 编号 | 风险 | 状态 | 备注 |
|---|---|---|---|
| R1 | Native .so 跨模块解析 | 🟡 未触发 | 待 R0.1 |
| R2 | 大目录迁移 | 🟢 已缓解（调查后降级） | 实证：git 只跟踪 349 文件；但需保证本机依赖（webdav curl/mbedtls/libssh2 源码、transfer_rtc prebuilt install-*）随模块正确引用（决策 D1） |
| R3 | Utils↔Managers 环 | 🟡 未触发 | 待 Stage 2 W2.1 |
| R4 | 业务层反向引用页 | 🟡 未触发 | 待 Stage 3/5 拆环 |
| R5 | 页面/资源跨模块注册 | 🟡 未触发 | main_pages 不变式遵循 |
| R6 | import 重写类型放宽 | 🟡 未触发 | 机器改写+抽查 |
| R7 | .cxx 缓存冲突 | 🟡 未触发 | 按 AGENTS.md 排查 |
| R8 | 单例双份化 | 🟡 未触发 | 迁移用 move |
| R9 | Windows 编码/中文路径 | 🟡 未触发 | pwsh+UTF-8 |
| R10 | 门禁被跳过 | ✅ 控制中 | P1/P8 已写入 PLAN |
| R11 | barrel 重导出在 ArkTS 语法约束（export * 不可靠） | 🟡 未触发 | 用显式 export {} from；受限则按文件深链接 manxia_core/src/main/ets/… |
| R12 | 500+ 处 import 一次性改写 | 🟡 未触发 | 机器改写 + 全量静态复扫 + 一次 M2 编译集中收口 |

## 7. 详细日志（按时间倒序）

### 2026-08-20 03:40 — 检查点提交与推送（执行方）
- M1 验收通过（用户确认）；提交前审查：
  - 补 gitignore 通用规则（**/webdav/curl-8.5.0 等迁后路径）与 **/BuildProfile.ets、**/avif/build_windows 等；
  - 发现并强制纳入 manxia-native/build-profile.json5（被旧 `build-profile.json5` 规则误忽略，不提交则克隆后模块无法构建）；
  - 确认不提交：AppScope/app.json5、changelog*、manxia-legado-runtime（submodule）、docs/analysis/Legado*、tools/legado-compat、reasonix.toml、*.tmp* 等既有无关 WIP；root build-profile.json5 含签名信息仍按策略不入库。
- 提交：46db83d6 refactor(har): 拆分 manxia-native HAR 模块，原生代码迁出 entry（Stage 0-1）——365 files, +961/-96。
- 推送：首次直推因 SEC_E_NO_CREDENTIALS 失败（沙箱无交互凭据）；改后台任务发起，请求用户完成 GCM/GitHub 授权。
- 剩余未提交（既有 WIP，待用户处置）：见本条目前列。

### 2026-08-20 03:22 — goal round 4：M1 三轮编译反馈处理（执行方）
- 用户编译新报错（00308018 ninja）：`manxia-native/entry/libs/arm64-v8a/libcurl.so missing and no known rule to make it`。
- 根因：MANXIA_ENTRY_LIBS_DIR 用了 3 级 `../../../entry/libs`，而 manxia-native/src/main/cpp 上 3 级是 manxia-native（上 4 级才是仓库根）→ 解析成不存在的 manxia-native/entry/libs。
- 修复：改为 `../../../../entry/libs/${OHOS_ARCH}`（并修正注释）。avif/webdav/transfer_rtc 均经由该变量，无需另改。
- 进展确认：ninja 已进入链接阶段（错误发生在链接 libwebdav_native.so 时），说明 CMake 生成、各 target issue 均正常，仅路径问题。
- 下一步：用户复跑 M1（§8）。

### 2026-08-20 03:10 — goal round 4：Stage 1b 全量迁移实施（执行方，待 M1 编译）
- 用户确认继续（"看起来并没有问题，可以继续"+ 运行日志 02:01 显示 QuickJS/JSVM/Rhino/Jsoup 引擎可用）。
- 构建证据确认 quickjs 迁移成功：manxia-native/.cxx 存在且 quickjs 各 .o 已编译；entry/oh_modules/libquickjs_engine.so 指向 manxia-native；root/oh_modules/manxia_native 已建立。
- 执行 Stage 1b：
  1. git mv 迁入 avif / webdav / third_party(libsmb2) / types / jsvm_engine.cpp（目录级 OK）。
  2. transfer_rtc 目录级 git mv 报 Permission denied（子目录被 IDE/java/node 进程占用）→ 改文件级 git mv（6 个跟踪文件全成功）；install-libdatachannel-arm64 头文件用 robocopy 迁入（rtc.hpp 就位）。
  3. entry/libs（预编译 13 个 so/a）因 ACL（BUILTIN\Administrators 属主 + 受限令牌）无法移动/复制 → **D1 决策：预编译库原地保留**，新模块顶层 CMake 定义 MANXIA_ENTRY_LIBS_DIR=../../../entry/libs/${OHOS_ARCH}，avif/webdav/transfer_rtc 统一改用该变量（相对路径跨模块引用，构建期有效；entry/libs 继续由 entry HAP 打包）。
  4. entry/src/main/cpp/CMakeLists.txt git rm；entry/build-profile.json5 移除 externalNativeOptions（native 整体迁出 entry）。
  5. entry/oh-package.json5：5 个 lib*.so 依赖全部改指 ../manxia-native/...。
- 静态核对：manxia-native/src/main/cpp 完整（avif/quickjs/third_party/transfer_rtc/types/webdav/CMakeLists.txt/jsvm_engine.cpp）；entry/src/main/cpp 仅剩 ignored 残留（build-transfer-rtc-native-test、transfer_rtc 产物等，Stage 7 清理）；ArkTS import 不变；无遗留旧路径引用。
- 待办（管理员权限）：entry/libs 与 entry/src/main/cpp 残留目录的 ACL/清理（Stage 7 或用户手动）。
- 下一步：用户复跑 M1 全量编译 + 四功能域回归（§8）。

### 2026-08-20 04:30 — Stage 2 实施完成（执行方，静态已验，待 M2）
- 67 文件迁入 manxia-core（fixpoint 闭包 movable=67；含 Logger/TimeUtils/LogCollector 日志子系统、Types、Lifecycle、Database、Scraper、htmlparser 全套、纯 Utils 等）。
- barrel index.ets（344 符号，显式 export {} from；支持 type/async/多行导出与 re-export 依赖边）。
- entry 侧 525+ 文件 1014 处 import 改写为 from 'manxia_core'（仅 specifier，不改符号）。
- 静态校验全绿：brokenRel=0、missingNames=0、core2entry=0。
- 边界：ReaderSafeAreaUtils 因文件锁留在 entry（回退其 9 个 importers、barrel 移除）；WindowManager 等来 entry 保留清单按约定。
- 修复历程：导出正则初版漏 async/type 再导出 → 还原 108 文件后重跑增强流水线闭环。
- 下一步：用户 M2 编译 + 整机回归（见 §9）。

### 2026-08-20 02:35 — goal round 3：M1 二轮编译反馈处理（执行方）
- 用户反馈：`00303038 Configuration Error / Schema validate failed`，module.name 必须匹配 `^[a-zA-Z][0-9a-zA-Z_.]*$`。
- 根因：模块名 manxia-native 含连字符 -（不允许）。
- 修复：模块标识统一改为 manxia_native（module.json5 / 根 build-profile modules[].name / manxia-native oh-package name / 根 oh-package 依赖 key）；目录名保持 manxia-native（srcPath/file: 路径不受限，entry 的 libquickjs_engine.so file: 路径不变）。
- 教训已写进 STAGE1_PREP.md §3.3b 命名规则：**HAR 模块名禁止连字符，统一下划线**。
- 注：根/entry 的 oh-package-lock.json5 仍含旧名，需用户重跑 ohpm install 刷新。
- 下一步：用户复跑 M1 验收（§8）。

### 2026-08-20 02:20 — goal round 3：M1 首轮编译反馈处理（执行方）
- 用户反馈：`module.json5 file not found`，指向 manxia-native/src/main/module.json5。
- 根因：HAR 模块同样需要 src/main/module.json5（内含 `"type": "har"`）；前期骨架草稿漏建（已并入更正：后续建 HAR 一律含 module.json5）。
- 修复：新建 manxia-native/src/main/module.json5（name=manxia-native, type=har, deviceTypes=phone/tablet/2in1）。
- 注意：goal 状态为 paused（无阻塞，属正常暂停/等待用户）；本轮仅做修复，不越 M1 门禁。
- 下一步：用户复跑 M1 验收（§8）。

### 2026-08-20 02:05 — goal round 2：实施 Stage 1 最小实验（执行方，已静态核对，待 M1 门禁）
- M0 落据：`entry-default-signed.hap` 时间戳 2026-08-20 01:11（拆分前成功构建，164.56MB）→ 基线可编译。
- 发现并记录：**根 build-profile.json5 被 .gitignore 忽略**（含签名信息，非版本库跟踪）→ 回滚需依赖 .bak_harmod（已备份）。

---

## 9. 门禁 M2 — 用户验收指令（Stage 2 manxia-core）

### 9.1 编译
```
cd F:\DevEcoStudioProject\manxia
ohpm install
$env:DEVECO_SDK_HOME='F:\DevEco Studio\sdk'
& 'F:\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleHap --no-daemon
```

### 9.2 通过标准（涉及 525+ 文件 import，务必整机回归）
- [ ] 1. 编译成功，无 manxia_core/barrel 相关报错（重点看 index.ets re-export 语法）。
- [ ] 2. 冷启动到主界面，日志系统正常（Logger）、设置持久化正常。
- [ ] 3. 回归面（均依赖 core 符号）：数据库/书架/历史、缓存、主题、图源引擎（搜索/详情/阅读）、小说域、WebView 在线阅读、下载、WebDAV/传书、RSS、各 Ability 入口。
- [ ] 4. 无运行时“找不到导出/undefined”类错误（日志看 NGF 标签异常）。

### 9.3 若失败
- 贴报错。常见处置：
  1. barrel re-export 语法（export {} from / type re-export）受限 → 改为按文件深导入或拆分 barrel；
  2. 某符号未导出 → 定位符号原文件，补 barrel 行；
  3. 全量回滚：`git checkout -- entry/src/main/ets`（还原 525 文件）+ git mv 66 个 core 文件回 entry + 删 manxia-core + 还原根 build-profile/oh-package 自 .bak_harmod。
- 实施（全部按 P4 先 .bak_harmod 备份）：
  1. 新建 manxia-native 模块骨架（build-profile.json5 / oh-package.json5 / hvigorfile.ts(harTasks) / src/main/cpp/CMakeLists.txt(含 add_subdirectory(quickjs))）。
  2. `git mv entry/src/main/cpp/quickjs manxia-native/src/main/cpp/quickjs`：72 个跟踪文件（含 quickjs/types/libquickjs_engine）。
  3. entry/src/main/cpp/CMakeLists.txt 删除 add_subdirectory(quickjs)（jsvm/webdav/avif/transfer_rtc 仍在 entry）。
  4. 根 build-profile.json5 注册 manxia-native；根 oh-package.json5 加 file 依赖。
  5. entry/oh-package.json5：libquickjs_engine.so → `file:../manxia-native/src/main/cpp/quickjs/types/libquickjs_engine`（方案 B：沿用既有解析机制，最稳）。
- 静态核对：ArkTS `import quickjs from 'libquickjs_engine.so'` 未变；淹留引用扫描无旧路径；配置 read-back 确认。
- 决定：本轮采用方案 B（沿用 consumer file: 直引），方案 A（纯传递解析）留待后续视构建结果评估。
- 下一步：**用户执行 M1 验收（§8），通过后铺开其余 4 个 so（jsvm/webdav/avif/transfer_rtc）。**

### 2026-08-20 01:52 — goal round 1：Stage 1 非侵入实证调查完成（执行方）
- 清单化溯源：git ls-files entry/src/main/cpp = 349 个已跟踪文件（quickjs 72 / third_party libsmb2 195 / webdav 54 / avif 12 / types 8 / transfer_rtc 5 / 根 CMake+jsvm_engine.cpp 2）。磁盘 16k 文件其余皆为 gitignore 的构建产物与 curl/mbedtls/libssh2 第三方源码。
- 确认 CMake target→so 名映射（ArkTS import 名不可改）：libjsvm_engine / libquickjs_engine / libwebdav_native / libavif_decoder / libtransfer_rtc_native。
- 发现已入库 prebuilt install-curl-https-arm64/lib/libcurl.so；transfer_rtc 依赖本机 prebuilt install-*（gitignore）→ 决策项 D1。
- 产出 STAGE1_PREP.md：最小实验（quickjs 先行 72 文件+types）步骤、方案A/B 分支、manxia-native 骨架草稿（build-profile/oh-package/hvigorfile）、根配置 diff 摘要、回滚红线、决策项 D1~D4（含 webdav(1) 残留清理候选）。
- 风险 R2 降级为已缓解；未触碰任何 build 配置/源码（门禁 M0 前不做实操）。
- 下一步（待用户）：门禁 M0 基线确认 → 决策 D1~D4 → 用户点头后按最小实验方案开 Stage 1。

### 2026-08-20 01:45 — Stage 0 预研 R0 完成（执行方）
- 完成 baseline_snapshot.md：git 基线、关键配置 0 号快照、R0.1~R0.4 预研结论（含官方文档来源）。
- R0.1 Native .so 跨模块：倾向方案A，建议 Stage 1 先搬 jsvm_engine 做最小实验；备选方案B。
- R0.2 跨模块页面：保持 main_pages 名字符串不变（对既有路由零改动），按 Navigation 跨包路由落地。
- R0.3 HAR 资源：迁移前全量引用表 + 冲突登记。
- R0.4 .bak 约定：统一 `<file>.bak_harmod`。
- 下一步（待用户，门禁 M0）：确认基线可编译启动 → 选择第一个模块（默认 Stage 1 native：先 jsvm_engine 最小实验，成功后搬其余 3 个 so）。

### 2026-08-20 01:33 — 建立文档与台账（执行方）
- 完成 ANALYSIS（现状分析：模块/代码量/依赖环/候选分档）。
- 完成 PLAN（M0~M7 分阶段、统一阶段模板、风险册、验收模板）。
- 建立本 PROGRESS 台账，登记 git 基线。

---

## 8. 门禁 M1 — 用户验收指令（Stage 1：5 个 so 全量）

### 8.1 编译指令
```powershell
# 进入仓库根目录 F:\DevEcoStudioProject\manxia
# 1) 同步依赖（新增 manxia-native 模块；IDE 打开会自动 Sync，命令行方式：）
ohpm install
# 2) 编译
$env:DEVECO_SDK_HOME='F:\DevEco Studio\sdk'
& 'F:\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleHap --no-daemon
```

### 8.2 通过标准（全部满足才算 M1 通过）
- [ ] 1. 编译成功，无 `lib*.so` 名称解析报错（libjsvm_engine / libquickjs_engine / libwebdav_native / libavif_decoder / libtransfer_rtc_native）。
- [ ] 2. 5 个 so 全部出现在产物（APK 中间件/打包清单中可查 libs/*.so）。
- [ ] 3. 功能回归：
   - [ ] JS 引擎：`JsvmPlaygroundPage`（测试管理页）可运行 JS（JSVM+QuickJS）；图源/小说 JS 脚本执行正常；
   - [ ] AVIF：AvifTestPage / 漫画阅读含 avif 图正常（libavif_decoder）；
   - [ ] WebDAV：备份页配置+上传/下载、远程书库（libwebdav_native）；
   - [ ] 传输传书 RTC：局域网传书/transfer（libtransfer_rtc_native）；
   - [ ] SMB：NetworkFolderPage 网络文件夹（libsmb2）。
- [ ] 4. App 能启动到主界面，基础导航正常。

### 8.3 若编译失败
- 记录报错贴回。重点排查：
  1. `.cxx` 缓存冲突（generator mismatch）→ 按 AGENTS.md 先查缓存，非命令问题；
  2. `lib*.so` 解析失败（ohpm 未同步）→ 先 `ohpm install` 再编；
  3. so 未打入 HAP → 复查 manxia-native CMake 是否产出、entry 是否仍打包 libs；必要时把 5 个 so 的 types 改为从 manxia-native 直接声明依赖（方案 A）；
  4. 预编译库找不到（MANXIA_ENTRY_LIBS_DIR 解析错）→ 校对顶层 CMake message(STATUS) 输出与 entry/libs/{OHOS_ARCH} 路径。
- 回滚入口（如需回退本轮改动）：
  - `git mv manxia-native/src/main/cpp/{avif,webdav,transfer_rtc,third_party,types,jsvm_engine.cpp,quickjs} entry/src/main/cpp/`（反向搬回）
  - `git checkout -- entry/src/main/cpp/CMakeLists.txt entry/oh-package.json5 oh-package.json5`（恢复 entry CMake 与 so 依赖）
  - 还原 entry/build-profile.json5 的 externalNativeOptions；还原根 `build-profile.json5` 自 `.bak_harmod`；
  - 还原 `entry/oh-package.json5` 自 `entry/oh-package.json5.bak_harmod`。
  - 删除 `manxia-native/` 目录
