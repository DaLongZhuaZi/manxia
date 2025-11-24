# 欢迎引导系统使用说明

## 概述

欢迎引导系统是为漫匣应用设计的首次启动引导功能，帮助新用户快速了解应用的核心功能。该系统包含以下组件：

1. **WelcomeGuideManager**: 引导管理器，负责存储和管理首次启动标记
2. **WelcomeGuidePage**: 欢迎引导页面，展示引导内容
3. **GuideOverlay**: 可选的引导遮罩组件，用于页面内的高亮引导
4. **SplashPage**: 启动页面，检测首次启动并跳转
5. **MainMenuPage**: 主页面，处理引导跳转参数

## 系统架构

### 1. WelcomeGuideManager

引导管理器使用HarmonyOS的Preferences API持久化存储引导状态。

#### 主要功能：
- **首次启动检测**: `isFirstTimeLaunch()` 和 `shouldShowGuide()`
- **引导步骤管理**: `getCurrentStep()`, `setCurrentStep()`, `nextStep()`
- **状态标记**: `markGuideCompleted()`, `skipGuide()`, `resetGuide()`

#### 引导步骤枚举：
```typescript
enum GuideStep {
  WELCOME = 0,           // 欢迎页
  DATA_IMPORT = 1,       // 数据导入引导
  LOG_EXPORT = 2,        // 日志导出引导
  LIBRARY_INTRO = 3,     // 书库介绍
  COMPLETED = 4          // 完成
}
```

#### 使用示例：
```typescript
import { WelcomeGuideManager } from '../Framework/Managers/WelcomeGuideManager';

const guideManager = WelcomeGuideManager.getInstance();

// 初始化（在应用启动时调用）
await guideManager.initialize();

// 检查是否需要显示引导
if (guideManager.shouldShowGuide()) {
  // 跳转到引导页面
}

// 标记引导完成
await guideManager.markGuideCompleted();

// 重置引导（用于测试）
await guideManager.resetGuide();
```

### 2. WelcomeGuidePage

欢迎引导页面是一个完整的页面组件，展示引导内容并处理用户交互。

#### 引导流程：
1. **欢迎页** → 介绍应用，点击"开始引导"
2. **数据导入引导** → 介绍漫画导入功能，点击"前往导入"跳转到DataManagementPage
3. **日志导出引导** → 介绍日志管理功能，点击"查看日志"跳转到LogManagerPage
4. **书库介绍** → 介绍书库功能，点击"进入书库"完成引导并跳转到书库标签页

#### 页面特性：
- **沉浸式显示**: 遵循项目的沉浸式设计规范
- **流畅动画**: 页面切换和内容过渡都有流畅的动画效果
- **主题适配**: 自动适配当前主题（亮色/暗色模式）
- **跳过功能**: 用户可以随时跳过引导

### 3. GuideOverlay

可选的引导遮罩组件，用于在现有页面上添加高亮引导效果。

#### 使用示例：
```typescript
import { GuideOverlay, HighlightArea, GuideTip } from '../Framework/Components/GuideOverlay';

@State private showGuide: boolean = true;

build() {
  Stack() {
    // 主要内容
    Column() {
      // ...
    }

    // 引导遮罩
    GuideOverlay({
      visible: this.showGuide,
      highlightArea: {
        x: 100,
        y: 200,
        width: 200,
        height: 60,
        borderRadius: 8
      },
      tip: {
        title: '导入漫画',
        message: '点击这里可以导入本地漫画文件',
        position: 'bottom',
        offsetY: 10
      },
      showNextButton: true,
      showSkipButton: true,
      nextButtonText: '下一步',
      skipButtonText: '跳过',
      onNext: () => {
        // 进入下一步引导
      },
      onSkip: () => {
        this.showGuide = false;
      },
      themeState: this.themeState
    })
  }
}
```

## 引导流程详解

### 启动流程

1. **SplashPage 启动**
   - 初始化 WelcomeGuideManager
   - 初始化 ThemeManager
   - 检查是否首次启动

2. **首次启动检测**
   ```typescript
   const shouldShowGuide = this.welcomeGuideManager.shouldShowGuide();
   if (shouldShowGuide) {
     // 跳转到 WelcomeGuidePage
     router.replaceUrl({ url: 'pages/WelcomeGuidePage' });
   } else {
     // 跳转到 MainMenuPage
     router.replaceUrl({ url: 'pages/MainMenuPage' });
   }
   ```

3. **引导页面交互**
   - 用户浏览引导内容
   - 点击"前往导入"跳转到数据管理页面
   - 点击"查看日志"跳转到日志管理页面
   - 点击"进入书库"完成引导

4. **引导完成**
   - 标记引导已完成
   - 跳转到主页面的书库标签页

### 路由参数传递

引导页面通过路由参数与主页面通信：

```typescript
// WelcomeGuidePage 跳转到 MainMenuPage
router.pushUrl({
  url: 'pages/MainMenuPage',
  params: {
    targetPage: 'DataManagementPage',  // 目标页面
    fromGuide: true                     // 标记来自引导
  }
});

// MainMenuPage 处理参数
private handleRouteParams(): void {
  const params = router.getParams();
  this.fromGuide = params['fromGuide'] ?? false;
  this.targetPage = params['targetPage'] ?? '';
  
  if (this.fromGuide && this.targetPage) {
    // 导航到目标页面
    this.pathStack.pushPath({ name: this.targetPage });
  }
}
```

## 测试指南

### 测试首次启动引导

1. **安装应用**
   - 首次安装后启动应用
   - 应该自动显示欢迎引导页面

2. **重置引导状态**（用于测试）
   ```typescript
   // 在任意可访问的地方调用
   const guideManager = WelcomeGuideManager.getInstance();
   await guideManager.initialize();
   await guideManager.resetGuide();
   
   // 重启应用，将再次显示引导
   ```

3. **清除应用数据**
   - 在设备设置中清除应用数据
   - 重新启动应用，将再次显示引导

### 调试技巧

1. **查看日志**
   ```
   Tag: WelcomeGuideManager
   - 初始化状态
   - 引导步骤变化
   - 状态保存/加载
   
   Tag: WelcomeGuidePage
   - 页面生命周期
   - 按钮点击事件
   - 导航跳转
   ```

2. **检查Preferences存储**
   - 存储名称: `welcome_guide_preferences`
   - 关键字段:
     - `is_first_launch`: 是否首次启动
     - `guide_completed`: 引导是否完成
     - `guide_skipped`: 引导是否被跳过
     - `current_guide_step`: 当前引导步骤

## 自定义扩展

### 添加新的引导步骤

1. **更新GuideStep枚举**
   ```typescript
   export enum GuideStep {
     WELCOME = 0,
     DATA_IMPORT = 1,
     LOG_EXPORT = 2,
     LIBRARY_INTRO = 3,
     NEW_FEATURE = 4,        // 新步骤
     COMPLETED = 5           // 更新完成步骤的值
   }
   ```

2. **在WelcomeGuidePage中添加步骤内容**
   ```typescript
   private readonly guideSteps: Map<GuideStep, GuideStepContent> = new Map([
     // ... 现有步骤 ...
     [GuideStep.NEW_FEATURE, {
       title: '新功能标题',
       subtitle: '新功能副标题',
       description: '新功能描述',
       icon: $r('app.media.icon'),
       buttonText: '了解更多',
       showSkip: true
     }]
   ]);
   ```

3. **更新handleNextStep方法**
   ```typescript
   private handleNextStep(): void {
     switch (this.currentStep) {
       // ... 现有case ...
       case GuideStep.NEW_FEATURE:
         // 处理新步骤的逻辑
         break;
     }
   }
   ```

### 自定义引导样式

1. **修改主题颜色**
   - 在 `ResourceMap.ets` 中定义新的颜色
   - 使用 `ThemeAwareHelper.getTestManagementThemedColor()` 获取

2. **调整动画效果**
   - 修改 `startEntranceAnimation()` 方法中的动画参数
   - 调整 duration、curve 等属性

3. **更换图标**
   - 将图标文件放入 `resources/base/media/` 目录
   - 更新 `guideSteps` 中的 icon 字段

## 常见问题

### Q: 如何在开发时禁用引导？
A: 在 SplashPage 中临时注释掉引导检查逻辑：
```typescript
// const shouldShowGuide = this.welcomeGuideManager.shouldShowGuide();
const shouldShowGuide = false; // 强制不显示引导
```

### Q: 如何在生产环境重置某个用户的引导状态？
A: 可以在设置页面添加一个"重置引导"选项：
```typescript
async resetUserGuide(): Promise<void> {
  const guideManager = WelcomeGuideManager.getInstance();
  await guideManager.resetGuide();
  // 提示用户重启应用
}
```

### Q: 引导页面跳转失败怎么办？
A: 
1. 检查 `main_pages.json` 是否包含目标页面
2. 检查路由参数是否正确传递
3. 查看日志中的错误信息

### Q: 如何实现多语言支持？
A: 
1. 在 `resources/base/element/string.json` 中定义字符串资源
2. 使用 `$r('app.string.resource_name')` 引用
3. 添加其他语言的资源文件

## 注意事项

1. **Preferences初始化时机**: 必须在应用上下文可用后才能初始化
2. **页面路由配置**: 所有引导相关的页面必须在 `main_pages.json` 中注册
3. **状态持久化**: 引导状态会持久化保存，清除应用数据才会重置
4. **主题适配**: 所有UI组件都应使用主题颜色，确保亮色/暗色模式的适配
5. **错误处理**: 引导系统的错误不应导致应用崩溃，应有合理的降级处理

## 性能优化建议

1. **延迟加载**: 引导管理器在SplashPage初始化，避免阻塞应用启动
2. **动画优化**: 使用硬件加速的动画属性（opacity、transform）
3. **资源预加载**: 引导页面的图片资源应使用 `syncLoad(true)` 同步加载
4. **内存管理**: 引导完成后及时清理不需要的资源

## 版本历史

- **v1.0.0** (2025-01-07)
  - 初始版本
  - 实现基础引导流程
  - 支持首次启动检测
  - 实现4步引导流程
  - 添加GuideOverlay组件

## 相关文件

- `entry/src/main/ets/Framework/Managers/WelcomeGuideManager.ets`
- `entry/src/main/ets/pages/WelcomeGuidePage.ets`
- `entry/src/main/ets/Framework/Components/GuideOverlay.ets`
- `entry/src/main/ets/pages/SplashPage.ets`
- `entry/src/main/ets/pages/MainMenuPage.ets`
- `entry/src/main/resources/base/profile/main_pages.json`

