# 漫匣 HAR 模块化 — Stage 3（manxia-source-engine）实施记录

> 时间：2026-08-20 05:30（实施；M3 待编译）

## 1. 闭包分析结论
- 目标域：Framework/{NGF,WebView,Source,SourceEditor,Parsers,Search}
- 依赖 core（manxia_core 深路径）与系统包后可独立可迁文件：**67**（主要是 NGF contracts/facades 抽象层 + Search 子系统 + SourceEditor/WebView/Parsers 叶子）——NGF 依赖倒置设计带来的直接红利。
- 阻塞 63 项：依赖 entry 的 EventBus/ErrorHandler/WindowManager/Managers/(pages 反向)/Models 等 → 留 entry（示例见 analysis 输出）。

## 2. 已实施
- 新建 manxia-source-engine（name=manxia_source_engine, har；oh-package 依赖 manxia_core）。
- 根 build-profile.json5 注册模块；根 oh-package.json5 加 file 依赖。
- git mv 迁入 **33** 文件（34 个因文件句柄 Permission denied 未移动，软阻塞留 entry，级联处理保证无悬空引用）。
- entry 38 文件、81 处 import 改写为 manxia_source_engine/src/main/ets/...。
- 校验：residual=0、dangling=0。

## 3. 待办 / 后续
- M3 用户编译 + 图源链路回归（搜索/详情/章节/阅读/下载/图源管理/图源编辑器/WebView 在线）。
- 未迁 34 个（多为 NGF contracts/facades 与 Search 文件）在锁释放后可补迁；或随后续阶段处理。
