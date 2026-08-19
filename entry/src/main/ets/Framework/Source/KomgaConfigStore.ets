import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';
import { preferences } from '@kit.ArkData';
import { KomgaConfig, KomgaInstanceConfig, KOMGA_DEFAULT_CHAPTER_TEMPLATE } from './KomgaModels';
import { getContext } from '../../GlobalContext';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const STORE_NAME: string = 'komga_config';
const CONFIG_KEY: string = 'config_json';
const TAG: string = 'KomgaConfigStore';

function getKomgaPreferencesStore() {
  return preferences.getPreferencesSync(getContext(), { name: STORE_NAME });
}

function createInstanceId(): string {
  return `komga_${Date.now()}_${Math.floor(Math.random() * 100000)}`;
}

function normalizeAuthMode(value: string): 'NONE' | 'BASIC' | 'API_KEY' {
  if (value === 'BASIC' || value === 'API_KEY') {
    return value;
  }
  return 'NONE';
}

function normalizeInstance(raw: Record<string, Object> | null | undefined): KomgaInstanceConfig {
  if (!raw) {
    return createDefaultKomgaInstance();
  }

  const data: Record<string, Object> = raw;
  const instanceId = typeof data['id'] === 'string' && String(data['id']).length > 0
    ? String(data['id'])
    : createInstanceId();

  return {
    id: instanceId,
    displayName: typeof data['displayName'] === 'string' ? String(data['displayName']) : '',
    serverUrl: typeof data['serverUrl'] === 'string' ? String(data['serverUrl']) : '',
    authMode: normalizeAuthMode(typeof data['authMode'] === 'string' ? String(data['authMode']) : 'NONE'),
    username: typeof data['username'] === 'string' ? String(data['username']) : '',
    password: typeof data['password'] === 'string' ? String(data['password']) : '',
    apiKey: typeof data['apiKey'] === 'string' ? String(data['apiKey']) : '',
    defaultLibraryIds: Array.isArray(data['defaultLibraryIds'])
      ? (data['defaultLibraryIds'] as Object[]).map(item => String(item))
      : [],
    chapterTitleTemplate: typeof data['chapterTitleTemplate'] === 'string' && String(data['chapterTitleTemplate']).trim().length > 0
      ? String(data['chapterTitleTemplate'])
      : KOMGA_DEFAULT_CHAPTER_TEMPLATE,
    enabled: typeof data['enabled'] === 'boolean' ? Boolean(data['enabled']) : true
  };
}

export function createDefaultKomgaInstance(): KomgaInstanceConfig {
  return {
    id: createInstanceId(),
    displayName: '',
    serverUrl: '',
    authMode: 'NONE',
    username: '',
    password: '',
    apiKey: '',
    defaultLibraryIds: [],
    chapterTitleTemplate: KOMGA_DEFAULT_CHAPTER_TEMPLATE,
    enabled: true
  };
}

export function createEmptyKomgaConfig(): KomgaConfig {
  const instance = createDefaultKomgaInstance();
  return {
    instances: [instance],
    currentInstanceId: instance.id,
    useBrowsePageAsEntry: true
  };
}

export function normalizeKomgaConfig(raw: Record<string, Object> | null | undefined): KomgaConfig {
  if (!raw) {
    return createEmptyKomgaConfig();
  }

  const data: Record<string, Object> = raw;
  const rawInstances: Record<string, Object>[] = Array.isArray(data['instances']) ? data['instances'] as Record<string, Object>[] : [];
  const instances = rawInstances.map((item: Record<string, Object>) => normalizeInstance(item));
  const normalizedInstances = instances.length > 0 ? instances : [createDefaultKomgaInstance()];
  const currentInstanceId = typeof data['currentInstanceId'] === 'string'
    ? String(data['currentInstanceId'])
    : normalizedInstances[0].id;
  const currentExists = normalizedInstances.some(item => item.id === currentInstanceId);

  return {
    instances: normalizedInstances,
    currentInstanceId: currentExists ? currentInstanceId : normalizedInstances[0].id,
    useBrowsePageAsEntry: typeof data['useBrowsePageAsEntry'] === 'boolean' ? Boolean(data['useBrowsePageAsEntry']) : true
  };
}

function normalizeKomgaInstanceConfig(instance: KomgaInstanceConfig): KomgaInstanceConfig {
  const instanceId = instance.id.length > 0 ? instance.id : createInstanceId();
  const libraryIds: string[] = [];
  for (let i = 0; i < instance.defaultLibraryIds.length; i++) {
    libraryIds.push(instance.defaultLibraryIds[i]);
  }

  return {
    id: instanceId,
    displayName: instance.displayName,
    serverUrl: instance.serverUrl,
    authMode: normalizeAuthMode(instance.authMode),
    username: instance.username,
    password: instance.password,
    apiKey: instance.apiKey,
    defaultLibraryIds: libraryIds,
    chapterTitleTemplate: instance.chapterTitleTemplate.trim().length > 0
      ? instance.chapterTitleTemplate
      : KOMGA_DEFAULT_CHAPTER_TEMPLATE,
    enabled: instance.enabled
  };
}

function normalizeKomgaConfigForSave(config: KomgaConfig): KomgaConfig {
  const instances: KomgaInstanceConfig[] = config.instances.map((item: KomgaInstanceConfig): KomgaInstanceConfig => {
    return normalizeKomgaInstanceConfig(item);
  });
  const normalizedInstances = instances.length > 0 ? instances : [createDefaultKomgaInstance()];
  const currentInstanceId = config.currentInstanceId.length > 0
    ? config.currentInstanceId
    : normalizedInstances[0].id;
  const currentExists = normalizedInstances.some((item: KomgaInstanceConfig): boolean => item.id === currentInstanceId);

  return {
    instances: normalizedInstances,
    currentInstanceId: currentExists ? currentInstanceId : normalizedInstances[0].id,
    useBrowsePageAsEntry: config.useBrowsePageAsEntry
  };
}

export async function loadKomgaConfig(): Promise<KomgaConfig> {
  try {
    const store = getKomgaPreferencesStore();
    const rawText = store.getSync(CONFIG_KEY, '') as string;
    if (!rawText) {
      return createEmptyKomgaConfig();
    }
    return normalizeKomgaConfig(SafeUtils.parseObj(rawText) as Record<string, Object>);
  } catch (error) {
    logger.error(TAG, `加载 Komga 配置失败: ${String(error)}`);
    return createEmptyKomgaConfig();
  }
}

export async function saveKomgaConfig(config: KomgaConfig): Promise<boolean> {
  try {
    const store = getKomgaPreferencesStore();
    const normalized = normalizeKomgaConfigForSave(config);
    store.putSync(CONFIG_KEY, JSON.stringify(normalized));
    await store.flush();
    return true;
  } catch (error) {
    logger.error(TAG, `保存 Komga 配置失败: ${String(error)}`);
    return false;
  }
}

export function getKomgaInstanceDisplayName(instance: KomgaInstanceConfig): string {
  const displayName = instance.displayName.trim();
  if (displayName.length > 0) {
    return displayName;
  }

  const serverUrl = instance.serverUrl.trim();
  if (serverUrl.length <= 0) {
    return '未命名实例';
  }

  return serverUrl.replace(/^https?:\/\//, '').replace(/\/+$/, '');
}
