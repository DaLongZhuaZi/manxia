# HarmonyOS HdsTitleBar 和导航组件详细文档

## 概述

本文档详细介绍了HarmonyOS中与标题栏相关的组件，包括`HdsNavDestination`、`Navigation`组件的`titleBar`配置，以及相关的动画效果和自定义选项。

## 1. HdsNavDestination 组件

### 1.1 基本信息
- **API版本**: 从API Version 9开始支持
- **安全区避让**: API Version 11开始默认支持安全区避让特性，不需要特殊配置。
- **特殊安全区配置**: `expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])`表示突破系统认非安全区域，包括状态栏、导航栏，允许内容延伸到顶部和底部，即沉浸模式。
- **其他安全区选项**:
  - `expandSafeArea([SafeAreaType.CUTOUT])`：表示突破设备的非安全区域，例如刘海屏或挖孔屏区域。
  - `expandSafeArea([SafeAreaType.KEYBOARD])`：表示突破系统键盘安全区。


### 1.2 核心属性

#### title 属性
```typescript
title(value: string | CustomBuilder | NavDestinationCommonTitle | NavDestinationCustomTitle, options?: NavigationTitleOptions)
```

**参数说明**:
- `value`: 页面标题，支持多种类型
  - `string`: 简单文本标题
  - `CustomBuilder`: 自定义构建器，允许完全自定义标题栏内容
  - `NavDestinationCommonTitle`: 通用标题配置
  - `NavDestinationCustomTitle`: 自定义标题配置
- `options`: 标题栏选项（API 12+）

#### hideTitleBar 属性
```typescript
hideTitleBar(value: boolean)
```
- 控制标题栏的显示/隐藏
- 默认值: `false`

#### backButtonIcon 属性 (API 11+)
```typescript
backButtonIcon(value: ResourceStr | PixelMap | SymbolGlyphModifier)
```
- 自定义返回按钮图标
- 支持资源字符串、像素图和符号字形修饰符

#### menus 属性
```typescript
menus(value: Array<NavigationMenuItem> | CustomBuilder)
```
- 设置页面右上角菜单
- **显示限制**:
  - 竖屏: 最多显示3个图标
  - 横屏: 最多显示5个图标
  - 多余图标自动放入"更多"菜单

### 1.3 标题栏样式配置

#### titleBar 配置示例
```typescript
.titleBar({
  padding: {
    start: LengthMetrics.vp(16),
    end: LengthMetrics.vp(16)
  },
  style: {
    scrollEffectOpts: {
      enableScrollEffect: true,
      scrollEffectType: ScrollEffectType.COMMON_BLUR,
      blurEffectiveStartOffset: LengthMetrics.vp(0),
      blurEffectiveEndOffset: LengthMetrics.vp(56)
    },
    originalStyle: {
      backgroundStyle: {
        backgroundColor: Color.Transparent,
      },
      contentStyle: {
        titleStyle: { 
          mainTitleColor: $r('sys.color.font_primary'),
          subTitleColor: $r('sys.color.font_secondary')
        },
        menuStyle: { 
          backgroundColor: $r('sys.color.comp_background_tertiary'), 
          iconColor: $r('sys.color.icon_primary') 
        },
        backIconStyle: { 
          iconColor: $r('sys.color.icon_primary') 
        }
      }
    }
  }
})
```

## 2. Navigation 组件

### 2.1 显示模式

#### 自适应模式 (NavigationMode.Auto)
- 默认模式
- 页面宽度 ≥ 600vp: 分栏模式
- 页面宽度 < 600vp: 单栏模式

#### 单栏模式 (NavigationMode.Stack)
- 适用于窄屏设备
- 路由跳转时整个页面被替换

#### 分栏模式 (NavigationMode.Split)
- 适用于宽屏设备
- 左右分栏布局
- 路由跳转时只替换右侧子页

### 2.2 标题栏模式

#### Mini模式
- 普通型标题栏
- 用于不需要突出标题的一级页面

#### Full模式
- 强调型标题栏
- 用于需要突出标题的一级页面

### 2.3 菜单栏配置

#### NavigationMenuItem 配置
```typescript
interface NavigationMenuItem {
  value: string;
  icon?: ResourceStr;
  action?: () => void;
}
```

#### 自定义菜单示例
```typescript
menus: [
  {
    value: '搜索',
    icon: $r('app.media.ic_search'),
    action: () => { /* 搜索逻辑 */ }
  },
  {
    value: '设置',
    icon: $r('app.media.ic_settings'),
    action: () => { /* 设置逻辑 */ }
  }
]
```

## 3. 滚动效果配置

### 3.1 滚动模糊效果
```typescript
scrollEffectOpts: {
  enableScrollEffect: true,
  scrollEffectType: ScrollEffectType.COMMON_BLUR,
  blurEffectiveStartOffset: LengthMetrics.vp(0),
  blurEffectiveEndOffset: LengthMetrics.vp(56)
}
```

### 3.2 可用的滚动效果类型
- `ScrollEffectType.COMMON_BLUR`: 通用模糊效果
- `ScrollEffectType.FADE`: 渐隐效果
- 其他系统定义的效果类型

## 4. 动画系统

### 4.1 属性动画接口

#### animateTo (已废弃 - API 19)
- **废弃说明**: 全局`animateTo`方法已在API 19中完全废弃
- **替代方案**: 使用`UIContext.animateTo`

#### 正确的动画使用方式 (API 19+)
```typescript
@Component
struct MyComponent {
  @State animValue: number = 0;
  private uiContext: UIContext | undefined = undefined;
  
  aboutToAppear(): void {
    this.uiContext = this.getUIContext();
    if (!this.uiContext) {
      console.error('获取UIContext失败');
      return;
    }
    
    setTimeout(() => {
      this.startAnimation();
    }, 0);
  }
  
  private startAnimation(): void {
    if (this.uiContext) {
      const animateOptions: AnimateParam = { 
        duration: 300, 
        curve: Curve.EaseOut 
      };
      this.uiContext.animateTo(animateOptions, () => {
        this.animValue = 100; // 修改状态变量
      });
    }
  }
}
```

#### animation 属性动画
```typescript
.animation({
  duration: 300,
  curve: Curve.EaseInOut,
  delay: 0,
  iterations: 1,
  playMode: PlayMode.Normal
})
```

#### keyframeAnimateTo 关键帧动画
```typescript
keyframeAnimateTo({
  delay: 0,
  iterations: 1
}, [
  {
    duration: 300,
    curve: Curve.EaseOut,
    event: () => { this.value1 = 100; }
  },
  {
    duration: 200,
    curve: Curve.EaseIn,
    event: () => { this.value2 = 200; }
  }
]);
```

### 4.2 转场动画

#### 页面转场动画
```typescript
pageTransition() {
  // 页面进入动画
  PageTransitionEnter({ type: RouteType.Push })
    .slide(SlideEffect.Right)
    .duration(300);
    
  // 页面退出动画
  PageTransitionExit({ type: RouteType.Push })
    .slide(SlideEffect.Left)
    .duration(300);
}
```

#### 组件转场动画
```typescript
.transition(
  TransitionEffect.OPACITY
    .animation({ duration: 300, curve: Curve.EaseInOut })
    .combine(
      TransitionEffect.translate({ x: 100, y: 0 })
        .animation({ duration: 300, curve: Curve.EaseOut })
    )
)
```

## 5. 自定义标题栏最佳实践

### 5.1 使用CustomBuilder自定义标题栏
```typescript
@Builder
customTitleBar() {
  Row() {
    // 返回按钮
    Button() {
      Image($r('app.media.ic_back'))
        .width(24)
        .height(24)
        .fillColor($r('sys.color.icon_primary'))
    }
    .type(ButtonType.Circle)
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      // 返回逻辑
    })
    
    // 标题
    Text('自定义标题')
      .fontSize(18)
      .fontWeight(FontWeight.Bold)
      .fontColor($r('sys.color.font_primary'))
      .layoutWeight(1)
      .textAlign(TextAlign.Center)
    
    // 自定义按钮
    Button() {
      Image($r('app.media.ic_more'))
        .width(24)
        .height(24)
        .fillColor($r('sys.color.icon_primary'))
    }
    .type(ButtonType.Circle)
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      // 更多选项逻辑
    })
  }
  .width('100%')
  .height(56)
  .padding({ left: 16, right: 16 })
  .justifyContent(FlexAlign.SpaceBetween)
}

// 在组件中使用
.title(this.customTitleBar)
```

### 5.2 动态标题栏配置
```typescript
@State titleConfig: NavDestinationCustomTitle = {
  height: 56,
  builder: () => {
    this.customTitleBar()
  }
}

// 动态更新标题栏
updateTitleBar() {
  this.titleConfig = {
    height: 64, // 动态调整高度
    builder: () => {
      this.customTitleBar()
    }
  }
}
```

## 6. 安全区域适配

### 6.1 自动安全区避让 (API 11+)
```typescript
// HdsNavDestination 默认配置
.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
```

### 6.2 手动安全区避让
```typescript
@StorageProp('statusBarHeight') statusBarHeight: number = 0;
@StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

// 在布局中应用
.padding({
  top: this.statusBarHeight,
  bottom: this.navigationBarHeight
})
```

## 7. 主题适配

### 7.1 系统颜色资源
```typescript
// 推荐使用系统颜色资源
.fontColor($r('sys.color.font_primary'))
.backgroundColor($r('sys.color.comp_background_primary'))
```

### 7.2 动态主题切换
```typescript
// 监听主题变化
@Watch('onThemeChanged') @StorageProp('currentTheme') currentTheme: string = 'light';

onThemeChanged() {
  // 主题变化处理逻辑
  this.updateColors();
}
```

## 8. 性能优化建议

### 8.1 动画性能
- 优先使用`scale`属性而非`width/height`进行大小动画
- 避免在动画过程中频繁更新状态
- 使用`animateToImmediately`仅在特殊场景下

### 8.2 布局性能
- 避免在标题栏中使用复杂的嵌套布局
- 使用`LazyForEach`处理长列表
- 合理使用`@Builder`减少重复构建

## 9. 常见问题和解决方案

### 9.1 标题栏不显示
**原因**: NavDestination未设置主副标题并且没有返回键时，不显示标题栏
**解决**: 确保设置了title属性或存在返回键

### 9.2 自定义按钮不响应
**原因**: 按钮被其他组件遮挡或点击区域过小
**解决**: 检查zIndex层级和hitTestBehavior设置

### 9.3 动画卡顿
**原因**: 使用了已废弃的animateTo或动画参数不当
**解决**: 使用UIContext.animateTo并优化动画参数

## 10. 项目中的实际应用

### 10.1 MangaDetailPage 实现
```typescript
// 使用HdsNavDestination + 自定义顶部工具栏
HdsNavDestination() {
  Stack() {
    // 背景层
    Column()
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    
    // 内容层
    Scroll() {
      // 页面内容
    }
    
    // 自定义顶部工具栏
    this.buildTopBar()
  }
}
.backgroundColor(Color.Transparent)
```

### 10.2 TestManagementPage 实现
```typescript
// 使用HdsNavDestination + titleBar配置
HdsNavDestination() {
  // 页面内容
}
.titleBar({
  style: {
    scrollEffectOpts: {
      enableScrollEffect: true,
      scrollEffectType: ScrollEffectType.COMMON_BLUR
    }
  }
})
```

## 总结

HarmonyOS的标题栏系统提供了丰富的自定义选项和动画效果。通过合理使用`HdsNavDestination`、`Navigation`组件的`titleBar`配置，以及相关的动画接口，可以创建出既美观又功能丰富的应用界面。在实际开发中，需要注意API版本兼容性、性能优化和主题适配等方面的问题。