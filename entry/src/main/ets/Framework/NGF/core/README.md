# ngf-core

当前阶段:

1. 冻结契约接口命名。
2. 通过 façade 方式渐进集成，不替换旧实现。
3. 当前运行时集成入口:
   - `facades/NGFCoreIntegrationFacade.ets`
   - `facades/NGFCoreEventBridge.ets`
4. 当前已接入消费者:
   - `entry/src/main/ets/pages/SplashPage.ets`（初始化事件观测）
   - `entry/src/main/ets/Framework/Debug/ErrorMonitorService.ets`（初始化失败事件消费）
