/**
 * 不可见WebView测试页面
 * 演示如何使用不可见WebView系统
 */

import { webview } from '@kit.ArkWeb';
import { logger } from '../Utils/Logger';
import { WebViewContainer, GlobalWebViewContainer, WebViewEventCallbacks } from '../Framework/WebView/WebViewContainerPage';
import { WebViewSourceConfig } from '../Framework/WebView/WebViewImageLoader';

const TAG = 'InvisibleWebViewTestPage';

@Entry
@Component
struct InvisibleWebViewTestPage {
  @State testResults: string[] = [];
  @State isLoading: boolean = false;
  @State webViewCount: number = 0;
  
  // WebView容器引用
  private webViewContainer: WebViewContainer | null = null;
  private testController: webview.WebviewController | null = null;

  aboutToAppear() {
    logger.info(TAG, '测试页面初始化');
  }

  aboutToDisappear() {
    logger.info(TAG, '测试页面销毁');
    // 清理所有WebView
    GlobalWebViewContainer.clearAll();
  }

  /**
   * 添加测试结果
   */
  private addTestResult(message: string) {
    const timestamp = new Date().toLocaleTimeString();
    this.testResults.push(`[${timestamp}] ${message}`);
    logger.info(TAG, message);
  }

  /**
   * 测试1: 创建基础WebView
   */
  private async testBasicWebView() {
    this.addTestResult('=== 测试1: 创建基础WebView ===');
    this.isLoading = true;

    try {
      // 创建控制器
      const controller = new webview.WebviewController();
      this.testController = controller;

      // 配置
      const config: WebViewSourceConfig = {
        sourceId: 'test_basic',
        userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        enableJavaScript: true,
        enableImages: true,
        cookiePolicy: 'default',
        timeout: 30000
      };

      // 事件回调
      const callbacks: WebViewEventCallbacks = {
        onPageBegin: (url) => {
          this.addTestResult(`页面开始加载: ${url}`);
        },
        onPageEnd: (url) => {
          this.addTestResult(`页面加载完成: ${url}`);
          this.isLoading = false;
          
          // 页面加载完成后执行JavaScript
          this.executeJavaScriptTest();
        },
        onProgressChange: (progress) => {
          this.addTestResult(`加载进度: ${progress}%`);
        },
        onError: (error) => {
          this.addTestResult(`加载错误: ${error}`);
          this.isLoading = false;
        }
      };

      // 添加到容器
      GlobalWebViewContainer.addWebView('test_basic', controller, config, callbacks, 'https://www.baidu.com');
      this.webViewCount = GlobalWebViewContainer.getCount();
      
      this.addTestResult('WebView创建成功，开始加载页面...');

    } catch (error) {
      this.addTestResult(`测试失败: ${error}`);
      this.isLoading = false;
    }
  }

  /**
   * 测试2: 执行JavaScript
   */
  private async executeJavaScriptTest() {
    this.addTestResult('=== 测试2: 执行JavaScript ===');

    if (!this.testController) {
      this.addTestResult('错误: 控制器未初始化');
      return;
    }

    try {
      // 获取页面标题
      const title = await this.testController.runJavaScript('document.title');
      this.addTestResult(`页面标题: ${title}`);

      // 获取URL
      const url = await this.testController.runJavaScript('window.location.href');
      this.addTestResult(`当前URL: ${url}`);

      // 获取页面元素数量
      const elementCount = await this.testController.runJavaScript('document.querySelectorAll("*").length');
      this.addTestResult(`页面元素数量: ${elementCount}`);

    } catch (error) {
      this.addTestResult(`JavaScript执行失败: ${error}`);
    }
  }

  /**
   * 测试3: 导航到新页面
   */
  private async testNavigation() {
    this.addTestResult('=== 测试3: 导航到新页面 ===');

    if (!this.testController) {
      this.addTestResult('错误: 控制器未初始化');
      return;
    }

    try {
      this.isLoading = true;
      this.testController.loadUrl('https://www.bing.com');
      this.addTestResult('开始导航到新页面...');
    } catch (error) {
      this.addTestResult(`导航失败: ${error}`);
      this.isLoading = false;
    }
  }

  /**
   * 测试4: 创建多个WebView
   */
  private async testMultipleWebViews() {
    this.addTestResult('=== 测试4: 创建多个WebView ===');

    try {
      const urls = [
        'https://www.google.com',
        'https://www.github.com',
        'https://www.stackoverflow.com'
      ];

      for (let i = 0; i < urls.length; i++) {
        const controller = new webview.WebviewController();
        const config: WebViewSourceConfig = {
          sourceId: `test_multi_${i}`,
          userAgent: 'Mozilla/5.0',
          enableJavaScript: true,
          enableImages: false, // 禁用图片加载以提高性能
          cookiePolicy: 'default',
          timeout: 30000
        };

        const callbacks: WebViewEventCallbacks = {
          onPageEnd: (url) => {
            this.addTestResult(`WebView ${i} 加载完成: ${url}`);
          }
        };

        GlobalWebViewContainer.addWebView(`test_multi_${i}`, controller, config, callbacks, urls[i]);
      }

      this.webViewCount = GlobalWebViewContainer.getCount();
      this.addTestResult(`创建了 ${urls.length} 个WebView实例`);

    } catch (error) {
      this.addTestResult(`创建多个WebView失败: ${error}`);
    }
  }

  /**
   * 清理所有WebView
   */
  private clearAllWebViews() {
    this.addTestResult('=== 清理所有WebView ===');
    GlobalWebViewContainer.clearAll();
    this.webViewCount = 0;
    this.testController = null;
    this.addTestResult('所有WebView已清理');
  }

  /**
   * 清空测试结果
   */
  private clearResults() {
    this.testResults = [];
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text('不可见WebView测试')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
      }
      .width('100%')
      .height(56)
      .padding({ left: 16, right: 16 })
      .backgroundColor('#F5F5F5')

      // 状态信息
      Row() {
        Text(`WebView数量: ${this.webViewCount}`)
          .fontSize(14)
        
        Text(this.isLoading ? '加载中...' : '空闲')
          .fontSize(14)
          .fontColor(this.isLoading ? '#FF6B00' : '#00C853')
          .margin({ left: 20 })
      }
      .width('100%')
      .padding(16)
      .justifyContent(FlexAlign.Start)

      // 测试按钮
      Column() {
        Button('测试1: 创建基础WebView')
          .width('100%')
          .onClick(() => this.testBasicWebView())
          .margin({ bottom: 10 })

        Button('测试2: 执行JavaScript')
          .width('100%')
          .onClick(() => this.executeJavaScriptTest())
          .margin({ bottom: 10 })
          .enabled(this.testController !== null)

        Button('测试3: 导航到新页面')
          .width('100%')
          .onClick(() => this.testNavigation())
          .margin({ bottom: 10 })
          .enabled(this.testController !== null)

        Button('测试4: 创建多个WebView')
          .width('100%')
          .onClick(() => this.testMultipleWebViews())
          .margin({ bottom: 10 })

        Row() {
          Button('清理所有WebView')
            .width('48%')
            .onClick(() => this.clearAllWebViews())
            .backgroundColor('#FF5252')

          Button('清空结果')
            .width('48%')
            .onClick(() => this.clearResults())
            .backgroundColor('#757575')
        }
        .width('100%')
        .justifyContent(FlexAlign.SpaceBetween)
      }
      .width('100%')
      .padding(16)

      // 测试结果显示
      Column() {
        Text('测试结果:')
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .width('100%')
          .margin({ bottom: 10 })

        Scroll() {
          Column() {
            ForEach(this.testResults, (result: string, index: number) => {
              Text(result)
                .fontSize(12)
                .width('100%')
                .padding(8)
                .backgroundColor(index % 2 === 0 ? '#FFFFFF' : '#F5F5F5')
                .fontFamily('monospace')
            })
          }
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor('#FAFAFA')
        .border({ width: 1, color: '#E0E0E0' })
      }
      .width('100%')
      .padding(16)
      .layoutWeight(1)

      // 不可见的WebView容器
      WebViewContainer()
        .onAppear(() => {
          // 设置全局容器引用
          GlobalWebViewContainer.setContainer(this.webViewContainer!);
          this.addTestResult('WebView容器已初始化');
        })
    }
    .width('100%')
    .height('100%')
    .backgroundColor('#FFFFFF')
  }
}
