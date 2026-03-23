# 窗口管理与沉浸式治理方案

更新时间：2026-03-23

## 1. 结论

当前多个页面沉浸式布局混乱，根因不是单个页面写错，而是窗口管理职责被分散到了 4 个层级：

1. `WindowManager.ets` 提供底层 `DisplayMode` 切换。
2. `MainMenuPage.ets` 维护一套按页面名硬编码的路由分发规则。
3. 一批页面在 `aboutToAppear`、`onPageShow`、`onShown`、`aboutToDisappear` 中自行调用 `WindowManager.setDisplayMode(...)`。
4. 少数组件和跨页浮层也在直接读写窗口模式或通过 `AppStorage` 传递返回模式。

这导致同类页面即使都用了 `HdsNavDestination`，也会因为进入路径不同、上一个页面不同、是否手动补 `statusBarHeight` 不同，而出现不同的沉浸表现。

## 2. 现状盘点

### 2.1 直接调用窗口管理的文件

仓库内直接调用窗口显示模式的页面和组件共有 21 个：

- `entry/src/main/ets/pages/MainMenuPage.ets`
- `entry/src/main/ets/pages/AnnotationCenterPage.ets`
- `entry/src/main/ets/pages/CoverSelectionPage.ets`
- `entry/src/main/ets/pages/EBookReaderPage.ets`
- `entry/src/main/ets/pages/EBookSettingsPage.ets`
- `entry/src/main/ets/pages/FileEditorPage.ets`
- `entry/src/main/ets/pages/GlobalSearchPage.ets`
- `entry/src/main/ets/pages/MangaReaderPage.ets`
- `entry/src/main/ets/pages/MangaSettingsPage.ets`
- `entry/src/main/ets/pages/NovelReaderPage.ets`
- `entry/src/main/ets/pages/NovelReplaceRulePage.ets`
- `entry/src/main/ets/pages/NovelTxtTocRulePage.ets`
- `entry/src/main/ets/pages/OpenSourceLicensePage.ets`
- `entry/src/main/ets/pages/PrivacyPolicyPage.ets`
- `entry/src/main/ets/pages/ReadAloudPlayerPage.ets`
- `entry/src/main/ets/pages/SupportersPage.ets`
- `entry/src/main/ets/pages/SuwayomiReaderPage.ets`
- `entry/src/main/ets/pages/UnifiedDetailPage.ets`
- `entry/src/main/ets/pages/UserAgreementPage.ets`
- `entry/src/main/ets/pages/ZLibraryReaderPage.ets`
- `entry/src/main/ets/components/EBookReaderPage.ets`

### 2.2 `MainMenuPage` 当前的路由托管范围

`MainMenuPage.ets` 当前维护两组页面：

- HDS 子页 65 个：进入时统一切到 `DisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE`
- 自管理沉浸页 7 个：进入后由页面自己切换

自管理页为：

- `MangaReaderPage`
- `EBookReaderPage`
- `NovelReaderPage`
- `SuwayomiReaderPage`
- `ZLibraryReaderPage`
- `UnifiedDetailPage`
- `FileEditorPage`

### 2.3 HDS 页面并不都在 `MainMenuPage` 托管范围内

仓库中实际使用 `HdsNavDestination()` 的页面共有 77 个，但只有 65 个在 `MainMenuPage` 的 HDS 清单里。

也就是说，至少有 12 个 HDS 页面没有被主路由统一托管：

- `AnnotationCenterPage`
- `CoverSelectionPage`
- `EBookSettingsPage`
- `GlobalSearchPage`
- `MangaSettingsPage`
- `OpenSourceLicensePage`
- `PrivacyPolicyPage`
- `ReadAloudPlayerPage`
- `RssSubscriptionDetailPage`
- `SourceGuidePage`
- `SupportersPage`
- `UserAgreementPage`

其中只有 2 个页面完全没有本地窗口管理代码：

- `RssSubscriptionDetailPage`
- `SourceGuidePage`

这两个页面的窗口表现实际上依赖“它们是从哪个页面跳进来的”，属于隐藏继承。

### 2.4 HDS 页面内部的布局契约也不统一

77 个 HDS 页面内部又分成 3 类：

- `hideTitleBar` 未显式声明：64 个
- `hideTitleBar(true)`：8 个
- `hideTitleBar(false)`：5 个

同时：

- 使用 `statusBarHeight` 的 HDS 页面有 29 个
- 使用 `navigationBarHeight` 的 HDS 页面有 25 个

这说明页面并没有共享一套统一的“沉浸布局契约”：

- 有的页面希望系统标题栏负责顶部安全区
- 有的页面隐藏标题栏后自己补 `statusBarHeight`
- 有的页面只补顶部
- 有的页面顶部和底部都自己补

如果只是简单把所有页面切到同一个 `DisplayMode`，一定会有一部分页面错位。

## 3. 已确认的具体问题来源

### 3.1 窗口模式责任分散

当前至少同时存在 4 种入口：

1. `MainMenuPage` 根据页面名切模式
2. 页面自身生命周期切模式
3. 阅读器页面在进入/退出时记录并恢复“上一个模式”
4. `ReadAloudPlayerPage` 和悬浮球通过 `AppStorage` 传递返回模式

这意味着页面 A 是否正确，取决于：

- 它是否被 `MainMenuPage` 识别
- 它自己是否又覆盖了一次模式
- 返回链路是否写对了 `previousDisplayMode`
- 前台恢复时当前模式是否被正确重放

### 3.2 `DisplayMode.DEFAULT` 语义被过度复用

`WindowManager.ets` 中：

- `DisplayMode.DEFAULT` = `setWindowLayoutFullScreen(false)`，即非全屏布局，由系统避让状态栏和导航栏
- `DisplayMode.STATUS_SAFE_BOTTOM_IMMERSIVE` = `setWindowLayoutFullScreen(true)`，状态栏透明，页面自己处理顶部安全区

但是在业务代码里，`DisplayMode.DEFAULT` 同时被当成：

- 主页面根布局模式
- 通用普通页模式
- 阅读器退出后的恢复目标
- 听书播放器非阅读来源的回退目标

这让“默认模式”既承担了根页面职责，又承担了普通详情页职责，还承担了跨页返回语义，结果必然冲突。

### 3.3 `MainMenuPage` 的页面清单是硬编码的

问题不是 `MainMenuPage` 有分发，而是它只知道自己那 72 个名字。

一旦出现：

- 从非 `MainMenuPage` 跳入
- 新增 HDS 页面没加入清单
- 某页面后来改成 `hideTitleBar(true)` 但清单没同步

就会进入“页面局部自救”的状态。

### 3.4 窗口模式已经泄漏到组件层

不仅页面，组件层也在介入：

- `entry/src/main/ets/components/EBookReaderPage.ets`
- `entry/src/main/ets/Framework/Components/ReadAloudFloatingBall.ets`

这会导致页面与组件对同一窗口状态产生竞争，后期非常难维护。

## 4. 建议的统一管理模型

### 4.1 不再让页面直接决定 `DisplayMode`

页面层不应该再直接写：

```ts
WindowManager.setDisplayMode(...)
```

页面只声明“自己是什么类型的页面”，由统一协调器把页面类型映射到具体窗口模式。

### 4.2 引入页面级窗口策略枚举

建议新增 `PageWindowPolicy`，而不是继续直接用底层 `DisplayMode`：

- `ROOT_MAIN_MENU`
- `NAV_STANDARD`
- `NAV_CUSTOM_HEADER`
- `FULLSCREEN_READER`
- `FULLSCREEN_READER_WITH_BARS`
- `FOLLOW_HOST`
- `TRANSIENT_MODAL`

建议语义如下：

- `ROOT_MAIN_MENU`
  - 仅用于 `MainMenuPage`
  - 保持现在的主页面窗口策略与转场覆盖层

- `NAV_STANDARD`
  - 适用于绝大多数 `HdsNavDestination + 默认标题栏` 页面
  - 底层映射到 `STATUS_SAFE_BOTTOM_IMMERSIVE`
  - 页面不自己处理 `statusBarHeight`

- `NAV_CUSTOM_HEADER`
  - 适用于 `hideTitleBar(true)` 且页面自绘顶部头部的 HDS 页面
  - 底层也映射到 `STATUS_SAFE_BOTTOM_IMMERSIVE`
  - 但页面必须使用统一的顶部安全区容器，而不是各写各的 padding

- `FULLSCREEN_READER`
  - 适用于漫画/小说/电子书阅读器、文件编辑器等
  - 底层映射到 `FULL_IMMERSIVE`

- `FULLSCREEN_READER_WITH_BARS`
  - 适用于 `ZLibraryReaderPage`
  - 底层映射到 `IMMERSIVE_WITH_BARS`

- `FOLLOW_HOST`
  - 适用于 `ReadAloudPlayerPage` 这种需要跟随来源页面恢复的跨页浮层/播放器
  - 不再自己解释 `DisplayMode.DEFAULT`，而是跟随来源策略

- `TRANSIENT_MODAL`
  - 适用于后续可能存在的全屏引导、半独立弹层页

### 4.3 新增统一注册表

建议新增一个单独文件，例如：

- `entry/src/main/ets/Utils/PageWindowRegistry.ets`

注册信息至少包含：

- `pageName`
- `policy`
- `managedByMainMenu`
- `titleBarMode`
- `safeAreaContract`
- `notes`

示例：

```ts
export interface PageWindowSpec {
  pageName: string;
  policy: PageWindowPolicy;
  managedByMainMenu: boolean;
  titleBarMode: 'system' | 'custom' | 'hidden';
  safeAreaContract: 'system_titlebar' | 'custom_header' | 'fullscreen';
}
```

这样 `MainMenuPage` 不再维护两个 `Set<string>`，而是查询注册表。

### 4.4 新增统一协调器

建议新增：

- `entry/src/main/ets/Utils/PageWindowCoordinator.ets`

职责：

1. 页面进入时，根据 `PageWindowPolicy` 应用窗口模式
2. 页面退出时，恢复来源页面策略
3. 前后台切换后，统一重放当前策略
4. 为 `FOLLOW_HOST` 类型维护来源页面策略栈，而不是手写 `AppStorage` key
5. 屏蔽页面层对 `WindowManager` 的直接依赖

建议暴露的接口：

- `enter(pageName, uiContext, options?)`
- `leave(pageName, uiContext)`
- `reapplyCurrent(uiContext?)`
- `pushHostContext(pageName, policy)`
- `popHostContext(pageName)`

### 4.5 沉浸布局必须绑定共享 Scaffold

光统一窗口模式还不够，页面布局也要收口。

建议新增两个共享容器：

- `StandardNavPageScaffold`
  - 对应 `NAV_STANDARD`
  - 统一背景层、滚动区、标题栏风格
  - 页面不要再自己写顶部安全区 padding

- `ImmersiveHeaderPageScaffold`
  - 对应 `NAV_CUSTOM_HEADER`
  - 统一处理 `statusBarHeight`、自定义头部、底部导航栏空间

以及一个阅读器容器：

- `FullscreenReaderScaffold`
  - 对应 `FULLSCREEN_READER` / `FULLSCREEN_READER_WITH_BARS`

## 5. 页面治理建议

### 5.1 第一类：主路由根页面

- `MainMenuPage`

处理方式：

- 保留专属转场逻辑
- 从硬编码 `Set<string>` 迁移到 `PageWindowRegistry`
- 继续拥有“根页面回切覆盖层”这一特殊职责

### 5.2 第二类：标准 HDS 页面

特征：

- `HdsNavDestination()`
- 使用系统标题栏
- 不应自己操作窗口模式

建议策略：

- 全部归到 `NAV_STANDARD`

代表页面：

- `AboutPage`
- `GlobalSettingsPage`
- `ThemeSettingsPage`
- `ReadingSettingsSubPage`
- `DownloadSyncPage`
- `RssSubscriptionPage`

### 5.3 第三类：自绘头部 HDS 页面

特征：

- `HdsNavDestination()`
- `hideTitleBar(true)`
- 自己处理顶部头部和安全区

建议策略：

- 全部归到 `NAV_CUSTOM_HEADER`
- 必须迁移到统一 `ImmersiveHeaderPageScaffold`

代表页面：

- `MangaDetailPage`
- `EBookDetailPage`
- `SourceGuidePage`
- `SupportersPage`
- `OnlineEBookDetailPage`

### 5.4 第四类：全屏阅读/编辑类页面

建议策略：

- 全部归到 `FULLSCREEN_READER` 或 `FULLSCREEN_READER_WITH_BARS`

页面：

- `MangaReaderPage`
- `EBookReaderPage`
- `NovelReaderPage`
- `SuwayomiReaderPage`
- `FileEditorPage`
- `ZLibraryReaderPage`
- `UnifiedDetailPage`

### 5.5 第五类：脱离主路由托管的独立页

这是当前最需要先治理的一组。

页面：

- `AnnotationCenterPage`
- `CoverSelectionPage`
- `EBookSettingsPage`
- `GlobalSearchPage`
- `MangaSettingsPage`
- `OpenSourceLicensePage`
- `PrivacyPolicyPage`
- `ReadAloudPlayerPage`
- `RssSubscriptionDetailPage`
- `SourceGuidePage`
- `SupportersPage`
- `UserAgreementPage`

建议：

1. 全部进入 `PageWindowRegistry`
2. 明确它们的策略归属
3. 删除页面里的直接 `WindowManager.setDisplayMode(...)`

## 6. 推荐的迁移顺序

### Phase 1：先建规则，不继续扩散

1. 新建 `PageWindowPolicy`
2. 新建 `PageWindowRegistry`
3. 新建 `PageWindowCoordinator`
4. 规定页面层禁止新增直接 `WindowManager.setDisplayMode(...)`

### Phase 2：先收口 12 个主路由外 HDS 页面

优先处理：

- `GlobalSearchPage`
- `EBookSettingsPage`
- `MangaSettingsPage`
- `CoverSelectionPage`
- `AnnotationCenterPage`
- `OpenSourceLicensePage`
- `PrivacyPolicyPage`
- `UserAgreementPage`
- `SupportersPage`
- `SourceGuidePage`
- `RssSubscriptionDetailPage`
- `ReadAloudPlayerPage`

### Phase 3：再把 `MainMenuPage` 改成查注册表

目标：

- 删除硬编码页面分组
- 让主路由只负责“根据注册表查策略”

### Phase 4：最后处理阅读器和听书链路

这一步最复杂，因为涉及返回栈和来源页恢复。

重点对象：

- `ReadAloudPlayerPage`
- `ReadAloudFloatingBall.ets`
- `MangaReaderPage`
- `EBookReaderPage`
- `NovelReaderPage`
- `ZLibraryReaderPage`

目标：

- 从“传递 raw DisplayMode”改成“传递来源页面策略”

## 7. 最终治理目标

治理完成后，页面只需要回答两个问题：

1. 我是什么页面类型？
2. 我使用哪种共享布局容器？

而不再需要每个页面自己回答这些问题：

- 当前该不该全屏
- 返回时恢复哪个 `DisplayMode`
- 状态栏是否透明
- 顶部 padding 该加多少
- 当前页面是不是从 `MainMenuPage` 进来的

## 8. 直接判断

是的，当前问题的核心来源就是“窗口管理职责散落”，而且散落得不只是页面级别，还跨到了主路由、页面生命周期、组件层和跨页状态存储层。

如果不先做统一治理，而是继续逐页修状态栏或逐页补 `statusBarHeight`，后续每新增一个页面都会重新长出一套例外逻辑。
