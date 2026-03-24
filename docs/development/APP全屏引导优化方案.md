# APP 全屏引导优化方案

## 1. 目标

本方案用于统一记录 APP 当前全屏引导、页内引导遮罩、引导重播入口、长页面滚动对齐，以及悬浮层可读性相关的优化内容，并作为后续分批实施的执行基线。

本轮优化目标分为两层：

1. 修复现有全屏引导在覆盖范围、锚点定位、状态栏覆盖、滚动对齐上的问题。
2. 将引导从“少量页面的轻提示”扩展为“覆盖核心页面主要操作路径的系统化引导”。

## 2. 现状评估

### 2.1 已完成的基础修复

以下问题已经完成基础修复或已进入可继续扩展的状态：

1. `MainMenuPage`、阅读器页面的部分引导遮罩已开始支持更完整的全屏覆盖与安全区扩展。
2. `GlobalSearchPage` 已接入页内引导框架，不再是完全缺失引导的页面。
3. `UnifiedDetailPage` 已补充基础锚点，能够作为统一详情流的继续扩展基础。
4. `GlobalSettingsPage`、`ThemeSettingsPage`、`NovelSourceManagementPage` 已补充部分滚动对齐逻辑。
5. 悬浮层背景与玻璃效果透明度已提升，可读性已得到第一轮修正。

### 2.2 当前核心问题

当前全屏引导系统仍有以下结构性问题：

1. 页面覆盖率仍然偏低，很多高频核心页仍未接入 `AppGuideOverlay`。
2. 已接入页面的步骤过少，平均每个流程只有少量步骤，只能说明“这里是什么”，还不能说明“这里怎么用”。
3. 大量复杂页面缺少足够的锚点，导致无法稳定高亮到真正重要的操作区。
4. 长页面虽然已有局部滚动修正，但还未形成统一的“引导前滚动到目标锚点”的处理规范。
5. 首启 `WelcomeGuidePage` 与页内 `AppGuideOverlay` 仍属于双轨制，引导内容存在重复与割裂。

### 2.3 引导覆盖现状

当前已接入页内引导的核心页面主要包括：

1. `MainMenuPage`
2. `GlobalSearchPage`
3. `UnifiedDetailPage`
4. `MangaReaderPage`
5. `NovelReaderPage`
6. `EBookReaderPage`
7. `GlobalSettingsPage`
8. `ThemeSettingsPage`
9. `NovelSourceManagementPage`
10. `BackupPage`
11. `DownloadSyncPage`
12. `AnnotationCenterPage`
13. `SuwayomiBrowsePage`

当前仍缺少页内引导但操作密度较高的核心页面包括：

1. `SearchPage`
2. `NovelSearchPage`
3. `MangaDetailPage`
4. `NovelDetailPage`
5. `EBookDetailPage`
6. `SourceDetailPage`
7. `SuwayomiMangaDetailPage`
8. `SuwayomiReaderPage`
9. `ReadAloudPlayerPage`
10. `NovelReadAloudPage`
11. `DownloadManagerPage`
12. `StorageManagementPage`
13. `DataManagementPage`
14. `ReadingAnalyticsPage`
15. `SourceManagementPage`
16. `BookSourceManagementPage`
17. 高频设置子页面
18. `HelpCenterPage`

## 3. 优化原则

### 3.1 最小修改原则

P0 阶段必须遵守以下原则：

1. 优先扩展已经接入 `AppGuideOverlay` 的页面，不先做大规模重构。
2. 优先新增锚点 ID、扩充流程步骤、补充滚动对齐，不先改动引导协议模型。
3. 只在确有必要时才新增页面状态与辅助方法，避免一次性引入新的复杂状态机。
4. 已经恢复可编译的页面结构不得被回退或重写。

### 3.2 引导内容原则

每个核心页面的引导至少应覆盖：

1. 页面定位：这是哪里，主要负责什么。
2. 主操作入口：用户进入页面后第一步应该点哪里。
3. 次级操作入口：筛选、排序、设置、切换、缓存、下载等。
4. 状态识别：如何看懂当前状态、进度、缓存、来源、阅读位置。
5. 风险操作提示：删除、清理、恢复、替换、批量操作等。

### 3.3 编码与校验原则

1. 所有新增或修改内容必须使用 UTF-8 编码。
2. 所有中文必须为真实中文字符，禁止乱码。
3. 禁止在业务文件中保留 Unicode 转义形式的文本。
4. 每轮修改后必须执行 UTF-8 解码校验与关键中文读回校验。

## 4. 分阶段实施范围

## 4.1 P0：已接入核心页做深做细

P0 的目标不是“覆盖所有页面”，而是先把最核心、最高频、最容易通过最小修改做深的页面做完整。

### P0-1 主页面与统一入口

1. `MainMenuPage`
2. `GlobalSearchPage`
3. `UnifiedDetailPage`

目标：

1. 完整覆盖主入口、核心筛选、搜索结果承接、详情页主要操作、章节区与二级工具入口。
2. 每页步骤数优先扩展到 4 到 8 步。

### P0-2 三类阅读器

1. `MangaReaderPage`
2. `NovelReaderPage`
3. `EBookReaderPage`

目标：

1. 从单步提示扩展到完整说明菜单呼出、章节切换、设置入口、进度识别与返回路径。
2. 优先复用已有根锚点与常驻控件锚点，避免先引入复杂交互依赖。

### P0-3 核心设置与来源管理

1. `GlobalSettingsPage`
2. `ThemeSettingsPage`
3. `NovelSourceManagementPage`
4. `SourceManagementPage`
5. `BookSourceManagementPage`

目标：

1. 统一说明搜索、分组、导入、启停、筛选、排序、批量操作。
2. 长页面必须补齐滚动对齐。

### P0-4 下载与管理

1. `DownloadManagerPage`
2. `DownloadSyncPage`

目标：

1. 说明任务状态、过滤方式、暂停恢复、缓存统计、清理入口、同步导入路径。

## 4.2 P1：补齐内容发现与详情链路

页面范围：

1. `SearchPage`
2. `NovelSearchPage`
3. `MangaDetailPage`
4. `NovelDetailPage`
5. `EBookDetailPage`
6. `SourceDetailPage`
7. `SuwayomiMangaDetailPage`
8. `SuwayomiBrowsePage`
9. `SuwayomiReaderPage`

目标：

1. 补齐“搜索 -> 详情 -> 阅读”的完整操作链路。
2. 解决统一详情页与旧详情页并存期间的引导断层。

## 4.3 P2：补齐管理页、分析页与帮助重播闭环

页面范围：

1. `StorageManagementPage`
2. `DataManagementPage`
3. `ReadingAnalyticsPage`
4. `AnnotationCenterPage`
5. `ReadAloudPlayerPage`
6. `NovelReadAloudPage`
7. `HelpCenterPage`
8. 高频设置子页面
9. RSS 相关页面

目标：

1. 让帮助中心真正承接“任务流重播”。
2. 将复杂管理页和听书链路补齐。

## 5. 技术策略

### 5.1 第一阶段不重做引导架构

P0 不重做 `AppGuideManager` 协议，不立即合并 `WelcomeGuidePage` 和 `AppGuideOverlay`。

P0 只做以下增量改造：

1. 给关键区域补充稳定锚点 ID。
2. 扩充现有 `GUIDE_FLOWS` 的步骤数量和说明文案。
3. 给长页面补充 `ensureGuideAnchorVisibleInScroller(...)` 对齐逻辑。
4. 修复因安全区、状态栏、滚动容器导致的高亮错位。

### 5.2 第二阶段再考虑能力升级

当 P0 和 P1 基本完成后，再评估是否需要增加：

1. 按任务拆分的引导流。
2. 需要前置操作的步骤前置条件。
3. 多高亮或区域组合高亮。
4. 从帮助中心按任务直接重播。

## 6. 页面级建议步骤

### 6.1 GlobalSearchPage

建议至少覆盖：

1. 搜索输入框。
2. 内容类型筛选。
3. 来源类型筛选。
4. 搜索历史与结果承接区域。
5. 搜索后按来源分组的结果阅读方式。

### 6.2 UnifiedDetailPage

建议至少覆盖：

1. 页头信息。
2. 阅读主入口。
3. 标签与简介区域。
4. 设置、换源、缓存等工具操作区。
5. 章节区或电子书阅读信息区。

### 6.3 Reader 系列页面

建议至少覆盖：

1. 阅读区域与菜单呼出方式。
2. 章节切换。
3. 目录与进度识别。
4. 阅读设置入口。
5. 返回与恢复逻辑。

## 7. 验收标准

每轮提交必须满足：

1. 页面能正常编译。
2. 新增引导步骤能稳定定位到对应锚点。
3. 长页面目标锚点能够自动滚动到可视区域。
4. 全屏遮罩能覆盖到状态栏区域。
5. 所有新增中文通过 UTF-8 解码校验。

## 8. 本轮执行记录

本轮开始正式执行 P0，采用最小修改原则，首批实施范围如下：

1. `GlobalSearchPage`
2. `UnifiedDetailPage`
3. `AppGuideManager` 中对应流程定义

本轮实施目标：

1. 不重做引导协议。
2. 不改动页面主要业务结构。
3. 只补充关键锚点、步骤文案与必要的滚动对齐能力。

### 8.1 已追加完成的批次

在首批 `GlobalSearchPage`、`UnifiedDetailPage` 之后，本轮继续追加完成了以下 P0 深化内容：

1. 三类阅读器引导扩展：`MangaReaderPage`、`NovelReaderPage`、`EBookReaderPage`
2. 设置与管理页引导扩展：`GlobalSettingsPage`、`ThemeSettingsPage`、`NovelSourceManagementPage`
3. `AppGuideManager` 对应流程定义同步扩展

### 8.2 本轮新增落地点

本轮新增的最小改动主要包括：

1. 为三类阅读器补充顶部工具栏、底部工具栏、目录面板锚点。
2. 为阅读器引导增加“步骤前准备展示”逻辑，在高亮前自动展开工具栏或目录面板。
3. 为全局设置页补充更细的分组级锚点，覆盖阅读设置入口与备份入口。
4. 为书源管理页补充搜索栏锚点，并让引导步骤可自动展开搜索栏。
5. 扩充主题设置、全局设置、书源管理、三类阅读器的步骤文案，使其从“轻提示”提升到“操作路径说明”。

### 8.3 当前 P0 进展

截至当前，P0 已完成或已显著深化的页面包括：

1. `MainMenuPage`
2. `GlobalSearchPage`
3. `UnifiedDetailPage`
4. `MangaReaderPage`
5. `NovelReaderPage`
6. `EBookReaderPage`
7. `GlobalSettingsPage`
8. `ThemeSettingsPage`
9. `NovelSourceManagementPage`

下一批优先顺序保持不变，继续按最小修改原则推进：

1. `SourceManagementPage`
2. `BookSourceManagementPage`
3. `DownloadManagerPage`
4. `DownloadSyncPage`

### 8.4 欢迎引导基础阻塞修复

在继续扩展更多页面引导之前，先补了一批会持续影响后续引导正确性的基础问题，避免后面所有新页面都建立在不稳定的欢迎引导与遮罩层之上。

本批修复目标如下：

1. 欢迎引导仍在使用旧图标资源，需统一迁移为 `sys.symbol.*`，并保证浅色、深色模式下可读。
2. 全屏引导悬浮卡片和遮罩层背景过透，导致说明文字可读性差。
3. 局部高亮在部分页面和部分时机下存在遮罩缺失或遮罩范围异常的问题。
4. 从欢迎引导跳转到目标页面后返回时，未能稳定回到欢迎引导继续下一步。

本批实际落地如下：

1. `WelcomeGuidePage` 的欢迎、主题、导入、图源、书源、自定义体验、阅读报告、开始阅读等步骤图标已统一替换为 `sys.symbol.*` 资源。
2. `WelcomeGuidePage` 默认图标展示从旧的 `Image(...)` 改为带主题适配背景容器的 `SymbolGlyph(...)`，提升浅色、深色模式一致性。
3. `AppGuideOverlay` 已提升遮罩层颜色强度、卡片背景不透明度、边框与阴影强度，并补充更厚的背景模糊效果。
4. `AppGuideOverlay` 已增加高亮区域几何有效性校验与边界裁剪，减少因异常坐标导致的“局部没有遮罩”问题。
5. `WelcomeGuideManager` 的步骤持久化相关方法已补齐初始化保护，避免在未完成初始化时写入状态失败。
6. `WelcomeGuidePage` 已增加 `aboutToAppear` 与 `onPageShow` 的步骤同步逻辑，确保从目标页返回后可以重新读取最新步骤。
7. `MainMenuPage` 已增加从引导目标页返回时的兜底回跳逻辑，在页面重新显示且目标页已关闭时，主动返回 `WelcomeGuidePage` 继续流程。

本批涉及文件如下：

1. `entry/src/main/ets/pages/WelcomeGuidePage.ets`
2. `entry/src/main/ets/Framework/Managers/WelcomeGuideManager.ets`
3. `entry/src/main/ets/Framework/Components/AppGuideOverlay.ets`
4. `entry/src/main/ets/pages/MainMenuPage.ets`

本批校验结果如下：

1. 上述 4 个文件已完成严格 UTF-8 解码校验，通过后再继续保留修改。
2. 上述 4 个文件已完成中文读回检查，当前未发现替换字符或明显乱码。
3. `git diff --check` 已执行，当前未发现空白符层面的新增问题。
4. 当前终端环境未提供可直接调用的 `hvigor` 或 `ohpm` 命令，因此尚未在本轮修改后重新触发一次新的命令行构建。
5. `.hvigor/report` 中存在今天较早时间的成功构建记录，可证明项目在本轮之前处于可构建状态；本轮修改后的 fresh build 仍需在 DevEco Studio 内继续复核。
