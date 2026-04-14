# ngf-content-source

当前阶段:

1. 定义 source repository/loader/registry 契约。
2. 新增低风险兼容 façade：`facades/SourceRepositoryFacade.ets`。
3. 新增低风险兼容 façade：`facades/SourceLoaderFacade.ets`。
4. 新增低风险兼容 façade：`facades/SourceRegistryFacade.ets`。
5. 新增低风险兼容 façade：`facades/NGFContentSourceIntegrationFacade.ets`。
6. 保持旧 `SourceRepositoryManager` / `SourceManager` / `WebViewSourceManager` 逻辑不替换，先通过 façade 与运行时注册接线。
