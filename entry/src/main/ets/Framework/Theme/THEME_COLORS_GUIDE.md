# 统一主题色系统使用指南

## 概述

本项目采用类似 Material Design 3 的语义化主题色系统，所有颜色通过语义化角色定义，自动适配深浅主题。

## 核心概念

### 颜色角色（Color Roles）

| 角色 | 用途 | 示例 |
|------|------|------|
| `primary` | 主要强调色，品牌色 | 主按钮、FAB、重要链接 |
| `onPrimary` | 主色上的内容颜色 | 主按钮文字 |
| `secondary` | 次要强调色 | 次要按钮、筛选器 |
| `surface` | 表面/容器背景 | 卡片、对话框、底部栏 |
| `onSurface` | 表面上的内容颜色 | 卡片内文字 |
| `background` | 页面背景 | 整体页面背景 |
| `error/success/warning/info` | 状态色 | 错误提示、成功提示 |
| `outline` | 边框色 | 输入框边框、分割线 |
| `textPrimary/Secondary/Tertiary` | 文字层级 | 标题、正文、辅助文字 |

## 使用方式

### 方式一：静态访问（简单场景）

适用于不需要响应主题切换的场景，或在非组件代码中使用。

```typescript
import { AppColors } from '../Framework/Theme';

// 直接使用静态属性
Text('标题')
  .fontColor(AppColors.textPrimary)

Button('确定')
  .backgroundColor(AppColors.primary)
  .fontColor(AppColors.onPrimary)

Column()
  .backgroundColor(AppColors.surface)
  .borderColor(AppColors.outline)
```

### 方式二：响应式状态（推荐）

适用于需要响应主题切换的组件，主题变化时自动更新UI。

```typescript
import { ThemeColorState, ThemeColorManager, createThemeColors } from '../Framework/Theme';

@Component
struct MyComponent {
  @State colors: ThemeColorState = createThemeColors();
  
  aboutToAppear() {
    // 注册主题变化监听
    ThemeColorManager.register(this.colors, (newColors) => {
      this.colors = newColors;
    });
  }
  
  aboutToDisappear() {
    // 取消注册
    ThemeColorManager.unregister(this.colors);
  }
  
  build() {
    Column() {
      Text('标题')
        .fontColor(this.colors.textPrimary)
      
      Text('副标题')
        .fontColor(this.colors.textSecondary)
      
      Button('主按钮')
        .backgroundColor(this.colors.primary)
        .fontColor(this.colors.onPrimary)
      
      Button('次要按钮')
        .backgroundColor(this.colors.buttonSecondary)
        .fontColor(this.colors.buttonSecondaryText)
    }
    .backgroundColor(this.colors.surface)
  }
}
```

### 方式三：带透明度的颜色

```typescript
// 静态方式
import { AppColors, ColorRole } from '../Framework/Theme';

// 50% 透明度的主色
const semiTransparentPrimary = AppColors.withAlpha(ColorRole.PRIMARY, 0.5);

// 响应式方式
.backgroundColor(this.colors.withAlpha(this.colors.primary, 0.5))
```

## 颜色角色完整列表

### 主色系
- `primary` - 主要强调色
- `onPrimary` - 主色上的内容
- `primaryContainer` - 主色容器（较浅）
- `onPrimaryContainer` - 主色容器上的内容

### 次要色系
- `secondary` - 次要强调色
- `onSecondary` - 次要色上的内容
- `secondaryContainer` - 次要色容器
- `onSecondaryContainer` - 次要色容器上的内容

### 第三色系
- `tertiary` - 第三强调色（用于特殊标签）
- `onTertiary` - 第三色上的内容
- `tertiaryContainer` - 第三色容器
- `onTertiaryContainer` - 第三色容器上的内容

### 表面色系
- `surface` - 表面色（卡片、面板）
- `onSurface` - 表面上的内容
- `surfaceVariant` - 表面变体
- `onSurfaceVariant` - 表面变体上的内容
- `surfaceContainer` - 表面容器
- `surfaceContainerLow` - 低层级表面容器
- `surfaceContainerHigh` - 高层级表面容器
- `surfaceContainerHighest` - 最高层级表面容器

### 背景色系
- `background` - 页面背景
- `onBackground` - 背景上的内容

### 状态色系
- `error` / `onError` / `errorContainer` / `onErrorContainer`
- `success` / `onSuccess`
- `warning` / `onWarning`
- `info` / `onInfo`

### 边框和分割线
- `outline` - 主要边框色
- `outlineVariant` - 次要边框色（更浅）
- `divider` - 分割线

### 文字层级
- `textPrimary` - 主要文字（标题、重要内容）
- `textSecondary` - 次要文字（正文）
- `textTertiary` - 第三级文字（辅助信息）
- `textDisabled` - 禁用文字
- `textHint` - 提示文字（placeholder）

### 图标层级
- `iconPrimary` - 主要图标
- `iconSecondary` - 次要图标
- `iconDisabled` - 禁用图标

### 按钮专用
- `buttonPrimary` / `buttonPrimaryText`
- `buttonSecondary` / `buttonSecondaryText`
- `buttonDisabled` / `buttonDisabledText`

### 特殊用途
- `shadow` - 阴影色
- `scrim` - 遮罩色
- `overlay` - 覆盖层
- `ripple` - 水波纹

## 迁移指南

### 从硬编码颜色迁移

| 旧代码 | 新代码 |
|--------|--------|
| `.fontColor('#000000')` | `.fontColor(AppColors.textPrimary)` |
| `.fontColor('#666666')` | `.fontColor(AppColors.textSecondary)` |
| `.fontColor('#999999')` | `.fontColor(AppColors.textTertiary)` |
| `.fontColor('#FFFFFF')` | `.fontColor(AppColors.onPrimary)` 或 `textPrimary`（深色模式） |
| `.backgroundColor('#FFFFFF')` | `.backgroundColor(AppColors.surface)` |
| `.backgroundColor('#F5F5F5')` | `.backgroundColor(AppColors.surfaceVariant)` |
| `.backgroundColor('#007DFF')` | `.backgroundColor(AppColors.primary)` |
| `.backgroundColor('#4CAF50')` | `.backgroundColor(AppColors.success)` |
| `.backgroundColor('#F44336')` | `.backgroundColor(AppColors.error)` |
| `.backgroundColor('#FF9800')` | `.backgroundColor(AppColors.warning)` |
| `.borderColor('#E0E0E0')` | `.borderColor(AppColors.outlineVariant)` |
| `.shadow({ color: '#1F000000' })` | `.shadow({ color: AppColors.getShadowColor(4) })` |

### 从 ThemeAwareHelper 迁移

| 旧代码 | 新代码 |
|--------|--------|
| `ThemeAwareHelper.getTestManagementThemedColor('text_primary', theme)` | `this.colors.textPrimary` |
| `ThemeAwareHelper.getTestManagementThemedColor('background', theme)` | `this.colors.background` |
| `ThemeAwareHelper.getTestManagementThemedColor('accent_primary', theme)` | `this.colors.primary` |
| `ThemeAwareHelper.getTestManagementThemedColor('button_primary', theme)` | `this.colors.buttonPrimary` |

## 最佳实践

1. **优先使用语义化角色**：不要直接使用颜色值，使用语义化角色
2. **配对使用**：`primary` 配 `onPrimary`，`surface` 配 `onSurface`
3. **层级分明**：文字使用 `textPrimary/Secondary/Tertiary` 区分重要性
4. **状态一致**：错误用 `error`，成功用 `success`，警告用 `warning`
5. **响应式优先**：在组件中优先使用 `ThemeColorState` 响应式方式

## 自定义主题色

如需自定义主题色，修改 `AppColors.ets` 中的 `ThemePalette` 对象：

```typescript
const ThemePalette: Record<ColorRole, ColorValue> = {
  [ColorRole.PRIMARY]: {
    light: '#您的浅色主色',
    dark: '#您的深色主色'
  },
  // ...
};
```
