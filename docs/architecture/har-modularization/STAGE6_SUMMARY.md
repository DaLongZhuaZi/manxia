# 漫匣 HAR 模块化 — Stage 6 完整实施总结（收口版 v2）

> 生成：2026-08-20 21:20（收口时全面重写；v1 过于简略，v2 以 PROGRESS 台账为主体重构建）
> 关联：ANALYSIS / PLAN / PROGRESS / STAGE6_FORWARD_PLAN / MODULE_MANIFEST

---

## 1. 阶段目标与结果
- 目标：把 entry 里的 UI/基础层继续拆出去，并建立跨模块解耦范式。
- 结果：新抽取 manxia-theme / manxia-reader-ui / manxia-features-ui 三个 HAR，manxia-core 扩容；完成 3 条管理者级契约化闭环。

## 2. 模块抽取（均有门禁验收与提交）
| 阶段 | 模块 | 内容 | 说明 |
|---|---|---|---|
| U0 | manxia-theme | 主题集群：ThemeManager/Theme.*/ThemeAware/ThemeToggle/GlobalBackgroundLayer | 首迁 11 |
| U1 | manxia-core 扩容 | Models(13)+纯 Framework/Utils(16，含 UUIDGenerator/FontNameParser 等) | 并入 core |
| U2 | manxia-theme | 窗口/页面管理：WindowManager/PageWindowCoordinator/Policy/Registry | 4 |
| U3 | manxia-reader-ui | Reader 流程/常量 + Manga/TextReader/EBook/Epub/PageCurl 组件 | 17 |
| U4 | manxia-features-ui | settings 帮助类 + backup 对话框 + editor 组件 | 10 |
| U5 | manxia-theme | FontAware/FontManager/UIContextManager | 3 |

当前模块 ets 数（实测）：entry=654、manxia-core=101、manxia-theme=19、manxia-reader-ui=18、manxia-features-ui=11、manxia-source-engine=34、manxia-network=25、manxia-novel=26。

## 3. 契约化（U6 范式：契约进 core / 实现自注册 / 消费按接口）
| 管理器 | 进度 | 内容 |
|---|---|---|
| SettingsManager | 主链闭环 | SettingKeys 下沉 core；ISettingsManagerFacade+Holder；22 页消费；覆盖通用访问器与常用非通用成员(getVisibleTabs/getBottomBarStyle/isInitialized/initialize 等) |
| ProxyManager | 闭环 | ProxyProtocol/ProxyConfig/ProxyTestResult 下沉 core；IProxyManagerFacade+Holder；对话框消费 |
| DataManager | 类型+接口+最小接线(R1) | 57 数据契约下沉 DataContracts；IDataManagerFacade(3 只读)+Holder；implements+initialize 自注册+DownloadManagerPage 试点 |

## 4. R（推进）阶段实绩
- R1：DataManager 最小接线（M12 通过，提交 0d6140ca）：implements+自注册+1 消费试点。
- R2：SettingsManager 广度：批1 3 页（M13，64296487）、批2 5 页（M14，3df35054）；接口随批扩展。
- R2 平台期：剩余页需逐页扩接口，收益边际下降，暂止。

## 5. 关键教训（已固化到 FORWARD_PLAN 硬规则）
1) import 放置：并入 import 区；再导出须在最后一个 import 之后（否则 arkts-no-misplaced-imports）。
2) 类型下沉：本地 import+再导出 齐备；块内未导出辅助接口须转 export。
3) 多行 import（首行 import{）勿插入其中。
4) 新模块必须 ohpm install 同步，否则 Cannot find module。
5) 文件句柄锁：软阻塞+级联；用 fs 覆盖写。
6) 静态校验：residual=0 / dangling=0（精确正则）/ 深路径存在 / 无反向依赖 / 无重名。
7) 连续≥2 次门禁返修 → 回退上一提交重新设计，不叠加修补。
8) 可切性扫描须覆盖 settingsManager.任意成员名，非仅 get/set。

## 6. 工程状态与收口
- git：本会话累计约 26 个 HAR 相关提交；收口时未推 4 个（77e247c6 文档对账 + R1 0d6140ca + R2 批1/批2）。
- release 构建：已通过；近期改动建议在收口前再复核一次。
- 文档：README 模块架构 + 本目录全套。
- 剩余/可选：R2 逐页扩接口；R3 其余管理器；R4 阻塞页（settings 22 等）待咽喉闭合后迁入；R5 清理。

