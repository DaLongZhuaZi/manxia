# 全局背景层使用指南

## 概述
`GlobalBackgroundLayer` 组件用于在所有页面显示自定义主题的背景图片。当用户在主题设置中保存并应用自定义主题后，该组件会自动显示用户选择的背景图片。

## 使用方法

### 1. 导入组件
```typescript
import { GlobalBackgroundLayer } from '../Framework/Components/GlobalBackgroundLayer';
```

### 2. 在页面中使用

在任何页面的 `build()` 方法中，使用 `Stack` 布局，将 `GlobalBackgroundLayer` 作为最底层：

```typescript
build() {
  NavDestination() {
    Stack({ alignContent: Alignment.TopStart }) {
      // 背景层 - 自动显示自定义主题背景或默认背景色
      GlobalBackgroundLayer({ defaultBackgroundColor: $r('app.color.background') })

      // 内容层 - 你的页面内容
      Column() {
        // ... 你的页面UI
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarHeight, bottom: this.navigationBarHeight })
    }
    .width('100%')
    .height('100%')
  }
  .hideTitleBar(true)
  .onReady((context: NavDestinationContext) => {
    this.pathStack = context.pathStack;
  })
}
```

### 3. 完整示例

```typescript
import { GlobalBackgroundLayer } from '../Framework/Components/GlobalBackgroundLayer';

@Component
export struct MyPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;

  build() {
    NavDestination() {
      Stack({ alignContent: Alignment.TopStart }) {
        // 🎨 背景层
        GlobalBackgroundLayer({ defaultBackgroundColor: $r('app.color.background') })

        // 📄 内容层
        Column() {
          // 顶部标题栏
          Row() {
            Button() {
              Image($r('app.media.ic_arrow_back'))
                .width(24)
                .height(24)
                .fillColor($r('app.color.text_primary'))
            }
            .onClick(() => this.pathStack.pop())

            Text('页面标题')
              .fontSize(20)
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')
          .height(56)

          // 滚动内容
          Scroll() {
            Column() {
              // 你的页面内容
              Text('页面内容')
            }
            .padding(16)
          }
          .layoutWeight(1)
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.statusBarHeight, bottom: this.navigationBarHeight })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
  }
}
```

## 工作原理

1. **监听全局状态**：组件使用 `@StorageProp` 监听全局的背景图片路径和自定义主题激活状态
2. **自动切换**：
   - 当自定义主题激活且有背景图片时，显示背景图片
   - 否则，显示默认背景色
3. **沉浸式显示**：背景层使用 `expandSafeArea` 扩展到状态栏和导航栏区域，实现真正的全屏效果

## 关键特性

- ✅ 自动响应自定义主题变化
- ✅ 完全沉浸式显示（扩展到系统栏）
- ✅ 背景图片加载错误处理
- ✅ 支持自定义默认背景色
- ✅ 零配置，开箱即用

## 注意事项

1. **性能优化**：背景图片使用 `objectFit: ImageFit.Cover` 自动裁剪适配
2. **内容层透明度**：如果需要看到背景图片，确保内容层使用半透明背景或透明背景
3. **文字可读性**：在使用自定义背景时，建议为文字添加阴影或半透明背景以确保可读性
4. **主色调**：可以使用 `@StorageProp(CUSTOM_THEME_KEYS.PRIMARY_COLOR)` 获取主题主色调用于UI元素

## 获取主色调示例

```typescript
import { CUSTOM_THEME_KEYS } from '../Framework/Managers/ThemeManager';

@Component
export struct MyComponent {
  // 获取自定义主题的主色调
  @StorageProp(CUSTOM_THEME_KEYS.PRIMARY_COLOR) themePrimaryColor: string = '';
  
  build() {
    Column() {
      // 使用主色调作为强调色
      Button('操作按钮')
        .backgroundColor(this.themePrimaryColor || $r('app.color.accent_primary'))
      
      // 使用主色调作为图标颜色
      Image($r('app.media.icon'))
        .fillColor(this.themePrimaryColor || $r('app.color.accent_primary'))
    }
  }
}
```

## 清除自定义主题

用户可以通过以下方式清除自定义主题：

```typescript
import { ThemeManager } from '../Framework/Managers/ThemeManager';

const themeManager = ThemeManager.getInstance();
await themeManager.clearCustomTheme();
```

清除后，所有页面会自动恢复到默认背景。

