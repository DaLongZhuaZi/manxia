# 漫匣（manxia）HAR 模块化任务交接 Prompt

> 交接时间：2026-08-21｜交接人：上一推进 Agent（已按门禁逐阶段验收）｜接办人：继续推进的 Agent

## 0. 你的角色与目标
继续推进『漫匣』（HarmonyOS Next / ArkTS 项目）的 HAR 模块化工程。目标：在**逐阶段门禁（用户编译+功能回归）下**，把 entry 逐步瘦身到 8 个分层 HAR 模块，保持功能等价、不让任何模块变成超大耦合物。每步：**先按文档/数据严格规划，再执行**，不允许临时起意选件。

## 1. 仓库与环境（照做，勿另猜）
- 工作目录：`F:\DevEcoStudioProject\manxia`（必须在此根目录执行构建）
- SDK：`$env:DEVECO_SDK_HOME='F:\DevEco Studio\sdk'`
- 构建：`& 'F:\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleHap --no-daemon`（debug）；release 用 `-p product=default -p buildMode=release`
- ohpm：新增/变更 oh-package 依赖后必须 `& 'F:\DevEco Studio\tools\ohpm\bin\ohpm.bat' install`（lock EPERM 无碍）
- 设备：`F:\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe`；日志采集 `hdc shell hilog | …`
- 远端：`origin`=GitHub；`nas-backup`=http://192.168.5.146:3333/DLZZ/manxia.git（推全部与标签用 `git push nas-backup --all`+`--tags`）
- 沙箱环境：hvigor ~/.hvigor 缓存在受限环境常失效（es2abc/缓存 ENOENT）→ **不要试图在受限 shell 里跑完整构建**，编译/回归一律由用户在 DevEco 或全权限终端执行；你的职责是改对 + 静态自检 + 门禁脚本式断言。

## 2. 当前状态（已完成 ✅）
1) 8 个 HAR 模块建于位：manxia-core(139)/theme(30)/novel(28)/network(33)/source-engine(34)/reader-ui(18)/features-ui(17)；entry=585（原 810）。
2) 契约化三件套：SettingsManager（SettingKeys+ISettingsManagerFacade+Holder，28 页消费，实现本体已迁 core）；ProxyManager（契约+实现已迁 network）；DataManager（57 类型下沉 core + IDataManagerFacade + 接线）。
3) Wave-0 Core 去耦：core 反向耦合 11 处清零（GlobalContext/TaskNavigationTypes 下沉 core；ContentPanel/Changelog 赴 features-ui；PrivacyMode/ResponsiveLayout 赴 theme；ProxyManager 赴 network）→ **core 出边=0**。
4) W2 分发：theme(A 11)+features-ui(B 4)+network(C 6)+novel(D 2)+LocalTransfer/Import 子项目闭环（ImportFlowMonitor/Types→core；LocalTransferServerService/TransferUploadStoreService→network）。
5) 功能修复（都已实测）：EPUB Web 划线（WebView 注入 JS `window.SafeUtils.parseObj` shim + @Prop→@Link）；MOBI 转换健壮性；阅读进度；传书上传鉴权（`TransferSessionManager.isClientPaired` 放行已配对同 IP）；未改名“未知书名”记录 = 源/历史数据问题（非回归）。
6) 已知问题：#1 FTP/WebDAV 连接测试 ANR（THREAD_BLOCK_6S，登记未修）；#2/#3/#4 已修复关闭。

## 3. 权威文档（先读再动）
`docs/architecture/har-modularization/` 下：AUDIT_SUMMARY .md（全量审计+Core 反向耦合清单）、MODULE_MANIFEST .md（v2，计数+边界）、STAGE6_PHASE2_PLAN.md（v3，Wave-0/W1…R5 批次与护栏）、KNOWN_ISSUES.md、HAR_MODULARIZATION_PROGRESS.md（台账）、STAGE6_SUMMARY.md；机器可读全集 `.dsh-filess/AUDIT_INVENTORY.json`（entry 620 文件逐行属性+邻接矩阵）。

## 4. 边界（禁止迁移，已登记）
- entry 保留：BackupManager×3 / DataManager 本体 / NetworkFolderManager(SMB 原生) / MangaAssetLoader+Cache 簇（横切 DataManager+Source 层+native AvifDecoder+Download，评估为不可单迁） / Legado 运行时 18 件（Rhino/Wasm/JS 引擎原生承载） / Abilities、入口壳、pages。
- native(.so/.wasm)、`.bak*`、纯 entry 本地件：不迁。

## 5. 硬性规则（防止重蹈本会话之坑）
1) 迁移资格判定：无 entry 相对导入(**多行 import 的 from 行要以全行扫描、不能只扫 import 开头**) 且 **deep(manxia_*) ⊆ 目标模块可引层**；core 只承接 deep⊆core∪∅；任何放入 core 的提交验收含 **core 出边=0 脚本断言**。
2) 消费方改写：必须覆盖 **相对路径与深路径两种形态**（含动态 `import('…')`）；同名族（如 `SettingsManager/NovelSettingsManager/AnimationSettingsManager`）改写得用精确 specifier / lookbehind，禁止子串匹配误伤。
3) 类型下沉：本地 `import` + `export` 再导出 两者齐备；块内未导出辅助接口转 export。
4) 搬移后修复该文件自身指向其它模块的相对导入（resolve→对应模块深路径）；并全仓扫 dangling。
5) 新模块/依赖变更后必 `ohpm install`。文件句柄锁：用 Node fs 覆盖写 + 软阻塞级联，勿叠修补。
6) 门禁纪律：预检（相对导入解析+消费面）→ 最小改动 → 静态自检（residual=0/dangling=0/深路径存在/无反向依赖/无重名）→ 用户编译+回归 → 独立提交+台账回填。连续 2 次门禁返修 → 回退该项并**重构方案**（不再叠加修补）。
7) 单批 ≤8 文件 或 ≤40 处导入改写，超出拆批。
8) 不要用 `git stash` 做 A/B（本会话踩过：被锁文件导致 stash 不能干净恢复）；需要 A/B 用 `git checkout HEAD -- <定向路径>` 或在提交点之间切 branch。

## 6. 接下来的任务（至少看清再选）
### T1（建议最先）R5 收尾复核（已接近完成）
- 推送待推提交（当前仅 2 个：docs `47341c52`、台账 `315f16a0`），`git push origin agent/supporters-json` + `git push nas-backup --all` + `--tags`。
- 提示用户跑 release 复核（全权限终端）+ 关键回归（启动/设置/主题/代理/通知/传书/划线/MOBI）。
- 可选：打里程碑 tag（如 `harmod-wave0-w2`）并推送。
### T2（可选，深项）NGF barrel 去耦
- 现状：entry `Framework/NGF/**/index.ets`（及 Lifecycle/Scraper/Subscription barrel）被 entry+core+novel 三处引用；需先做逐件内容/引用分析（把真实层定到 core/novel/theme 何层），再分层下沉；输出分析方案→用户确认→分批。
### T3（可选，小）既有 8 处断裂相对导入
- 它们在被除外/死代码文件（ImageDescramblerRegistry .bak / LoadingPage Animated*/SystemIntegrationManager / WorkflowCapabilities ErrorHandler）。**只登记、不盲改**（改了可能把死文件拉进编译）。
### T4（可选）R4 页面闭包（settings 子页迁 features-ui，需路由/构建复核，独立设计）
### 明确不继续：Cache 簇/MangaAssetLoader 迁移（已判边界）、Backup/Legado/DataManager 迁移、一切 native。

## 7. 推进方式（对你每次行动的要求）
1) 先用 `AUDIT_INVENTORY.json` 或脚本产出候选名单（relEntry/deep/importers），**名单交用户/接办人确认**，再分批执行。
2) 每批：预检 → 移动+改写 → 断言（core 出边=0 等）→ 交给用户编译+回归 → 提交 + 台账回填（阶段/批次/提交/门禁结果）。
3) 全部文档随进度更新（PROGRESS/MANIFEST/PLAN/KNOWN_ISSUES），保持“现实基线”不漂移。
4) 交互只用中文；每步汇报简洁（改动点/断言结果/待用户门禁），不输出大段文件原文。

## 8. 验收/完成标准
- 凡新提交：编译通过（用户验证）+ 相关功能回归无新问题；core 出边维持 0；无 dangling/反向依赖。
- 任务完成时更新 PROGRESS 台账 & MANIFEST（计数、边界、阶段、已知问题状态），并给出待推清单。

