# 测试管理页面主题切换功能

## 功能概述

为 `TestManagementPage.ets` 页面成功添加了主题切换功能，支持浅色和暗色两种主题模式。该功能具有良好的复用性，可以轻松应用到其他相似结构的页面中。

## 实现的功能

### 1. 主题管理系统
- **ThemeManager.ets**: 单例模式的主题管理器，负责主题的切换、保存和加载
- **ThemeType**: 枚举定义了 `LIGHT` 和 `DARK` 两种主题类型
- **主题持久化**: 使用 `preferences` 保存用户的主题选择

### 2. 主题切换组件
- **ThemeToggle.ets**: 可复用的主题切换按钮组件
- **多种样式**: 支持 `compact` 和 `labeled` 两种显示样式
- **动画效果**: 平滑的主题切换动画

### 3. 主题感知辅助工具
- **ThemeAware.ets**: 提供主题感知功能的辅助类
- **ThemeAwareHelper**: 提供颜色资源获取和动画效果的静态方法
- **ThemeAwareState**: 管理组件的主题状态

## 颜色资源配置

### 1. 基础颜色 (base/element/color.json)
```json
{
  "test_management_background_light": "#F5F5F5",
  "test_management_text_primary_light": "#212121",
  "test_management_text_secondary_light": "#757575",
  "test_management_button_background_light": "#E0E0E0",
  "test_management_panel_background_light": "#FFFFFF",
  "test_management_panel_border_light": "#E0E0E0",
  "test_management_accent_primary_light": "#2196F3",
  "test_management_accent_secondary_light": "#4CAF50",
  "test_management_divider_light": "#E0E0E0"
}
```

### 2. 暗色主题 (dark/element/color.json)
```json
{
  "test_management_background_dark": "#1A1A1A",
  "test_management_text_primary_dark": "#FFFFFF",
  "test_management_text_secondary_dark": "#B0B0B0",
  "test_management_button_background_dark": "#2A2A2A",
  "test_management_panel_background_dark": "#2A2A2A",
  "test_management_panel_border_dark": "#404040",
  "test_management_accent_primary_dark": "#4CAF50",
  "test_management_accent_secondary_dark": "#2196F3",
  "test_management_divider_dark": "#404040"
}
```

### 3. 资源映射 (ResourceMap.ets)
所有颜色资源都在 `ResourceMap.ets` 中进行了映射，确保类型安全和代码提示。

## 页面组件更新

### 1. 搜索栏
- 支持主题切换的占位符颜色、光标颜色、字体颜色、背景色和边框色
- 添加了平滑的主题切换动画

### 2. 分类标签
- 选中和未选中状态的颜色根据主题动态调整
- 选中状态在不同主题下使用不同的文本颜色以确保可读性

### 3. 测试卡片
- 标题、描述、分类标签的颜色支持主题切换
- 卡片背景和边框颜色根据主题调整
- 添加了主题切换动画效果

### 4. 统计信息面板
- 统计数字和标签的颜色支持主题切换
- 分隔线颜色根据主题调整
- 面板背景和边框支持主题切换

### 5. 操作按钮
- 按钮文本和背景颜色支持主题切换
- 主要操作按钮在不同主题下使用不同的文本颜色
- 添加了主题切换动画

### 6. 标题栏
- 标题和副标题颜色支持主题切换
- 与页面整体主题保持一致

## 使用方法

### 1. 在页面中集成主题功能
```typescript
// 导入必要的模块
import { ThemeManager, ThemeType } from '../utils/ThemeManager'
import { ThemeToggle } from '../components/ThemeToggle'
import { ThemeAwareState, ThemeAwareHelper } from '../utils/ThemeAware'

// 在组件中添加主题状态
@State themeState: ThemeAwareState = new ThemeAwareState()
private themeManager: ThemeManager = ThemeManager.getInstance()
private componentId: string = `TestManagementPage_${Date.now()}`

// 生命周期方法
aboutToAppear() {
  ThemeAwareHelper.initializeThemeAware(this.themeState, this.themeManager, this.componentId)
}

aboutToDisappear() {
  ThemeAwareHelper.cleanupThemeAware(this.themeManager, this.componentId)
}
```

### 2. 添加主题切换按钮
```typescript
ThemeToggle({
  themeManager: this.themeManager,
  style: 'compact'  // 或 'labeled'
})
```

### 3. 使用主题颜色
```typescript
.fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
.backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
```

## 复用性

该主题系统具有良好的复用性：

1. **模块化设计**: 主题管理、切换组件和辅助工具都是独立的模块
2. **配置化颜色**: 通过配置文件定义颜色，易于扩展和修改
3. **标准化接口**: 提供统一的API接口，便于在其他页面中使用
4. **动画支持**: 内置主题切换动画，提供流畅的用户体验

## 扩展到其他页面

要在其他页面中使用此主题系统：

1. 在颜色配置文件中添加新页面的颜色定义
2. 在 `ResourceMap.ets` 中添加颜色映射
3. 在 `ThemeAwareHelper` 中添加新页面的颜色获取方法
4. 在目标页面中集成主题状态和切换组件
5. 更新页面组件使用主题颜色

这样就可以轻松地为任何页面添加主题切换功能。