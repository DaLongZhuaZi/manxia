// 文件路径: entry/src/main/ets/pages/settings/PageSettingsSubPage.ets
/**
 * 页面设置子页面
 * 允许用户选择不同场景使用的详情页类型
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { logger } from '../../Utils/Logger';
import { PageLifecycleManager } from '../../Framework/Lifecycle';
import { ThemeAwareState, ThemeAwareHelper } from '../../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../../Framework/Components/FontAware';
import { DeviceAdaptationManager, DeviceInfo, DeviceChangeListener, Breakpoint } from '../../Framework/Managers/DeviceAdaptationManager';
import { ResponsiveLayoutHelper } from '../../Framework/Utils/ResponsiveLayout';
import { SettingsManager, SettingKeys } from '../../Framework/Managers/SettingsManager';

const TAG = 'PageSettingsSubPage';
const TITLE_BAR_HEIGHT = 56;

/**
 * 详情页类型枚举
 * 注意：由于不同内容类型的数据结构不同，跨类型使用详情页可能导致显示异常
 * - DEFAULT: 使用原有的专用详情页
 * - UNIFIED: 使用统一详情页（支持所有内容类型）
 * - 其他类型: 仅在数据兼容时使用，否则回退到默认
 */
export enum DetailPageType {
  DEFAULT = 'default',       // 默认（使用原有逻辑）
  MANGA = 'manga',           // 漫画详情页
  EBOOK = 'ebook',           // 电子书详情页
  NOVEL = 'novel',           // 小说详情页
  UNIFIED = 'unified'        // 统一详情页
}

/**
 * 场景类型枚举
 */
export enum SceneType {
  MANGA = 'manga',           // 漫画场景
  EBOOK = 'ebook',           // 电子书场景
  NOVEL = 'novel'            // 小说场景
}

/**
 * 详情页选项
 */
interface DetailPageOption {
  type: DetailPageType;
  name: string;
  description: string;
}

/**
 * 设置键常量
 */
export class PageSettingKeys {
  static readonly MANGA_DETAIL_PAGE_TYPE = 'page_settings_manga_detail_type';
  static readonly EBOOK_DETAIL_PAGE_TYPE = 'page_settings_ebook_detail_type';
  static readonly NOVEL_DETAIL_PAGE_TYPE = 'page_settings_novel_detail_type';
}

@Component
export struct PageSettingsSubPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  private componentId: string = 'PageSettingsSubPage';
  private scroller: Scroller = new Scroller();

  // 响应式布局
  private deviceManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();
  private deviceChangeListener: DeviceChangeListener | null = null;
  @State responsive_contentPadding: number = 16;
  @State responsive_maxContentWidth: number = 1200;
  @State responsive_isLandscape: boolean = false;

  // 设置状态
  @State mangaDetailPageType: DetailPageType = DetailPageType.DEFAULT;
  @State ebookDetailPageType: DetailPageType = DetailPageType.DEFAULT;
  @State novelDetailPageType: DetailPageType = DetailPageType.DEFAULT;

  // 设置管理器
  private settingsManager: SettingsManager = SettingsManager.getInstance();

  // 详情页选项列表（只保留默认和统一详情页两项）
  private detailPageOptions: DetailPageOption[] = [
    { type: DetailPageType.DEFAULT, name: '默认', description: '使用原有的专用详情页' },
    { type: DetailPageType.UNIFIED, name: '统一详情页', description: '使用新的统一详情页（推荐，支持所有内容类型）' }
  ];

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });

    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );

    this.initializeResponsiveLayout();
    this.loadSettings();
  }

  private lifecycle = new PageLifecycleManager('PageSettingsSubPage', { enableDebug: true });

  aboutToDisappear(): void {
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);

    if (this.deviceChangeListener) {
      this.deviceManager.removeListener(this.deviceChangeListener);
      this.deviceChangeListener = null;
    }
  }

  private initializeResponsiveLayout(): void {
    try {
      this.updateResponsiveParams();
      this.deviceChangeListener = (deviceInfo: DeviceInfo) => {
        logger.info(TAG, `设备状态变化: 断点=${deviceInfo.breakpoint}, 方向=${deviceInfo.orientation}`);
        this.updateResponsiveParams();
      };
      this.deviceManager.addListener(this.deviceChangeListener);
    } catch (error) {
      logger.error(TAG, '响应式布局初始化失败', String(error));
    }
  }

  private updateResponsiveParams(): void {
    const layoutParams = ResponsiveLayoutHelper.getLayoutParams();
    const deviceInfo = this.deviceManager.getDeviceInfo();
    this.responsive_contentPadding = layoutParams.contentPadding;
    this.responsive_isLandscape = deviceInfo.isLandscape;
    switch (deviceInfo.breakpoint) {
      case Breakpoint.XS:
        this.responsive_maxContentWidth = 600;
        break;
      case Breakpoint.SM:
        this.responsive_maxContentWidth = 840;
        break;
      case Breakpoint.MD:
        this.responsive_maxContentWidth = 1024;
        break;
      case Breakpoint.LG:
        this.responsive_maxContentWidth = 1200;
        break;
    }
  }

  /**
   * 加载设置
   */
  private loadSettings(): void {
    const mangaType = this.settingsManager.getString(PageSettingKeys.MANGA_DETAIL_PAGE_TYPE, DetailPageType.DEFAULT);
    const ebookType = this.settingsManager.getString(PageSettingKeys.EBOOK_DETAIL_PAGE_TYPE, DetailPageType.DEFAULT);
    const novelType = this.settingsManager.getString(PageSettingKeys.NOVEL_DETAIL_PAGE_TYPE, DetailPageType.DEFAULT);

    this.mangaDetailPageType = mangaType as DetailPageType;
    this.ebookDetailPageType = ebookType as DetailPageType;
    this.novelDetailPageType = novelType as DetailPageType;

    logger.info(TAG, `加载设置: manga=${mangaType}, ebook=${ebookType}, novel=${novelType}`);
  }

  /**
   * 保存设置
   */
  private saveSettings(): void {
    this.settingsManager.setString(PageSettingKeys.MANGA_DETAIL_PAGE_TYPE, this.mangaDetailPageType);
    this.settingsManager.setString(PageSettingKeys.EBOOK_DETAIL_PAGE_TYPE, this.ebookDetailPageType);
    this.settingsManager.setString(PageSettingKeys.NOVEL_DETAIL_PAGE_TYPE, this.novelDetailPageType);

    logger.info(TAG, `保存设置: manga=${this.mangaDetailPageType}, ebook=${this.ebookDetailPageType}, novel=${this.novelDetailPageType}`);

    promptAction.showToast({
      message: '设置已保存',
      duration: 1500
    });
  }

  /**
   * 获取详情页类型名称
   */
  private getDetailPageTypeName(type: DetailPageType): string {
    const option = this.detailPageOptions.find(o => o.type === type);
    return option ? option.name : '默认';
  }

  @Builder
  buildSceneSettings(title: string, description: string, currentType: DetailPageType, onSelect: (type: DetailPageType) => void) {
    Column({ space: 12 }) {
      Row() {
        Column({ space: 4 }) {
          Text(title)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

          Text(description)
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text(this.getDetailPageTypeName(currentType))
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      }
      .width('100%')

      // 选项列表
      Column({ space: 8 }) {
        ForEach(this.detailPageOptions, (option: DetailPageOption) => {
          Row() {
            Column({ space: 2 }) {
              Text(option.name)
                .fontSize(14)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

              Text(option.description)
                .fontSize(11)
                .fontFamily(this.appFontFamily)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            }
            .alignItems(HorizontalAlign.Start)
            .layoutWeight(1)

            Radio({ value: option.type, group: title })
              .checked(currentType === option.type)
              .onChange((isChecked: boolean) => {
                if (isChecked) {
                  onSelect(option.type);
                }
              })
          }
          .width('100%')
          .padding({ top: 8, bottom: 8 })
          .onClick(() => {
            onSelect(option.type);
          })
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
  }

  @Builder
  buildResetButton() {
    Button('恢复默认设置')
      .fontSize(14)
      .fontFamily(this.appFontFamily)
      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
      .backgroundColor(Color.Transparent)
      .borderWidth(1)
      .borderColor(ThemeAwareHelper.getTestManagementThemedColor('color_error', this.themeState.currentTheme))
      .borderRadius(8)
      .height(40)
      .width('100%')
      .onClick(() => {
        this.mangaDetailPageType = DetailPageType.DEFAULT;
        this.ebookDetailPageType = DetailPageType.DEFAULT;
        this.novelDetailPageType = DetailPageType.DEFAULT;
        this.saveSettings();
      })
  }

  build() {
    HdsNavDestination() {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        Scroll(this.scroller) {
          Column({ space: 16 }) {
            Blank().height(TITLE_BAR_HEIGHT)

            // 说明文字
            Text('选择在不同场景下使用的详情页类型。选择"默认"将使用原有的详情页，选择其他选项将统一使用指定的详情页样式。')
              .fontSize(13)
              .fontFamily(this.appFontFamily)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .padding({ left: 16, right: 16 })

            // 漫画场景设置
            this.buildSceneSettings(
              '漫画详情页',
              '打开漫画时使用的详情页类型',
              this.mangaDetailPageType,
              (type: DetailPageType) => {
                this.mangaDetailPageType = type;
                this.saveSettings();
              }
            )

            // 电子书场景设置
            this.buildSceneSettings(
              '电子书详情页',
              '打开电子书时使用的详情页类型',
              this.ebookDetailPageType,
              (type: DetailPageType) => {
                this.ebookDetailPageType = type;
                this.saveSettings();
              }
            )

            // 小说场景设置
            this.buildSceneSettings(
              '小说详情页',
              '打开小说时使用的详情页类型',
              this.novelDetailPageType,
              (type: DetailPageType) => {
                this.novelDetailPageType = type;
                this.saveSettings();
              }
            )

            // 恢复默认按钮
            this.buildResetButton()

            Blank().height(40)
          }
          .width('100%')
          .constraintSize({ maxWidth: this.responsive_maxContentWidth })
          .padding({ left: this.responsive_contentPadding, right: this.responsive_contentPadding, bottom: 40 })
        }
        .width('100%')
        .height('100%')
        .align(Alignment.TopStart)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.Spring)
      }
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(16),
        end: LengthMetrics.vp(16)
      },
      style: {
        originalStyle: {
          backgroundStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme) },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        }
      },
      content: {
        title: { mainTitle: '页面设置' }
      }
    })
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
    .backgroundColor(Color.Transparent)
  }
}

/**
 * 页面设置工具类
 * 用于获取当前场景应该使用的详情页类型
 */
export class PageSettingsHelper {
  private static settingsManager: SettingsManager = SettingsManager.getInstance();

  /**
   * 获取漫画场景的详情页类型
   */
  static getMangaDetailPageType(): DetailPageType {
    const type = PageSettingsHelper.settingsManager.getString(PageSettingKeys.MANGA_DETAIL_PAGE_TYPE, DetailPageType.DEFAULT);
    return type as DetailPageType;
  }

  /**
   * 获取电子书场景的详情页类型
   */
  static getEBookDetailPageType(): DetailPageType {
    const type = PageSettingsHelper.settingsManager.getString(PageSettingKeys.EBOOK_DETAIL_PAGE_TYPE, DetailPageType.DEFAULT);
    return type as DetailPageType;
  }

  /**
   * 获取小说场景的详情页类型
   */
  static getNovelDetailPageType(): DetailPageType {
    const type = PageSettingsHelper.settingsManager.getString(PageSettingKeys.NOVEL_DETAIL_PAGE_TYPE, DetailPageType.DEFAULT);
    return type as DetailPageType;
  }

  /**
   * 根据场景和设置获取应该跳转的详情页名称
   */
  static getDetailPageName(scene: SceneType): string {
    let pageType: DetailPageType;

    switch (scene) {
      case SceneType.MANGA:
        pageType = PageSettingsHelper.getMangaDetailPageType();
        break;
      case SceneType.EBOOK:
        pageType = PageSettingsHelper.getEBookDetailPageType();
        break;
      case SceneType.NOVEL:
        pageType = PageSettingsHelper.getNovelDetailPageType();
        break;
      default:
        pageType = DetailPageType.DEFAULT;
    }

    // 如果是默认，返回原有页面名称
    if (pageType === DetailPageType.DEFAULT) {
      switch (scene) {
        case SceneType.MANGA:
          return 'MangaDetailPage';
        case SceneType.EBOOK:
          return 'EBookDetailPage';
        case SceneType.NOVEL:
          return 'NovelDetailPage';
      }
    }

    // 如果选择了统一详情页
    if (pageType === DetailPageType.UNIFIED) {
      return 'UnifiedDetailPage';
    }

    // 如果选择了特定类型的详情页
    switch (pageType) {
      case DetailPageType.MANGA:
        return 'MangaDetailPage';
      case DetailPageType.EBOOK:
        return 'EBookDetailPage';
      case DetailPageType.NOVEL:
        return 'NovelDetailPage';
      default:
        return 'UnifiedDetailPage';
    }
  }
}
