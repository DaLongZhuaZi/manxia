## 阶段一：`Classes cannot be used as objects`（17处）🔴 最高优先级
> 可能在后续 API 升级中变为 ERROR，必须先处理

- [x] 查找所有 `arkts-no-classes-as-obj` 位置：全部集中在 MainMenuPage.ets 第 15694-15752 行
- [x] 修复 buildShelfManageCard() 中误用 `${ShelfType}` 的模板字符串 → 改为 `'system_manage_shelf'` 固定字符串
- [ ] 验证修复后不再有此类 WARN（等待下次构建验证）

## 阶段二：废弃动画 API 迁移（205处）🟠
> `animateTo` → `UIContext.animateTo`

- [/] MainMenuPage.ets（73处）— 子代理 7b9ccce4 处理中
- [/] EBookReaderPage.ets（16处）— 子代理 058ef76c 处理中
- [/] FileEditorPage.ets（6处）— 子代理 058ef76c 处理中
- [/] NovelReaderPage.ets（4处）— 子代理 058ef76c 处理中
- [/] NovelDetailPage.ets（2处）— 子代理 058ef76c 处理中
- [/] KomgaReaderPage.ets（2处）— 子代理 058ef76c 处理中
- [/] HelpCenterPage.ets（1处）— 子代理 058ef76c 处理中
- [/] KomgaBrowsePage.ets（1处）— 子代理 058ef76c 处理中

## 阶段三：废弃 Toast/Dialog API 迁移（745处）🟡
> `showToast` / `show` → `UIContext` 方法

- [x] MainMenuPage.ets — 内部封装方法已正确使用 UIContext，无需修改
- [/] FileEditorPage.ets（14处）— 子代理 45f31514 处理中
- [/] BackupPage.ets（5处）— 子代理 45f31514 处理中
- [/] AboutPage.ets（4处）— 子代理 45f31514 处理中
- [/] NovelSearchPage.ets（4处）— 子代理 45f31514 处理中
- [/] NovelDetailPage.ets（3处）— 子代理 3a51d200 处理中
- [/] HelpCenterPage.ets（2处）— 子代理 3a51d200 处理中
- [/] KomgaBrowsePage.ets（1处）— 子代理 3a51d200 处理中
- [/] AvifTestPage.ets（1处）— 子代理 3a51d200 处理中
- [/] EBookDetailPage.ets（1处）— 子代理 3a51d200 处理中
- [/] RssFavoritesPage.ets（1处）— 子代理 3a51d200 处理中
- [/] KomgaReaderPage.ets（1处）— 子代理 3a51d200 处理中
- [ ] 'show' 废弃（31处）— 待下阶段处理

## 阶段四：补全 try-catch（1228处）🟠
> `Function may throw exceptions` — 按文件分批

- [ ] MainMenuPage.ets（文件最大，IO/网络调用最多）
- [ ] NovelReaderPage.ets
- [ ] BackupPage.ets / MangaReaderPage.ets
- [ ] EBookReaderPage.ets / FileEditorPage.ets
- [ ] TransferPage.ets
- [ ] 其余工具类/Manager

## 附加：资源名冲突修复（18处）
- [ ] 为各模块字符串资源键名添加模块前缀
