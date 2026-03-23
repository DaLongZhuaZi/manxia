# APJ21-22 UI焕新改造方案

## 1. 文档目的

本文用于沉淀 `manxia` 项目从 `APJ18` 升级到 `API 21/22` 之后的界面焕新改造方案。

目标不是单纯“多加一点 blur”，而是基于：

- 项目现有源码结构
- 本地 HarmonyOS SDK 实际声明
- OpenHarmony 官方能力方向

建立一套可持续演进的视觉框架，重点覆盖：

- 玻璃态与模糊层级
- 标题栏滚动模糊
- Hero 区与沉浸式背景
- 页面转场与共享元素动效
- Sheet 化交互
- SymbolGlyph 动效统一
- 高性能兜底策略

## 2. 本次核对结论

### 2.1 构建版本已升级到 21/22

已在 `build-profile.json5` 中确认：

- `compatibleSdkVersion`: `6.0.1(21)`
- `targetSdkVersion`: `6.0.2(22)`

这意味着项目已经具备收编 21/22 视觉能力的前提，不需要再停留在 18 时期的保守写法。

### 2.2 本地 SDK 已实际核对

已核对的本地 SDK 路径：

- `F:\HarmonyOS\SDK\18`
- `F:\DevEco Studio\sdk\default\openharmony`
- `F:\DevEco Studio\sdk\default\hms`

其中本次视觉方案的最终判断，以本地 `d.ts` 声明为准。

### 2.3 当前项目不是“没有特效”，而是“特效没有体系化”

项目里已经存在大量玻璃化、模糊、浮层、SymbolGlyph 动效，但使用方式偏分散：

- 有统一主题与玻璃效果管理雏形
- 有全局背景层和后台模糊遮罩
- 主页和漫画详情页已经用了不少玻璃卡片
- 但页面骨架、标题栏、弹层、转场、性能策略没有统一标准

因此本次改造的核心方向应当是“视觉体系收敛”，不是继续散点堆效果。

## 3. 源码现状诊断

### 3.1 页面规模较大，适合先抓骨架而不是全量重画

`entry/src/main/ets/pages` 下页面很多，且至少已有几十个页面使用导航容器。

本次调研中通过源码检索确认：

- `HdsNavDestination(`：约 78 处
- `hideTitleBar(true)`：约 16 处
- `backgroundBlurStyle(`：约 64 处
- `bindPopup(`：约 31 处
- `SymbolGlyph(`：约 542 处

结论：

- 视觉焕新不能靠手工逐页各改各的
- 必须先统一视觉 token、页面骨架和交互容器

### 3.2 现有主题系统已经具备“玻璃态基础设施”

关键文件：

- `entry/src/main/ets/Framework/Managers/ThemeManager.ets`
- `entry/src/main/ets/Framework/Theme/AppColors.ets`
- `entry/src/main/ets/Framework/Theme/UserThemeConfig.ets`

已确认 `ThemeManager` 中已有：

- `getGlassBlurStyle()`
- `getGlassBackgroundResource()`
- `getGlassRadius()`
- `getGlassShadowColor()`
- `getGlassEffectOptions()`
- `createGlassModifier()`
- `createGlassModifierWithOptions()`

这说明主题系统已经有“玻璃容器工厂”的雏形，但还停留在“单一通用 glass”层面，缺乏针对：

- 标题栏
- Hero 区
- 卡片
- 弹层
- 浮动控件

的分层设计。

### 3.3 用户主题配置已经支持透明度和特效开关

`UserThemeConfig.ets` 已有以下能力：

- 透明度配置：
  - `navigationBar`
  - `tabBar`
  - `card`
  - `dialog`
  - `floatingBall`
  - `menu`
  - `sidebar`
- 特效配置：
  - `enableBlur`
  - `blurIntensity`
  - `enableShadow`
  - `shadowIntensity`
  - `enableAnimation`
  - `animationSpeed`
  - `enableRoundedCorners`
  - `cornerRadius`
  - `enableGlassmorphism`

这意味着我们不需要重新发明用户配置模型，只需要把这些配置真正映射到统一的视觉层级上。

### 3.4 全局背景与后台模糊已经有基础组件

关键文件：

- `entry/src/main/ets/Framework/Components/GlobalBackgroundLayer.ets`
- `entry/src/main/ets/Framework/Components/BackgroundBlurOverlay.ets`

现状判断：

- `GlobalBackgroundLayer.ets` 负责自定义主题背景图或纯色背景回退
- `BackgroundBlurOverlay.ets` 已经用 `backgroundBlurStyle(BlurStyle.BACKGROUND_ULTRA_THICK, ...)` 做后台模糊保护层
- 该组件还用了 `ScaleSymbolEffect`

说明：

- 全局背景系统可以继续扩展
- 隐私遮罩路线已经具备较高完成度
- 不需要从零设计背景模糊体系

### 3.5 页面实现存在“半统一”问题

#### 代表页面现状

1. `GlobalSettingsPage.ets`

- 使用 `HdsNavDestination`
- 页面背景仍偏静态纯色
- 卡片大量使用 `panel_background`
- `titleBar` 仍是静态背景样式，没有接入统一玻璃标题栏策略

2. `SearchPage.ets`

- 使用 `HdsNavDestination`
- `titleBar` 已启用 `ScrollEffectType.COMMON_BLUR`
- 是当前项目里最接近“标准标题栏玻璃化”的样板

3. `EBookDetailPage.ets`

- 使用 `HdsNavDestination`
- 同时存在 `.hideTitleBar(true)` 与保留的 `titleBar` 模糊配置代码
- 说明设计方向已经考虑到滚动模糊，但尚未真正落地统一实现

4. `MangaDetailPage.ets`

- 已有较多玻璃卡片
- 已有渐变和封面区效果
- 但整体仍偏“组件级玻璃”，页面级结构和统一转场不足

5. `UnifiedDetailPage.ets`

- 仍使用 `NavDestination()`
- 标题栏策略没有收编进 `HdsNavDestination`
- 这页很适合作为统一详情骨架改造重点

6. `MainMenuPage.ets`

- 是当前视觉最复杂、玻璃效果最多的页面之一
- 顶部浮条、侧边浮条、刷新浮条、各种 popup 都各自调 blur/shadow
- 当前 SymbolGlyph 主要使用 `BounceSymbolEffect`
- 焕新价值极高，但必须先把视觉 token 收敛，否则只会更乱

## 4. 本地 SDK 能力确认

以下能力均已在本地 SDK 声明中实际确认。

### 4.1 18 起就已经可用的基础能力

这些能力并不是“21 新增”，而是项目升级后应该系统性收编：

1. `backgroundBlurStyle(style, options?)`

- 旧 SDK 18 中存在
- `@since 18`

2. `backdropBlur(radius, options?)`

- 旧 SDK 18 中存在
- `@since 18`

3. `renderGroup(isGroup?)`

- 旧 SDK 18 中存在
- `@since 18`

4. `pixelStretchEffect(options?)`

- 旧 SDK 18 中存在
- `@since 18`

5. `useEffect(useEffect?, effectType?)`

- 旧 SDK 18 中存在
- `@since 18`

6. `sharedTransition(id, options?)`

- 旧 SDK 18 中存在
- `@since 11`

7. `geometryTransition(id, options?)`

- 旧 SDK 18 中存在
- `@since 12`

### 4.2 升到 21/22 后更值得收编的增强点

1. `backgroundBlurStyle(style, options, sysOptions)`

- 当前默认 SDK 中存在
- `@since 19`
- 适合为标题栏、Hero 区和弹层补系统自适应参数

2. `navigation.d.ts` 中的 `backgroundBlurStyleOptions`

- `@since 19`
- 说明导航容器本身已支持更细粒度模糊配置

3. `action_sheet.d.ts` 中的 `backgroundBlurStyleOptions`

- `@since 19`
- 说明系统弹层路线可做更细粒度玻璃化

4. `customNavContentTransition(...)`

- 在 `navigation.d.ts` 中存在
- `@since 12`
- 适合补全统一页面转场节奏

5. `ScaleSymbolEffect / AppearSymbolEffect / DisappearSymbolEffect / BounceSymbolEffect / ReplaceSymbolEffect`

- 当前 SDK 中均存在
- 在 crossplatform 条目中可见 `@since 20`
- 适合把当前散乱的图标状态变化收敛成统一动效语言

6. `ComponentSnapshot / getComponentSnapshot()`

- 当前 SDK 中有更完整定义
- `ComponentSnapshot` 跨端增强条目可见 `@since 22`
- 二期可以用于封面取样、景深背景、分享预览图等高级玩法

7. `openBindSheet / updateBindSheet / closeBindSheet`

- `@since 12`
- 适合替换大量当前 `bindPopup` 的手机场景交互

### 4.3 项目中当前尚未真正用起来的能力

源码全量检索结果显示，以下能力在 `entry/src/main/ets` 中基本没有形成实际用例：

- `sharedTransition(`
- `geometryTransition(`
- `customNavContentTransition(`
- `openBindSheet(`
- `updateBindSheet(`
- `closeBindSheet(`
- `bindSheet(`

这意味着：

- 它们非常适合作为这次焕新的高价值增量点
- 不会与大量既有实现发生强耦合冲突

## 5. 焕新方向总原则

### 5.1 从“组件效果”升级到“页面视觉系统”

本次改造应分为三层：

1. 视觉 token 层

- 统一玻璃层级
- 统一透明度、边框、阴影、模糊、动效节奏

2. 页面骨架层

- 统一标题栏策略
- 统一 Hero 区结构
- 统一背景层级

3. 交互容器层

- 统一 popup/sheet/action sheet
- 统一导航转场和共享元素
- 统一 SymbolGlyph 动效语言

### 5.2 不追求“所有地方都很重”

本次焕新应当强调：

- 高频核心区域重做
- 长列表和阅读器保守
- 视觉层级清晰
- 性能优先

原则上：

- 真正的 blur 只给标题栏、Hero 区、浮层、sheet、悬浮操作条
- 普通列表卡片优先使用半透明 token，而不是每张卡片都真模糊

## 6. 建议改造架构

### 6.1 先建立五级玻璃视觉 token

建议在 `ThemeManager.ets` 与 `AppColors.ets` 中补齐以下层级：

1. `heroGlass`

- 最重的景深层
- 用于详情页头图区、沉浸式背景前景层

2. `navGlass`

- 用于 `HdsNavDestination.titleBar`
- 滚动时逐步增强模糊和遮罩

3. `cardGlass`

- 用于重点卡片、工具条、筛选条
- 比普通 `panel_background` 更轻、更统一

4. `sheetGlass`

- 用于手机底部 sheet、ActionSheet、上下文菜单

5. `floatingGlass`

- 用于浮动按钮、悬浮栏、底部刷新条、快速操作条

每一级应包含至少这些参数：

- `backgroundColor`
- `blurStyle`
- `backgroundBlurStyleOptions`
- `radius`
- `borderColor`
- `shadowColor`
- `opacity`
- `animationPreset`

### 6.2 用户主题配置映射到五级 token

建议将 `UserThemeConfig` 现有字段重新映射，而不是新增一套平行配置：

- `navigationBar` -> `navGlass`
- `card` -> `cardGlass`
- `dialog` / `menu` -> `sheetGlass`
- `floatingBall` -> `floatingGlass`
- `blurIntensity` -> 各层 blur scale 基线
- `shadowIntensity` -> 各层 shadow alpha/radius 系数
- `cornerRadius` -> 各层 radius 基线
- `animationSpeed` -> 全局动效倍率

### 6.3 为主题系统新增“按场景取效果”接口

建议在 `ThemeManager.ets` 中新增或重构：

- `getGlassToken(level: GlassLevel): GlassToken`
- `createGlassModifier(level: GlassLevel): CommonModifier`
- `getNavBarBlurOptions()`
- `getSheetBlurOptions()`
- `getHeroBlurOptions()`
- `getFloatingBlurOptions()`

这样后续页面不再自己拼：

- `backgroundColor`
- `backgroundBlurStyle`
- `shadow`
- `border`

避免视觉越改越散。

## 7. 页面级焕新方案

## 7.1 全局背景层

目标文件：

- `entry/src/main/ets/Framework/Components/GlobalBackgroundLayer.ets`
- `entry/src/main/ets/pages/ThemeSettingsPage.ets`

建议改造：

1. 把背景层改成三层结构

- 底图层：当前主题图或纯色
- 中间调色层：统一 scrim，用于暗化或提亮
- 顶层氛围层：可选的轻度模糊/渐变/景深 mask

2. 继续沿用 `ThemeSettingsPage.ets` 里已经存在的 `effectKit` 流程

- `filter.blur(...)`
- `filter.brightness(...)`
- 主色提取

这样可以在主题生成阶段就完成预处理，而不是运行时每一页重复做重型特效。

3. 让 `GlobalBackgroundLayer` 能根据当前页面类型切换背景模式

建议至少支持：

- 默认背景模式
- 沉浸式详情背景模式
- 阅读模式低干扰背景模式

## 7.2 标题栏统一

目标文件：

- `entry/src/main/ets/pages/SearchPage.ets`
- `entry/src/main/ets/pages/settings/GlobalSettingsPage.ets`
- `entry/src/main/ets/pages/ThemeSettingsPage.ets`
- `entry/src/main/ets/pages/EBookDetailPage.ets`
- `entry/src/main/ets/pages/MangaDetailPage.ets`
- `entry/src/main/ets/pages/UnifiedDetailPage.ets`

建议：

1. 以 `SearchPage.ets` 作为标题栏焕新样板

当前 `SearchPage` 已经有：

- `ScrollEffectType.COMMON_BLUR`
- 原始样式与滚动样式分离

这页适合作为统一模板抽象成 helper。

2. `GlobalSettingsPage.ets` 与 `ThemeSettingsPage.ets` 改为统一玻璃标题栏

当前这两页仍偏静态背景栏，应统一为：

- 初始状态更通透
- 滚动后进入 `navGlass`
- back/menu 按钮统一圆形玻璃按钮

3. `EBookDetailPage.ets` 恢复并真正启用滚动模糊标题栏

当前已有思路但仍保留在注释/兼容状态中，应作为第一批落地点。

4. `MangaDetailPage.ets` 与 `UnifiedDetailPage.ets` 采用“沉浸式 Hero + 滚动收束标题栏”

- 顶部初始不强调完整标题栏
- 滚动后逐步收束为标准玻璃导航栏

5. `UnifiedDetailPage.ets` 优先从 `NavDestination()` 收编到统一导航骨架

这是后续统一详情模板的关键。

## 7.3 首页 MainMenuPage 焕新

目标文件：

- `entry/src/main/ets/pages/MainMenuPage.ets`

这是本项目最值得做“旗舰焕新”的页面。

建议：

1. 先统一浮层容器样式

当前页面中：

- 顶部浮条
- 侧边浮条
- 搜索按钮
- 刷新浮条
- 预览浮条
- 各类 popup

大量各写各的 blur/shadow。

建议统一走：

- `floatingGlass`
- `sheetGlass`
- `cardGlass`

并且对复杂浮层统一补 `renderGroup(true)`。

2. 统一主页图标动效语言

当前底部/侧边 tab 的 `SymbolGlyph` 主要依赖 `BounceSymbolEffect`。

建议升级为：

- 选中态：`Bounce + Scale`
- 模式切换：`Replace`
- 新出现操作：`Appear`
- 消失/退出：`Disappear`

这样能显著提升主页的“新版本感”。

3. 将 popup 体系分流

当前主页里很多筛选和上下文菜单使用 `bindPopup`。

建议：

- 手机：主用 `bindSheet/openBindSheet`
- 平板/大屏：保留 popup 或 side sheet

优先改造：

- 书架排序/网格设置
- 漫画/电子书/小说卡片长按菜单
- 书签作者/标签筛选
- 图源项上下文菜单

4. 补统一页面转场

主页到详情的点击，应优先为这些元素加共享转场：

- 封面图
- 标题文本
- 类型标签
- 主按钮组

建议第一批只做稳定元素，不做整卡共享，避免兼容性复杂度过高。

## 7.4 MangaDetailPage 焕新

目标文件：

- `entry/src/main/ets/pages/MangaDetailPage.ets`

当前页已经有不错的视觉基础，应继续升级为“统一详情样板”。

建议：

1. 建立 Hero 区三层结构

- 背景封面放大层
- `backdropBlur/pixelStretchEffect` 景深层
- 前景信息层

2. 顶部采用“沉浸式标题栏 -> 滚动收束玻璃标题栏”

3. 当前零散玻璃块统一接入 token

不要再直接在页面里散写：

- `ThemeManager.getInstance().getGlassBackgroundResource()`
- `ThemeManager.getInstance().getGlassBlurStyle()`

而是让详情页显式使用：

- `heroGlass`
- `cardGlass`
- `floatingGlass`

4. 将章节筛选、排序、下载选项等弹层逐步改为 sheet 化

当前很多交互仍是 popup，更像工具菜单而非内容面板。

更适合改成：

- 手机：底部 sheet
- 大屏：侧边 sheet 或 popup

## 7.5 UnifiedDetailPage 焕新

目标文件：

- `entry/src/main/ets/pages/UnifiedDetailPage.ets`

该页面是“统一详情框架”的理想落点。

建议：

1. 从 `NavDestination()` 迁移到统一导航骨架

优先考虑：

- 是否切到 `HdsNavDestination`
- 是否复用详情页统一 title bar helper

2. 统一 Hero 区与工具条策略

把漫画详情、电子书详情、统一详情三个页面收成同一套路：

- 顶部沉浸式 Hero
- 滚动收束标题栏
- 底部操作条玻璃化

3. 把这页做成后续详情模板母版

如果这页收拢成功，后续：

- `MangaDetailPage`
- `EBookDetailPage`
- 可能的新内容详情页

都能复用。

## 7.6 EBookDetailPage 焕新

目标文件：

- `entry/src/main/ets/pages/EBookDetailPage.ets`

建议：

1. 正式启用滚动模糊标题栏

当前页面已有相关结构和思路，是低风险高收益项。

2. 详情操作区与信息区统一玻璃容器

将当前零散的操作按钮、状态块、信息块统一接入 token。

3. 和 `MangaDetailPage` 对齐详情页体验

目标不是让两个页面完全一样，而是让它们遵循同一套视觉语法。

## 7.7 设置页体系焕新

目标文件：

- `entry/src/main/ets/pages/settings/GlobalSettingsPage.ets`
- 其他设置页

建议：

1. 所有 `HdsNavDestination` 设置页统一玻璃标题栏模板

2. 设置组卡片统一成“轻玻璃 + 统一边框 + 更柔和阴影”

3. 右侧箭头、开关、二级入口统一 `SymbolGlyph` 风格

4. 搜索栏和筛选栏统一接入 `cardGlass`

设置页的价值在于：

- 它能快速覆盖大量二级页面
- 是低风险、高可见度的焕新入口

## 7.8 Reader 页策略

目标文件：

- `entry/src/main/ets/pages/MangaReaderPage.ets`
- `entry/src/main/ets/pages/EBookReaderPage.ets`

建议：

- 不做正文区域重特效
- 只做 chrome 级玻璃化
- 保留控制栏、工具栏、菜单的焕新

原因：

- 阅读器是高频核心场景
- 大面积 blur 或复杂背景最容易影响可读性和性能

## 8. 交互容器改造策略

### 8.1 popup -> sheet 分流

建议按设备分流：

1. 手机

- 优先 `bindSheet`
- 更复杂场景使用 `openBindSheet`

2. 平板 / 大屏

- 保留 `bindPopup`
- 或演进为侧边 sheet

适合优先改造的场景：

- 排序
- 筛选
- 长按上下文菜单
- 快速设置
- 下载选项

### 8.2 标准弹层视觉

建议为 sheet 和 popup 统一定义：

- 背景毛玻璃层
- 圆角等级
- 顶部 drag indicator
- 内部分组卡片层级
- 出入场动画曲线

### 8.3 动画节奏统一

建议统一三档：

1. 快速

- 图标反馈
- chip 状态切换

2. 标准

- 标题栏收束
- 卡片显隐
- sheet 打开关闭

3. 强调

- 主页到详情共享转场
- Hero 区进入动画

## 9. 转场与动效建议

### 9.1 第一批共享元素

建议先给以下元素做 `sharedTransition` / `geometryTransition`：

- 首页封面 -> 详情封面
- 搜索结果封面 -> 详情封面
- 标题文本
- 来源 / 类型标签
- 部分操作按钮

### 9.2 不建议一开始全量共享整卡

原因：

- 复合卡片元素太多
- 不同布局之间适配成本高
- 容易引入裁切和层级异常

更稳妥的做法是先做封面、标题、标签这种稳定元素。

### 9.3 SymbolGlyph 动效收敛建议

建议建立统一规范：

- 选中态：`BounceSymbolEffect`
- 重点强调：`ScaleSymbolEffect`
- 替换态：`ReplaceSymbolEffect`
- 进入：`AppearSymbolEffect`
- 退出：`DisappearSymbolEffect`

同时应避免：

- 每个地方都随机使用不同动效
- 将 Symbol 动效与复杂位移动画叠加过重

## 10. 性能策略

### 10.1 blur 预算控制

必须明确：

- 不是所有卡片都应该真实 blur
- 长列表卡片大多数应使用“半透明 token + 边框 + 轻阴影”
- 真 blur 只留给高优先级容器

### 10.2 建议使用 `renderGroup` 的场景

优先包括：

- 主页浮动栏
- 底部刷新浮条
- 复杂玻璃 popup/sheet
- 详情页悬浮工具条

### 10.3 预处理优先于运行时重型处理

主题背景相关效果应尽量在：

- 主题生成
- 主题切换

时预处理，而不是在每个页面 build 期间重复处理。

### 10.4 阅读器与大列表保守

这两个区域是性能风险最高的地方，应始终优先：

- 滚动稳定性
- 文本/图片可读性
- 输入响应速度

## 11. 推荐实施顺序

## 11.1 第一期：先把体系立起来

优先文件：

- `entry/src/main/ets/Framework/Managers/ThemeManager.ets`
- `entry/src/main/ets/Framework/Theme/AppColors.ets`
- `entry/src/main/ets/Framework/Theme/UserThemeConfig.ets`
- `entry/src/main/ets/Framework/Components/GlobalBackgroundLayer.ets`
- `entry/src/main/ets/Framework/Components/BackgroundBlurOverlay.ets`

目标：

- 建立统一 token
- 建立统一玻璃 modifier
- 收拢背景层结构

## 11.2 第二期：做页面样板

优先文件：

- `entry/src/main/ets/pages/SearchPage.ets`
- `entry/src/main/ets/pages/settings/GlobalSettingsPage.ets`
- `entry/src/main/ets/pages/EBookDetailPage.ets`
- `entry/src/main/ets/pages/UnifiedDetailPage.ets`

目标：

- 统一标题栏骨架
- 统一设置页和详情页基础体验

## 11.3 第三期：做旗舰视觉页

优先文件：

- `entry/src/main/ets/pages/MainMenuPage.ets`
- `entry/src/main/ets/pages/MangaDetailPage.ets`

目标：

- 首页整体焕新
- Hero 区与共享转场落地
- popup -> sheet 体系迁移

## 11.4 第四期：做高级效果与收尾

候选：

- `ComponentSnapshot` 取样背景
- 更精细的 `customNavContentTransition`
- 更完整的大屏分流策略

## 12. 第一阶段建议清单

建议先执行以下可落地任务：

1. 在 `ThemeManager.ets` 中新增玻璃层级枚举与 token 获取接口
2. 在 `AppColors.ets` 中补齐与玻璃层级对应的语义色
3. 在 `UserThemeConfig.ets` 中完成用户配置到 token 的映射
4. 在 `GlobalBackgroundLayer.ets` 中扩展背景三层结构
5. 将 `SearchPage.ets` 抽象为标准玻璃标题栏样板
6. 将 `GlobalSettingsPage.ets` 接入统一标题栏和设置卡片容器
7. 让 `EBookDetailPage.ets` 正式启用滚动模糊标题栏
8. 规划 `UnifiedDetailPage.ets` 向统一详情模板收敛

## 13. 最终判断

这次升级带来的机会，不是“加几个新 API”，而是让整个 APP 的视觉语言从：

- 各页面零散使用 blur
- 各组件自行拼装玻璃背景
- popup、标题栏、浮层风格不统一

升级为：

- 有清晰层级的玻璃视觉体系
- 有统一滚动标题栏骨架
- 有 Hero 区与共享转场
- 有 sheet 化交互
- 有统一 SymbolGlyph 动效语言
- 有明确性能预算

如果这套方案落地，焕新感最明显的页面会是：

- `MainMenuPage`
- `MangaDetailPage`
- `UnifiedDetailPage`
- `EBookDetailPage`
- `GlobalSettingsPage`
- `SearchPage`

而真正支撑这些页面持续演进的基础，则是：

- `ThemeManager`
- `AppColors`
- `UserThemeConfig`
- `GlobalBackgroundLayer`

## 14. 依据说明

本方案基于以下三类依据形成：

1. 项目源码实际盘点

- 主题系统
- 背景层
- 首页、详情页、设置页、搜索页实现现状

2. 本地 SDK 声明确认

- `F:\HarmonyOS\SDK\18\ets\component\common.d.ts`
- `F:\DevEco Studio\sdk\default\openharmony\ets\component\common.d.ts`
- `F:\DevEco Studio\sdk\default\openharmony\ets\component\navigation.d.ts`
- `F:\DevEco Studio\sdk\default\openharmony\ets\component\action_sheet.d.ts`
- `F:\DevEco Studio\sdk\default\openharmony\ets\component\symbolglyph.d.ts`
- `F:\DevEco Studio\sdk\default\openharmony\ets\api\@ohos.arkui.UIContext.d.ts`

3. 官方资料方向

已按 OpenHarmony 官方文档站与官方文档仓库的相关主题进行检索，重点参考方向包括：

- blur / background effect
- shared element transition
- sheet transition
- SymbolGlyph effect

其中本次能力判断以本地 SDK 声明为最终依据。

