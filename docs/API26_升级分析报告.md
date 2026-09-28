# API 26 升级分析报告（基于 API 23 现状）

> 生成时间：2026-08-03
> 当前版本：`targetSdkVersion / compatibleSdkVersion = 6.1.0(23)`（API 23）
> 目标版本：API 26（HarmonyOS NEXT 6.x 后续版本）
> 信息来源：华为开发者文档中心 20 个官方页面（doccenter-capabilities，含相关锚点章节），原始抓取存于 `tmp/api26-docs/`
> 对比对象：`entry/src/main/ets` 全工程（已排除所有 `*.bak` 备份文件）

---

## 0. 结论速览

| 主题 | API 26 主要变化 | 项目影响 | 优先级 |
|---|---|---|---|
| promptAction（Toast/Dialog/菜单） | 新增 `systemMaterial`；`backgroundBlurStyle` 默认值变更 | 低风险，1 处废弃调用待修 | ⭐ 低 |
| CustomDialogController | 新增 `systemMaterial`、`displayModeInSubWindow`；`backgroundBlurStyle` 默认值变更 | 视觉回归需审计 | ⭐⭐ 中 |
| bindSheet / bindPopup / tips | 新增 `systemMaterial`（sheet/tips）；`AnchoredColorMode`；PopupV2 新组件 | 无破坏性变更，可选增强 | ⭐ 低 |
| ChipV2 / ChipGroupV2 | 全新组件（全部 API 26 起始） | 可替换部分自绘 Chip | ⭐⭐ 中 |
| SelectionMenu / SwipeRefresherV2 / TreeViewV2 | 全新组件（SwipeRefresherV2/TreeViewV2 全 26 起始） | 可选增量能力 | ⭐ 低 |
| 状态管理 V2 | @ComponentV2/@ObservedV2/@Trace/@Monitor 等深度观察体系 | 已有少量 V2，建议按需扩展 | ⭐⭐⭐ 高（长期） |
| 懒加载布局 | LazyColumnLayout/LazyVWaterFlowLayout（26 起始）、header/sticky | 现有 LazyForEach 成熟，可选试点 | ⭐⭐ 中 |
| 沉浸式 / 系统材质 | UIMaterial 应用级开关、ImmersiveMaterial | 收益最直接，首批改造对象 | ⭐⭐⭐ 高 |
| PDF（PDFViewManager） | `setRenderMode`、`loadDocumentFromMemory`、`getPageIndexFromViewPoint` | 深色阅读优化可直接受益 | ⭐⭐ 中 |
| 快速调度 / 手写笔 | perfHint、StylusFrameBoost | 锦上添花，按需接入 | ⭐ 低 |

---

## 1. 横切变更：系统材质（systemMaterial）与模糊默认值

这是本次升级**影响面最大**的一类变更，多个 API 同时涉及，先统一说明。

> **📎 相关官网文档**：[⑨ js-apis-promptaction#showtoastoptions](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/js-apis-promptaction#showtoastoptions) ｜ [⑩ #showdialogoptions](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/js-apis-promptaction#showdialogoptions) ｜ [⑪ #actionmenuoptions](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/js-apis-promptaction#actionmenuoptions) ｜ [⑫ ts-methods-custom-dialog-box](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ts-methods-custom-dialog-box#customdialogcontrolleroptions对象说明) ｜ [⑬ sheet-transition#示例10](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ts-universal-attributes-sheet-transition#示例10半模态设置系统材质) ｜ [⑭ popup#popupoptions](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ts-universal-attributes-popup#popupoptions类型说明) ｜ [⑧ tips#示例3](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ts-universal-attributes-tips#示例3设置悬浮气泡的系统材质视效) ｜ [① selectionmenu](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ohos-arkui-advanced-selectionmenu#导入模块)
> **📄 原始抓取文件**：[09_promptaction.md](../tmp/api26-docs/09_promptaction.md) ｜ [12_custom_dialog.md](../tmp/api26-docs/12_custom_dialog.md) ｜ [13_sheet.md](../tmp/api26-docs/13_sheet.md) ｜ [14_popup.md](../tmp/api26-docs/14_popup.md) ｜ [08_tips.md](../tmp/api26-docs/08_tips.md) ｜ [01_selectionmenu.md](../tmp/api26-docs/01_selectionmenu.md)

### 1.1 `backgroundBlurStyle` 默认值变更（行为变化，必须注意）

从 **API 26.0.0** 起，以下接口的 `backgroundBlurStyle` 默认值由 `BlurStyle.COMPONENT_ULTRA_THICK` **改为 `BlurStyle.NONE`**：

- `ShowToastOptions.backgroundBlurStyle`
- `ShowDialogOptions.backgroundBlurStyle`
- `CustomDialogControllerOptions.backgroundBlurStyle`

**含义**：升级后凡未显式设置 `backgroundBlurStyle` 的 Toast / 系统对话框 / 自定义对话框，背板默认不再有系统模糊，观感会变化。

**对策**：升级后统一审计；需要保持旧观感时显式设置 `backgroundBlurStyle: BlurStyle.COMPONENT_ULTRA_THICK`，或改用 1.2 的 `systemMaterial`。

### 1.2 `systemMaterial: SystemUiMaterial`（API 26 新增，多接口统一引入）

以下接口均新增 `systemMaterial` 字段（起始版本 26.0.0），用于设置弹窗/浮层的系统材质（背景色、模糊、阴影、材质效果一体化）：

| 接口 | 新增字段 |
|---|---|
| `promptAction.ShowToastOptions` | `systemMaterial` |
| `promptAction.ShowDialogOptions` | `systemMaterial` |
| `promptAction.ActionMenuOptions` | `systemMaterial` |
| `CustomDialogControllerOptions` | `systemMaterial`（默认 `ImmersiveMaterial({style: ULTRA_THICK})`） |
| `SheetOptions`（bindSheet） | `systemMaterial` |
| `TipsOptions`（bindTips） | `systemMaterial` |
| `SelectionMenuOptions` | `backgroundSystemMaterial` |

**用法要点**：
- 通过 `new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THIN/REGULAR/THICK/ULTRA_THICK })` 创建。
- 设置 `systemMaterial` 后，`backgroundColor` / `backgroundBlurStyle` / `backgroundEffect` / `shadow`（部分接口含 `borderColor/borderWidth`）**均不再生效**，需将背景显式设为透明、避免重复叠加。
- 典型示例：

```ts
import { uiMaterial } from '@kit.ArkUI';

@State myMaterial: SystemUiMaterial | undefined =
  new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THICK });

// bindSheet 半模态设置系统材质（对应官方示例 10）
.bindSheet($$this.isShow, this.myBuilder(), {
  height: 300,
  backgroundColor: Color.Transparent,
  systemMaterial: this.myMaterial
})

// bindTips 悬浮气泡系统材质（对应官方示例 3）
.bindTips('悬浮气泡测试', {
  systemMaterial: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.THIN })
})
```

### 1.3 应用级系统材质开关（UIMaterial）

- `module.json5` 可配置 `ohos.arkui.UIMaterial.state = enable`（应用级开关，需 `targetAPIVersion >= 26`），开启后 Dialog/Toast/Chip/Menu/Select 等**系统组件零代码**获得沉浸材质质感。
- 需先用 `uiMaterial.getMaterialInfo()` 判断设备/版本能力，并给用户提供开关。
- **性能红线**：勿整页铺材质、勿嵌套层叠、勿在列表逐项设置、勿在阅读器动态翻页内容上叠加材质（本项目是漫画/阅读 App，翻页/视频类场景尤其要小心，材质区域必须稳定）。

---

## 2. promptAction（Toast / 系统对话框 / ActionMenu）

来源：⑨ ⑩ ⑪（同一页面 `js-apis-promptaction` 的三个锚点）。

> **📎 官网文档**：[⑨ showToastOptions](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/js-apis-promptaction#showtoastoptions) ｜ [⑩ showDialogOptions](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/js-apis-promptaction#showdialogoptions) ｜ [⑪ ActionMenuOptions](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/js-apis-promptaction#actionmenuoptions)
> **📄 原始抓取文件**：[09_promptaction.md](../tmp/api26-docs/09_promptaction.md)

### 2.1 API 26 相关要点

- **API 26 新增**：`ShowToastOptions.systemMaterial`、`ShowDialogOptions.systemMaterial`、`ActionMenuOptions.systemMaterial`（见 §1.2）。
- **API 26 默认值变更**：`backgroundBlurStyle` 默认改为 `NONE`（见 §1.1）。
- **API 18+ 已有但项目未用**：`openToast`/`closeToast`（返回 toastId，可主动关闭）、`DialogController`/`CommonController`/`LevelOrder`、`CommonState`（20+）。
- **废弃接口**：全局 `promptAction.showToast/showDialog/showActionMenu/openCustomDialog/closeCustomDialog` 自 API 18 起废弃，官方统一建议改 `uiContext.getPromptAction().xxx()`。

### 2.2 项目现状

- 全工程约 40+ 个文件使用 promptAction，**绝大多数已采用推荐的 `this.getUIContext().getPromptAction().xxx()`**（如 `EpubWebViewReaderComponent.ets:4652`、`TextReaderComponent.ets:7041`、`AnnotationCenterPage.ets`、`MainMenuKomgaTabContent.ets:448`、`NovelReaderPage.ets:3980` 等）。
- **唯一一处废弃直接调用**：`Framework/Components/BookSourceTabContent.ets:877` → `promptAction.showToast({ message: '漫画书源桥接失败，请稍后重试' })`。
- 项目使用了 `showToast`、`showDialog`、`showActionMenu`（含 6 元组 buttons 构造），未使用 `openToast`/`closeToast` 及 DialogController 系列。

### 2.3 升级影响与建议

1. **基本无破坏性变更**：UIContext 版接口在 API 26 原样可用。
2. **必修**：将 `BookSourceTabContent.ets:877` 改为 `this.getUIContext().getPromptAction().showToast(...)`。
3. **关注视觉**：Toast/Dialog 若未显式设置 `backgroundBlurStyle`，升级后模糊消失——按 §1.1 处理。
4. **可选增强**：`systemMaterial` 统一材质观感；`openToast`/`closeToast` 提供可关闭 Toast；`ShowDialogOptions`/`ActionMenuOptions` 生命周期回调（19+/20+）做埋点；`levelMode`/`levelOrder` 控制弹窗层级顺序。

---

## 3. CustomDialogController（自定义对话框）

来源：⑫ `ts-methods-custom-dialog-box`（CustomDialogControllerOptions 对象说明）。

> **📎 官网文档**：[⑫ CustomDialogControllerOptions 对象说明](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ts-methods-custom-dialog-box#customdialogcontrolleroptions对象说明)
> **📄 原始抓取文件**：[12_custom_dialog.md](../tmp/api26-docs/12_custom_dialog.md)

### 3.1 API 26 相关要点

- **API 26 新增字段**：
  - `displayModeInSubWindow: DialogDisplayMode`（默认 `SCREEN_BASED`，仅 `showInSubWindow=true` 生效）；
  - `systemMaterial: SystemUiMaterial`（默认 `ImmersiveMaterial({style: ULTRA_THICK})`，设置后 backgroundColor/backgroundBlurStyle/backgroundEffect/borderColor/borderWidth/shadow 均失效）。
- **API 26 默认值变更**：`backgroundBlurStyle` 默认改为 `NONE`（见 §1.1）。
- 其他注意：弹窗动效仅通过 `openAnimation`/`closeAnimation` 控制（**没有 transition 字段**）；`showInSubWindow=true` 的弹窗不能再弹同模式弹窗；controller 需作为 `@Component` 成员变量赋值，`aboutToDisappear` 时置空。

### 3.2 项目现状

- 全工程 20+ 个文件使用 `CustomDialogController`（不含 .bak），代表性构造点：
  - `Framework/Components/UniversalDialog.ets:202`（通用弹窗管理器，`customStyle:true, autoCancel:false`）
  - `Framework/Components/ArchivePasswordDialog.ets:157`
  - `pages/DataManagementPage.ets:1686`（6 个 controller）
  - `pages/DownloadSyncPage.ets:2841`（6 个）
  - `pages/EBookDetailPage.ets:534`
  - 以及 `MangaImportDialog`/`NovelImportDialog`/`PdfImportDialog` 等大量导入类对话框
- 常用字段仅 `builder/customStyle/autoCancel/alignment`，未显式设置 `backgroundBlurStyle`、`systemMaterial`、`displayModeInSubWindow`。

### 3.3 升级影响与建议

1. **视觉回归审计**：所有 `customStyle:false` 且未设置模糊的弹窗，升级后背板模糊消失。逐一审计或统一设置。
2. **可选简化**：用 `systemMaterial` 统一替换背板系列配置（需保持现视觉时显式设置）。
3. `displayModeInSubWindow` 目前无关（项目未见 `showInSubWindow:true`）。

```ts
// API 26 推荐写法：系统材质弹窗
dialogController = new CustomDialogController({
  builder: CustomDialogExample(),
  systemMaterial: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THICK })
});
// 若需保持 API 26 前的模糊背板：
// backgroundBlurStyle: BlurStyle.COMPONENT_ULTRA_THICK
```

---

## 4. bindSheet / bindPopup / tips（半模态、气泡、悬浮提示）

来源：⑬ sheet-transition（示例 10 半模态系统材质）、⑭ popup（PopupOptions 类型说明）、⑧ tips（示例 3 悬浮气泡系统材质）、⑱ PopupV2。

> **📎 官网文档**：[⑬ sheet-transition#示例10 半模态设置系统材质](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ts-universal-attributes-sheet-transition#示例10半模态设置系统材质) ｜ [⑭ popup#PopupOptions 类型说明](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ts-universal-attributes-popup#popupoptions类型说明) ｜ [⑧ tips#示例3 悬浮气泡系统材质视效](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ts-universal-attributes-tips#示例3设置悬浮气泡的系统材质视效) ｜ [⑱ PopupV2](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ohos-arkui-advanced-popupv2)
> **📄 原始抓取文件**：[13_sheet.md](../tmp/api26-docs/13_sheet.md) ｜ [14_popup.md](../tmp/api26-docs/14_popup.md) ｜ [08_tips.md](../tmp/api26-docs/08_tips.md) ｜ [18_popupv2.md](../tmp/api26-docs/18_popupv2.md)

### 4.1 API 26 相关要点

**bindSheet（SheetOptions）**：
- **API 26 新增 `systemMaterial: SystemUiMaterial`**（示例 10：`ImmersiveMaterial({style: ULTRA_THICK})`；与 borderWidth/borderColor/backgroundColor/shadow 冲突，需背景透明）。
- 其他字段：`height`（默认 LARGE）、`detents`(11+)、`preferType`(11+)、`showClose`、`dragBar`、`blurStyle`(11+)、`maskColor`、`enableOutsideInteractive`(11+)、`title`(11+)、`shouldDismiss`(11+)/`onWillDismiss`(12+)、`radius`(15+)、`onWillAppear` 等生命周期回调。

**bindPopup（PopupOptions）**：
- **API 26 新增枚举 `AnchoredColorMode`**（FOLLOW_SYSTEM / FOLLOW_TARGET）。
- 字段：`message`（必填）、`primaryButton/secondaryButton`、`onStateChange`、`showInSubWindow`(9+)、`mask`(10+)、`messageOptions`(10+)、`targetSpace`(10+ 默认 8vp)、`placement`(10+ 默认 Bottom)、`offset`(10+)、`enableArrow`(10+)、箭头系列(9+/11+)、`popupColor`(11+)、`autoCancel`(11+)、`width/radius`(11+)、`backgroundBlurStyle`、`shadow`、`transition`、`onWillDismiss`、`followTransformOfTarget`、`keyboardAvoidMode`(15+)。

**tips（bindTips，API 19 起）**：
- `bindTips(message: TipsMessageType, options?)`，依赖悬浮事件，预览器不支持。
- **API 26 新增 `systemMaterial`**（示例 3，设置后 backgroundColor/borderColor/borderWidth/shadow 失效）。
- TipsOptions：appearingTime/disappearingTime（默认 700/300ms）、enableArrow、箭头系列、`showAtAnchor`(20+)。

**PopupV2（全新组件，起始版本 26.0.0）**：
- 基于状态管理 V2 的 @Builder 高级组件。导入 `import { PopupV2, PopupV2Button, PopupV2InitInfo } from '@kit.ArkUI'`。
- `PopupV2InitInfo`：icon/title/message（必填）、titleModifier/iconModifier/messageModifier、showClose/onClose、buttons（最多 2 个 `PopupV2Button{text, action}`）、direction、maxWidth（默认 400vp）。

```ts
// PopupV2 用法（API 26，需 @ComponentV2）
import { PopupV2, PopupV2Button, ImageModifier, TextModifier } from '@kit.ArkUI';

PopupV2({
  icon: $r('app.media.startIcon'),
  iconModifier: new ImageModifier().width(32).height(32).fillColor(Color.White),
  title: '提示',
  titleModifier: new TextModifier().fontSize(20),
  message: '内容',
  messageModifier: new TextModifier().fontSize(15),
  showClose: true,
  onClose: () => {},
  buttons: [{ text: '确定', action: () => {} }] as [PopupV2Button | undefined, PopupV2Button | undefined]
})
```

### 4.2 项目现状

- **bindSheet 1 处**：`BookSourceTabContent.ets:1855`（书源筛选，`height: MEDIUM, showClose: false, dragBar: true`）。
- **bindPopup 约 24 处**：`ContentPanel.ets:869`（字体气泡）、`EBookReadingSettingsPanel.ets:681`（主题提示）、`MainMenuPage.ets` 23 处。均为 `CustomPopupOptions`（builder+placement+popupColor/enableArrow+onStateChange），未用 mask/targetSpace/offset/transition 等。
- **bindContentCover 1 处**：`SourceDetailPage.ets:4884`。
- **tips/bindTips、PopupV2、uiMaterial/systemMaterial：均未使用**（仅 `HdsStyleBottomBar.ets:338` 用组件属性 `systemMaterialEffect`，非同一 API）。

### 4.3 升级影响与建议

- 现有 bindSheet/bindPopup/bindContentCover 调用在 API 26 可继续编译，**无破坏性变更**。
- bindSheet 可用 `systemMaterial` 替换 `blurStyle + backgroundColor` 组合。
- bindPopup 暂未用到 API 26 新字段，可保持。
- PopupV2 为全新能力，需配合状态管理 V2，可按需引入。

---

## 5. ChipV2 / ChipGroupV2（全新组件）

来源：⑮ ChipV2、⑯ ChipGroupV2。

> **📎 官网文档**：[⑮ ChipV2](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ohos-arkui-advanced-chipv2#示例) ｜ [⑯ ChipGroupV2](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ohos-arkui-advanced-chipgroupv2)
> **📄 原始抓取文件**：[15_chipv2.md](../tmp/api26-docs/15_chipv2.md) ｜ [16_chipgroupv2.md](../tmp/api26-docs/16_chipgroupv2.md)

### 5.1 文档要点（全部接口起始版本 26.0.0）

**ChipV2**：
- 导入 `import { ChipV2, ChipV2Options, ChipV2Size } from '@kit.ArkUI'`；基于状态管理 V2（@ComponentV2/@ObservedV2）；仅 Stage 模型；**Wearable 不支持**。
- 构造：`ChipV2({ chipV2Options: ChipV2Options })`。
- `ChipV2Options`：label（必填）、prefixIcon、suffixIcon、allowClose（默认 true）、closeIcon、enabled、activated、backgroundColor、activatedBackgroundColor、borderRadius、size（NORMAL/SMALL）、direction、padding、fontSize、maxFontScale/minFontScale、accessibility 系列、backgroundSystemMaterial/activatedBackgroundSystemMaterial、onClose、onClicked。
- **无 `selectedStyle` 字段**，选中态由 `activated` 系列（activatedBackgroundColor/activatedFontColor）承担。
- `ChipV2Label`：text、fontSize、fontColor、activatedFontColor、fontFamily、labelMargin/localizedLabelMargin、modifier。
- 图标分 Symbol（SymbolGlyphModifier）与 Image（仅 SVG 生效）两类；suffix 图标支持 action 点击，传入 suffixIcon 时 allowClose 失效。

**ChipGroupV2**：
- 构造：`ChipGroupV2({ items, $items?, itemStyle?, selectedIndexes?, $selectedIndexes?, multiple?, chipGroupSpace?, chipGroupPadding?, onChange?, suffix? })`。
- `items` 必填（为空不渲染）；`itemStyle` 含 size/backgroundColor/fontColor/**selectedFontColor/selectedBackgroundColor**/材质；`multiple` 单选/多选（默认 false）；`onChange` 返回选中索引数组；`suffix` 用 ChipGroupV2IconGroupSuffix 定制尾部。

### 5.2 项目现状

项目**未使用原生 Chip/ChipGroup**，全部为自绘 @Builder（主题色经 ThemeAwareHelper 动态取色）：

| 位置 | 自绘 Chip |
|---|---|
| `BookSourceTabContent.ets:1174/:1206` | `buildBookSourceTypeFilterChip` / `buildBookSourceGroupFilterChip`（Text+背景模糊+边框+圆角） |
| `EBookDownloadComponents.ets:393` | `buildFormatChip`（Column 双行文本，网格 Flex wrap） |
| `ImportFilenameSuggestionPanel.ets:185` | `buildMetaChip`（纯文本标签） |
| `NovelImportDialog.ets:2332` | `buildEncodingChip` |
| `ReadAloudCacheDialogComponent.ets:2995` | `buildReadAloudCacheChoiceChip`（Button+scale/animation） |
| `MainMenuKomgaTabContent.ets:910` | `buildChip`（大面积筛选标签） |
| `SuwayomiMangaDetailPage.ets:632`、`GlobalSearchPage.ets` 等 | `buildMetaChip`/`buildContentTypeChip` 系列 |

### 5.3 升级影响与替换建议

- **前置条件**：ChipV2/ChipGroupV2 全部为 API 26 起始接口，需先升级 `compileSdkVersion=26` 才能编译。
- **可替换场景**：单选/多选筛选类（BookSourceTabContent、MainMenuKomgaTabContent、ReadAloudCacheDialog）天然匹配 `ChipGroupV2`（multiple、selectedIndexes、onChange、suffix），可省去自绘状态管理。
- **样式差异风险**：ChipV2 不支持 `borderWidth`/自定义边框颜色、`backgroundBlurStyle`、背景特效、scale 动画等自绘特性；双行 chip（EBookDownloadComponents）或带动画 chip（ReadAloudCacheDialog）**建议保留自绘**。
- **可迁移项**：纯文本小标签（buildMetaChip 系列）可用 ChipV2 简化，收益有限。
- 对象内部属性变化需 `UIUtils.makeObserved` 包裹才能被 @Param 深度观测。

---

## 6. SelectionMenu / SwipeRefresherV2 / TreeViewV2（新组件）

来源：① SelectionMenu、⑲ SwipeRefresherV2、⑳ TreeViewV2。

> **📎 官网文档**：[① SelectionMenu](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ohos-arkui-advanced-selectionmenu#导入模块) ｜ [⑲ SwipeRefresherV2](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ohos-arkui-advanced-swiperefresherv2) ｜ [⑳ TreeViewV2](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ohos-arkui-advanced-treeviewv2#示例)
> **📄 原始抓取文件**：[01_selectionmenu.md](../tmp/api26-docs/01_selectionmenu.md) ｜ [19_swiperefresherv2.md](../tmp/api26-docs/19_swiperefresherv2.md) ｜ [20_treeviewv2.md](../tmp/api26-docs/20_treeviewv2.md)

### 6.1 SelectionMenu（文本选择菜单，API 11 起）

- 导入 `import { SelectionMenu, EditorMenuOptions, ExpandedMenuOptions, EditorEventInfo, SelectionMenuOptions } from '@kit.ArkUI'`。
- `SelectionMenu(options)` 为 @Builder 组件，**仅配合 RichEditor/Text 的 `bindSelectionMenu` 使用**，不能单独作组件；建议鼠标右键/选中方式弹出。
- Options：`editorMenuOptions`（编辑菜单：icon/symbolStyle(18+)/builder/action）、`expandedMenuOptions`（扩展下拉，继承 MenuItemOptions）、`controller`（RichEditorController，非空时显示系统默认菜单）、`onCopy/onPaste/onCut/onSelectAll`、**`backgroundSystemMaterial`（起始版本 26.0.0，本组件唯一 26 新增项）**。

```ts
// 示例（API 26）：绑定 RichEditor 文本选择菜单并设置系统材质
Text(this.content)
  .bindSelectionMenu(TextSpanType.TEXT, this.MyMenu(), TextResponseType.RIGHT_CLICK, {
    backgroundSystemMaterial: new uiMaterial.ImmersiveMaterial({ style: uiMaterial.ImmersiveStyle.ULTRA_THIN })
  })

@Builder
MyMenu() {
  SelectionMenu({
    editorMenuOptions: [
      { icon: $r('sys.symbol.copy'), action: () => this.onCopy() },
    ],
    expandedMenuOptions: [
      { value: '全选', action: () => this.onSelectAll() }
    ]
  })
}
```

### 6.2 SwipeRefresherV2（下拉刷新，全部接口起始版本 26.0.0）

- 基于状态管理 V2（@ComponentV2）；导入 `import { SwipeRefresherV2 } from '@kit.ArkUI'`。
- 构造：`SwipeRefresherV2({ content?: string, isLoading: boolean })`。
- **无子组件、不支持通用属性/通用事件**；Wearable 不支持；仅 Stage 模型。

### 6.3 TreeViewV2（树形组件，全部接口起始版本 26.0.0）

- @ComponentV2；导入 `import { TreeViewV2 } from '@kit.ArkUI'`；构造 `TreeViewV2({ treeControllerV2: TreeControllerV2 })`。
- TreeControllerV2：`addNode/removeNode/modifyNode/buildDone/refreshNode`；`NodeParamV2`：parentNodeId/currentNodeId/isFolder/icon/symbolIconStyle/selectedIcon/editIcon/primaryTitle/secondaryTitle/container。
- `TreeListenerManagerV2`（单例）提供 onNodeClick/onNodeAdd/onNodeDelete/onNodeModify/onNodeMove 及 off 系列。

### 6.4 项目现状

1. **bindSelectionMenu（均为自建 @Builder 菜单，未用 SelectionMenu）**：`EpubWebViewReaderComponent.ets:5549`（WebElementType.TEXT，LONG_PRESS）、`TextReaderComponent.ets:3883-3983`（TextSpanType.TEXT 6 处）、`UnifiedDetailPage.ets:8239/:11042`。
2. **下拉刷新**：未使用 SwipeRefresher/SwipeRefresherV2，全部为旧版 `Refresh` 基础组件：`MainMenuPage.ets:30954/32982/33018/33055`、`SourceTabContent.ets:272`、`KomgaBrowsePage.ets:1361`、`KomgaLibraryDetailPage.ets:1012`、`MainMenuKomgaTabContent.ets:1138`、`SuwayomiTabContent.ets:998`。
3. **树形**：未用系统 TreeView/TreeViewV2；`DownloadSyncPage.ets:117/495/1293/1767` 用自定义 FlatTreeItem + ForEach 实现扁平树目录选择。

### 6.5 升级影响与建议

1. **SelectionMenu**：项目三处自建选择菜单升级后不受影响。注意 **WebView（EpubWebViewReaderComponent）无法使用 SelectionMenu**（仅支持 RichEditor/Text），该处必须保留自建菜单；Text 相关（TextReaderComponent/UnifiedDetailPage）迁移工作量中等、非必须。
2. **SwipeRefresherV2**：全新组件，需页面迁移至 V2（@ComponentV2/@Local），且无 builder 自定义刷新动画（旧 Refresh 有），视觉回归风险高，**建议维持现状**。
3. **TreeViewV2**：替换需 V2 化且自定义样式受限，**建议暂不替换**。

---

## 7. 状态管理 V2（长期战略主题）

来源：⑰ 状态管理概述（状态管理 V2 章节）。

> **📎 官网文档**：[⑰ 状态管理概述#状态管理V2](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-state-management-overview#状态管理v2)
> **📄 原始抓取文件**：[17_state_mgmt.md](../tmp/api26-docs/17_state_mgmt.md)

### 7.1 V1 / V2 对比（核心差异）

| V1 | V2 | 关键差异 |
|---|---|---|
| @Component | @ComponentV2 | V2 组件内才能用 @Local/@Param/@Event/@Once/@Monitor/@Provider/@Consumer |
| @State | @Local；@Param+@Once | @State 可外部初始化；@Local 只能组件内部初始化 |
| @Prop | @Param | **复杂类型 @Prop 深拷贝，@Param 是引用（非深拷贝）**；@Once 仅同步一次 |
| @Link | @Param+@Event | V2 由开发者用回调实现双向同步 |
| @ObjectLink | @Param | @Param 不要求 @Observed class |
| @Provide/@Consume | @Provider/@Consumer | 跨组件层级双向同步 |
| @Observed | @ObservedV2 | @Observed 只观察第一层且需配 @ObjectLink；@ObservedV2 本身无观察力，需配 @Trace 深度观察 |
| @Track | @Trace | 精确跟踪类属性 |
| @Watch | @Monitor | 深度监听，一次事件多次变化仅按最终结果触发 |
| @Reusable | @ReusableV2 | 组件复用 |
| AppStorage/$$ | AppStorageV2 / !! | 双向绑定建议用 !! |
| animateTo | **部分场景不支持** | V2 中 animateTo 动画可能异常，需验证 |
| — | @Computed | 计算属性只算一次，避免 UI 重复计算 |

其他要点：状态管理仅限 UI 主线程；V1/V2 可混用（V2 组件内勿用 V1 装饰器）；V1 够用则不必强迁；API 18 起系统预置组件支持 V2（如 DialogV2）。

### 7.2 项目现状

- **主体仍为 V1**：约百个页面/组件使用 @Component/@State/@Prop/@Link/@Provide/@Consume/@StorageLink（如 `MangaViewer.ets` @Prop 二十余个、`MainMenuPage.ets` 大量 @State、`EntryAbility.ets` AppStorage.setOrCreate 数十处）。
- **V2 仅 7 个文件**，且只用浅层 `@ComponentV2 + @Param + @Local`（回调/配置型弹窗与编辑器页）：`components/CacheManagementPanel.ets:34`、`pages/FileEditorPage.ets:93`（50+ @Local）、`pages/BackupPage.ets:99`、`components/backup/WebDAVConfigDialog.ets:22`、`RestoreOptionsDialog.ets:32`、`BackupOptionsDialog.ets:12`、`components/source/ProxyConfigDialog.ets:43`。
- **V2 高级能力全库 0 使用**：@ObservedV2 / @Trace / @Monitor / @Computed / @Provider / @Consumer / AppStorageV2 / @ReusableV2 / PersistenceV2 / @Event / @Once。

### 7.3 升级影响与建议

1. **保持现有 V2 使用模式**（@ComponentV2 + @Param @Require + @Local 用于弹窗/面板），新功能/新组件继续用 V2。
2. **强烈建议补齐 V2 深度观察**：阅读器/书库这类深层数据（Manga/章节/页对象、大量 @State 引用类型）是 V1 冗余更新的重灾区；局部改用 `@ObservedV2 + @Trace + @Monitor`（深度监听、属性级精准更新）收益明确、风险可控（V1/V2 可混用）。
3. **对存量巨兽（MainMenuPage ~1.3MB、MangaViewer ~900KB）不要全量迁移**：风险大、收益小。
4. 迁移注意点：V2 中 animateTo 部分场景异常；@Param 复杂类型是引用而非深拷贝；状态管理只能在主线程。

---

## 8. 懒加载布局（LazyColumnLayout 等）

来源：⑦ 懒加载布局开发指导。

> **📎 官网文档**：[⑦ 懒加载布局开发指导](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-layout-development-create-lazy-layout)
> **📄 原始抓取文件**：[07_lazy_layout.md](../tmp/api26-docs/07_lazy_layout.md)

### 8.1 文档要点

- 三种懒加载布局容器**本身不滚动**，嵌套在可滚动父组件内按需创建子组件，帧间空闲预加载上下各半屏，减少首帧与内存，支持混合布局+独立数据源。
- **版本**：`LazyVGridLayout` 自 API 19；`LazyColumnLayout` / `LazyVWaterFlowLayout` 自 **API 26.0.0**（项目当前 API 23 用不了后两者）。
- 能力：VGrid 支持 columnsTemplate/rowsGap/columnsGap；Column 支持 space/alignItems；**API 26 起三者支持 header/footer/sticky/onVisibleIndexesChange**；仅 LazyColumnLayout 可嵌套懒加载容器。
- **约束**（避免踩坑）：高度默认自适应，禁止设固定高度/constraintSize/aspectRatio/layoutWeight 等垂直固定；父组件必须竖直方向；List 下勿同时设 lanes/chainAnimation/scrollSnapAlign；WaterFlow 多列时失效；sticky 缝隙用 pixelRound 兜底。
- LazyForEach 键须唯一且稳定；`cachedCount` 控制预加载量。

### 8.2 项目现状

- LazyForEach 使用广泛且成熟：`MangaViewer.ets:6694/:9041/:9059`（漫画翻页数据源）、`SuwayomiTabContent.ets:1476`、`MainMenuPage.ets` 书库网格/列表（cachedCount 十余处，取值 3/5/8/10/12）。
- 数据源封装良好：`Utils/BasicDataSource.ets`（通用 IDataSource，`setDataStable` 按 key/signature 最小化 diff）、`components/MangaLazyDataSources.ets`（notifyDataAdd/Change/Reload 齐备）。
- **LazyColumnLayout / LazyVGridLayout / LazyVWaterFlowLayout：全库 0 使用**。

### 8.3 升级影响与建议

- 现有方案成熟，**无需推翻**。
- **可低成本试点**：`LazyVGridLayout`（API 19 起）用于书库/图源网格的"Scroll 内嵌网格"场景；升级 API 26 后 `LazyColumnLayout/LazyVWaterFlowLayout` 用于"混合布局页"（如书库首页多区块混合），获得 header/footer/sticky 粘性标题和 onVisibleIndexesChange。
- cachedCount 现值 3-12 已合理，可微调，无硬性改动必要。

---

## 9. PDF（PDFViewManager / setRenderMode）

来源：③ pdf-arkts-pdfviewmanage（用户关注 setRenderMode 锚点）。

> **📎 官网文档**：[③ PDFViewManager#setRenderMode](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/pdf-arkts-pdfviewmanage#setrendermode)
> **📄 原始抓取文件**：[03_pdfviewmanage.md](../tmp/api26-docs/03_pdfviewmanage.md)

### 9.1 文档要点

- 导入 `import { pdfViewManager } from '@kit.PDFKit'`；创建 `new pdfViewManager.PdfController()`；先 `loadDocument` 成功再调用其他方法。
- **API 26 新增项**（起始版本均 26.0.0）：
  - **`setRenderMode(renderMode: PresetRenderMode): void`**：`PresetRenderMode` 枚举只有两个值——`DEFAULT`=0（标准渲染，默认）、`DARKMODE`=1（深色反差增强，适合夜间/低光）。错误码 1011302004（渲染线程忙碌）、1011302005（未知渲染模式），需 try-catch。
  - `loadDocumentFromMemory(data: ArrayBuffer, ...)`：支持 1GB 以内二进制；data 必须用 private 变量存储，不可用 @State/@Link，生命周期内不得篡改。
  - `getPageIndexFromViewPoint(viewPoint: Point): number`：视图坐标转页码，-1 表示未落在有效页面。
- 文档中**不存在 `PageRenderMode`**；PdfView 组件的页面配置是 pageFit/pageLayout/isContinuous/showScroll 等既有属性。

```ts
// API 26 setRenderMode 推荐写法（深色主题联动）
import { pdfService, pdfViewManager, PdfView } from '@kit.PDFKit';
import { BusinessError } from '@kit.BasicServicesKit';

@Component
export struct PdfKitViewerComponent {
  private pdfController: pdfViewManager.PdfController = new pdfViewManager.PdfController();
  @Prop isDarkTheme: boolean = false;

  private loadPdfDocument(): void {
    this.pdfController.loadDocument(this.ebook.filePath)
      .then((loadResult: pdfService.ParseResult) => {
        if (loadResult === pdfService.ParseResult.PARSE_SUCCESS) {
          this.applyRenderMode(); // 先加载成功，再设渲染模式
        }
      })
      .catch((err: BusinessError) => { /* 加载失败处理 */ });
  }

  private applyRenderMode(): void {
    try {
      this.pdfController.setRenderMode(
        this.isDarkTheme
          ? pdfViewManager.PresetRenderMode.DARKMODE
          : pdfViewManager.PresetRenderMode.DEFAULT
      );
    } catch (e) {
      const err = e as BusinessError;
      logger.warn(TAG, `setRenderMode failed: code=${err.code}, msg=${err.message}`);
    }
  }
}
```

### 9.2 项目现状

- 已全面采用 PDF Kit（非旧 Web 预览），**未使用 setRenderMode**：
  - `Framework/Components/PdfKitViewerComponent.ets:14`（import pdfService/pdfViewManager/PdfView）、:75（PdfController）、:285（loadDocument）、:371-377（PdfView：FIT_PAGE、单页非连续、showScroll:false）、:94/:325/:127（registerPageCountChangedListener/goToPage/releaseDocument）。
  - `pages/EBookReaderPage.ets:4151` 挂载 PdfKitViewerComponent（深色主题背景已打通）。
  - `Framework/Parsers/PdfToMangaImporter.ets:156/:172/:525-536`：导入转图路径用 `pdfService.PdfDocument + getPagePixelMap()`（服务层 API，非视图层）。

### 9.3 升级影响与建议

1. **setRenderMode 可显著改善夜间/深色阅读体验（推荐采用）**：深色主题下调用 `DARKMODE`，浅色回切 `DEFAULT`；调用时机为 `loadDocument` 返回 `PARSE_SUCCESS` 后，主题/亮度设置变化时按需切换；包裹 try-catch 处理 1011302004/1011302005。
2. `getPageIndexFromViewPoint` 可用于把"三分区点击翻页"升级为精确坐标→页码定位（低优先级）。
3. `loadDocumentFromMemory` 对现有"文件路径加载"模式收益有限，暂不必要。
4. **导入转图路径不受影响**：setRenderMode 仅作用于视图层，与 PdfToMangaImporter 互不干扰。
5. 资源纪律不变：`loadDocument` 仍不支持重复调用，`releaseDocument` 后再加载。

---

## 10. 快速调度优化 / 手写笔增强 / 沉浸式（系统级能力）

来源：② fast-scheduling-optimization、④ pen-stylus-frame-boost、⑥ arkts-immersive-light-sense。

> **📎 官网文档**：[② 快速调度优化](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/fast-scheduling-optimization_arkts) ｜ [④ 手写笔触控增强](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/pen-stylus-frame-boost) ｜ [⑥ 沉浸式轻感设计](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-immersive-light-sense)
> **📄 原始抓取文件**：[02_fast_scheduling.md](../tmp/api26-docs/02_fast_scheduling.md) ｜ [04_pen_stylus.md](../tmp/api26-docs/04_pen_stylus.md) ｜ [06_immersive.md](../tmp/api26-docs/06_immersive.md)

### 10.1 快速调度优化（②）

- 涉及 `perfHint` 等性能调度能力（应用通过性能提示参与系统调度优化）。
- 项目现状：全库 0 匹配 perfHint / schedulingOptimization。
- 建议：perfHint 可在阅读器页面切换/章节加载时上报 BEGIN/END，成本极低、失败无副作用（不保证生效），可顺手接入。

### 10.2 手写笔触控增强（④）

- 涉及 `StylusFrameBoost`（手写笔跟手性加速），需 `ohos.permission.STYLUS_FRAME_BOOST` 权限 + 高刷新率设备。
- 项目现状：`module.json5` 无 STYLUS_FRAME_BOOST 权限，全库 0 匹配。
- 建议：与"漫画家阅读/批注"场景契合度较高，如支持手写批注可考虑接入；否则暂缓（锦上添花）。

### 10.3 沉浸式轻感设计（⑥）

- 官方沉浸式设计指导：背景扩展到系统栏区域（安全区协调）、层级化内容、材质克制使用。
- 项目现状（已相当完善）：
  - **窗口级**：`Utils/WindowManager.ets` 大量 `setWindowLayoutFullScreen`（:713/:749/:785/:821/:858/:897/:1648/:2068-2091）；`EBookReaderAbility.ets:134`。
  - **页面级协调**：自研 `Utils/PageWindowCoordinator.ets`（PageWindowRegistry/PageWindowPolicy + setDisplayMode），被 `AnnotationCenterPage`、`CoverSelectionPage`、`PagePolicyHostFacade` 等使用。
  - **组件级安全区**：大量页面 `expandSafeArea([SafeAreaType.SYSTEM], [TOP, BOTTOM])` + `ignoreLayoutSafeArea(...)`。
  - **API 26 沉浸光感未用**：systemMaterial / uiMaterial / ImmersiveMaterial 全库无匹配（仅 HdsStyleBottomBar 用 HDS 组件 `systemMaterialEffect`）。
- 建议（首批改造）：
  1. `module.json5` 增加 `ohos.arkui.UIMaterial.state = enable`，系统组件零代码获得沉浸材质。
  2. 自定义弹窗（WebDAVConfigDialog/ProxyConfigDialog/CacheManagementPanel 等 V2 面板）逐步用 `.systemMaterial(new uiMaterial.ImmersiveMaterial(...))` 替换手写背景色+模糊。
  3. 遵守性能红线（见 §1.3）。

---

## 11. HdsSnackBar（UI 设计组件）

来源：⑤ ui-design-hdssnackbar。

> **📎 官网文档**：[⑤ HdsSnackBar](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ui-design-hdssnackbar#示例)
> **📄 原始抓取文件**：[05_hdssnackbar.md](../tmp/api26-docs/05_hdssnackbar.md)

### 11.1 文档要点

- **起始版本 6.0.0(20)**；导入 `import { HdsSnackBar } from '@kit.UIDesignKit'`；构造 `new HdsSnackBar(uiContext)`。
- 方法：`show(icon, message, operation, style?)`、`dismiss()`。
- 参数：
  - `SnackBarIconOptions`：icon（SymbolGlyph/Image）、iconType（默认 SMALL）、iconModifier/iconSymbolModifier、**iconBuilder/iconBuilderWidth（26.0.0 新增）**；
  - `SnackBarMessageOptions`：title/titleColor/content/contentColor、**titleModifier/contentModifier（26.0.0 新增）**；
  - `SnackBarOperationOptions`：operationType（TEXT_ONLY=0/CLOSE_BUTTON_ONLY=1/TEXT_WITH_ARROW=2/TEXT_WITH_CLOSE=3/HIGHLIGHT_TEXT_WITH_CLOSE=4）、content、onContentClick、onCloseButtonClick、**closeSymbolModifier（26.0.0）**、textButtonId 等；
  - `SnackBarStyleOptions`：width、backgroundColor、backgroundBlurStyle、duration（默认 5000ms，≤0 常驻）、blurStrategy（默认 ADAPTIVE）、isHeightAdaptive（6.1.0(23) 起，默认 false）。

```ts
import { HdsSnackBar, SnackBarIconOptions, SnackBarMessageOptions,
  SnackBarOperationOptions, SnackBarStyleOptions, SnackBarOperationType } from '@kit.UIDesignKit';

const hds = new HdsSnackBar(this.getUIContext());
hds.show(
  { icon: $r('sys.symbol.checkmark_circle') },
  { title: '标题', content: '内容' },
  { operationType: SnackBarOperationType.TEXT_WITH_CLOSE, content: '操作', textButtonId: 'op' },
  { duration: -1 } // 常驻
);
```

### 11.2 项目现状与建议

- 项目无 HdsSnackBar 使用（promptAction.showToast 为主）。
- HdsSnackBar 为可选增强，可替代部分 showToast 场景（尤其需要"操作按钮+常驻"的提示），无强制迁移。

---

## 12. 升级路线图与优先级建议

### 第一批（升级后立即处理，成本低、防回归）
1. **视觉回归审计**：全工程 Toast/系统对话框/自定义对话框的 `backgroundBlurStyle` 默认值变更（§1.1）——升级后跑一遍 UI 巡检，必要时显式设回或改 systemMaterial。
2. **修废弃调用**：`BookSourceTabContent.ets:877` → UIContext 方式。
3. **沉浸式系统材质开关**：`module.json5` 增加 `ohos.arkui.UIMaterial.state = enable`（需 targetAPIVersion≥26），并用 `uiMaterial.getMaterialInfo()` 判断能力 + 提供用户开关。

### 第二批（价值明确、风险可控）
4. **PDF setRenderMode**：深色主题联动（§9）。
5. **ChipGroupV2 试点**：替换 1-2 个筛选类自绘 Chip 场景验证效果（§5）。
6. **状态管理 V2 深度观察试点**：选择阅读器/书库一个数据密集模块引入 `@ObservedV2 + @Trace + @Monitor`（§7）。

### 第三批（可选增量、评估后引入）
7. LazyColumnLayout/LazyVWaterFlowLayout 混合布局页试点（§8）。
8. SelectionMenu 迁移 Text 阅读器选择菜单（WebView 场景除外，§6）。
9. HdsSnackBar / PopupV2 按场景选用。
10. perfHint、StylusFrameBoost 视产品方向接入（§10）。

### 不建议做
- SwipeRefresherV2 替换现有 Refresh（视觉回归风险高）。
- TreeViewV2 替换自建扁平树。
- 存量巨兽页面（MainMenuPage/MangaViewer）全量 V1→V2 迁移。

---

## 13. 参考文档清单（对应 20 个链接）

| # | 主题 | 官网文档（点击跳转） | 原始抓取文件 |
|---|---|---|---|
| ① | SelectionMenu | [ohos-arkui-advanced-selectionmenu#导入模块](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ohos-arkui-advanced-selectionmenu#导入模块) | [01_selectionmenu.md](../tmp/api26-docs/01_selectionmenu.md) |
| ② | 快速调度优化 | [fast-scheduling-optimization_arkts](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/fast-scheduling-optimization_arkts) | [02_fast_scheduling.md](../tmp/api26-docs/02_fast_scheduling.md) |
| ③ | PDFViewManager.setRenderMode | [pdf-arkts-pdfviewmanage#setrendermode](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/pdf-arkts-pdfviewmanage#setrendermode) | [03_pdfviewmanage.md](../tmp/api26-docs/03_pdfviewmanage.md) |
| ④ | 手写笔触控增强 | [pen-stylus-frame-boost](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/pen-stylus-frame-boost) | [04_pen_stylus.md](../tmp/api26-docs/04_pen_stylus.md) |
| ⑤ | HdsSnackBar | [ui-design-hdssnackbar#示例](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ui-design-hdssnackbar#示例) | [05_hdssnackbar.md](../tmp/api26-docs/05_hdssnackbar.md) |
| ⑥ | 沉浸式轻感设计 | [arkts-immersive-light-sense](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-immersive-light-sense) | [06_immersive.md](../tmp/api26-docs/06_immersive.md) |
| ⑦ | 懒加载布局 | [arkts-layout-development-create-lazy-layout](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-layout-development-create-lazy-layout) | [07_lazy_layout.md](../tmp/api26-docs/07_lazy_layout.md) |
| ⑧ | tips 悬浮气泡系统材质 | [ts-universal-attributes-tips#示例3](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ts-universal-attributes-tips#示例3设置悬浮气泡的系统材质视效) | [08_tips.md](../tmp/api26-docs/08_tips.md) |
| ⑨ | promptAction showToastOptions | [js-apis-promptaction#showtoastoptions](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/js-apis-promptaction#showtoastoptions) | [09_promptaction.md](../tmp/api26-docs/09_promptaction.md) |
| ⑩ | promptAction showDialogOptions | [js-apis-promptaction#showdialogoptions](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/js-apis-promptaction#showdialogoptions) | [09_promptaction.md](../tmp/api26-docs/09_promptaction.md) |
| ⑪ | promptAction ActionMenuOptions | [js-apis-promptaction#actionmenuoptions](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/js-apis-promptaction#actionmenuoptions) | [09_promptaction.md](../tmp/api26-docs/09_promptaction.md) |
| ⑫ | CustomDialogControllerOptions | [ts-methods-custom-dialog-box#customdialogcontrolleroptions对象说明](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ts-methods-custom-dialog-box#customdialogcontrolleroptions对象说明) | [12_custom_dialog.md](../tmp/api26-docs/12_custom_dialog.md) |
| ⑬ | bindSheet 半模态系统材质 | [ts-universal-attributes-sheet-transition#示例10](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ts-universal-attributes-sheet-transition#示例10半模态设置系统材质) | [13_sheet.md](../tmp/api26-docs/13_sheet.md) |
| ⑭ | PopupOptions 类型说明 | [ts-universal-attributes-popup#popupoptions类型说明](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ts-universal-attributes-popup#popupoptions类型说明) | [14_popup.md](../tmp/api26-docs/14_popup.md) |
| ⑮ | ChipV2 | [ohos-arkui-advanced-chipv2#示例](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ohos-arkui-advanced-chipv2#示例) | [15_chipv2.md](../tmp/api26-docs/15_chipv2.md) |
| ⑯ | ChipGroupV2 | [ohos-arkui-advanced-chipgroupv2](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ohos-arkui-advanced-chipgroupv2) | [16_chipgroupv2.md](../tmp/api26-docs/16_chipgroupv2.md) |
| ⑰ | 状态管理 V2 | [arkts-state-management-overview#状态管理v2](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/arkts-state-management-overview#状态管理v2) | [17_state_mgmt.md](../tmp/api26-docs/17_state_mgmt.md) |
| ⑱ | PopupV2 | [ohos-arkui-advanced-popupv2](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ohos-arkui-advanced-popupv2) | [18_popupv2.md](../tmp/api26-docs/18_popupv2.md) |
| ⑲ | SwipeRefresherV2 | [ohos-arkui-advanced-swiperefresherv2](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ohos-arkui-advanced-swiperefresherv2) | [19_swiperefresherv2.md](../tmp/api26-docs/19_swiperefresherv2.md) |
| ⑳ | TreeViewV2 | [ohos-arkui-advanced-treeviewv2#示例](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/api/ohos-arkui-advanced-treeviewv2#示例) | [20_treeviewv2.md](../tmp/api26-docs/20_treeviewv2.md) |

原始抓取（Markdown 转换版）存放于 [`tmp/api26-docs/`](../tmp/api26-docs/)，可作后续开发时的快速查阅。各详细章节（§1–§11）开头均已内嵌对应的官网链接与原始文件链接。

---

*本报告由自动化调研生成：抓取官方文档 → 提取 API 26 关键信息 → 全工程 grep 对比（已排除 .bak）→ 输出结构化分析。接口签名与版本号以官方文档为准，正式升级前请再次核对最新文档。*
