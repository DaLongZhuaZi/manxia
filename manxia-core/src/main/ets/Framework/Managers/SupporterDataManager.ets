import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { IProxyManagerFacade, ProxyManagerHolder } from 'manxia_core/src/main/ets/Framework/Contracts/ProxyManagerFacade';
import { ISettingsManagerFacade, SettingsManagerHolder } from 'manxia_core/src/main/ets/Framework/Contracts/ISettingsManagerFacade';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { util } from '@kit.ArkTS';

const TAG: string = 'SupporterDataManager';
const REMOTE_URL: string = 'https://raw.githubusercontent.com/DaLongZhuaZi/manxia/master/entry/src/main/resources/rawfile/supporters.json';
const ROUTES: string[] = ['', 'https://gh-proxy.org/', 'https://hk.gh-proxy.org/'];
const REFRESH_INTERVAL_MS: number = 6 * 60 * 60 * 1000;
const ROUTE_COOLDOWN_MS: number = 12 * 60 * 60 * 1000;

export class SupporterRecord {
  name: string = '';
  level: string = '';
}

class SupporterPayload {
  version: number = 1;
  supporters: SupporterRecord[] = [];
}

export class SupporterDataManager {
  private static instance: SupporterDataManager | null = null;
  private get settingsManager(): ISettingsManagerFacade { return SettingsManagerHolder.get(); }
  private refreshing: boolean = false;

  static getInstance(): SupporterDataManager {
    if (SupporterDataManager.instance === null) SupporterDataManager.instance = new SupporterDataManager();
    return SupporterDataManager.instance;
  }

  private constructor() {}

  async load(context: common.UIAbilityContext): Promise<SupporterRecord[]> {
    const cached: string = this.settingsManager.getString('supporters_remote_cache', '');
    const cachedRecords = this.parse(cached);
    if (cachedRecords.length > 0) return cachedRecords;
    try {
      const bytes: Uint8Array = await context.resourceManager.getRawFileContent('supporters.json');
      return this.parse(new util.TextDecoder('utf-8').decodeToString(bytes));
    } catch (error) {
      logger.warn(TAG, `读取本地支持者数据失败: ${String(error)}`);
      return [];
    }
  }

  async refreshSilently(context: common.UIAbilityContext): Promise<void> {
    logger.info(TAG, '进入支持者名单静默刷新检查');
    if (this.refreshing) {
      logger.info(TAG, '已有支持者名单刷新任务运行中，跳过本次检查');
      return;
    }
    const now: number = Date.now();
    const lastAttempt: number = this.settingsManager.getNumber('supporters_last_refresh_at', 0);
    if (now - lastAttempt < REFRESH_INTERVAL_MS) {
      const remainingMinutes: number = Math.ceil((REFRESH_INTERVAL_MS - (now - lastAttempt)) / 60000);
      logger.info(TAG, `支持者名单仍在刷新冷却期，跳过本次请求，剩余约 ${remainingMinutes} 分钟`);
      return;
    }
    this.refreshing = true;
    await this.settingsManager.setNumber('supporters_last_refresh_at', now);
    logger.info(TAG, `开始静默更新支持者名单，候选路由数量=${ROUTES.length}`);
    try {
      const preferred: number = this.settingsManager.getNumber('supporters_preferred_route', 0);
      for (let step = 0; step < ROUTES.length; step += 1) {
        const index: number = (preferred + step) % ROUTES.length;
        const failedUntil: number = this.settingsManager.getNumber(`supporters_route_${index}_failed_until`, 0);
        if (failedUntil > now) {
          logger.info(TAG, `跳过处于冷却期的支持者路由: index=${index}`);
          continue;
        }
        const routeUrl: string = `${ROUTES[index]}${REMOTE_URL}`;
        logger.info(TAG, `尝试支持者数据路由: index=${index}, kind=${index === 0 ? 'origin' : 'github_proxy'}`);
        const text = await this.request(routeUrl);
        if (this.parse(text).length > 0) {
          await this.settingsManager.setString('supporters_remote_cache', text);
          await this.settingsManager.setNumber('supporters_preferred_route', index);
          await this.settingsManager.setNumber(`supporters_route_${index}_failed_until`, 0);
          AppStorage.setOrCreate('supporters_data_revision', now);
          logger.info(TAG, `支持者名单静默更新成功: routeIndex=${index}, count=${this.parse(text).length}`);
          return;
        }
        logger.warn(TAG, `支持者路由返回无效数据，进入冷却: index=${index}`);
        await this.settingsManager.setNumber(`supporters_route_${index}_failed_until`, now + ROUTE_COOLDOWN_MS);
      }
    } catch (error) {
      logger.debug(TAG, `支持者数据静默更新未完成: ${String(error)}`);
    } finally {
      this.refreshing = false;
      logger.info(TAG, '支持者名单静默刷新检查结束');
    }
  }

  private async request(url: string): Promise<string> {
    const request = http.createHttp();
    try {
      const options: http.HttpRequestOptions = { method: http.RequestMethod.GET, connectTimeout: 3500, readTimeout: 5000 };
      const proxy: IProxyManagerFacade = ProxyManagerHolder.get();
      if (proxy.isEnabled()) await proxy.applyToHttpOptions(options, url);
      const response = await request.request(url, options);
      if (response.responseCode !== 200) {
        logger.warn(TAG, `支持者路由 HTTP 状态异常: code=${response.responseCode}`);
        return '';
      }
      return typeof response.result === 'string' ? response.result : JSON.stringify(response.result);
    } catch (error) {
      logger.debug(TAG, `支持者路由不可用: ${url}, ${String(error)}`);
      return '';
    } finally {
      request.destroy();
    }
  }

  private parse(text: string): SupporterRecord[] {
    if (!text) return [];
    try {
      const payload = SafeUtils.parseObj(text) as SupporterPayload;
      if (!payload || !Array.isArray(payload.supporters)) return [];
      const result: SupporterRecord[] = [];
      for (const item of payload.supporters) {
        if (item && item.name && item.name.trim().length > 0) result.push(item);
      }
      return result;
    } catch (error) {
      logger.debug(TAG, `支持者数据解析失败: ${String(error)}`);
      return [];
    }
  }
}
