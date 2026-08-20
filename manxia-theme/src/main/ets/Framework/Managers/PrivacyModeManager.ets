import { userAuth } from '@kit.UserAuthenticationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { ISettingsManagerFacade, SettingsManagerHolder } from 'manxia_core/src/main/ets/Framework/Contracts/ISettingsManagerFacade';
import { SettingKeys } from 'manxia_core/src/main/ets/Framework/Contracts/SettingKeys';
import { ThemeManager, ThemeType } from 'manxia_theme/src/main/ets/Framework/Managers/ThemeManager';

const TAG = 'PrivacyModeManager';

/**
 * 隐私模式管理器
 * 负责管理隐私书库的验证和状态
 */
export class PrivacyModeManager {
  private static instance: PrivacyModeManager | null = null;
  private isPrivacyMode: boolean = false;
  private listeners: Set<(isPrivacyMode: boolean) => void> = new Set();
  private settingsManager: ISettingsManagerFacade = SettingsManagerHolder.get();
  private themeManager: ThemeManager = ThemeManager.getInstance();
  private previousTheme: ThemeType = ThemeType.DARK;

  private constructor() {
    this.settingsManager = SettingsManagerHolder.get();
  }

  public static getInstance(): PrivacyModeManager {
    if (!PrivacyModeManager.instance) {
      PrivacyModeManager.instance = new PrivacyModeManager();
    }
    return PrivacyModeManager.instance;
  }

  /**
   * 检查设备是否支持生物识别
   */
  public async checkBiometricSupport(): Promise<boolean> {
    try {
      userAuth.getAvailableStatus(userAuth.UserAuthType.FINGERPRINT, userAuth.AuthTrustLevel.ATL1);
      logger.info(TAG, '设备支持指纹识别');
      return true;
    } catch (error) {
      logger.error(TAG, `生物识别不支持: ${JSON.stringify(error)}`);
      return false;
    }
  }

  /**
   * 启动生物识别验证
   * 基于HarmonyOS官方文档的正确实现（API 12+）
   */
  public async authenticateWithBiometric(): Promise<boolean> {
    return new Promise<boolean>((resolve) => {
      try {
        logger.info(TAG, '开始生物识别验证');
        
        // 生成随机challenge
        const rand = cryptoFramework.createRandom();
        const len: number = 16;
        let randData: Uint8Array | null = null;
        let retryCount = 0;
        while(retryCount < 3){
          randData = rand?.generateRandomSync(len)?.data;
          if(randData){
            break;
          }
          retryCount++;
        }
        if(!randData){
          logger.error(TAG, '生成随机challenge失败');
          resolve(false);
          return;
        }
        
        // 配置认证参数
        const authParam: userAuth.AuthParam = {
          challenge: randData,
          authType: [userAuth.UserAuthType.FINGERPRINT],
          authTrustLevel: userAuth.AuthTrustLevel.ATL1,
        };
        
        // 配置UI参数
        const widgetParam: userAuth.WidgetParam = {
          title: '隐私书库验证',
        };
        
        try {
          // 获取UserAuthInstance对象
          const userAuthInstance = userAuth.getUserAuthInstance(authParam, widgetParam);
          logger.info(TAG, '获取userAuth实例成功');
          
          // 订阅认证结果
          userAuthInstance.on('result', {
            onResult (result) {
              logger.info(TAG, `生物识别结果: ${JSON.stringify(result)}`);
              if (result.result === userAuth.UserAuthResultCode.SUCCESS) {
                logger.info(TAG, '生物识别验证成功');
                resolve(true);
              } else {
                logger.warn(TAG, `生物识别验证失败，错误码: ${result.result}`);
                resolve(false);
              }
            }
          });
          
          // 启动认证
          userAuthInstance.start();
          logger.info(TAG, '生物识别认证已启动');
          
        } catch (authError) {
          const err = authError as BusinessError;
          logger.error(TAG, `生物识别初始化失败: ${err.code} - ${err.message}`);
          logger.warn(TAG, '生物识别不可用，将使用密码验证');
          resolve(false);
        }
        
      } catch (error) {
        const err = error as BusinessError;
        logger.error(TAG, `生物识别验证异常: ${err.code} - ${err.message}`);
        resolve(false);
      }
    });
  }

  /**
   * 使用密码验证（备用方案）
   */
  public async authenticateWithPassword(password: string): Promise<boolean> {
    try {
      // 从设置中获取保存的密码哈希
      const savedPasswordHash: string = this.settingsManager.getString('privacy_password_hash', '');
      
      if (!savedPasswordHash) {
        logger.warn(TAG, '未设置隐私密码');
        return false;
      }

      // 简单的密码验证（实际应用中应该使用加密哈希）
      const passwordHash = this.hashPassword(password);
      const isValid = passwordHash === savedPasswordHash;
      
      if (isValid) {
        logger.info(TAG, '密码验证成功');
      } else {
        logger.warn(TAG, '密码验证失败');
      }
      
      return isValid;
    } catch (error) {
      logger.error(TAG, `密码验证异常: ${JSON.stringify(error)}`);
      return false;
    }
  }

  /**
   * 设置隐私密码
   */
  public async setPrivacyPassword(password: string): Promise<void> {
    const passwordHash = this.hashPassword(password);
    await this.settingsManager.setString('privacy_password_hash', passwordHash);
    logger.info(TAG, '隐私密码已设置');
  }

  /**
   * 检查是否已设置隐私密码
   */
  public hasPrivacyPassword(): boolean {
    const savedPasswordHash: string = this.settingsManager.getString('privacy_password_hash', '');
    return savedPasswordHash !== '';
  }

  /**
   * 简单的密码哈希（实际应用中应使用更安全的算法）
   */
  private hashPassword(password: string): string {
    // 这里使用简单的哈希，实际应用中应该使用 crypto 模块
    let hash = 0;
    for (let i = 0; i < password.length; i++) {
      const char = password.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash;
    }
    return hash.toString(16);
  }

  /**
   * 进入隐私模式
   */
  public async enterPrivacyMode(): Promise<boolean> {
    try {
      // 优先尝试生物识别
      const biometricSupported = await this.checkBiometricSupport();
      let authenticated = false;

      if (biometricSupported) {
        authenticated = await this.authenticateWithBiometric();
      }

      // 如果生物识别失败或不支持，返回false让UI显示密码输入
      if (!authenticated) {
        return false;
      }

      // 保存当前主题
      this.previousTheme = this.themeManager.getCurrentThemeSync();
      
      // 切换到隐私模式主题
      await this.themeManager.setTheme(ThemeType.PRIVACY);
      
      this.isPrivacyMode = true;
      this.notifyListeners(true);
      logger.info(TAG, '已进入隐私模式，主题已切换');
      return true;
    } catch (error) {
      logger.error(TAG, `进入隐私模式失败: ${JSON.stringify(error)}`);
      return false;
    }
  }

  /**
   * 使用密码进入隐私模式
   */
  public async enterPrivacyModeWithPassword(password: string): Promise<boolean> {
    const authenticated = await this.authenticateWithPassword(password);
    if (authenticated) {
      // 保存当前主题
      this.previousTheme = this.themeManager.getCurrentThemeSync();
      
      // 切换到隐私模式主题
      await this.themeManager.setTheme(ThemeType.PRIVACY);
      
      this.isPrivacyMode = true;
      this.notifyListeners(true);
      logger.info(TAG, '已通过密码进入隐私模式，主题已切换');
    }
    return authenticated;
  }

  /**
   * 退出隐私模式
   */
  public async exitPrivacyMode(): Promise<void> {
    // 恢复之前的主题
    await this.themeManager.setTheme(this.previousTheme);
    
    this.isPrivacyMode = false;
    this.notifyListeners(false);
    logger.info(TAG, '已退出隐私模式，主题已恢复');
  }

  /**
   * 获取当前是否处于隐私模式
   */
  public isInPrivacyMode(): boolean {
    return this.isPrivacyMode;
  }

  /**
   * 添加隐私模式状态监听器
   */
  public addListener(listener: (isPrivacy: boolean) => void): void {
    this.listeners.add(listener);
  }

  /**
   * 移除隐私模式状态监听器
   */
  public removeListener(listener: (isPrivacy: boolean) => void): void {
    this.listeners.delete(listener);
  }

  /**
   * 通知所有监听器
   */
  private notifyListeners(isPrivacy: boolean): void {
    this.listeners.forEach(listener => {
      try {
        listener(isPrivacy);
      } catch (error) {
        logger.error(TAG, `监听器执行失败: ${JSON.stringify(error)}`);
      }
    });
  }

  /**
   * 清除所有监听器
   */
  public clearListeners(): void {
    this.listeners.clear();
  }
}
