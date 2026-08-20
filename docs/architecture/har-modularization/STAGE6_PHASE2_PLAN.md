# Stage 6 推进文档 v3（全量审计后，Core 去耦优先）

> 2026-08-21 13:45。v2 批次须先完成 Core 去耦 Wave-0 再执行；批次按“目标模块最合适优先、core 仅最后手段+护栏”修正。

## Wave-0：Core 去耦合（先清账，逐文件门禁）
0.1 ContentPanel -> manxia-features-ui（按消费方定点）
0.2 GlobalContext/getContext 下沉 core -> 解除 7 个 core 管理器对 theme 依赖
0.3 TaskNavigationTypes(纯类型) 下沉 core -> 解 NotificationManager->network
0.4 PrivacyModeManager / ResponsiveLayout -> 归位 theme 或降级仅 core 依赖
0.5 ProxyManager -> manxia-network（消费方深路径改写）
验收：core 出边(import 上层)=0；每项独立门禁+提交

## Core 增长护栏（硬性）
- core 入批条件：deep 包含于 core；且 纯类型/纯工具/跨模块共享契约
- UI/窗口/Canvas/原生桥 -> 对应模块（theme/reader-ui/features-ui/network/novel/source-engine）
- 每批 <=8 文件 或 <=40 改写；批后核 core 出边=0
- 149 个 pure-core-only 候选过大：多数应散入特征模块，非 core

## 后续批次（Wave-0 后）
W1 core-only 真共享类型/契约 小批入 core（如 NGF 小接口、纯模型）
W2 主题-UI 系组件 -> theme / features-ui
W3 网络系 -> network；W4 Novel/Legado(含 native) 留 entry 并登记
R4 页面闭包；R5 收尾（release/README/台账/MODULE_MANIFEST）

## 规则追加
1) 任何放 core 的提交，验收含 core 出边=0（脚本断言）
2) 违反即回退；连续 2 次返修 -> 停并重构，不再叠加
