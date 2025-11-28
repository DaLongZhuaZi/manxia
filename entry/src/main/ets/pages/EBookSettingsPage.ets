// 文件路径: entry/src/main/ets/pages/EBookSettingsPage.ets
/**
 * 电子书设置页面
 * 提供电子书阅读相关的设置选项
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';
import { logger } from '../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { EBook, EBookReadingSettings, EBookPageMode, EBOOK_THEME_PRESETS, EBookThemePreset, EBookFormat } from '../Models/EBookModels';
import { EBookDataManager } from '../Framework/Data/EBookDataManager';
import { EBookSettingsPageParams } from './EBookDetailPage';
import { DeviceAdaptationManager, DeviceChangeListener, DeviceInfo } from '../Framework/Managers/DeviceAdaptationManager';

const TAG = 'EBookSettingsPage';
const TITLE_BAR_HEIGHT_MINI: number = 56;

@Component
export struct EBookSettingsPage {
  @State pathStack: NavPathStack = new NavPathStack();
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private componentId: string = 'EBookSettingsPage';
  private scroller: Scroller = new Scroller();

  // 电子书数据
  @State ebook: EBook | null = null;
  @State settings: EBookReadingSettings | null = null;
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  @State isSaving: boolean = false;

  // 字体设置
  @State settingFontSize: number = 18;
  @State settingFontFamily: string = 'HarmonyOS Sans';
  @State settingFontPath: string = '';
  @State settingFontWeight: number = 400;
  
  // 排版设置
  @State settingLineHeight: number = 1.9;
  
  // 颜色主题设置
  @State settingBgColor: string = '#FFFFFF';
  @State settingTextColor: string = '#000000';
  @State settingThemeBgImage: string = '';
  @State settingNightMode: boolean = false;
  @State selectedThemeIndex: number = 0;
  
  // 翻页设置
  @State settingPageMargin: number = 20;
  @State settingPageMode: EBookPageMode = EBookPageMode.SIMULATION;
  
  // 系统设置
  @State settingBrightness: number = 100;
  @State settingAutoSave: boolean = true;
  @State settingSaveInterval: number = 30;

  // 主题相关
  private themeManager: ThemeManager = ThemeManager.getInstance();

  // 设备方向检测
  @State private isLandscape: boolean = false;
  private deviceOrientationListener: DeviceChangeListener | null = null;
  private deviceAdaptationManager: DeviceAdaptationManager = DeviceAdaptationManager.getInstance();

  // 数据管理器
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
    
    // 初始化设备方向
    this.updateDeviceOrientation();
    
    // 注册设备方向变化监听器
    this.deviceOrientationListener = (deviceInfo: DeviceInfo) => {
      logger.info(TAG, `设备方向变化: ${deviceInfo.isLandscape ? '横屏' : '竖屏'}`);
      this.isLandscape = deviceInfo.isLandscape;
    };
    this.deviceAdaptationManager.addListener(this.deviceOrientationListener);
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    
    // 移除设备方向监听器
    if (this.deviceOrientationListener) {
      this.deviceAdaptationManager.removeListener(this.deviceOrientationListener);
      this.deviceOrientationListener = null;
    }
  }

  /**
   * 更新设备方向
   */
  private updateDeviceOrientation(): void {
    const deviceInfo = this.deviceAdaptationManager.getDeviceInfo();
    this.isLandscape = deviceInfo.isLandscape;
    logger.info(TAG, `设备方向初始化: ${this.isLandscape ? '横屏' : '竖屏'}`);
  }

  /**
   * 加载电子书设置
   */
  private async loadSettings(bookId: string): Promise<void> {
    try {
      this.isLoading = true;
      this.errorMessage = '';

      logger.info(TAG, `加载电子书设置: ${bookId}`);
      const ebook = await this.ebookDataManager.getEBookById(bookId);

      if (!ebook) {
        throw new Error('电子书不存在');
      }

      this.ebook = ebook;
      
      // 加载阅读设置
      if (ebook.readingSettings) {
        this.settings = ebook.readingSettings;
        // 字体设置
        this.settingFontSize = ebook.readingSettings.fontSize;
        this.settingFontFamily = ebook.readingSettings.fontFamily;
        this.settingFontPath = ebook.readingSettings.fontPath || '';
        this.settingFontWeight = ebook.readingSettings.fontWeight || 400;
        // 排版设置
        this.settingLineHeight = ebook.readingSettings.lineHeight;
        // 颜色主题设置
        this.settingBgColor = ebook.readingSettings.backgroundColor;
        this.settingTextColor = ebook.readingSettings.textColor;
        this.settingThemeBgImage = ebook.readingSettings.themeBgImage || '';
        this.settingNightMode = ebook.readingSettings.nightMode || false;
        // 查找匹配的主题索引
        this.selectedThemeIndex = EBOOK_THEME_PRESETS.findIndex(
          (theme: EBookThemePreset) => theme.backgroundColor === this.settingBgColor
        );
        if (this.selectedThemeIndex < 0) this.selectedThemeIndex = 0;
        // 翻页设置
        this.settingPageMargin = ebook.readingSettings.pageMargin;
        this.settingPageMode = ebook.readingSettings.pageMode || EBookPageMode.SIMULATION;
        // 系统设置
        this.settingBrightness = ebook.readingSettings.brightness;
        this.settingAutoSave = ebook.readingSettings.autoSave;
        this.settingSaveInterval = ebook.readingSettings.saveInterval;
      }

      logger.info(TAG, `电子书设置加载完成: ${ebook.metadata.title}`);
    } catch (error) {
      this.errorMessage = `加载失败: ${String(error instanceof Error ? error.message : error)}`;
      logger.error(TAG, this.errorMessage);
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 保存设置
   */
  private async saveSettings(): Promise<void> {
    if (!this.ebook) {
      return;
    }

    try {
      this.isSaving = true;
      
      // 更新设置
      const newSettings: EBookReadingSettings = {
        // 字体设置
        fontSize: this.settingFontSize,
        fontFamily: this.settingFontFamily,
        fontPath: this.settingFontPath,
        fontWeight: this.settingFontWeight,
        // 排版设置
        lineHeight: this.settingLineHeight,
        // 颜色主题设置
        backgroundColor: this.settingBgColor,
        textColor: this.settingTextColor,
        themeBgImage: this.settingThemeBgImage,
        nightMode: this.settingNightMode,
        // 翻页设置
        pageMargin: this.settingPageMargin,
        pageMode: this.settingPageMode,
        // 系统设置
        brightness: this.settingBrightness,
        autoSave: this.settingAutoSave,
        saveInterval: this.settingSaveInterval,
        followSystemTheme: false
      };

      this.ebook.readingSettings = newSettings;
      await this.ebookDataManager.saveEBook(this.ebook);
      
      logger.info(TAG, '设置保存成功');
      this.pathStack.pop();
    } catch (error) {
      logger.error(TAG, `保存设置失败: ${String(error)}`);
    } finally {
      this.isSaving = false;
    }
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        // 内容层
        if (this.isLoading) {
          Column({ space: 16 }) {
            Blank().height(TITLE_BAR_HEIGHT_MINI)
            this.buildLoadingView()
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 20 })
        } else if (this.errorMessage.length > 0) {
          Column({ space: 16 }) {
            Blank().height(TITLE_BAR_HEIGHT_MINI)
            this.buildErrorView()
          }
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 20 })
        } else if (this.isLandscape) {
          // 横屏布局：左边40%电子书信息，右边60%设置选项
          Row() {
            // 左侧：电子书封面和基本信息
            Scroll() {
              Column() {
                Blank().height(TITLE_BAR_HEIGHT_MINI)
                this.buildEBookInfoSection()
              }
              .width('100%')
            }
            .width('40%')
            .height('100%')
            .padding({ left: 16, right: 8 })
            .edgeEffect(EdgeEffect.Spring)
            .scrollBar(BarState.Auto)
            
            // 右侧：各种设置选项
            Scroll(this.scroller) {
              Column({ space: 16 }) {
                Blank().height(TITLE_BAR_HEIGHT_MINI)
                this.buildSettingsContent()
              }
              .width('100%')
              .padding({ bottom: 40 })
            }
            .width('60%')
            .height('100%')
            .padding({ left: 8, right: 16 })
            .edgeEffect(EdgeEffect.Spring)
            .scrollBar(BarState.Auto)
          }
          .width('100%')
          .height('100%')
        } else {
          // 竖屏布局：原有布局
          Scroll(this.scroller) {
            Column({ space: 16 }) {
              Blank().height(TITLE_BAR_HEIGHT_MINI)
              this.buildEBookInfoSection()
              this.buildSettingsContent()
            }
            .width('100%')
            .padding({ left: 16, right: 16, bottom: 40 })
          }
          .width('100%')
          .height('100%')
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
        }
      }
    }
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, 'HdsNavDestination.onReady 已触发');
      this.pathStack = context.pathStack;
      const param = context.pathInfo.param as EBookSettingsPageParams | null;
      if (param && param.bookId) {
        this.loadSettings(param.bookId);
      } else {
        this.errorMessage = '无效的电子书ID';
        this.isLoading = false;
      }
    })
    .backgroundColor(Color.Transparent)
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
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: this.themeState.currentTheme === ThemeType.DARK ? '#E61A1A1A' : '#E6F5F5F5'
          },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        }
      },
      content: {
        title: { mainTitle: '电子书设置' }
      }
    })
  }

  /**
   * 构建加载视图
   */
  @Builder
  buildLoadingView() {
    Column({ space: 16 }) {
      LoadingProgress()
        .width(60)
        .height(60)
        .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

      Text('加载中...')
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
    }
    .width('100%')
    .height(300)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 构建错误视图
   */
  @Builder
  buildErrorView() {
    Column({ space: 16 }) {
      Text(this.errorMessage)
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .textAlign(TextAlign.Center)

      Button('返回')
        .fontSize(16)
        .height(40)
        .onClick(() => {
          this.pathStack.pop();
        })
    }
    .width('100%')
    .height(300)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .padding(20)
  }

  /**
   * 检查是否为 PDF 格式
   */
  private isPdfFormat(): boolean {
    return this.ebook?.format === EBookFormat.PDF;
  }

  /**
   * 构建设置内容
   * 根据电子书格式显示不同的设置选项
   */
  @Builder
  buildSettingsContent() {
    Column({ space: 16 }) {
      // PDF 格式显示专用设置
      if (this.isPdfFormat()) {
        this.buildPdfSettingsContent()
      } else {
        // 非 PDF 格式显示标准设置
        this.buildStandardSettingsContent()
      }
    }
    .width('100%')
  }

  /**
   * 构建 PDF 专用设置内容
   */
  @Builder
  buildPdfSettingsContent() {
    // PDF 格式提示
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Image($r('app.media.ic_pdf'))
          .width(24)
          .height(24)
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        Text('PDF 文档设置')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      }
      .width('100%')

      Text('PDF 文档使用系统 PDF 阅读器进行渲染，部分设置可能不适用。')
        .fontSize(13)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(12)

    // PDF 显示设置
    Column({ space: 12 }) {
      Text('显示设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      this.buildPdfDisplaySettings()
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(12)

    // 阅读设置（自动保存等）
    Column({ space: 12 }) {
      Text('阅读设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      this.buildReadingSettings()
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(12)

    // 保存按钮
    Button('保存设置')
      .fontSize(16)
      .width('100%')
      .height(48)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
      .borderRadius(12)
      .enabled(!this.isSaving)
      .onClick(() => {
        this.saveSettings();
      })
  }

  /**
   * 构建 PDF 显示设置
   */
  @Builder
  buildPdfDisplaySettings() {
    Column({ space: 16 }) {
      // 页面适配模式（PDF Kit 支持）
      Row() {
        Text('页面适配')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Blank()
        Text('适应宽度')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      }
      .width('100%')

      // 连续滚动
      Row() {
        Text('连续滚动')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: true })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .enabled(false) // PDF Kit 默认启用连续滚动
      }
      .width('100%')

      // 显示滚动条
      Row() {
        Text('显示滚动条')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        Blank()
        Toggle({ type: ToggleType.Switch, isOn: true })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .enabled(false) // PDF Kit 默认显示滚动条
      }
      .width('100%')
    }
    .width('100%')
  }

  /**
   * 构建标准设置内容（非 PDF 格式）
   */
  @Builder
  buildStandardSettingsContent() {
    // 字体设置
    Column({ space: 12 }) {
      Text('字体设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      this.buildFontSettings()
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(12)

    // 主题设置
    Column({ space: 12 }) {
      Text('主题设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      this.buildThemeSettings()
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(12)

    // 翻页设置
    Column({ space: 12 }) {
      Text('翻页设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      this.buildFlipModeSettings()
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(12)

    // 显示设置
    Column({ space: 12 }) {
      Text('显示设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

      this.buildDisplaySettings()
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
    .borderRadius(12)

    // 阅读设置
    Column({ space: 12 }) {
      Text('阅读设置')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .width('100%')

        this.buildReadingSettings()
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      .borderRadius(12)

      // 保存按钮
      Button(this.isSaving ? '保存中...' : '保存设置')
        .width('100%')
        .height(48)
        .fontSize(16)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .enabled(!this.isSaving)
        .onClick(() => {
          this.saveSettings();
        })
    }
  

  /**
   * 构建主题设置
   */
  @Builder
  buildThemeSettings() {
    Column({ space: 16 }) {
      // 预设主题选择
      Text('选择主题')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .width('100%')

      Row({ space: 8 }) {
        ForEach(EBOOK_THEME_PRESETS, (theme: EBookThemePreset, index: number) => {
          Column() {
            Stack() {
              Column()
                .width(40)
                .height(40)
                .backgroundColor(theme.backgroundColor)
                .borderRadius(20)
                .border({
                  width: this.selectedThemeIndex === index ? 2 : 1,
                  color: this.selectedThemeIndex === index 
                    ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('border_light', this.themeState.currentTheme)
                })
              
              if (this.selectedThemeIndex === index) {
                Image($r('app.media.ic_check'))
                  .width(16)
                  .height(16)
                  .fillColor(theme.nightMode ? '#FFFFFF' : '#000000')
              }
            }
            
            Text(theme.name)
              .fontSize(11)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
              .margin({ top: 4 })
          }
          .onClick(() => {
            this.selectedThemeIndex = index;
            this.settingBgColor = theme.backgroundColor;
            this.settingTextColor = theme.textColor;
            this.settingThemeBgImage = theme.themeBgImage;
            this.settingNightMode = theme.nightMode;
          })
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceAround)
    }
    .width('100%')
  }

  /**
   * 构建翻页模式设置
   */
  @Builder
  buildFlipModeSettings() {
    Column({ space: 16 }) {
      Row({ space: 16 }) {
        // 仿真翻页
        Row({ space: 8 }) {
          Radio({ value: 'simulation', group: 'flipMode' })
            .checked(this.settingPageMode === EBookPageMode.SIMULATION)
            .onChange((isChecked: boolean) => {
              if (isChecked) {
                this.settingPageMode = EBookPageMode.SIMULATION;
              }
            })
          Text('仿真翻页')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }

        // 横向滑动
        Row({ space: 8 }) {
          Radio({ value: 'horizontal', group: 'flipMode' })
            .checked(this.settingPageMode === EBookPageMode.HORIZONTAL)
            .onChange((isChecked: boolean) => {
              if (isChecked) {
                this.settingPageMode = EBookPageMode.HORIZONTAL;
              }
            })
          Text('横向滑动')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        }
      }
      .width('100%')
    }
    .width('100%')
  }

  /**
   * 构建字体设置
   */
  @Builder
  buildFontSettings() {
    Column({ space: 16 }) {
      // 字体大小
      Row() {
        Text('字体大小')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width(80)

        Slider({
          value: this.settingFontSize,
          min: 12,
          max: 32,
          step: 1
        })
          .layoutWeight(1)
          .onChange((value: number) => {
            this.settingFontSize = value;
          })

        Text(`${this.settingFontSize}`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width(40)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      // 行高
      Row() {
        Text('行高')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width(80)

        Slider({
          value: this.settingLineHeight * 10,
          min: 12,
          max: 30,
          step: 1
        })
          .layoutWeight(1)
          .onChange((value: number) => {
            this.settingLineHeight = value / 10;
          })

        Text(`${this.settingLineHeight.toFixed(1)}`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width(40)
          .textAlign(TextAlign.End)
      }
      .width('100%')
    }
    .width('100%')
  }

  /**
   * 构建显示设置
   */
  @Builder
  buildDisplaySettings() {
    Column({ space: 16 }) {
      // 页边距
      Row() {
        Text('页边距')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width(80)

        Slider({
          value: this.settingPageMargin,
          min: 8,
          max: 48,
          step: 4
        })
          .layoutWeight(1)
          .onChange((value: number) => {
            this.settingPageMargin = value;
          })

        Text(`${this.settingPageMargin}`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width(40)
          .textAlign(TextAlign.End)
      }
      .width('100%')

      // 亮度
      Row() {
        Text('亮度')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width(80)

        Slider({
          value: this.settingBrightness,
          min: 10,
          max: 100,
          step: 5
        })
          .layoutWeight(1)
          .onChange((value: number) => {
            this.settingBrightness = value;
          })

        Text(`${this.settingBrightness}%`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .width(50)
          .textAlign(TextAlign.End)
      }
      .width('100%')
    }
    .width('100%')
  }

  /**
   * 构建阅读设置
   */
  @Builder
  buildReadingSettings() {
    Column({ space: 16 }) {
      // 自动保存
      Row() {
        Text('自动保存进度')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.settingAutoSave })
          .onChange((isOn: boolean) => {
            this.settingAutoSave = isOn;
          })
      }
      .width('100%')

      // 保存间隔
      if (this.settingAutoSave) {
        Row() {
          Text('保存间隔')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .width(80)

          Slider({
            value: this.settingSaveInterval,
            min: 10,
            max: 120,
            step: 10
          })
            .layoutWeight(1)
            .onChange((value: number) => {
              this.settingSaveInterval = value;
            })

          Text(`${this.settingSaveInterval}秒`)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .width(50)
            .textAlign(TextAlign.End)
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  /**
   * 构建电子书信息展示区域
   */
  @Builder
  buildEBookInfoSection() {
    if (this.ebook) {
      Column({ space: 16 }) {
        // 封面图片
        Stack() {
          if (this.ebook.metadata.coverImagePath && this.ebook.metadata.coverImagePath.length > 0) {
            Image(this.ebook.metadata.coverImagePath.startsWith('/') 
              ? `file://${this.ebook.metadata.coverImagePath}` 
              : this.ebook.metadata.coverImagePath)
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .borderRadius(8)
          } else {
            Column() {
              Image($r('app.media.ic_ebook'))
                .width(50)
                .height(50)
                .fillColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            }
            .width('100%')
            .height('100%')
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme))
            .borderRadius(8)
            .justifyContent(FlexAlign.Center)
          }
        }
        .width(100)
        .height(150)
        .shadow({ radius: 8, color: '#1F000000', offsetY: 4 })

        // 标题
        Text(this.ebook.metadata.title)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .textAlign(TextAlign.Center)

        // 作者
        Text(this.ebook.metadata.author)
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .width('100%')
          .textAlign(TextAlign.Center)

        // 格式标签
        Row({ space: 8 }) {
          Text(this.ebook.format)
            .fontSize(11)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .borderRadius(4)

          Text(`${this.ebook.chapters.length}章`)
            .fontSize(11)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
            .padding({ left: 6, right: 6, top: 3, bottom: 3 })
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .borderRadius(4)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)

        // 阅读进度
        if (this.ebook.readingProgress && this.ebook.readingProgress.progress > 0) {
          Column({ space: 4 }) {
            Text(`已读 ${Math.floor(this.ebook.readingProgress.progress)}%`)
              .fontSize(11)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            Progress({
              value: this.ebook.readingProgress.progress,
              total: 100,
              type: ProgressType.Linear
            })
            .width('100%')
            .height(4)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }
      }
      .width('100%')
      .padding(16)
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.themeState.currentTheme))
      .borderRadius(12)
    }
  }
}

// 已经在 struct 定义时导出，不需要重复导出
