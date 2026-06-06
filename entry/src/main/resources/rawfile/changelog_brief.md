# 更新日志

## v0.1.1 (104802306)

### 核心重构
- 全面消除ESObject，30+文件迁移至Record与显式接口
- DistributedDataSyncManager改为多回调模式，支持独立注册与注销
- 移除definite assignment assertion，组件@Prop改为带默认值
- GlobalTaskCoordinator新增IPageManager接口，消除ESObject

### 功能与优化
- 9处showToast迁移至UIContext.getPromptAction()
- 搜索调度改为滑动窗口并发，合并网络任务队列避免卡顿
- Suwayomi新增扩展章节信息接口
- Komga配置保存规范化
- NGF编排器新增完成承诺，延迟分布式会话加入

### 其他修复
- 清理UTF-8 BOM标记
- 修复变量替换正则与非法属性附加
