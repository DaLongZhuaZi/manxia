// 文件路径: entry/src/main/ets/Framework/Components/EBookReadingSettingsPanel.ets
/**
 * 电子书阅读设置面板
 * 提供字体大小、行高、主题等阅读设置
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ThemeAwareHelper } from './ThemeAware';
import { ThemeType } from '../Managers/ThemeManager';
import { AppColors } from '../Theme/AppColors';
import { EBookReadingSettings, EBookPageMode, DEFAULT_EBOOK_READING_SETTINGS } from 'manxia_core/src/main/ets/Models/EBookModels';
import { getFontManager, SystemFont, CustomFont } from '../Managers/FontManager';

const TAG = 'EBookReadingSettingsPanel';

/**
 * 阅读设置面板参数
 */
export interface EBookReadingSettingsPanelParams {
  settings: EBookReadingSettings;
  onSettingsChange: (settings: EBookReadingSettings) => void;
  onClose: () => void;
}

@Component
export struct EBookReadingSettingsPanel {
  @Prop settings: EBookReadingSettings;
  onSettingsChange: (settings: EBookReadingSettings) => void = (settings: EBookReadingSettings) => {};
  onClose: () => void = () => {};

  @State currentTheme: ThemeType = ThemeType.AUTO;
  
  // 主题提示 Popup 显示状态
  @State showThemeHintPopup: boolean = false;
  
  // 字体选择相关
  @State showFontPicker: boolean = false;
  @State systemFonts: SystemFont[] = [];
  @State customFonts: CustomFont[] = [];

  // 预设主题（自动模式会跟随系统主题，其他主题不会）
  private themes: ReadingTheme[] = [
    { name: '自动', bgColor: 'auto', textColor: 'auto', followSystem: true },
    { name: '默认', bgColor: '#FFFFFF', textColor: '#000000', followSystem: false },
    { name: '护眼', bgColor: '#C7EDCC', textColor: '#2B2B2B', followSystem: false },
    { name: '羊皮纸', bgColor: '#F4ECD8', textColor: '#5C4B37', followSystem: false },
    { name: '夜间', bgColor: '#1E1E1E', textColor: '#D4D4D4', followSystem: false }
  ];
  
  // 预设字体颜色
  private textColors: TextColorOption[] = [
    { name: '黑色', color: '#000000' },
    { name: '深灰', color: '#333333' },
    { name: '灰色', color: '#666666' },
    { name: '白色', color: '#FFFFFF' },
    { name: '淡灰', color: '#D4D4D4' },
    { name: '棕色', color: '#5C4B37' }
  ];

  /**
   * 复制当前设置并返回新对象
   */
  private copySettings(): EBookReadingSettings {
    return {
      fontSize: this.settings.fontSize,
      fontFamily: this.settings.fontFamily,
      fontPath: this.settings.fontPath || '',
      fontWeight: this.settings.fontWeight || 400,
      lineHeight: this.settings.lineHeight,
      backgroundColor: this.settings.backgroundColor,
      textColor: this.settings.textColor,
      themeBgImage: this.settings.themeBgImage || '',
      nightMode: this.settings.nightMode || false,
      followSystemTheme: this.settings.followSystemTheme !== false,
      pageMargin: this.settings.pageMargin,
      pageTopMargin: this.settings.pageTopMargin,
      pageBottomMargin: this.settings.pageBottomMargin,
      pageMode: this.settings.pageMode,
      brightness: this.settings.brightness,
      autoSave: this.settings.autoSave,
      saveInterval: this.settings.saveInterval,
      letterSpacing: this.settings.letterSpacing,
      paragraphSpacing: this.settings.paragraphSpacing,
      firstLineIndent: this.settings.firstLineIndent,
      textAlignment: this.settings.textAlignment,
      pageTurnAnimation: this.settings.pageTurnAnimation,
      tapToTurn: this.settings.tapToTurn,
      volumeKeyNavigation: this.settings.volumeKeyNavigation,
      keepScreenOn: this.settings.keepScreenOn,
      lockDeviceOrientation: this.settings.lockDeviceOrientation ?? false,
      showPageNumber: this.settings.showPageNumber,
      showProgress: this.settings.showProgress,
      showTime: this.settings.showTime,
      showBattery: this.settings.showBattery,
      backgroundType: this.settings.backgroundType,
      backgroundImagePath: this.settings.backgroundImagePath,
      backgroundImageOpacity: this.settings.backgroundImageOpacity
    };
  }

  /**
   * 更新字体大小
   */
  private updateFontSize(size: number): void {
    const newSettings = this.copySettings();
    newSettings.fontSize = size;
    this.onSettingsChange(newSettings);
  }

  /**
   * 更新行高
   */
  private updateLineHeight(height: number): void {
    const newSettings = this.copySettings();
    newSettings.lineHeight = height;
    this.onSettingsChange(newSettings);
  }

  /**
   * 更新页边距
   */
  private updatePageMargin(margin: number): void {
    const newSettings = this.copySettings();
    newSettings.pageMargin = margin;
    this.onSettingsChange(newSettings);
  }

  /**
   * 更新字体
   */
  private updateFont(fontFamily: string, fontPath: string): void {
    const newSettings = this.copySettings();
    newSettings.fontFamily = fontFamily;
    newSettings.fontPath = fontPath;
    this.onSettingsChange(newSettings);
    logger.info(TAG, `字体已更新: ${fontFamily}, path=${fontPath}`);
  }

  /**
   * 更新字体粗细
   */
  private updateFontWeight(weight: number): void {
    const newSettings = this.copySettings();
    newSettings.fontWeight = weight;
    this.onSettingsChange(newSettings);
  }

  /**
   * 获取当前字体显示名称
   */
  private getCurrentFontDisplayName(): string {
    const currentFamily = this.settings.fontFamily;
    
    const systemFont = this.systemFonts.find(f => f.name === currentFamily);
    if (systemFont) {
      return systemFont.displayName;
    }
    
    const customFont = this.customFonts.find(f => f.familyName === currentFamily);
    if (customFont) {
      return customFont.displayName;
    }
    
    return '系统默认';
  }

  aboutToAppear(): void {
    // 加载字体列表
    const fontManager = getFontManager();
    this.systemFonts = fontManager.getSystemFonts();
    this.customFonts = fontManager.getCustomFonts();
    logger.info(TAG, `字体列表已加载: 系统字体=${this.systemFonts.length}个, 自定义字体=${this.customFonts.length}个, 当前字体=${this.settings.fontFamily}`);
  }

  /**
   * 更新主题
   * 注意：选择"自动"主题时，followSystemTheme 为 true，会跟随系统主题
   * 选择其他主题时，followSystemTheme 为 false，不会跟随系统主题
   */
  private updateTheme(theme: ReadingTheme): void {
    const newSettings = this.copySettings();
    
    if (theme.followSystem) {
      // 自动模式：根据当前系统主题设置颜色
      const isDarkMode = this.currentTheme === ThemeType.DARK;
      newSettings.backgroundColor = isDarkMode ? '#1E1E1E' : '#FFFFFF';
      newSettings.textColor = isDarkMode ? '#D4D4D4' : '#000000';
      newSettings.nightMode = isDarkMode;
    } else {
      newSettings.backgroundColor = theme.bgColor;
      newSettings.textColor = theme.textColor;
      // 检测是否为夜间模式
      newSettings.nightMode = theme.bgColor === '#1E1E1E';
    }
    
    // 根据主题类型设置是否跟随系统主题
    newSettings.followSystemTheme = theme.followSystem;
    this.onSettingsChange(newSettings);
    logger.info(TAG, `主题已更新: ${theme.name}, followSystemTheme=${theme.followSystem}`);
  }

  /**
   * 更新字体颜色
   */
  private updateTextColor(color: string): void {
    const newSettings = this.copySettings();
    newSettings.textColor = color;
    // 手动设置字体颜色时，关闭跟随系统主题
    newSettings.followSystemTheme = false;
    this.onSettingsChange(newSettings);
    logger.info(TAG, `字体颜色已更新: ${color}`);
  }

  /**
   * 更新翻页模式
   */
  private updatePageMode(mode: EBookPageMode): void {
    const newSettings = this.copySettings();
    newSettings.pageMode = mode;
    this.onSettingsChange(newSettings);
  }

  private updateDeviceOrientationLock(enabled: boolean): void {
    const newSettings = this.copySettings();
    newSettings.lockDeviceOrientation = enabled;
    this.onSettingsChange(newSettings);
  }

  private getDeviceOrientationLockHint(): string {
    return (this.settings.lockDeviceOrientation ?? false)
      ? '保持当前屏幕方向，阅读时旋转设备不会改变方向'
      : '关闭后会跟随系统旋转策略，适合临时横屏阅读';
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text('阅读设置')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))

        Blank()

        Button({ type: ButtonType.Circle }) {
          Image($r('app.media.ic_close'))
            .width(20)
            .height(20)
            .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
        }
        .width(32)
        .height(32)
        .backgroundColor('transparent')
        .onClick(() => {
          this.onClose();
        })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 16, bottom: 16 })
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.currentTheme))

      Divider()
        .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))

      // 设置内容
      Scroll() {
        Column({ space: 20 }) {
          // 字体大小
          this.buildFontSizeSetting()

          Divider()
            .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))

          // 行高
          this.buildLineHeightSetting()

          Divider()
            .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))

          // 页边距
          this.buildPageMarginSetting()

          Divider()
            .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))

          // 字体选择
          this.buildFontSetting()

          Divider()
            .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))

          // 阅读主题
          this.buildThemeSetting()

          Divider()
            .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))

          // 字体颜色（仅在非自动模式下显示）
          if (!this.settings.followSystemTheme) {
            this.buildTextColorSetting()

            Divider()
              .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))
          }

          // 翻页模式
          this.buildPageModeSetting()

          Divider()
            .color(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))

          // 其他设置
          this.buildOtherSettings()
        }
        .width('100%')
        .padding({ left: 20, right: 20, top: 16, bottom: 16 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)

      // 底部操作栏
      Row({ space: 12 }) {
        Button('恢复默认')
          .fontSize(14)
          .layoutWeight(1)
          .height(44)
          .backgroundColor('transparent')
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
          .border({
            width: 1,
            color: ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme)
          })
          .onClick(() => {
            this.resetToDefault();
          })

        Button('完成')
          .fontSize(14)
          .layoutWeight(1)
          .height(44)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.currentTheme))
          .onClick(() => {
            this.onClose();
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12, bottom: 12 })
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
    }
    .width('100%')
    .height('100%')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_primary', this.currentTheme))
  }

  /**
   * 构建字体大小设置
   */
  @Builder
  buildFontSizeSetting() {
    Column({ space: 12 }) {
      Row() {
        Text('字体大小')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))

        Blank()

        Text(`${this.settings.fontSize}`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')

      Row({ space: 12 }) {
        Button('A-')
          .fontSize(14)
          .width(50)
          .height(36)
          .backgroundColor('transparent')
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .border({
            width: 1,
            color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme)
          })
          .onClick(() => {
            if (this.settings.fontSize > 12) {
              this.updateFontSize(this.settings.fontSize - 2);
            }
          })

        Slider({
          value: this.settings.fontSize,
          min: 12,
          max: 32,
          step: 2,
          style: SliderStyle.InSet
        })
          .layoutWeight(1)
          .trackColor(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
          .showTips(false)
          .onChange((value: number) => {
            this.updateFontSize(Math.round(value));
          })

        Button('A+')
          .fontSize(14)
          .width(50)
          .height(36)
          .backgroundColor('transparent')
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .border({
            width: 1,
            color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme)
          })
          .onClick(() => {
            if (this.settings.fontSize < 32) {
              this.updateFontSize(this.settings.fontSize + 2);
            }
          })
      }
      .width('100%')

      // 预览文本
      Text('这是预览文本 This is preview text')
        .fontSize(this.settings.fontSize)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
        .lineHeight(this.settings.fontSize * this.settings.lineHeight)
        .padding(16)
        .width('100%')
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_secondary', this.currentTheme))
        .borderRadius(8)
    }
  }

  /**
   * 构建行高设置
   */
  @Builder
  buildLineHeightSetting() {
    Column({ space: 12 }) {
      Row() {
        Text('行高')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))

        Blank()

        Text(`${this.settings.lineHeight.toFixed(1)}`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')

      Slider({
        value: this.settings.lineHeight,
        min: 1.0,
        max: 3.0,
        step: 0.1,
        style: SliderStyle.InSet
      })
        .width('100%')
        .trackColor(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))
        .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
        .showTips(false)
        .onChange((value: number) => {
          this.updateLineHeight(Math.round(value * 10) / 10);
        })
    }
  }

  /**
   * 构建字体选择设置
   */
  @Builder
  buildFontSetting() {
    Column({ space: 12 }) {
      // 字体粗细
      Row() {
        Text('字体粗细')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))

        Blank()

        Text(`${this.settings.fontWeight || 400}`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')

      Slider({
        value: this.settings.fontWeight || 400,
        min: 300,
        max: 700,
        step: 100,
        style: SliderStyle.InSet
      })
        .width('100%')
        .trackColor(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))
        .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
        .showTips(false)
        .onChange((value: number) => {
          this.updateFontWeight(Math.round(value));
        })

      // 字体选择
      Row() {
        Text('字体')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))

        Blank()

        Text(this.getCurrentFontDisplayName())
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
      }
      .width('100%')
      .onClick(() => {
        this.showFontPicker = !this.showFontPicker;
      })

      if (this.showFontPicker) {
        Column({ space: 8 }) {
          Text('系统字体')
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
            .width('100%')

          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.systemFonts, (font: SystemFont) => {
              Button(font.displayName)
                .fontSize(12)
                .height(32)
                .margin({ right: 8, bottom: 8 })
                .backgroundColor(this.settings.fontFamily === font.name ?
                  ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme) :
                  ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.currentTheme))
                .fontColor(this.settings.fontFamily === font.name ?
                  Color.White :
                  ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
                .onClick(() => {
                  this.updateFont(font.name, '');
                })
            }, (font: SystemFont) => font.id)
          }
          .width('100%')

          if (this.customFonts.length > 0) {
            Text('自定义字体')
              .fontSize(12)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
              .width('100%')
              .margin({ top: 8 })

            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(this.customFonts, (font: CustomFont) => {
                Button(font.displayName)
                  .fontSize(12)
                  .height(32)
                  .margin({ right: 8, bottom: 8 })
                  .backgroundColor(this.settings.fontFamily === font.familyName ?
                    ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme) :
                    ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.currentTheme))
                  .fontColor(this.settings.fontFamily === font.familyName ?
                    Color.White :
                    ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
                  .onClick(() => {
                    this.updateFont(font.familyName, font.filePath);
                  })
              }, (font: CustomFont) => font.id)
            }
            .width('100%')
          }
        }
        .width('100%')
        .padding(12)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.currentTheme))
        .borderRadius(8)
      }
    }
  }

  /**
   * 构建页边距设置
   */
  @Builder
  buildPageMarginSetting() {
    Column({ space: 12 }) {
      Row() {
        Text('页边距')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))

        Blank()

        Text(`${this.settings.pageMargin}`)
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')

      Slider({
        value: this.settings.pageMargin,
        min: 10,
        max: 50,
        step: 5,
        style: SliderStyle.InSet
      })
        .width('100%')
        .trackColor(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))
        .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
        .showTips(false)
        .onChange((value: number) => {
          this.updatePageMargin(Math.round(value));
        })
    }
  }

  /**
   * 构建主题提示 Popup 内容
   */
  @Builder
  buildThemeHintPopup() {
    Column({ space: 8 }) {
      Text('主题跟随说明')
        .fontSize(14)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppColors.textPrimary)
      
      Text('• "默认"和"夜间"主题会自动跟随App全局主题切换')
        .fontSize(12)
        .fontColor(AppColors.textSecondary)
      
      Text('• "护眼"和"羊皮纸"主题为固定主题，不会跟随系统变化')
        .fontSize(12)
        .fontColor(AppColors.textSecondary)
      
      Row() {
        Text(this.settings.followSystemTheme !== false ? '当前：跟随系统' : '当前：固定主题')
          .fontSize(12)
          .fontColor(this.settings.followSystemTheme !== false ? AppColors.success : AppColors.warning)
          .fontWeight(FontWeight.Medium)
      }
      .margin({ top: 4 })
    }
    .padding(12)
    .backgroundColor(Color.White)
    .borderRadius(8)
    .shadow({ radius: 8, color: AppColors.getShadowColor(4), offsetX: 0, offsetY: 2 })
  }

  /**
   * 构建主题设置
   */
  @Builder
  buildThemeSetting() {
    Column({ space: 12 }) {
      Row() {
        Text('阅读主题')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
        
        // 提示图标，点击显示 popup
        Image($r('app.media.ic_public_help'))
          .width(18)
          .height(18)
          .fillColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
          .margin({ left: 6 })
          .onClick(() => {
            this.showThemeHintPopup = !this.showThemeHintPopup;
          })
          .bindPopup(this.showThemeHintPopup, {
            builder: this.buildThemeHintPopup,
            placement: Placement.Bottom,
            popupColor: Color.Transparent,
            enableArrow: true,
            onStateChange: (e) => {
              if (!e.isVisible) {
                this.showThemeHintPopup = false;
              }
            }
          })
        
        Blank()
        
        // 显示当前跟随状态
        Text(this.settings.followSystemTheme !== false ? '跟随系统' : '固定主题')
          .fontSize(12)
          .fontColor(this.settings.followSystemTheme !== false 
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .backgroundColor(this.settings.followSystemTheme !== false 
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme) + '20'
            : ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))
          .borderRadius(4)
      }
      .width('100%')

      Row({ space: 8 }) {
        ForEach(this.themes, (theme: ReadingTheme) => {
          Column({ space: 4 }) {
            Stack() {
              if (theme.followSystem) {
                // 自动模式：显示渐变效果
                Column() {
                  Row() {
                    Column()
                      .width('50%')
                      .height('100%')
                      .backgroundColor('#FFFFFF')
                    Column()
                      .width('50%')
                      .height('100%')
                      .backgroundColor('#1E1E1E')
                  }
                  .width('100%')
                  .height('100%')
                }
                .width(44)
                .height(44)
                .borderRadius(8)
                .clip(true)
                .border({
                  width: this.settings.followSystemTheme ? 2 : 1,
                  color: this.settings.followSystemTheme 
                    ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme)
                    : ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme)
                })
              } else {
                Column()
                  .width(44)
                  .height(44)
                  .backgroundColor(theme.bgColor)
                  .borderRadius(8)
                  .border({
                    width: !this.settings.followSystemTheme && this.settings.backgroundColor === theme.bgColor ? 2 : 1,
                    color: !this.settings.followSystemTheme && this.settings.backgroundColor === theme.bgColor 
                      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme)
                      : ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme)
                  })
              }
            }
            .width(44)
            .height(44)
            .onClick(() => {
              this.updateTheme(theme);
            })

            Text(theme.name)
              .fontSize(11)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
          }
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
  }

  /**
   * 构建字体颜色设置
   */
  @Builder
  buildTextColorSetting() {
    Column({ space: 12 }) {
      Row() {
        Text('字体颜色')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))

        Blank()

        // 显示当前颜色
        Row({ space: 6 }) {
          Column()
            .width(20)
            .height(20)
            .backgroundColor(this.settings.textColor)
            .borderRadius(4)
            .border({
              width: 1,
              color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme)
            })
          
          Text(this.settings.textColor)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
        }
      }
      .width('100%')

      // 预设颜色选择
      Row({ space: 8 }) {
        ForEach(this.textColors, (colorOption: TextColorOption) => {
          Column({ space: 4 }) {
            Column()
              .width(36)
              .height(36)
              .backgroundColor(colorOption.color)
              .borderRadius(8)
              .border({
                width: this.settings.textColor === colorOption.color ? 2 : 1,
                color: this.settings.textColor === colorOption.color 
                  ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme)
                  : ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme)
              })
              .onClick(() => {
                this.updateTextColor(colorOption.color);
              })

            Text(colorOption.name)
              .fontSize(10)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
          }
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      // 预览效果
      Text('预览文本 Preview')
        .fontSize(this.settings.fontSize)
        .fontColor(this.settings.textColor)
        .lineHeight(this.settings.fontSize * this.settings.lineHeight)
        .padding(16)
        .width('100%')
        .backgroundColor(this.settings.backgroundColor)
        .borderRadius(8)
        .border({
          width: 1,
          color: ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme)
        })
    }
  }

  /**
   * 构建翻页模式设置
   */
  @Builder
  buildPageModeSetting() {
    Column({ space: 12 }) {
      Text('翻页模式')
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
        .width('100%')

      Row({ space: 12 }) {
        // 仿真翻页（Reader Kit flipMode = '0'）
        Button('仿真翻页')
          .fontSize(14)
          .layoutWeight(1)
          .height(40)
          .backgroundColor(this.settings.pageMode === EBookPageMode.SIMULATION 
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme)
            : 'transparent')
          .fontColor(this.settings.pageMode === EBookPageMode.SIMULATION
            ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .border({
            width: 1,
            color: this.settings.pageMode === EBookPageMode.SIMULATION
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme)
          })
          .onClick(() => {
            this.updatePageMode(EBookPageMode.SIMULATION);
          })

        // 横向滑动（Reader Kit flipMode = '1'）
        Button('横向滑动')
          .fontSize(14)
          .layoutWeight(1)
          .height(40)
          .backgroundColor(this.settings.pageMode === EBookPageMode.HORIZONTAL 
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme)
            : 'transparent')
          .fontColor(this.settings.pageMode === EBookPageMode.HORIZONTAL
            ? ThemeAwareHelper.getTestManagementThemedColor('text_white', this.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          .border({
            width: 1,
            color: this.settings.pageMode === EBookPageMode.HORIZONTAL
              ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme)
              : ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme)
          })
          .onClick(() => {
            this.updatePageMode(EBookPageMode.HORIZONTAL);
          })
      }
      .width('100%')
    }
  }

  /**
   * 构建其他设置
   */
  @Builder
  buildOtherSettings() {
    Column({ space: 16 }) {
      Text('其他设置')
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
        .width('100%')

      // 自动保存
      Row() {
        Text('自动保存进度')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))

        Blank()

        Toggle({ type: ToggleType.Switch, isOn: this.settings.autoSave })
          .onChange((isOn: boolean) => {
            const newSettings = this.copySettings();
            newSettings.autoSave = isOn;
            this.onSettingsChange(newSettings);
          })
      }
      .width('100%')

      Row() {
        Column() {
          Text('锁定方向')
            .fontSize(16)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))
          Text(this.getDeviceOrientationLockHint())
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.currentTheme))
            .margin({ top: 2 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.settings.lockDeviceOrientation ?? false })
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
          .onChange((isOn: boolean) => {
            this.updateDeviceOrientationLock(isOn);
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })

      // 保存间隔
      if (this.settings.autoSave) {
        Row() {
          Text('保存间隔（秒）')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.currentTheme))

          Blank()

          Text(`${this.settings.saveInterval}`)
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
            .fontWeight(FontWeight.Bold)
        }
        .width('100%')

        Slider({
          value: this.settings.saveInterval,
          min: 10,
          max: 120,
          step: 10,
          style: SliderStyle.InSet
        })
          .width('100%')
          .trackColor(ThemeAwareHelper.getTestManagementThemedColor('divider', this.currentTheme))
          .selectedColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.currentTheme))
          .showTips(false)
          .onChange((value: number) => {
            const newSettings = this.copySettings();
            newSettings.saveInterval = Math.round(value);
            this.onSettingsChange(newSettings);
          })
      }
    }
  }

  /**
   * 恢复默认设置
   */
  private resetToDefault(): void {
    // 使用全局默认设置常量（ArkTS 不支持展开运算符，需要显式复制）
    const defaultSettings: EBookReadingSettings = {
      fontSize: DEFAULT_EBOOK_READING_SETTINGS.fontSize,
      fontFamily: DEFAULT_EBOOK_READING_SETTINGS.fontFamily,
      fontPath: DEFAULT_EBOOK_READING_SETTINGS.fontPath,
      fontWeight: DEFAULT_EBOOK_READING_SETTINGS.fontWeight,
      lineHeight: DEFAULT_EBOOK_READING_SETTINGS.lineHeight,
      backgroundColor: DEFAULT_EBOOK_READING_SETTINGS.backgroundColor,
      textColor: DEFAULT_EBOOK_READING_SETTINGS.textColor,
      themeBgImage: DEFAULT_EBOOK_READING_SETTINGS.themeBgImage,
      nightMode: DEFAULT_EBOOK_READING_SETTINGS.nightMode,
      followSystemTheme: DEFAULT_EBOOK_READING_SETTINGS.followSystemTheme,
      pageMargin: DEFAULT_EBOOK_READING_SETTINGS.pageMargin,
      pageTopMargin: DEFAULT_EBOOK_READING_SETTINGS.pageTopMargin,
      pageBottomMargin: DEFAULT_EBOOK_READING_SETTINGS.pageBottomMargin,
      pageMode: DEFAULT_EBOOK_READING_SETTINGS.pageMode,
      brightness: DEFAULT_EBOOK_READING_SETTINGS.brightness,
      autoSave: DEFAULT_EBOOK_READING_SETTINGS.autoSave,
      saveInterval: DEFAULT_EBOOK_READING_SETTINGS.saveInterval,
      letterSpacing: DEFAULT_EBOOK_READING_SETTINGS.letterSpacing,
      paragraphSpacing: DEFAULT_EBOOK_READING_SETTINGS.paragraphSpacing,
      firstLineIndent: DEFAULT_EBOOK_READING_SETTINGS.firstLineIndent,
      textAlignment: DEFAULT_EBOOK_READING_SETTINGS.textAlignment,
      pageTurnAnimation: DEFAULT_EBOOK_READING_SETTINGS.pageTurnAnimation,
      tapToTurn: DEFAULT_EBOOK_READING_SETTINGS.tapToTurn,
      volumeKeyNavigation: DEFAULT_EBOOK_READING_SETTINGS.volumeKeyNavigation,
      keepScreenOn: DEFAULT_EBOOK_READING_SETTINGS.keepScreenOn,
      lockDeviceOrientation: DEFAULT_EBOOK_READING_SETTINGS.lockDeviceOrientation ?? false,
      showPageNumber: DEFAULT_EBOOK_READING_SETTINGS.showPageNumber,
      showProgress: DEFAULT_EBOOK_READING_SETTINGS.showProgress,
      showTime: DEFAULT_EBOOK_READING_SETTINGS.showTime,
      showBattery: DEFAULT_EBOOK_READING_SETTINGS.showBattery,
      backgroundType: DEFAULT_EBOOK_READING_SETTINGS.backgroundType,
      backgroundImagePath: DEFAULT_EBOOK_READING_SETTINGS.backgroundImagePath,
      backgroundImageOpacity: DEFAULT_EBOOK_READING_SETTINGS.backgroundImageOpacity
    };
    this.onSettingsChange(defaultSettings);
    logger.info(TAG, '已恢复默认设置');
  }
}

/**
 * 阅读主题接口
 */
interface ReadingTheme {
  name: string;
  bgColor: string;
  textColor: string;
  followSystem: boolean;  // 是否跟随系统主题
}

/**
 * 字体颜色选项接口
 */
interface TextColorOption {
  name: string;
  color: string;
}

