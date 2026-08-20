/**
 * 设置Tab内容组件
 * 从 MainMenuPage 提取的设置页面逻辑
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { SettingsPageSurfaceManager, SettingsPageSurfaceStyle } from 'manxia_features_ui/src/main/ets/pages/settings/SettingsPageSurfaceManager';
import { AnnotationCenterPageParams } from '../pages/AnnotationCenterPage';
import { openFileEditorInIsolatedAbility } from '../Framework/Editor/FileEditorAbilityLauncher';
import {
  FileEditorOpenParams,
  FileEditorOpenSource,
  FileEditorSaveTargetType,
  fileEditorService
} from '../Framework/Editor/FileEditorService';

const TAG = 'SettingsTabContent';

interface NavigationPathParam {
  fromPage: string;
  timestamp: number;
}

interface NavigationPath {
  name: string;
  param: NavigationPathParam | FileEditorOpenParams;
}

@Component
export struct SettingsTabContent {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @Prop topSpacerHeight: number = 0;
  @Prop bottomSpacerHeight: number = 125;
  @Prop @Watch('onRefreshSignalChanged') refreshSignal: number = 0;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  @State private themeState: ThemeAwareState = new ThemeAwareState();
  @StorageLink('advanced_mode_enabled') private advancedModeEnabled: boolean = true;
  @StorageLink('source_features_enabled') private sourceFeaturesEnabled: boolean = false;

  private settingsScroller: Scroller = new Scroller();
  private componentId: string = 'SettingsTabContent';

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState,
      (theme: ThemeType) => {
        const newState = new ThemeAwareState();
        newState.updateTheme(theme);
        this.themeState = newState;
      },
      (newState: ThemeAwareState) => {
        this.themeState = newState;
      }
    );
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  onRefreshSignalChanged(): void {
    // Settings tab 无需刷新数据
  }

  private showToast(message: string): void {
    try {
      this.getUIContext().getPromptAction().showToast({ message: message, duration: 1800 });
    } catch (error) {
      logger.warn(TAG, `Toast显示失败: ${message}`);
    }
  }

  // ── Settings Analytics Card 样式方法 ──

  private getSettingsAnalyticsCardBackground(): ResourceColor {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.backgroundColor;
  }

  private getSettingsAnalyticsCardBlurStyle(): BlurStyle | undefined {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.blurStyle;
  }

  private getSettingsAnalyticsCardBlurOptions(): BackgroundBlurStyleOptions {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.blurOptions;
  }

  private getSettingsAnalyticsCardBackgroundEffect(): BackgroundEffectOptions | undefined {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.backgroundEffect;
  }

  private getSettingsAnalyticsCardBorderColor(): ResourceColor {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.borderColor;
  }

  private getSettingsAnalyticsCardBorderWidth(): number {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.borderWidth;
  }

  private getSettingsAnalyticsCardShadowColor(): string {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.shadowColor;
  }

  private getSettingsAnalyticsCardRadius(): number {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.radius;
  }

  private getSettingsAnalyticsCardTopEdgeColor(): ResourceColor {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.topEdgeColor;
  }

  private getSettingsAnalyticsCardBottomEdgeColor(): ResourceColor {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.bottomEdgeColor;
  }

  private getSettingsAnalyticsCardSurfaceGradient(): LinearGradient {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).surface.surfaceGradient;
  }

  private getSettingsAnalyticsCardIconColor(): ResourceColor {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).row.iconColor;
  }

  private getSettingsAnalyticsCardTitleColor(): ResourceColor {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).row.titleColor;
  }

  private getSettingsAnalyticsCardSubtitleColor(): ResourceColor {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).row.subtitleColor;
  }

  private getSettingsAnalyticsCardChevronColor(): ResourceColor {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).row.chevronColor;
  }

  private getSettingsAnalyticsCardChevronOpacity(): number {
    return SettingsPageSurfaceManager.getFeaturedCardStyle(this.themeState.currentTheme).row.chevronOpacity;
  }

  // ── Settings Management Item 样式方法 ──

  private getSettingsManagementItemIconColor(): ResourceColor {
    return SettingsPageSurfaceManager.getManagementListItemStyle(this.themeState.currentTheme).iconColor;
  }

  private getSettingsManagementItemTitleColor(): ResourceColor {
    return SettingsPageSurfaceManager.getManagementListItemStyle(this.themeState.currentTheme).titleColor;
  }

  private getSettingsManagementItemSubtitleColor(): ResourceColor {
    return SettingsPageSurfaceManager.getManagementListItemStyle(this.themeState.currentTheme).subtitleColor;
  }

  private getSettingsManagementItemChevronColor(): ResourceColor {
    return SettingsPageSurfaceManager.getManagementListItemStyle(this.themeState.currentTheme).chevronColor;
  }

  private getSettingsManagementItemChevronOpacity(): number {
    return SettingsPageSurfaceManager.getManagementListItemStyle(this.themeState.currentTheme).chevronOpacity;
  }

  private getSettingsManagementContentSurfaceStyle(): SettingsPageSurfaceStyle {
    return SettingsPageSurfaceManager.getManagementContentSurfaceStyle(this.themeState.currentTheme);
  }

  // ── @Builder 方法 ──

  @Builder
  buildSettingsAnalyticsCard() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(this.getSettingsAnalyticsCardRadius())
        .linearGradient(this.getSettingsAnalyticsCardSurfaceGradient())

      Column()
        .width('100%')
        .height(1)
        .backgroundColor(this.getSettingsAnalyticsCardTopEdgeColor())

      Column()
        .width('100%')
        .height(1)
        .align(Alignment.Bottom)
        .backgroundColor(this.getSettingsAnalyticsCardBottomEdgeColor())

      Row() {
        Column() {
          SymbolGlyph($r('sys.symbol.histogram_fill'))
            .fontSize(54)
            .fontColor([this.getSettingsAnalyticsCardIconColor()])
        }
        .width(60)
        .height(60)
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)

        Column({ space: 4 }) {
          Text('阅读报告')
            .fontSize(18)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getSettingsAnalyticsCardTitleColor())

          Text('查看您的阅读统计与趋势分析')
            .fontSize(14)
            .fontFamily(this.appFontFamily)
            .fontColor(this.getSettingsAnalyticsCardSubtitleColor())
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        .margin({ left: 16 })

        SymbolGlyph($r('sys.symbol.chevron_right'))
          .fontSize(20)
          .fontColor([this.getSettingsAnalyticsCardChevronColor()])
          .opacity(this.getSettingsAnalyticsCardChevronOpacity())
      }
      .width('100%')
      .height('100%')
      .alignItems(VerticalAlign.Center)
      .padding(16)
    }
    .width('100%')
    .height(92)
    .backgroundColor(this.getSettingsAnalyticsCardBackground())
    .backgroundBlurStyle(this.getSettingsAnalyticsCardBlurStyle(), this.getSettingsAnalyticsCardBlurOptions())
    .backgroundEffect(this.getSettingsAnalyticsCardBackgroundEffect())
    .borderRadius(this.getSettingsAnalyticsCardRadius())
    .clip(true)
    .border({
      width: this.getSettingsAnalyticsCardBorderWidth(),
      color: this.getSettingsAnalyticsCardBorderColor()
    })
    .shadow({
      radius: this.getSettingsAnalyticsCardRadius() + 4,
      color: this.getSettingsAnalyticsCardShadowColor(),
      offsetX: 0,
      offsetY: 8
    })
    .margin({ bottom: 16 })
    .id('guide_main_setting_analytics')
    .onClick(() => {
      try {
        const navigationPath: NavigationPath = {
          name: 'ReadingAnalyticsPage',
          param: {
            fromPage: 'MainMenuPage',
            timestamp: Date.now()
          }
        };
        this.pathStack.pushPath(navigationPath);
        logger.info(TAG, '导航到阅读报告页面');
      } catch (error) {
        logger.error(TAG, '导航到阅读报告页面失败', String(error));
        this.showToast('打开阅读报告页面失败');
      }
    })
  }

  @Builder
  buildSettingItem(title: string, subtitle: string, icon: ResourceStr, onClick?: () => void, guideId?: string) {
    Row() {
      SymbolGlyph(icon as Resource)
        .fontSize(24)
        .fontColor([this.getSettingsManagementItemIconColor()])
        .renderingStrategy(SymbolRenderingStrategy.SINGLE)

      Column({ space: 2 }) {
        Text(title)
          .fontSize(16)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getSettingsManagementItemTitleColor())
          .textAlign(TextAlign.Start)
          .width('100%')

        Text(subtitle)
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(this.getSettingsManagementItemSubtitleColor())
          .textAlign(TextAlign.Start)
          .width('100%')
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      .margin({ left: 16 })

      SymbolGlyph($r('sys.symbol.chevron_right'))
        .fontSize(20)
        .fontColor([this.getSettingsManagementItemChevronColor()])
        .opacity(this.getSettingsManagementItemChevronOpacity())
    }
    .width('100%')
    .height(64)
    .padding({ left: 16, right: 16 })
    .id(guideId && guideId.length > 0 ? guideId : `main_setting_${title}`)
    .onClick(() => {
      if (onClick) {
        onClick();
      } else {
        this.showToast(`${title}入口未配置操作`);
      }
    })
  }

  @Builder
  buildSettingsContent() {
    Scroll(this.settingsScroller) {
      Column({ space: 0 }) {
        Blank().height(this.topSpacerHeight)
        this.buildSettingsAnalyticsCard()

        // 设置选项列表
        Column() {
          this.buildSettingItem('漫匣支持者计划', '支持项目并解锁独有功能', $r('sys.symbol.star'), () => {
            try {
              this.pathStack.pushPathByName('SupporterPlanPage', null);
              logger.info(TAG, '导航到漫匣支持者计划页面');
            } catch (error) {
              logger.error(TAG, '导航到漫匣支持者计划页面失败', String(error));
              this.showToast('打开支持者计划失败');
            }
          }, 'guide_main_setting_supporter')

          this.buildSettingItem('主题设置', '自定义背景、强调色', $r('sys.symbol.paintpalette'), () => {
            try {
              const navigationPath: NavigationPath = {
                name: 'ThemeSettingsPage',
                param: {
                  fromPage: 'MainMenuPage',
                  timestamp: Date.now()
                }
              };
              this.pathStack.pushPath(navigationPath);
              logger.info(TAG, '导航到主题设置页面');
            } catch (error) {
              logger.error(TAG, '导航到主题设置页面失败', String(error));
              this.showToast('打开主题设置页面失败');
            }
          }, 'guide_main_setting_theme')

          this.buildSettingItem('视觉效果', '查看设备材质能力与材质档位策略', $r('sys.symbol.lightbulb'), () => {
            try {
              const navigationPath: NavigationPath = {
                name: 'VisualEffectsSettingsSubPage',
                param: {
                  fromPage: 'MainMenuPage',
                  timestamp: Date.now()
                }
              };
              this.pathStack.pushPath(navigationPath);
              logger.info(TAG, '导航到视觉效果设置页面');
            } catch (error) {
              logger.error(TAG, '导航到视觉效果设置页面失败', String(error));
              this.showToast('打开视觉效果设置页面失败');
            }
          }, 'guide_main_setting_visual_effects')

          this.buildSettingItem('全局设置', '默认阅读模式、下载选项', $r('sys.symbol.slider_horizontal_2_square'), () => {
            try {
              const navigationPath: NavigationPath = {
                name: 'GlobalSettingsPage',
                param: {
                  fromPage: 'MainMenuPage',
                  timestamp: Date.now()
                }
              };
              this.pathStack.pushPath(navigationPath);
              logger.info(TAG, '导航到全局设置页面');
            } catch (error) {
              logger.error(TAG, '导航到全局设置页面失败', String(error));
              this.showToast('打开全局设置页面失败');
            }
          }, 'guide_main_setting_global')

          this.buildSettingItem('灵感', '查看和管理全部内容的书签、划线与想法', $r('sys.symbol.highlighter_line'), () => {
            try {
              const params: AnnotationCenterPageParams = {
                contentTitle: '全部内容'
              };
              this.pathStack.pushPathByName('AnnotationCenterPage', params);
              logger.info(TAG, '导航到灵感页面');
            } catch (error) {
              logger.error(TAG, '导航到灵感页面失败', String(error));
              this.showToast('打开灵感页面失败');
            }
          }, 'guide_main_setting_inspiration')

          if (this.sourceFeaturesEnabled) {
            this.buildSettingItem('更新提醒', '统一管理作品、书架和远程库的更新提醒', $r('sys.symbol.bell'), () => {
              try {
                this.pathStack.pushPathByName('SubscriptionManagementPage', null);
                logger.info(TAG, '导航到更新提醒页面');
              } catch (error) {
                logger.error(TAG, '导航到更新提醒页面失败', String(error));
                this.showToast('打开更新提醒页面失败');
              }
            }, 'guide_main_setting_subscription_management')
          }

          if (this.advancedModeEnabled) {
            this.buildSettingItem('下载管理', '离线下载管理', $r('sys.symbol.arrow_down_circle'), () => {
              try {
                const navigationPath: NavigationPath = {
                  name: 'DownloadManagerPage',
                  param: {
                    fromPage: 'MainMenuPage',
                    timestamp: Date.now()
                  }
                };
                this.pathStack.pushPath(navigationPath);
                logger.info(TAG, '导航到下载管理页面');
              } catch (error) {
                logger.error(TAG, '导航到下载管理页面失败', String(error));
                this.showToast('打开下载管理页面失败');
              }
            }, 'guide_main_setting_download_manager')
          }

          this.buildSettingItem('备份与恢复', '备份所有数据或从备份恢复', $r('sys.symbol.arrow_2_circlepath'), () => {
            try {
              const navigationPath: NavigationPath = {
                name: 'BackupPage',
                param: {
                  fromPage: 'MainMenuPage',
                  timestamp: Date.now()
                }
              };
              this.pathStack.pushPath(navigationPath);
              logger.info(TAG, '导航到备份页面');
            } catch (error) {
              logger.error(TAG, '导航到备份页面失败', String(error));
              this.showToast('打开备份页面失败');
            }
          }, 'guide_main_setting_backup')

          if (this.advancedModeEnabled) {
            this.buildSettingItem('数据与缓存管理', '统一查看、监控和清理缓存数据', $r('sys.symbol.externaldrive_fill'), () => {
              try {
                const navigationPath: NavigationPath = {
                  name: 'StorageManagementPage',
                  param: {
                    fromPage: 'MainMenuPage',
                    timestamp: Date.now()
                  }
                };
                this.pathStack.pushPath(navigationPath);
                logger.info(TAG, '导航到数据与缓存管理页面');
              } catch (error) {
                logger.error(TAG, '导航到数据与缓存管理页面失败', String(error));
                this.showToast('打开数据与缓存管理页面失败');
              }
            }, 'guide_main_setting_storage')
          }

          this.buildSettingItem('文件导入', '单独导入Mihon/Komikku本地漫画、电子书、小说', $r('sys.symbol.folder_badge_plus'), () => {
            try {
              const navigationPath: NavigationPath = {
                name: 'DataManagementPage',
                param: {
                  fromPage: 'MainMenuPage',
                  timestamp: Date.now()
                }
              };
              this.pathStack.pushPath(navigationPath);
              logger.info(TAG, '导航到数据管理页面');
            } catch (error) {
              logger.error(TAG, '导航到数据管理页面失败', String(error));
              this.showToast('打开数据管理页面失败');
            }
          }, 'guide_main_setting_data_management')

          this.buildSettingItem('网络文件夹', '通过 WebDAV/FTP/FTPS/SMB 连接远程文件夹并导入文件', $r('sys.symbol.wifi_router'), () => {
            try {
              const navigationPath: NavigationPath = {
                name: 'NetworkFolderPage',
                param: {
                  fromPage: 'MainMenuPage',
                  timestamp: Date.now()
                }
              };
              this.pathStack.pushPath(navigationPath);
              logger.info(TAG, '导航到网络文件夹页面');
            } catch (error) {
              logger.error(TAG, '导航到网络文件夹页面失败', String(error));
              this.showToast('打开网络文件夹页面失败');
            }
          }, 'guide_main_setting_network_folder')

          this.buildSettingItem('局域网传书', '在同一局域网内通过浏览器直连漫匣并传输文件', $r('sys.symbol.computer_host_fill'), () => {
            try {
              const navigationPath: NavigationPath = {
                name: 'TransferPage',
                param: {
                  fromPage: 'MainMenuPage',
                  timestamp: Date.now()
                }
              };
              this.pathStack.pushPath(navigationPath);
              logger.info(TAG, '导航到局域网传书页面');
            } catch (error) {
              logger.error(TAG, '导航到局域网传书页面失败', String(error));
              this.showToast('打开局域网传书页面失败');
            }
          }, 'guide_main_setting_transfer')

          this.buildSettingItem('Download导入', '从Download目录扫描并导入文件', $r('sys.symbol.square_and_arrow_down'), () => {
            try {
              const navigationPath: NavigationPath = {
                name: 'DownloadSyncPage',
                param: {
                  fromPage: 'MainMenuPage',
                  timestamp: Date.now()
                }
              };
              this.pathStack.pushPath(navigationPath);
              logger.info(TAG, '导航到Download导入页面');
            } catch (error) {
              logger.error(TAG, '导航到Download导入页面失败', String(error));
              this.showToast('打开Download导入页面失败');
            }
          }, 'guide_main_setting_download_sync')

          if (this.advancedModeEnabled) {
            this.buildSettingItem('文件编辑器', '编辑代码、配置文件、Markdown', $r('sys.symbol.doc_plaintext'), () => {
              try {
                const openParams: FileEditorOpenParams = {
                  origin: FileEditorOpenSource.MANUAL,
                  title: '文件编辑器',
                  saveTarget: fileEditorService.createSaveTarget(FileEditorSaveTargetType.NONE)
                };
                openFileEditorInIsolatedAbility(this.getUIContext(), openParams, TAG);
                logger.info(TAG, '导航到文件编辑器页面');
              } catch (error) {
                logger.error(TAG, '导航到文件编辑器页面失败', String(error));
                this.showToast('打开文件编辑器页面失败');
              }
            }, 'guide_main_setting_file_editor')
          }

          this.buildSettingItem('AVIF图片查看器', '测试AVIF图片查看、导出功能', $r('sys.symbol.picture'), () => {
            const navigationPath: NavigationPath = {
              name: 'AvifTestPage',
              param: {
                fromPage: 'MainMenuPage',
                timestamp: Date.now()
              }
            };
            this.pathStack.pushPath(navigationPath);
          }, 'guide_main_setting_avif')

          this.buildSettingItem('帮助中心', '查看功能说明和常见问题', $r('sys.symbol.questionmark_circle'), () => {
            try {
              const navigationPath: NavigationPath = {
                name: 'HelpCenterPage',
                param: {
                  fromPage: 'MainMenuPage',
                  timestamp: Date.now()
                }
              };
              this.pathStack.pushPath(navigationPath);
              logger.info(TAG, '导航到帮助中心页面');
            } catch (error) {
              logger.error(TAG, '导航到帮助中心页面失败', String(error));
              this.showToast('打开帮助中心页面失败');
            }
          }, 'guide_main_setting_help')

          this.buildSettingItem('关于应用', '版本信息', $r('sys.symbol.info_circle'), () => {
            try {
              const navigationPath: NavigationPath = {
                name: 'AboutPage',
                param: {
                  fromPage: 'MainMenuPage',
                  timestamp: Date.now()
                }
              };
              this.pathStack.pushPath(navigationPath);
              logger.info(TAG, '导航到关于应用页面');
            } catch (error) {
              logger.error(TAG, '导航到关于应用页面失败', String(error));
              this.showToast('打开关于应用页面失败');
            }
          }, 'guide_main_setting_about')
        }
        .backgroundColor(this.getSettingsManagementContentSurfaceStyle().backgroundColor)
        .backgroundBlurStyle(
          this.getSettingsManagementContentSurfaceStyle().blurStyle,
          this.getSettingsManagementContentSurfaceStyle().blurOptions
        )
        .backgroundEffect(this.getSettingsManagementContentSurfaceStyle().backgroundEffect)
        .borderRadius(this.getSettingsManagementContentSurfaceStyle().radius)
        .clip(true)
        .border({
          width: this.getSettingsManagementContentSurfaceStyle().borderWidth,
          color: this.getSettingsManagementContentSurfaceStyle().borderColor
        })
        .shadow({
          radius: this.getSettingsManagementContentSurfaceStyle().radius + 4,
          color: this.getSettingsManagementContentSurfaceStyle().shadowColor,
          offsetX: 0,
          offsetY: 8
        })

        Blank().height(this.bottomSpacerHeight)
      }
      .width('100%')
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .id('guide_main_settings_scroll')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.Spring)
    .onScrollFrameBegin((offset: number, _state: ScrollState) => {
      AppStorage.setOrCreate<number>('extracted_tab_scroll_delta', offset);
      return { offsetRemain: offset };
    })
    .onScrollStop(() => {
      AppStorage.setOrCreate<number>('extracted_tab_scroll_stop', Date.now());
    })
  }

  build() {
    Column() {
      this.buildSettingsContent()
    }
    .width('100%')
    .height('100%')
  }
}
