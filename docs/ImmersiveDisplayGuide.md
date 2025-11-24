# HarmonyOS NEXT 沉浸式显示完整适配方案

## 概述

本文档提供了基于 HarmonyOS NEXT API 12 的完整沉浸式显示适配方案，结合最新的官方文档和开发最佳实践，实现稳定可靠的沉浸式用户体验。

## 核心特性

### 1. 双重保障策略
- **窗口级配置**：在 `EntryAbility` 中统一设置全屏布局和系统栏属性
- **组件级适配**：在各页面组件中使用 `expandSafeArea` 和 `padding` 确保UI安全

### 2. 系统栏管理
- **透明化处理**：状态栏和导航栏背景透明，内容可见
- **动态高度获取**：实时获取系统栏高度并存储到全局状态
- **持久化存储**：使用 `PersistentStorage` 确保应用重启后数据可用

### 3. 安全区域处理
- **自动扩展**：使用 `expandSafeArea` 让内容扩展到系统栏区域
- **智能填充**：使用动态 `padding` 避免重要UI被系统栏遮挡

## 实现架构

### 1. WindowManager 工具类

```typescript
// src/main/ets/Utils/WindowManager.ets
export class WindowManager {
  // 设置沉浸式全屏显示
  static setupImmersiveDisplay(windowStage: window.WindowStage): void
  
  // 设置系统栏透明属性
  private static setTransparentSystemBar(mainWindow: window.Window): void
  
  // 获取并存储系统栏高度信息
  private static storeSystemBarHeights(mainWindow: window.Window): void
  
  // 设置自定义系统栏颜色
  static setCustomSystemBarColor(...): void
  
  // 隐藏/显示系统栏
  static hideSystemBar(mainWindow: window.Window): void
  static showSystemBar(mainWindow: window.Window): void
}
```

### 2. EntryAbility 集成

```typescript
// src/main/ets/EntryAbility.ets
export default class EntryAbility extends UIAbility {
  onWindowStageCreate(windowStage: window.WindowStage): void {
    // 设置沉浸式显示
    this.setupImmersiveMode(windowStage);
    
    // 请求权限并加载内容
    this.requestPermissionsAndLoadContent(windowStage);
  }
  
  setupImmersiveMode(windowStage: window.WindowStage): void {
    // 使用WindowManager统一处理
    WindowManager.setupImmersiveDisplay(windowStage);
  }
}
```

### 3. 页面组件适配

#### 3.1 根页面 (Index.ets)
```typescript
@Entry
@Component
export struct Index {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  build() {
    Stack() {
      this.CurrentPage()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Black)
    // 扩展到系统栏区域
    .expandSafeArea([SafeAreaType.SYSTEM], 
                   [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
```

#### 3.2 游戏页面 (GamePage.ets)
```typescript
@Component
export struct GamePage {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Canvas(this.canvasContext)
        .width('100%')
        .height('100%')
        // Canvas扩展到系统栏区域
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      
      // UI组件层
      if (this.isEngineReady) {
        InGameHUD({ /* ... */ })
        if (this.showDebugPanel) {
          DebugPanel({ /* ... */ })
        }
      }
    }
    .width('100%')
    .height('100%')
    // 整个页面扩展到系统栏区域
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    // 为UI组件预留安全区域
    .padding({
      top: this.statusBarHeight,
      bottom: this.navigationBarHeight
    })
  }
}
```

#### 3.3 主菜单页面 (MainMenuPage.ets)
```typescript
@Component
export struct MainMenuPage {
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  build() {
    Stack() {
      // 背景图片
      Image($r('app.media.unfinished'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
      
      Column({ space: 20 }) {
        // 菜单内容
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      // 为菜单内容预留安全区域
      .padding({
        top: this.statusBarHeight,
        bottom: this.navigationBarHeight
      })
    }
    .width('100%')
    .height('100%')
    // 扩展到系统栏区域
    .expandSafeArea([SafeAreaType.SYSTEM], 
                   [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
```

## 技术实现要点

### 1. 窗口设置方式

#### 方式一：全屏布局 + 透明系统栏（推荐）
```typescript
// 设置全屏布局
mainWindow.setWindowLayoutFullScreen(true, callback);

// 设置透明系统栏
const systemBarProperties: window.SystemBarProperties = {
  statusBarColor: '#00000000',        // 透明背景
  navigationBarColor: '#00000000',    // 透明背景
  statusBarContentColor: '#ffffff',   // 内容颜色
  navigationBarContentColor: '#ffffff',
  isStatusBarLightIcon: false,        // 图标主题
  isNavigationBarLightIcon: false
};
mainWindow.setWindowSystemBarProperties(systemBarProperties, callback);
```

#### 方式二：隐藏系统栏（完全沉浸式）
```typescript
// 完全隐藏系统栏
const names: Array<'status' | 'navigation'> = [];
mainWindow.setWindowSystemBarEnable(names, callback);
```

### 2. 高度获取与存储

```typescript
// 获取系统栏高度
const statusBarArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
const navigationArea = mainWindow.getWindowAvoidArea(window.AvoidAreaType.TYPE_NAVIGATION_INDICATOR);

// 转换为vp单位
const statusBarHeight = px2vp(statusBarArea.topRect.height);
const navigationBarHeight = px2vp(navigationArea.bottomRect.height);

// 存储到全局状态
AppStorage.setOrCreate('statusBarHeight', statusBarHeight);
AppStorage.setOrCreate('navigationBarHeight', navigationBarHeight);

// 持久化存储
PersistentStorage.persistProp('statusBarHeight', statusBarHeight);
PersistentStorage.persistProp('navigationBarHeight', navigationBarHeight);
```

### 3. 组件级适配

```typescript
// 在组件中获取高度
@StorageProp('statusBarHeight') statusBarHeight: number = 0;
@StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

// 扩展到安全区域
.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

// 预留安全区域
.padding({
  top: this.statusBarHeight,
  bottom: this.navigationBarHeight
})
```

## 最佳实践

### 1. 分层设计
- **背景层**：扩展到全屏，提供沉浸式背景
- **内容层**：添加安全区域填充，确保可见性
- **交互层**：考虑手势区域，避免误触

### 2. 动态适配
- **设备差异**：不同设备的系统栏高度可能不同
- **方向变化**：横竖屏切换时重新获取高度
- **系统更新**：兼容不同版本的API变化

### 3. 性能优化
- **同步获取**：使用 `getMainWindowSync()` 提高性能
- **缓存机制**：避免重复计算和设置
- **按需更新**：只在必要时更新UI状态

### 4. 错误处理
- **回调检查**：检查所有窗口API的错误回调
- **兜底方案**：提供默认值和降级处理
- **日志记录**：详细记录设置过程和错误信息

## 常见问题与解决方案

### 1. 状态栏内容被遮挡
**问题**：设置沉浸式后，应用内容被状态栏遮挡
**解决**：使用 `padding` 为内容预留状态栏高度的空间

### 2. 导航栏手势冲突
**问题**：底部导航栏手势与应用手势冲突
**解决**：为底部交互元素预留导航栏高度的安全距离

### 3. 不同设备适配问题
**问题**：在不同设备上显示效果不一致
**解决**：动态获取系统栏高度，避免硬编码数值

### 4. 应用重启后设置丢失
**问题**：应用重启后沉浸式设置失效
**解决**：使用 `PersistentStorage` 持久化存储设置

## 测试验证

### 1. 功能测试
- [ ] 状态栏透明效果正常
- [ ] 导航栏透明效果正常
- [ ] 内容不被系统栏遮挡
- [ ] 手势操作正常

### 2. 兼容性测试
- [ ] 不同设备型号
- [ ] 不同屏幕尺寸
- [ ] 横竖屏切换
- [ ] 系统版本兼容

### 3. 性能测试
- [ ] 启动时间影响
- [ ] 内存使用情况
- [ ] 渲染性能影响

## 总结

本方案通过以下关键技术实现了稳定可靠的沉浸式显示效果：

1. **统一管理**：使用 `WindowManager` 工具类统一处理窗口设置
2. **双重保障**：窗口级设置 + 组件级适配确保效果稳定
3. **动态适配**：实时获取系统栏高度，支持不同设备
4. **持久化存储**：确保应用重启后设置仍然有效
5. **错误处理**：完善的错误处理和日志记录机制

该方案已在项目中成功实施，可以作为 HarmonyOS NEXT 沉浸式显示开发的标准参考。