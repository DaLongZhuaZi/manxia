/**
 * 漫画阅读器章节列表组件
 * 用于在阅读器内快速切换章节
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ThemeManager } from '../Framework/Managers/ThemeManager';
import { MangaChapter } from '../Models/MangaModels';
import { curves, UIContext, display } from '@kit.ArkUI';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeType } from '../Framework/Managers/ThemeManager';

const TAG = 'MangaReaderChapterList';

/**
 * 章节列表参数接口
 */
export interface MangaReaderChapterListParams {
  /** 章节列表 */
  chapters: MangaChapter[];
  /** 当前章节ID */
  currentChapterId: string;
  /** 是否显示 */
  isVisible: boolean;
  /** 章节切换回调 */
  onChapterSelect?: (chapterId: string) => void;
  /** 关闭回调 */
  onClose?: () => void;
}

// 定义事件回调接口
interface MangaReaderChapterListCallbacks {
  onChapterSelect: (chapterId: string) => void;
  onClose: () => void;
}

@Component
export struct MangaReaderChapterList {
  @Prop chapters: MangaChapter[];
  @Prop currentChapterId: string;
  @Prop isVisible: boolean;
  @Prop pageCountSignal: number = 0;
  @Prop callbacks: MangaReaderChapterListCallbacks;

  // 内部状态
  @State private panelOpacity: number = 0;
  @State private panelScale: number = 0.95;
  @State private panelTranslateY: number = 20;
  @State private panelTranslateX: number = -300;
  @State private backdropOpacity: number = 0;
  @State private themeState: ThemeAwareState = new ThemeAwareState();
  @State private isLandscape: boolean = false;

  // 列表滚动控制器（用于自动滚动到当前章节）
  private listScroller: ListScroller = new ListScroller();

  // 动画系统
  private uiContext: UIContext | undefined = undefined;

  aboutToAppear() {
    // 获取UI上下文
    this.uiContext = this.getUIContext();
    if (!this.uiContext) {
      logger.error(TAG, '获取UIContext失败');
    }
    
    // 初始化屏幕方向检测
    this.detectScreenOrientation();
    
    // 初始化主题感知
    ThemeAwareHelper.initializeThemeAware('MangaReaderChapterList', this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `MangaReaderChapterList 主题切换: ${theme}`);
    });
    
    // 延迟执行动画，确保组件完全渲染后再播放
    if (this.isVisible) {
      setTimeout(() => {
        this.showPanel();
        // 自动滚动到当前章节
        this.scrollToCurrentChapter();
      }, 50);
    }
  }
  
  /**
   * 检测屏幕方向
   */
  private detectScreenOrientation(): void {
    try {
      const displayInfo = display.getDefaultDisplaySync();
      if (displayInfo) {
        const screenWidth = displayInfo.width / (displayInfo.densityPixels || 1);
        const screenHeight = displayInfo.height / (displayInfo.densityPixels || 1);
        this.isLandscape = screenWidth > screenHeight;
      }
    } catch (error) {
      logger.error(TAG, `屏幕方向检测失败: ${String(error)}`);
    }
  }
  
  /**
   * 自动滚动到当前章节
   */
  private scrollToCurrentChapter(): void {
    if (!this.currentChapterId || this.chapters.length === 0) {
      return;
    }
    
    const currentIndex = this.chapters.findIndex((ch: MangaChapter) => ch.id === this.currentChapterId);
    if (currentIndex > 0) {
      // 延迟滚动，确保列表已完成渲染
      setTimeout(() => {
        try {
          this.listScroller.scrollToIndex(Math.max(0, currentIndex - 1), true);
          logger.info(TAG, `自动滚动到当前章节: index=${currentIndex}, title=${this.chapters[currentIndex].title}`);
        } catch (error) {
          logger.warn(TAG, `自动滚动失败: ${String(error)}`);
        }
      }, 100);
    }
  }

  aboutToDisappear() {
    // 清理主题感知
    ThemeAwareHelper.cleanupThemeAware('MangaReaderChapterList');
  }

  onPageShow() {
    if (this.isVisible) {
      this.showPanel();
    }
  }

  /**
   * 显示章节列表面板
   */
  private showPanel(): void {
    if (!this.uiContext) {
      logger.error(TAG, 'UIContext未初始化，无法执行动画');
      return;
    }

    const fadeInOptions: AnimateParam = { 
      duration: 200, 
      curve: curves.initCurve(Curve.EaseOut),
      iterations: 1,
      playMode: PlayMode.Normal
    };
    this.uiContext.animateTo(fadeInOptions, () => {
      this.backdropOpacity = 0.5;
    });

    if (this.isLandscape) {
      // 横屏：从左侧滑入
      this.panelTranslateX = -300;
      const slideInOptions: AnimateParam = { 
        duration: 300, 
        curve: curves.initCurve(Curve.EaseOut),
        iterations: 1,
        playMode: PlayMode.Normal
      };
      this.uiContext.animateTo(slideInOptions, () => {
        this.panelOpacity = 1;
        this.panelTranslateX = 0;
      });
    } else {
      // 竖屏：缩放弹入
      const slideInOptions: AnimateParam = { 
        duration: 200, 
        curve: curves.initCurve(Curve.EaseOut),
        iterations: 1,
        playMode: PlayMode.Normal
      };
      this.uiContext.animateTo(slideInOptions, () => {
        this.panelOpacity = 1;
        this.panelScale = 1;
        this.panelTranslateY = 0;
      });
    }
  }

  /**
   * 隐藏章节列表面板
   */
  private hidePanel(): void {
    if (!this.uiContext) {
      logger.error(TAG, 'UIContext未初始化，无法执行动画');
      return;
    }

    if (this.isLandscape) {
      // 横屏：滑出到左侧
      const slideOutOptions: AnimateParam = { 
        duration: 250, 
        curve: curves.initCurve(Curve.EaseIn),
        iterations: 1,
        playMode: PlayMode.Normal
      };
      this.uiContext.animateTo(slideOutOptions, () => {
        this.panelOpacity = 0;
        this.panelTranslateX = -300;
      });
    } else {
      // 竖屏：缩放淡出
      const slideOutOptions: AnimateParam = { 
        duration: 160, 
        curve: curves.initCurve(Curve.EaseIn),
        iterations: 1,
        playMode: PlayMode.Normal
      };
      this.uiContext.animateTo(slideOutOptions, () => {
        this.panelOpacity = 0;
        this.panelScale = 0.95;
        this.panelTranslateY = 20;
      });
    }

    const fadeOutOptions: AnimateParam = { 
      duration: 200, 
      curve: curves.initCurve(Curve.EaseInOut),
      iterations: 1,
      playMode: PlayMode.Normal
    };
    this.uiContext.animateTo(fadeOutOptions, () => {
      this.backdropOpacity = 0;
    });
  }

  /**
   * 选择章节
   */
  private selectChapter(chapterId: string): void {
    logger.info(TAG, `选择章节: ${chapterId}`);
    if (this.callbacks.onChapterSelect) {
      this.callbacks.onChapterSelect(chapterId);
    }
    this.hidePanel();
    
    // 动画完成后调用关闭回调
    setTimeout(() => {
      if (this.callbacks.onClose) {
        this.callbacks.onClose();
      }
    }, 500);
  }

  private getChapterPageCountLabel(chapter: MangaChapter): string {
    const pageCount = chapter.totalPages && chapter.totalPages > 0
      ? chapter.totalPages
      : (chapter.pages && chapter.pages.length > 0 ? chapter.pages.length : 0);
    if (pageCount <= 0 && this.pageCountSignal >= 0) {
      return '暂未获取页面数量';
    }
    return `${pageCount}页`;
  }

  /**
   * 构建章节列表项
   */
  @Builder
  buildChapterItem(chapter: MangaChapter, index: number) {
    Row() {
      Column() {
        Text(chapter.title)
          .fontSize(16)
          .fontWeight(chapter.id === this.currentChapterId ? FontWeight.Bold : FontWeight.Normal)
          .fontColor(chapter.id === this.currentChapterId ? 
            $r('app.color.accent') : $r('app.color.text_primary'))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Row() {
          if (chapter.isDownloaded) {
            Image($r('app.media.ic_download_done'))
              .width(14)
              .height(14)
              .fillColor($r('app.color.accent_green'))
              .margin({ right: 8 })
          }
          
          // [懒加载优化] 优先使用totalPages；拿不到时明确标记未知，避免误显示0页。
          Text(this.getChapterPageCountLabel(chapter))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .margin({ top: 4 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      if (chapter.id === this.currentChapterId) {
        Image($r('app.media.ic_check'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.accent'))
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(chapter.id === this.currentChapterId ? 
      $r('app.color.accent_background') : Color.Transparent)
    .borderRadius(8)
    .onClick(() => {
      if (chapter.id !== this.currentChapterId) {
        this.selectChapter(chapter.id);
      }
    })
  }

  /**
   * 构建竖屏面板（居中弹窗样式）
   */
  @Builder
  buildPortraitPanel() {
    Column() {
      // 面板标题
      Row() {
        Text('章节目录')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)

        Text(`共${this.chapters.length}章`)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ right: 12 })

        Button() {
          Image($r('app.media.ic_close'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.text_secondary'))
        }
        .width(36)
        .height(36)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.hidePanel();
          if (this.callbacks.onClose) {
            this.callbacks.onClose();
          }
        })
      }
      .width('100%')
      .margin({ bottom: 16 })

      // 滚动章节列表
      List({ scroller: this.listScroller }) {
        ForEach(this.chapters, (chapter: MangaChapter, index: number) => {
          ListItem() {
            this.buildChapterItem(chapter, index)
          }
        }, (chapter: MangaChapter) => chapter.id)
      }
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .divider({
        strokeWidth: 1,
        color: $r('app.color.divider'),
        startMargin: 16,
        endMargin: 16
      })
    }
    .width('90%')
    .height('70%')
    .constraintSize({ maxWidth: 500, maxHeight: 600 })
    .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
    .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
    .borderRadius(16)
    .padding(20)
    .opacity(this.panelOpacity)
    .scale({ x: this.panelScale, y: this.panelScale })
    .translate({ y: this.panelTranslateY })
  }

  /**
   * 构建横屏面板（左侧贴边侧栏）
   */
  @Builder
  buildLandscapePanel() {
    Row() {
      // 左侧章节列表面板
      Column() {
        // 面板标题
        Row() {
          Text('章节目录')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)

          Text(`共${this.chapters.length}章`)
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .margin({ right: 8 })

          Button() {
            Image($r('app.media.ic_close'))
              .width(18)
              .height(18)
              .fillColor($r('app.color.text_secondary'))
          }
          .width(32)
          .height(32)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.hidePanel();
            if (this.callbacks.onClose) {
              this.callbacks.onClose();
            }
          })
        }
        .width('100%')
        .margin({ bottom: 12 })

        // 滚动章节列表
        List({ scroller: this.listScroller }) {
          ForEach(this.chapters, (chapter: MangaChapter, index: number) => {
            ListItem() {
              this.buildChapterItem(chapter, index)
            }
          }, (chapter: MangaChapter) => chapter.id)
        }
        .layoutWeight(1)
        .scrollBar(BarState.Auto)
        .divider({
          strokeWidth: 1,
          color: $r('app.color.divider'),
          startMargin: 16,
          endMargin: 16
        })
      }
      .width(300)
      .height('100%')
      .padding(16)
      .backgroundColor(ThemeManager.getInstance().getGlassBackgroundResource())
      .backgroundBlurStyle(ThemeManager.getInstance().getGlassBlurStyle())
      .borderRadius({ topRight: 16, bottomRight: 16 })
      .opacity(this.panelOpacity)
      .translate({ x: this.panelTranslateX })
      .hitTestBehavior(HitTestMode.Default)

      // 右侧空白区域（点击关闭）
      Column()
        .layoutWeight(1)
        .height('100%')
        .onClick(() => {
          this.hidePanel();
          if (this.callbacks.onClose) {
            this.callbacks.onClose();
          }
        })
    }
    .width('100%')
    .height('100%')
  }

  build() {
    if (this.isVisible) {
      Stack() {
        // 背景遮罩
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.background_overlay'))
          .opacity(this.backdropOpacity)
          .onClick(() => {
            this.hidePanel();
            if (this.callbacks.onClose) {
              this.callbacks.onClose();
            }
          })

        // 根据屏幕方向选择不同布局
        if (this.isLandscape) {
          this.buildLandscapePanel()
        } else {
          this.buildPortraitPanel()
        }
      }
      .width('100%')
      .height('100%')
      .position({ x: 0, y: 0 })
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        const newWidth = Number(newValue.width);
        const newHeight = Number(newValue.height);
        if (newWidth > 0 && newHeight > 0) {
          this.isLandscape = newWidth > newHeight;
        }
      })
    }
  }
}

