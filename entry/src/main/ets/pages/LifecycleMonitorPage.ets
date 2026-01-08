/**
 * 生命周期监控页面
 * 
 * 提供全局任务监控和调试功能
 * 
 * 文件路径: entry/src/main/ets/pages/LifecycleMonitorPage.ets
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { logger } from '../Utils/Logger';
import { LifecycleMonitorPanel } from '../components/LifecycleMonitorPanel';
import { ThemeAwareHelper, ThemeAwareState } from '../Framework/Components/ThemeAware';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { LengthMetrics } from '@kit.ArkUI';

const TAG = 'LifecycleMonitorPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

@ComponentV2
struct LifecycleMonitorPage {
  @Local themeState: ThemeAwareState = new ThemeAwareState();
  @Local fontState: FontAwareState = new FontAwareState();
  @Local appFontFamily: string = 'HarmonyOS Sans';
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private lifecycle = new PageLifecycleManager('LifecycleMonitorPage', { enableDebug: true });
  private componentId: string = 'LifecycleMonitorPage';
  pathStack: NavPathStack = new NavPathStack();
  
  aboutToAppear(): void {
    logger.lifecycle(TAG, 'aboutToAppear');
    
    // 初始化主题
    this.themeManager.getCurrentTheme().then((theme: ThemeType) => {
      this.themeState.currentTheme = theme;
    });
    
    // 监听主题变化
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
      this.themeState.currentTheme = theme;
    });
    FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (newState: FontAwareState) => {
      this.fontState = newState;
      this.appFontFamily = newState.appFontFamily;
    });
  }
  
  aboutToDisappear(): void {
    logger.lifecycle(TAG, 'aboutToDisappear');
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }
  
  build() {
    HdsNavDestination() {
      Stack() {
        // 背景区域
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          
        Column() {
        LifecycleMonitorPanel({ currentTheme: this.themeState.currentTheme })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
      }
    }
    .hideTitleBar(false)
    .mode(NavDestinationMode.STANDARD)
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
          blurEffectiveEndOffset: LengthMetrics.vp(TITLE_BAR_HEIGHT_MINI)
        },
        originalStyle: {
          backgroundStyle: { backgroundColor: Color.Transparent },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { 
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), 
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) 
            }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: this.themeState.currentTheme === ThemeType.DARK ? '#E61A1A1A' : '#E6F5F5F5'
          },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { 
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), 
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) 
            }
          }
        }
      },
      content: {
        title: { mainTitle: '生命周期监控' }
      }
    })
  }
}

export { LifecycleMonitorPage }
