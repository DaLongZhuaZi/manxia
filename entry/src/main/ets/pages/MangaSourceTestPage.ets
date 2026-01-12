/**
 * 漫画图源测试页面
 * 支持加载和测试JSON驱动的图源配置
 * 遵循沉浸式设计规范和Navigation + 属性动画架构
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { curves, UIContext, LengthMetrics } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
// 已弃用自定义 AnimatedButton，改用原生 ArkUI Button
import { MangaSourceEngine, SearchResult, EngineResult, EngineConfig } from '../Framework/WebView/MangaSourceEngine';
import { MangaSourceConfig, MangaInfo, ChapterInfo, AntiCrawlerConfig } from '../Framework/WebView/MangaSourceTypes';

const TAG = 'MangaSourceTestPage';

// 定义标题栏最小高度，用于内容占位
const TITLE_BAR_HEIGHT_MINI: number = 56;

interface AnimateOptions {
  duration: number;
  curve: curves.Curve;
}

// 定义测试结果接口
interface TestResult {
  testName: string;
  status: 'success' | 'error' | 'pending' | 'running';
  message: string;
  timestamp: number;
  duration?: number;
  data?: Object;
}

// 定义图源测试项接口
interface SourceTestItem {
  id: string;
  name: string;
  description: string;
  configFile: string;
  enabled: boolean;
}

@Component
struct MangaSourceTestPage {
  private scroller: Scroller = new Scroller();
  @State pathStack: NavPathStack = new NavPathStack();
  private uiContext: UIContext | undefined = undefined;
  private webviewController: webview.WebviewController = new webview.WebviewController();

  // 主题相关状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = 'MangaSourceTestPage';

  // 测试相关状态

  // 测试相关状态
  @State private testResults: TestResult[] = [];
  @State private isTestRunning: boolean = false;
  @State private currentTestName: string = '';
  @State private selectedSourceIndex: number = 0;
  @State private searchKeyword: string = '进击的巨人';
  @State private testProgress: number = 0;

  // 动画状态
  @State private titleOpacity: number = 0;
  @State private contentTranslateY: number = 50;
  @State private buttonScale: number = 0.8;

  // 图源引擎
  private mangaSourceEngine: MangaSourceEngine | undefined = undefined;

  // 测试图源列表
  private sourceTestItems: SourceTestItem[] = [
    {
      id: 'simple_source',
      name: '简单图源',
      description: '基础功能测试图源，适合快速验证',
      configFile: 'simple_manga_source.json',
      enabled: true
    },
    {
      id: 'example_source',
      name: '示例图源',
      description: '完整功能演示图源，包含所有特性',
      configFile: 'example_manga_source.json',
      enabled: true
    },
    {
      id: 'advanced_source',
      name: '高级图源',
      description: '高级功能测试图源，包含反爬虫机制',
      configFile: 'advanced_manga_source.json',
      enabled: true
    }
  ];

  aboutToAppear(): void {
    logger.lifecycle(TAG, 'aboutToAppear');
    
    // 获取UI上下文
    this.uiContext = this.getUIContext();
    if (!this.uiContext) {
      logger.error(TAG, '获取UIContext失败');
      return;
    }

    // 初始化主题感知功能
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题已切换到: ${theme}`);
    });

    // 初始化漫画图源引擎
    this.initializeMangaSourceEngine();

    // 启动入场动画
    this.startEntranceAnimation();
  }

  private lifecycle = new PageLifecycleManager('MangaSourceTestPage', { enableDebug: true });

  aboutToDisappear(): void {
    logger.lifecycle(TAG, 'aboutToDisappear');
    this.lifecycle.destroy();
    
    // 清理主题感知功能
    ThemeAwareHelper.cleanupThemeAware(this.componentId);

    // 清理图源引擎
    this.cleanupMangaSourceEngine();
  }

  /**
   * 初始化漫画图源引擎
   */
  private async initializeMangaSourceEngine(): Promise<void> {
    try {
      logger.info(TAG, '开始初始化漫画图源引擎');
      
      // 创建默认的反爬虫配置
      const antiCrawlerConfig: AntiCrawlerConfig = {
        cloudflare: {
          enabled: true,
          timeout: 30000,
          maxRetries: 3
        },
        captcha: {
          enabled: false,
          timeout: 60000,
          autoSolve: false
        },
        ipBlock: {
          enabled: true,
          retryDelay: 5000,
          maxRetries: 3
        },
        userAgentRotation: {
          enabled: true,
          agents: [
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/91.0.4472.124 Safari/537.36'
          ]
        }
      };
      
      const engineConfig: EngineConfig = {
        webViewController: this.webviewController,
        antiCrawlerConfig: antiCrawlerConfig,
        debug: true,
        timeout: 30000,
        caseSensitive: false,
        sourceId: 0
      };
      
      this.mangaSourceEngine = new MangaSourceEngine(engineConfig);
      
      logger.info(TAG, '漫画图源引擎初始化完成');
    } catch (error) {
      logger.error(TAG, `漫画图源引擎初始化失败: ${error}`);
      this.addTestResult('引擎初始化', 'error', `初始化失败: ${error}`);
    }
  }

  /**
   * 清理漫画图源引擎
   */
  private async cleanupMangaSourceEngine(): Promise<void> {
    try {
      if (this.mangaSourceEngine) {
        // 这里可以添加清理逻辑
        this.mangaSourceEngine = undefined;
      }
      logger.info(TAG, '漫画图源引擎清理完成');
    } catch (error) {
      logger.error(TAG, `漫画图源引擎清理失败: ${error}`);
    }
  }

  /**
   * 启动入场动画
   */
  private startEntranceAnimation(): void {
    if (!this.uiContext) return;

    setTimeout(() => {
      const animateOptions: AnimateOptions = {
        duration: 800,
        curve: Curve.EaseOut
      };
      
      this.uiContext!.animateTo(animateOptions, () => {
        this.titleOpacity = 1;
        this.contentTranslateY = 0;
        this.buttonScale = 1;
      });
    }, 100);
  }

  /**
   * 运行完整测试流程
   */
  private async runFullTest(): Promise<void> {
    if (this.isTestRunning || !this.mangaSourceEngine) {
      return;
    }

    this.isTestRunning = true;
    this.testResults = [];
    this.testProgress = 0;

    try {
      const selectedSource = this.sourceTestItems[this.selectedSourceIndex];
      logger.info(TAG, `开始测试图源: ${selectedSource.name}`);

      // 步骤1: 加载配置
      await this.testLoadConfiguration(selectedSource);
      this.testProgress = 20;

      // 步骤2: 初始化测试
      await this.testInitialization();
      this.testProgress = 40;

      // 步骤3: 搜索测试
      const searchResults = await this.testSearch();
      this.testProgress = 60;

      // 步骤4: 详情测试
      if (searchResults && searchResults.length > 0) {
        await this.testMangaDetail(searchResults[0]);
        this.testProgress = 80;

        // 步骤5: 章节列表测试
        if (searchResults[0].id) {
          await this.testChapterList(searchResults[0].id);
          this.testProgress = 100;
        } else {
          throw new Error('搜索结果缺少ID字段');
        }
      }

      this.addTestResult('完整测试流程', 'success', '所有测试步骤完成');

    } catch (error) {
      logger.error(TAG, `测试失败: ${error}`);
      this.addTestResult('完整测试流程', 'error', `测试失败: ${error}`);
    } finally {
      this.isTestRunning = false;
      this.currentTestName = '';
      this.testProgress = 0;
    }
  }

  /**
   * 测试配置加载
   */
  private async testLoadConfiguration(source: SourceTestItem): Promise<void> {
    this.currentTestName = '加载配置文件';
    
    try {
      const startTime = Date.now();
      
      await this.mangaSourceEngine!.loadConfig(`manga_sources/${source.configFile}`);
      
      const duration = Date.now() - startTime;
      this.addTestResult('配置加载', 'success', `配置文件加载成功: ${source.configFile}`, duration);
      
    } catch (error) {
      this.addTestResult('配置加载', 'error', `配置加载失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 测试初始化
   */
  private async testInitialization(): Promise<void> {
    this.currentTestName = '初始化图源';
    
    try {
      const startTime = Date.now();
      
      const result = await this.mangaSourceEngine!.searchManga('初始化测试');
      
      const duration = Date.now() - startTime;
      this.addTestResult('图源初始化', 'success', '图源初始化成功', duration, result);
      
    } catch (error) {
      this.addTestResult('图源初始化', 'error', `初始化失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 测试搜索功能
   */
  private async testSearch(): Promise<MangaInfo[] | undefined> {
    this.currentTestName = '搜索漫画';
    
    try {
      const startTime = Date.now();
      
      const results = await this.mangaSourceEngine!.searchManga(this.searchKeyword);
      
      const duration = Date.now() - startTime;
      
      if (results.success && results.data) {
        this.addTestResult('搜索功能', 'success', `搜索成功，找到${results.data.mangas.length}个结果`, duration, results.data);
        return results.data.mangas;
      } else {
        throw new Error(results.error || '搜索失败');
      }
      
    } catch (error) {
      this.addTestResult('搜索功能', 'error', `搜索失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 测试漫画详情
   */
  private async testMangaDetail(searchResult: MangaInfo): Promise<void> {
    this.currentTestName = '获取漫画详情';
    
    try {
      const startTime = Date.now();
      
      if (!searchResult.id) {
        throw new Error('搜索结果缺少ID字段');
      }
      
      const mangaInfo = await this.mangaSourceEngine!.getMangaDetail(searchResult.id);
      
      const duration = Date.now() - startTime;
      
      if (mangaInfo.success && mangaInfo.data) {
        this.addTestResult('漫画详情', 'success', `详情获取成功: ${mangaInfo.data.title}`, duration, mangaInfo.data);
      } else {
        const errorMessage = mangaInfo.error || '详情获取失败';
        throw new Error(errorMessage);
      }
      
    } catch (error) {
      this.addTestResult('漫画详情', 'error', `详情获取失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 测试章节列表
   */
  private async testChapterList(mangaId: string): Promise<void> {
    this.currentTestName = '获取章节列表';
    
    try {
      const startTime = Date.now();
      
      const chapters = await this.mangaSourceEngine!.getChapterList(mangaId);
      
      const duration = Date.now() - startTime;
      
      if (chapters.success && chapters.data) {
        this.addTestResult('章节列表', 'success', `章节列表获取成功，共${chapters.data.length}章`, duration, chapters.data);
      } else {
        throw new Error(chapters.error || '章节列表获取失败');
      }
      
    } catch (error) {
      this.addTestResult('章节列表', 'error', `章节列表获取失败: ${error}`);
      throw error as Error;
    }
  }

  /**
   * 添加测试结果
   */
  private addTestResult(testName: string, status: 'success' | 'error' | 'pending' | 'running', message: string, duration?: number, data?: Object): void {
    const result: TestResult = {
      testName,
      status,
      message,
      timestamp: Date.now(),
      duration,
      data
    };

    this.testResults.push(result);
    logger.info(TAG, `测试结果: ${testName} - ${status} - ${message}`);
  }

  /**
   * 清除测试结果
   */
  private clearTestResults(): void {
    this.testResults = [];
    this.testProgress = 0;
    logger.info(TAG, '测试结果已清除');
  }

  /**
   * 构建页面标题
   */
  @Builder
  buildPageTitle() {
    Column() {
      Text('漫画图源测试')
        .fontSize(28)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .opacity(this.titleOpacity)
        .margin({ bottom: 8 })

      Text('测试JSON驱动的漫画图源配置和功能')
        .fontSize(16)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .opacity(this.titleOpacity)
        .textAlign(TextAlign.Center)
        .margin({ bottom: 24 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
  }

  /**
   * 构建测试配置面板
   */
  @Builder
  buildConfigPanel() {
    Column({ space: 16 }) {
      Text('测试配置')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

      // 图源选择
      Column({ space: 8 }) {
        Text('选择图源')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .alignSelf(ItemAlign.Start)

        Column() {
          ForEach(this.sourceTestItems, (item: SourceTestItem, index: number) => {
            Row({ space: 12 }) {
              Radio({ value: item.id, group: 'sourceGroup' })
                .checked(index === this.selectedSourceIndex)
                .onChange((isChecked: boolean) => {
                  if (isChecked) {
                    this.selectedSourceIndex = index;
                  }
                })

              Column({ space: 4 }) {
                Text(item.name)
                  .fontSize(16)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
                  .alignSelf(ItemAlign.Start)

                Text(item.description)
                  .fontSize(12)
                  .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_dim', this.themeState.currentTheme))
                  .alignSelf(ItemAlign.Start)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
            }
            .width('100%')
            .padding(12)
            .backgroundColor(index === this.selectedSourceIndex ? 
              ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme) : 
              'transparent')
            .borderRadius(8)
            .onClick(() => {
              this.selectedSourceIndex = index;
            })
          })
        }
        .width('100%')
      }

      // 搜索关键词
      Column({ space: 8 }) {
        Text('搜索关键词')
          .fontSize(14)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          .alignSelf(ItemAlign.Start)

        TextInput({ placeholder: '请输入搜索关键词', text: this.searchKeyword })
          .width('100%')
          .height(40)
          .fontSize(16)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
          .placeholderColor(ThemeAwareHelper.getTestManagementThemedColor('text_dim', this.themeState.currentTheme))
          .onChange((value: string) => {
            this.searchKeyword = value;
          })
      }

      // 测试按钮
      Row({ space: 12 }) {
        Button({ stateEffect: true }) {
          Text(this.isTestRunning ? '测试中...' : '开始测试')
            .fontSize(16)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_primary', this.themeState.currentTheme))
        }
          .height(44)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_primary', this.themeState.currentTheme))
          .borderRadius(8)
          .enabled(!this.isTestRunning)
          .onClick(() => this.runFullTest())
          .layoutWeight(1)

        Button({ stateEffect: true }) {
          Text('清除结果')
            .fontSize(16)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('button_text_secondary', this.themeState.currentTheme))
        }
          .height(44)
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('button_secondary', this.themeState.currentTheme))
          .borderRadius(8)
          .enabled(!this.isTestRunning)
          .onClick(() => this.clearTestResults())
          .layoutWeight(1)
      }
      .width('100%')

      // 测试进度
      if (this.isTestRunning) {
        Column({ space: 8 }) {
          Row({ space: 8 }) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))

            Text(`正在执行: ${this.currentTestName}`)
              .fontSize(14)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          }

          Progress({ value: this.testProgress, total: 100, type: ProgressType.Linear })
            .width('100%')
            .height(4)
            .color(ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme))
            .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
        }
        .width('100%')
      }
    }
    .width('100%')
    .padding(16)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.themeState.currentTheme))
    .borderRadius(12)
    .transform({ translateY: this.contentTranslateY })
    .scale({ x: this.buttonScale, y: this.buttonScale })
  }

  /**
   * 构建测试结果列表
   */
  @Builder
  buildTestResults() {
    Column({ space: 16 }) {
      Text('测试结果')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))

      if (this.testResults.length === 0) {
        Column({ space: 16 }) {
          Text('📋')
            .fontSize(48)
          Text('暂无测试结果')
            .fontSize(16)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
          Text('选择图源并点击"开始测试"按钮运行测试')
            .fontSize(14)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_dim', this.themeState.currentTheme))
            .textAlign(TextAlign.Center)
        }
        .width('100%')
        .padding(40)
        .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.themeState.currentTheme))
        .borderRadius(12)
      } else {
        Column({ space: 8 }) {
          ForEach(this.testResults, (result: TestResult, index: number) => {
            this.buildTestResultItem(result, index)
          })
        }
        .width('100%')
      }
    }
    .width('100%')
  }

  /**
   * 构建单个测试结果项
   */
  @Builder
  buildTestResultItem(result: TestResult, index: number) {
    Column({ space: 8 }) {
      Row({ space: 12 }) {
        // 状态图标
        Text(this.getStatusIcon(result.status))
          .fontSize(16)

        // 测试名称和状态
        Column({ space: 4 }) {
          Text(result.testName)
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
            .alignSelf(ItemAlign.Start)

          Text(result.message)
            .fontSize(14)
            .fontColor(this.getStatusColor(result.status))
            .alignSelf(ItemAlign.Start)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        // 执行时间
        if (result.duration !== undefined) {
          Text(`${result.duration}ms`)
            .fontSize(12)
            .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_dim', this.themeState.currentTheme))
        }
      }
      .width('100%')

      // 详细数据（可展开）
      if (result.data && result.status === 'success') {
        Text(`数据: ${JSON.stringify(result.data).substring(0, 100)}...`)
          .fontSize(12)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_dim', this.themeState.currentTheme))
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('100%')
    .padding(12)
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_primary', this.themeState.currentTheme))
    .borderRadius(8)
    .border({
      width: 1,
      color: result.status === 'success' ? 
        ThemeAwareHelper.getTestManagementThemedColor('success_border', this.themeState.currentTheme) :
        result.status === 'error' ?
        ThemeAwareHelper.getTestManagementThemedColor('error_border', this.themeState.currentTheme) :
        ThemeAwareHelper.getTestManagementThemedColor('comp_border_primary', this.themeState.currentTheme)
    })
  }

  /**
   * 获取状态图标
   */
  private getStatusIcon(status: string): string {
    switch (status) {
      case 'success': return '✅';
      case 'error': return '❌';
      case 'running': return '⏳';
      case 'pending': return '⏸️';
      default: return '❓';
    }
  }

  /**
   * 获取状态颜色
   */
  private getStatusColor(status: string): ResourceStr {
    switch (status) {
      case 'success': 
        return ThemeAwareHelper.getTestManagementThemedColor('success_text', this.themeState.currentTheme);
      case 'error': 
        return ThemeAwareHelper.getTestManagementThemedColor('error_text', this.themeState.currentTheme);
      case 'running': 
        return ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme);
      default: 
        return ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme);
    }
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
            
            this.buildPageTitle()
            this.buildConfigPanel()
            this.buildTestResults()
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
        originalStyle: {
          backgroundStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('panel_background', this.themeState.currentTheme) },
          contentStyle: {
            titleStyle: { mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme) },
            backIconStyle: { backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('comp_background_tertiary', this.themeState.currentTheme), iconColor: ThemeAwareHelper.getTestManagementThemedColor('icon_primary', this.themeState.currentTheme) }
          }
        }
      },
      content: {
        title: {
          mainTitle: "漫画图源测试",
        },
        menu: {
          value: [{
            content: {
              label: '清除结果',
              icon: $r('app.media.ic_public_refresh'),
              isEnabled: !this.isTestRunning,
              action: () => {
                this.clearTestResults();
              }
            }
          }]
        },
      }
    })
    .onReady((context: NavDestinationContext) => {
      logger.info(TAG, 'HdsNavDestination.onReady 已触发');
      this.pathStack = context.pathStack;
    })
    .backgroundColor(Color.Transparent)
  }
}

export { MangaSourceTestPage };
