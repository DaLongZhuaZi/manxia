# ArkUI 选择框（ActionMenu）正确用法与最佳实践（API 18/19）

本指南系统化整理 HarmonyOS Next ArkUI 的系统选择框（ActionMenu）的正确用法、类型约束、内容与样式能力，以及项目内的安全接入范式，便于后续统一复用与排错。

## 适用场景
- 需要在系统样式的菜单中，让用户从 1–6 个操作中选择其一。
- 期望使用系统级弹出层与交互、一致的可访问性与主题适配。
- 不需要在弹窗中自定义复杂布局（图片、输入框、列表等）。

## 能力与限制（官方能力归纳）
- 显示内容：仅支持 `title`（纯文本）和 `buttons`（按钮列表）。
- 按钮：1–6 个自定义按钮，属性包含 `text`（显示文本）与 `color`（按钮文本颜色）。
- 取消：用户点击蒙层或系统取消会触发失败回调（或 Promise reject），菜单本身不支持自定义复杂取消行为；如需业务取消分支，建议保留一个自定义“取消”按钮并在回调中处理。
- 样式：按钮仅支持文本与颜色；不支持图标、富文本、组件插入、复杂排版。
- 窗口属性：部分实现支持 `isModal` 与 `showInSubWindow`（是否模态与是否使用子窗口）。
- UI 上下文：必须通过 `UIContext.getPromptAction()` 调用，不能直接使用废弃的 `getContext()` 或旧版全局 `promptAction`（项目规则 62）。

参考资料：
- [示例与能力综述 1](https://developer.aliyun.com/article/1666925)
- [示例与能力综述 2](https://segmentfault.com/a/1190000046647148)
- [示例代码（包含 menu 参数说明）](https://www.cnblogs.com/webabcd/p/18700439/harmony_pages_component_flyout_PromptActionDemo)

## 类型与参数（项目内约束）
- ArkTS 类型安全：严禁使用 `any`/`unknown`，所有对象字面量需对应明确接口（项目规则 14/24/60）。
- 类型断言：仅允许使用 `as T` 语法（项目规则 21）。
- 主题色：统一通过 `ThemeAwareHelper.getTestManagementThemedColor()` 获取 `Resource` 类型颜色；禁止硬编码颜色值（项目规则 43/61）。
- 按钮数组：必须构造 1–6 元素的变长元组，避免 `undefined` 项导致运行时错误与 ArkTS 校验报错（我们在 `UniversalDialog.ets` 已实现安全构造）。

项目内接口约定（节选）：

```ts
// 按钮定义（ArkTS 接口）
interface ActionMenuButtonDef {
  text: string;
  color: Resource; // 统一使用 Resource 类型颜色
}

// 选项定义（ArkTS 接口）
interface ActionMenuOptionsDef {
  title: string;
  buttons: [
    ActionMenuButtonDef,
    ActionMenuButtonDef?,
    ActionMenuButtonDef?,
    ActionMenuButtonDef?,
    ActionMenuButtonDef?,
    ActionMenuButtonDef?
  ];
  // 可选：若系统版本支持
  isModal?: boolean;
  showInSubWindow?: boolean;
}
```

## 正确接入范式（组件内调用）

```ts
import { UIContext } from '@kit.ArkUI';
import prompt from '@kit.ArkUI'; // 如需类型引用，请以 UIContext.getPromptAction() 为准
import { ThemeAwareHelper, ThemeType } from '../../Framework/Theme/ThemeAware';

// 获取 UIContext 并调用 PromptAction
const uiContext = this.getUIContext();
if (!uiContext) {
  // 项目统一日志：logger.error
  logger.error('UIContext 获取失败，无法展示 ActionMenu');
  return;
}

const promptAction = uiContext.getPromptAction();
if (!promptAction) {
  logger.error('PromptAction 不可用（上下文未就绪）');
  return;
}

// 构造安全的按钮元组（1–6）
const buttons: [ActionMenuButtonDef, ActionMenuButtonDef?] = [
  { text: '主操作', color: ThemeAwareHelper.getTestManagementThemedColor('accent_green', ThemeType.LIGHT) },
  { text: '取消', color: ThemeAwareHelper.getTestManagementThemedColor('button_inactive', ThemeType.LIGHT) },
];

// 选项对象使用显式接口
const options: ActionMenuOptionsDef = {
  title: '请选择操作',
  buttons,
  isModal: true,
};

// 推荐使用 Promise，并在 then/catch 中区分用户行为
promptAction.showActionMenu(options)
  .then(data => {
    // data.index: number（用户选择的按钮索引，从 0 开始）
    logger.info(`ActionMenu 选择 index=${data.index}`);
    // 执行业务动作
  })
  .catch((err: Error) => {
    // 用户取消或点击空白区域，一般走 reject
    logger.warn(`ActionMenu 取消或错误：${err.message}`);
  });
```

关键点：
- 必须在 `aboutToAppear` 或明确的 UI 生命周期节点中获取并缓存 `UIContext`（项目规则 58/62）。
- 只能在动画或弹窗回调中修改 `@State` 状态变量，禁止直接操作组件实例（项目规则 58）。
- 按钮颜色请统一从 `ThemeAwareHelper` 获取 `Resource` 类型，避免硬编码与主题不一致（项目规则 61）。

## 常见错误与规避
- 未类型化对象字面量：必须为 `options` 与 `buttons` 定义接口（已在项目中通过 `ActionMenuButtonDef`/`ActionMenuOptionsDef` 修复）。
- 按钮数组包含 `undefined`：严格构造 1–6 元素元组，动态截断多余项，避免运行时失败。
- `PromptAction` 未就绪：在调用前对 `uiContext` 和 `promptAction` 做空值检查，失败时记录日志并返回。
- 颜色类型错误：确保颜色为 `Resource` 类型，统一由主题助手提供。
- 依赖废弃 API：禁止使用 `getContext()` 与全局 `animateTo`，改用 `UIContext.getHostContext()` 与 `UIContext.animateTo`（项目规则 58/62）。

## 样式与内容优化建议
- 标题：加入关键上下文（如漫画名、候选数量），示例：`合并漫画：xxx（找到 3 个候选）`。
- 按钮顺序：将主要操作置顶，取消置底，危险操作（如“替换”或“删除”）置末位并使用危险色。
- 颜色：
  - 主操作：`accent_green`
  - 次操作：`button_inactive`
  - 危险操作：`button_danger`
- 模态：对于数据风险操作建议 `isModal: true`，减少误触。

## 进阶：需要更丰富内容时
- 使用 `UIContext.getPromptAction().openCustomDialog(...)` 加载自定义组件内容（图文、列表、输入框、复杂排版等）。
- 自定义弹窗需严格遵守 ArkTS 类型与项目沉浸式显示规范（规则 48），将 UI 构建拆分为多个 `@Builder` 方法，并使用 `AnimatedComponent`/`AnimatedButton` 提供统一动画能力（规则 52/53）。

## 参考与链接
- [示例与能力综述（阿里云）](https://developer.aliyun.com/article/1666925)
- [示例与能力综述（SegmentFault）](https://segmentfault.com/a/1190000046647148)
- [菜单参数与示例（博客园）](https://www.cnblogs.com/webabcd/p/18700439/harmony_pages_component_flyout_PromptActionDemo)

> 注：以上资料用于梳理能力与参数范式，项目实现需以 HarmonyOS Next 最新官方文档与本仓库约束为准；涉及 API 19 的迁移（如 `getContext`/`animateTo`）已在项目中完成替换。