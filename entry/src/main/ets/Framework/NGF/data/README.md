# ngf-data

当前阶段:

1. 定义数据门面与存储相关契约。
2. 新增低风险兼容 façade：`facades/DataFacade.ets`。
3. 新增低风险兼容 façade：`facades/SettingsStoreFacade.ets`。
4. 新增低风险兼容 façade：`facades/CacheStoreFacade.ets`。
5. 新增低风险兼容 façade：`facades/StorageProviderFacade.ets`。
6. 新增低风险兼容 façade：`facades/DbMigratorFacade.ets`。
7. 新增低风险兼容 façade：`facades/NGFDataIntegrationFacade.ets`。
8. 保持旧 `DataManager` 实现不拆分，先通过 façade 与运行时注册接线。
