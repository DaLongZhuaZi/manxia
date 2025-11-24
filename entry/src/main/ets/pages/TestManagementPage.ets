/**
 * 测试管理页面
 * 提供各种测试功能的入口，包括沉浸式测试、动画演示等
 * 支持浅色和暗色主题切换
 */
import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics } from '@kit.ArkUI';

import { AnimatedComponent } from '../Framework/Animation/AnimatedComponent';
import { AnimationType } from '../Framework/Animation/GlobalAnimationSystem';
import { logger } from '../Utils/Logger';
import { TestItem, TestCategory } from '../Data/TestData';
import { testData } from '../Data/TestData';
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { uiContextManager } from '../Framework/Managers/UIContextManager';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { ThemeToggle } from '../Framework/Components/ThemeToggle';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';

// 定义标题栏最小高度，用于内容占位
const TITLE_BAR_HEIGHT_MINI: number = 56;

@Component
struct TestManagementPage {
  private scroller: Scroller = new Scroller();
  @State pathStack: NavPathStack = new NavPathStack();
  @State titleAnimationDelay: number = 0;
  @State componentAnimationDelay: number = 200;
  @State buttonAnimationDelay: number = 400;
  @State selectedCategory: number = 0;
  @State searchText: string = '';
  @State filteredItems: TestItem[] = [];
  
  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'TestManagementPage';

  private categories: string[] = ['全部', '应用设置', '系统测试', '功能测试', '演示页面'];
  private testItems: TestItem[] = [
    { id: 'theme_settings', title: '主题设置', description: '自定义主题：选择图片、裁剪、模糊效果、主色调提取、深色模式适配', icon: '🎨', routeName: 'ThemeSettingsPage', isAvailable: true, category: '应用设置' },
    { id: 'dummy_page', title: '组件展示页面', description: '展示各种系统组件和动画效果的标准页面', icon: '🎨', routeName: 'DummyPage', isAvailable: true, category: '演示页面' },
    { id: 'system_animation_demo', title: '系统动画演示', description: '展示所有系统动画效果和动画控制功能', icon: '🎬', routeName: 'SystemAnimationDemoPage', isAvailable: true, category: '演示页面' },
    { id: 'system_resource_demo', title: '系统资源展示', description: '展示系统颜色资源和文件资源的博物馆式页面', icon: '🏛️', routeName: 'SystemResourceDemoPage', isAvailable: true, category: '演示页面' },
    { id: 'hello_world', title: 'Hello World', description: '基础的Hello World测试页面', icon: '👋', routeName: 'HelloWorldPage', isAvailable: true, category: '系统测试' },
    { id: 'system_status', title: '系统状态', description: '显示系统运行状态和性能信息', icon: '📊', routeName: 'SystemStatusPage', isAvailable: true, category: '系统测试' },
    { id: 'webview_configurable_system_test', title: 'WebView可配置系统测试', description: '测试JSON配置系统、扩展模块、统一操作接口等功能', icon: '⚙️', routeName: 'WebViewConfigurableSystemTestPage', isAvailable: true, category: '系统测试' },
    // 数据管理测试入口已移除
    // { id: 'webview_image_test', title: 'WebView图片测试', description: '验证WebView图片加载功能、缓存机制和性能表现', icon: '🌐', routeName: 'WebViewImageTestPage', isAvailable: true, category: '功能测试' }, // 已移除，不符合JSON驱动系统
    { id: 'manga_source_test', title: '漫画图源测试', description: '测试JSON驱动的漫画图源配置和功能验证', icon: '📚', routeName: 'MangaSourceTestPage', isAvailable: true, category: '功能测试' }
  ];

  aboutToAppear(): void {
    // 初始化主题感知功能
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info('TestManagementPage', `主题已切换到: ${theme}`);
    });
  }

  aboutToDisappear(): void {
    // 清理主题感知功能
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  onPageShow() {
    this.filterItems();
  }

  private filterItems() {
    let items = this.testItems;
    if (this.selectedCategory > 0) {
      const category = this.categories[this.selectedCategory];
      items = items.filter(item => item.category === category);
    }
    if (this.searchText.trim()) {
      const searchLower = this.searchText.toLowerCase();
      items = items.filter(item =>
      item.title.toLowerCase().includes(searchLower) ||
      item.description.toLowerCase().includes(searchLower)
      );
    }
    this.filteredItems = items;
  }

  private navigateToTest(item: TestItem) {
    if (!item.isAvailable) {
      logger.warn('TestManagementPage', `测试项目 ${item.title} 暂不可用`);
      return;
    }
    logger.info('TestManagementPage', `导航到测试页面: ${item.title}`);
    this.pathStack.pushPath({
      name: item.routeName
    });
  }

  @Builder
  buildSearchBar() {
    TextInput({ placeholder: '搜索测试项目...', text: this.searchText })
      .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      .placeholderFont({ size: 14 })
      .caretColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
      .fontSize(14)
      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
      .borderRadius(8)
      .border({ 
        width: 1, 
        color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) 
      })
      .padding({ left: 16, right: 16, top: 12, bottom: 12 })
      .onChange((value: string) => {
        this.searchText = value;
        this.filterItems();
      })
      .width('100%')
      .margin({ left: 20, right: 20 })
      .animation(ThemeAwareHelper.getThemeTransitionAnimation())
  }

  @Builder
  buildCategoryTabs() {
    Row() {
      ForEach(this.categories, (category: string, index: number) => {
        Button(category)
          .fontSize(12)
          .fontColor(this.selectedCategory === index 
            ? ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .backgroundColor(this.selectedCategory === index 
            ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
            : ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
          .borderRadius(16)
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .onClick(() => {
            this.selectedCategory = index;
            this.filterItems();
          })
          .margin({ right: 8 })
          .animation(ThemeAwareHelper.getThemeTransitionAnimation())
      })
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
  }

  @Builder
  buildTestCard(item: TestItem, index: number) {
    Column() {
      Row() {
        Text(item.icon)
          .fontSize(32)
          .margin({ right: 16 })

        Column() {
          Text(item.title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 4 })

        Text(item.description)
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .alignSelf(ItemAlign.Start)
            .lineHeight(16)

          Text(item.category)
            .fontSize(10)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .borderRadius(4)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
            .alignSelf(ItemAlign.Start)
            .margin({ top: 8 })
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Text('▶')
          .fontSize(16)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
          .margin({ left: 8 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ 
      width: 1, 
      color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) 
    })
    .opacity(item.isAvailable ? 1.0 : 0.5)
    .onClick(() => {
      this.navigateToTest(item);
    })
    .animation(ThemeAwareHelper.getThemeTransitionAnimation())
  }

  @Builder
  buildTestList() {
    Column({ space: 12 }) {
      if (this.filteredItems.length === 0) {
        Column() {
          Text('🔍')
            .fontSize(48)
            .margin({ bottom: 16 })
          Text('未找到匹配的测试项目')
            .fontSize(16)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
            .textAlign(TextAlign.Center)
          Text('请尝试调整搜索条件或分类筛选')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_dim', this.themeState.currentTheme))
            .textAlign(TextAlign.Center)
            .margin({ top: 8 })
        }
        .width('100%')
        .padding(40)
      } else {
        ForEach(this.filteredItems, (item: TestItem, index: number) => {
          this.buildTestCard(item, index);
        }, (item: TestItem) => item.id)
      }
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
  }

  @Builder
  buildStatistics() {
    Row() {
      Column() {
        Text(`${this.testItems.length}`)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        Text('总测试项')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      }
      .layoutWeight(1)

      Column() {
        Text(`${this.testItems.filter(item => item.isAvailable).length}`)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_secondary', this.themeState.currentTheme))
        Text('可用项目')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      }
      .layoutWeight(1)

      Column() {
        Text(`${this.filteredItems.length}`)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        Text('当前显示')
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      }
      .layoutWeight(1)
    }
    .width('100%')
    .padding(20)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ 
      width: 1, 
      color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) 
    })
    .margin({ left: 20, right: 20 })
    .animation(ThemeAwareHelper.getThemeTransitionAnimation())
  }

  @Builder
  buildActionButtons() {
    Row({ space: 16 }) {
      Button('返回主菜单')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
        .borderRadius(8)
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .onClick(() => this.goBack())
        .animation(ThemeAwareHelper.getThemeTransitionAnimation())

      Button('刷新列表')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
        .borderRadius(8)
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .onClick(() => this.refreshList())
        .animation(ThemeAwareHelper.getThemeTransitionAnimation())

      Button('清空搜索')
        .fontSize(14)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_background', this.themeState.currentTheme))
        .borderRadius(8)
        .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        .onClick(() => this.clearSearch())
        .animation(ThemeAwareHelper.getThemeTransitionAnimation())
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceEvenly)
    .padding({ left: 20, right: 20 })
  }

  private async goBack() {
    logger.info('TestManagementPage', '用户点击返回按钮');
    try {
      this.pathStack.pop();
    } catch (error) {
      logger.warn('TestManagementPage', '返回失败，尝试跳转到主菜单页面');
      try {
        this.pathStack.pushPath({ name: 'MainMenuPage' });
      } catch (fallbackError) {
        const errorMessage = fallbackError instanceof Error ? fallbackError.message : String(fallbackError);
        logger.error('TestManagementPage', '导航失败', errorMessage);
      }
    }
  }

  private refreshList() {
    this.filterItems();
    this.getUIContext().getPromptAction().showToast({ message: '列表已刷新' });
  }

  private clearSearch() {
    this.searchText = '';
    this.selectedCategory = 0;
    this.filterItems();
  }

  build() {
    HdsNavDestination() {
      Stack() {
        // 背景层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
          .animation(ThemeAwareHelper.getThemeTransitionAnimation())
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        
        // 内容层
        Scroll(this.scroller) {
          Column({ space: 24 }) {
            // [修复] 添加Blank占位符，防止内容与标题栏重叠
            Blank().height(TITLE_BAR_HEIGHT_MINI)
            
            // 主题切换按钮区域
            Row() {
              Blank().layoutWeight(1)
              ThemeToggle({
                themeManager: this.themeManager,
                showLabel: false,
                iconSize: 20
              })
            }
            .width('100%')
            .padding({ left: 20, right: 20 })
            
            this.buildSearchBar()
            this.buildCategoryTabs()
            this.buildStatistics()
            this.buildTestList()
            this.buildActionButtons()
          }
          .width('100%')
          .padding({ bottom: 20 })
        }
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Auto)
      }
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(2),
        end: LengthMetrics.vp(2)
      },
      style: {
        scrollEffectOpts: {
          enableScrollEffect: true,
          scrollEffectType: ScrollEffectType.COMMON_BLUR,
          blurEffectiveStartOffset: LengthMetrics.vp(0),
          blurEffectiveEndOffset: LengthMetrics.vp(20)
        },
        originalStyle: {
          backgroundStyle: {
            backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme),
          },
          contentStyle: {
            titleStyle: { 
              mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme), 
              subTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme) 
            },
            menuStyle: { 
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), 
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) 
            },
            backIconStyle: { 
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), 
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) 
            }
          }
        },
        scrollEffectStyle: {
          backgroundStyle: {
            backgroundColor: this.themeState.currentTheme === ThemeType.LIGHT ? 
              '#E6FFFFFF' : '#E6000000',
          },
          contentStyle: {
            titleStyle: { 
              mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme), 
              subTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme) 
            },
            menuStyle: { 
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), 
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) 
            },
            backIconStyle: { 
              backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), 
              iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) 
            }
          }
        }
      },
      content: {
        title: {
          mainTitle: "测试管理中心",
        },
        menu: {
          value: [{
            content: {
              label: '刷新',
              icon: $r('app.media.SculptureLargeAnimalistA'),
              isEnabled: true,
              action: () => {
                this.refreshList();
              }
            }
          }]
        },
      }
    })
    .onReady((context: NavDestinationContext) => {
      logger.info('TestManagementPage', 'HdsNavDestination.onReady 已触发');
      this.pathStack = context.pathStack;
      this.onPageShow();
    })
    .backgroundColor(Color.Transparent)
  }
}

export { TestManagementPage }