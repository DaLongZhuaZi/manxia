// 文件路径: src/main/ets/Framework/WebView/MangaSourceAntiCrawler.ets
/**
 * 漫画图源反爬虫机制处理器
 * 处理Cloudflare、验证码、IP封禁等反爬虫措施
 */

import { webview } from '@kit.ArkWeb';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { AntiCrawlerConfig, CloudflareConfig, CaptchaConfig, IpBlockConfig } from './MangaSourceTypes';

const TAG = 'MangaSourceAntiCrawler';

/**
 * 反爬虫检测结果
 */
export interface AntiCrawlerResult {
  detected: boolean;
  type: 'cloudflare' | 'captcha' | 'ip_block' | 'rate_limit' | 'unknown';
  message: string;
  canBypass: boolean;
  estimatedWaitTime?: number;
}

/**
 * Cloudflare绕过结果
 */
export interface CloudflareBypassResult {
  success: boolean;
  waitTime: number;
  error?: string;
}

/**
 * 验证码处理结果
 */
export interface CaptchaResult {
  detected: boolean;
  type: 'recaptcha' | 'hcaptcha' | 'image' | 'text' | 'unknown';
  solved: boolean;
  error?: string;
}

/**
 * 反爬虫机制处理器
 */
export class MangaSourceAntiCrawler {
  private webviewController: webview.WebviewController;
  private config: AntiCrawlerConfig;
  private onNeedUserInteraction?: () => void;

  constructor(webviewController: webview.WebviewController, config: AntiCrawlerConfig) {
    this.webviewController = webviewController;
    this.config = config;
  }

  /**
   * 设置用户交互回调（当需要用户手动完成验证时调用）
   */
  setOnNeedUserInteraction(callback: () => void): void {
    this.onNeedUserInteraction = callback;
  }

  /**
   * 更新WebView控制器（修复：页面返回后WebView失效）
   */
  updateWebViewController(controller: webview.WebviewController): void {
    this.webviewController = controller;
  }

  /**
   * 检测当前页面是否存在反爬虫机制
   */
  async detectAntiCrawler(): Promise<AntiCrawlerResult> {
    try {
      logger.debug(TAG, '开始检测反爬虫机制');

      // 获取页面内容
      const pageContent = await this.getPageContent();
      const pageTitle = await this.getPageTitle();
      const currentUrl = await this.getCurrentUrl();

      // 检测Cloudflare
      if (this.config.cloudflare?.enabled) {
        const cloudflareResult = this.detectCloudflare(pageContent, pageTitle);
        if (cloudflareResult.detected) {
          return cloudflareResult;
        }
      }

      // 检测验证码
      if (this.config.captcha?.enabled) {
        const captchaResult = this.detectCaptcha(pageContent);
        if (captchaResult.detected) {
          return {
            detected: true,
            type: 'captcha',
            message: '检测到验证码',
            canBypass: this.config.captcha.autoSolve || false
          };
        }
      }

      // 检测IP封禁
      if (this.config.ipBlock?.enabled) {
        const ipBlockResult = this.detectIpBlock(pageContent, pageTitle);
        if (ipBlockResult.detected) {
          return ipBlockResult;
        }
      }

      // 检测频率限制
      const rateLimitResult = this.detectRateLimit(pageContent, pageTitle);
      if (rateLimitResult.detected) {
        return rateLimitResult;
      }

      logger.debug(TAG, '未检测到反爬虫机制');
      return {
        detected: false,
        type: 'unknown',
        message: '未检测到反爬虫机制',
        canBypass: true
      };

    } catch (error) {
      logger.error(TAG, '检测反爬虫机制时发生错误' + error);
      return {
        detected: true,
        type: 'unknown',
        message: `检测失败: ${error}`,
        canBypass: false
      };
    }
  }

  /**
   * 绕过Cloudflare保护
   * @param method 绕过方法，可选值: wait, click, refresh, interactive
   * @param maxWait 最大等待时间（毫秒）
   */
  async bypassCloudflare(method?: string, maxWait?: number): Promise<CloudflareBypassResult> {
    try {
      logger.info(TAG, '开始绕过Cloudflare保护');

      const startTime = Date.now();
      const maxWaitTime = maxWait || this.config.cloudflare?.maxWaitTime || 30000;
      let retryCount = 0;
      const maxRetries = this.config.cloudflare?.retryCount || 5;
      const bypassMethod = method || this.config.cloudflare?.bypassMethod || 'wait';

      // 首先检查是否需要绕过
      const initialCheck = await this.isCloudflareBlocked();
      if (!initialCheck) {
        logger.info(TAG, 'Cloudflare绕过成功（页面无CF验证），耗时: 0ms');
        return {
          success: true,
          waitTime: 0
        };
      }
      
      logger.info(TAG, `检测到Cloudflare验证，方法: ${bypassMethod}，最大等待时间: ${maxWaitTime}ms`);

      // 无论什么模式，只要检测到CF验证且设置了回调，就通知UI层显示验证对话框
      // 这样用户可以手动完成验证
      if (this.onNeedUserInteraction) {
        logger.info(TAG, '【CF验证】通知UI层显示验证对话框，等待用户手动完成');
        this.onNeedUserInteraction();
      }

      // 等待用户完成验证，每2秒检查一次
      while (Date.now() - startTime < maxWaitTime) {
        await this.sleep(2000);
        
        const isStillBlocked = await this.isCloudflareBlocked();
        if (!isStillBlocked) {
          const finalElapsed = Date.now() - startTime;
          logger.info(TAG, `【CF验证】验证通过，耗时: ${finalElapsed}ms`);
          return {
            success: true,
            waitTime: finalElapsed
          };
        }
        
        const elapsed = Date.now() - startTime;
        if (elapsed % 10000 < 2000) {
          logger.debug(TAG, `【CF验证】等待用户完成验证... 已等待: ${Math.floor(elapsed / 1000)}秒`);
        }
      }
      
      const totalTime = Date.now() - startTime;
      logger.warn(TAG, `【CF验证】验证超时，用户未在${maxWaitTime / 1000}秒内完成`);
      return {
        success: false,
        waitTime: totalTime,
        error: `等待用户验证超时（${maxWaitTime / 1000}秒）`
      };

    } catch (error) {
      logger.error(TAG, '绕过Cloudflare时发生错误' + error);
      return {
        success: false,
        waitTime: 0,
        error: `绕过失败: ${error}`
      };
    }
  }

  /**
   * 处理验证码
   */
  async handleCaptcha(): Promise<CaptchaResult> {
    try {
      logger.info(TAG, '开始处理验证码');

      const captchaType = await this.detectCaptchaType();
      if (captchaType === 'unknown') {
        return {
          detected: false,
          type: 'unknown',
          solved: false,
          error: '未检测到验证码'
        };
      }

      const config = this.config.captcha as CaptchaConfig;

      if (config.autoSolve) {
        // 自动验证码依赖外部识别服务，本地版本只返回明确受限原因。
        return await this.autoSolveCaptcha(captchaType);
      } else {
        // 手动处理验证码
        return await this.manualSolveCaptcha(captchaType, config.timeout || 300000);
      }

    } catch (error) {
      logger.error(TAG, '处理验证码时发生错误' + error);
      return {
        detected: true,
        type: 'unknown',
        solved: false,
        error: `处理失败: ${error}`
      };
    }
  }

  /**
   * 处理IP封禁
   */
  async handleIpBlock(): Promise<boolean> {
    try {
      logger.warn(TAG, '检测到IP封禁，开始处理');

      const config = this.config.ipBlock as IpBlockConfig;
      const delay = config.delay || 60000;
      const maxRetries = config.maxRetries || 5;

      for (let i = 0; i < maxRetries; i++) {
        logger.info(TAG, `等待${delay}ms后重试 (${i + 1}/${maxRetries})`);
        await this.sleep(delay);

        // 刷新页面检查是否仍被封禁
        await this.refreshPage();
        await this.sleep(3000);

        const stillBlocked = await this.isIpBlocked();
        if (!stillBlocked) {
          logger.info(TAG, 'IP封禁已解除');
          return true;
        }
      }

      logger.error(TAG, 'IP封禁处理失败，已达到最大重试次数');
      return false;

    } catch (error) {
      logger.error(TAG, '处理IP封禁时发生错误' + error);
      return false;
    }
  }

  /**
   * 轮换User-Agent
   */
  async rotateUserAgent(): Promise<void> {
    try {
      const rotation = this.config.userAgentRotation;
      if (!rotation?.enabled || !rotation.agents || rotation.agents.length === 0) {
        return;
      }

      const randomAgent = rotation.agents[Math.floor(Math.random() * rotation.agents.length)];
      
      // 通过JavaScript设置User-Agent（注意：这种方法有限制）
      await this.executeScript(`
        Object.defineProperty(navigator, 'userAgent', {
          get: function() { return '${randomAgent}'; }
        });
      `);

      logger.debug(TAG, `User-Agent已轮换为: ${randomAgent}`);

    } catch (error) {
      logger.error(TAG, '轮换User-Agent时发生错误' + error);
    }
  }

  // 私有方法

  private async getPageContent(): Promise<string> {
    return await this.executeScript('document.documentElement.outerHTML') as string;
  }

  private async getPageTitle(): Promise<string> {
    return await this.executeScript('document.title') as string;
  }

  private async getCurrentUrl(): Promise<string> {
    return await this.executeScript('window.location.href') as string;
  }

  detectCloudflare(content: string, title: string): AntiCrawlerResult {
    // 默认的Cloudflare检测指标
    const defaultIndicators = [
      'Just a moment',
      'Checking your browser',
      'Please Wait',
      'Cloudflare',
      'cf-browser-verification',
      'cf_chl_opt',
      'challenge-platform',
      'ray ID',
      'cf-spinner',
      'turnstile',
      'Verifying you are human',
      'DDoS protection',
      'Enable JavaScript and cookies',
      '请稍候',
      '正在检查您的浏览器',
      '请完成以下操作，验证您是真人。',
      '正在验证您是否是真人。这可能需要几秒钟时间。'
    ];
    
    const indicators = this.config.cloudflare?.indicators || defaultIndicators;
    
    for (const indicator of indicators) {
      if (content.toLowerCase().includes(indicator.toLowerCase()) || 
          title.toLowerCase().includes(indicator.toLowerCase())) {
        logger.info(TAG, `检测到Cloudflare保护: ${indicator}`);
        return {
          detected: true,
          type: 'cloudflare',
          message: `检测到Cloudflare保护: ${indicator}`,
          canBypass: true,
          estimatedWaitTime: this.config.cloudflare?.maxWaitTime || 30000
        };
      }
    }

    return { detected: false, type: 'cloudflare', message: '', canBypass: true };
  }

  detectCaptcha(content: string): AntiCrawlerResult {
    const indicators = this.config.captcha?.indicators || [];
    
    for (const indicator of indicators) {
      if (content.includes(indicator)) {
        return {
          detected: true,
          type: 'captcha',
          message: `检测到验证码: ${indicator}`,
          canBypass: this.config.captcha?.autoSolve || false
        };
      }
    }

    return { detected: false, type: 'captcha', message: '', canBypass: false };
  }

  detectIpBlock(content: string, title: string): AntiCrawlerResult {
    const indicators = this.config.ipBlock?.indicators || [];
    
    for (const indicator of indicators) {
      if (content.includes(indicator) || title.includes(indicator)) {
        return {
          detected: true,
          type: 'ip_block',
          message: `检测到IP封禁: ${indicator}`,
          canBypass: true,
          estimatedWaitTime: this.config.ipBlock?.delay || 60000
        };
      }
    }

    return { detected: false, type: 'ip_block', message: '', canBypass: true };
  }

  detectRateLimit(content: string, title: string): AntiCrawlerResult {
    const rateLimitIndicators = [
      'rate limit',
      'too many requests',
      '请求过于频繁',
      '访问频率过高',
      '429',
      'slow down'
    ];

    for (const indicator of rateLimitIndicators) {
      if (content.toLowerCase().includes(indicator.toLowerCase()) || 
          title.toLowerCase().includes(indicator.toLowerCase())) {
        return {
          detected: true,
          type: 'rate_limit',
          message: `检测到频率限制: ${indicator}`,
          canBypass: true,
          estimatedWaitTime: 30000
        };
      }
    }

    return { detected: false, type: 'rate_limit', message: '', canBypass: true };
  }

  async isCloudflareBlocked(): Promise<boolean> {
    try {
      // 检查WebView是否已准备好
      if (!this.isWebViewReady()) {
        logger.warn(TAG, 'WebView未准备好，跳过CF检测');
        return false; // WebView未准备好时返回false，避免无限等待
      }
      
      const content = await this.getPageContent();
      const title = await this.getPageTitle();
      const result = this.detectCloudflare(content, title);
      return result.detected;
    } catch (error) {
      logger.error(TAG, '检查Cloudflare状态时发生错误' + error);
      return false; // 出错时返回false，避免无限等待
    }
  }

  async isIpBlocked(): Promise<boolean> {
    try {
      const content = await this.getPageContent();
      const title = await this.getPageTitle();
      const result = this.detectIpBlock(content, title);
      return result.detected;
    } catch (error) {
      logger.error(TAG, '检查IP封禁状态时发生错误' + error);
      return true; // 出错时假设仍被封禁
    }
  }

  async waitForCloudflarePass(): Promise<void> {
    // 先尝试点击CF验证按钮
    await this.clickCloudflareButton();
    // 等待验证完成
    await this.sleep(5000);
  }

  async clickCloudflareButton(): Promise<void> {
    try {
      logger.info(TAG, '尝试点击Cloudflare验证按钮');
      // 尝试点击各种可能的CF验证按钮
      await this.executeScript(`
        (function() {
          // Turnstile iframe 中的复选框
          const turnstileIframe = document.querySelector('iframe[src*="challenges.cloudflare.com"]');
          if (turnstileIframe) {
            try {
              const iframeDoc = turnstileIframe.contentDocument || turnstileIframe.contentWindow.document;
              const checkbox = iframeDoc.querySelector('input[type="checkbox"]');
              if (checkbox) {
                checkbox.click();
                console.log('[CF] 点击了Turnstile复选框');
                return;
              }
            } catch(e) {
              console.log('[CF] 无法访问iframe内容');
            }
          }
          
          // 点击 Turnstile 容器
          const turnstileContainer = document.querySelector('.cf-turnstile, [data-sitekey]');
          if (turnstileContainer) {
            turnstileContainer.click();
            console.log('[CF] 点击了Turnstile容器');
            return;
          }
          
          // 点击验证按钮
          const verifyButtons = document.querySelectorAll(
            'input[type="button"][value*="Verify"], ' +
            'button:contains("Verify"), ' +
            '.challenge-form input[type="submit"], ' +
            '#challenge-form input[type="submit"], ' +
            '.cb-lb, ' +
            'input[type="checkbox"]'
          );
          for (let btn of verifyButtons) {
            if (btn.offsetParent !== null) {
              btn.click();
              console.log('[CF] 点击了验证按钮');
              return;
            }
          }
          
          // 尝试点击页面中间区域（某些CF验证需要）
          const centerX = window.innerWidth / 2;
          const centerY = window.innerHeight / 2;
          const element = document.elementFromPoint(centerX, centerY);
          if (element && element.tagName !== 'BODY' && element.tagName !== 'HTML') {
            element.click();
            console.log('[CF] 点击了页面中心元素');
          }
        })();
      `);
      await this.sleep(1000); // 等待点击生效
    } catch (error) {
      logger.error(TAG, '点击Cloudflare验证按钮失败: ' + error);
    }
  }

  async refreshPage(): Promise<void> {
    try {
      this.webviewController.refresh();
      await this.sleep(3000); // 等待页面加载
    } catch (error) {
      logger.error(TAG, '刷新页面失败' + error);
    }
  }

  async detectCaptchaType(): Promise<'recaptcha' | 'hcaptcha' | 'image' | 'text' | 'unknown'> {
    try {
      const hasRecaptcha = await this.executeScript(`
        document.querySelector('.g-recaptcha, #recaptcha, .recaptcha') !== null
      `) as boolean;

      if (hasRecaptcha) return 'recaptcha';

      const hasHcaptcha = await this.executeScript(`
        document.querySelector('.h-captcha, #hcaptcha, .hcaptcha') !== null
      `) as boolean;

      if (hasHcaptcha) return 'hcaptcha';

      const hasImageCaptcha = await this.executeScript(`
        document.querySelector('img[src*="captcha"], .captcha-image') !== null
      `) as boolean;

      if (hasImageCaptcha) return 'image';

      const hasTextCaptcha = await this.executeScript(`
        document.querySelector('input[name*="captcha"], .captcha-input') !== null
      `) as boolean;

      if (hasTextCaptcha) return 'text';

      return 'unknown';

    } catch (error) {
      logger.error(TAG, '检测验证码类型失败' + error);
      return 'unknown';
    }
  }

  async autoSolveCaptcha(type: string): Promise<CaptchaResult> {
    logger.warn(TAG, '自动解决验证码功能需要第三方服务支持');
    return {
      detected: true,
      type: type as 'recaptcha' | 'hcaptcha' | 'image' | 'text' | 'unknown',
      solved: false,
      error: '自动解决验证码需要接入第三方验证码识别服务，本地版本不自动提交验证码'
    };
  }

  async manualSolveCaptcha(type: string, timeout: number): Promise<CaptchaResult> {
    // 手动处理验证码，等待用户操作
    logger.info(TAG, `请手动解决${type}验证码，等待${timeout}ms`);
    
    const startTime = Date.now();
    while (Date.now() - startTime < timeout) {
      await this.sleep(2000);
      
      // 检查验证码是否已解决
      const captchaStillExists = await this.detectCaptchaType() !== 'unknown';
      if (!captchaStillExists) {
        return {
          detected: true,
          type: type as 'recaptcha' | 'hcaptcha' | 'image' | 'text' | 'unknown',
          solved: true
        };
      }
    }

    return {
      detected: true,
      type: type as 'recaptcha' | 'hcaptcha' | 'image' | 'text' | 'unknown',
      solved: false,
      error: '手动解决验证码超时'
    };
  }

  /**
   * 检查WebView是否已准备好
   */
  private isWebViewReady(): boolean {
    try {
      // 尝试获取URL来检查WebView是否已关联
      this.webviewController.getUrl();
      return true;
    } catch (error) {
      return false;
    }
  }

  async executeScript(script: string): Promise<Object> {
    // 检查WebView是否已准备好
    if (!this.isWebViewReady()) {
      logger.warn(TAG, 'WebView未准备好，无法执行脚本');
      return '';
    }
    
    return new Promise((resolve, reject) => {
      this.webviewController.runJavaScript(script, (error, result) => {
        if (error) {
          reject(error);
        } else {
          resolve(result);
        }
      });
    });
  }

  async sleep(ms: number): Promise<void> {
    return new Promise(resolve => setTimeout(resolve, ms));
  }
}
