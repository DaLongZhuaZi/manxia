# ngf-content-workflow

当前阶段:

1. 定义 workflow/action/retry/limit 契约。
2. 新增低风险兼容 façade：`facades/WorkflowEngineFacade.ets`。
3. 新增低风险兼容 façade：`facades/ActionExecutorFacade.ets`。
4. 新增低风险兼容 façade：`facades/RetryPolicyFacade.ets`。
5. 新增低风险兼容 façade：`facades/RateLimitPolicyFacade.ets`。
6. 新增运行时接线入口：`facades/NGFContentWorkflowIntegrationFacade.ets`。
7. 暂不迁移既有执行器主链路，先通过 façade 与运行时注册接线。
