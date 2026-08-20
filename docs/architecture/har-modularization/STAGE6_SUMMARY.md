# Stage 6 小结与契约化下一步（U6）

> 2026-08-20 15:00

## 已完成（8 个 HAR 模块）
- 既有五层：manxia-native / manxia-core / manxia-source-engine / manxia-network / manxia-novel
- Stage 6 新增/扩容：manxia-theme（U0 主题 + U2 窗口 + U5 字体）、manxia-reader-ui（U3）、manxia-features-ui（U4）、manxia-core 扩容（U1 Models + Framework/Utils）

## U6 探测结论
- settings 子页与功能页（Backup/DataManagement/Source* 等）仍依赖 entry 内业务管理器：SettingsManager / DataManager / BackupManager / AppInfoManager / ProxyManager / NetworkFolderManager / SearchHistoryManager / AnimationSettingsManager 等。
- 继续外迁无机械切分；需先契约化：纯状态者下沉，业务依赖者抽 interface（NGF 式 facades）。

## 建议
- 本轮主路径可告一段落（entry 保留壳/业务管理器/主页面，已文档化）。
- 若续推：U6 契约化作为下一大块，可从单个管理器（如 SettingsManager）试点再推广。
