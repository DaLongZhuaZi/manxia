# 条目过渡动画系统使用指南

## 概述

条目过渡动画系统是一个通用的Canvas绘制动画框架，用于在首页、书库、发现页等场景中实现平滑的条目位置变换动画。类似于手机桌面应用图标的安装/卸载动画效果，避免突兀的UI刷新。

## 核心特性

- ✅ **Canvas精确绘制**：使用Canvas API进行像素级动画控制
- ✅ **多种动画类型**：支持添加、删除、移动、刷新等操作
- ✅ **平滑过渡效果**：支持淡入淡出、缩放、交错延迟等效果
- ✅ **自动状态管理**：自动检测条目变化并选择合适的动画类型
- ✅ **高性能实现**：使用PixelMap快照和requestAnimationFrame优化性能
- ✅ **通用可复用**：适用于任何网格布局场景

## 架构设计

### 核心组件

```
ItemTransitionAnimator.ets      - 动画引擎核心类
AnimatedGridState.ets           - 状态管理类
SnapshotCapture.ets             - 快照捕获工具
AnimatedGrid.ets                - 可复用组件包装器
```

### 工作流程

```
1. 数据更新 → 2. 状态对比 → 3. 捕获快照 → 4. 计算位置 → 5. Canvas绘制 → 6. 完成清理
```

## 快速开始

### 基础用法

```typescript
import { AnimatedGrid, AnimatedGridController } from '../components/AnimatedGrid';
import { AnimatedItem } from '../Framework/Animation/AnimatedGridState';
import { AnimationType } from '../Framework/Animation/ItemTransitionAnimator';

// 1. 定义数据接口（必须包含id字段）
interface MangaItem extends AnimatedItem {
  id: string;
  title: string;
  coverUrl: string;
}

@Component
struct MyPage {
  @State private items: MangaItem[] = [];
  
  // 2. 创建动画控制器
  private gridController: AnimatedGridController<MangaItem> = 
    new AnimatedGridController({
      columns: 3,
      itemWidth: 100,
      itemHeight: 150,
      columnGap: 12,
      rowGap: 12,
      paddingLeft: 16,
      paddingTop: 16
    });

  build() {
    Column() {
      // 3. 使用AnimatedGrid包裹Grid内容
      AnimatedGrid({
        columns: 3,
        itemWidth: 100,
        itemHeight: 150,
        columnGap: 12,
        rowGap: 12,
        gridContent: () => {
          this.buildGridContent();
        }
      })
    }
  }

  @Builder
  buildGridContent() {
    Grid() {
      ForEach(this.items, (item: MangaItem) => {
        GridItem() {
          Column() {
            Image(item.coverUrl)
              .width('100%')
              .aspectRatio(0.7)
            Text(item.title)
          }
          .id(`item_${item.id}`)  // 4. 重要：设置唯一ID
        }
      }, (item: MangaItem) => item.id)
    }
    .columnsTemplate('1fr 1fr 1fr')
    .rowsGap(12)
    .columnsGap(12)
  }

  // 5. 触发动画
  private async updateItemsWithAnimation(newItems: MangaItem[]): Promise<void> {
    this.items = newItems;
    await this.gridController.updateItems(newItems, AnimationType.REFRESH);
  }
}
```

## 动画类型

### AnimationType.ADD - 添加动画
用于新增条目时，新条目淡入并放大，其他条目平移到新位置。

```typescript
// 添加新条目
const newItem = { id: 'new_1', title: '新漫画', coverUrl: '...' };
const newItems = [...this.items, newItem];
this.items = newItems;
await this.gridController.updateItems(newItems, AnimationType.ADD);
```

### AnimationType.REMOVE - 删除动画
用于删除条目时，被删除条目淡出并缩小，其他条目平移填补空位。

```typescript
// 删除条目
const newItems = this.items.filter(item => item.id !== 'remove_id');
this.items = newItems;
await this.gridController.updateItems(newItems, AnimationType.REMOVE);
```

### AnimationType.MOVE - 移动动画
用于条目位置变化时，所有条目平移到新位置。

```typescript
// 移动条目（如排序）
const sorted = [...this.items].sort((a, b) => a.title.localeCompare(b.title));
this.items = sorted;
await this.gridController.updateItems(sorted, AnimationType.MOVE);
```

### AnimationType.REFRESH - 刷新动画
用于完全刷新列表时，自动处理新增、删除和移动的混合场景。

```typescript
// 刷新列表
const refreshedItems = await this.loadDataFromServer();
this.items = refreshedItems;
await this.gridController.updateItems(refreshedItems, AnimationType.REFRESH);
```

## 高级配置

### 自定义动画参数

```typescript
AnimatedGrid({
  // 布局参数
  columns: 3,
  itemWidth: 100,
  itemHeight: 150,
  columnGap: 12,
  rowGap: 12,
  paddingLeft: 16,
  paddingTop: 16,
  
  // 动画参数
  animationDuration: 400,      // 动画时长（毫秒）
  enableFadeIn: true,          // 启用淡入效果
  enableFadeOut: true,         // 启用淡出效果
  enableScale: true,           // 启用缩放效果
  staggerDelay: 30,            // 交错延迟（毫秒）
  
  gridContent: () => {
    this.buildGridContent();
  }
})
```

### 响应式布局支持

```typescript
// 根据屏幕宽度动态调整列数
private calculateColumns(): number {
  const screenWidth = this.getUIContext().getHostContext()
    .resourceManager.getDeviceCapability().screenDensity;
  
  if (screenWidth > 1000) return 5;
  if (screenWidth > 600) return 4;
  return 3;
}

// 更新控制器配置
this.gridController.updateLayoutConfig({
  columns: this.calculateColumns()
});
```

## 实际集成示例

### 在MainMenuPage中集成

```typescript
// 首页最近阅读区域
@Builder
buildRecentReadingWithAnimation() {
  AnimatedGrid({
    columns: this.getRecentReadingColumns(),
    itemWidth: this.getItemWidth(),
    itemHeight: this.getItemHeight(),
    columnGap: 12,
    rowGap: 12,
    paddingLeft: 16,
    paddingTop: 16,
    gridContent: () => {
      Grid() {
        ForEach(this.recentReadingList, (manga: Manga) => {
          GridItem() {
            this.buildMangaCard(manga)
          }
        }, (manga: Manga) => `manga_${manga.id}`)
      }
      .columnsTemplate(this.getColumnsTemplate())
      .rowsGap(12)
      .columnsGap(12)
    }
  })
}

// 刷新时触发动画
private async refreshRecentReading(): Promise<void> {
  const newList = await this.loadRecentReadingList();
  this.recentReadingList = newList;
  await this.recentGridController.updateItems(
    newList.map(m => ({ id: m.id, ...m })),
    AnimationType.REFRESH
  );
}

// 删除时触发动画
private async deleteManga(mangaId: string): Promise<void> {
  await this.dataManager.deleteManga(mangaId);
  const newList = this.recentReadingList.filter(m => m.id !== mangaId);
  this.recentReadingList = newList;
  await this.recentGridController.updateItems(
    newList.map(m => ({ id: m.id, ...m })),
    AnimationType.REMOVE
  );
}
```

### 在书库页面中集成

```typescript
// 书库网格
@Builder
buildLibraryGrid() {
  AnimatedGrid({
    columns: this.libraryColumns,
    itemWidth: this.libraryItemWidth,
    itemHeight: this.libraryItemHeight,
    columnGap: this.responsive_gridGap,
    rowGap: this.responsive_gridGap,
    paddingLeft: 16,
    paddingTop: 16,
    gridContent: () => {
      Grid() {
        ForEach(this.filteredMangaList, (manga: Manga) => {
          GridItem() {
            this.buildMangaGridCard(manga)
          }
        }, (manga: Manga) => manga.id)
      }
      .columnsTemplate(this.getLibraryGridColumnsTemplate())
      .rowsGap(this.responsive_gridGap)
      .columnsGap(this.responsive_gridGap)
    }
  })
}

// 筛选变化时触发动画
private async onFilterChanged(): Promise<void> {
  const filtered = this.applyFilters(this.mangaList);
  this.filteredMangaList = filtered;
  await this.libraryGridController.updateItems(
    filtered.map(m => ({ id: m.id, ...m })),
    AnimationType.REFRESH
  );
}
```

## 性能优化建议

### 1. 快照质量控制

```typescript
// 对于大量条目，降低快照质量以提升性能
const snapshots = await this.snapshotCapture.captureComponents(itemIds, {
  scale: 0.8,  // 降低到80%质量
  waitTime: 30 // 减少等待时间
});
```

### 2. 限制同时动画的条目数量

```typescript
// 只对可见区域的条目进行动画
private getVisibleItemIds(): string[] {
  const visibleItems = this.items.filter((item, index) => {
    return index < 20; // 只动画前20个条目
  });
  return visibleItems.map(item => item.id);
}
```

### 3. 使用防抖避免频繁触发

```typescript
private animationDebounceTimer: number = -1;

private triggerAnimationDebounced(items: MangaItem[]): void {
  if (this.animationDebounceTimer !== -1) {
    clearTimeout(this.animationDebounceTimer);
  }
  
  this.animationDebounceTimer = setTimeout(() => {
    this.gridController.updateItems(items, AnimationType.REFRESH);
  }, 300);
}
```

## 注意事项

1. **必须设置唯一ID**：每个GridItem必须设置唯一的`.id()`属性，格式为`item_${itemId}`
2. **数据接口要求**：条目数据必须实现`AnimatedItem`接口（包含`id`字段）
3. **Canvas层级**：动画期间Canvas层会覆盖在Grid上方，确保不影响用户交互
4. **内存管理**：动画完成后会自动释放PixelMap资源，无需手动管理
5. **异步操作**：`updateItems()`是异步方法，如需等待动画完成再执行后续操作，使用`await`

## 故障排查

### 问题：动画不触发

**原因**：条目没有设置唯一ID或ID格式不正确

**解决**：
```typescript
// 错误
GridItem() {
  this.buildCard(item)
}

// 正确
GridItem() {
  this.buildCard(item)
}
.id(`item_${item.id}`)
```

### 问题：动画卡顿

**原因**：同时动画的条目过多或快照质量过高

**解决**：
- 限制动画条目数量（只动画可见区域）
- 降低快照质量（scale参数）
- 增加staggerDelay以分散动画负载

### 问题：快照捕获失败

**原因**：组件尚未完成渲染或ID不存在

**解决**：
- 增加waitTime参数
- 确保在数据更新后等待一帧再触发动画
- 检查组件ID是否正确设置

## 完整示例代码

参考文件：`entry/src/main/ets/components/AnimatedGridExample.ets`

## API参考

### ItemTransitionAnimator

核心动画引擎类，负责Canvas绘制和动画计算。

**主要方法**：
- `initCanvas(context, width, height)` - 初始化Canvas上下文
- `prepareAnimation(oldPos, newPos, pixelMaps, type)` - 准备动画数据
- `startAnimation(onComplete)` - 开始动画
- `stopAnimation()` - 停止动画

### AnimatedGridState

状态管理类，跟踪条目变化。

**主要方法**：
- `updateItems(newItems, animationType)` - 更新条目列表
- `getCurrentPositions()` - 获取当前位置
- `getPreviousPositions()` - 获取之前位置
- `getAddedItemIds()` - 获取新增条目ID
- `getRemovedItemIds()` - 获取删除条目ID

### SnapshotCapture

快照捕获工具类。

**主要方法**：
- `captureComponent(componentId, options)` - 捕获单个组件
- `captureComponents(componentIds, options)` - 批量捕获
- `releasePixelMaps(pixelMaps)` - 释放资源

### AnimatedGridController

简化版控制器，封装常用操作。

**主要方法**：
- `updateItems(newItems, animationType)` - 更新并触发动画
- `updateLayoutConfig(config)` - 更新布局配置
- `reset()` - 重置状态

## 总结

条目过渡动画系统提供了一套完整的解决方案，用于实现流畅的网格布局动画效果。通过Canvas精确绘制和智能状态管理，可以轻松集成到任何需要动画的场景中，显著提升用户体验。
