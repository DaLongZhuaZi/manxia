// 文件路径: src/main/ets/Framework/WebView/WebViewNetworkTester.ets
/**
 * WebView网络连接测试工具
 * 用于诊断网站可访问性、连接问题和请求/响应头
 */

import { webview } from '@kit.ArkWeb';
import { http } from '@kit.NetworkKit';
import { logger } from '../../Utils/Logger';

const TAG = 'WebViewNetworkTester';

/**
 * 网络测试结果
 */
export interface NetworkTestResult {
  /** 测试是否成功 */
  success: boolean;
  /** 测试URL */
  url: string;
  /** HTTP状态码 */
  statusCode?: number;
  /** 响应时间(ms) */
  responseTime?: number;
  /** 请求头 */
  requestHeaders?: Record<string, string>;
  /** 响应头 */
  responseHeaders?: Record<string, string>;
  /** 错误信息 */
  error?: string;
  /** 连接类型 */
  connectionType?: string;
  /** 是否重定向 */
  redirected?: boolean;
  /** 最终URL */
  finalUrl?: string;
  /** 响应体大小(bytes) */
  contentLength?: number;
  /** Content-Type */
  contentType?: string;
}

/**
 * WebView测试结果
 */
export interface WebViewTestResult {
  /** 测试是否成功 */
  success: boolean;
  /** 页面URL */
  url: string;
  /** 页面标题 */
  title?: string;
  /** 加载时间(ms) */
  loadTime?: number;
  /** UserAgent */
  userAgent?: string;
  /** Cookie数量 */
  cookieCount?: number;
  /** 是否有Cloudflare挑战 */
  hasCloudflare?: boolean;
  /** DOM元素数量 */
  domElementCount?: number;
  /** 错误信息 */
  error?: string;
  /** 页面内容预览 */
  contentPreview?: string;
}

/**
 * 完整测试报告
 */
export interface TestReport {
  /** 测试时间 */
  timestamp: number;
  /** 目标URL */
  targetUrl: string;
  /** HTTP测试结果 */
  httpTest: NetworkTestResult;
  /** WebView测试结果 */
  webViewTest: WebViewTestResult;
  /** 诊断建议 */
  suggestions: string[];
}

/**
 * WebView网络测试器
 */
export class WebViewNetworkTester {
  private static instance: WebViewNetworkTester | null = null;

  private constructor() {}

  public static getInstance(): WebViewNetworkTester {
    if (!WebViewNetworkTester.instance) {
      WebViewNetworkTester.instance = new WebViewNetworkTester();
    }
    return WebViewNetworkTester.instance;
  }

  /**
   * 执行HTTP连接测试
   */
  async testHttpConnection(url: string, customHeaders?: Record<string, string>): Promise<NetworkTestResult> {
    logger.info(TAG, `🔍 开始HTTP连接测试: ${url}`);
    const startTime = Date.now();

    const result: NetworkTestResult = {
      success: false,
      url: url
    };

    try {
      const httpRequest = http.createHttp();
      
      // 构建请求头
      const headers: Record<string, string> = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
        'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
        'Accept-Language': 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7',
        'Accept-Encoding': 'gzip, deflate, br',
        'Connection': 'keep-alive',
        'Upgrade-Insecure-Requests': '1',
        'Sec-Fetch-Dest': 'document',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'none',
        'Cache-Control': 'max-age=0',
        ...customHeaders
      };

      result.requestHeaders = headers;

      logger.debug(TAG, `📤 请求头: ${JSON.stringify(headers, null, 2)}`);

      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        header: headers,
        readTimeout: 30000,
        connectTimeout: 30000,
        expectDataType: http.HttpDataType.STRING
      });

      const responseTime = Date.now() - startTime;
      result.responseTime = responseTime;
      result.statusCode = response.responseCode;

      // 解析响应头
      const responseHeaders: Record<string, string> = {};
      if (response.header) {
        Object.keys(response.header).forEach(key => {
          const value = response.header[key];
          responseHeaders[key] = Array.isArray(value) ? value.join(', ') : String(value);
        });
      }
      result.responseHeaders = responseHeaders;
      result.contentType = responseHeaders['content-type'] || responseHeaders['Content-Type'];
      result.contentLength = parseInt(responseHeaders['content-length'] || responseHeaders['Content-Length'] || '0');

      // 检查重定向
      if (response.responseCode >= 300 && response.responseCode < 400) {
        result.redirected = true;
        result.finalUrl = responseHeaders['location'] || responseHeaders['Location'];
        logger.info(TAG, `🔄 检测到重定向: ${response.responseCode} -> ${result.finalUrl}`);
      }

      logger.info(TAG, `📥 响应码: ${response.responseCode}, 耗时: ${responseTime}ms`);
      logger.debug(TAG, `📥 响应头: ${JSON.stringify(responseHeaders, null, 2)}`);

      result.success = response.responseCode >= 200 && response.responseCode < 300;

      if (!result.success) {
        result.error = `HTTP ${response.responseCode}: ${this.getStatusMessage(response.responseCode)}`;
      }

      httpRequest.destroy();
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      result.error = errorMsg;
      result.responseTime = Date.now() - startTime;
      logger.error(TAG, `❌ HTTP请求失败: ${errorMsg}`);
      
      // 分析错误类型
      if (errorMsg.includes('CONNECTION_CLOSED') || errorMsg.includes('Connection closed')) {
        result.connectionType = 'CONNECTION_CLOSED';
        logger.error(TAG, '🔴 连接被服务器关闭，可能原因：1) 服务器拒绝连接 2) 网络不稳定 3) 防火墙拦截');
      } else if (errorMsg.includes('TIMEOUT') || errorMsg.includes('timeout')) {
        result.connectionType = 'TIMEOUT';
        logger.error(TAG, '🔴 连接超时，可能原因：1) 网络延迟过高 2) 服务器无响应 3) DNS解析失败');
      } else if (errorMsg.includes('SSL') || errorMsg.includes('certificate')) {
        result.connectionType = 'SSL_ERROR';
        logger.error(TAG, '🔴 SSL证书错误，可能原因：1) 证书过期 2) 证书不受信任 3) 中间人攻击');
      }
    }

    return result;
  }

  /**
   * 执行WebView测试
   */
  async testWebViewConnection(
    url: string,
    controller: webview.WebviewController,
    customUserAgent?: string
  ): Promise<WebViewTestResult> {
    logger.info(TAG, `🌐 开始WebView连接测试: ${url}`);
    const startTime = Date.now();

    const result: WebViewTestResult = {
      success: false,
      url: url
    };

    try {
      // 设置自定义UserAgent
      if (customUserAgent) {
        controller.setCustomUserAgent(customUserAgent);
        logger.info(TAG, `✅ 已设置UserAgent: ${customUserAgent}`);
      }

      // 加载页面
      controller.loadUrl(url);
      
      // 等待页面加载
      await new Promise<void>((resolve) => setTimeout(resolve, 5000));

      const loadTime = Date.now() - startTime;
      result.loadTime = loadTime;

      // 获取页面信息
      const testScript = `
        (function() {
          return JSON.stringify({
            url: window.location.href,
            title: document.title,
            userAgent: navigator.userAgent,
            cookieCount: document.cookie.split(';').filter(c => c.trim()).length,
            hasCloudflare: !!(document.querySelector('#challenge-form') || document.querySelector('.cf-browser-verification')),
            domElementCount: document.querySelectorAll('*').length,
            bodyLength: document.body.innerHTML.length,
            contentPreview: document.body.innerHTML.substring(0, 500)
          });
        })();
      `;

      const scriptResult = await new Promise<string>((resolve, reject) => {
        controller.runJavaScript(testScript, (error, result) => {
          if (error) {
            reject(error);
          } else {
            resolve(result);
          }
        });
      });

      const pageInfo = JSON.parse(scriptResult);
      result.title = pageInfo.title;
      result.userAgent = pageInfo.userAgent;
      result.cookieCount = pageInfo.cookieCount;
      result.hasCloudflare = pageInfo.hasCloudflare;
      result.domElementCount = pageInfo.domElementCount;
      result.contentPreview = pageInfo.contentPreview;
      result.success = true;

      logger.info(TAG, `✅ WebView测试成功，加载时间: ${loadTime}ms`);
      logger.info(TAG, `📄 页面标题: ${result.title}`);
      logger.info(TAG, `🍪 Cookie数量: ${result.cookieCount}`);
      logger.info(TAG, `🔒 Cloudflare挑战: ${result.hasCloudflare ? '是' : '否'}`);
      logger.info(TAG, `📊 DOM元素数量: ${result.domElementCount}`);

    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      result.error = errorMsg;
      result.loadTime = Date.now() - startTime;
      logger.error(TAG, `❌ WebView测试失败: ${errorMsg}`);
    }

    return result;
  }

  /**
   * 执行完整测试
   */
  async runFullTest(
    url: string,
    controller?: webview.WebviewController,
    customHeaders?: Record<string, string>
  ): Promise<TestReport> {
    logger.info(TAG, `🚀 开始完整网络测试: ${url}`);
    logger.info(TAG, '='.repeat(60));

    const report: TestReport = {
      timestamp: Date.now(),
      targetUrl: url,
      httpTest: await this.testHttpConnection(url, customHeaders),
      webViewTest: { success: false, url: url },
      suggestions: []
    };

    // 如果提供了WebView控制器，执行WebView测试
    if (controller) {
      report.webViewTest = await this.testWebViewConnection(url, controller, customHeaders?.['User-Agent']);
    }

    // 生成诊断建议
    report.suggestions = this.generateSuggestions(report);

    // 输出测试报告
    this.printReport(report);

    return report;
  }

  /**
   * 生成诊断建议
   */
  private generateSuggestions(report: TestReport): string[] {
    const suggestions: string[] = [];

    // HTTP测试分析
    if (!report.httpTest.success) {
      if (report.httpTest.connectionType === 'CONNECTION_CLOSED') {
        suggestions.push('🔴 连接被关闭：尝试更换域名或使用代理');
        suggestions.push('🔴 检查网络连接是否稳定');
        suggestions.push('🔴 确认目标网站是否可访问');
      } else if (report.httpTest.statusCode === 403) {
        suggestions.push('🔴 403 Forbidden：网站拒绝访问，可能需要特定的请求头或Cookie');
        suggestions.push('🔴 尝试添加Referer头部');
        suggestions.push('🔴 检查是否需要登录或验证');
      } else if (report.httpTest.statusCode === 503) {
        suggestions.push('🔴 503 Service Unavailable：服务器暂时不可用');
        suggestions.push('🔴 稍后重试或更换域名');
      } else if (report.httpTest.connectionType === 'TIMEOUT') {
        suggestions.push('🔴 连接超时：增加超时时间或检查网络');
      }
    }

    // WebView测试分析
    if (report.webViewTest.hasCloudflare) {
      suggestions.push('🟡 检测到Cloudflare挑战：需要实现Cloudflare绕过');
    }

    if (report.webViewTest.domElementCount && report.webViewTest.domElementCount < 100) {
      suggestions.push('🟡 DOM元素较少：页面可能未完全加载或被拦截');
      suggestions.push('🟡 建议增加等待时间或检查页面内容');
    }

    if (!suggestions.length && report.httpTest.success && report.webViewTest.success) {
      suggestions.push('✅ 所有测试通过，网站可正常访问');
    }

    return suggestions;
  }

  /**
   * 打印测试报告
   */
  private printReport(report: TestReport): void {
    logger.info(TAG, '');
    logger.info(TAG, '📊 ========== 网络测试报告 ==========');
    logger.info(TAG, `🎯 目标URL: ${report.targetUrl}`);
    logger.info(TAG, `⏰ 测试时间: ${new Date(report.timestamp).toLocaleString()}`);
    logger.info(TAG, '');
    
    // HTTP测试结果
    logger.info(TAG, '📡 HTTP测试结果:');
    logger.info(TAG, `   状态: ${report.httpTest.success ? '✅ 成功' : '❌ 失败'}`);
    logger.info(TAG, `   状态码: ${report.httpTest.statusCode || 'N/A'}`);
    logger.info(TAG, `   响应时间: ${report.httpTest.responseTime || 'N/A'}ms`);
    logger.info(TAG, `   Content-Type: ${report.httpTest.contentType || 'N/A'}`);
    logger.info(TAG, `   Content-Length: ${report.httpTest.contentLength || 'N/A'} bytes`);
    if (report.httpTest.error) {
      logger.error(TAG, `   错误: ${report.httpTest.error}`);
    }
    logger.info(TAG, '');

    // WebView测试结果
    logger.info(TAG, '🌐 WebView测试结果:');
    logger.info(TAG, `   状态: ${report.webViewTest.success ? '✅ 成功' : '❌ 失败'}`);
    logger.info(TAG, `   页面标题: ${report.webViewTest.title || 'N/A'}`);
    logger.info(TAG, `   加载时间: ${report.webViewTest.loadTime || 'N/A'}ms`);
    logger.info(TAG, `   Cookie数量: ${report.webViewTest.cookieCount || 0}`);
    logger.info(TAG, `   Cloudflare: ${report.webViewTest.hasCloudflare ? '是' : '否'}`);
    logger.info(TAG, `   DOM元素: ${report.webViewTest.domElementCount || 'N/A'}`);
    if (report.webViewTest.error) {
      logger.error(TAG, `   错误: ${report.webViewTest.error}`);
    }
    logger.info(TAG, '');

    // 诊断建议
    logger.info(TAG, '💡 诊断建议:');
    report.suggestions.forEach(suggestion => {
      logger.info(TAG, `   ${suggestion}`);
    });
    logger.info(TAG, '');
    logger.info(TAG, '=' .repeat(60));
  }

  /**
   * 获取HTTP状态码描述
   */
  private getStatusMessage(code: number): string {
    const messages: Record<number, string> = {
      200: 'OK',
      301: 'Moved Permanently',
      302: 'Found',
      304: 'Not Modified',
      400: 'Bad Request',
      401: 'Unauthorized',
      403: 'Forbidden',
      404: 'Not Found',
      500: 'Internal Server Error',
      502: 'Bad Gateway',
      503: 'Service Unavailable',
      504: 'Gateway Timeout'
    };
    return messages[code] || 'Unknown Status';
  }
}
