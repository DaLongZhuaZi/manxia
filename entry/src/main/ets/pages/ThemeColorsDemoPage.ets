/**
 * 主题色系统演示页面
 * 
 * 展示新的统一主题色系统 (AppColors / ThemeColorState) 的使用方式
 * 可作为其他页面迁移的参考
 */

import { ThemeColorState, ThemeColorManager, createThemeColors, AppColors, ColorRole } from '../Framework/Theme';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { logger } from '../Utils/Logger';

const TAG = 'ThemeColorsDemoPage';

@Component
export struct ThemeColorsDemoPage {
  // 响应式主题色状态 - 主题切换时自动更新
  @State colors: ThemeColorState = createThemeColors();
  
  // 导航栈
  @State pathStack: NavPathStack = new NavPathStack();
  
  // 状态栏高度
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;

  aboutToAppear(): void {
    logger.info(TAG, 'aboutToAppear');
    
    // 注册主题变化监听 - 主题切换时自动更新 colors
    ThemeColorManager.register(this.colors, (newColors) => {
      this.colors = newColors;
      logger.info(TAG, `主题已切换: ${newColors.isDark ? '深色' : '浅色'}`);
    });
  }

  aboutToDisappear(): void {
    logger.info(TAG, 'aboutToDisappear');
    
    // 取消注册
    ThemeColorManager.unregister(this.colors);
  }

  build() {
    NavDestination() {
      Scroll() {
        Column({ space: 16 }) {
          // 标题区域
          this.buildHeader()
          
          // 主色系展示
          this.buildPrimarySection()
          
          // 表面色系展示
          this.buildSurfaceSection()
          
          // 文字层级展示
          this.buildTextSection()
          
          // 按钮展示
          this.buildButtonSection()
          
          // 状态色展示
          this.buildStatusSection()
          
          // 主题切换按钮
          this.buildThemeToggle()
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 16, bottom: 32 })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.colors.background)
      .scrollBar(BarState.Off)
    }
    .title('主题色系统演示')
    .backgroundColor(this.colors.background)
  }

  @Builder
  buildHeader() {
    Column({ space: 8 }) {
      Text('统一主题色系统')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.colors.textPrimary)
      
      Text('基于 Material Design 3 的语义化颜色角色')
        .fontSize(14)
        .fontColor(this.colors.textSecondary)
      
      Text(`当前主题: ${this.colors.isDark ? '深色模式' : '浅色模式'}`)
        .fontSize(12)
        .fontColor(this.colors.textTertiary)
        .padding({ top: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding({ bottom: 16 })
  }

  @Builder
  buildPrimarySection() {
    Column({ space: 12 }) {
      Text('主色系 (Primary)')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.colors.textPrimary)
      
      Row({ space: 12 }) {
        // Primary
        Column({ space: 4 }) {
          Row()
            .width(60)
            .height(60)
            .backgroundColor(this.colors.primary)
            .borderRadius(8)
          Text('primary')
            .fontSize(10)
            .fontColor(this.colors.textSecondary)
        }
        
        // On Primary
        Column({ space: 4 }) {
          Row() {
            Text('Aa')
              .fontSize(20)
              .fontColor(this.colors.onPrimary)
          }
          .width(60)
          .height(60)
          .backgroundColor(this.colors.primary)
          .borderRadius(8)
          .justifyContent(FlexAlign.Center)
          
          Text('onPrimary')
            .fontSize(10)
            .fontColor(this.colors.textSecondary)
        }
        
        // Primary Container
        Column({ space: 4 }) {
          Row()
            .width(60)
            .height(60)
            .backgroundColor(this.colors.primaryContainer)
            .borderRadius(8)
          Text('container')
            .fontSize(10)
            .fontColor(this.colors.textSecondary)
        }
        
        // Secondary
        Column({ space: 4 }) {
          Row()
            .width(60)
            .height(60)
            .backgroundColor(this.colors.secondary)
            .borderRadius(8)
          Text('secondary')
            .fontSize(10)
            .fontColor(this.colors.textSecondary)
        }
        
        // Tertiary
        Column({ space: 4 }) {
          Row()
            .width(60)
            .height(60)
            .backgroundColor(this.colors.tertiary)
            .borderRadius(8)
          Text('tertiary')
            .fontSize(10)
            .fontColor(this.colors.textSecondary)
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.colors.surface)
    .borderRadius(12)
  }

  @Builder
  buildSurfaceSection() {
    Column({ space: 12 }) {
      Text('表面色系 (Surface)')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.colors.textPrimary)
      
      Column({ space: 8 }) {
        // Surface 层级展示
        Row({ space: 8 }) {
          Column({ space: 4 }) {
            Row()
              .width('100%')
              .height(40)
              .backgroundColor(this.colors.surfaceContainerLow)
              .borderRadius(6)
            Text('Low')
              .fontSize(10)
              .fontColor(this.colors.textTertiary)
          }
          .layoutWeight(1)
          
          Column({ space: 4 }) {
            Row()
              .width('100%')
              .height(40)
              .backgroundColor(this.colors.surfaceContainer)
              .borderRadius(6)
            Text('Container')
              .fontSize(10)
              .fontColor(this.colors.textTertiary)
          }
          .layoutWeight(1)
          
          Column({ space: 4 }) {
            Row()
              .width('100%')
              .height(40)
              .backgroundColor(this.colors.surfaceContainerHigh)
              .borderRadius(6)
            Text('High')
              .fontSize(10)
              .fontColor(this.colors.textTertiary)
          }
          .layoutWeight(1)
          
          Column({ space: 4 }) {
            Row()
              .width('100%')
              .height(40)
              .backgroundColor(this.colors.surfaceContainerHighest)
              .borderRadius(6)
            Text('Highest')
              .fontSize(10)
              .fontColor(this.colors.textTertiary)
          }
          .layoutWeight(1)
        }
        .width('100%')
        
        // 边框和分割线
        Row({ space: 8 }) {
          Column({ space: 4 }) {
            Row()
              .width('100%')
              .height(40)
              .backgroundColor(this.colors.surface)
              .border({ width: 2, color: this.colors.outline })
              .borderRadius(6)
            Text('outline')
              .fontSize(10)
              .fontColor(this.colors.textTertiary)
          }
          .layoutWeight(1)
          
          Column({ space: 4 }) {
            Row()
              .width('100%')
              .height(40)
              .backgroundColor(this.colors.surface)
              .border({ width: 1, color: this.colors.outlineVariant })
              .borderRadius(6)
            Text('outlineVariant')
              .fontSize(10)
              .fontColor(this.colors.textTertiary)
          }
          .layoutWeight(1)
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.colors.surface)
    .borderRadius(12)
  }

  @Builder
  buildTextSection() {
    Column({ space: 12 }) {
      Text('文字层级 (Text Hierarchy)')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.colors.textPrimary)
      
      Column({ space: 8 }) {
        Row({ space: 12 }) {
          Text('Primary')
            .fontSize(14)
            .fontColor(this.colors.textPrimary)
            .layoutWeight(1)
          Text('标题、重要内容')
            .fontSize(12)
            .fontColor(this.colors.textTertiary)
        }
        
        Divider()
          .color(this.colors.divider)
        
        Row({ space: 12 }) {
          Text('Secondary')
            .fontSize(14)
            .fontColor(this.colors.textSecondary)
            .layoutWeight(1)
          Text('正文、描述')
            .fontSize(12)
            .fontColor(this.colors.textTertiary)
        }
        
        Divider()
          .color(this.colors.divider)
        
        Row({ space: 12 }) {
          Text('Tertiary')
            .fontSize(14)
            .fontColor(this.colors.textTertiary)
            .layoutWeight(1)
          Text('辅助信息')
            .fontSize(12)
            .fontColor(this.colors.textTertiary)
        }
        
        Divider()
          .color(this.colors.divider)
        
        Row({ space: 12 }) {
          Text('Disabled')
            .fontSize(14)
            .fontColor(this.colors.textDisabled)
            .layoutWeight(1)
          Text('禁用状态')
            .fontSize(12)
            .fontColor(this.colors.textTertiary)
        }
        
        Divider()
          .color(this.colors.divider)
        
        Row({ space: 12 }) {
          Text('Hint / Placeholder')
            .fontSize(14)
            .fontColor(this.colors.textHint)
            .layoutWeight(1)
          Text('提示文字')
            .fontSize(12)
            .fontColor(this.colors.textTertiary)
        }
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.colors.surface)
    .borderRadius(12)
  }

  @Builder
  buildButtonSection() {
    Column({ space: 12 }) {
      Text('按钮样式 (Buttons)')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.colors.textPrimary)
      
      Row({ space: 12 }) {
        // Primary Button
        Button('主要按钮')
          .backgroundColor(this.colors.buttonPrimary)
          .fontColor(this.colors.buttonPrimaryText)
          .fontSize(14)
          .height(40)
          .borderRadius(20)
        
        // Secondary Button
        Button('次要按钮')
          .backgroundColor(this.colors.buttonSecondary)
          .fontColor(this.colors.buttonSecondaryText)
          .fontSize(14)
          .height(40)
          .borderRadius(20)
        
        // Disabled Button
        Button('禁用按钮')
          .backgroundColor(this.colors.buttonDisabled)
          .fontColor(this.colors.buttonDisabledText)
          .fontSize(14)
          .height(40)
          .borderRadius(20)
          .enabled(false)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      
      // Outlined Button
      Row({ space: 12 }) {
        Button('边框按钮')
          .backgroundColor(Color.Transparent)
          .fontColor(this.colors.primary)
          .fontSize(14)
          .height(40)
          .borderRadius(20)
          .border({ width: 1, color: this.colors.outline })
        
        // Text Button
        Button('文字按钮')
          .backgroundColor(Color.Transparent)
          .fontColor(this.colors.primary)
          .fontSize(14)
          .height(40)
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.colors.surface)
    .borderRadius(12)
  }

  @Builder
  buildStatusSection() {
    Column({ space: 12 }) {
      Text('状态色 (Status Colors)')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.colors.textPrimary)
      
      Row({ space: 12 }) {
        // Success
        Column({ space: 4 }) {
          Row() {
            Text('成功')
              .fontSize(12)
              .fontColor(this.colors.onSuccess)
          }
          .width(60)
          .height(36)
          .backgroundColor(this.colors.success)
          .borderRadius(6)
          .justifyContent(FlexAlign.Center)
          
          Text('success')
            .fontSize(10)
            .fontColor(this.colors.textTertiary)
        }
        
        // Warning
        Column({ space: 4 }) {
          Row() {
            Text('警告')
              .fontSize(12)
              .fontColor(this.colors.onWarning)
          }
          .width(60)
          .height(36)
          .backgroundColor(this.colors.warning)
          .borderRadius(6)
          .justifyContent(FlexAlign.Center)
          
          Text('warning')
            .fontSize(10)
            .fontColor(this.colors.textTertiary)
        }
        
        // Error
        Column({ space: 4 }) {
          Row() {
            Text('错误')
              .fontSize(12)
              .fontColor(this.colors.onError)
          }
          .width(60)
          .height(36)
          .backgroundColor(this.colors.error)
          .borderRadius(6)
          .justifyContent(FlexAlign.Center)
          
          Text('error')
            .fontSize(10)
            .fontColor(this.colors.textTertiary)
        }
        
        // Info
        Column({ space: 4 }) {
          Row() {
            Text('信息')
              .fontSize(12)
              .fontColor(this.colors.onInfo)
          }
          .width(60)
          .height(36)
          .backgroundColor(this.colors.info)
          .borderRadius(6)
          .justifyContent(FlexAlign.Center)
          
          Text('info')
            .fontSize(10)
            .fontColor(this.colors.textTertiary)
        }
      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.colors.surface)
    .borderRadius(12)
  }

  @Builder
  buildThemeToggle() {
    Column({ space: 12 }) {
      Text('主题切换')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.colors.textPrimary)
      
      Row({ space: 12 }) {
        Button('浅色模式')
          .backgroundColor(this.colors.isDark ? this.colors.buttonSecondary : this.colors.buttonPrimary)
          .fontColor(this.colors.isDark ? this.colors.buttonSecondaryText : this.colors.buttonPrimaryText)
          .fontSize(14)
          .height(44)
          .layoutWeight(1)
          .borderRadius(22)
          .onClick(() => {
            ThemeManager.getInstance().setTheme(ThemeType.LIGHT);
          })
        
        Button('深色模式')
          .backgroundColor(this.colors.isDark ? this.colors.buttonPrimary : this.colors.buttonSecondary)
          .fontColor(this.colors.isDark ? this.colors.buttonPrimaryText : this.colors.buttonSecondaryText)
          .fontSize(14)
          .height(44)
          .layoutWeight(1)
          .borderRadius(22)
          .onClick(() => {
            ThemeManager.getInstance().setTheme(ThemeType.DARK);
          })
        
        Button('跟随系统')
          .backgroundColor(this.colors.buttonSecondary)
          .fontColor(this.colors.buttonSecondaryText)
          .fontSize(14)
          .height(44)
          .layoutWeight(1)
          .borderRadius(22)
          .onClick(() => {
            ThemeManager.getInstance().setTheme(ThemeType.AUTO);
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.colors.surface)
    .borderRadius(12)
  }
}
