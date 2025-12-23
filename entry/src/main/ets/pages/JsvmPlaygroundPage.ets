/**
 * JSVM Playground - JavaScript 代码运行测试页面
 * 提供类似IDE的代码编辑和执行环境，用于测试JSVM引擎功能
 * 
 * 文件路径: entry/src/main/ets/pages/JsvmPlaygroundPage.ets
 */

import { HdsNavDestination, HdsNavDestinationAttribute, ScrollEffectType } from '@kit.UIDesignKit';
import { LengthMetrics, promptAction } from '@kit.ArkUI';
import { logger } from '../Utils/Logger';
import { ThemeAwareState, ThemeAwareHelper } from '../Framework/Components/ThemeAware';
import { ThemeManager, ThemeType } from '../Framework/Managers/ThemeManager';
import { NativeJsEngine, JsContext, JsResult, getNativeJsEngine } from '../Framework/Novel/NativeJsEngine';
import { testHtmlParser } from '../libs/htmlparser/index';

const TAG = 'JsvmPlaygroundPage';

/**
 * 代码示例
 */
interface CodeExample {
  name: string;
  code: string;
  description: string;
}

/**
 * 执行历史记录
 */
interface ExecutionHistory {
  id: number;
  code: string;
  result: string;
  success: boolean;
  timestamp: number;
  duration: number;
}

@Component
export struct JsvmPlaygroundPage {
  @Consume('NavPathStack') pathStack: NavPathStack;
  @State themeState: ThemeAwareState = new ThemeAwareState();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private componentId: string = `JsvmPlaygroundPage_${Date.now()}`;
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  // 编辑器状态
  @State codeInput: string = '// 在这里输入JavaScript代码\nvar result = 1 + 2 * 3;\nresult;';
  @State outputText: string = '';
  @State isExecuting: boolean = false;
  @State executionTime: number = 0;
  
  // 上下文变量
  @State contextResult: string = '';
  @State contextBaseUrl: string = 'https://example.com';
  @State contextKey: string = '测试关键字';
  @State contextPage: number = 1;
  
  // 执行历史
  @State executionHistory: ExecutionHistory[] = [];
  private historyIdCounter: number = 0;
  
  // 引擎状态
  @State engineStatus: string = '未初始化';
  @State vmCount: number = 0;
  
  // UI状态
  @State showExamples: boolean = false;
  @State showContext: boolean = false;
  @State showHistory: boolean = false;
  @State selectedTab: number = 0; // 0: 编辑器, 1: 输出, 2: 历史
  
  // 代码示例
  private codeExamples: CodeExample[] = [
    {
      name: '基础运算',
      code: '// 基础数学运算\nvar a = 10;\nvar b = 20;\nvar sum = a + b;\nvar product = a * b;\n"和: " + sum + ", 积: " + product;',
      description: '演示基本的数学运算'
    },
    {
      name: '字符串操作',
      code: '// 字符串操作\nvar str = "Hello, JSVM!";\nvar upper = str.toUpperCase();\nvar lower = str.toLowerCase();\nvar len = str.length;\n"原始: " + str + "\\n大写: " + upper + "\\n长度: " + len;',
      description: '演示字符串处理'
    },
    {
      name: '数组操作',
      code: '// 数组操作\nvar arr = [1, 2, 3, 4, 5];\nvar doubled = [];\nfor (var i = 0; i < arr.length; i++) {\n  doubled.push(arr[i] * 2);\n}\nJSON.stringify(doubled);',
      description: '演示数组遍历和操作'
    },
    {
      name: 'JSON处理',
      code: '// JSON处理\nvar obj = {\n  name: "JSVM",\n  version: "1.0",\n  features: ["执行JS", "无需JIT"]\n};\nJSON.stringify(obj, null, 2);',
      description: '演示JSON序列化'
    },
    {
      name: '使用上下文变量',
      code: '// 使用上下文变量\n// baseUrl, key, page 是预设的上下文变量\nvar url = baseUrl + "/search?q=" + encodeURIComponent(key) + "&page=" + page;\nurl;',
      description: '演示如何使用预设的上下文变量'
    },
    {
      name: 'Base64编解码',
      code: '// Base64编解码 (使用java对象)\nvar original = "Hello, 鸿蒙!";\nvar encoded = java.base64Encode(original);\nvar decoded = java.base64Decode(encoded);\n"原始: " + original + "\\n编码: " + encoded + "\\n解码: " + decoded;',
      description: '演示Base64编解码功能'
    },
    {
      name: '时间格式化',
      code: '// 时间格式化\nvar now = Date.now();\nvar formatted = java.timeFormat(now);\n"当前时间戳: " + now + "\\n格式化: " + formatted;',
      description: '演示时间格式化功能'
    },
    {
      name: '正则表达式',
      code: '// 正则表达式\nvar text = "价格: ¥99.99, 数量: 10个";\nvar priceMatch = text.match(/¥([\\d.]+)/);\nvar numMatch = text.match(/(\\d+)个/);\n"价格: " + (priceMatch ? priceMatch[1] : "未找到") + "\\n数量: " + (numMatch ? numMatch[1] : "未找到");',
      description: '演示正则表达式匹配'
    },
    {
      name: 'HTML解析测试',
      code: '// HTML解析测试 (使用 node-html-parser)\n// 点击"测试HTML解析器"按钮来测试\n"请点击下方的【测试HTML解析器】按钮";',
      description: '测试 node-html-parser 库是否正常工作'
    }
  ];

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
    this.checkEngineStatus();
  }

  aboutToDisappear(): void {
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
  }

  /**
   * 检查引擎状态
   */
  private checkEngineStatus(): void {
    // 首先检查Native模块是否可用
    if (!NativeJsEngine.isNativeModuleAvailable()) {
      this.engineStatus = '模块未加载';
      this.vmCount = 0;
      logger.warn(TAG, `Native JSVM模块未加载: ${NativeJsEngine.getNativeModuleError()}`);
      return;
    }
    
    try {
      const engine = getNativeJsEngine();
      if (engine.isReady()) {
        this.engineStatus = '已就绪';
      } else {
        this.engineStatus = '初始化中...';
        engine.initialize().then((success: boolean) => {
          this.engineStatus = success ? '已就绪' : '初始化失败';
          this.vmCount = NativeJsEngine.getVmCount();
        });
      }
      this.vmCount = NativeJsEngine.getVmCount();
    } catch (e) {
      this.engineStatus = `错误: ${String(e)}`;
    }
  }

  /**
   * 执行代码
   */
  private async executeCode(): Promise<void> {
    if (this.isExecuting) {
      return;
    }
    
    if (!this.codeInput.trim()) {
      promptAction.showToast({ message: '请输入代码' });
      return;
    }
    
    this.isExecuting = true;
    this.outputText = '执行中...';
    const startTime = Date.now();
    
    try {
      const engine = getNativeJsEngine();
      
      // 构建上下文
      const context: JsContext = {
        result: this.contextResult,
        baseUrl: this.contextBaseUrl,
        key: this.contextKey,
        page: this.contextPage
      };
      
      const result = await engine.execute(this.codeInput, context);
      const endTime = Date.now();
      this.executionTime = endTime - startTime;
      
      if (result.success) {
        this.outputText = result.result;
      } else {
        this.outputText = `错误: ${result.error || '未知错误'}`;
      }
      
      // 添加到历史记录
      this.addToHistory(this.codeInput, this.outputText, result.success, this.executionTime);
      
      // 更新引擎状态
      this.vmCount = NativeJsEngine.getVmCount();
      
    } catch (e) {
      const endTime = Date.now();
      this.executionTime = endTime - startTime;
      this.outputText = `执行异常: ${String(e)}`;
      this.addToHistory(this.codeInput, this.outputText, false, this.executionTime);
    }
    
    this.isExecuting = false;
  }

  /**
   * 添加到历史记录
   */
  private addToHistory(code: string, result: string, success: boolean, duration: number): void {
    const history: ExecutionHistory = {
      id: ++this.historyIdCounter,
      code: code,
      result: result,
      success: success,
      timestamp: Date.now(),
      duration: duration
    };
    
    // 保持最多20条记录
    if (this.executionHistory.length >= 20) {
      this.executionHistory.pop();
    }
    this.executionHistory.unshift(history);
  }

  /**
   * 清空代码
   */
  private clearCode(): void {
    this.codeInput = '';
    this.outputText = '';
  }

  /**
   * 测试 HTML 解析器
   */
  private testHtmlParserLib(): void {
    const startTime = Date.now();
    try {
      const result = testHtmlParser();
      const endTime = Date.now();
      this.executionTime = endTime - startTime;
      this.outputText = result;
      this.addToHistory('// HTML Parser Test', result, result.includes('PASSED'), this.executionTime);
      this.selectedTab = 1; // 切换到输出面板
    } catch (e) {
      const endTime = Date.now();
      this.executionTime = endTime - startTime;
      this.outputText = `HTML解析器测试失败: ${String(e)}`;
      this.addToHistory('// HTML Parser Test', this.outputText, false, this.executionTime);
      this.selectedTab = 1;
    }
  }

  /**
   * 加载示例代码
   */
  private loadExample(example: CodeExample): void {
    this.codeInput = example.code;
    this.showExamples = false;
    promptAction.showToast({ message: `已加载: ${example.name}` });
  }

  /**
   * 从历史记录加载
   */
  private loadFromHistory(history: ExecutionHistory): void {
    this.codeInput = history.code;
    this.showHistory = false;
    this.selectedTab = 0;
  }

  /**
   * 格式化时间戳
   */
  private formatTimestamp(timestamp: number): string {
    const date = new Date(timestamp);
    const hours = String(date.getHours()).padStart(2, '0');
    const minutes = String(date.getMinutes()).padStart(2, '0');
    const seconds = String(date.getSeconds()).padStart(2, '0');
    return `${hours}:${minutes}:${seconds}`;
  }

  build() {
    HdsNavDestination() {
      Column() {
        // 工具栏
        this.buildToolbar()
        
        // 主内容区域
        Column() {
          // 标签栏
          this.buildTabBar()
          
          // 内容区域
          Stack() {
            if (this.selectedTab === 0) {
              this.buildEditorPanel()
            } else if (this.selectedTab === 1) {
              this.buildOutputPanel()
            } else {
              this.buildHistoryPanel()
            }
          }
          .layoutWeight(1)
          .width('100%')
        }
        .layoutWeight(1)
        .width('100%')
        
        // 底部操作栏
        this.buildBottomBar()
      }
      .width('100%')
      .height('100%')
      .padding({ top: this.statusBarHeight, bottom: this.navigationBarHeight })
      .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
    }
    .titleBar({
      padding: {
        start: LengthMetrics.vp(2),
        end: LengthMetrics.vp(2)
      },
      style: {
        originalStyle: {
          backgroundStyle: {
            backgroundColor: ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme),
          },
          contentStyle: {
            titleStyle: {
              mainTitleColor: ThemeAwareHelper.getTestManagementThemedColor('text_primary', this.themeState.currentTheme),
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
          mainTitle: 'JSVM Playground'
        }
      }
    })
    .backgroundColor(ThemeAwareHelper.getTestManagementThemedColor('background', this.themeState.currentTheme))
    .onReady(() => {
      logger.info(TAG, 'HdsNavDestination.onReady 已触发');
    })
  }

  /**
   * 显示引擎信息
   */
  private showEngineInfo(): void {
    const isAvailable = NativeJsEngine.isNativeModuleAvailable();
    const moduleError = NativeJsEngine.getNativeModuleError();
    
    let message = `状态: ${this.engineStatus}\n活跃VM数: ${this.vmCount}\n\n`;
    
    if (isAvailable) {
      message += 'JSVM-API 使用解释器模式执行JavaScript代码，无需JIT权限。';
    } else {
      message += `⚠️ Native模块未加载\n\n原因: ${moduleError || '未知'}\n\n`;
      message += '解决方案:\n';
      message += '1. 在build-profile.json5中配置externalNativeOptions\n';
      message += '2. 确保CMakeLists.txt路径正确\n';
      message += '3. 重新编译项目';
    }
    
    promptAction.showDialog({
      title: 'JSVM 引擎信息',
      message: message,
      buttons: [{ text: '确定', color: '#007AFF' }]
    });
  }

  @Builder
  buildToolbar() {
    Row() {
      // 示例按钮
      Button('示例')
        .type(ButtonType.Normal)
        .height(32)
        .fontSize(13)
        .fontColor(this.themeState.isDarkTheme() ? '#ffffff' : '#333333')
        .backgroundColor(this.themeState.isDarkTheme() ? '#333333' : '#e0e0e0')
        .borderRadius(6)
        .onClick(() => {
          this.showExamples = !this.showExamples;
          this.showContext = false;
        })
      
      // 上下文按钮
      Button('上下文')
        .type(ButtonType.Normal)
        .height(32)
        .fontSize(13)
        .fontColor(this.themeState.isDarkTheme() ? '#ffffff' : '#333333')
        .backgroundColor(this.showContext ? '#007AFF' : (this.themeState.isDarkTheme() ? '#333333' : '#e0e0e0'))
        .borderRadius(6)
        .margin({ left: 8 })
        .onClick(() => {
          this.showContext = !this.showContext;
          this.showExamples = false;
        })
      
      // HTML解析器测试按钮
      Button('测试HTML解析')
        .type(ButtonType.Normal)
        .height(32)
        .fontSize(13)
        .fontColor('#ffffff')
        .backgroundColor('#4CAF50')
        .borderRadius(6)
        .margin({ left: 8 })
        .onClick(() => {
          this.testHtmlParserLib();
        })
      
      Blank()
      
      // 引擎状态指示器
      Row() {
        Circle()
          .width(8)
          .height(8)
          .fill(this.engineStatus === '已就绪' ? '#4CAF50' : (this.engineStatus.includes('错误') ? '#F44336' : '#FF9800'))
        Text(this.engineStatus)
          .fontSize(12)
          .fontColor(this.themeState.isDarkTheme() ? '#aaaaaa' : '#666666')
          .margin({ left: 4 })
      }
    }
    .width('100%')
    .height(44)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.themeState.isDarkTheme() ? '#252525' : '#ffffff')
    
    // 示例列表
    if (this.showExamples) {
      this.buildExamplesPanel()
    }
    
    // 上下文设置
    if (this.showContext) {
      this.buildContextPanel()
    }
  }

  @Builder
  buildExamplesPanel() {
    Column() {
      ForEach(this.codeExamples, (example: CodeExample) => {
        Row() {
          Column() {
            Text(example.name)
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.themeState.isDarkTheme() ? '#ffffff' : '#333333')
            Text(example.description)
              .fontSize(12)
              .fontColor(this.themeState.isDarkTheme() ? '#888888' : '#666666')
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)
          
          SymbolGlyph($r('sys.symbol.chevron_right'))
            .fontSize(16)
            .fontColor([this.themeState.isDarkTheme() ? '#666666' : '#999999'])
        }
        .width('100%')
        .padding(12)
        .backgroundColor(this.themeState.isDarkTheme() ? '#2a2a2a' : '#fafafa')
        .borderRadius(8)
        .margin({ bottom: 8 })
        .onClick(() => this.loadExample(example))
      })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.themeState.isDarkTheme() ? '#1e1e1e' : '#f0f0f0')
  }

  @Builder
  buildContextPanel() {
    Column() {
      Text('上下文变量')
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.themeState.isDarkTheme() ? '#ffffff' : '#333333')
        .margin({ bottom: 12 })
      
      // baseUrl
      Row() {
        Text('baseUrl')
          .fontSize(13)
          .fontColor(this.themeState.isDarkTheme() ? '#aaaaaa' : '#666666')
          .width(80)
        TextInput({ text: this.contextBaseUrl })
          .layoutWeight(1)
          .height(36)
          .fontSize(13)
          .backgroundColor(this.themeState.isDarkTheme() ? '#333333' : '#ffffff')
          .onChange((value: string) => {
            this.contextBaseUrl = value;
          })
      }
      .width('100%')
      .margin({ bottom: 8 })
      
      // key
      Row() {
        Text('key')
          .fontSize(13)
          .fontColor(this.themeState.isDarkTheme() ? '#aaaaaa' : '#666666')
          .width(80)
        TextInput({ text: this.contextKey })
          .layoutWeight(1)
          .height(36)
          .fontSize(13)
          .backgroundColor(this.themeState.isDarkTheme() ? '#333333' : '#ffffff')
          .onChange((value: string) => {
            this.contextKey = value;
          })
      }
      .width('100%')
      .margin({ bottom: 8 })
      
      // page
      Row() {
        Text('page')
          .fontSize(13)
          .fontColor(this.themeState.isDarkTheme() ? '#aaaaaa' : '#666666')
          .width(80)
        TextInput({ text: String(this.contextPage) })
          .layoutWeight(1)
          .height(36)
          .fontSize(13)
          .type(InputType.Number)
          .backgroundColor(this.themeState.isDarkTheme() ? '#333333' : '#ffffff')
          .onChange((value: string) => {
            const num = parseInt(value);
            if (!isNaN(num)) {
              this.contextPage = num;
            }
          })
      }
      .width('100%')
      .margin({ bottom: 8 })
      
      // result
      Row() {
        Text('result')
          .fontSize(13)
          .fontColor(this.themeState.isDarkTheme() ? '#aaaaaa' : '#666666')
          .width(80)
        TextInput({ text: this.contextResult, placeholder: '上一步结果(可选)' })
          .layoutWeight(1)
          .height(36)
          .fontSize(13)
          .backgroundColor(this.themeState.isDarkTheme() ? '#333333' : '#ffffff')
          .onChange((value: string) => {
            this.contextResult = value;
          })
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.themeState.isDarkTheme() ? '#1e1e1e' : '#f0f0f0')
  }

  @Builder
  buildTabBar() {
    Row() {
      this.buildTabButton('编辑器', 0)
      this.buildTabButton('输出', 1)
      this.buildTabButton('历史', 2)
    }
    .width('100%')
    .height(40)
    .backgroundColor(this.themeState.isDarkTheme() ? '#252525' : '#ffffff')
    .border({ width: { bottom: 1 }, color: this.themeState.isDarkTheme() ? '#333333' : '#e0e0e0' })
  }

  @Builder
  buildTabButton(title: string, index: number) {
    Column() {
      Text(title)
        .fontSize(14)
        .fontColor(this.selectedTab === index ? '#007AFF' : (this.themeState.isDarkTheme() ? '#888888' : '#666666'))
        .fontWeight(this.selectedTab === index ? FontWeight.Medium : FontWeight.Normal)
      
      if (this.selectedTab === index) {
        Divider()
          .width(40)
          .height(2)
          .color('#007AFF')
          .margin({ top: 6 })
      }
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.selectedTab = index;
    })
  }

  @Builder
  buildEditorPanel() {
    Column() {
      // 代码编辑区
      TextArea({ text: this.codeInput, placeholder: '// 在这里输入JavaScript代码' })
        .width('100%')
        .layoutWeight(1)
        .fontSize(14)
        .fontFamily('monospace')
        .backgroundColor(this.themeState.isDarkTheme() ? '#1e1e1e' : '#ffffff')
        .fontColor(this.themeState.isDarkTheme() ? '#d4d4d4' : '#333333')
        .caretColor('#007AFF')
        .padding(12)
        .borderRadius(0)
        .onChange((value: string) => {
          this.codeInput = value;
        })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildOutputPanel() {
    Column() {
      // 执行时间
      if (this.executionTime > 0) {
        Row() {
          Text(`执行耗时: ${this.executionTime}ms`)
            .fontSize(12)
            .fontColor(this.themeState.isDarkTheme() ? '#888888' : '#666666')
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        .backgroundColor(this.themeState.isDarkTheme() ? '#252525' : '#f5f5f5')
      }
      
      // 输出内容
      Scroll() {
        Text(this.outputText || '暂无输出')
          .width('100%')
          .fontSize(14)
          .fontFamily('monospace')
          .fontColor(this.outputText.startsWith('错误') || this.outputText.startsWith('执行异常') 
            ? '#F44336' 
            : (this.themeState.isDarkTheme() ? '#d4d4d4' : '#333333'))
          .padding(12)
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor(this.themeState.isDarkTheme() ? '#1e1e1e' : '#ffffff')
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  buildHistoryPanel() {
    if (this.executionHistory.length === 0) {
      Column() {
        SymbolGlyph($r('sys.symbol.clock'))
          .fontSize(48)
          .fontColor([this.themeState.isDarkTheme() ? '#444444' : '#cccccc'])
        Text('暂无执行历史')
          .fontSize(14)
          .fontColor(this.themeState.isDarkTheme() ? '#666666' : '#999999')
          .margin({ top: 12 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
    } else {
      List() {
        ForEach(this.executionHistory, (history: ExecutionHistory) => {
          ListItem() {
            Column() {
              Row() {
                // 状态指示
                Circle()
                  .width(8)
                  .height(8)
                  .fill(history.success ? '#4CAF50' : '#F44336')
                
                Text(this.formatTimestamp(history.timestamp))
                  .fontSize(12)
                  .fontColor(this.themeState.isDarkTheme() ? '#888888' : '#666666')
                  .margin({ left: 8 })
                
                Text(`${history.duration}ms`)
                  .fontSize(12)
                  .fontColor(this.themeState.isDarkTheme() ? '#666666' : '#999999')
                  .margin({ left: 8 })
                
                Blank()
                
                Button('加载')
                  .type(ButtonType.Normal)
                  .height(24)
                  .fontSize(11)
                  .fontColor('#007AFF')
                  .backgroundColor(Color.Transparent)
                  .onClick(() => this.loadFromHistory(history))
              }
              .width('100%')
              
              // 代码预览
              Text(history.code.split('\n')[0] + (history.code.includes('\n') ? '...' : ''))
                .fontSize(12)
                .fontFamily('monospace')
                .fontColor(this.themeState.isDarkTheme() ? '#aaaaaa' : '#555555')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 6 })
              
              // 结果预览
              Text(history.result.substring(0, 50) + (history.result.length > 50 ? '...' : ''))
                .fontSize(11)
                .fontColor(history.success ? (this.themeState.isDarkTheme() ? '#888888' : '#666666') : '#F44336')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 4 })
            }
            .width('100%')
            .padding(12)
            .backgroundColor(this.themeState.isDarkTheme() ? '#252525' : '#ffffff')
            .borderRadius(8)
          }
          .margin({ bottom: 8 })
        })
      }
      .width('100%')
      .height('100%')
      .padding(12)
      .backgroundColor(this.themeState.isDarkTheme() ? '#1a1a1a' : '#f5f5f5')
    }
  }

  @Builder
  buildBottomBar() {
    Row() {
      // 清空按钮
      Button() {
        Row() {
          SymbolGlyph($r('sys.symbol.trash'))
            .fontSize(16)
            .fontColor(['#F44336'])
          Text('清空')
            .fontSize(14)
            .fontColor('#F44336')
            .margin({ left: 4 })
        }
      }
      .type(ButtonType.Normal)
      .height(44)
      .backgroundColor(this.themeState.isDarkTheme() ? '#2a2a2a' : '#fff0f0')
      .borderRadius(8)
      .padding({ left: 16, right: 16 })
      .onClick(() => this.clearCode())
      
      Blank()
      
      // 运行按钮
      Button() {
        Row() {
          if (this.isExecuting) {
            LoadingProgress()
              .width(16)
              .height(16)
              .color(Color.White)
          } else {
            SymbolGlyph($r('sys.symbol.play_fill'))
              .fontSize(16)
              .fontColor([Color.White])
          }
          Text(this.isExecuting ? '执行中...' : '运行')
            .fontSize(14)
            .fontColor(Color.White)
            .margin({ left: 4 })
        }
      }
      .type(ButtonType.Normal)
      .height(44)
      .backgroundColor(this.isExecuting ? '#999999' : '#007AFF')
      .borderRadius(8)
      .padding({ left: 24, right: 24 })
      .enabled(!this.isExecuting)
      .onClick(() => {
        this.executeCode();
        this.selectedTab = 1; // 切换到输出面板
      })
    }
    .width('100%')
    .height(60)
    .padding({ left: 16, right: 16 })
    .backgroundColor(this.themeState.isDarkTheme() ? '#252525' : '#ffffff')
    .border({ width: { top: 1 }, color: this.themeState.isDarkTheme() ? '#333333' : '#e0e0e0' })
  }
}
