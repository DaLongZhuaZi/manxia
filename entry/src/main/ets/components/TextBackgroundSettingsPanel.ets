import { common } from '@kit.AbilityKit';
import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
/**
 * 小说阅读器背景设置面板
 * 独立对话框，提供预设主题、自定义背景图片、图片不透明度、文字颜色等设置
 * 风格与漫画阅读器对话框一致：竖屏底部上滑、横屏右侧滑入
 */

import {
  TextReaderSettings,
  BackgroundType,
  CustomBackground,
  PRESET_BACKGROUNDS,
  PresetBackground,
  SavedBackgroundImage
} from 'manxia_core/src/main/ets/Models/TextReaderModels';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ThemeManager } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { EBookDataManager, BackgroundImageInfo } from 'manxia_core/src/main/ets/Framework/Data/EBookDataManager';
import { SettingsManager, SettingKeys } from '../Framework/Managers/SettingsManager';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import fs from '@ohos.file.fs';
import { curves, UIContext, display } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';

const TAG = 'TextBackgroundSettingsPanel';

/**
 * 回调接口
 */
interface TextBackgroundSettingsCallbacks {
  onSettingsChange: (settings: TextReaderSettings) => void;
  onClose: () => void;
}

@Component
export struct TextBackgroundSettingsPanel {
  @Prop settings: TextReaderSettings;
  @Prop isVisible: boolean;
  @Prop callbacks: TextBackgroundSettingsCallbacks;
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';

  // 动画状态
  @State private panelOpacity: number = 0;
  @State private panelTranslateY: number = 300;
  @State private panelTranslateX: number = 320;
  @State private backdropOpacity: number = 0;
  @State private themeState: ThemeAwareState = new ThemeAwareState();
  @State private isLandscape: boolean = false;
  @State private isClosing: boolean = false;

  // 背景图片
  @State private allAvailableBackgroundImages: BackgroundImageInfo[] = [];
  @State private showOtherBgImagePicker: boolean = false;
  private ebookDataManager: EBookDataManager = EBookDataManager.getInstance();
  private uiContext: UIContext | undefined = undefined;

  aboutToAppear() {
    this.uiContext = this.getUIContext();
    this.detectScreenOrientation();

    ThemeAwareHelper.initializeThemeAware('TextBackgroundSettingsPanel', this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });

    this.loadAllAvailableBackgroundImages();

    setTimeout(() => {
      this.showPanel();
    }, 50);
  }

  aboutToDisappear() {
    ThemeAwareHelper.cleanupThemeAware('TextBackgroundSettingsPanel');
  }

  private detectScreenOrientation(): void {
    try {
      const displayInfo = display.getDefaultDisplaySync();
      if (displayInfo) {
        const w = displayInfo.width / (displayInfo.densityPixels || 1);
        const h = displayInfo.height / (displayInfo.densityPixels || 1);
        this.isLandscape = w > h;
      }
    } catch (error) {
      logger.error(TAG, `屏幕方向检测失败: ${String(error)}`);
    }
  }

  private showPanel(): void {
    if (!this.uiContext) {
      this.panelOpacity = 1;
      this.panelTranslateY = 0;
      this.panelTranslateX = 0;
      this.backdropOpacity = 0.5;
      return;
    }

    this.uiContext.animateTo({
      duration: 200,
      curve: curves.initCurve(Curve.EaseOut)
    }, () => {
      this.backdropOpacity = 0.5;
    });

    if (this.isLandscape) {
      this.uiContext.animateTo({
        duration: 250,
        curve: curves.initCurve(Curve.EaseOut)
      }, () => {
        this.panelOpacity = 1;
        this.panelTranslateX = 0;
      });
    } else {
      this.uiContext.animateTo({
        duration: 300,
        curve: curves.initCurve(Curve.EaseOut)
      }, () => {
        this.panelOpacity = 1;
        this.panelTranslateY = 0;
      });
    }
  }

  private hidePanel(): void {
    if (this.isClosing) {
      return;
    }
    this.isClosing = true;

    if (!this.uiContext) {
      this.panelOpacity = 0;
      this.panelTranslateY = 300;
      this.panelTranslateX = 320;
      this.backdropOpacity = 0;
      this.callbacks.onClose();
      this.isClosing = false;
      return;
    }

    if (this.isLandscape) {
      this.uiContext.animateTo({
        duration: 200,
        curve: curves.initCurve(Curve.EaseIn)
      }, () => {
        this.panelOpacity = 0;
        this.panelTranslateX = 320;
      });
    } else {
      this.uiContext.animateTo({
        duration: 200,
        curve: curves.initCurve(Curve.EaseIn)
      }, () => {
        this.panelOpacity = 0;
        this.panelTranslateY = 300;
      });
    }

    this.uiContext.animateTo({
      duration: 200,
      curve: curves.initCurve(Curve.EaseIn)
    }, () => {
      this.backdropOpacity = 0;
    });

    setTimeout(() => {
      this.callbacks.onClose();
      this.isClosing = false;
    }, 220);
  }

  private notifyChange(): void {
    if (this.callbacks.onSettingsChange) {
      this.callbacks.onSettingsChange(this.settings);
    }
  }

  /**
   * 加载所有可用的背景图片
   */
  private async loadAllAvailableBackgroundImages(): Promise<void> {
    try {
      const ebookImages = await this.ebookDataManager.getAllCustomBackgroundImages();
      const allImages: BackgroundImageInfo[] = [];
      const seenPaths = new Set<string>();

      const settingsManager = SettingsManager.getInstance();
      const globalBgImagePath = settingsManager.getString(SettingKeys.GLOBAL_TEXT_BG_IMAGE_PATH, '');
      if (globalBgImagePath && globalBgImagePath.length > 0) {
        seenPaths.add(globalBgImagePath);
        const globalBgInfo: BackgroundImageInfo = {
          bookId: 'global',
          bookTitle: '全局默认背景',
          imagePath: globalBgImagePath
        };
        allImages.push(globalBgInfo);
      }

      for (const img of ebookImages) {
        if (!seenPaths.has(img.imagePath)) {
          seenPaths.add(img.imagePath);
          allImages.push(img);
        }
      }

      this.allAvailableBackgroundImages = allImages;
    } catch (error) {
      logger.error(TAG, `加载背景图片列表失败: ${String(error)}`);
    }
  }

  /**
   * 选择背景图片并复制到沙箱
   */
  private async selectBackgroundImage(): Promise<void> {
    try {
      const photoPicker = new photoAccessHelper.PhotoViewPicker();
      const result = await photoPicker.select({
        MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE,
        maxSelectNumber: 1
      });

      if (result.photoUris && result.photoUris.length > 0) {
        const sourceUri = result.photoUris[0];
        const savedPath = await this.copyImageToSandbox(sourceUri);
        if (!savedPath) return;

        if (!this.settings.savedBackgroundImages) {
          this.settings.savedBackgroundImages = [];
        }

        const exists = this.settings.savedBackgroundImages.some(
          (img: SavedBackgroundImage) => img.path === savedPath
        );

        if (!exists) {
          if (this.settings.savedBackgroundImages.length >= 10) {
            const oldImage = this.settings.savedBackgroundImages.shift();
            if (oldImage) this.deleteImageFile(oldImage.path);
          }
          this.settings.savedBackgroundImages.push({
            path: savedPath,
            addTime: Date.now()
          });
        }

        this.settings.background = {
          type: BackgroundType.IMAGE,
          imagePath: savedPath,
          imageOpacity: this.settings.background.imageOpacity ?? 0.3
        };
        this.notifyChange();
      }
    } catch (error) {
      logger.error(TAG, `选择图片失败: ${String(error)}`);
    }
  }

  private async copyImageToSandbox(sourceUri: string): Promise<string | null> {
    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext);
      const cacheDir: string = context.cacheDir;
      const timestamp = Date.now();
      const randomStr = Math.random().toString(36).substring(2, 8);
      const extension = this.getFileExtension(sourceUri);
      const destFileName = `bg_${timestamp}_${randomStr}${extension}`;
      const destPath = `${cacheDir}/${destFileName}`;

      const sourceFile = SafeFileUtils.openSync(sourceUri, fs.OpenMode.READ_ONLY);
      SafeFileUtils.copyFileSync(sourceFile.fd, destPath);
      SafeFileUtils.closeSync(sourceFile);
      return destPath;
    } catch (error) {
      logger.error(TAG, `复制图片失败: ${String(error)}`);
      return null;
    }
  }

  private getFileExtension(path: string): string {
    const lastDot = path.lastIndexOf('.');
    if (lastDot >= 0) return path.substring(lastDot);
    return '.jpg';
  }

  private deleteImageFile(path: string): void {
    try {
      if (path.includes('/bg_images/')) {
        SafeFileUtils.unlinkSync(path);
      }
    } catch (error) {
      logger.warn(TAG, `删除图片文件失败: ${String(error)}`);
    }
  }

  private showDeleteConfirmDialog(index: number): void {
    this.getUIContext().getPromptAction().showDialog({
      title: '删除背景图片',
      message: '确定要删除这张背景图片吗？',
      buttons: [
        { text: '取消', color: '#666666' },
        { text: '删除', color: '#FF4444' }
      ]
    }).then((result) => {
      if (result.index === 1) {
        this.deleteBackgroundImage(index);
      }
    }).catch((err: Error) => {
      logger.error(TAG, `显示对话框失败: ${err.message}`);
    });
  }

  private deleteBackgroundImage(index: number): void {
    if (!this.settings.savedBackgroundImages || index < 0 || index >= this.settings.savedBackgroundImages.length) {
      return;
    }
    const deletedPath = this.settings.savedBackgroundImages[index].path;
    this.deleteImageFile(deletedPath);
    this.settings.savedBackgroundImages.splice(index, 1);

    if (this.settings.background.type === BackgroundType.IMAGE &&
        this.settings.background.imagePath === deletedPath) {
      this.settings.background = {
        type: BackgroundType.COLOR,
        color: '#F5F0E1',
        imageOpacity: 1.0
      };
      this.settings.textStyle.textColor = '#5D4037';
    }
    this.notifyChange();
  }

  // ==================== 竖屏面板 ====================
  @Builder
  buildPortraitPanel() {
    Column() {
      Row() {
        Text('背景设置')
          .fontSize(18)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Button() {
          Image($r('app.media.ic_close'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.text_secondary'))
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .onClick(() => this.hidePanel())
      }
      .width('100%')
      .margin({ bottom: 16 })

      Scroll() {
        Column({ space: 20 }) {
          this.buildBackgroundContent()
        }
        .width('100%')
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      Row() {
        Button('完成')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_on_accent'))
          .backgroundColor($r('app.color.accent'))
          .layoutWeight(1)
          .height(40)
          .onClick(() => this.hidePanel())
      }
      .width('100%')
    }
    .width('100%')
    .constraintSize({ maxHeight: '75%' })
    .padding(20)
    .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
    .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
    .borderRadius({ topLeft: 16, topRight: 16 })
    .opacity(this.panelOpacity)
    .translate({ x: 0, y: this.panelTranslateY })
    .position({ x: 0, y: '100%' })
    .translate({ x: 0, y: '-100%' })
    .hitTestBehavior(HitTestMode.Default)
  }

  // ==================== 横屏面板 ====================
  @Builder
  buildLandscapePanel() {
    Row() {
      Column()
        .layoutWeight(1)
        .height('100%')
        .onClick(() => this.hidePanel())

      Column() {
        Row() {
          Text('背景设置')
            .fontSize(16)
            .fontFamily(this.appFontFamily)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          Button() {
            Image($r('app.media.ic_close'))
              .width(18)
              .height(18)
              .fillColor($r('app.color.text_secondary'))
          }
          .width(32)
          .height(32)
          .backgroundColor(Color.Transparent)
          .onClick(() => this.hidePanel())
        }
        .width('100%')
        .margin({ bottom: 12 })

        Scroll() {
          Column({ space: 16 }) {
            this.buildBackgroundContentCompact()
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)

        Button('完成')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_on_accent'))
          .backgroundColor($r('app.color.accent'))
          .width('100%')
          .height(36)
          .onClick(() => this.hidePanel())
      }
      .width(320)
      .height('100%')
      .padding(16)
      .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
      .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
      .borderRadius({ topLeft: 16, bottomLeft: 16 })
      .opacity(this.panelOpacity)
      .translate({ x: this.panelTranslateX })
      .hitTestBehavior(HitTestMode.Default)
    }
    .width('100%')
    .height('100%')
  }

  // ==================== 竖屏内容 ====================
  @Builder
  buildBackgroundContent() {
    // 预设主题
    Column({ space: 12 }) {
      Text('预设主题(同时设置背景主题与文本颜色)')
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(PRESET_BACKGROUNDS, (preset: PresetBackground) => {
          Column() {
            Text('Aa')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor(preset.textColor)
          }
          .width(52)
          .height(40)
          .backgroundColor(preset.backgroundColor)
          .borderRadius(8)
          .border({
            width: (this.settings.background.type === BackgroundType.COLOR &&
                   this.settings.background.color === preset.backgroundColor) ? 2 : 1,
            color: (this.settings.background.type === BackgroundType.COLOR &&
                   this.settings.background.color === preset.backgroundColor) ?
              $r('app.color.accent') : $r('app.color.divider')
          })
          .justifyContent(FlexAlign.Center)
          .margin({ right: 8, bottom: 8 })
          .onClick(() => {
            this.settings.background = {
              type: BackgroundType.COLOR,
              color: preset.backgroundColor,
              imageOpacity: 1.0
            };
            this.settings.textStyle.textColor = preset.textColor;
            this.notifyChange();
          })
        })
      }
      .width('100%')
    }
    .width('100%')

    Divider().color($r('app.color.divider'))

    // 自定义背景图片
    Column({ space: 12 }) {
      Row() {
        Text('自定义背景图片')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
        Blank()
        Row({ space: 8 }) {
          if (this.allAvailableBackgroundImages.length > 0) {
            Button('已有')
              .fontSize(12)
              .fontFamily(this.appFontFamily)
              .height(28)
              .backgroundColor($r('app.color.accent_secondary'))
              .fontColor(Color.White)
              .onClick(() => {
                this.showOtherBgImagePicker = !this.showOtherBgImagePicker;
              })
          }
          Button('添加')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .height(28)
            .backgroundColor($r('app.color.accent'))
            .fontColor(Color.White)
            .onClick(() => {
              this.selectBackgroundImage();
            })
        }
      }
      .width('100%')

      // 其他电子书背景图片选择器
      if (this.showOtherBgImagePicker && this.allAvailableBackgroundImages.length > 0) {
        Column({ space: 8 }) {
          Text('选择已有背景图片')
            .fontSize(12)
            .fontFamily(this.appFontFamily)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')

          Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
            ForEach(this.allAvailableBackgroundImages, (item: BackgroundImageInfo) => {
              Column({ space: 2 }) {
                Image(item.imagePath.startsWith('/') ? 'file://' + item.imagePath : item.imagePath)
                  .width(60)
                  .height(45)
                  .objectFit(ImageFit.Contain)
                  .borderRadius(6)
                  .backgroundColor($r('app.color.comp_background_tertiary'))
                  .border({
                    width: this.settings.background.imagePath === item.imagePath ? 2 : 0,
                    color: $r('app.color.accent')
                  })

                Text(item.bookTitle)
                  .fontSize(9)
                  .fontFamily(this.appFontFamily)
                  .fontColor($r('app.color.text_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width(60)
                  .textAlign(TextAlign.Center)
              }
              .margin({ right: 8, bottom: 8 })
              .onClick(() => {
                this.settings.background = {
                  type: BackgroundType.IMAGE,
                  imagePath: item.imagePath,
                  imageOpacity: this.settings.background.imageOpacity || 1.0
                };
                this.showOtherBgImagePicker = false;
                this.notifyChange();
              })
            })
          }
          .width('100%')
        }
        .width('100%')
        .padding(8)
        .backgroundColor($r('app.color.comp_background_tertiary'))
        .borderRadius(8)
      }

      // 已保存的背景图片缩略图
      if (this.settings.savedBackgroundImages && this.settings.savedBackgroundImages.length > 0) {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.settings.savedBackgroundImages, (savedImg: SavedBackgroundImage, index: number) => {
            Stack() {
              Image(savedImg.path.startsWith('/') ? 'file://' + savedImg.path : savedImg.path)
                .width(60)
                .height(45)
                .objectFit(ImageFit.Contain)
                .borderRadius(6)
                .backgroundColor($r('app.color.comp_background_tertiary'))
                .border({
                  width: (this.settings.background.type === BackgroundType.IMAGE &&
                         this.settings.background.imagePath === savedImg.path) ? 2 : 0,
                  color: $r('app.color.accent')
                })

              if (this.settings.background.type === BackgroundType.IMAGE &&
                  this.settings.background.imagePath === savedImg.path) {
                Column()
                  .width(16)
                  .height(16)
                  .backgroundColor($r('app.color.accent'))
                  .borderRadius(8)
                  .position({ x: 44, y: -4 })
              }
            }
            .width(60)
            .height(45)
            .margin({ right: 8, bottom: 8 })
            .onClick(() => {
              this.settings.background = {
                type: BackgroundType.IMAGE,
                imagePath: savedImg.path,
                imageOpacity: this.settings.background.imageOpacity || 1.0
              };
              this.notifyChange();
            })
            .gesture(
              LongPressGesture()
                .onAction(() => {
                  this.showDeleteConfirmDialog(index);
                })
            )
          })
        }
        .width('100%')

        Text('长按图片可删除')
          .fontSize(11)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
      } else {
        Text('暂无保存的背景图片')
          .fontSize(13)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .padding({ top: 8, bottom: 8 })
      }

      // 图片不透明度
      if (this.settings.background.type === BackgroundType.IMAGE) {
        Column({ space: 8 }) {
          Row() {
            Text('图片不透明度')
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Text(`${Math.round((this.settings.background.imageOpacity || 1) * 100)}%`)
              .fontSize(14)
              .fontFamily(this.appFontFamily)
              .fontColor($r('app.color.accent'))
          }
          .width('100%')

          Slider({
            value: (this.settings.background.imageOpacity || 1) * 100,
            min: 10,
            max: 100,
            step: 5
          })
            .width('100%')
            .trackColor($r('app.color.divider'))
            .selectedColor($r('app.color.accent'))
            .onChange((value: number) => {
              this.settings.background.imageOpacity = value / 100;
              this.notifyChange();
            })
        }
        .width('100%')
        .margin({ top: 8 })
      }
    }
    .width('100%')

    // 文字颜色（图片背景时手动选择）
    if (this.settings.background.type === BackgroundType.IMAGE) {
      Divider().color($r('app.color.divider'))

      Column({ space: 12 }) {
        Text('文字颜色')
          .fontSize(14)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')

        Row({ space: 8 }) {
          ForEach(['#333333', '#FFFFFF', '#5D4037', '#2E7D32', '#1565C0', '#D4D4D4'], (color: string) => {
            Column()
              .width(32)
              .height(32)
              .backgroundColor(color)
              .borderRadius(16)
              .border({
                width: this.settings.textStyle.textColor === color ? 2 : 1,
                color: this.settings.textStyle.textColor === color ?
                  $r('app.color.accent') : $r('app.color.divider')
              })
              .onClick(() => {
                this.settings.textStyle.textColor = color;
                this.notifyChange();
              })
          })
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  // ==================== 横屏紧凑内容 ====================
  @Builder
  buildBackgroundContentCompact() {
    // 预设主题（紧凑）
    Column() {
      Text('预设主题')
        .fontSize(12)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .margin({ bottom: 6 })

      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        ForEach(PRESET_BACKGROUNDS, (preset: PresetBackground) => {
          Column() {
            Text('Aa')
              .fontSize(11)
              .fontFamily(this.appFontFamily)
              .fontColor(preset.textColor)
          }
          .width(40)
          .height(32)
          .backgroundColor(preset.backgroundColor)
          .borderRadius(6)
          .border({
            width: (this.settings.background.type === BackgroundType.COLOR &&
                   this.settings.background.color === preset.backgroundColor) ? 2 : 1,
            color: (this.settings.background.type === BackgroundType.COLOR &&
                   this.settings.background.color === preset.backgroundColor) ?
              $r('app.color.accent') : $r('app.color.divider')
          })
          .justifyContent(FlexAlign.Center)
          .margin({ right: 6, bottom: 6 })
          .onClick(() => {
            this.settings.background = {
              type: BackgroundType.COLOR,
              color: preset.backgroundColor,
              imageOpacity: 1.0
            };
            this.settings.textStyle.textColor = preset.textColor;
            this.notifyChange();
          })
        })
      }
      .width('100%')
    }
    .width('100%')

    Divider().color($r('app.color.divider'))

    // 自定义背景（紧凑）
    Column() {
      Row() {
        Text('背景图片')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)

        Button('添加')
          .fontSize(10)
          .fontFamily(this.appFontFamily)
          .height(24)
          .backgroundColor($r('app.color.accent'))
          .fontColor(Color.White)
          .onClick(() => {
            this.selectBackgroundImage();
          })
      }
      .width('100%')
      .margin({ bottom: 8 })

      if (this.settings.savedBackgroundImages && this.settings.savedBackgroundImages.length > 0) {
        Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
          ForEach(this.settings.savedBackgroundImages, (savedImg: SavedBackgroundImage, index: number) => {
            Image(savedImg.path.startsWith('/') ? 'file://' + savedImg.path : savedImg.path)
              .width(48)
              .height(36)
              .objectFit(ImageFit.Contain)
              .borderRadius(4)
              .border({
                width: (this.settings.background.type === BackgroundType.IMAGE &&
                       this.settings.background.imagePath === savedImg.path) ? 2 : 0,
                color: $r('app.color.accent')
              })
              .margin({ right: 6, bottom: 6 })
              .onClick(() => {
                this.settings.background = {
                  type: BackgroundType.IMAGE,
                  imagePath: savedImg.path,
                  imageOpacity: this.settings.background.imageOpacity || 1.0
                };
                this.notifyChange();
              })
          })
        }
        .width('100%')
      }

      // 图片不透明度（紧凑）
      if (this.settings.background.type === BackgroundType.IMAGE) {
        Row() {
          Text('透明度')
            .fontSize(11)
            .fontFamily(this.appFontFamily)
            .fontColor($r('app.color.text_primary'))
            .width(40)

          Slider({
            value: (this.settings.background.imageOpacity || 1) * 100,
            min: 10,
            max: 100,
            step: 5
          })
            .layoutWeight(1)
            .trackColor($r('app.color.divider'))
            .selectedColor($r('app.color.accent'))
            .onChange((value: number) => {
              this.settings.background.imageOpacity = value / 100;
              this.notifyChange();
            })

          Text(`${Math.round((this.settings.background.imageOpacity || 1) * 100)}%`)
            .fontSize(10)
            .fontFamily(this.appFontFamily)
            .fontColor($r('app.color.accent'))
            .width(30)
        }
        .width('100%')
        .margin({ top: 8 })
      }
    }
    .width('100%')

    // 文字颜色（紧凑）
    if (this.settings.background.type === BackgroundType.IMAGE) {
      Column() {
        Text('文字颜色')
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ bottom: 6 })

        Row({ space: 6 }) {
          ForEach(['#333333', '#FFFFFF', '#5D4037', '#2E7D32', '#1565C0', '#D4D4D4'], (color: string) => {
            Column()
              .width(24)
              .height(24)
              .backgroundColor(color)
              .borderRadius(12)
              .border({
                width: this.settings.textStyle.textColor === color ? 2 : 1,
                color: this.settings.textStyle.textColor === color ?
                  $r('app.color.accent') : $r('app.color.divider')
              })
              .onClick(() => {
                this.settings.textStyle.textColor = color;
                this.notifyChange();
              })
          })
        }
        .width('100%')
      }
      .width('100%')
    }
  }

  build() {
    if (this.isVisible) {
      Stack() {
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.background_overlay'))
          .opacity(this.backdropOpacity)
          .hitTestBehavior(HitTestMode.Block)
          .onClick(() => {
            this.hidePanel();
          })

        if (this.isLandscape) {
          this.buildLandscapePanel()
        } else {
          this.buildPortraitPanel()
        }
      }
      .width('100%')
      .height('100%')
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const newWidth = Number(newValue.width);
        const newHeight = Number(newValue.height);
        if (newWidth > 0 && newHeight > 0) {
          this.isLandscape = newWidth > newHeight;
        }
      })
      .position({ x: 0, y: 0 })
    }
  }
}
