// 文件路径: entry/src/main/ets/pages/SourceGuidePage.ets
// 职责: 图源说明页面，详细说明WebView图源和JSON配置文件的开发规则
// 最后编辑: 2025-11-23

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { FontAwareHelper, FontAwareState } from '../Framework/Components/FontAware';
import { logger } from '../Utils/Logger';
import { PageLifecycleManager } from '../Framework/Lifecycle';
import { DisplayMode } from '../Utils/WindowManager';
import { PageWindowCoordinator } from '../Utils/PageWindowCoordinator';

const TAG = 'SourceGuidePage';

/**
 * 图源说明页面
 * 提供WebView图源和JSON配置文件的完整开发指南
 */
@Component
export struct SourceGuidePage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  
  // 主题状态
  @State themeState: ThemeAwareState = new ThemeAwareState();
  @State fontState: FontAwareState = new FontAwareState();
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `SourceGuidePage_${Date.now()}`;
  private previousDisplayMode: DisplayMode = DisplayMode.DEFAULT;

  // 滚动控制器
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    logger.lifecycle(TAG, 'aboutToAppear');
    this.previousDisplayMode = PageWindowCoordinator.captureCurrentDisplayMode();
    PageWindowCoordinator.applyPagePolicy('SourceGuidePage', this.getUIContext());
    
    // 初始化主题状态
    ThemeAwareHelper.initializeThemeAware(
      this.componentId,
      this.themeState,
      (newTheme: ThemeType) => {
        logger.info(TAG, `主题已切换到: ${newTheme}`);
      },
      (newState: ThemeAwareState) => {
        this.themeState = newState;
      }
    );
    FontAwareHelper.initializeFontAware(
      this.componentId,
      this.fontState,
      (newState: FontAwareState) => {
        this.fontState = newState;
      }
    );
  }

  private lifecycle = new PageLifecycleManager('SourceGuidePage', { enableDebug: true });

  aboutToDisappear(): void {
    logger.lifecycle(TAG, 'aboutToDisappear');
    PageWindowCoordinator.restoreDisplayMode(this.previousDisplayMode, this.getUIContext());
    this.lifecycle.destroy();
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    FontAwareHelper.cleanupFontAware(this.componentId);
  }

  /**
   * 返回上一页
   */
  private goBack(): void {
    try {
      this.pathStack.pop();
      logger.info(TAG, '返回上一页');
    } catch (error) {
      logger.error(TAG, `返回失败: ${String(error)}`);
    }
  }

  /**
   * 构建章节标题
   */
  @Builder
  buildSectionTitle(title: string, emoji: string) {
    Row({ space: 8 }) {
      Text(emoji)
        .fontSize(24)
        .fontFamily(this.appFontFamily)
      
      Text(title)
        .fontSize(20)
        .fontFamily(this.appFontFamily)
        .fontWeight(FontWeight.Bold)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
    }
    .width('100%')
    .margin({ top: 24, bottom: 12 })
  }

  /**
   * 构建子标题
   */
  @Builder
  buildSubTitle(title: string) {
    Text(title)
      .fontSize(18)
      .fontFamily(this.appFontFamily)
      .fontWeight(FontWeight.Medium)
      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      .width('100%')
      .margin({ top: 16, bottom: 8 })
  }

  /**
   * 构建段落文本
   */
  @Builder
  buildParagraph(text: string) {
    Text(text)
      .fontSize(15)
      .fontFamily(this.appFontFamily)
      .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
      .lineHeight(24)
      .width('100%')
      .margin({ bottom: 12 })
  }

  /**
   * 构建代码块
   */
  @Builder
  buildCodeBlock(code: string, language: string = 'json') {
    Column() {
      // 语言标签
      Row() {
        Text(language.toUpperCase())
          .fontSize(12)
          .fontFamily(this.appFontFamily)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_white', this.themeState.currentTheme))
          .padding({ left: 8, right: 8, top: 4, bottom: 4 })
          .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
          .borderRadius(4)
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8 })

      // 代码内容
      Text(code)
        .fontSize(13)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
        .fontFamily('monospace')
        .lineHeight(20)
        .width('100%')
        .padding(12)
    }
    .width('100%')
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('comp_background_secondary', this.themeState.currentTheme))
    .borderRadius(8)
    .margin({ bottom: 12 })
  }

  /**
   * 构建要点列表项
   */
  @Builder
  buildBulletPoint(text: string) {
    Row({ space: 8 }) {
      Text('•')
        .fontSize(16)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('accent_blue', this.themeState.currentTheme))
        .width(20)
      
      Text(text)
        .fontSize(15)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .lineHeight(22)
        .layoutWeight(1)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ bottom: 8 })
  }

  /**
   * 构建提示框
   */
  @Builder
  buildTipBox(title: string, content: string, type: 'info' | 'warning' | 'success' = 'info') {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text(type === 'info' ? '💡' : type === 'warning' ? '⚠️' : '✅')
          .fontSize(18)
          .fontFamily(this.appFontFamily)
        
        Text(title)
          .fontSize(16)
          .fontFamily(this.appFontFamily)
          .fontWeight(FontWeight.Medium)
          .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
      }
      .width('100%')

      Text(content)
        .fontSize(14)
        .fontFamily(this.appFontFamily)
        .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_secondary', this.themeState.currentTheme))
        .lineHeight(20)
        .width('100%')
    }
    .width('100%')
    .padding(12)
    .backgroundColor(type === 'info' 
      ? ThemeAwareHelper.getTestManagementThemedColor('accent_primary', this.themeState.currentTheme)
      : type === 'warning'
      ? '#FFF3E0'
      : '#E8F5E9')
    .borderRadius(8)
    .margin({ bottom: 12 })
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
        Column() {
          // 顶部导航栏
          Row() {
            Button() {
              SymbolGlyph($r('sys.symbol.arrow_left'))
                .fontSize(24)
                .fontColor([ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme)])
            }
            .width(40)
            .height(40)
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.goBack();
            })

            Text('图源开发指南')
              .fontSize(20)
              .fontFamily(this.appFontFamily)
              .fontWeight(FontWeight.Bold)
              .fontColor(ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme))
              .layoutWeight(1)
              .textAlign(TextAlign.Center)

            // 占位符保持标题居中
            Column()
              .width(40)
              .height(40)
          }
          .width('100%')
          .height(56)
          .padding({ left: 16, right: 16 })

          // 滚动内容
          Scroll(this.scroller) {
            Column() {
              // 简介
              this.buildSectionTitle('📚 简介', '📚')
              this.buildParagraph('漫匣采用先进的WebView图源系统，通过JSON配置文件定义工作流(Workflow)来实现漫画数据的自动化提取。本指南基于最新的引擎实现(2025-11-23)。')

              // WebView图源系统架构
              this.buildSectionTitle('🌐 WebView图源系统架构', '🌐')
              this.buildParagraph('WebView图源系统由三大核心引擎组成，协同工作实现强大的数据提取能力：')

              this.buildSubTitle('核心引擎')
              this.buildBulletPoint('MangaSourceEngine - 主控制器，整合所有引擎并提供统一接口')
              this.buildBulletPoint('MangaSourceActionEngine - 操作执行引擎，支持导航、等待、提取、脚本等12种操作类型')
              this.buildBulletPoint('MangaSourceConfigParser - 配置解析器，将JSON转换为可执行的操作序列')
              this.buildBulletPoint('MangaSourceSelectorEngine - 选择器引擎，支持CSS选择器和特殊语法')
              this.buildBulletPoint('MangaSourceAPIEngine - API引擎，支持RESTful API调用和JSON数据提取')

              this.buildSubTitle('配置文件结构')
              this.buildParagraph('WebView图源配置包含metadata、workflows、network、settings等核心部分：')
              this.buildCodeBlock(`{
  "metadata": {
    "id": "copymanga_webview",
    "name": "拷贝漫画 (WebView)",
    "version": "2.0.0",
    "baseUrl": "https://www.2025copy.com",
    "author": "ManXia Team"
  },
  "network": {
    "userAgent": "Mozilla/5.0...",
    "timeout": 30000,
    "retryCount": 3
  },
  "workflows": {
    "search": [...],
    "getMangaDetail": [...],
    "getChapterList": [...]
  }
}`, 'json')

              this.buildSubTitle('工作流(Workflow)系统')
              this.buildBulletPoint('每个工作流由一系列Action组成，按顺序执行')
              this.buildBulletPoint('支持的工作流类型：search、popular、latest、filter、getMangaDetail、getChapterList、getPageList等')
              this.buildBulletPoint('工作流支持变量替换，如{{query}}、{{mangaId}}、{{chapterId}}')
              this.buildBulletPoint('支持条件判断、循环、脚本执行等高级功能')

              this.buildTipBox('核心优势', 'WebView图源通过声明式配置实现复杂的数据提取逻辑，无需编写代码，支持DOM提取和API调用两种模式。', 'success')

              // Action操作类型
              this.buildSectionTitle('⚙️ Action操作类型', '⚙️')
              this.buildParagraph('ActionEngine支持12种操作类型，涵盖所有数据提取场景：')

              this.buildBulletPoint('navigate - 导航到指定URL，支持变量替换和超时设置')
              this.buildBulletPoint('wait - 等待条件满足(time/element/load/network_idle)')
              this.buildBulletPoint('click - 点击元素，通过CSS选择器定位')
              this.buildBulletPoint('input - 输入文本到表单元素')
              this.buildBulletPoint('extract - 提取DOM数据，支持单项和多项提取')
              this.buildBulletPoint('script - 执行自定义JavaScript代码')

              this.buildSubTitle('高级操作')
              this.buildBulletPoint('condition - 条件判断，支持then/else分支')
              this.buildBulletPoint('api - RESTful API请求，支持GET/POST/PUT/DELETE')
              this.buildBulletPoint('http - 通用HTTP请求')

              this.buildSubTitle('反爬虫对抗')
              this.buildBulletPoint('cloudflare_bypass - 绕过Cloudflare防护')
              this.buildBulletPoint('captcha - 验证码处理(支持自动识别)')
              this.buildBulletPoint('ip_block - IP封禁处理和重试策略')

              this.buildSubTitle('选择器语法')
              this.buildParagraph('SelectorEngine支持强大的选择器语法：')
              this.buildCodeBlock(`// CSS选择器
".manga-item"           // 类选择器
"#manga-123"            // ID选择器
"div.title"             // 标签+类
"a[href*='comic']"      // 属性选择器

// 特殊语法
".title::text"          // 提取文本内容
"img::attr(data-src)"   // 提取属性值
"@href"                 // 简写：提取href属性
"@data-id"              // 简写：提取data-id属性
"::index"               // 获取索引值`, 'css')

              this.buildTipBox('选择器优势', '支持CSS3全部选择器，并扩展了::text、::attr()等特殊语法，简化数据提取。', 'info')

              // 实战示例：拷贝漫画WebView图源
              this.buildSectionTitle('📖 实战示例：拷贝漫画', '📖')
              this.buildParagraph('以copymanga_webview.json为例，展示完整的工作流配置：')
              
              this.buildSubTitle('1. 搜索工作流')
              this.buildCodeBlock(`"search": {
  "actions": [
    {
      "type": "navigate",
      "url": "https://www.2025copy.com/search?q={{query}}",
      "timeout": 10000
    },
    {
      "type": "wait",
      "condition": "time",
      "duration": 1500
    },
    {
      "type": "script",
      "code": "window.scrollTo(0, 2400);"
    },
    {
      "type": "extract",
      "selector": ".exemptComic_Item",
      "multiple": true,
      "fields": {
        "id": "a::attr(href)",
        "title": ".exemptComicItem-txt p::text",
        "cover": "img::attr(data-src)"
      }
    }
  ]
}`, 'json')

              this.buildSubTitle('2. 章节列表提取')
              this.buildParagraph('使用script操作执行复杂的DOM提取逻辑：')
              this.buildCodeBlock(`{
  "type": "script",
  "code": "(() => {
    const chapters = [];
    const links = document.querySelectorAll('.chapter-list li a');
    links.forEach(link => {
      chapters.push({
        id: link.getAttribute('href'),
        title: link.textContent.trim()
      });
    });
    return JSON.stringify(chapters);
  })();"
}`, 'javascript')

              this.buildSubTitle('3. 错误处理与重试')
              this.buildCodeBlock(`"errorHandling": {
  "retry": {
    "enabled": true,
    "maxAttempts": 3,
    "strategy": "exponential",
    "baseDelay": 2000,
    "retryOn": {
      "statusCodes": [408, 429, 500, 502, 503, 504],
      "errors": ["TIMEOUT", "NETWORK_ERROR"]
    }
  },
  "fallback": {
    "enabled": true,
    "strategies": [
      {
        "type": "alternativeUrl",
        "url": "https://www.copy20.com"
      }
    ]
  }
}`, 'json')

              // 测试和调试
              this.buildSectionTitle('🔧 测试和调试', '🔧')
              this.buildParagraph('漫匣提供了完整的图源测试工具，帮助您快速验证图源配置。')

              this.buildSubTitle('测试步骤')
              this.buildBulletPoint('1. 在设置页面进入"数据管理"')
              this.buildBulletPoint('2. 选择"导入图源配置"')
              this.buildBulletPoint('3. 上传您的JSON配置文件')
              this.buildBulletPoint('4. 使用"图源测试"工具验证各个接口')
              this.buildBulletPoint('5. 查看详细的请求和响应日志')

              this.buildSubTitle('调试技巧')
              this.buildBulletPoint('查看Logger输出：MangaSourceEngine、ActionEngine、ConfigParser都有详细日志')
              this.buildBulletPoint('使用script操作输出console.log，通过WebView调试工具查看')
              this.buildBulletPoint('验证选择器：先在浏览器开发者工具测试CSS选择器')
              this.buildBulletPoint('检查变量替换：确认{{query}}、{{mangaId}}等变量正确传递')

              this.buildTipBox('调试建议', '开启debug模式后，引擎会输出每个Action的执行结果和耗时，帮助定位问题。', 'warning')

              // 技术要点
              this.buildSectionTitle('� 技术要点', '�')
              
              this.buildSubTitle('变量系统')
              this.buildBulletPoint('支持的内置变量：query、mangaId、chapterId、page、offset、baseUrl')
              this.buildBulletPoint('script操作的返回值自动保存到scriptResult变量')
              this.buildBulletPoint('可通过settings定义用户可配置的变量(如filterOrdering、imageQuality)')
              
              this.buildSubTitle('执行流程')
              this.buildBulletPoint('1. ConfigParser解析JSON并验证配置')
              this.buildBulletPoint('2. Engine根据工作流类型构建Action序列')
              this.buildBulletPoint('3. ActionEngine按顺序执行每个Action')
              this.buildBulletPoint('4. SelectorEngine处理DOM提取，APIEngine处理API请求')
              this.buildBulletPoint('5. 结果经过transformToMangaInfo/ChapterInfo转换后返回')

              this.buildSubTitle('性能优化')
              this.buildBulletPoint('合理设置wait时间，避免过长等待')
              this.buildBulletPoint('使用script一次性提取多个字段，减少JavaScript调用次数')
              this.buildBulletPoint('启用errorHandling的retry和fallback机制提高成功率')
              this.buildBulletPoint('对于大量数据，考虑使用API模式替代DOM提取')

              this.buildTipBox('最佳实践', '参考copymanga_webview.json和komiic_webview.json的实现，它们展示了处理懒加载、滚动触发、复杂DOM结构的最佳方案。', 'success')

              // 常见问题
              this.buildSectionTitle('❓ 常见问题', '❓')
              
              this.buildSubTitle('Q: extract操作提取不到数据？')
              this.buildParagraph('A: 1) 检查选择器是否正确；2) 确认页面是否已加载完成(增加wait时间)；3) 检查是否是懒加载内容(需要先滚动)；4) 使用浏览器开发者工具验证选择器。')

              this.buildSubTitle('Q: script操作返回undefined？')
              this.buildParagraph('A: 1) 确保脚本有return语句；2) 对于对象/数组，使用JSON.stringify()转换；3) 检查是否有JavaScript语法错误；4) 查看WebView控制台日志。')

              this.buildSubTitle('Q: 如何处理懒加载内容？')
              this.buildParagraph('A: 使用script操作执行window.scrollTo()滚动页面，然后wait等待DOM更新，最后extract提取数据。参考copymanga的实现。')

              this.buildSubTitle('Q: 变量替换不生效？')
              this.buildParagraph('A: 1) 检查变量名拼写(区分大小写)；2) 确认变量已在context中设置；3) 使用{{}}包裹变量名；4) 查看日志确认变量值。')

              this.buildSubTitle('Q: 如何支持多个域名？')
              this.buildParagraph('A: 在metadata.alternativeUrls中配置备用域名，在settings中提供domain选择器，errorHandling中配置fallback策略。')

              // 底部间距
              Column()
                .height(40)
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 16, bottom: 20 })
          }
          .layoutWeight(1)
          .scrollBar(BarState.Auto)
          .edgeEffect(EdgeEffect.Spring)
        }
        .width('100%')
        .height('100%')
        .padding({ top: this.statusBarHeight })
      }
    }
    .backgroundColor(Color.Transparent)
    .hideTitleBar(true)
  }
}

