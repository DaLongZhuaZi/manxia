# 漫匣 API 26（HarmonyOS 7）升级与反馈入口一级页改造报告

> 分支：`manxia-api26-upgrade`（worktree：`C:\Users\13359\.paseo\worktrees\35047gzq\manxia-api26-upgrade`）
> 基线提交：`08ef5b26 Merge branch 'agent/supporters-json'`
> 代码提交：`459e1127 feat(api26): 升级到 API 26 并将反馈中心入口移到一级页`
> 工程：`com.dlzz.manxia`，版本 `0.1.4`（versionCode `105402300`）
> 报告生成：2026-11-25

---

## 0. 结论摘要

| 项目 | 结果 |
|---|---|
| 目标 API | 已从 `6.1.0(23)` 升到 **`26.0.0`**（API 26 / HarmonyOS 7） |
| 构建 | **通过**：清理后全量 `assembleHap` 成功（3m40s）；提交后默认配置重建成功（3m40s）；剥离签名后的 CI 路径也成功（45s） |
| 破坏性变更 | 未发现仓库使用被移除 API；已修复 5 处全局 `promptAction.*` 废弃调用；其余为视觉/行为默认值风险，见 §3 |
| 新能力已实现 | 3 项：PDF 深色渲染模式、中文标点悬挂、EPUB 视频全屏覆盖层 |
| 反馈入口 | 已移到**一级页面**（全标签页可见的悬浮按钮）；原“关于应用→问题反馈”入口移除；反馈页/服务/缓存未改 |
| 真机运行验证 | **受阻**：两台 API 26 设备均因签名 profile 授权/信任问题拒绝安装；已用 HAP 元数据 + 字节码字符串作为替代证据 |
| main 工作树 | 未合、未 push、未归档；未复制 main 未提交改动；有 2 个文件存在**合并冲突风险**，见 §8 |

---

## 1. 审计：工具链、SDK、模块与配置

### 1.1 本机实际工具链

| 项 | 值 | 证据 |
|---|---|---|
| DevEco Studio | `26.0.0`，安装于 `G:\DevEco Studio 26\DevEco Studio` | `build.txt = DS-261.23567.138.36.2600821` |
| hvigor | `6.26.4` | `tools/hvigor/hvigor/package.json` |
| 构建用 SDK | `26.0.0.105`（DevEco 自带 `sdk/default`） | `oh-uni-package.json` / 构建 HAP `compileSdkVersion` |
| 备用 SDK | `F:\HarmonyOS\SDK\26.0.0`（`26.0.0.38`）、`F:\HarmonyOS\SDK\23`（`6.1.0.32`） | 本机目录 |
| 旧文档路径 | `F:\DevEco Studio` 已不存在 | AGENTS.md 2.1/2.2 的历史路径需要后续维护 |

构建环境变量实际使用：

```powershell
$env:DEVECO_SDK_HOME='G:\DevEco Studio 26\DevEco Studio\sdk'
```

> AGENTS.md 里 `F:\DevEco Studio\tools\hvigor\bin\hvigorw.bat` 在本机已失效；
> 本次使用 `G:\DevEco Studio 26\DevEco Studio\tools\hvigor\bin\hvigorw.bat`。

### 1.2 版本号格式变化（升级的第一个坑）

API 26 起 HarmonyOS 版本号改为语义化版本，`build-profile.json5` 使用 **`26.0.0`**，
不能再写 `26.0.0(26)`。证据：

- `sdkApiVersionMap.json`：`"26.0.0":["26.0.0"]`，无 `26.0.0(26)`。
- hvigor 的 `newDotSeparatedVersion` 正则只接受 `^([2-9][0-9])\.[1-9]?[0-9]\.[1-9]?[0-9]$`；
  `26.0.0(26)` 会走旧格式正则并校验失败。
- 本机 `hos-config.json` 的 `osVersionMapper`：`"26.0.0": "26.0.0"`。

### 1.3 模块与依赖

- 全部 10 个参与编译的模块均为 HAR（`entry` 为 HAP），模块 `oh-package.json5` 的
  `name` 与目录一一对应，`version` 均为 `1.0.0`。
- 根 `oh-package.json5` / `hvigor/hvigor-config.json5` 的 `modelVersion` 仍为 `6.0.1`；
  hvigor 6.26.4 可正常接受，未强行升级。
- 根目录 `build-profile.json5` 被 `.gitignore` 忽略，CI 的唯一配置来源是
  `build-profile.json5.example`；本次已同步修改该模板。

### 1.4 升级前后 SDK 配置

| 字段 | 升级前 | 升级后 |
|---|---|---|
| `targetSdkVersion` | `6.1.0(23)` | `26.0.0` |
| `compatibleSdkVersion` | `6.1.0(23)` | `26.0.0` |
| `runtimeOS` | `HarmonyOS` | `HarmonyOS`（未变） |
| `compileSdkVersion` | 未显式写，随 IDE | 未显式写，实际 `26.0.0.105` |

`build-profile.json5.example`、`AGENTS.md` 已同步；CI 镜像从 `...:api23` 改为 `...:api26`。

> ⚠️ 版本上限决策：华为官方《快速适配 HarmonyOS 7 (API 26) 全指南》建议
> `compatibleSdkVersion` **通常保持不变**（保留旧设备下限）。本次按用户明确要求
> 把 `compatibleSdkVersion` 也设为 `26.0.0`，因此安装下限变为 HarmonyOS 7。
> 如果要继续支持 API 23 设备，应把它改回 `6.1.0(23)`，并对 §4 的 API 26 属性做运行时版本判断。

---

## 2. 实施改动清单

### 2.1 配置与 CI

| 文件 | 改动 |
|---|---|
| `build-profile.json5.example` | `target/compatibleSdkVersion` → `26.0.0` |
| `.github/workflows/build.yml` | `CI_IMAGE` → `ghcr.io/dalongzhuazi/harmonyos-ci:api26`，更新注释 |
| `AGENTS.md` | 当前目标 API 示例改为 `26.0.0` |
| 本地 `build-profile.json5` | 仅本机（gitignore）：改 API 26，并临时复用本机签名配置；**未入库** |

### 2.2 废弃 API 修复

| 文件 | 改动 |
|---|---|
| `entry/src/main/ets/Framework/Components/BookSourceTabContent.ets` | 删除 `promptAction, curves` 全局导入；2 处 `promptAction.showToast` → `this.getUIContext().getPromptAction().showToast` |
| `entry/src/main/ets/pages/NovelExplorePage.ets` | 删除全局 `promptAction` 导入；2 处同上 |
| `entry/src/main/ets/pages/NovelSearchPage.ets` | 删除全局 `promptAction` 导入；1 处同上 |

> 全局 `promptAction.showToast/showDialog/showActionMenu` 自 API 18 起废弃；
> 本次全仓复核后已无直接全局调用（剩余 `promptAction.*` 仅为类型引用）。

### 2.3 新能力实现（只做低风险、明确有益）

1. **PDF Kit 深色渲染模式（API 26）**
   - 文件：`entry/src/main/ets/Framework/Components/PdfKitViewerComponent.ets`
   - 新增 `applyPdfRenderMode()`（:286），在 `loadDocument` 成功后（:703）、
     阅读设置应用后（:485）、夜间蒙层切换时（:278）调用。
   - 深色/夜间/深色背景时使用 `pdfViewManager.PresetRenderMode.DARKMODE`，否则 `DEFAULT`；
     `setRenderMode` 抛出的 1011302004/1011302005 已 `try/catch` 降级。
   - 收益：PDF 夜间阅读对比度更好；风险：仅影响 PDF 页面渲染，失败自动回退。

2. **中文标点悬挂（API 26 ArkUI Text）**
   - 文件：`entry/src/main/ets/components/TextReaderComponent.ets`
   - 14 处正文 `Text` 链新增 `.punctuationOverflow(true)`（翻页、双页、滚动、快照四条渲染路径）。
   - 收益：避免中文标点被挤到行首；标点悬挂只会减少换行、不会增加行数，
     对现有手工分页的“可能裁切”风险最低。
   - 未启用 `orphanCharOptimization`：它可能改变断行、影响手工分页，列入 §5 未实现清单。

3. **EPUB 内嵌视频全屏覆盖层（API 26 ArkWeb）**
   - 文件：`entry/src/main/ets/Framework/Components/EpubWebViewReaderComponent.ets:5538`
   - 新增 `.enableFullscreenVideoOverlay(true)`；仅影响视频全屏，不影响文字排版。

### 2.4 反馈中心入口（一级页面）

**改前路径（已移除）：**

```
主页面底部“管理/我的” → 关于应用（AboutPage） → “问题反馈”按钮
AboutPage.ets:690-697（旧）
```

**改后路径（一级页主入口）：**

```
主页面（MainMenuPage，任意一级标签页）
  → 右下角/搜索按钮旁的玻璃拟态悬浮按钮“反馈中心”
  → MangaFeedbackPage
```

实现位置：

| 位置 | 说明 |
|---|---|
| `MainMenuPage.ets:16048` | `buildFloatingFeedbackButton()`，SVG 图标 `app.media.ic_feedback`，复用搜索按钮的玻璃/阴影/按压样式 |
| `MainMenuPage.ets:35436` | `build()` 中挂载悬浮按钮，`zIndex: 20` |
| `MainMenuPage.ets:4646` | `getFloatingFeedbackButtonX()`：与搜索按钮同排，自动避让隐私按钮、书架“管理/添加”按钮 |
| `MainMenuPage.ets:4722` | `openFeedbackCenter()`：`pathStack.pushPath({ name: 'MangaFeedbackPage' })` |
| `MainMenuPage.ets:16081` | 稳定 `id('main_menu_feedback_entry')`，便于自动化测试 |
| `AboutPage.ets` | 删除旧“问题反馈”入口（严格“移动”语义） |

行为说明：

- 书库/历史/图源/书源/Suwayomi/Komga/管理任一标签页都能看到；
- 进入书架分类详情（`showCategoryDetail`）时隐藏，避免与详情页操作冲突；
- 平板侧栏模式下占用原搜索悬浮位；
- `MangaFeedbackPage`、`FeedbackCenterService`、`FeedbackCenterCacheManager`、
  `PageWindowRegistry` 均未修改，反馈功能本身保持不变。

---

## 3. 破坏性 / 废弃变更审计（API 23 → 26）

### 3.1 方法

对 SDK 26 的 `ets/api`、`ets/component`、`ets/build-tools` 与 HMS `ets/api`
扫描 `@deprecated since 24/25/26`，再与仓库源码交叉检索。

结果：

- OpenHarmony SDK 26：**38 条** since ≥24 的废弃项（27 条 since 26.0.0，11 条 since 24）。
- HMS SDK 26：**23 条**，全部 since 26.0.0，均与漫匣当前功能无关（活体检测、VoIP、PC 文件预加载等）。
- API 25：当前工具链没有独立 API 25 SDK/版本映射；版本路线是 `6.1.1(24)` → `26.0.0(26)`。

### 3.2 与漫匣相关的废弃项（已核对）

| 废弃项 | 仓库是否使用 | 处理 |
|---|---|---|
| `window.WindowProperties.type`（→ `windowType`） | 否（只读 `properties.id`） | 无需改 |
| `fs.TaskSignal.onCancel()` | 否（同名 `.onCancel()` 均为组件自定义方法） | 无需改 |
| `notificationManager.isDistributedEnabled` | 否 | 无需改 |
| `@ohos.settings.*`（飞行模式/悬浮窗/URI） | 否 | 无需改 |
| 全局 `AlertDialog` / `ActionSheet` 类 | 否（已用 `UIContext.showAlertDialog`） | 无需改 |
| `@ohos.print.*` | 否 | 无需改 |
| `ActionExtensionAbility` | 否 | 无需改 |
| `multimodalAwareness.userStatus` | 否 | 无需改 |
| `web.ConsoleMessageSource.Log` / `CrownAction.BEGIN` | 否 | 无需改 |
| 全局 `promptAction.showToast/showDialog/showActionMenu` | **是，5 处** | **已修复**（§2.2） |

### 3.3 非“废弃”但需要注意的行为变化

1. **`backgroundBlurStyle` 默认值变更（API 26）**
   - `ShowToastOptions` / `ShowDialogOptions` / `CustomDialogControllerOptions`
     的默认值由 `COMPONENT_ULTRA_THICK` 变为 `NONE`。
   - 项目内 Toast/Dialog 大多未显式设置该字段，升级后部分弹层可能“失去模糊”。
   - 本次未统一改动（涉及 40+ 调用点，且属于视觉层）；如需恢复旧观感，
     显式设置 `backgroundBlurStyle: BlurStyle.COMPONENT_ULTRA_THICK` 或改用 `systemMaterial`。
   - 归入 §7 遗留问题，建议真机视觉走查后统一处理。

2. **targetSdkVersion=26 的运行时行为切换**
   - 官方说明：按目标版本分流的接口会采用新逻辑；未分流的接口统一新规则。
   - 仓库使用 `taskpool`（`JsonSerializeUtils`、`LegadoRequestPipeline`、`SourceVerifier`、
     `NetworkScannerAdapter`），API 24 起 taskpool 超时可能抛错；本次编译通过，
     但未做运行时压测，列入 §7。

3. **ArkWeb 引擎升级 / 安全参数**
   - API 26 ArkWeb 增加 `SecurityParams`、AI Session、滚动方向锁等；引擎版本变化可能影响图源网页。
   - 本次未启用这些新参数，也未改图源引擎核心；图源回归需真机联网验证。

---

## 4. API 24 / 25 / 26 新能力调研清单

> 说明：当前工具链无 API 25 SDK；以下“24/26”即本机可验证的两个台阶。

### 4.1 已实现（明确有益 + 低风险）

| 能力 | 起始版本 | 实现位置 | 理由 |
|---|---|---|---|
| PDF `setRenderMode(DARKMODE)` | 26.0.0 | `PdfKitViewerComponent.ets` | 夜间 PDF 阅读直接受益；失败可回退 |
| `Text.punctuationOverflow` | 26.0.0 | `TextReaderComponent.ets`（14 处） | 中文标点排版；只减少换行，分页风险低 |
| `Web.enableFullscreenVideoOverlay` | 26.0.0 | `EpubWebViewReaderComponent.ets:5538` | EPUB 内嵌视频全屏不被容器裁剪 |

### 4.2 已评估但本次不实现（投机性或高风险）

| 能力 | 版本 | 不实现原因 |
|---|---|---|
| `UIMaterial` 应用级系统材质 / `systemMaterial` | 26 | 全局视觉改版，必须真机逐页走查；阅读器动态翻页场景有性能红线 |
| `ChipV2` / `ChipGroupV2` | 26 | 项目 Chip 为自绘玻璃拟态，替换会丢失边框/模糊/动画；收益有限 |
| `LazyColumnLayout` / `LazyVWaterFlowLayout` | 26 | 现有 `LazyForEach` + `BasicDataSource` 已成熟，迁移面大 |
| `TreeViewV2` / `SwipeRefresherV2` | 26 | 需 V2 状态管理改造，且自定义刷新动画受限，视觉回归风险高 |
| 状态管理 V2 深度迁移（`@ObservedV2/@Trace/@Monitor`） | 18+ | 长期战略；MainMenuPage/MangaViewer 体量巨大，不在本次范围 |
| `SelectionMenu.backgroundSystemMaterial` | 26 | 现有自建选择菜单稳定；WebView 也不支持 SelectionMenu |
| PDF `loadDocumentFromMemory` / `getPageIndexFromViewPoint` | 26 | 当前文件路径加载 + 分区点击已够用，收益有限 |
| `Text.orphanCharOptimization` | 26 | 会调整断行，可能影响手工分页；本次仅上标点悬挂 |
| ArkWeb `SecurityParams` / `AISession` | 26 | 会改变网页能力（禁用 JIT/WASM 等），可能破坏图源，属投机 |
| ArkWeb UA Client Hints / `saveImage` / 下载原始 URL | 24 | 图源引擎已有自己的下载/图片链路，未找到必须替换点 |
| `net.http.ConnectionExtraInfo` / `reuseConnections` | 24/26 | 可做诊断/性能，但无明确收益证据，先记录 |
| `window.releaseUIContent` | 24 | 阅读器 Ability 内存优化潜力大，但生命周期风险高 |
| `fs.listFileExt` / `mmap` | 26 | 可优化目录扫描/大文件读取，但当前导入链路无明确瓶颈 |
| `audio` 独立音频会话/静音提示 | 24 | 听书可受益，但需音频焦点回归，暂缓 |
| `ContainerReader`、V2 高级组件 | 26 | 与当前布局体系不匹配，投机 |
| 冷启网络预建链 / QUIC / LTPO 等系统能力 | 26 | 系统/平台级，应用侧无可控接入点 |

---

## 5. 构建验证

### 5.1 命令

```powershell
$env:DEVECO_SDK_HOME='G:\DevEco Studio 26\DevEco Studio\sdk'
$env:PATH='G:\DevEco Studio 26\DevEco Studio\tools\node;' + $env:PATH
$env:TEMP='F:\manxia-build\temp'; $env:TMP='F:\manxia-build\temp'

& 'G:\DevEco Studio 26\DevEco Studio\tools\hvigor\bin\hvigorw.bat' clean --no-daemon
& 'G:\DevEco Studio 26\DevEco Studio\tools\hvigor\bin\hvigorw.bat' assembleHap --no-daemon --stacktrace
```

### 5.2 结果

| 构建 | 结果 | 日志 |
|---|---|---|
| 清理后全量 signed 构建（F: 重定向） | **BUILD SUCCESSFUL in 3m40s**，105 tasks（95 executed） | `F:\manxia-build\logs\build_api26_final.log` |
| 提交后默认配置重建（无重定向） | **BUILD SUCCESSFUL in 3m40s**，115 tasks（115 executed） | `F:\manxia-build\logs\build_api26_committed_tree.log` |
| 剥离签名（CI 路径）unsigned 构建 | **BUILD SUCCESSFUL in 45s**，105 tasks（89 executed） | `F:\manxia-build\logs\build_api26_unsigned.log` |

产物元数据（`entry-default-signed.hap` / `module.json`）：

```json
{
  "bundleName": "com.dlzz.manxia",
  "versionName": "0.1.4",
  "versionCode": 105402300,
  "compileSdkVersion": "26.0.0.105",
  "compileSdkType": "HarmonyOS",
  "targetAPIVersion": 260000026,
  "minAPIVersion": 260000026,
  "apiReleaseType": "Release",
  "debug": true
}
```

`pack.info` 亦确认：`"apiVersion":{"compatible":26,"target":26}`。

> 本地 C: 盘在首次构建时仅剩约 58–276MB，因 `ENOSPC` 失败；当时通过**仅本机、未提交**的
> `hvigor/hvigor-config.json5` `properties.ohos.buildDir` 把产物重定向到
> `F:\manxia-build\api26\build`，并把 `TEMP/TMP` 指向 F: 盘。
> 提交前已还原该临时配置；随后用**默认配置重建提交后的树**也成功（115 tasks），
> 说明最终提交不依赖该重定向。复现时仍建议构建盘保留 ≥2GB 空间。

---

## 6. 真机 / 模拟器运行验证（受阻与替代证据）

### 6.1 设备状态

`hdc list targets`：

- `2UCUT24724009680`（ADA-AL00U，HarmonyOS `7.0.0.111(SP16C00E111R2P1)`，API 26）
- `192.168.5.133:42355`（MLR-AL10，HarmonyOS `7.0.0.111(SP18C00E111R1P2)`，API 26）

两台设备均为 API 26，满足目标版本；设备上已安装的旧漫匣为 API 23（`apiTargetVersion=60100023`）。

### 6.2 安装尝试与失败原因

| 签名方式 | 结果 |
|---|---|
| 主工程 release 签名（`manxiaRelease.p7b`） | `code:9568322 signature verification failed due to not trusted app source` |
| 旧 debug profile 签名（`manxiaDebug.p7b`） | `code:9568423 device is unauthorized, UDID not configured in the signing profile` |
| 当前自动签名 profile（`default_manxia...p7b`） | UDID 列表**包含**两台设备，但该 p12 的当前口令不可得；旧备份口令已失效（`11014003 Init keystore failed`）。为避免把签名口令写入 worktree，未继续尝试 |

- 本机存在 API 26 模拟器“Pura X Max”，但命令行启动需要先接受 2 份许可协议；
  未在未获授权的情况下自动接受。
- 因此**未完成**：安装、启动、反馈按钮点击、漫画/EPUB/文本阅读实机回归。

### 6.3 替代证据（已做）

1. **编译证据**：两次完整构建通过（signed + unsigned），ArkTS 编译无 error。
2. **产物证据**：HAP `module.json` / `pack.info` 确认 `target/min API = 26`、
   `compileSdkVersion=26.0.0.105`、签名产物存在。
3. **字节码证据**：`modules.abc` 中可检索到本次新增字符串：
   - `反馈中心`（7 次）
   - `PDF 渲染模式已切换`（1 次）
   - `书源结果已过期`（1 次）
   说明新代码已进入最终产物，而非仅改源码。
4. **静态路径核对**：反馈按钮 → `openFeedbackCenter()` → `pathStack.pushPath('MangaFeedbackPage')`；
   `MangaFeedbackPage` 的 NavDestination 注册（`MainMenuPage.ets` 末尾）与
   `PageWindowRegistry` 均未改动。
5. **废弃 API 复核**：全仓已无全局 `promptAction.showToast/showDialog/showActionMenu` 直接调用。

**缺什么**：真实 UI 布局（尤其平板顶栏模式悬浮按钮是否遮挡标签）、
标点悬挂后的分页观感、PDF 深色渲染效果、漫画/EPUB/文本阅读端到端回归。

---

## 7. 遗留问题与建议

1. **P0 — 真机安装签名**：需要把两台设备 UDID 加入可用的 debug profile，且拿到当前
   `default_manxia...p12` 的口令（或让 DevEco 重新自动签名）；之后安装 `entry-default-signed.hap`
   做 §6.3 列出的端到端回归。
2. **P1 — 视觉默认值**：API 26 的 Toast/Dialog 模糊默认值变化；建议真机走查后统一
   显式设置 `backgroundBlurStyle` 或迁移到 `systemMaterial`。
3. **P1 — 平板顶栏布局**：反馈悬浮按钮在 `top/bottom` 顶栏模式下与搜索按钮同排，
   可能覆盖标签按钮；建议真机确认，必要时改为顶栏内的固定反馈图标。
4. **P1 — 分页观感**：`punctuationOverflow` 对手工分页的影响需真机看首/尾页；
   若出现裁切，可只在滚动模式启用。
5. **P2 — compatibleSdkVersion**：当前为 26，安装下限为 HarmonyOS 7；若需兼容 API 23，
   改回 `6.1.0(23)` 并对 §4 的 API 26 属性做运行时判断。
6. **P2 — CI 镜像**：已改为 `:api26`，但本次未实际触发云端 CI；本地 unsigned 构建已通过，
   建议推送分支后观察一次 workflow。
7. **P2 — taskpool/ArkWeb 行为**：target 26 下的 taskpool 超时、ArkWeb 引擎/安全默认值
   未做运行时压测；图源阅读需联网回归。

---

## 8. 与 main 工作树未提交改动的关系

- 本 worktree 基于 main 提交 `08ef5b26`，**不包含** main 工作树当前未提交改动；
  未复制任何 main 源码改动。
- 仅读取了 main 工作树的本机 `build-profile.json5`（gitignore）用于本机构建/签名；
  未复制其源码改动，也未把签名口令写入分支文件。
- main 工作树未提交改动中，与本次修改**同文件、可能冲突**的有：
  - `entry/src/main/ets/Framework/Components/EpubWebViewReaderComponent.ets`（main +204 行）
  - `entry/src/main/ets/components/TextReaderComponent.ets`（main +244 行）
- 其余 main 未提交文件（`AppScope/app.json5`、EPUB 设置面板、`MangaReaderPage.ets`、
  changelog、`SettingKeys.ets`、`tools/legado-compat/*` 删除等）本次未触碰。
- 合并 main 时请优先保留 main 的阅读器改动，再把本报告的 14 处 `.punctuationOverflow(true)`
  和 1 处 `.enableFullscreenVideoOverlay(true)` 重新插入；不要整文件覆盖。

---

## 9. 提交与复现

- 分支：`manxia-api26-upgrade`；本报告与代码改动在同一分支提交。
- 未执行：`git merge main`、`git push`、归档、修改 main 工作树。
- 复现构建：
  1. 确保 `G:\DevEco Studio 26\DevEco Studio` 与 SDK 26 可用；
  2. 由 `build-profile.json5.example` 生成本地 `build-profile.json5`，配置本机签名；
  3. 设置 `DEVECO_SDK_HOME`，在仓库根目录执行 `hvigorw assembleHap --no-daemon`；
  4. 如 C: 空间不足，参考 §5.2 的 `ohos.buildDir`/TEMP 重定向（仅本机，不要提交）。

---

## 10. 参考

- 华为开发者论坛《快速适配 HarmonyOS 7 (API 26) 全指南》：
  https://developer.huawei.com/consumer/cn/forum/topic/0208227805407896221
- 仓库既有分析：`docs/API26_升级分析报告.md`（系统材质、Dialog、V2 组件、PDF 等）
- SDK 26 本机声明：`G:\DevEco Studio 26\DevEco Studio\sdk\default\openharmony\ets\api`
- 构建日志：`F:\manxia-build\logs\build_api26_final.log`、`build_api26_unsigned.log`
