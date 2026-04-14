# NGF Module Ownership（Phase 0）

## 1. 文档信息

- 版本: v0.1
- 日期: 2026-04-13
- 状态: 待确认负责人

## 2. 角色定义

1. 架构 Owner: 负责边界、接口冻结、风险兜底。
2. 模块 Owner: 负责模块内设计与交付。
3. Reviewer: 负责兼容性与回归评审。
4. QA Owner: 负责阶段验收与回归结论。

## 3. 模块责任划分

| 模块 | 目标目录 | 责任范围 | 进入条件 | 退出条件 |
|---|---|---|---|---|
| ngf-core | `entry/src/main/ets/Framework/NGF/core` | logger/event/error/lifecycle/di | 接口冻结 | façade 可用 |
| ngf-platform-ohos | `entry/src/main/ets/Framework/NGF/platformOhos` | window/context/policy bridge | core 接口冻结 | 页面策略兼容 |
| ngf-data | `entry/src/main/ets/Framework/NGF/data` | settings/cache/storage/db contracts | 数据契约完成 | DataFacade 接线完成 |
| ngf-content-workflow | `entry/src/main/ets/Framework/NGF/contentWorkflow` | workflow engine contracts | source schema 确认 | 统一执行入口可跑 |
| ngf-content-source | `entry/src/main/ets/Framework/NGF/contentSource` | repository/loader/registry | index/source schema 确认 | 图源加载可回归 |
| ngf-ui-shell | `entry/src/main/ets/Framework/NGF/uiShell` | navigation shell/page policy host | platform bridge 可用 | 壳层接入稳定 |

## 4. 评审责任

1. 所有接口变更必须经过架构 Owner + 模块 Owner 双签。
2. 高风险改动需增加 QA Owner 预审。
3. 影响启动流程的改动必须经过专项评审。

## 5. 升级窗口建议

1. 周一至周三: 允许接口与实现迁移。
2. 周四: 仅允许修复类变更。
3. 周五: 冻结新迁移，执行回归与复盘。

## 6. 待补充

1. 具体人员映射。
2. 各模块 SLA（响应时限、故障恢复时限）。
