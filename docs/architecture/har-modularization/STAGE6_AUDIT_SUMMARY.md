# Stage6 全量实现审计汇总（2026-08-21）

完整机器可读清单: .dsh-filess/AUDIT_INVENTORY.json（entry 620 文件逐行属性 + 模块邻接矩阵）

## 1. 规模
- entry .ets = 620（Framework 369 / pages 129 / 其它 122）
- 8 模块 ets：core=139、source-engine=34、network=25、novel=26、theme=19、reader-ui=18、features-ui=11
- 模块邻接：entry 依赖全部 8；core 出边(import 上层)=11 文件（需去耦）；core 被上层依赖=4（干净）

## 2. entry 纯净度
- relEntry=0 纯文件合计 196
- 其中 pure 且 deep 仅含 core/空 = 149（理论可迁 core）
- 其中 pure 且 deep 含其它模块 = 47（不可迁 core）
- native(.so/.wasm)=9（留 entry 或归 native 承载模块）

## 3. Core 反向耦合清单（Wave-0 目标，11）
| core 文件 | 依赖上层 | 处置 |
| ContentPanel | theme + features_ui(MarkdownViewer) | 迁 features-ui（M51 误放 core） |
| UserManualData | theme(GlobalContext) | GlobalContext 下沉 core 后解除 |
| AppGuideManager | theme(GlobalContext) | 同左 |
| WelcomeGuideManager | theme(GlobalContext) | 同左 |
| HoldingAwarenessManager | theme(GlobalContext) | 同左 |
| InteractionManager | theme(GlobalContext) | 同左 |
| ReadingAnalyticsManager | theme(GlobalContext) | 同左 |
| PrivacyModeManager | theme(ThemeManager) | 归 theme 或降级 |
| ResponsiveLayout | theme(DeviceAdaptationManager) | 归 theme 或降级 |
| NotificationManager | network(TaskNavigationTypes) | TaskNavigationTypes 下沉 core |
| ProxyManager | network(LocalProxyBridge) | 迁 manxia-network |

## 4. 结论
- 先 Wave-0 去耦（逐文件门禁），杜绝 core 反向依赖，再谈新增迁移
- Core 增长护栏：仅纯共享契约/纯工具/纯类型；UI/窗口/原生桥进对应模块
