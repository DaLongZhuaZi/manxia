# NGF Phase 0 Execution Board

## 1. 说明

- 版本: v0.4
- 周期: 2026-04-13 ~ 2026-04-26
- 状态字段: Todo / In Progress / Review / Done / Blocked

## 2. 当前看板

| Task ID | 模块 | 任务 | 风险 | 前置依赖 | 状态 | 验收标准 |
|---|---|---|---|---|---|---|
| NGF-P0-001 | governance | 细化实施计划执行章节 | 低 | 无 | Done | 计划文档具备周粒度与出入口条件 |
| NGF-P0-002 | docs | 输出接口草案文档 | 低 | NGF-P0-001 | Done | 第一批接口命名冻结清单可评审 |
| NGF-P0-003 | docs | 输出迁移影响矩阵 | 低 | NGF-P0-001 | Done | 关键模块风险分级完成 |
| NGF-P0-004 | docs | 输出模块责任文档 | 低 | NGF-P0-001 | Done | 模块责任边界可追踪 |
| NGF-P0-005 | scaffold | 创建 NGF 模块骨架目录 | 低 | NGF-P0-002 | Done | 目录结构落盘且说明文件齐全 |
| NGF-P0-006 | core | 建立 core 契约文件（仅接口） | 中 | NGF-P0-005 | Done | 不改旧逻辑，仅新增契约层 |
| NGF-P0-007 | platform | 建立平台契约文件（仅接口） | 中 | NGF-P0-005 | Done | Window/Policy/Context 契约齐备 |
| NGF-P0-008 | source | 建立 source/workflow 契约文件 | 中 | NGF-P0-005 | Done | Source 与 Workflow 接口齐备 |
| NGF-P0-009 | data | 建立 data 契约文件（仅接口） | 中 | NGF-P0-005 | Done | DataFacade 与存储契约齐备 |
| NGF-P0-010 | review | Phase 0 评审与冻结 v0.2 | 中 | NGF-P0-006~009 | Done | `NGF_INTERFACE_DRAFT.md` 升级为 v0.2-frozen |

## 3. 阻塞与风险

1. 若发现契约命名与既有模块冲突，先在接口草案更新，再落代码。
2. 若目录命名影响后续 import 规范，统一在 Phase 0 结束前修正。

## 4. 下一步（当前轮次）

1. 继续推进 Phase 1 façade 的低风险集成接线。
2. 修复 hvigor 构建链路并补跑构建级验证。
3. 准备 Phase 1-alpha 回归清单。
