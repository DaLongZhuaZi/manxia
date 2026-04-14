# 小说书源导入能力梳理（Manxia）

更新时间：2026-04-14

## 1. 当前已支持的导入方式

基于 `entry/src/main/ets/pages/NovelSourceManagementPage.ets`：

1. 文件导入（支持多文件）
- 入口：导入弹层 -> `从文件导入`
- 实现：`importFromFile()`（DocumentViewPicker，多文件轮询导入）

2. 剪贴板导入
- 入口：导入弹层 -> `从剪贴板导入`，或空列表态按钮
- 实现：`pasteFromClipboard()` + `doImport()`

3. 网络导入
- 入口：导入弹层 -> `网络导入（含 Legado 链接）`
- 实现：`importFromNetwork()`
- 支持输入：
  - `http://` / `https://` 直链
  - `legado://import/...?...src=...` 中 `src` 参数

4. 远程索引递归导入（Legado 兼容增强）
- 网络内容若为 `sourceUrls` / `bookSourceUrls` 索引，会递归拉取并导入
- 含去重与最大深度限制（`NETWORK_IMPORT_MAX_DEPTH = 4`）

## 2. 与 Legado 规则的对齐点

本仓库内 Legado 参考实现（`legado/`）显示：

1. URL Scheme 导入
- `legado://import/{path}?src={url}`
- 参考：`legado/README.md`，`OnLineImportActivity.kt`

2. 书源导入输入形态
- JSON 对象 / JSON 数组
- `sourceUrls` 远程索引
- 直接 URL / URI
- 参考：`ImportBookSourceViewModel.kt`

Manxia 当前对齐情况：
- 已对齐：JSON 对象/数组、URL 网络导入、`sourceUrls` 远程索引、Legado scheme 的 `src` 解析
- 未直接对齐：URI 文件串（当前主要通过文件选择器和剪贴板覆盖）

## 3. 小说书源管理页入口与弹层规范

当前实现入口链路：

1. 标题栏 `导入书源` 按钮
- 触发 `showImportOptions()`
- 打开自定义导入入口弹层（非系统 ActionMenu）

2. 统一弹层基座
- 全部导入相关弹层均基于 `SourceDialogScaffold`
- 具备：
  - 玻璃模糊遮罩（mask blur）
  - 卡片玻璃模糊（card blur）
  - 缩放 + 透明度过渡动画

3. 导入弹层结构
- 导入入口弹层：方式选择（文件/剪贴板/网络）
- 文本导入弹层：粘贴 JSON 并导入
- 网络导入弹层：输入链接并下载导入

## 4. 关键代码位置

1. 页面与入口
- `entry/src/main/ets/pages/NovelSourceManagementPage.ets`

2. 统一玻璃弹层
- `entry/src/main/ets/Framework/Components/SourceDialogScaffold.ets`

3. Legado 书源解析
- `entry/src/main/ets/Framework/Novel/LegadoSourceParser.ets`

4. Legado 参考实现（仓库内）
- `legado/app/src/main/java/io/legado/app/ui/association/OnLineImportActivity.kt`
- `legado/app/src/main/java/io/legado/app/ui/association/ImportBookSourceViewModel.kt`
