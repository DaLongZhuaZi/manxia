import { bundleManager } from '@kit.AbilityKit';
import { deviceInfo, BusinessError } from '@kit.BasicServicesKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

interface AppBaseInfo {
  bundleName: string;
  appId: string;
  versionName: string;
  versionCode: number;
  label: string;
  targetApi: number;
  compatibleApi: number;
}

interface SignatureInfoAccess {
  appId?: string;
  appIdentifier?: string;
  fingerprint?: string;
}

interface ApplicationInfoAccess {
  label?: string;
  minAPIVersion?: number;
  targetAPIVersion?: number;
}

interface BundleInfoAccess {
  name?: string;
  versionName?: string;
  versionCode?: number;
  hapModulesInfo?: bundleManager.HapModuleInfo[];
  label?: string;
  applicationInfo?: ApplicationInfoAccess;
  signatureInfo?: SignatureInfoAccess;
}

export class AppInfoManager {
  private static instance: AppInfoManager | null = null;
  private cachedBundleInfo: BundleInfoAccess | undefined = undefined;
  private cacheTimestamp: number = 0;

  private constructor() {}

  public static getInstance(): AppInfoManager {
    if (!AppInfoManager.instance) {
      AppInfoManager.instance = new AppInfoManager();
    }
    return AppInfoManager.instance;
  }

  public resetCache(): void {
    this.cachedBundleInfo = undefined;
    this.cacheTimestamp = 0;
  }

  private async ensureBundleInfo(): Promise<BundleInfoAccess> {
    if (this.cachedBundleInfo) {
      return this.cachedBundleInfo as BundleInfoAccess;
    }
    try {
      const flags: number = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION |
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_METADATA |
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_HAP_MODULE |
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_SIGNATURE_INFO;
      const info = await bundleManager.getBundleInfoForSelf(flags);
      const access = info as BundleInfoAccess;
      this.cachedBundleInfo = access as BundleInfoAccess;
      this.cacheTimestamp = Date.now();
      logger.info('AppInfoManager', '应用BundleInfo已加载');
      return access as BundleInfoAccess;
    } catch (error) {
      const e = error as BusinessError;
      logger.error('AppInfoManager', '获取BundleInfo失败: ' + e.message);
      throw new Error('获取BundleInfo失败');
    }
  }

  public async getVersionName(): Promise<string> {
    try {
      const info = await this.ensureBundleInfo();
      const name = info.versionName !== undefined ? info.versionName as string : '';
      return name;
    } catch (error) {
      const e = error as Error;
      logger.error('AppInfoManager', '获取版本名失败: ' + e.message);
      return '';
    }
  }

  public async getVersionCode(): Promise<number> {
    try {
      const info = await this.ensureBundleInfo();
      const code = info.versionCode !== undefined ? info.versionCode as number : 0;
      return code;
    } catch (error) {
      const e = error as Error;
      logger.error('AppInfoManager', '获取版本号失败: ' + e.message);
      return 0;
    }
  }

  public async getBundleName(): Promise<string> {
    try {
      const info = await this.ensureBundleInfo();
      const name = info.name !== undefined ? info.name as string : '';
      return name;
    } catch (error) {
      const e = error as Error;
      logger.error('AppInfoManager', '获取bundleName失败: ' + e.message);
      return '';
    }
  }

  public async getLabel(): Promise<string> {
    try {
      const info = await this.ensureBundleInfo();
      if (info.applicationInfo && info.applicationInfo.label !== undefined) {
        return info.applicationInfo.label as string;
      }
      if (info.label !== undefined) {
        return info.label as string;
      }
      return '';
    } catch (error) {
      const e = error as Error;
      logger.error('AppInfoManager', '获取应用名称失败: ' + e.message);
      return '';
    }
  }

  public async getTargetApi(): Promise<number> {
    try {
      const info = await this.ensureBundleInfo();
      if (info.applicationInfo && info.applicationInfo.targetAPIVersion !== undefined) {
        return info.applicationInfo.targetAPIVersion as number;
      }
      return 0;
    } catch (error) {
      const e = error as Error;
      logger.error('AppInfoManager', '获取targetApi失败: ' + e.message);
      return 0;
    }
  }

  public async getCompatibleApi(): Promise<number> {
    try {
      const info = await this.ensureBundleInfo();
      if (info.applicationInfo && info.applicationInfo.minAPIVersion !== undefined) {
        return info.applicationInfo.minAPIVersion as number;
      }
      return 0;
    } catch (error) {
      const e = error as Error;
      logger.error('AppInfoManager', '获取compatibleApi失败: ' + e.message);
      return 0;
    }
  }

  public async getAppBaseInfo(): Promise<AppBaseInfo> {
    try {
      const info = await this.ensureBundleInfo();
      const bundleName = info.name !== undefined ? info.name as string : '';
      const versionName = info.versionName !== undefined ? info.versionName as string : '';
      const versionCode = info.versionCode !== undefined ? info.versionCode as number : 0;
      const label = info.applicationInfo && info.applicationInfo.label !== undefined ? info.applicationInfo.label as string : (info.label !== undefined ? info.label as string : '');
      const targetApi = info.applicationInfo && info.applicationInfo.targetAPIVersion !== undefined ? info.applicationInfo.targetAPIVersion as number : 0;
      const compatibleApi = info.applicationInfo && info.applicationInfo.minAPIVersion !== undefined ? info.applicationInfo.minAPIVersion as number : 0;
      const appId = info.signatureInfo && info.signatureInfo.appId !== undefined ? info.signatureInfo.appId as string : '';
      const base: AppBaseInfo = {
        bundleName: bundleName,
        appId: appId,
        versionName: versionName,
        versionCode: versionCode,
        label: label,
        targetApi: targetApi,
        compatibleApi: compatibleApi
      } as AppBaseInfo;
      return base;
    } catch (error) {
      const e = error as Error;
      logger.error('AppInfoManager', '获取基础信息失败: ' + e.message);
      const base: AppBaseInfo = {
        bundleName: '',
        appId: '',
        versionName: '',
        versionCode: 0,
        label: '',
        targetApi: 0,
        compatibleApi: 0
      } as AppBaseInfo;
      return base;
    }
  }

  public getSystemDisplayVersion(): string {
    try {
      const ver = deviceInfo.displayVersion as string;
      return ver;
    } catch (error) {
      const e = error as Error;
      logger.error('AppInfoManager', '获取系统版本失败: ' + e.message);
      return '';
    }
  }
}

export const appInfoManager = AppInfoManager.getInstance();