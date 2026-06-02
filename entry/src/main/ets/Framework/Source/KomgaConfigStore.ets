import { SafeUtils } from '../../Utils/SafeUtils';
import { preferences } from '@kit.ArkData';
import { KomgaConfig, KomgaInstanceConfig, KOMGA_DEFAULT_CHAPTER_TEMPLATE } from './KomgaModels';
import { getContext } from '../../GlobalContext';
import { logger } from '../../Utils/Logger';

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

function normalizeInstance(raw: ESObject | null | undefined): KomgaInstanceConfig {
  if (!raw) {
    return createDefaultKomgaInstance();
  }

  const data: ESObject = raw;
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

export function normalizeKomgaConfig(raw: ESObject | null | undefined): KomgaConfig {
  if (!raw) {
    return createEmptyKomgaConfig();
  }

  const data: ESObject = raw;
  const rawInstances: ESObject[] = Array.isArray(data['instances']) ? data['instances'] as ESObject[] : [];
  const instances = rawInstances.map((item: ESObject) => normalizeInstance(item));
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

export async function loadKomgaConfig(): Promise<KomgaConfig> {
  try {
    const store = getKomgaPreferencesStore();
    const rawText = store.getSync(CONFIG_KEY, '') as string;
    if (!rawText) {
      return createEmptyKomgaConfig();
    }
    return normalizeKomgaConfig(SafeUtils.parseObj(rawText) as ESObject);
  } catch (error) {
    logger.error(TAG, `加载 Komga 配置失败: ${String(error)}`);
    return createEmptyKomgaConfig();
  }
}

export async function saveKomgaConfig(config: KomgaConfig): Promise<boolean> {
  try {
    const store = getKomgaPreferencesStore();
    const normalized = normalizeKomgaConfig(config as ESObject);
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
