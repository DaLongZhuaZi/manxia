# 📢 更新日志

> 感谢您使用漫匣！以下是最新版本的更新内容。

## 🚀 v0.1.2 `(104802309)`

### ✨ 书源引擎与云更新 (Source Engine & Cloud Updates)

- **新增书源引擎页面**
  > 集中管理 Legado 兼容书源索引与运行时资产。
  - 在小说设置页新增“书源引擎”入口，并接入独立页面导航。
  - 页面支持自管书源索引地址、运行时仓库地址、已保存仓库、同步进度、同步日志与更新提示展示。
  - 明确声明漫匣 App 与仓库不提供、不内置、不推荐、不托管、不维护任何书源，用户需要自行导入或维护书源。

- **新增 Legado 书源仓库同步基础能力**
  > 支持用户通过独立 GitHub 仓库维护自己的 Legado 兼容书源索引。
  - 新增 `NovelSourceRepositoryManager`，使用独立目录 `filesDir/legado-source-repositories` 管理索引、书源文件、图标和仓库记录。
  - 支持下载并校验 `index.main.json`、`pkg/source.json` 与可选图标，按 `sha256` 校验后导入或更新本地书源。
  - 更新已有书源时保留用户本地状态，包括启用状态、权重、排序、分组与 NSFW 手动设置。
  - 默认官方书源索引保持空索引，仅作为格式模板和同步机制验证，不向用户下发任何书源。

### 🧩 运行时资产与兼容层 (Runtime Assets)

- **新增 Legado WebView 运行时资产管理器**
  > 为后续 Legado 兼容层 HTML/JS/Rhino 沙箱资产热更新建立基础。
  - 新增 `LegadoRuntimeAssetManager`，使用 `staging/active/rollback` 三段目录管理运行时安装、切换与回滚。
  - 支持下载运行时 manifest 中声明的 HTML、JavaScript、Rhino 沙箱文件，校验路径、大小与 `sha256` 后切换到 active。
  - `LegadoWebViewComponent` 与 `RhinoSandboxComponent` 会优先加载已验证 active 目录，失败后回退内置 rawfile。
  - `LegadoRuntimeV2` 等待运行时页面健康检查通过后再进入可执行状态，避免页面尚未准备完成时执行 JS。

- **运行时版本展示与版本标记**
  > 书源引擎页面现在能直接显示运行时实际状态。
  - 展示当前运行时版本、code、runtimeApi、健康状态、激活时间与 rawfile 回退状态。
  - 接入 `VersionHistoryManager` 的仓库版本标记，展示本地已同步 commit、远端最新 commit 与检查状态。
  - 手动“检查版本”会强制检查默认书源索引仓库与运行时仓库，不会误把未记录本地版本显示为“已是最新”。

### 🔄 版本管理与更新检测 (Version Management)

- **扩展 GitHub 仓库版本管理**
  > 将 Legado 书源索引与运行时仓库纳入统一版本记录。
  - `VersionHistoryManager` 新增 `manxia_legado_sources` 与 `manxia_legado_runtime` 两个 GitHub target。
  - 手动同步默认仓库成功后记录对应 GitHub commit marker，用于后续判断是否存在更新。
  - 自动检查不再放入冷启动流程，而是在 `MainMenuPage` 加载并显示后执行，每日最多检查一次且只提示状态，不自动下载。

- **新增独立仓库结构与文档**
  > 将可热更新资产从主 App 编译产物中拆分出来。
  - 新增并连接 `manxia-legado-sources` 与 `manxia-legado-runtime` 两个独立仓库。
  - 两个仓库均提供中文主文档与英文文档，并补充仓库格式、版本管理和内容边界说明。
  - 运行时仓库修正 GitHub raw 文件换行与 manifest size/hash 不一致问题，保证云端同步校验稳定。

### 🛠 修复与体验优化 (Fixes & Improvements)

- **修复书源引擎弹层动画**
  > 统一 `SourceDialogScaffold` 的出现与消失过渡。
  - 为遮罩增加 opacity transition。
  - 为弹层卡片增加 opacity + scale transition，使书源引擎及相关弹窗出现和关闭更自然。

- **修复仓库连通性与同步错误**
  > 降低代理探测噪声，提高同步失败定位准确性。
  - 优化仓库路由选择，优先使用可连通地址；当主地址可用时，代理探测失败只记录为备用地址不可用。
  - 修复运行时文件大小不匹配导致同步失败的问题：若 `sha256` 已通过则允许继续；文本资产可按索引换行格式归一化后再校验。
  - 修复空书源索引同步时被误判为失败的问题，空索引现在会作为合法同步结果处理。
