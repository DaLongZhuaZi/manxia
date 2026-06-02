import { common } from '@kit.AbilityKit';
/**
 * 认证处理器
 * 处理JWT令牌、Cookie等认证方式
 */

import { validateJWT, isJWTExpired } from '../../Utils/JWTUtils';
import { logger } from '../../Utils/Logger';
import preferences from '@ohos.data.preferences';

const TAG = 'AuthenticationHandler';

/**
 * 认证配置
 */
export interface AuthenticationConfig {
  type: 'none' | 'basic' | 'bearer' | 'jwt' | 'cookie' | 'custom';
  loginUrl?: string;
  loginMethod?: string;
  tokenStorageKey?: string;
  tokenLeeway?: number;
  loginPayload?: Record<string, string>;
  tokenExtraction?: {
    type: 'json' | 'header';
    path?: string;
    header?: string;
  };
  requiresLogin?: boolean;
}

/**
 * 认证凭据
 */
export interface Credentials {
  username?: string;
  password?: string;
  token?: string;
  [key: string]: string | undefined;
}

/**
 * 认证处理器类
 */
export class AuthenticationHandler {
  private config: AuthenticationConfig;
  private sourceId: string;
  private preferencesStore: preferences.Preferences | null = null;

  constructor(config: AuthenticationConfig, sourceId: string) {
    this.config = config;
    this.sourceId = sourceId;
  }

  /**
   * 初始化Preferences存储
   */
  private async initPreferences(): Promise<void> {
    if (this.preferencesStore) {
      return;
    }

    try {
      const context = (this.getUIContext().getHostContext() as common.UIAbilityContext);
      this.preferencesStore = await preferences.getPreferences(context, 'auth_storage');
    } catch (error) {
      logger.error(TAG, `初始化Preferences失败: ${error}`);
      throw error;
    }
  }

  /**
   * 获取存储的令牌
   */
  async getStoredToken(): Promise<string | null> {
    try {
      await this.initPreferences();
      if (!this.preferencesStore) {
        return null;
      }

      const key = this.getTokenKey();
      const token = await this.preferencesStore.get(key, '') as string;
      return token || null;
    } catch (error) {
      logger.error(TAG, `获取存储令牌失败: ${error}`);
      return null;
    }
  }

  /**
   * 保存令牌
   */
  async saveToken(token: string): Promise<void> {
    try {
      await this.initPreferences();
      if (!this.preferencesStore) {
        throw new Error('Preferences未初始化');
      }

      const key = this.getTokenKey();
      await this.preferencesStore.put(key, token);
      await this.preferencesStore.flush();
      logger.info(TAG, `令牌已保存: ${this.sourceId}`);
    } catch (error) {
      logger.error(TAG, `保存令牌失败: ${error}`);
      throw error;
    }
  }

  /**
   * 清除令牌
   */
  async clearToken(): Promise<void> {
    try {
      await this.initPreferences();
      if (!this.preferencesStore) {
        return;
      }

      const key = this.getTokenKey();
      await this.preferencesStore.delete(key);
      await this.preferencesStore.flush();
      logger.info(TAG, `令牌已清除: ${this.sourceId}`);
    } catch (error) {
      logger.error(TAG, `清除令牌失败: ${error}`);
    }
  }

  /**
   * 获取令牌存储键
   */
  private getTokenKey(): string {
    return this.config.tokenStorageKey || `token_${this.sourceId}`;
  }

  /**
   * 验证令牌是否有效
   */
  async validateToken(token?: string): Promise<boolean> {
    try {
      const tokenToValidate = token || await this.getStoredToken();
      if (!tokenToValidate) {
        return false;
      }

      // 根据认证类型验证
      switch (this.config.type) {
        case 'jwt':
          const leeway = this.config.tokenLeeway || 10;
          return validateJWT(tokenToValidate, leeway);
        case 'bearer':
        case 'custom':
          // 简单检查令牌是否为空
          return tokenToValidate.trim().length > 0;
        default:
          return true;
      }
    } catch (error) {
      logger.error(TAG, `验证令牌失败: ${error}`);
      return false;
    }
  }

  /**
   * 检查令牌是否过期
   */
  async isTokenExpired(token?: string): Promise<boolean> {
    try {
      const tokenToCheck = token || await this.getStoredToken();
      if (!tokenToCheck) {
        return true;
      }

      // 只有JWT类型才检查过期
      if (this.config.type === 'jwt') {
        const leeway = this.config.tokenLeeway || 10;
        return isJWTExpired(tokenToCheck, leeway);
      }

      return false;
    } catch (error) {
      logger.error(TAG, `检查令牌过期失败: ${error}`);
      return true;
    }
  }

  /**
   * 获取有效的令牌（如果过期则返回null）
   */
  async getValidToken(): Promise<string | null> {
    try {
      const token = await this.getStoredToken();
      if (!token) {
        return null;
      }

      const isValid = await this.validateToken(token);
      if (!isValid) {
        logger.warn(TAG, `令牌无效，已清除: ${this.sourceId}`);
        await this.clearToken();
        return null;
      }

      return token;
    } catch (error) {
      logger.error(TAG, `获取有效令牌失败: ${error}`);
      return null;
    }
  }

  /**
   * 构建认证头
   */
  async buildAuthHeaders(token?: string): Promise<Record<string, string>> {
    const headers: Record<string, string> = {};

    try {
      const authToken = token || await this.getValidToken();
      if (!authToken) {
        if (this.config.requiresLogin) {
          throw new Error('需要登录');
        }
        return headers;
      }

      switch (this.config.type) {
        case 'bearer':
          headers['Authorization'] = `Bearer ${authToken}`;
          break;
        case 'jwt':
          headers['authorization'] = authToken;
          break;
        case 'custom':
          headers['Authorization'] = authToken;
          break;
        default:
          break;
      }

      return headers;
    } catch (error) {
      logger.error(TAG, `构建认证头失败: ${error}`);
      throw error;
    }
  }

  /**
   * 从响应中提取令牌
   */
  extractTokenFromResponse(response: ESObject): string | null {
    try {
      if (!this.config.tokenExtraction) {
        return null;
      }

      const extraction = this.config.tokenExtraction;

      if (extraction.type === 'json' && extraction.path) {
        // 使用JSONPath提取
        return this.extractByPath(response, extraction.path);
      } else if (extraction.type === 'header' && extraction.header) {
        // 从响应头提取
        const headers = response['headers'] as Record<string, string>;
        return headers?.[extraction.header] || null;
      }

      return null;
    } catch (error) {
      logger.error(TAG, `提取令牌失败: ${error}`);
      return null;
    }
  }

  /**
   * 通过路径提取值
   */
  private extractByPath(obj: ESObject, path: string): string | null {
    try {
      const parts = path.split('.');
      let current: ESObject = obj;

      for (const part of parts) {
        if (current && typeof current === 'object' && part in current) {
          current = current[part] as ESObject;
        } else {
          return null;
        }
      }

      return typeof current === 'string' ? current : null;
    } catch (error) {
      logger.error(TAG, `路径提取失败: ${error}`);
      return null;
    }
  }

  /**
   * 是否需要登录
   */
  requiresLogin(): boolean {
    return this.config.requiresLogin === true;
  }

  /**
   * 获取登录配置
   */
  getLoginConfig(): {
    url: string;
    method: string;
    payload: Record<string, string>;
  } | null {
    if (!this.config.loginUrl || !this.config.loginMethod) {
      return null;
    }

    return {
      url: this.config.loginUrl,
      method: this.config.loginMethod,
      payload: this.config.loginPayload || {}
    };
  }
}
