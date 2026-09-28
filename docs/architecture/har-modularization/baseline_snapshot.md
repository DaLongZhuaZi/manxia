# 漫匣 HAR 模块化 — 基线快照与 R0 预研结论（Stage 0 交付物）

> 采集时间：2026-08-20 01:33~01:40
> 用途：作为 M0 门禁与后续每一步回滚/比对的"0 号基线"。

---

## 1. git 基线

- 分支：`agent/supporters-json`
- 工作区已修改：AppScope/app.json5；entry/src/main/resources/rawfile/changelog.md、changelog_brief.md；manxia-legado-runtime(submodule，小写 m 表示子模块有内容变更)
- 未跟踪（与本次拆分无关，先不动）：docs/* 若干、reasonix.toml、tools/legado-compat/、*.tmp*.txt
- 末尾提交：`bcbff26f chore: stop tracking agent tool dirs and hvigor tmp caches`
- **建议**：模块搬迁前，用户可将这些无关改动 commit/stash，避免与拆分混在一起；不强制但在本文件记录为已知基线缺陷。

## 2. 关键配置 0 号快照（只读原文存于 ANALYSIS §1.1、§2，路径清单）

| 文件 | 内容要点 |
|---|---|
| 根 build-profile.json5 | modules=[entry]；products.default → targetSdk/compatibleSdk 6.1.0(23) |
| 根 oh-package.json5 | deps: @ohos/oh7zip,@ohos/minizip,buffer；devDeps: hypium,hamock |
| entry/build-profile.json5 | externalNativeOptions → ./src/main/cpp/CMakeLists.txt |
| entry/oh-package.json5 | devDeps 含 5 个 `lib*.so: file:./src/main/cpp/types/*` |
| entry/module.json5 | 13 Ability + Backup/Form/Share；querySchemes=manxia |
| entry/.../profile/main_pages.json | 16 页（SplashPage … ContinuationRestorePage） |

## 3. R0 预研结论（结论需在对应 Stage 实际操作时用最小实验复核）

### R0.1 Native 跨模块 .so 解析（影响 Stage 1）
- 官方有"Native侧跨HAR/HSP模块接口调用开发实践"best-practice：https://developer.huawei.com/consumer/cn/doc/best-practices-V5/bpta-cross-module-reference-V5
- 官方"构建 HAR"：https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-hvigor-build-har
- 社区实践：HAR 内放 native（so+types），宿主以 ohpm agenda（`file:`/包名）依赖该 HAR，ArkTS 侧以 `import x from 'libxxx.so'` 经 ohpm 传递解析可行。
- **暂定方案 A**（首选）：4 个 so 的源码+types 全部进 `manxia-native/src/main/cpp`；在 `manxia-native/oh-package.json5` 声明 `lib*.so: file:./src/main/cpp/types/*`；entry 只在根/entry 依赖 `manxia-native`（file:）。需在 Stage 1 用"最小 manxia-native（先搬 jsvm_engine 一个 so）→ entry 引用新路径编译"的方式做一次可行性实验，成功后再搬其余 3 个。
- **备选方案 B**：entry 直接 `lib*.so: file:../manxia-native/src/main/cpp/types/*`（跨模块文件直引）。风险较低但破坏了"类型跟随模块"的封装。A 失败才用 B。

### R0.2 跨模块页面（影响 Stage 3/6）
- 官方推荐 **Navigation 跨包路由**（本项目已用 NavPathStack，属 Navigation 体系）：https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/arkts-navigation-cross-package
- 要点：HAR 中的页面若走 router 模型，需在宿主 HAP 的 `main_pages.json` 登记；Navigation 模型下页面可作为组件经 `Navigation` 的 `NavDestination`/路由表引入，路径名保持字符串路由即可。
- **本项目落地**：保持 entry `main_pages.json` 条目不变（16 页名字符串不动），页面实现文件移入 HAR 后，路由 push 名不变 → 对既有调用零改动；属于跨包的页面在注册与引用上按官方 Navigation 规则处理，Stage 3/6 各做一次"单个页面跨模块验证"。

### R0.3 HAR 资源 (`$r`/`rawfile) 迁移规则（影响 Stage 2/3/5/6）
- HAR 资源并入宿主后按资源优先级解析，同名项存在冲突风险（官方无独立“HAR 资源规则”单页，参考 HAP/HSP 资源优先级问答与社区避坑：https://developer.huawei.com/consumer/cn/forum/topic/0204187643647856511 ）
- 落地：迁 rawfile（help/localization/manga_sources/webview_config/rhino_sandbox/wasm_modules）时先 `grep -r "`$`rawfile('" entry/src/main/ets` 全量收集引用表，再逐个数据源对应；同名 ``$``r(app.media.*)` 资源若跨模块冲突，登记冲突表并优先保 entry，HAR 内改名保唯一。
- 本项目 release 未开混淆（buildOption.arkOptions.obfuscation.enable=false），资源混淆冲突风险低。

### R0.4 现有 .bak 约定盘点（影响 P4）
- 既有文件命名：`<file>.bak`、`<file>.ets.<yyyymmdd_hhmmss>.bak`、`<file>.codex-<ts>.bak`、目录 `xxx.bak` / `xxx.bak_<ts>`（如 entry/.cxx/.../arm64-v8a.bak_20260806_nativecache；ets 下 Framework/Network.bak、Framework/ImageProcessing.bak）。
- 本计划统一采用：侵入性改动前 `copy <file> <file>.bak_harmod`；整批迁移前写《回滚清单》（源→目标→可逆性），并全体登记进 PROGRESS 变更台账。

## 4. M0 门禁待办

- [ ] 用户确认：当前分支 HAP 可正常编译（assembleHap）并启动到主界面。
- [ ] 用户确认：是否先对我方无关的未跟踪/修改文件做 commit/stash（可选）。
- [ ] 用户选择第一个动手方向（默认建议 Stage 1 native HAR 化）。
