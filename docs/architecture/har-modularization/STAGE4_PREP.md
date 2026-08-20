# 漫匣 HAR 模块化 — Stage 4（manxia-network）实施记录

> 时间：2026-08-20 ~06:00（实施；M4 待编译）

## 1. 闭包分析
- 目标域：Framework/{Network,FTP,WebDAV,Download,Task,Cache,ExternalFile}
- 可迁 24 文件：缓存组(Disk/LocalImage/FeedbackCenter/WebViewData)、下载组(StreamDownloader/DownloadCache*)、ExternalFile 组、FTP 客户端、网络叶子(LocalProxyBridge/NetworkTransportFailureCoordinator/LegadoImageTransportTrace)、Task 组、WebDAV(Client/ErrorAnalyzer/NativeClient/Test)。
- 阻塞 18 项：依赖 Models/DataManager/UIContextManager/CookieManager/SettingsManager/NotificationManager/BackupModels 等 → 留 entry。

## 2. 已实施
- 新建 manxia-network（name=manxia_network, har；依赖 manxia_core）。
- 根注册 + 根 oh-package dep。
- git mv 迁入 **24/24**（全部成功，无锁）；entry 39 文件 75 处改写为 manxia_network 深路径。
- 校验：residual=0、dangling=0。

## 3. M4 验收点
- 编译通过；回归：WebDAV(备份/远程库)、FTP、网络请求/代理、下载管理器、缓存、外部文件任务入口。
