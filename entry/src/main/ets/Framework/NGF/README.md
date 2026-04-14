# NGF 目录骨架

本目录用于 NGF 框架的分层落地，当前阶段为 Phase 0（契约冻结 + 骨架搭建）。

子目录说明:

1. `core`: 日志、事件、错误、生命周期、DI 等核心契约。
2. `platformOhos`: HarmonyOS 平台桥接与窗口治理契约。
3. `data`: 数据访问、设置、缓存、存储、迁移契约。
4. `contentWorkflow`: workflow 执行引擎契约。
5. `contentSource`: 图源仓库与加载契约。
6. `uiShell`: 导航壳层与页面策略宿主契约。

注意:

1. 当前仅新增契约骨架，不替换现有业务实现。
2. 后续迁移遵循 `docs/development/NGF_IMPLEMENTATION_PLAN.md`。
