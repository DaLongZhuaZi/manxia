# Legado 书源引擎兼容推进台账

更新时间：2026-08-14T19:16:56.3150764+00:00

| 阶段 | 状态 | 结论 |
| --- | --- | --- |
| 阶段 0：基线与差分平台 | planned |  |
| 阶段 1：无损导入与存储 | planned |  |
| 阶段 2：规则编译器与请求内核 | planned |  |
| 阶段 3：ArkWeb 统一传输 | planned |  |
| 阶段 4：工作流与类型适配 | planned |  |
| 阶段 5：JS API 契约 | planned |  |
| 阶段 6：全局 V2 切换、界面与收敛 | planned |  |
| 阶段 7：V2 全局路径封口与真机验收 | planned |  |
| 阶段 7A：原版 Legado 同端点差分诊断 | planned |  |
| 阶段 8：能力矩阵扩展与上线收敛 | planned |  |

## 持续真机治理状态

该区块只读取 `tools/legado-compat/state/full-source-validation-state.json`，与阶段状态机分开呈现。它记录后续逐源真机治理与 UI 回归，**不会将阶段 7 的历史失败改写为通过**。

| 范围 | 状态 | 脱敏摘要 |
| --- | --- | --- |
| 真机持久化“完整验证”（唯一设备级口径） | observed_incomplete | 完整验证=0/458；策略=v2_full_cutover；证据=tmp/book-source-management-r4-20260809-unlocked/result.json |
| Harness / 状态机逐源执行账本（不等同真机完整验证） | blocked | 总数=458；planned=0；running=0；verifying=0；passed=4；failed=50；expected_external=0；needs_interaction=158；policy_blocked=95；blocked=151 |
| V2 语义资格（fixture、trace 与参考差分；不等同真机完整验证） | evidence | unverified=65；execution_verified_no_reference=19；semantic_match=0；semantic_mismatch=1；external_confirmed=0；endpoint_unconfirmed=50；needs_interaction=158；policy_rejected=95；engine_rejected=20；arkweb_unconfirmed=1；harness_or_engine_failure=43 |
| 持续治理台账 | running | 活跃任务：COMPAT-006；议题：planned=10；running=0；verifying=29；passed=102；failed=59；blocked=158；expected_external=1；needs_interaction=50 |
| 当前机器活动源码议题 | ISSUE-COMPAT-244-JSOUP-HTML-ENTITY-SEMANTICS | verifying；244 R4 统一验证全部 8 步完成：干净单一 run（v2-hypium-full-17516-1786713467539）458/458 终态可追溯（step4-full-batch.json）；1 处 semanticDifference（ordinal 8 reference_success_v2_http_error=外部站点 HTTP 503，非实体语义缺陷，不新增根因）；fixed Legado 同输入差分 witness OK、V2 差分除单对象投影格式缺口（归 231）外一致；hvigor 构建、安装、真机冷启动与 Hypium、书源管理页 54/54 渲染完成（ledger completed）。244 仍保持 verifying：最终 passed/semantic_match 需用户批准。 |

详细治理问题、证据路径和状态转换以该机器事实源为准；原始书源、Cookie、账号、正文和密钥均不进入本区块。

持续真机治理状态只来自 `tools/legado-compat/state/full-source-validation-state.json`；阶段历史状态仍由对应阶段事实文件保留。总控不会写入原始书源、Cookie、正文、账号或密钥。