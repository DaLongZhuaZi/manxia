# 漫匣 HAR 模块化 — Stage 2（manxia-core）实证分析与执行方案

> 时间：2026-08-20 03:50（Stage 2 动手前实证）
> 性质：非侵入分析文档。

---

## 1. 为什么 core 无法“小步”抽取

HAR 约束：任何上层 HAR（Stage 3/4/5/6）不能 import 宿主 entry（依赖必须向下）。而全部 810 个文件最终都依赖：
- Utils/Logger：**530 个文件引用**（几乎全应用）
- Framework/Utils：业务型工具，反向依赖 Managers/Source/Novel（不能进 core）
- Models：依赖 Framework/Utils（不能直接进 core）
- Framework/Debug/LogCollector：Logger 的依赖
- 各类 Manager 单例

把 Logger/Utils 留在 entry = 上层 HAR 全部卡死。**所以要么做一次大规模 import 重写把基础层搬出，要么放弃分层 HAR 化。**

## 2. 实证：core 候选闭包检查结论

| 候选 | 引用面 | 结论 |
|---|---|---|
| Utils/Logger | 530 引用 | 必进 core；依赖 LogCollector、TimeUtils 须一并下沉 |
| Utils/* 纯工具子集 | — | 进 core；例外（WindowManager 39 / WidgetDataSync 3 / CompressionUtils 5 / AvifTranscoder 1 / MoveState 1 / LogFloatingWindow 1 / WelcomeGuideTestHelper 0）留 entry |
| Framework/Types | 大（类型层） | 依赖窄，进 core |
| Framework/Core、EventBus | EventBus 50 引用 | EventBus 依赖 Debug/LogCollector → 先下沉“日志子系统”再进 |
| Framework/Lifecycle / Database / Storage(SandboxManager 20) | 中 | 进 core，复核内部依赖 |
| Models | 广泛 | 依赖 Framework/Utils → 本期不迁 |
| Data(ResourceMap 5) / libs/htmlparser(4) / Scraper(2) / Compress / ImageProcessing | 低 | 进 core，顺带 |
| Framework/Utils | 业务型 | 本期不进 core |

## 3. 执行方案（用户绿灯后执行）

### 3.1 目标结构
manxia-core（name=manxia_core, har）→ src/main/ets/：index.ets(barrel) + Utils(纯+Logger) + Types/Core/EventBus/Lifecycle/Database/Storage/Compress/ImageProcessing/Scraper/Data/libs

### 3.2 步骤
1. W2.1 下沉日志子系统（LogCollector、TimeUtils），保证 Logger 只依赖 core 内。
2. 建 manxia-core 骨架（build-profile / oh-package(name=manxia_core) / hvigorfile(harTasks) / module.json5(type=har, name=manxia_core)），全 UTF-8、P4 备份。
3. 根 build-profile.json5 注册模块；根 oh-package.json5 加 manxia_core: file:./manxia-core；entry 依赖之。
4. git mv 选定文件入 core，修正 core 内相互相对 import。
5. 生成 barrel index.ets（从各文件“^export ”提取符号，显式 export { … } from './…'，避免 export * 语义不确定）。
6. 脚本化改写 entry 侧 import：指向已迁文件的相对路径 → from 'manxia_core'（只改 specifier，不改被导入名）。
7. 静态验证：import 解析器全量复扫（无旧路径残留、core 不反向 import entry、barrel 符号完整）。
8. 交付 M2 编译清单。

### 3.3 风险
- R6 import 重写类型放宽：脚本只改 specifier，编译期 strict 把关。
- R8 重复定义：迁移用 git mv。
- 新增 R11：barrel 重导出在 ArkTS 的语法约束（避免 export *，用显式 export {} from；受限则退化为按文件深链接 manxia_core/src/main/ets/…，以编译器实际支持为准，最小验证先行）。
- 新增 R12：500+ 处 import 一次性改写 → 机器改写 + 全量静态复扫 + 用户一次 M2 编译集中收口。

## 4. 决策待办（需用户绿灯）
- [ ] 是否执行大规模 core 抽取（预计 ~80 文件搬移 + ~600 处 import specifier 改写）？
- [ ] 确认 entry 保留清单（WindowManager 等 8 个 + Models/Framework/Utils 本期不迁）。
