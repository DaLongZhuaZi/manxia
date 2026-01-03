# SymbolGlyph 使用指南

## 概述

`SymbolGlyph` 是 HarmonyOS NEXT 提供的系统符号图标组件，用于显示系统内置的 SF Symbols 风格图标。相比传统的图片资源，SymbolGlyph 具有以下优势：

- **矢量图标**：无损缩放，适配任意尺寸
- **主题适配**：自动响应系统主题（深色/浅色模式）
- **多色支持**：支持单色、多色、分层渲染
- **性能优越**：无需加载图片资源，渲染效率高
- **统一风格**：与系统UI风格保持一致

## 基本用法

### 1. 导入组件

```typescript
import { SymbolGlyph } from '@kit.ArkUI';
```

### 2. 使用系统符号

```typescript
SymbolGlyph($r('sys.symbol.图标名称'))
  .fontSize(24)
  .fontColor([Color.Black])
```

## 常用系统图标列表

### 导航类图标

| 图标名称 | 说明 | 使用场景 |
|---------|------|---------|
| `chevron_left` | 左箭头 | 返回按钮 |
| `chevron_right` | 右箭头 | 前进、展开 |
| `chevron_up` | 上箭头 | 收起、向上 |
| `chevron_down` | 下箭头 | 展开、向下 |
| `arrow_left` | 粗左箭头 | 返回导航 |
| `arrow_right` | 粗右箭头 | 前进导航 |
| `arrow_up` | 粗上箭头 | 上传、向上 |
| `arrow_down` | 粗下箭头 | 下载、向下 |

### 操作类图标

| 图标名称 | 说明 | 使用场景 |
|---------|------|---------|
| `plus` | 加号 | 添加、新建 |
| `minus` | 减号 | 删除、移除 |
| `multiply` | 乘号/关闭 | 关闭、取消 |
| `checkmark` | 对勾 | 确认、完成 |
| `xmark` | 叉号 | 错误、关闭 |
| `trash` | 垃圾桶 | 删除 |
| `pencil` | 铅笔 | 编辑 |
| `square_and_pencil` | 方框铅笔 | 编辑、修改 |
| `doc_on_doc` | 文档复制 | 复制 |
| `scissors` | 剪刀 | 剪切 |
| `arrow_clockwise` | 顺时针箭头 | 刷新、重试 |
| `arrow_counterclockwise` | 逆时针箭头 | 撤销 |

### 文件和文档类

| 图标名称 | 说明 | 使用场景 |
|---------|------|---------|
| `folder` | 文件夹 | 目录、分组 |
| `folder_fill` | 实心文件夹 | 选中的文件夹 |
| `doc` | 文档 | 文件 |
| `doc_fill` | 实心文档 | 选中的文件 |
| `doc_text` | 文本文档 | 文本文件 |
| `doc_plaintext` | 纯文本 | TXT文件 |
| `book` | 书籍 | 书籍、阅读 |
| `book_fill` | 实心书籍 | 选中的书籍 |

### 媒体控制类

| 图标名称 | 说明 | 使用场景 |
|---------|------|---------|
| `play` | 播放 | 播放按钮 |
| `play_fill` | 实心播放 | 播放状态 |
| `pause` | 暂停 | 暂停按钮 |
| `pause_fill` | 实心暂停 | 暂停状态 |
| `stop` | 停止 | 停止按钮 |
| `stop_fill` | 实心停止 | 停止状态 |

### 通信和网络类

| 图标名称 | 说明 | 使用场景 |
|---------|------|---------|
| `wifi` | WiFi | 网络连接 |
| `antenna_radiowaves_left_and_right` | 信号 | 网络信号 |
| `arrow_down_circle` | 下载圆圈 | 下载 |
| `arrow_up_circle` | 上传圆圈 | 上传 |
| `icloud` | 云 | 云存储 |
| `icloud_and_arrow_down` | 云下载 | 从云下载 |
| `icloud_and_arrow_up` | 云上传 | 上传到云 |

### 设置和工具类

| 图标名称 | 说明 | 使用场景 |
|---------|------|---------|
| `gearshape` | 齿轮 | 设置 |
| `gearshape_fill` | 实心齿轮 | 设置（选中） |
| `slider_horizontal_3` | 滑块 | 调节、筛选 |
| `magnifyingglass` | 放大镜 | 搜索 |
| `line_3_horizontal_decrease` | 筛选 | 过滤、筛选 |
| `ellipsis` | 省略号 | 更多选项 |
| `ellipsis_circle` | 圆形省略号 | 更多菜单 |

### 状态和提示类

| 图标名称 | 说明 | 使用场景 |
|---------|------|---------|
| `info_circle` | 信息圆圈 | 信息提示 |
| `info_circle_fill` | 实心信息 | 重要信息 |
| `exclamationmark_triangle` | 警告三角 | 警告 |
| `exclamationmark_triangle_fill` | 实心警告 | 严重警告 |
| `checkmark_circle` | 对勾圆圈 | 成功 |
| `checkmark_circle_fill` | 实心对勾 | 完成 |
| `xmark_circle` | 叉号圆圈 | 错误 |
| `xmark_circle_fill` | 实心叉号 | 失败 |
| `clock` | 时钟 | 历史、时间 |
| `clock_fill` | 实心时钟 | 定时 |

### 用户和社交类

| 图标名称 | 说明 | 使用场景 |
|---------|------|---------|
| `person` | 人物 | 用户、个人 |
| `person_fill` | 实心人物 | 当前用户 |
| `person_2` | 两人 | 用户组 |
| `person_2_fill` | 实心两人 | 团队 |
| `heart` | 心形 | 收藏、喜欢 |
| `heart_fill` | 实心心形 | 已收藏 |
| `star` | 星星 | 评分、收藏 |
| `star_fill` | 实心星星 | 已评分 |

## 高级用法

### 1. 设置颜色

```typescript
// 单色
SymbolGlyph($r('sys.symbol.heart'))
  .fontColor([Color.Red])

// 使用主题颜色
SymbolGlyph($r('sys.symbol.heart'))
  .fontColor([ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)])
```

### 2. 设置大小

```typescript
SymbolGlyph($r('sys.symbol.star'))
  .fontSize(32)  // 设置图标大小
```

### 3. 渲染模式

```typescript
// 分层渲染（支持多色）
SymbolGlyph($r('sys.symbol.heart_fill'))
  .symbolEffect(new HierarchicalSymbolEffect(EffectFillStyle.ITERATIVE))

// 单色渲染
SymbolGlyph($r('sys.symbol.heart'))
  .renderingStrategy(SymbolRenderingStrategy.SINGLE)
```

### 4. 动画效果

```typescript
// 脉冲动画
SymbolGlyph($r('sys.symbol.wifi'))
  .symbolEffect(new ScaleSymbolEffect(EffectScope.WHOLE, EffectFillStyle.ITERATIVE))

// 弹跳动画
SymbolGlyph($r('sys.symbol.arrow_down'))
  .symbolEffect(new BounceSymbolEffect(EffectScope.WHOLE, EffectDirection.DOWN))
```

## 实际应用示例

### 示例1：导航按钮

```typescript
@Builder
buildBackButton() {
  Row() {
    SymbolGlyph($r('sys.symbol.chevron_left'))
      .fontSize(20)
      .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
    
    Text('返回')
      .fontSize(16)
      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      .margin({ left: 4 })
  }
  .onClick(() => this.pathStack.pop())
}
```

### 示例2：操作按钮组

```typescript
@Builder
buildActionButtons() {
  Row({ space: 12 }) {
    // 编辑按钮
    Button() {
      SymbolGlyph($r('sys.symbol.pencil'))
        .fontSize(18)
        .fontColor([Color.White])
    }
    .backgroundColor('#1890FF')
    .onClick(() => this.handleEdit())
    
    // 删除按钮
    Button() {
      SymbolGlyph($r('sys.symbol.trash'))
        .fontSize(18)
        .fontColor([Color.White])
    }
    .backgroundColor('#FF4D4F')
    .onClick(() => this.handleDelete())
    
    // 更多按钮
    Button() {
      SymbolGlyph($r('sys.symbol.ellipsis'))
        .fontSize(18)
        .fontColor([Color.White])
    }
    .backgroundColor('#52C41A')
    .onClick(() => this.showMoreOptions())
  }
}
```

### 示例3：状态指示器

```typescript
@Builder
buildStatusIndicator(status: 'success' | 'error' | 'warning' | 'info') {
  Row({ space: 8 }) {
    if (status === 'success') {
      SymbolGlyph($r('sys.symbol.checkmark_circle_fill'))
        .fontSize(20)
        .fontColor([Color.Green])
    } else if (status === 'error') {
      SymbolGlyph($r('sys.symbol.xmark_circle_fill'))
        .fontSize(20)
        .fontColor([Color.Red])
    } else if (status === 'warning') {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle_fill'))
        .fontSize(20)
        .fontColor([Color.Orange])
    } else {
      SymbolGlyph($r('sys.symbol.info_circle_fill'))
        .fontSize(20)
        .fontColor([Color.Blue])
    }
    
    Text(this.getStatusText(status))
      .fontSize(14)
  }
}
```

### 示例4：列表项图标

```typescript
@Builder
buildListItem(title: string, icon: Resource) {
  Row() {
    SymbolGlyph(icon)
      .fontSize(24)
      .fontColor([ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme)])
    
    Text(title)
      .fontSize(16)
      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      .margin({ left: 12 })
      .layoutWeight(1)
    
    SymbolGlyph($r('sys.symbol.chevron_right'))
      .fontSize(16)
      .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme)])
  }
  .width('100%')
  .padding(16)
}
```

## 注意事项

1. **颜色参数格式**：`fontColor` 必须使用数组格式 `[Color]`，不能直接传递颜色值
2. **图标命名**：使用 `$r('sys.symbol.图标名')` 格式引用系统图标
3. **主题适配**：建议配合 `ThemeAwareHelper` 使用，确保图标颜色响应主题变化
4. **大小设置**：使用 `fontSize` 而非 `width/height` 设置图标大小
5. **性能优化**：SymbolGlyph 比 Image 组件性能更好，优先使用系统图标

## 迁移指南

### 从 Image 迁移到 SymbolGlyph

**之前（使用 Image）：**
```typescript
Image($r('app.media.ic_edit'))
  .width(24)
  .height(24)
  .fillColor(Color.Blue)
```

**之后（使用 SymbolGlyph）：**
```typescript
SymbolGlyph($r('sys.symbol.pencil'))
  .fontSize(24)
  .fontColor([Color.Blue])
```

## 参考资源

- [HarmonyOS NEXT 官方文档 - SymbolGlyph](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V5/ts-basic-components-symbolglyph-V5)
- [SF Symbols 图标库](https://developer.apple.com/sf-symbols/)
