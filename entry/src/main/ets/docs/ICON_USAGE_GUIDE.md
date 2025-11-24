# 图标使用指南

本文档说明如何正确使用项目中的图标系统，特别是新重绘的图标及其三种状态。

## 图标状态说明

所有重绘的图标都有三种状态：

1. **Normal（默认状态）**：正常显示状态，使用深色（#333333）确保在浅色模式下可读
2. **Selected（选中状态）**：当前选中或激活状态，使用蓝色（#007DFF）和浅蓝色填充（#E6F2FF）
3. **Inactive（未选中/禁用状态）**：禁用或未激活状态，使用浅灰色（#CCCCCC）

## 可用图标列表

### 1. 图片图标（Image）
- `$r('app.media.ic_image_normal')` - 默认状态
- `$r('app.media.ic_image_selected')` - 选中状态
- `$r('app.media.ic_image_inactive')` - 禁用状态

**用途**：图片库、图片上传、图片管理等功能

### 2. 搜索图标（Search）
- `$r('app.media.ic_search_normal')` - 默认状态
- `$r('app.media.ic_search_selected')` - 选中状态（搜索激活时）
- `$r('app.media.ic_search_inactive')` - 禁用状态

**用途**：搜索功能、搜索按钮

### 3. 列表视图图标（List View）
- `$r('app.media.ic_view_list_normal')` - 默认状态
- `$r('app.media.ic_view_list_selected')` - 选中状态（当前为列表视图时）
- `$r('app.media.ic_view_list_inactive')` - 禁用状态

**用途**：视图模式切换（列表视图）

### 4. 网格视图图标（Grid View）
- `$r('app.media.ic_view_grid_normal')` - 默认状态
- `$r('app.media.ic_view_grid_selected')` - 选中状态（当前为网格视图时）
- `$r('app.media.ic_view_grid_inactive')` - 禁用状态

**用途**：视图模式切换（网格视图）

### 5. 性能图标（Performance）
- `$r('app.media.ic_performance_normal')` - 默认状态
- `$r('app.media.ic_performance_selected')` - 选中状态（性能监控激活时）
- `$r('app.media.ic_performance_inactive')` - 禁用状态

**用途**：性能监控、性能设置

### 6. 同步图标（Sync）
- `$r('app.media.ic_sync_normal')` - 默认状态
- `$r('app.media.ic_sync_selected')` - 选中状态（正在同步时）
- `$r('app.media.ic_sync_inactive')` - 禁用状态

**用途**：数据同步、刷新功能

### 7. 系统图标（System）
- `$r('app.media.ic_system_normal')` - 默认状态
- `$r('app.media.ic_system_selected')` - 选中状态（系统设置激活时）
- `$r('app.media.ic_system_inactive')` - 禁用状态

**用途**：系统设置、系统管理

## 使用示例

### 示例1：视图切换按钮（MainMenuPage）

```typescript
Button() {
  Image(this.libraryViewMode === LibraryViewMode.LIST 
    ? $r('app.media.ic_view_list_selected')
    : $r('app.media.ic_view_grid_selected'))
    .width(24)
    .height(24)
}
.type(ButtonType.Circle)
.width(36)
.height(36)
.backgroundColor(Color.Transparent)
.onClick(() => {
  this.toggleLibraryViewMode();
})
```

### 示例2：根据状态动态切换图标

```typescript
// 假设有一个isSearchActive状态
Button() {
  Image(this.isSearchActive 
    ? $r('app.media.ic_search_selected')
    : $r('app.media.ic_search_normal'))
    .width(24)
    .height(24)
}
.onClick(() => {
  this.toggleSearch();
})
```

### 示例3：禁用状态的图标

```typescript
Button() {
  Image(this.canSync 
    ? $r('app.media.ic_sync_normal')
    : $r('app.media.ic_sync_inactive'))
    .width(24)
    .height(24)
}
.enabled(this.canSync)
.onClick(() => {
  if (this.canSync) {
    this.startSync();
  }
})
```

## 设计规范

### 颜色规范
- **Normal状态**：#333333（深色，确保浅色模式下可读）
- **Selected状态**：#007DFF（蓝色主色）+ #E6F2FF（浅蓝色填充）
- **Inactive状态**：#CCCCCC（浅灰色）

### 尺寸规范
- 所有图标原始尺寸：24x24 px
- 推荐显示尺寸：24x24 px（1:1）
- 按钮中使用时可适当调整，但保持比例

### 间距规范
- 图标周围至少保持4px的padding
- 在按钮中使用时，按钮尺寸通常为图标尺寸 + 12px（每边6px padding）

## 注意事项

1. **不要使用fillColor**：新图标已经包含颜色信息，不需要再使用fillColor属性
2. **保持一致性**：在相同的功能模块中，确保图标状态的使用一致
3. **避免频繁切换**：状态切换应该有明确的用户操作或系统状态变化触发
4. **无障碍支持**：在使用图标时，确保提供适当的文本标签或提示

## 更新日志

- 2024-11-08：初始版本，创建7组图标，每组包含3种状态

