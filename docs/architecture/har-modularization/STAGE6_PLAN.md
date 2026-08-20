# 漫匣 HAR 模块化 — Stage 6（UI 层拆分）周密实施计划（基于依赖实证）

> 版本 v1（2026-08-20）｜前置：Stage 0-5 已完成（native/core/source-engine/network/novel）｜采用约定：段门禁编译+回归、深路径导入(不用 barrel)、新模块必 ohpm install、.bak_harmod、git mv、文件锁软阻塞+级联、每段独立提交检查点。

## 1. 依赖实证
- UI 宇宙(entry: pages+components+能力页)约 199 文件；向 entry 其余泄漏边约 1590 条、289 目标。
- 咽喉点 Top：主题/视觉（ThemeManager 134/ThemeAware 124/FontAware 86/GlobalBackgroundLayer 69/SharedPageBackgroundLayer 69）；Models（MangaModels 40/EBookModels 21/TextReaderModels 17/NovelModels 14/UnifiedContentModels 14）；其它（DeviceAdaptationManager 37/SettingsManager 31/WindowManager+PageWindowCoordinator 31/ResponsiveLayout 29/EventBus 26/DataManager 22/EBookDataManager 19/AppGuide 系 38/NovelSourceManager 12）。
- 结论：直接搬页面必失败；须先降基座，使 UI 群依赖闭包收敛。
## 2. 目标结构
- entry（壳）都 manxia-reader-ui + manxia-features-ui，其下为既有五层。
- 新增下沉层（顺序即阶段）：manxia-theme（ThemeManager/ThemeAware/FontAware/AppColors/UserThemeConfig/GlobalBackgroundLayer/SharedPageBackgroundLayer/VisualEffects，消咽喉点1）；manxia-models（Models 全量下沉，消咽喉点2）；manxia-appcore（SettingsManager/DeviceAdaptationManager/WindowManager/PageWindowCoordinator/ResponsiveLayout/DataManager 契约化或下沉，消咽喉点3）。

## 3. 阶段路线（每段=一次用户编译+回归门禁 M6.x）
- Phase U0 manxia-theme 下沉（最高杠杆）：迁 Theme 系；前置检查其依赖（Logger/AppStorage/EventBus/Settings 只读）；必要时 EventBus 一并下沉。验收：主题切换/阅读器背景/沉浸式等价。
- Phase U1 Models 下沉：先消 Models—Framework/Utils 依赖（纯工具 UUIDGenerator 等进 core），再迁 Models。验收：书架/历史/图源数据读写正常。
- Phase U2 应用级基础：纯状态(AppStorage)实现下沉；业务依赖抽 contract(NGF 式 facades)，UI 改依赖 contract。验收：设置持久化/窗口/设备适配回归。
- Phase U3 manxia-reader-ui：Reader 剩余+components(Manga*/TextReader*/EBook*/PageCurl*)+阅读类页面（含能力页）；entry main_pages 字符串路由不变。验收：各阅读器全流程。
- Phase U4 manxia-features-ui：pages/settings + 备份/传输/数据/图源管理/关于 + components/{backup,editor,source}。验收：设置/功能页+深链入口。
- Phase U5 收尾：entry 壳化、release 构建、文档、清理。
## 4. 每段固定作业清单
1) 原生 fs 闭包复算得可迁集/阻塞/泄漏；2) 建骨架+module.json5(type=har)+build-profile(force-add)+oh-package(main+file deps)+根注册+根 ohpm dep；3) 用户/IDE 执行 ohpm install（关键）；4) git mv（软阻塞+级联回退）；5) entry import 深路径改写（脚本+fs 写，锁文件可覆盖）；6) index.ets 最小化；7) 静态校验 residual=0/dangling=0/目标存在/无反向依赖；8) 提交检查点；9) 用户编译+回归回填台账。

## 5. 风险（Stage 6 特化）
- R6-1 咽喉点下沉仍带出更多依赖：每次先跑闭包，软阻塞留 entry。
- R6-2 能力页/Ability 跨模块 srcEntry：同名处理，模块内显式声明。
- R6-3 跨模块页面路由：entry main_pages 名字符串不变。
- R6-4 UI 仍依赖 entry 业务管理器：U0-U2 先消咽喉点，U3/U4 仅闭包支持才推。
- R6-5 新模块未 ohpm install：门禁清单默认带。
- R6-6 文件锁：软阻塞+级联+fs 覆盖写。
- R6-7 单例双份化：git mv 防复制。

## 6. 验收口径
- 每 Phase 一次 M6x 门禁；与原功能等价+NGF 日志无找不到导出/Undefined 崩溃；整体完成做全功能冒烟 + 能力页/深链入口 + release 构建。

## 7. 立即动作（U0 待批准）
- U0：闭包复算 theme 集 → 建 manxia-theme → 迁移+改写 → 交用户 M6.0 编译。


