/**
 * 内容重复检测设置子页面
 * 配置重复检测的开关、阈值、范围和匹配权重
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from 'manxia_theme/src/main/ets/Framework/Components/FontAware';
import { ISettingsManagerFacade, SettingsManagerHolder } from 'manxia_core/src/main/ets/Framework/Contracts/ISettingsManagerFacade';
import { SettingKeys } from 'manxia_core/src/main/ets/Framework/Contracts/SettingKeys';
// OLD: ../../Framework/Managers/SettingsManager';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SettingsSearchSupport } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsSearchSupport';
import { SettingsPanelSurfaceHelper } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPanelSurfaceHelper';
import { SharedPageBackgroundLayer } from 'manxia_theme/src/main/ets/Framework/Components/SharedPageBackgroundLayer';
import { GlobalBackgroundLayerMode } from 'manxia_theme/src/main/ets/Framework/Components/GlobalBackgroundLayer';
import { SettingsImmersiveTitleBar } from './SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageTitleBarManager';

const TAG = 'DuplicateDetectionSettingsSubPage';

@Component
export struct DuplicateDetectionSettingsSubPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  private scroller: Scroller = new Scroller();

  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private settingsManager: ISettingsManagerFacade = SettingsManagerHolder.get();
  private componentId: string = 'DuplicateDetectionSettingsSubPage';

  // 设置状态
  @State duplicateDetectionEnabled: boolean = false;
  @State detectionThreshold: number = 50; // 显示为百分比 10~90
  @State detectionScope: string = 'same_type'; // same_type | all_types
  @State titleWeight: number = 70; // 显示为百分比 10~90

  // 搜索高亮
  @State private activeSearchAnchorId: string = '';
  @State private searchHighlightPulse: boolean = false;
  private searchHighlightPulseTimer: number = -1;
  private searchHighlightClearTimer: number = -1;

  private loadSettings(): void {
    try {
      this.duplicateDetectionEnabled = this.settingsManager.getBoolean(
        SettingKeys.DUPLICATE_DETECTION_ENABLED,
        false
      );
      this.detectionThreshold = Math.round(this.settingsManager.getNumber(
        SettingKeys.DUPLICATE_DETECTION_THRESHOLD,
        0.5
      ) * 100);
      this.detectionScope = this.settingsManager.getString(
        SettingKeys.DUPLICATE_DETECTION_SCOPE,
        'same_type'
      );
      this.titleWeight = Math.round(this.settingsManager.getNumber(
        SettingKeys.DUPLICATE_DETECTION_TITLE_WEIGHT,
        0.7
      ) * 100);
    } catch (error) {
      logger.error(TAG, `加载设置失败: ${String(error)}`);
    }
  }

  private async saveBooleanSetting(key: string, value: boolean): Promise<void> {
    await this.settingsManager.setBoolean(key, value);
    this.settingsManager.syncToAppStorage();
  }

  private async saveNumberSetting(key: string, value: number): Promise<void> {
    await this.settingsManager.setNumber(key, value);
  }

  private async saveStringSetting(key: string, value: string): Promise<void> {
    await this.settingsManager.setString(key, value);
  }

  private applyPendingSearchTarget(): void {
    const target = SettingsSearchSupport.consumePendingTarget('DuplicateDetectionSettingsSubPage');
    if (!target) {
      return;
    }
    SettingsSearchSupport.activateHighlight(this, target.anchorId);
    const offset = Math.max(0, target.scrollOffset);
    logger.info(TAG, `应用设置搜索定位: id=${target.id}, offset=${offset}`);
    setTimeout(() => {
      try {
        this.scroller.scrollTo({ xOffset: 0, yOffset: offset, animation: { duration: 360 } });
      } catch (error) {
        logger.warn(TAG, `滚动到设置搜索目标失败: ${String(error)}`);
      }
    }, 140);
  }

  @Builder
  buildDetectionRules() {
    Column({ space: 16 }) {
      Text('检测规则')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      // 开关
      Row() {
        Column({ space: 4 }) {
          Text('启用重复检测')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          Text('添加内容到书库前自动检测重复')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .alignItems(HorizontalAlign.Start)

        Blank()
        Toggle({ type: ToggleType.Switch, isOn: this.duplicateDetectionEnabled })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .onChange(async (isOn: boolean) => {
            this.duplicateDetectionEnabled = isOn;
            await this.saveBooleanSetting(SettingKeys.DUPLICATE_DETECTION_ENABLED, isOn);
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      if (this.duplicateDetectionEnabled) {
        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
          .margin({ top: 4, bottom: 4 })

        // 阈值滑块
        Column({ space: 8 }) {
          Row() {
            Text('相似度阈值')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Blank()
            Text(`${this.detectionThreshold}%`)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          }
          .width('100%')

          Text('相似度达到此百分比时提示重复')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .alignSelf(ItemAlign.Start)

          Slider({
            value: this.detectionThreshold,
            min: 10,
            max: 90,
            step: 5,
            style: SliderStyle.InSet
          })
            .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .trackColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onChange(async (value: number) => {
              this.detectionThreshold = Math.round(value);
              await this.saveNumberSetting(SettingKeys.DUPLICATE_DETECTION_THRESHOLD, this.detectionThreshold / 100.0);
            })
        }
        .width('100%')
        .padding({ left: 8 })

        Divider()
          .color(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
          .margin({ top: 4, bottom: 4 })

        // 检测范围
        Column({ space: 8 }) {
          Text('检测范围')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .alignSelf(ItemAlign.Start)

          Text('选择在哪些内容类型之间检测重复')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .alignSelf(ItemAlign.Start)

          Row({ space: 12 }) {
            Button('仅同类型')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .height(36)
              .layoutWeight(1)
              .borderRadius(18)
              .backgroundColor(this.detectionScope === 'same_type'
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .fontColor(this.detectionScope === 'same_type'
                ? Color.White
                : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .onClick(async () => {
                this.detectionScope = 'same_type';
                await this.saveStringSetting(SettingKeys.DUPLICATE_DETECTION_SCOPE, 'same_type');
              })

            Button('跨类型')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .height(36)
              .layoutWeight(1)
              .borderRadius(18)
              .backgroundColor(this.detectionScope === 'all_types'
                ? ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme)
                : ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
              .fontColor(this.detectionScope === 'all_types'
                ? Color.White
                : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .onClick(async () => {
                this.detectionScope = 'all_types';
                await this.saveStringSetting(SettingKeys.DUPLICATE_DETECTION_SCOPE, 'all_types');
              })
          }
          .width('100%')
        }
        .width('100%')
        .padding({ left: 8 })
      }
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 2
    })
  }

  @Builder
  buildMatchWeights() {
    Column({ space: 16 }) {
      Text('匹配权重')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      if (this.duplicateDetectionEnabled) {
        Column({ space: 8 }) {
          Row() {
            Text('标题权重')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            Blank()
            Text(`标题 ${this.titleWeight}% / 作者 ${100 - this.titleWeight}%`)
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          }
          .width('100%')

          Text('调整标题和作者在相似度计算中的权重比例')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .alignSelf(ItemAlign.Start)

          Slider({
            value: this.titleWeight,
            min: 10,
            max: 90,
            step: 10,
            style: SliderStyle.InSet
          })
            .blockColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .trackColor(ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme))
            .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
            .onChange(async (value: number) => {
              this.titleWeight = Math.round(value);
              await this.saveNumberSetting(SettingKeys.DUPLICATE_DETECTION_TITLE_WEIGHT, this.titleWeight / 100.0);
            })
        }
        .width('100%')
        .padding({ left: 8 })
      } else {
        Text('请先启用重复检测功能')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 2
    })
  }

  @Builder
  buildExplanation() {
    Column({ space: 12 }) {
      Text('说明')
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)

      Column({ space: 8 }) {
        Text('• 重复检测基于标题和作者的文本相似度，采用编辑距离与 N-gram 混合算法')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        Text('• 阈值越低，检测越宽松（更容易被标记为重复）；阈值越高，检测越严格')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        Text('• "仅同类型"只在漫画与漫画、小说与小说之间检测；"跨类型"会在所有内容类型之间检测')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        Text('• 检测到重复时会弹窗显示匹配结果，由您决定是否继续添加')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))

        Text('• 仅在收藏和本地导入时检测，在线浏览不会触发')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .padding(16)
    .alignItems(HorizontalAlign.Start)
    .backgroundColor(SettingsPanelSurfaceHelper.getBackground(this.themeState.currentTheme))
    .linearGradient(SettingsPanelSurfaceHelper.getSurfaceGradient(this.themeState.currentTheme))
    .backgroundBlurStyle(SettingsPanelSurfaceHelper.getBlurStyle(this.themeState.currentTheme), SettingsPanelSurfaceHelper.getBlurOptions(this.themeState.currentTheme))
    .backgroundEffect(SettingsPanelSurfaceHelper.getBackgroundEffect(this.themeState.currentTheme))
    .borderRadius(SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme))
    .border({ width: SettingsPanelSurfaceHelper.getBorderWidth(this.themeState.currentTheme), color: SettingsPanelSurfaceHelper.getBorderColor(this.themeState.currentTheme) })
    .shadow({
      radius: SettingsPanelSurfaceHelper.getRadius(this.themeState.currentTheme) + 4,
      color: SettingsPanelSurfaceHelper.getShadowColor(this.themeState.currentTheme),
      offsetX: 0,
      offsetY: 2
    })
  }

  build() {
    HdsNavDestination() {
      Stack() {
        SharedPageBackgroundLayer({
          defaultBackgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme),
          mode: GlobalBackgroundLayerMode.IMMERSIVE
        })
          .width('100%')
          .height('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Scroll(this.scroller) {
          Column({ space: 16 }) {
            Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))

            Column({ space: 16 }) {
              this.buildDetectionRules()
            }
            .padding(4)
            .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
              this.themeState.currentTheme,
              this.activeSearchAnchorId,
              'dup_detect_rules'
            ))
            .borderRadius(16)
            .border({
              width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'dup_detect_rules') ? 1 : 0,
              color: SettingsSearchSupport.getHighlightOverlayBorder(this.themeState.currentTheme, this.activeSearchAnchorId, 'dup_detect_rules')
            })
            .scale({
              x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'dup_detect_rules', this.searchHighlightPulse),
              y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'dup_detect_rules', this.searchHighlightPulse)
            })
            .shadow(SettingsSearchSupport.getHighlightOverlayShadow(this.themeState.currentTheme, this.activeSearchAnchorId, 'dup_detect_rules', this.searchHighlightPulse))
            .animation({ duration: 260, curve: Curve.EaseOut })

            Column({ space: 16 }) {
              this.buildMatchWeights()
            }
            .padding(4)
            .backgroundColor(SettingsSearchSupport.getHighlightOverlayBackground(
              this.themeState.currentTheme,
              this.activeSearchAnchorId,
              'dup_detect_weight'
            ))
            .borderRadius(16)
            .border({
              width: SettingsSearchSupport.isHighlightActive(this.activeSearchAnchorId, 'dup_detect_weight') ? 1 : 0,
              color: SettingsSearchSupport.getHighlightOverlayBorder(this.themeState.currentTheme, this.activeSearchAnchorId, 'dup_detect_weight')
            })
            .scale({
              x: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'dup_detect_weight', this.searchHighlightPulse),
              y: SettingsSearchSupport.getHighlightScale(this.activeSearchAnchorId, 'dup_detect_weight', this.searchHighlightPulse)
            })
            .shadow(SettingsSearchSupport.getHighlightOverlayShadow(this.themeState.currentTheme, this.activeSearchAnchorId, 'dup_detect_weight', this.searchHighlightPulse))
            .animation({ duration: 260, curve: Curve.EaseOut })

            this.buildExplanation()

            Blank().height(40)
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 16 })
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .width('100%')
        .height('100%')

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: '内容重复检测',
          appFontFamily: this.appFontFamily,
          contentPadding: 16,
          maxContentWidth: 1200,
          pathStack: this.pathStack
        })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
      ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (newTheme: ThemeType) => {
        logger.info(TAG, `主题切换到: ${newTheme}`);
      });
      FontAwareHelper.initializeFontAware(this.componentId, this.fontState, (newState: FontAwareState) => {
        this.fontState = newState;
      });
      this.loadSettings();
      this.applyPendingSearchTarget();
    })
    .backgroundColor(Color.Transparent)
  }

  aboutToDisappear(): void {
    SettingsSearchSupport.clearHighlight(this);
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
    if (this.searchHighlightPulseTimer >= 0) {
      clearTimeout(this.searchHighlightPulseTimer);
    }
    if (this.searchHighlightClearTimer >= 0) {
      clearTimeout(this.searchHighlightClearTimer);
    }
  }
}
