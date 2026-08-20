/**
 * 系统资源演示页面 - 支持主题切换
 * 展示系统资源的使用方法和效果
 */
import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, curves } from '@kit.ArkUI';
import { colorMap } from 'manxia_core/src/main/ets/Data/ResourceMap';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { AnimatedComponent, AnimationType } from '../Framework/Animation/AnimatedComponent';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { ThemeToggle } from 'manxia_theme/src/main/ets/Framework/Components/ThemeToggle';
import { ThemeAwareState, ThemeAwareHelper } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';

// 添加必要的类型导入
interface NavDestinationContext {
  pathStack: NavPathStack;
}

interface GeneratedTypeLiteralInterface_1 {
  name: string;
  resource: Resource;
  category: string;
}

interface GeneratedTypeLiteralInterface_2 {
  name: string;
  size: string;
  type: string;
  path: string;
}

interface GeneratedTypeLiteralInterface_3 {
  name: string;
  resource: Resource;
  category: string;
}

interface GeneratedTypeLiteralInterface_4 {
  name: string;
  size: string;
  type: string;
  path: string;
}

interface GeneratedTypeLiteralInterface_5 {
  name: string;
  icon: string;
}

interface GeneratedTypeLiteralInterface_6 {
  name: string;
  resource: Resource;
  category: string;
}

interface GeneratedTypeLiteralInterface_7 {
  name: string;
  size: string;
  type: string;
  path: string;
}

// 定义标题栏最小高度，用于内容占位
const TITLE_BAR_HEIGHT_MINI: number = 56;


@Component
struct SystemResourceDemoPage {
  // [修复] 不再使用@Consume，创建一个本地状态变量
  @State pathStack: NavPathStack = new NavPathStack();
  private scroller: Scroller = new Scroller();

  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'SystemResourceDemoPage';

  @State titleAnimationDelay: number = 0;
  @State componentAnimationDelay: number = 200;
  @State buttonAnimationDelay: number = 400;
  
  // 资源展示状态
  @State selectedTabIndex: number = 0;
  @State searchText: string = '';
  @State colorResources: Array<GeneratedTypeLiteralInterface_1> = [];
  @State fileResources: Array<GeneratedTypeLiteralInterface_2> = [];
  @State filteredColorResources: Array<GeneratedTypeLiteralInterface_3> = [];
  @State filteredFileResources: Array<GeneratedTypeLiteralInterface_4> = [];
  
  // 标签页列表
  private tabs: Array<GeneratedTypeLiteralInterface_5> = [
    { name: '颜色资源', icon: '🎨' },
    { name: '媒体资源', icon: '🖼️' },
    { name: '配置文件', icon: '⚙️' },
    { name: '原始文件', icon: '📁' }
  ];

  /**
   * 修复SystemResourceDemoPage.ets中的getContext过时用法
   */
  onPageShow() {
    // [修复] 使用 onPageShow 替代 aboutToAppear
    try {
      const stack = AppStorage.get<NavPathStack>('GlobalNavStack');
      if (stack) {
        this.pathStack = stack;
      } else {
        logger.error('SystemResourceDemoPage', '无法从 AppStorage 获取 GlobalNavStack!');
      }
    } catch (err) {
      logger.error('SystemResourceDemoPage', 'AppStorage.get 异常', err);
    }
    this.initializeResources();
  }

  onReady() {
    // 初始化主题感知
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (newTheme: ThemeType) => {
      logger.info('SystemResourceDemoPage', `主题已切换到: ${newTheme}`);
    });
  }

  aboutToDisappear() {
    // 清理主题感知
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  /**
   * 初始化资源数据
   */
  private async initializeResources() {
    // 初始化颜色资源
    this.initializeColorResources();
    
    // 初始化文件资源 - 移除错误的await
    this.initializeFileResources();
    
    // 初始化过滤结果
    this.updateFilteredResources();
  }

  /**
   * 初始化颜色资源
   */
  private initializeColorResources() {
    const colors: Array<GeneratedTypeLiteralInterface_6> = [];
    
    // 从colorMap中提取所有颜色资源
    Object.keys(colorMap).forEach(key => {
      const name = key.replace('app.color.', '');
      const resource = colorMap[key];
      let category = '其他';
      
      // 根据颜色名称分类
      if (name.startsWith('game_')) {
        if (name.includes('resource')) category = '游戏资源';
        else if (name.includes('skill')) category = '游戏技能';
        else if (name.includes('building')) category = '游戏建筑';
        else if (name.includes('weather')) category = '游戏天气';
        else if (name.includes('season')) category = '游戏季节';
        else if (name.includes('health')) category = '游戏健康';
        else if (name.includes('mood')) category = '游戏情绪';
        else if (name.includes('faction')) category = '游戏派系';
        else if (name.includes('priority')) category = '游戏优先级';
        else if (name.includes('weapon')) category = '游戏武器';
        else if (name.includes('apparel')) category = '游戏装备';
        else if (name.includes('temperature')) category = '游戏温度';
        else category = '游戏UI';
      } else if (name.startsWith('console_')) {
        if (name.includes('button')) category = '控制台按钮';
        else if (name.includes('text')) category = '控制台文本';
        else if (name.includes('background')) category = '控制台背景';
        else if (name.includes('border')) category = '控制台边框';
        else if (name.includes('log')) category = '控制台日志';
        else category = '控制台';
      } else if (name.startsWith('settings_')) {
        if (name.includes('text')) category = '设置文本';
        else if (name.includes('background')) category = '设置背景';
        else if (name.includes('button')) category = '设置按钮';
        else category = '设置页面';
      } else if (name.startsWith('system_resource_')) {
        if (name.includes('tab')) category = '系统资源标签';
        else if (name.includes('text')) category = '系统资源文本';
        else if (name.includes('background')) category = '系统资源背景';
        else if (name.includes('border')) category = '系统资源边框';
        else if (name.includes('button')) category = '系统资源按钮';
        else category = '系统资源';
      } else if (name.startsWith('test_management_')) {
        if (name.includes('text')) category = '测试管理文本';
        else if (name.includes('background')) category = '测试管理背景';
        else if (name.includes('button')) category = '测试管理按钮';
        else category = '测试管理';
      } else if (name.includes('color_')) {
        category = '状态颜色';
      } else if (name.startsWith('brand')) {
        category = '品牌颜色';
      } else if (name.includes('background')) {
        category = '背景颜色';
      } else if (name.includes('text')) {
        category = '文本颜色';
      } else {
        category = '基础颜色';
      }
      
      colors.push({
        name: name,
        resource: resource,
        category: category
      });
    });
    
    // 按分类和名称排序
    colors.sort((a, b) => {
      if (a.category !== b.category) {
        return a.category.localeCompare(b.category);
      }
      return a.name.localeCompare(b.name);
    });
    
    this.colorResources = colors;
    logger.info('SystemResourceDemoPage', `已加载 ${colors.length} 个颜色资源`);
  }

  /**
   * 初始化文件资源
   */
  private async initializeFileResources() {
    const files: Array<GeneratedTypeLiteralInterface_7> = [];
    
    // 媒体资源
    const mediaFiles = [
      'Chemfuel.png', 'Gold_c.png', 'Meat_Big_c.png', 'SculptureLargeAnimalistA.png',
      'background.png', 'foreground.png', 'logo.png', 'startIcon.png', 'unfinished.jpg'
    ];
    
    mediaFiles.forEach(file => {
      files.push({
        name: file,
        size: this.getFileSize(file),
        type: '媒体文件',
        path: `resources/base/media/${file}`
      });
    });
    
    // 配置文件
    const configFiles = [
      'color.json', 'float.json', 'string.json', 'backup_config.json', 'main_pages.json'
    ];
    
    configFiles.forEach(file => {
      files.push({
        name: file,
        size: this.getFileSize(file),
        type: '配置文件',
        path: `resources/base/${file.includes('backup') || file.includes('main') ? 'profile' : 'element'}/${file}`
      });
    });
    
    // 原始文件
    const rawFiles = [
      'default_config.json', 'config.json',
      'logo.svg', 'zh_CN.json', 'resources_metadata.json'
    ];
    
    rawFiles.forEach(file => {
      let subPath = '';
      if (file.includes('config')) subPath = 'config/';
      else if (file.includes('svg')) subPath = 'images/';
      else if (file.includes('zh_CN')) subPath = 'localization/';
      
      files.push({
        name: file,
        size: this.getFileSize(file),
        type: '原始文件',
        path: `resources/rawfile/${subPath}${file}`
      });
    });
    
    this.fileResources = files;
  }

  /**
   * 获取文件大小（模拟）
   */
  private getFileSize(fileName: string): string {
    // 模拟文件大小
    const sizeMap: Record<string, string> = {
      'Chemfuel.png': '15.2 KB',
      'Gold_c.png': '12.8 KB',
      'background.png': '245.6 KB',
      'logo.png': '8.4 KB',
      'color.json': '12.1 KB',
      'string.json': '5.3 KB',
      'config.json': '2.1 KB'
    };
    
    return sizeMap[fileName] || `${Math.floor(Math.random() * 50 + 1)}.${Math.floor(Math.random() * 9)} KB`;
  }

  /**
   * 更新过滤结果
   */
  private updateFilteredResources() {
    const searchLower = this.searchText.toLowerCase();
    
    this.filteredColorResources = this.colorResources.filter(color =>
      color.name.toLowerCase().includes(searchLower) ||
      color.category.toLowerCase().includes(searchLower)
    );
    
    this.filteredFileResources = this.fileResources.filter(file =>
      file.name.toLowerCase().includes(searchLower) ||
      file.type.toLowerCase().includes(searchLower)
    );
  }

  /**
   * 构建页面标题
   */
  @Builder
  buildTitle() {
    AnimatedComponent({
      animationType: AnimationType.FADE_IN,
      delay: this.titleAnimationDelay,
      content: () => {
        this.titleContent()
      }
    })
  }

  @Builder
  titleContent() {
    Row({ space: 12 }) {
      Text('🎨')
        .fontSize(28)
      
      Column({ space: 4 }) {
        Text('系统资源展示')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
        
        Text('查看系统颜色和文件资源')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
    .justifyContent(FlexAlign.Start)
  }

  /**
   * 构建搜索栏
   */
  @Builder
  buildSearchBar() {
    AnimatedComponent({
      animationType: AnimationType.SLIDE_IN_LEFT,
      delay: this.componentAnimationDelay,
      content: () => {
        this.searchBarContent()
      }
    })
  }

  @Builder
  searchBarContent() {
    Row({ space: 12 }) {
      Text('🔍')
        .fontSize(20)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .animation({
          duration: 300,
          curve: Curve.EaseInOut
        })
      
      TextInput({ placeholder: '搜索资源...', text: this.searchText })
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(8)
        .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
        .padding({ left: 12, right: 12, top: 10, bottom: 10 })
        .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_placeholder', this.themeState.currentTheme))
        .layoutWeight(1)
        .onChange((value: string) => {
          this.searchText = value;
          this.updateFilteredResources();
        })
        .animation({
          duration: 300,
          curve: Curve.EaseInOut
        })
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
  }

  /**
   * 构建标签页
   */
  @Builder
  buildTabs() {
    Row() {
      ForEach(this.tabs, (tab: GeneratedTypeLiteralInterface_5, index: number) => {
        Button() {
          Row({ space: 6 }) {
            Text(tab.icon)
              .fontSize(16)
            Text(tab.name)
              .fontSize(14)
              .fontWeight(this.selectedTabIndex === index ? FontWeight.Bold : FontWeight.Normal)
          }
        }
        .fontSize(14)
        .fontColor(this.selectedTabIndex === index ? 
          ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme) : 
          ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
        .backgroundColor(this.selectedTabIndex === index ? 
          ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme) : 
          Color.Transparent)
        .borderRadius(8)
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .onClick(() => {
          this.selectedTabIndex = index;
        })
        .layoutWeight(1)
        .animation({
          duration: 300,
          curve: Curve.EaseInOut
        })
      })
    }
    .width('100%')
    .padding({ left: 20, right: 20 })
    .justifyContent(FlexAlign.SpaceEvenly)
  }

  /**
   * 构建颜色资源展示
   */
  @Builder
  buildColorResources() {
    Column({ space: 12 }) {
      Text(`颜色资源 (${this.filteredColorResources.length})`)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)
        .animation({
          duration: 300,
          curve: Curve.EaseInOut
        })
      
      Grid() {
        ForEach(this.filteredColorResources, (color: GeneratedTypeLiteralInterface_3, index: number) => {
          GridItem() {
            Column({ space: 8 }) {
              // 颜色预览 - 使用实际的Resource对象
              Row()
                .width(60)
                .height(60)
                .backgroundColor(color.resource)
                .borderRadius(8)
                .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
              
              // 颜色信息
              Column({ space: 4 }) {
                Text(color.name)
                  .fontSize(12)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
                  .fontWeight(FontWeight.Medium)
                  .textAlign(TextAlign.Center)
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                
                Text(`app.color.${color.name}`)
                  .fontSize(10)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                  .textAlign(TextAlign.Center)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                
                Text(color.category)
                  .fontSize(10)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                  .textAlign(TextAlign.Center)
                  .padding({ top: 2 })
                  .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
                  .borderRadius(4)
                  .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              }
              .width('100%')
            }
            .width('100%')
            .padding(12)
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
            .borderRadius(8)
            .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
            .onClick(() => {
              // 点击时显示详细信息
              logger.info('SystemResourceDemoPage', `点击颜色: ${color.name}, 分类: ${color.category}`);
            })
            .animation({
              duration: 300,
              curve: Curve.EaseInOut
            })
          }
        })
      }
      .columnsTemplate('1fr 1fr 1fr')
      .rowsGap(12)
      .columnsGap(12)
      .width('100%')
    }
  }

  /**
   * 构建文件资源展示
   */
  @Builder
  buildFileResources() {
    Column({ space: 12 }) {
      Text(`文件资源 (${this.filteredFileResources.length})`)
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .alignSelf(ItemAlign.Start)
        .animation({
          duration: 300,
          curve: Curve.EaseInOut
        })
      
      Column({ space: 8 }) {
        ForEach(this.filteredFileResources, (file: GeneratedTypeLiteralInterface_4, index: number) => {
          Row({ space: 12 }) {
            // 文件类型图标
            Text(this.getFileIcon(file.type))
              .fontSize(24)
              .width(40)
              .textAlign(TextAlign.Center)
            
            // 文件信息
            Column({ space: 4 }) {
              Text(file.name)
                .fontSize(14)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
                .fontWeight(FontWeight.Medium)
              
              Text(file.path)
                .fontSize(12)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
            
            // 文件大小和类型
            Column({ space: 4 }) {
              Text(file.size)
                .fontSize(12)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
                .textAlign(TextAlign.End)
              
              Text(file.type)
                .fontSize(10)
                .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_muted', this.themeState.currentTheme))
                .textAlign(TextAlign.End)
            }
            .alignItems(HorizontalAlign.End)
          }
          .width('100%')
          .padding(12)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
          .borderRadius(8)
          .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('panel_border', this.themeState.currentTheme) })
          .animation({
            duration: 300,
            curve: Curve.EaseInOut
          })
        })
      }
      .width('100%')
    }
  }

  /**
   * 获取文件类型图标
   */
  private getFileIcon(type: string): string {
    switch (type) {
      case '媒体文件': return '🖼️';
      case '配置文件': return '⚙️';
      case '原始文件': return '📄';
      default: return '📁';
    }
  }

  /**
   * 构建内容区域
   */
  @Builder
  buildContent() {
    Column({ space: 16 }) {
      if (this.selectedTabIndex === 0) {
        this.buildColorResources()
      } else {
        this.buildFileResources()
      }
    }
    .width('100%')
    .padding(20)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_overlay', this.themeState.currentTheme))
    .borderRadius(12)
    .border({ width: 1, color: ThemeAwareHelper.getTestManagementThemedColor('border_subtle', this.themeState.currentTheme) })
  }

  /**
   * 构建操作按钮
   */
  @Builder
  buildActionButtons() {
    Row({ space: 16 }) {
      Button('返回')
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme))
        .borderRadius(8)
        .width(100)
        .height(40)
        .onClick(() => this.goBack())
        .animation({
          duration: 300,
          curve: Curve.EaseInOut
        })
      
      Button('系统动画')
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_green', this.themeState.currentTheme))
        .borderRadius(8)
        .width(120)
        .height(40)
        .onClick(() => this.navigateToSystemAnimation())
        .animation({
          duration: 300,
          curve: Curve.EaseInOut
        })
    }
    .width('100%')
    .justifyContent(FlexAlign.SpaceEvenly)
    .padding({ left: 20, right: 20 })
  }

  /**
   * 返回上一页
   */
  private goBack() {
    try {
      this.pathStack.pop();
    } catch (error) {
      logger.error('SystemResourceDemoPage', '返回失败，跳转到测试管理页面', error);
      this.pathStack.pushPath({ name: 'TestManagementPage' });
    }
  }

  /**
   * 导航到系统动画页面
   */
  private navigateToSystemAnimation() {
    try {
      this.pathStack.pushPath({ name: 'SystemAnimationDemoPage' });
    } catch (error) {
      logger.error('SystemResourceDemoPage', '导航到系统动画页面失败', error);
    }
  }

  build() {
    // 使用 HdsNavDestination 作为根组件
    HdsNavDestination() {
      // 使用 Stack 分离背景和内容
      Stack() {
        // 背景层
        Column()
          .width('100%')
          .height('100%')
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background_dark', this.themeState.currentTheme))
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          .animation({
            duration: 300,
            curve: Curve.EaseInOut
          })

        // 内容层
        Scroll(this.scroller) {
          Column({ space: 20 }) {
            // 添加 Blank 占位符
            Blank().height(TITLE_BAR_HEIGHT_MINI)

            this.buildSearchBar()
            this.buildTabs()

            if (this.selectedTabIndex === 0) {
              this.buildColorResources()
            } else {
              this.buildFileResources()
            }
          }
          .width('100%')
          .padding({ left: 20, right: 20, bottom: 40 })
        }
        .edgeEffect(EdgeEffect.Spring)
        .scrollBar(BarState.Auto)
      }
    }
    // 配置 titleBar，实现滚动模糊效果
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
          mainTitle: "🏛️ 系统资源展示",
        },
        menu: {
          value: [{
            content: {
              label: "主题",
              isEnabled: true,
              action: () => {
                this.themeManager.toggleTheme();
              }
            }
          }]
        }
      }
    })
    .onReady((context: NavDestinationContext) => {
      logger.info('SystemResourceDemoPage', 'HdsNavDestination.onReady 已触发');
      this.pathStack = context.pathStack;
      this.onPageShow();
    })
    // HdsNavDestination 自身背景设为透明
    .backgroundColor(Color.Transparent)
  }
}


export { SystemResourceDemoPage };
