// 文件路径: entry/src/main/ets/Framework/Services/FeedbackTurnstileBridge.ets
/**
 * 反馈中心 Turnstile 验证回传桥。
 *
 * 反馈中心的安全验证改为在系统浏览器中完成（ArkWeb 内嵌 WebView 在当前网络
 * 环境下无法通过 Cloudflare Turnstile 挑战），验证页拿到 token 后通过
 * manxia://turnstile?token=... Deep Link 跳回应用，由 EntryAbility 把 token
 * 交给本单例，反馈页面再从这里取回 token 继续提交。
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG = 'FeedbackTurnstileBridge';
const MIN_TOKEN_LENGTH: number = 20;

export class FeedbackTurnstileBridge {
  private static instance: FeedbackTurnstileBridge | null = null;
  private pendingResolver: ((token: string) => void) | null = null;
  private pendingTimer: number = -1;

  private constructor() {}

  public static getInstance(): FeedbackTurnstileBridge {
    if (FeedbackTurnstileBridge.instance === null) {
      FeedbackTurnstileBridge.instance = new FeedbackTurnstileBridge();
    }
    return FeedbackTurnstileBridge.instance;
  }

  /**
   * 等待系统浏览器回传的 Turnstile token。
   * 超时或失败时以空字符串结束等待。
   */
  public waitForToken(timeoutMilliseconds: number): Promise<string> {
    this.settlePending('');
    return new Promise<string>((resolve) => {
      this.pendingResolver = resolve;
      this.pendingTimer = setTimeout((): void => {
        if (this.pendingResolver === resolve) {
          this.pendingResolver = null;
          this.pendingTimer = -1;
          resolve('');
          logger.warn(TAG, 'Turnstile 验证等待超时，已结束本次等待');
        }
      }, timeoutMilliseconds);
    });
  }

  /**
   * 由 EntryAbility 在收到 manxia://turnstile Deep Link 时调用。
   */
  public deliverTokenFromUri(uri: string): void {
    let token: string = '';
    const marker: string = 'token=';
    const markerIndex: number = uri.indexOf(marker);
    if (markerIndex >= 0) {
      try {
        token = decodeURIComponent(uri.substring(markerIndex + marker.length));
      } catch (error) {
        logger.warn(TAG, '解析 Turnstile token 失败: ' + String(error));
      }
    }
    if (token.length < MIN_TOKEN_LENGTH) {
      logger.warn(TAG, 'Turnstile token 无效（长度 ' + String(token.length) + '），忽略回传');
      return;
    }
    const resolver = this.pendingResolver;
    this.pendingResolver = null;
    if (this.pendingTimer !== -1) {
      clearTimeout(this.pendingTimer);
      this.pendingTimer = -1;
    }
    if (resolver !== null) {
      resolver(token);
      logger.info(TAG, 'Turnstile token 已送达反馈页面');
    } else {
      logger.warn(TAG, 'Turnstile token 回传时无等待方，已丢弃');
    }
  }

  /**
   * 放弃当前等待（新验证开始前调用），以空字符串结束旧等待。
   */
  public resetPending(): void {
    this.settlePending('');
  }

  private settlePending(token: string): void {
    const resolver = this.pendingResolver;
    this.pendingResolver = null;
    if (this.pendingTimer !== -1) {
      clearTimeout(this.pendingTimer);
      this.pendingTimer = -1;
    }
    if (resolver !== null) {
      resolver(token);
    }
  }
}
