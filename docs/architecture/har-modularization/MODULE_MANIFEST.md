# 漫匣 HAR 模块化 — 权威模块清单（v2，2026-08-21）

> 以磁盘实测为准。上一版 v1 已过时（反映 Stage6 早期）。

## 当前各模块 ets 数（git tracked，排除 oh_modules/build）
- entry: 591（最初 810）
- manxia-core: 135
- manxia-theme: 30
- manxia-novel: 28
- manxia-network: 33
- manxia-source-engine: 34
- manxia-reader-ui: 18
- manxia-features-ui: 17
- 合计: 886

## 阶段达成
- 契约化三件套：SettingsManager / ProxyManager / DataManager（类型+接口+Holder）。
- 大量管理器与 UI 件整迁各模块；Wave-0 Core 去耦：core 反向耦合清零（出边=0）。
- W2 分发：theme(A 11) + features-ui(B 4) + network(C 6) + novel(D 2) + LocalTransfer/Import 子项目闭环。
- EBook 功能修复：划线 / MOBI / 进度；传书上传鉴权修复。

## 预留 entry 清单（边界，不迁）
- BackupManager x3（依赖 Novel/Legado 大簇）
- DataManager（巨型数据层本体；类型/契约在 core）
- NetworkFolderManager（依赖 SMBClientAdapter 原生）
- MangaAssetLoader（依赖缓存簇，延后子项目）
- Legado 运行时 18 件（Rhino/Wasm/JS 引擎等原生承载）
- Abilities / 入口壳 / pages（assembly 层）

## 阶段状态
- **M7 收尾完成**（2026-08-21）：release 编译通过，标签 harmod-wave0-w2
- 3 轮 release 门禁修复：ArkTS 编译错误(9) → for..in(1+2) → intra-module 深路径(151)+孤儿文件(6)+INTERNET 权限
- .bak_harmod 备份与 .bak 孤儿目录已清理

## 校验口径
- core 出边（对上层模块 import）= 0（脚本断言）
- residual=0 / dangling=0 / 深路径目标存在 / 无反向依赖 / 无重名；每批门禁后提交
- intra-module 深路径自引用=0（151 处已改相对路径）
