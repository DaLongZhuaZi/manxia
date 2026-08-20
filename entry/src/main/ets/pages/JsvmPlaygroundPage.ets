import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
/**
 * JSVM Playground - JavaScript 代码运行测试页面
 * 提供类似IDE的代码编辑和执行环境，用于测试JSVM引擎功能
 * 
 * 文件路径: entry/src/main/ets/pages/JsvmPlaygroundPage.ets
 */

import { HdsNavDestination } from '@kit.UIDesignKit';
import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { webview } from '@kit.ArkWeb';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ThemeAwareHelper, ThemeAwareState } from 'manxia_theme/src/main/ets/Framework/Components/ThemeAware';
import { PageLifecycleManager, Disposable, CancellationError } from 'manxia_core/src/main/ets/Framework/Lifecycle/index';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';
import { NativeJsEngine, JsContext, JsResult, getNativeJsEngine } from '../Framework/Novel/NativeJsEngine';
import { testHtmlParser } from 'manxia_core/src/main/ets/libs/htmlparser/index';
import { getLegadoRhinoEngine, JsEngineType, LegadoRhinoEngine } from '../Framework/Novel/LegadoRhinoEngine';
import { getLegadoJsEngine } from '../Framework/Novel/LegadoJsEngine';
import { SettingsImmersiveTitleBar } from './settings/SettingsImmersiveTitleBar';
import { SettingsPageTitleBarManager } from './settings/SettingsPageTitleBarManager';
import quickjs from 'libquickjs_engine.so';

const TAG = 'JsvmPlaygroundPage';

/**
 * QuickJS执行结果接口
 */
interface QuickJSResult {
  success: boolean;
  result: string;
  error?: string;
}

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
  @StorageLink('appFontFamily') appFontFamily: string = 'HarmonyOS Sans';
  @StorageProp('statusBarHeight') statusBarHeight: number = 0;
  @StorageProp('navigationBarHeight') navigationBarHeight: number = 0;
  
  // 生命周期管理器
  private lifecycle = new PageLifecycleManager('JsvmPlaygroundPage', {
    enableDebug: true
  });
  
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
  
  // QuickJS引擎状态
  @State quickjsStatus: string = '未初始化';
  @State quickjsInitialized: boolean = false;
  
  // Rhino沙箱引擎状态
  @State rhinoSandboxStatus: string = '未初始化';
  @State rhinoSandboxMode: string = '';
  private rhinoEngine: LegadoRhinoEngine | null = null;
  
  // WebView开关（用于测试不同引擎模式）
  @State enableWebView: boolean = false;
  @State webViewStatus: string = '未启用';
  
  // WebView控制器（用于LegadoJsEngine执行网络请求）
  private webViewController: webview.WebviewController = new webview.WebviewController();
  
  // UI状态
  @State showExamples: boolean = false;
  @State showContext: boolean = false;
  @State showHistory: boolean = false;
  @State showSettings: boolean = false;
  @State selectedTab: number = 0; // 0: 编辑器, 1: 输出, 2: 历史
  
  // 历史记录展开状态
  @State expandedHistoryIds: Set<number> = new Set<number>();
  
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
    },
    {
      name: '[QuickJS] 基础测试',
      code: '// QuickJS基础测试\nvar a = 100;\nvar b = 200;\nvar result = a + b;\n"QuickJS计算结果: " + result;',
      description: '使用QuickJS引擎执行基础运算'
    },
    {
      name: '[QuickJS] BigInt测试',
      code: '// QuickJS BigInt测试\nvar big1 = 9007199254740993n;\nvar big2 = 1n;\nvar sum = big1 + big2;\n"BigInt结果: " + sum.toString();',
      description: '测试QuickJS的BigInt支持'
    },
    {
      name: '[QuickJS] java.base64Encode',
      code: '// QuickJS Base64编码测试\nvar text = "Hello, 鸿蒙QuickJS!";\nvar encoded = java.base64Encode(text);\n"原文: " + text + "\\n编码: " + encoded;',
      description: '测试QuickJS的Legado API - Base64编码'
    },
    {
      name: '[QuickJS] source对象',
      code: '// QuickJS source对象测试\nsource.setVariable("testKey", "testValue123");\nvar value = source.getVariable("testKey");\n"source变量测试: " + value;',
      description: '测试QuickJS的Legado API - source对象'
    },
    {
      name: '[QuickJS] 上下文变量',
      code: '// QuickJS上下文变量测试\n// key, page, baseUrl 是预设变量\nvar info = "关键字: " + key + "\\n";\ninfo += "页码: " + page + "\\n";\ninfo += "基础URL: " + baseUrl;\ninfo;',
      description: '测试QuickJS的上下文变量注入'
    },
    {
      name: '[Rhino沙箱] 基础测试',
      code: '// Rhino沙箱基础测试\nvar a = 100;\nvar b = 200;\nvar result = a + b;\n"Rhino沙箱计算结果: " + result;',
      description: '使用Rhino WASM沙箱执行基础运算'
    },
    {
      name: '[Rhino沙箱] java.ajax模拟',
      code: '// Rhino沙箱网络请求测试\n// 注意：实际请求可能受跨域限制\nvar url = baseUrl + "/api/test";\njava.log("请求URL: " + url);\n"模拟请求: " + url;',
      description: '测试Rhino沙箱的java.ajax功能'
    },
    {
      name: '[Rhino沙箱] Jsoup解析',
      code: '// Jsoup HTML解析测试\nvar html = "<div class=\\"item\\"><h1>标题</h1><p>内容</p></div>";\nvar doc = Jsoup.parse(html);\nvar title = doc.select("h1").text();\nvar content = doc.select("p").text();\n"标题: " + title + ", 内容: " + content;',
      description: '测试Rhino沙箱的Jsoup DOM解析'
    },
    {
      name: '[Rhino沙箱] source对象',
      code: '// Rhino沙箱source对象测试\nsource.setVariable("testKey", "testValue123");\nvar value = source.getVariable("testKey");\n"source变量测试: " + value;',
      description: '测试Rhino沙箱的source对象'
    },
    {
      name: '[Rhino沙箱] Base64编解码',
      code: '// Rhino沙箱Base64测试\nvar original = "Hello, 鸿蒙Rhino!";\nvar encoded = java.base64Encode(original);\nvar decoded = java.base64Decode(encoded);\n"原文: " + original + "\\n编码: " + encoded + "\\n解码: " + decoded;',
      description: '测试Rhino沙箱的Base64编解码'
    },
    {
      name: '[Rhino沙箱] 完整书源模拟',
      code: '// 模拟书源搜索规则\nvar searchUrl = baseUrl + "/search?q=" + encodeURIComponent(key) + "&page=" + page;\njava.log("搜索URL: " + searchUrl);\n\n// 模拟HTML响应\nvar mockHtml = \'<div class="book-list"><div class="book-item"><a href="/book/1">书名1</a><span class="author">作者1</span></div></div>\';\n\n// 使用Jsoup解析\nvar doc = Jsoup.parse(mockHtml);\nvar items = doc.select(".book-item");\nvar result = [];\nfor (var i = 0; i < items.size(); i++) {\n  var item = items.get(i);\n  result.push({\n    name: item.select("a").text(),\n    author: item.select(".author").text(),\n    url: item.select("a").attr("href")\n  });\n}\nJSON.stringify(result, null, 2);',
      description: '模拟完整的书源搜索解析流程'
    },
    {
      name: '[WebView] 晴天书源登录测试',
      code: `// 晴天书源登录测试 - 简化版
// 模拟jsLib中的getArguments函数
var host = ['https://v1.gyks.cf'];
function getArguments(open_argument, key) {
  try {
    open_argument = SafeUtils.parseObj(open_argument);
  } catch (e) {
    open_argument = { server: host[0] };
  }
  return key ? open_argument[key] : open_argument;
}
function getArgument(key) {
  return getArguments(source.getVariable(), key);
}
function setArgument(key, value) {
  var open_argument = getArguments(source.getVariable(), '');
  open_argument[key] = value;
  source.setVariable(JSON.stringify(open_argument));
  return open_argument;
}
function getKey(cookieStr) {
  if (!cookieStr) return '';
  var match = cookieStr.match(/qttoken=([^;]+)/);
  return match ? match[1] : '';
}

// 简化的login函数
function login(flag) {
  java.longToast("正在登录中...");
  var base_url = getArgument('server') || host[0];
  java.log("服务器: " + base_url);
  
  // 测试网络请求
  try {
    var testUrl = base_url + "/get_avatar";
    java.log("测试URL: " + testUrl);
    var response = java.ajax(testUrl);
    java.log("响应: " + response);
    return "登录测试完成，响应: " + response.substring(0, 100);
  } catch(e) {
    return "登录测试失败: " + e.message;
  }
}

// 执行登录
login(true);`,
      description: '测试晴天书源的登录功能（简化版）'
    },
    {
      name: '[WebView] 简单网络请求测试',
      code: `// 简单网络请求测试 - 获取必应首页
java.log("开始测试网络请求...");
java.toast("测试中...");

var result = "";
try {
  var url = "https://www.bing.com";
  java.log("请求URL: " + url);
  var response = java.ajax(url);
  java.log("响应长度: " + (response ? response.length : 0));
  
  // 提取页面标题
  var titleMatch = response.match(/<title>([^<]+)<\\/title>/i);
  var title = titleMatch ? titleMatch[1] : "未找到标题";
  
  result = "请求成功!\\n页面标题: " + title + "\\n响应长度: " + response.length + " 字符";
} catch(e) {
  result = "请求失败: " + e.message;
}
result`,
      description: '测试WebView中的java.ajax网络请求（获取必应首页）'
    }
  ];

  aboutToAppear(): void {
    ThemeAwareHelper.initializeThemeAware(this.componentId, this.themeState, (theme: ThemeType) => {
      logger.info(TAG, `主题切换: ${theme}`);
    });
    this.checkEngineStatus();
  }

  aboutToDisappear(): void {
    logger.lifecycle(TAG, 'aboutToDisappear - 开始清理资源');
    
    // 使用生命周期管理器自动清理所有资源
    this.lifecycle.destroy();
    
    // 清理主题
    ThemeAwareHelper.cleanupThemeAware(this.componentId);
    
    logger.lifecycle(TAG, 'aboutToDisappear - 资源清理完成');
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
      this.getUIContext().getPromptAction().showToast({ message: '请输入代码' });
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
   * 初始化QuickJS引擎
   */
  private initQuickJS(): void {
    try {
      const result: boolean = quickjs.init();
      if (result) {
        this.quickjsInitialized = true;
        this.quickjsStatus = '已就绪';
        // 设置书源信息
        quickjs.setSourceInfo('https://test.example.com', 'TestSource', '');
        logger.info(TAG, 'QuickJS引擎初始化成功');
        this.getUIContext().getPromptAction().showToast({ message: 'QuickJS引擎初始化成功' });
        
        // 注册清理逻辑到生命周期管理器
        class QuickjsDisposable implements Disposable {
          private initialized: boolean;
          
          constructor(initialized: boolean) {
            this.initialized = initialized;
          }
          
          dispose(): void {
            if (this.initialized) {
              try {
                quickjs.destroy?.();
                logger.info(TAG, 'QuickJS引擎已销毁');
              } catch (e) {
                logger.error(TAG, `QuickJS销毁失败: ${e}`);
              }
            }
          }
        }
        this.lifecycle.registerResource(new QuickjsDisposable(this.quickjsInitialized));
      } else {
        this.quickjsStatus = '初始化失败';
        this.getUIContext().getPromptAction().showToast({ message: 'QuickJS引擎初始化失败' });
      }
    } catch (e) {
      this.quickjsStatus = `错误: ${String(e)}`;
      logger.error(TAG, `QuickJS初始化异常: ${String(e)}`);
      this.getUIContext().getPromptAction().showToast({ message: `QuickJS初始化异常: ${String(e)}` });
    }
  }

  /**
   * 使用QuickJS执行代码
   */
  private async executeWithQuickJS(): Promise<void> {
    if (this.isExecuting) {
      return;
    }
    
    if (!this.codeInput.trim()) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入代码' });
      return;
    }
    
    // 确保QuickJS已初始化
    if (!this.quickjsInitialized) {
      this.initQuickJS();
      if (!this.quickjsInitialized) {
        return;
      }
    }
    
    this.isExecuting = true;
    this.outputText = '[QuickJS] 执行中...';
    const startTime = Date.now();
    
    try {
      // 执行代码（包装为可取消的 Promise）
      const result: QuickJSResult = await this.lifecycle.registerPromise(
        Promise.resolve(quickjs.execute(this.codeInput, this.contextKey, this.contextPage, this.contextResult, this.contextBaseUrl) as QuickJSResult)
      );
      const endTime = Date.now();
      this.executionTime = endTime - startTime;
      
      if (result.success) {
        logger.debug(TAG, `[QuickJS] JS执行成功: ${result.result.substring(0, 100)}`);
        this.outputText = `[QuickJS] ${result.result}`;
      } else {
        logger.warn(TAG, `[QuickJS] JS执行失败: ${result.error || '未知错误'}`);
        this.outputText = `[QuickJS] 错误: ${result.error || '未知错误'}`;
      }
      
      // 添加到历史记录
      this.addToHistory(`[QuickJS] ${this.codeInput}`, this.outputText, result.success, this.executionTime);
      
    } catch (e) {
      const endTime = Date.now();
      this.executionTime = endTime - startTime;
      logger.error(TAG, `[QuickJS] JS执行异常: ${String(e)}`);
      this.outputText = `[QuickJS] 执行异常: ${String(e)}`;
      this.addToHistory(`[QuickJS] ${this.codeInput}`, this.outputText, false, this.executionTime);
    }
    
    this.isExecuting = false;
  }

  /**
   * 测试QuickJS引擎
   */
  private testQuickJSEngine(): void {
    logger.info(TAG, '[QuickJS] 开始引擎测试');
    const startTime = Date.now();
    let results: string[] = [];
    
    try {
      // 1. 初始化测试
      results.push('=== QuickJS引擎测试 ===\n');
      
      if (!this.quickjsInitialized) {
        this.initQuickJS();
      }
      
      if (!this.quickjsInitialized) {
        results.push('❌ 引擎初始化失败');
        this.outputText = results.join('\n');
        return;
      }
      results.push('✅ 引擎初始化成功');
      
      // 2. 版本信息
      const version: string = quickjs.getVersion() as string;
      results.push(`✅ 版本: ${version}`);
      
      // 3. 基础运算测试
      const basicResult: QuickJSResult = quickjs.execute('1 + 2 * 3', '', 1, '', '') as QuickJSResult;
      if (basicResult.success && basicResult.result === '7') {
        results.push('✅ 基础运算: 1 + 2 * 3 = 7');
      } else {
        results.push(`❌ 基础运算失败: ${basicResult.result || basicResult.error}`);
      }
      
      // 4. 字符串测试
      const strResult: QuickJSResult = quickjs.execute('"Hello".toUpperCase()', '', 1, '', '') as QuickJSResult;
      if (strResult.success && strResult.result === 'HELLO') {
        results.push('✅ 字符串操作: "Hello".toUpperCase() = HELLO');
      } else {
        results.push(`❌ 字符串操作失败: ${strResult.result || strResult.error}`);
      }
      
      // 5. JSON测试
      const jsonResult: QuickJSResult = quickjs.execute('JSON.stringify({a:1,b:2})', '', 1, '', '') as QuickJSResult;
      if (jsonResult.success) {
        results.push(`✅ JSON序列化: ${jsonResult.result}`);
      } else {
        results.push(`❌ JSON序列化失败: ${jsonResult.error}`);
      }
      
      // 6. 上下文变量测试
      const ctxResult: QuickJSResult = quickjs.execute('key + " - 页码:" + page', '测试关键字', 5, '', 'https://test.com') as QuickJSResult;
      if (ctxResult.success) {
        results.push(`✅ 上下文变量: ${ctxResult.result}`);
      } else {
        results.push(`❌ 上下文变量失败: ${ctxResult.error}`);
      }
      
      // 7. java对象测试
      const javaResult: QuickJSResult = quickjs.execute('typeof java', '', 1, '', '') as QuickJSResult;
      if (javaResult.success && javaResult.result === 'object') {
        results.push('✅ java对象存在');
      } else {
        results.push(`⚠️ java对象: ${javaResult.result || javaResult.error}`);
      }
      
      // 8. source对象测试
      const sourceResult: QuickJSResult = quickjs.execute('typeof source', '', 1, '', '') as QuickJSResult;
      if (sourceResult.success && sourceResult.result === 'object') {
        results.push('✅ source对象存在');
      } else {
        results.push(`⚠️ source对象: ${sourceResult.result || sourceResult.error}`);
      }
      
      const endTime = Date.now();
      results.push(`\n总耗时: ${endTime - startTime}ms`);
      
      logger.info(TAG, `[QuickJS] 引擎测试完成, 耗时: ${endTime - startTime}ms`);
      this.outputText = results.join('\n');
      this.executionTime = endTime - startTime;
      this.addToHistory('// QuickJS Engine Test', this.outputText, true, this.executionTime);
      this.selectedTab = 1;
      
    } catch (e) {
      const endTime = Date.now();
      logger.error(TAG, `[QuickJS] 引擎测试异常: ${String(e)}`);
      results.push(`\n❌ 测试异常: ${String(e)}`);
      this.outputText = results.join('\n');
      this.executionTime = endTime - startTime;
      this.addToHistory('// QuickJS Engine Test', this.outputText, false, this.executionTime);
      this.selectedTab = 1;
    }
  }

  /**
   * 初始化Rhino沙箱引擎
   */
  private async initRhinoSandbox(): Promise<void> {
    logger.info(TAG, '[RhinoSandbox] 开始初始化Rhino沙箱引擎...');
    try {
      this.rhinoSandboxStatus = '初始化中...';
      this.rhinoEngine = getLegadoRhinoEngine();
      
      // 配置引擎（优先使用离线模式）
      this.rhinoEngine.setConfig({
        preferredEngine: JsEngineType.RHINO_OFFLINE,
        enableRhinoSandbox: true,
        executeTimeout: 30000
      });
      
      // 初始化
      const success = await this.rhinoEngine.initialize();
      
      if (success) {
        const status = this.rhinoEngine.getStatus();
        this.rhinoSandboxStatus = '已就绪';
        this.rhinoSandboxMode = status.rhinoSandboxMode || 'offline';
        logger.info(TAG, `[RhinoSandbox] 初始化成功, 模式: ${this.rhinoSandboxMode}`);
        this.getUIContext().getPromptAction().showToast({ message: `Rhino沙箱初始化成功 (${this.rhinoSandboxMode}模式)` });
        
        // 注册清理逻辑到生命周期管理器
        class RhinoDisposable implements Disposable {
          private engine: LegadoRhinoEngine | null;
          
          constructor(engine: LegadoRhinoEngine | null) {
            this.engine = engine;
          }
          
          async dispose(): Promise<void> {
            if (this.engine) {
              try {
                await this.engine.destroy?.();
                logger.info(TAG, 'Rhino引擎已销毁');
              } catch (e) {
                logger.error(TAG, `Rhino销毁失败: ${e}`);
              }
            }
          }
        }
        this.lifecycle.registerResource(new RhinoDisposable(this.rhinoEngine));
      } else {
        this.rhinoSandboxStatus = '初始化失败';
        logger.error(TAG, '[RhinoSandbox] 初始化失败');
        this.getUIContext().getPromptAction().showToast({ message: 'Rhino沙箱初始化失败' });
      }
    } catch (e) {
      this.rhinoSandboxStatus = `错误: ${String(e)}`;
      logger.error(TAG, `[RhinoSandbox] 初始化异常: ${String(e)}`);
      this.getUIContext().getPromptAction().showToast({ message: `Rhino沙箱初始化异常: ${String(e)}` });
    }
  }

  /**
   * 使用Rhino沙箱执行代码
   */
  private async executeWithRhinoSandbox(): Promise<void> {
    if (this.isExecuting) {
      return;
    }
    
    if (!this.codeInput.trim()) {
      this.getUIContext().getPromptAction().showToast({ message: '请输入代码' });
      return;
    }
    
    // 确保Rhino沙箱已初始化
    if (!this.rhinoEngine || this.rhinoSandboxStatus !== '已就绪') {
      await this.initRhinoSandbox();
      if (this.rhinoSandboxStatus !== '已就绪') {
        return;
      }
    }
    
    this.isExecuting = true;
    this.outputText = '[RhinoSandbox] 执行中...';
    const startTime = Date.now();
    
    logger.info(TAG, `[RhinoSandbox] 开始执行代码, 长度: ${this.codeInput.length}`);
    logger.debug(TAG, `[RhinoSandbox] 代码内容: ${this.codeInput.substring(0, 200)}...`);
    
    try {
      const result = await this.rhinoEngine!.execute(this.codeInput, {
        result: this.contextResult,
        baseUrl: this.contextBaseUrl,
        key: this.contextKey,
        page: this.contextPage
      });
      
      const endTime = Date.now();
      this.executionTime = endTime - startTime;
      
      if (result.success) {
        logger.info(TAG, `[RhinoSandbox] 执行成功, 耗时: ${this.executionTime}ms`);
        logger.debug(TAG, `[RhinoSandbox] 结果: ${String(result.result).substring(0, 200)}`);
        this.outputText = `[RhinoSandbox] ${result.result}`;
      } else {
        logger.warn(TAG, `[RhinoSandbox] 执行失败: ${result.error}`);
        this.outputText = `[RhinoSandbox] 错误: ${result.error || '未知错误'}`;
      }
      
      this.addToHistory(`[RhinoSandbox] ${this.codeInput}`, this.outputText, result.success, this.executionTime);
      
    } catch (e) {
      const endTime = Date.now();
      this.executionTime = endTime - startTime;
      logger.error(TAG, `[RhinoSandbox] 执行异常: ${String(e)}`);
      this.outputText = `[RhinoSandbox] 执行异常: ${String(e)}`;
      this.addToHistory(`[RhinoSandbox] ${this.codeInput}`, this.outputText, false, this.executionTime);
    }
    
    this.isExecuting = false;
  }

  /**
   * 全面测试Rhino沙箱引擎
   */
  private async testRhinoSandboxEngine(): Promise<void> {
    logger.info(TAG, '[RhinoSandbox] ========== 开始全面引擎测试 ==========');
    const startTime = Date.now();
    let results: string[] = [];
    let passCount = 0;
    let failCount = 0;
    
    try {
      results.push('=== Rhino WASM沙箱引擎测试 ===\n');
      
      // 1. 初始化测试
      logger.info(TAG, '[RhinoSandbox] 测试1: 引擎初始化');
      if (!this.rhinoEngine || this.rhinoSandboxStatus !== '已就绪') {
        await this.initRhinoSandbox();
      }
      
      if (this.rhinoSandboxStatus !== '已就绪') {
        results.push('❌ 引擎初始化失败');
        failCount++;
        logger.error(TAG, '[RhinoSandbox] 测试1失败: 引擎初始化失败');
        this.outputText = results.join('\n');
        return;
      }
      results.push(`✅ 引擎初始化成功 (模式: ${this.rhinoSandboxMode})`);
      passCount++;
      logger.info(TAG, `[RhinoSandbox] 测试1通过: 引擎初始化成功, 模式=${this.rhinoSandboxMode}`);
      
      // 2. 基础运算测试
      logger.info(TAG, '[RhinoSandbox] 测试2: 基础运算');
      const basicResult = await this.rhinoEngine!.execute('1 + 2 * 3', {});
      if (basicResult.success && basicResult.result === '7') {
        results.push('✅ 基础运算: 1 + 2 * 3 = 7');
        passCount++;
        logger.info(TAG, '[RhinoSandbox] 测试2通过: 基础运算正确');
      } else {
        results.push(`❌ 基础运算失败: ${basicResult.result || basicResult.error}`);
        failCount++;
        logger.error(TAG, `[RhinoSandbox] 测试2失败: 期望7, 得到${basicResult.result}`);
      }
      
      // 3. 字符串测试
      logger.info(TAG, '[RhinoSandbox] 测试3: 字符串操作');
      const strResult = await this.rhinoEngine!.execute('"Hello".toUpperCase()', {});
      if (strResult.success && strResult.result === 'HELLO') {
        results.push('✅ 字符串操作: "Hello".toUpperCase() = HELLO');
        passCount++;
        logger.info(TAG, '[RhinoSandbox] 测试3通过: 字符串操作正确');
      } else {
        results.push(`❌ 字符串操作失败: ${strResult.result || strResult.error}`);
        failCount++;
        logger.error(TAG, `[RhinoSandbox] 测试3失败: 期望HELLO, 得到${strResult.result}`);
      }
      
      // 4. JSON测试
      logger.info(TAG, '[RhinoSandbox] 测试4: JSON序列化');
      const jsonResult = await this.rhinoEngine!.execute('JSON.stringify({a:1,b:2})', {});
      if (jsonResult.success) {
        results.push(`✅ JSON序列化: ${jsonResult.result}`);
        passCount++;
        logger.info(TAG, `[RhinoSandbox] 测试4通过: JSON序列化=${jsonResult.result}`);
      } else {
        results.push(`❌ JSON序列化失败: ${jsonResult.error}`);
        failCount++;
        logger.error(TAG, `[RhinoSandbox] 测试4失败: ${jsonResult.error}`);
      }
      
      // 5. 上下文变量测试
      logger.info(TAG, '[RhinoSandbox] 测试5: 上下文变量');
      const ctxResult = await this.rhinoEngine!.execute('key + " - 页码:" + page', {
        key: '测试关键字',
        page: 5,
        baseUrl: 'https://test.com'
      });
      if (ctxResult.success) {
        results.push(`✅ 上下文变量: ${ctxResult.result}`);
        passCount++;
        logger.info(TAG, `[RhinoSandbox] 测试5通过: 上下文变量=${ctxResult.result}`);
      } else {
        results.push(`❌ 上下文变量失败: ${ctxResult.error}`);
        failCount++;
        logger.error(TAG, `[RhinoSandbox] 测试5失败: ${ctxResult.error}`);
      }
      
      // 6. java对象测试
      logger.info(TAG, '[RhinoSandbox] 测试6: java对象');
      const javaResult = await this.rhinoEngine!.execute('typeof java', {});
      if (javaResult.success && javaResult.result === 'object') {
        results.push('✅ java对象存在');
        passCount++;
        logger.info(TAG, '[RhinoSandbox] 测试6通过: java对象存在');
      } else {
        results.push(`⚠️ java对象: ${javaResult.result || javaResult.error}`);
        failCount++;
        logger.warn(TAG, `[RhinoSandbox] 测试6警告: java对象类型=${javaResult.result}`);
      }
      
      // 7. source对象测试
      logger.info(TAG, '[RhinoSandbox] 测试7: source对象');
      const sourceResult = await this.rhinoEngine!.execute('typeof source', {});
      if (sourceResult.success && sourceResult.result === 'object') {
        results.push('✅ source对象存在');
        passCount++;
        logger.info(TAG, '[RhinoSandbox] 测试7通过: source对象存在');
      } else {
        results.push(`⚠️ source对象: ${sourceResult.result || sourceResult.error}`);
        failCount++;
        logger.warn(TAG, `[RhinoSandbox] 测试7警告: source对象类型=${sourceResult.result}`);
      }
      
      // 8. Base64编解码测试
      logger.info(TAG, '[RhinoSandbox] 测试8: Base64编解码');
      const b64Result = await this.rhinoEngine!.execute(
        'var encoded = java.base64Encode("Hello"); var decoded = java.base64Decode(encoded); decoded === "Hello" ? "OK" : "FAIL"',
        {}
      );
      if (b64Result.success && b64Result.result === 'OK') {
        results.push('✅ Base64编解码正确');
        passCount++;
        logger.info(TAG, '[RhinoSandbox] 测试8通过: Base64编解码正确');
      } else {
        results.push(`❌ Base64编解码失败: ${b64Result.result || b64Result.error}`);
        failCount++;
        logger.error(TAG, `[RhinoSandbox] 测试8失败: ${b64Result.result}`);
      }
      
      // 9. Jsoup解析测试
      logger.info(TAG, '[RhinoSandbox] 测试9: Jsoup DOM解析');
      const jsoupResult = await this.rhinoEngine!.execute(
        'var doc = Jsoup.parse("<div><h1>Title</h1></div>"); doc.select("h1").text();',
        {}
      );
      if (jsoupResult.success && jsoupResult.result === 'Title') {
        results.push('✅ Jsoup DOM解析正确');
        passCount++;
        logger.info(TAG, '[RhinoSandbox] 测试9通过: Jsoup解析正确');
      } else {
        results.push(`❌ Jsoup解析失败: ${jsoupResult.result || jsoupResult.error}`);
        failCount++;
        logger.error(TAG, `[RhinoSandbox] 测试9失败: ${jsoupResult.result}`);
      }
      
      // 10. cookie对象测试
      logger.info(TAG, '[RhinoSandbox] 测试10: cookie对象');
      const cookieResult = await this.rhinoEngine!.execute('typeof cookie', {});
      if (cookieResult.success && cookieResult.result === 'object') {
        results.push('✅ cookie对象存在');
        passCount++;
        logger.info(TAG, '[RhinoSandbox] 测试10通过: cookie对象存在');
      } else {
        results.push(`⚠️ cookie对象: ${cookieResult.result || cookieResult.error}`);
        failCount++;
        logger.warn(TAG, `[RhinoSandbox] 测试10警告: cookie对象类型=${cookieResult.result}`);
      }
      
      // 11. cache对象测试
      logger.info(TAG, '[RhinoSandbox] 测试11: cache对象');
      const cacheResult = await this.rhinoEngine!.execute('typeof cache', {});
      if (cacheResult.success && cacheResult.result === 'object') {
        results.push('✅ cache对象存在');
        passCount++;
        logger.info(TAG, '[RhinoSandbox] 测试11通过: cache对象存在');
      } else {
        results.push(`⚠️ cache对象: ${cacheResult.result || cacheResult.error}`);
        failCount++;
        logger.warn(TAG, `[RhinoSandbox] 测试11警告: cache对象类型=${cacheResult.result}`);
      }
      
      // 12. 时间格式化测试
      logger.info(TAG, '[RhinoSandbox] 测试12: 时间格式化');
      const timeResult = await this.rhinoEngine!.execute('java.timeFormat(Date.now())', {});
      if (timeResult.success && timeResult.result && timeResult.result.length > 0) {
        results.push(`✅ 时间格式化: ${timeResult.result}`);
        passCount++;
        logger.info(TAG, `[RhinoSandbox] 测试12通过: 时间格式化=${timeResult.result}`);
      } else {
        results.push(`❌ 时间格式化失败: ${timeResult.error}`);
        failCount++;
        logger.error(TAG, `[RhinoSandbox] 测试12失败: ${timeResult.error}`);
      }
      
      const endTime = Date.now();
      const totalTime = endTime - startTime;
      
      results.push(`\n========== 测试完成 ==========`);
      results.push(`通过: ${passCount}, 失败: ${failCount}`);
      results.push(`总耗时: ${totalTime}ms`);
      
      logger.info(TAG, `[RhinoSandbox] ========== 测试完成 ==========`);
      logger.info(TAG, `[RhinoSandbox] 通过: ${passCount}, 失败: ${failCount}, 耗时: ${totalTime}ms`);
      
      this.outputText = results.join('\n');
      this.executionTime = totalTime;
      this.addToHistory('// Rhino Sandbox Engine Test', this.outputText, failCount === 0, this.executionTime);
      this.selectedTab = 1;
      
    } catch (e) {
      const endTime = Date.now();
      logger.error(TAG, `[RhinoSandbox] 测试异常: ${String(e)}`);
      results.push(`\n❌ 测试异常: ${String(e)}`);
      this.outputText = results.join('\n');
      this.executionTime = endTime - startTime;
      this.addToHistory('// Rhino Sandbox Engine Test', this.outputText, false, this.executionTime);
      this.selectedTab = 1;
    }
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
   * 测试Jsoup DOM解析功能
   */
  private async testJsoupParsing(): Promise<void> {
    logger.info(TAG, '[Jsoup] ========== 开始Jsoup DOM解析测试 ==========');
    const startTime = Date.now();
    let results: string[] = [];
    let passCount = 0;
    let failCount = 0;
    
    try {
      results.push('=== Jsoup DOM解析测试 ===\n');
      
      // 确保Rhino沙箱已初始化
      if (!this.rhinoEngine || this.rhinoSandboxStatus !== '已就绪') {
        await this.initRhinoSandbox();
      }
      
      if (this.rhinoSandboxStatus !== '已就绪') {
        results.push('❌ Rhino沙箱初始化失败，无法测试Jsoup');
        failCount++;
        this.outputText = results.join('\n');
        this.selectedTab = 1;
        return;
      }
      results.push('✅ Rhino沙箱已就绪');
      passCount++;
      
      // 1. 基础解析测试
      logger.info(TAG, '[Jsoup] 测试1: 基础HTML解析');
      const basicResult = await this.rhinoEngine!.execute(
        'var doc = Jsoup.parse("<html><head><title>Test</title></head><body><p>Hello</p></body></html>"); doc.title();',
        {}
      );
      if (basicResult.success && basicResult.result === 'Test') {
        results.push('✅ 基础解析: doc.title() = Test');
        passCount++;
        logger.info(TAG, '[Jsoup] 测试1通过');
      } else {
        results.push(`❌ 基础解析失败: ${basicResult.result || basicResult.error}`);
        failCount++;
        logger.error(TAG, `[Jsoup] 测试1失败: ${basicResult.result}`);
      }
      
      // 2. CSS选择器测试
      logger.info(TAG, '[Jsoup] 测试2: CSS选择器');
      const selectResult = await this.rhinoEngine!.execute(
        'var doc = Jsoup.parse("<div class=\\"item\\"><span>Text1</span></div><div class=\\"item\\"><span>Text2</span></div>"); doc.select(".item span").size();',
        {}
      );
      if (selectResult.success && selectResult.result === '2') {
        results.push('✅ CSS选择器: .item span 匹配2个元素');
        passCount++;
        logger.info(TAG, '[Jsoup] 测试2通过');
      } else {
        results.push(`❌ CSS选择器失败: ${selectResult.result || selectResult.error}`);
        failCount++;
        logger.error(TAG, `[Jsoup] 测试2失败: ${selectResult.result}`);
      }
      
      // 3. 获取文本测试
      logger.info(TAG, '[Jsoup] 测试3: 获取文本');
      const textResult = await this.rhinoEngine!.execute(
        'var doc = Jsoup.parse("<h1>标题内容</h1>"); doc.select("h1").text();',
        {}
      );
      if (textResult.success && textResult.result === '标题内容') {
        results.push('✅ 获取文本: h1.text() = 标题内容');
        passCount++;
        logger.info(TAG, '[Jsoup] 测试3通过');
      } else {
        results.push(`❌ 获取文本失败: ${textResult.result || textResult.error}`);
        failCount++;
        logger.error(TAG, `[Jsoup] 测试3失败: ${textResult.result}`);
      }
      
      // 4. 获取属性测试
      logger.info(TAG, '[Jsoup] 测试4: 获取属性');
      const attrResult = await this.rhinoEngine!.execute(
        'var doc = Jsoup.parse("<a href=\\"https://example.com\\" title=\\"链接\\">Link</a>"); doc.select("a").attr("href");',
        {}
      );
      if (attrResult.success && attrResult.result === 'https://example.com') {
        results.push('✅ 获取属性: a.attr("href") = https://example.com');
        passCount++;
        logger.info(TAG, '[Jsoup] 测试4通过');
      } else {
        results.push(`❌ 获取属性失败: ${attrResult.result || attrResult.error}`);
        failCount++;
        logger.error(TAG, `[Jsoup] 测试4失败: ${attrResult.result}`);
      }
      
      // 5. 遍历元素测试
      logger.info(TAG, '[Jsoup] 测试5: 遍历元素');
      const iterResult = await this.rhinoEngine!.execute(
        'var doc = Jsoup.parse("<ul><li>A</li><li>B</li><li>C</li></ul>"); var items = doc.select("li"); var texts = []; for(var i=0; i<items.size(); i++) { texts.push(items.get(i).text()); } texts.join(",");',
        {}
      );
      if (iterResult.success && iterResult.result === 'A,B,C') {
        results.push('✅ 遍历元素: li texts = A,B,C');
        passCount++;
        logger.info(TAG, '[Jsoup] 测试5通过');
      } else {
        results.push(`❌ 遍历元素失败: ${iterResult.result || iterResult.error}`);
        failCount++;
        logger.error(TAG, `[Jsoup] 测试5失败: ${iterResult.result}`);
      }
      
      // 6. 嵌套选择测试
      logger.info(TAG, '[Jsoup] 测试6: 嵌套选择');
      const nestedResult = await this.rhinoEngine!.execute(
        'var doc = Jsoup.parse("<div class=\\"book\\"><h2 class=\\"name\\">书名</h2><span class=\\"author\\">作者</span></div>"); var book = doc.selectFirst(".book"); book.select(".name").text() + " - " + book.select(".author").text();',
        {}
      );
      if (nestedResult.success && nestedResult.result === '书名 - 作者') {
        results.push('✅ 嵌套选择: 书名 - 作者');
        passCount++;
        logger.info(TAG, '[Jsoup] 测试6通过');
      } else {
        results.push(`❌ 嵌套选择失败: ${nestedResult.result || nestedResult.error}`);
        failCount++;
        logger.error(TAG, `[Jsoup] 测试6失败: ${nestedResult.result}`);
      }
      
      // 7. 批量获取属性测试
      logger.info(TAG, '[Jsoup] 测试7: 批量获取属性');
      const batchAttrResult = await this.rhinoEngine!.execute(
        'var doc = Jsoup.parse("<img src=\\"1.jpg\\"/><img src=\\"2.jpg\\"/><img src=\\"3.jpg\\"/>"); doc.select("img").eachAttr("src").join(",");',
        {}
      );
      if (batchAttrResult.success && batchAttrResult.result === '1.jpg,2.jpg,3.jpg') {
        results.push('✅ 批量获取属性: img.src = 1.jpg,2.jpg,3.jpg');
        passCount++;
        logger.info(TAG, '[Jsoup] 测试7通过');
      } else {
        results.push(`❌ 批量获取属性失败: ${batchAttrResult.result || batchAttrResult.error}`);
        failCount++;
        logger.error(TAG, `[Jsoup] 测试7失败: ${batchAttrResult.result}`);
      }
      
      // 8. 模拟书源解析测试
      logger.info(TAG, '[Jsoup] 测试8: 模拟书源解析');
      const bookSourceResult = await this.rhinoEngine!.execute(`
        var html = '<div class="search-result"><div class="book-item"><a href="/book/1" class="book-link"><h3 class="title">斗破苍穹</h3></a><p class="author">天蚕土豆</p><p class="intro">这是简介...</p></div></div>';
        var doc = Jsoup.parse(html);
        var item = doc.selectFirst(".book-item");
        var result = {
          name: item.select(".title").text(),
          author: item.select(".author").text(),
          url: item.select(".book-link").attr("href"),
          intro: item.select(".intro").text()
        };
        JSON.stringify(result);
      `, {});
      if (bookSourceResult.success) {
        try {
          const parsed = SafeUtils.parseObj(bookSourceResult.result) as Record<string, string>;
          if (parsed['name'] === '斗破苍穹' && parsed['author'] === '天蚕土豆') {
            results.push('✅ 书源解析: 斗破苍穹 - 天蚕土豆');
            passCount++;
            logger.info(TAG, '[Jsoup] 测试8通过');
          } else {
            results.push(`❌ 书源解析数据不匹配: ${bookSourceResult.result}`);
            failCount++;
          }
        } catch (e) {
          results.push(`❌ 书源解析JSON解析失败: ${bookSourceResult.result}`);
          failCount++;
        }
      } else {
        results.push(`❌ 书源解析失败: ${bookSourceResult.error}`);
        failCount++;
        logger.error(TAG, `[Jsoup] 测试8失败: ${bookSourceResult.error}`);
      }
      
      const endTime = Date.now();
      const totalTime = endTime - startTime;
      
      results.push(`\n========== 测试完成 ==========`);
      results.push(`通过: ${passCount}, 失败: ${failCount}`);
      results.push(`总耗时: ${totalTime}ms`);
      
      logger.info(TAG, `[Jsoup] ========== 测试完成 ==========`);
      logger.info(TAG, `[Jsoup] 通过: ${passCount}, 失败: ${failCount}, 耗时: ${totalTime}ms`);
      
      this.outputText = results.join('\n');
      this.executionTime = totalTime;
      this.addToHistory('// Jsoup DOM Parsing Test', this.outputText, failCount === 0, this.executionTime);
      this.selectedTab = 1;
      
    } catch (e) {
      const endTime = Date.now();
      logger.error(TAG, `[Jsoup] 测试异常: ${String(e)}`);
      results.push(`\n❌ 测试异常: ${String(e)}`);
      this.outputText = results.join('\n');
      this.executionTime = endTime - startTime;
      this.addToHistory('// Jsoup DOM Parsing Test', this.outputText, false, this.executionTime);
      this.selectedTab = 1;
    }
  }

  /**
   * 加载示例代码
   */
  private loadExample(example: CodeExample): void {
    this.codeInput = example.code;
    this.showExamples = false;
    this.getUIContext().getPromptAction().showToast({ message: `已加载: ${example.name}` });
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

  /**
   * 复制内容到剪贴板
   */
  private async copyToClipboard(text: string): Promise<void> {
    try {
      const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
      const systemPasteboard = pasteboard.getSystemPasteboard();
      await systemPasteboard.setData(pasteData);
      this.getUIContext().getPromptAction().showToast({ message: '已复制到剪贴板' });
    } catch (error) {
      logger.error(TAG, `复制失败: ${String(error)}`);
      this.getUIContext().getPromptAction().showToast({ message: '复制失败' });
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
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        
        // 隐藏的WebView用于LegadoJsEngine执行网络请求
        Web({ src: $rawfile('js_executor.html'), controller: this.webViewController })
          .width(1)
          .height(1)
          .opacity(0)
          .position({ x: -100, y: -100 })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(true)
          .mixedMode(MixedMode.All)
          .onControllerAttached(() => {
            const jsEngine = getLegadoJsEngine();
            jsEngine.setWebviewController(this.webViewController);
            this.webViewStatus = '已就绪';
            logger.info(TAG, 'WebView控制器已设置到LegadoJsEngine');
          })
        
        Column() {
          // 标题栏占位
          Blank().height(SettingsPageTitleBarManager.getContentTopPadding(this.statusBarHeight))
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
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
            .layoutWeight(1)
            .width('100%')
          }
          .layoutWeight(1)
          .width('100%')
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
          
          // 底部操作栏
          this.buildBottomBar()
        }
        .width('100%')
        .height('100%')
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

        SettingsImmersiveTitleBar({
          themeState: this.themeState,
          title: 'JSVM Playground',
          appFontFamily: this.appFontFamily
        })
      }
      .width('100%')
      .height('100%')
    }
    .hideTitleBar(true)
    .ignoreLayoutSafeArea([LayoutSafeAreaType.SYSTEM], [LayoutSafeAreaEdge.TOP, LayoutSafeAreaEdge.BOTTOM])
    .backgroundColor(Color.Transparent)
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
    
    this.getUIContext().getPromptAction().showDialog({
      title: 'JSVM 引擎信息',
      message: message,
      buttons: [{ text: '确定', color: '#007AFF' }]
    });
  }

  @Builder
  buildToolbar() {
    Column() {
      // 第一行：基础操作
      Row() {
        // 示例按钮
        Button('示例')
          .type(ButtonType.Normal)
          .height(28)
          .fontSize(12)
          .fontColor(this.themeState.isDarkTheme() ? '#ffffff' : '#333333')
          .backgroundColor(this.showExamples ? '#007AFF' : (this.themeState.isDarkTheme() ? '#333333' : '#e0e0e0'))
          .borderRadius(6)
          .animation({ duration: 140 })
          .onClick(() => {
            this.showExamples = !this.showExamples;
            this.showContext = false;
          })
        
        // 上下文按钮
        Button('上下文')
          .type(ButtonType.Normal)
          .height(28)
          .fontSize(12)
          .fontColor(this.themeState.isDarkTheme() ? '#ffffff' : '#333333')
          .backgroundColor(this.showContext ? '#007AFF' : (this.themeState.isDarkTheme() ? '#333333' : '#e0e0e0'))
          .borderRadius(6)
          .margin({ left: 6 })
          .animation({ duration: 140 })
          .onClick(() => {
            this.showContext = !this.showContext;
            this.showExamples = false;
            this.showSettings = false;
          })
        
        // 设置按钮
        Button('设置')
          .type(ButtonType.Normal)
          .height(28)
          .fontSize(12)
          .fontColor(this.themeState.isDarkTheme() ? '#ffffff' : '#333333')
          .backgroundColor(this.showSettings ? '#007AFF' : (this.themeState.isDarkTheme() ? '#333333' : '#e0e0e0'))
          .borderRadius(6)
          .margin({ left: 6 })
          .animation({ duration: 140 })
          .onClick(() => {
            this.showSettings = !this.showSettings;
            this.showExamples = false;
            this.showContext = false;
          })
        
        Blank()
        
        // 引擎状态指示器
        Row() {
          // JSVM状态
          Circle()
            .width(6)
            .height(6)
            .fill(this.engineStatus === '已就绪' ? '#4CAF50' : '#FF9800')
          Text('VM')
            .fontSize(10)
            .fontColor(this.themeState.isDarkTheme() ? '#888888' : '#666666')
            .margin({ left: 2 })
          
          // Rhino沙箱状态
          Circle()
            .width(6)
            .height(6)
            .fill(this.rhinoSandboxStatus === '已就绪' ? '#4CAF50' : '#FF9800')
            .margin({ left: 8 })
          Text('R')
            .fontSize(10)
            .fontColor(this.themeState.isDarkTheme() ? '#888888' : '#666666')
            .margin({ left: 2 })
          
          // WebView状态
          Circle()
            .width(6)
            .height(6)
            .fill(this.enableWebView ? '#4CAF50' : '#999999')
            .margin({ left: 8 })
          Text('WV')
            .fontSize(10)
            .fontColor(this.themeState.isDarkTheme() ? '#888888' : '#666666')
            .margin({ left: 2 })
        }
        .onClick(() => this.showEngineInfo())
      }
      .width('100%')
      .height(36)
      .padding({ left: 12, right: 12 })
      
      // 第二行：测试按钮
      Row() {
        // HTML解析器测试按钮
        Button('HTML解析')
          .type(ButtonType.Normal)
          .height(26)
          .fontSize(11)
          .fontColor('#ffffff')
          .backgroundColor('#4CAF50')
          .borderRadius(4)
          .animation({ duration: 140 })
          .onClick(() => {
            this.testHtmlParserLib();
          })
        
        // QuickJS测试按钮
        Button('QuickJS')
          .type(ButtonType.Normal)
          .height(26)
          .fontSize(11)
          .fontColor('#ffffff')
          .backgroundColor('#FF9800')
          .borderRadius(4)
          .margin({ left: 6 })
          .animation({ duration: 140 })
          .onClick(() => {
            this.testQuickJSEngine();
          })
        
        // Rhino沙箱测试按钮
        Button('Rhino沙箱')
          .type(ButtonType.Normal)
          .height(26)
          .fontSize(11)
          .fontColor('#ffffff')
          .backgroundColor('#9C27B0')
          .borderRadius(4)
          .margin({ left: 6 })
          .animation({ duration: 140 })
          .onClick(() => {
            this.testRhinoSandboxEngine();
          })
        
        // Jsoup测试按钮
        Button('Jsoup')
          .type(ButtonType.Normal)
          .height(26)
          .fontSize(11)
          .fontColor('#ffffff')
          .backgroundColor('#2196F3')
          .borderRadius(4)
          .margin({ left: 6 })
          .animation({ duration: 140 })
          .onClick(() => {
            this.testJsoupParsing();
          })
        
        Blank()
      }
      .width('100%')
      .height(32)
      .padding({ left: 12, right: 12 })
    }
    .width('100%')
    .backgroundColor(this.themeState.isDarkTheme() ? '#252525' : '#ffffff')
    .border({ width: { bottom: 1 }, color: this.themeState.isDarkTheme() ? '#333333' : '#e0e0e0' })
    
    // 示例列表
    if (this.showExamples) {
      this.buildExamplesPanel()
    }
    
    // 上下文设置
    if (this.showContext) {
      this.buildContextPanel()
    }
    
    // 设置面板
    if (this.showSettings) {
      this.buildSettingsPanel()
    }
  }

  @Builder
  buildExamplesPanel() {
    Scroll() {
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
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Auto)
    .edgeEffect(EdgeEffect.Spring)
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
  buildSettingsPanel() {
    Column() {
      // WebView开关
      Row() {
        Column() {
          Text('启用WebView沙箱')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.themeState.isDarkTheme() ? '#ffffff' : '#333333')
          Text('开启后Rhino沙箱将使用WebView执行，支持完整的网络请求功能')
            .fontSize(12)
            .fontColor(this.themeState.isDarkTheme() ? '#888888' : '#666666')
            .margin({ top: 4 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        
        Toggle({ type: ToggleType.Switch, isOn: this.enableWebView })
          .selectedColor('#007AFF')
          .onChange((isOn: boolean) => {
            this.enableWebView = isOn;
            this.webViewStatus = isOn ? '已启用' : '未启用';
            logger.info(TAG, `[Settings] WebView开关切换: ${isOn ? '开启' : '关闭'}`);
            
            // 重置Rhino引擎状态，下次执行时重新初始化
            if (this.rhinoEngine) {
              this.rhinoEngine = null;
              this.rhinoSandboxStatus = '未初始化';
              this.rhinoSandboxMode = '';
              logger.info(TAG, '[Settings] Rhino引擎已重置，将在下次执行时重新初始化');
            }
            
            this.getUIContext().getPromptAction().showToast({ 
              message: isOn ? 'WebView沙箱已启用，将使用完整Rhino WASM' : 'WebView沙箱已禁用，将使用NativeJsEngine' 
            });
          })
      }
      .width('100%')
      .padding({ top: 12, bottom: 12 })
      .border({ width: { bottom: 1 }, color: this.themeState.isDarkTheme() ? '#333333' : '#e0e0e0' })
      
      // 当前状态显示
      Column() {
        Text('引擎状态')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.themeState.isDarkTheme() ? '#aaaaaa' : '#666666')
          .margin({ bottom: 8 })
        
        Row() {
          Text('JSVM:')
            .fontSize(12)
            .fontColor(this.themeState.isDarkTheme() ? '#888888' : '#666666')
            .width(80)
          Text(this.engineStatus)
            .fontSize(12)
            .fontColor(this.engineStatus === '已就绪' ? '#4CAF50' : '#FF9800')
        }
        .width('100%')
        .margin({ bottom: 4 })
        
        Row() {
          Text('Rhino沙箱:')
            .fontSize(12)
            .fontColor(this.themeState.isDarkTheme() ? '#888888' : '#666666')
            .width(80)
          Text(`${this.rhinoSandboxStatus}${this.rhinoSandboxMode ? ' (' + this.rhinoSandboxMode + ')' : ''}`)
            .fontSize(12)
            .fontColor(this.rhinoSandboxStatus === '已就绪' ? '#4CAF50' : '#FF9800')
        }
        .width('100%')
        .margin({ bottom: 4 })
        
        Row() {
          Text('WebView:')
            .fontSize(12)
            .fontColor(this.themeState.isDarkTheme() ? '#888888' : '#666666')
            .width(80)
          Text(this.webViewStatus)
            .fontSize(12)
            .fontColor(this.enableWebView ? '#4CAF50' : '#999999')
        }
        .width('100%')
        .margin({ bottom: 4 })
        
        Row() {
          Text('QuickJS:')
            .fontSize(12)
            .fontColor(this.themeState.isDarkTheme() ? '#888888' : '#666666')
            .width(80)
          Text(this.quickjsStatus)
            .fontSize(12)
            .fontColor(this.quickjsInitialized ? '#4CAF50' : '#FF9800')
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding({ top: 12 })
      
      // 清除历史按钮
      Button('清除执行历史')
        .type(ButtonType.Normal)
        .width('100%')
        .height(40)
        .fontSize(14)
        .fontColor('#F44336')
        .backgroundColor(this.themeState.isDarkTheme() ? '#2a2a2a' : '#fff0f0')
        .borderRadius(8)
        .margin({ top: 16 })
        .onClick(() => {
          this.executionHistory = [];
          this.expandedHistoryIds.clear();
          logger.info(TAG, '[Settings] 执行历史已清除');
          this.getUIContext().getPromptAction().showToast({ message: '执行历史已清除' });
        })
    }
    .width('100%')
    .padding(16)
    .backgroundColor(this.themeState.isDarkTheme() ? '#1e1e1e' : '#f0f0f0')
  }

  @Builder
  buildTabBar() {
    Row() {
      this.buildTabButton($r('sys.symbol.doc_text'), '编辑器', 0)
      this.buildTabButton($r('sys.symbol.play_fill'), '输出', 1)
      this.buildTabButton($r('sys.symbol.clock'), `历史${this.executionHistory.length > 0 ? ' (' + this.executionHistory.length + ')' : ''}`, 2)
    }
    .width('100%')
    .height(36)
    .backgroundColor(this.themeState.isDarkTheme() ? '#1f1f1f' : '#f3f3f3')
    .border({ width: { bottom: 1 }, color: this.themeState.isDarkTheme() ? '#333333' : '#e0e0e0' })
  }

  @Builder
  buildTabButton(icon: Resource, title: string, index: number) {
    Row({ space: 6 }) {
      SymbolGlyph(icon)
        .fontSize(13)
        .fontColor([this.selectedTab === index ? '#007AFF' : (this.themeState.isDarkTheme() ? '#9a9a9a' : '#666666')])

      Text(title)
        .fontSize(13)
        .fontColor(this.selectedTab === index ? '#007AFF' : (this.themeState.isDarkTheme() ? '#9a9a9a' : '#666666'))
        .fontWeight(this.selectedTab === index ? FontWeight.Medium : FontWeight.Normal)
    }
    .layoutWeight(1)
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor(this.selectedTab === index ? (this.themeState.isDarkTheme() ? '#2b2b2b' : '#ffffff') : Color.Transparent)
    .border({
      width: { top: this.selectedTab === index ? 2 : 0, bottom: 0, left: 0, right: 0 },
      color: '#007AFF'
    })
    .animation({ duration: 160 })
    .onClick(() => {
      this.selectedTab = index;
    })
  }

  @Builder
  buildEditorPanel() {
    Column() {
      // 代码统计信息
      Row() {
        Text(`${this.codeInput.split('\n').length} 行`)
          .fontSize(11)
          .fontColor(this.themeState.isDarkTheme() ? '#666666' : '#999999')
        Text(`${this.codeInput.length} 字符`)
          .fontSize(11)
          .fontColor(this.themeState.isDarkTheme() ? '#666666' : '#999999')
          .margin({ left: 12 })
        Blank()
        Text('JavaScript')
          .fontSize(11)
          .fontColor('#007AFF')
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 6, bottom: 6 })
      .backgroundColor(this.themeState.isDarkTheme() ? '#252525' : '#f5f5f5')
      
      // 代码编辑区
      TextArea({ text: this.codeInput, placeholder: '// 在这里输入JavaScript代码\n// 支持 java.xxx、source、Jsoup 等 Legado API' })
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
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }

  @Builder
  buildOutputPanel() {
    Column() {
      // 状态栏
      Row() {
        // 执行状态指示
        if (this.isExecuting) {
          LoadingProgress()
            .width(14)
            .height(14)
            .color('#007AFF')
          Text('执行中...')
            .fontSize(12)
            .fontColor('#007AFF')
            .margin({ left: 6 })
        } else if (this.outputText) {
          Circle()
            .width(8)
            .height(8)
            .fill(this.outputText.startsWith('错误') || this.outputText.startsWith('执行异常') ? '#F44336' : '#4CAF50')
          Text(this.outputText.startsWith('错误') || this.outputText.startsWith('执行异常') ? '执行失败' : '执行成功')
            .fontSize(12)
            .fontColor(this.outputText.startsWith('错误') || this.outputText.startsWith('执行异常') ? '#F44336' : '#4CAF50')
            .margin({ left: 6 })
        } else {
          Text('等待执行')
            .fontSize(12)
            .fontColor(this.themeState.isDarkTheme() ? '#666666' : '#999999')
        }
        
        Blank()
        
        // 执行时间
        if (this.executionTime > 0) {
          Text(`${this.executionTime}ms`)
            .fontSize(11)
            .fontColor('#ffffff')
            .backgroundColor(this.executionTime < 100 ? '#4CAF50' : (this.executionTime < 500 ? '#FF9800' : '#F44336'))
            .borderRadius(4)
            .padding({ left: 6, right: 6, top: 2, bottom: 2 })
        }
        
        // 复制按钮
        if (this.outputText) {
          Button('复制')
            .type(ButtonType.Normal)
            .height(24)
            .fontSize(11)
            .fontColor('#007AFF')
            .backgroundColor(Color.Transparent)
            .margin({ left: 8 })
            .onClick(() => {
              this.copyToClipboard(this.outputText);
            })
        }
      }
      .width('100%')
      .padding({ left: 12, right: 12, top: 8, bottom: 8 })
      .backgroundColor(this.themeState.isDarkTheme() ? '#252525' : '#f5f5f5')
      
      // 输出内容
      Scroll() {
        Column() {
          if (!this.outputText) {
            // 空状态
            Column() {
              Text('📄')
                .fontSize(40)
              Text('执行代码后将在此显示输出')
                .fontSize(13)
                .fontColor(this.themeState.isDarkTheme() ? '#555555' : '#aaaaaa')
                .margin({ top: 12 })
            }
            .width('100%')
            .padding({ top: 60 })
          } else {
            Text(this.outputText)
              .width('100%')
              .fontSize(14)
              .fontFamily('monospace')
              .fontColor(this.outputText.startsWith('错误') || this.outputText.startsWith('执行异常') 
                ? '#F44336' 
                : (this.themeState.isDarkTheme() ? '#d4d4d4' : '#333333'))
          }
        }
        .width('100%')
        .padding(12)
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .backgroundColor(this.themeState.isDarkTheme() ? '#1e1e1e' : '#ffffff')
      .scrollBar(BarState.Auto)
    }
    .width('100%')
    .height('100%')
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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
        Text('执行代码后将在此显示历史记录')
          .fontSize(12)
          .fontColor(this.themeState.isDarkTheme() ? '#555555' : '#aaaaaa')
          .margin({ top: 8 })
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .justifyContent(FlexAlign.Center)
    } else {
      Column() {
        // 历史记录统计
        Row() {
          Text(`共 ${this.executionHistory.length} 条记录`)
            .fontSize(12)
            .fontColor(this.themeState.isDarkTheme() ? '#888888' : '#666666')
          Blank()
          Button('全部折叠')
            .type(ButtonType.Normal)
            .height(24)
            .fontSize(11)
            .fontColor('#007AFF')
            .backgroundColor(Color.Transparent)
            .onClick(() => {
              this.expandedHistoryIds.clear();
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 8, bottom: 8 })
        
        List() {
          ForEach(this.executionHistory, (history: ExecutionHistory) => {
            ListItem() {
              Column() {
                // 头部信息行
                Row() {
                  // 状态指示
                  Circle()
                    .width(10)
                    .height(10)
                    .fill(history.success ? '#4CAF50' : '#F44336')
                  
                  Text(this.formatTimestamp(history.timestamp))
                    .fontSize(12)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(this.themeState.isDarkTheme() ? '#cccccc' : '#333333')
                    .margin({ left: 8 })
                  
                  // 耗时标签
                  Text(`${history.duration}ms`)
                    .fontSize(10)
                    .fontColor('#ffffff')
                    .backgroundColor(history.duration < 100 ? '#4CAF50' : (history.duration < 500 ? '#FF9800' : '#F44336'))
                    .borderRadius(4)
                    .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                    .margin({ left: 8 })
                  
                  Blank()
                  
                  // 展开/折叠按钮
                  Button(this.expandedHistoryIds.has(history.id) ? '收起' : '展开')
                    .type(ButtonType.Normal)
                    .height(24)
                    .fontSize(11)
                    .fontColor(this.themeState.isDarkTheme() ? '#aaaaaa' : '#666666')
                    .backgroundColor(Color.Transparent)
                    .onClick(() => {
                      if (this.expandedHistoryIds.has(history.id)) {
                        this.expandedHistoryIds.delete(history.id);
                      } else {
                        this.expandedHistoryIds.add(history.id);
                      }
                      // 触发UI更新
                      this.expandedHistoryIds = new Set(this.expandedHistoryIds);
                    })
                  
                  Button('加载')
                    .type(ButtonType.Normal)
                    .height(24)
                    .fontSize(11)
                    .fontColor('#007AFF')
                    .backgroundColor(Color.Transparent)
                    .onClick(() => this.loadFromHistory(history))
                }
                .width('100%')
                
                // 代码预览（折叠状态）
                if (!this.expandedHistoryIds.has(history.id)) {
                  Text(history.code.split('\n')[0] + (history.code.includes('\n') ? '...' : ''))
                    .fontSize(12)
                    .fontFamily('monospace')
                    .fontColor(this.themeState.isDarkTheme() ? '#aaaaaa' : '#555555')
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 8 })
                  
                  // 结果预览
                  Text(history.result.substring(0, 80) + (history.result.length > 80 ? '...' : ''))
                    .fontSize(11)
                    .fontColor(history.success ? (this.themeState.isDarkTheme() ? '#888888' : '#666666') : '#F44336')
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .margin({ top: 4 })
                }
                
                // 展开状态：显示完整代码和结果
                if (this.expandedHistoryIds.has(history.id)) {
                  // 完整代码
                  Column() {
                    Text('代码:')
                      .fontSize(11)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.themeState.isDarkTheme() ? '#888888' : '#666666')
                      .margin({ bottom: 4 })
                    
                    Scroll() {
                      Text(history.code)
                        .fontSize(12)
                        .fontFamily('monospace')
                        .fontColor(this.themeState.isDarkTheme() ? '#d4d4d4' : '#333333')
                        .width('100%')
                    }
                    .width('100%')
                    .constraintSize({ maxHeight: 150 })
                    .backgroundColor(this.themeState.isDarkTheme() ? '#1a1a1a' : '#f5f5f5')
                    .borderRadius(6)
                    .padding(8)
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                  .margin({ top: 10 })
                  
                  // 完整结果
                  Column() {
                    Text('结果:')
                      .fontSize(11)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(this.themeState.isDarkTheme() ? '#888888' : '#666666')
                      .margin({ bottom: 4 })
                    
                    Scroll() {
                      Text(history.result || '(无输出)')
                        .fontSize(12)
                        .fontFamily('monospace')
                        .fontColor(history.success 
                          ? (this.themeState.isDarkTheme() ? '#d4d4d4' : '#333333') 
                          : '#F44336')
                        .width('100%')
                    }
                    .width('100%')
                    .constraintSize({ maxHeight: 200 })
                    .backgroundColor(this.themeState.isDarkTheme() ? '#1a1a1a' : '#f5f5f5')
                    .borderRadius(6)
                    .padding(8)
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                  .margin({ top: 8 })
                }
              }
              .width('100%')
              .padding(12)
              .backgroundColor(this.themeState.isDarkTheme() ? '#252525' : '#ffffff')
              .borderRadius(8)
              .shadow({ radius: 2, color: this.themeState.isDarkTheme() ? '#000000' : '#00000020', offsetY: 1 })
            }
            .margin({ bottom: 10 })
          })
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ left: 12, right: 12, bottom: 12 })
      }
      .width('100%')
      .height('100%')
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .backgroundColor(this.themeState.isDarkTheme() ? '#1a1a1a' : '#f0f0f0')
    }
  }

  @Builder
  buildBottomBar() {
    Column() {
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
      .animation({ duration: 140 })
      .onClick(() => this.clearCode())
      
      Blank()
      
      // Rhino沙箱运行按钮
      Button() {
        Row() {
          if (this.isExecuting) {
            LoadingProgress()
              .width(14)
              .height(14)
              .color(Color.White)
          } else {
            Text('R')
              .fontSize(11)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
          }
          Text(this.isExecuting ? '' : '沙箱')
            .fontSize(12)
            .fontColor(Color.White)
            .margin({ left: 2 })
        }
      }
      .type(ButtonType.Normal)
      .height(40)
      .backgroundColor(this.isExecuting ? '#999999' : '#9C27B0')
      .borderRadius(8)
      .padding({ left: 12, right: 12 })
      .enabled(!this.isExecuting)
      .animation({ duration: 140 })
      .onClick(() => {
        this.executeWithRhinoSandbox();
        this.selectedTab = 1;
      })
      
      // QuickJS运行按钮
      Button() {
        Row() {
          if (this.isExecuting) {
            LoadingProgress()
              .width(14)
              .height(14)
              .color(Color.White)
          } else {
            Text('Q')
              .fontSize(11)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Bold)
          }
          Text(this.isExecuting ? '' : 'JS')
            .fontSize(12)
            .fontColor(Color.White)
            .margin({ left: 2 })
        }
      }
      .type(ButtonType.Normal)
      .height(40)
      .backgroundColor(this.isExecuting ? '#999999' : '#FF9800')
      .borderRadius(8)
      .padding({ left: 12, right: 12 })
      .margin({ left: 6 })
      .enabled(!this.isExecuting)
      .animation({ duration: 140 })
      .onClick(() => {
        this.executeWithQuickJS();
        this.selectedTab = 1;
      })
      
      // JSVM运行按钮
      Button() {
        Row() {
          if (this.isExecuting) {
            LoadingProgress()
              .width(14)
              .height(14)
              .color(Color.White)
          } else {
            SymbolGlyph($r('sys.symbol.play_fill'))
              .fontSize(14)
              .fontColor([Color.White])
          }
          Text(this.isExecuting ? '' : 'VM')
            .fontSize(12)
            .fontColor(Color.White)
            .margin({ left: 2 })
        }
      }
      .type(ButtonType.Normal)
      .height(40)
      .backgroundColor(this.isExecuting ? '#999999' : '#007AFF')
      .borderRadius(8)
      .padding({ left: 12, right: 12 })
      .margin({ left: 6 })
      .enabled(!this.isExecuting)
      .animation({ duration: 140 })
      .onClick(() => {
        this.executeCode();
        this.selectedTab = 1;
      })
      }
      .width('100%')
      .height(60)
      .padding({ left: 16, right: 16 })
    }
    .width('100%')
    // .padding({ bottom: this.navigationBarHeight })
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .backgroundColor(this.themeState.isDarkTheme() ? '#252525' : '#ffffff')
    .border({ width: { top: 1 }, color: this.themeState.isDarkTheme() ? '#333333' : '#e0e0e0' })
  }
}
