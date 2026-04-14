# NGF Module Registry

## 1. 文档信息

- 版本: v0.7
- 日期: 2026-04-13
- 状态: 生效中
- 作用: 提供 NGF 全模块可检测清单（模块级注册基线）

## 2. 注册规则（强制）

1. 新增模块必须先注册再实施。
2. 每次新增 contracts/facades/index 后必须同步更新本表。
3. 注册信息必须与真实路径一致，且文件编码为 UTF-8。

## 3. 模块注册表

| moduleId | 层级 | 根目录 | README | index 导出 | contracts | facades | runtimeIntegration | 状态 |
|---|---|---|---|---|---|---|---|---|
| ngf-core | core | `entry/src/main/ets/Framework/NGF/core` | ✅ | ✅ | ✅ | ✅ | `core/facades/NGFCoreIntegrationFacade.ets`, `core/facades/NGFCoreEventBridge.ets`, `EntryAbility.ets`, `Framework/Debug/ErrorMonitorService.ets` | Active |
| ngf-platform-ohos | platform | `entry/src/main/ets/Framework/NGF/platformOhos` | ✅ | ✅ | ✅ | ✅ | `platformOhos/facades/*`, `EntryAbility.ets`, `pages/UnifiedDetailPage.ets`, `pages/SplashPage.ets` | Active |
| ngf-data | data | `entry/src/main/ets/Framework/NGF/data` | ✅ | ✅ | ✅ | ✅ | `data/facades/*`, `EntryAbility.ets`, `pages/settings/NGFFrameworkStatusPage.ets` | Active |
| ngf-content-workflow | content | `entry/src/main/ets/Framework/NGF/contentWorkflow` | ✅ | ✅ | ✅ | ✅ | `contentWorkflow/facades/*`, `EntryAbility.ets`, `pages/settings/NGFFrameworkStatusPage.ets`, `Framework/Workflow/WorkflowExecutor.ets` | Active |
| ngf-content-source | content | `entry/src/main/ets/Framework/NGF/contentSource` | ✅ | ✅ | ✅ | ✅ | `contentSource/facades/*`, `EntryAbility.ets`, `pages/settings/NGFFrameworkStatusPage.ets`, `Framework/Source/SourceRepositoryManager.ets`, `Framework/Source/SourceManager.ets` | Active |
| ngf-ui-shell | ui | `entry/src/main/ets/Framework/NGF/uiShell` | ✅ | ✅ | ✅ | ✅ | `uiShell/facades/*`, `EntryAbility.ets`, `pages/settings/SettingsImmersiveTitleBar.ets`, `pages/SupportersPage.ets`, `pages/UserAgreementPage.ets` | Active |

## 4. 根入口检测点

1. NGF 根导出文件：`entry/src/main/ets/Framework/NGF/index.ets`
2. 根导出应覆盖本表所有 Active 模块。

## 5. 后续强制声明

1. 之后所有新增模块与文件都必须满足“可注册、可导出、可追踪”。
2. 未登记在本表的模块不允许进入完成态。
