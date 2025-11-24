# HarmonyOS Next 沉浸式设计指南

## 概述

本指南详细说明了在 HarmonyOS Next 项目中实现完全沉浸式显示的标准方法和最佳实践。所有页面组件都必须遵循此设计规范，确保游戏界面的一致性和现代化体验。

## 核心原理

### 1. 沉浸式显示的实现方式

- **EntryAbility 配置**：在应用启动时通过 `setImmersiveModeEnabledState(true)` 开启沉浸式模式
- **组件级扩展**：使用 `expandSafeArea` 将背景元素扩展到系统栏区域
- **内容安全区域**：通过 `padding` 确保内容不被状态栏和导航栏遮挡

### 2. 双层布局设计

```typescript
Stack() {
  // 背景层 - 扩展到系统栏区域
  Column()
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

  // 内容层 - 避开系统栏
  Column() {
    // 页面内容
  }
  .padding({
    top: this.statusBarHeight,
    bottom: this.navigationBarHeight
  })
}
```

## 实现步骤

### 步骤 1：EntryAbility 配置

在 `EntryAbility.ets` 中配置沉浸式模式：

```typescript
private async setupImmersiveMode(windowStage: window.WindowStage): Promise<void> {
  try {
    // 获取主窗口并开启沉浸式布局模式
    const mainWindow = windowStage.getMainWindow();
    await mainWindow.setImmersiveModeEnabledState(true);
    logger.info('EntryAbility', '✅ 沉浸式模式已开启');
    
    // 保留原有的窗口管理器配置作为备用
    WindowManager.setupImmersiveDisplay(windowStage);
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    logger.error('EntryAbility', '❌ 沉浸式模式配置失败', errorMessage);
  }
}
```

### 步骤 2：页面组件状态声明

每个页面组件必须声明沉浸式状态属性：

```typescript
@Component
export struct YourPage {
  // [必需] 沉浸式显示相关状态
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  // 其他组件状态...
}
```

### 步骤 3：实现双层布局

```typescript
build() {
  Stack() {
    // 背景层 - 扩展到系统栏区域
    Column()
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.background_primary'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

    // 内容层 - 避开系统栏
    Column({ space: 20 }) {
      // 页面具体内容
      Text('页面标题')
        .fontSize(32)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.text_primary'))
      
      // 其他UI元素...
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .padding({
      top: this.statusBarHeight,
      bottom: this.navigationBarHeight
    })
  }
  .width('100%')
  .height('100%')
}
```

## 特殊场景处理

### 1. 背景图片的沉浸式处理

```typescript
// 背景图片也需要扩展到系统栏区域
Image($r('app.media.background'))
  .width('100%')
  .height('100%')
  .objectFit(ImageFit.Cover)
  .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
```

### 2. 复杂布局的安全区域处理

```typescript
// 对于复杂的布局，可以在不同层级设置不同的padding
Column() {
  // 顶部内容区域
  Row() {
    // 内容
  }
  .padding({ top: this.statusBarHeight })
  
  // 中间内容区域（无需padding）
  Column() {
    // 内容
  }
  
  // 底部内容区域
  Row() {
    // 内容
  }
  .padding({ bottom: this.navigationBarHeight })
}
```

### 3. 游戏页面的特殊处理

```typescript
// 游戏页面需要确保Canvas和HUD都正确处理沉浸式显示
Stack({ alignContent: Alignment.TopStart }) {
  // 背景层
  Column()
    .width('100%')
    .height('100%')
    .backgroundColor('#2d472c')

  // Canvas层 - 游戏渲染画布
  Canvas(this.canvasContext)
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)

  // UI层 - HUD和调试面板
  // 这些组件需要根据具体需求设置padding
}
.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
.padding({
  top: this.statusBarHeight,
  bottom: this.navigationBarHeight
})
```

## 最佳实践

### 1. 颜色使用规范

- 使用应用颜色资源：`$r('app.color.text_primary')`、`$r('app.color.background_secondary')` 等
- 避免硬编码颜色值，支持主题切换

### 2. 布局一致性

- 所有页面都使用相同的沉浸式布局结构
- 保持内容层的padding设置一致
- 确保背景层正确扩展到系统栏区域

### 3. 性能优化

- 避免在padding计算中使用复杂表达式
- 合理使用@StorageProp避免不必要的状态更新
- 确保expandSafeArea只在必要的组件上使用

### 4. 调试和测试

- 在不同设备上测试沉浸式效果
- 检查状态栏和导航栏高度的正确获取
- 验证内容不被系统栏遮挡

## 常见问题

### Q: 为什么内容仍然被状态栏遮挡？
A: 检查是否正确设置了内容层的padding，确保使用了正确的statusBarHeight值。

### Q: 背景没有扩展到系统栏区域？
A: 确保背景元素使用了expandSafeArea属性，并且设置了正确的SafeAreaType和SafeAreaEdge。

### Q: 在某些设备上沉浸式效果不一致？
A: 检查EntryAbility中的沉浸式模式配置，确保setImmersiveModeEnabledState调用成功。

## 代码模板

### 标准页面组件模板

```typescript
import { logger } from '../Utils/Logger';

@Component
export struct TemplatePage {
  // [必需] 沉浸式显示相关状态
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  aboutToAppear() {
    logger.lifecycle('TemplatePage', '页面即将显示');
  }

  build() {
    Stack() {
      // 背景层 - 扩展到系统栏区域
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.background_primary'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

      // 内容层 - 避开系统栏
      Column({ space: 20 }) {
        Text('页面标题')
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))

        // 添加其他UI元素...
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .padding({
        top: this.statusBarHeight,
        bottom: this.navigationBarHeight
      })
    }
    .width('100%')
    .height('100%')
  }
}
```

## 总结

遵循本指南的沉浸式设计规范，可以确保：

1. **一致的用户体验**：所有页面都具有统一的沉浸式显示效果
2. **内容安全性**：重要内容不会被系统栏遮挡
3. **现代化界面**：充分利用屏幕空间，提供沉浸式游戏体验
4. **兼容性保证**：在不同设备和系统版本上都能正常工作

请确保所有新创建的页面组件都严格遵循此设计规范。