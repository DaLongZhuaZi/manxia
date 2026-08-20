import { common, Want } from '@kit.AbilityKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';

const TAG: string = 'ExternalImportNavigationCoordinator';
const APP_BUNDLE_NAME: string = 'com.dlzz.manxia';
const ENTRY_ABILITY_NAME: string = 'EntryAbility';
const PENDING_NAVIGATION_KEY: string = 'pendingExternalImportNavigation';
const NAVIGATION_TRIGGER_KEY: string = 'externalImportNavigationTrigger';

export enum ExternalImportNavigationTarget {
  NONE = '',
  DATA_MANAGEMENT = 'DataManagementPage',
  BACKUP = 'BackupPage',
  AVIF_TEST = 'AvifTestPage',
  SOURCE_MANAGEMENT = 'SourceManagementPage',
  NOVEL_SOURCE_MANAGEMENT = 'NovelSourceManagementPage',
  FONT_SETTINGS = 'FontSettingsSubPage'
}

export enum ExternalImportNavigationSource {
  EXTERNAL_FILE_TASK = 'external_file_task',
  MAIN_MENU_FALLBACK = 'main_menu_fallback'
}

export class ExternalImportNavigationPayload {
  public target: string = '';
  public source: string = '';
  public title: string = '';
  public taskInstanceId: string = '';
  public createdAt: number = 0;
}

export class ExternalImportNavigationRequest {
  public target: ExternalImportNavigationTarget = ExternalImportNavigationTarget.NONE;
  public source: ExternalImportNavigationSource = ExternalImportNavigationSource.EXTERNAL_FILE_TASK;
  public title: string = '';
  public taskInstanceId: string = '';
}

export class ExternalImportNavigationCoordinator {
  public static requestNavigation(request: ExternalImportNavigationRequest): void {
    if (request.target === ExternalImportNavigationTarget.NONE) {
      return;
    }

    const payload = new ExternalImportNavigationPayload();
    payload.target = request.target;
    payload.source = request.source;
    payload.title = request.title;
    payload.taskInstanceId = request.taskInstanceId;
    payload.createdAt = Date.now();

    AppStorage.setOrCreate(PENDING_NAVIGATION_KEY, SafeUtils.stringifyJson(payload, ''));
    const currentTrigger: number = AppStorage.get<number>(NAVIGATION_TRIGGER_KEY) || 0;
    AppStorage.setOrCreate(NAVIGATION_TRIGGER_KEY, currentTrigger + 1);
    logger.info(TAG, `已登记外部导入完成跳转: target=${payload.target}, source=${payload.source}, task=${payload.taskInstanceId}`);
  }

  public static consumePendingNavigation(): ExternalImportNavigationPayload | null {
    const rawPayload: string = AppStorage.get<string>(PENDING_NAVIGATION_KEY) || '';
    if (rawPayload.trim().length <= 0) {
      return null;
    }
    AppStorage.delete(PENDING_NAVIGATION_KEY);
    const parsed = SafeUtils.parseOptional<ExternalImportNavigationPayload>(rawPayload);
    if (!parsed) {
      logger.warn(TAG, '外部导入完成跳转参数解析失败');
      return null;
    }
    return ExternalImportNavigationCoordinator.normalizePayload(parsed);
  }

  public static peekPendingNavigationTarget(): string {
    const rawPayload: string = AppStorage.get<string>(PENDING_NAVIGATION_KEY) || '';
    if (rawPayload.trim().length <= 0) {
      return '';
    }
    const parsed = SafeUtils.parseOptional<ExternalImportNavigationPayload>(rawPayload);
    if (!parsed) {
      return '';
    }
    return parsed.target ?? '';
  }

  public static async bringEntryAbilityToFront(
    abilityContext: common.UIAbilityContext | null,
    sourceTag: string
  ): Promise<boolean> {
    if (!abilityContext) {
      logger.warn(TAG, `拉起主窗口失败: source=${sourceTag}, reason=AbilityContext unavailable`);
      return false;
    }
    const want: Want = {
      bundleName: APP_BUNDLE_NAME,
      abilityName: ENTRY_ABILITY_NAME
    };
    try {
      await abilityContext.startAbility(want);
      logger.info(TAG, `已拉起主窗口消费外部导入跳转: source=${sourceTag}`);
      return true;
    } catch (error) {
      logger.warn(TAG, `拉起主窗口失败: source=${sourceTag}, reason=${String(error)}`);
      return false;
    }
  }

  public static async closeCurrentAbility(
    abilityContext: common.UIAbilityContext | null,
    sourceTag: string
  ): Promise<void> {
    if (!abilityContext) {
      return;
    }
    try {
      await abilityContext.terminateSelf();
      logger.info(TAG, `已关闭外部导入任务窗口: source=${sourceTag}`);
    } catch (error) {
      logger.warn(TAG, `关闭外部导入任务窗口失败: source=${sourceTag}, reason=${String(error)}`);
    }
  }

  private static normalizePayload(source: ExternalImportNavigationPayload): ExternalImportNavigationPayload {
    const payload = new ExternalImportNavigationPayload();
    payload.target = source.target ?? '';
    payload.source = source.source ?? '';
    payload.title = source.title ?? '';
    payload.taskInstanceId = source.taskInstanceId ?? '';
    payload.createdAt = typeof source.createdAt === 'number' ? source.createdAt : Date.now();
    return payload;
  }
}
