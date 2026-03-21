/**
 * 文本阅读器数据模型定义
 * 支持多种阅读模式、翻页动画、自定义背景和文字样式
 */

/**
 * 文本阅读模式枚举
 */
export enum TextReadingMode {
  SCROLL = 'SCROLL',           // 连续滚动模式
  PAGE = 'PAGE',               // 翻页模式
  AUTO_SCROLL = 'AUTO_SCROLL', // 自动滚动模式
  DUAL_PAGE = 'DUAL_PAGE'      // 双页模式（横屏左右双页）
}

/**
 * 文本阅读方向枚举
 */
export enum TextReadingDirection {
  HORIZONTAL = 'HORIZONTAL',   // 水平翻页（左右）
  VERTICAL = 'VERTICAL'        // 垂直翻页（上下）
}

/**
 * 文本翻页动画类型枚举
 */
export enum TextPageTurnAnimation {
  NONE = 'NONE',               // 无动画
  SLIDE = 'SLIDE',             // 滑动
  CURL = 'CURL',               // 拟真卷曲
  FADE = 'FADE'                // 淡入淡出
}

/**
 * 文字对齐方式枚举
 */
export enum TextAlignment {
  LEFT = 'LEFT',               // 左对齐
  CENTER = 'CENTER',           // 居中对齐
  RIGHT = 'RIGHT',             // 右对齐
  JUSTIFY = 'JUSTIFY'          // 两端对齐
}

/**
 * 背景类型枚举
 */
export enum BackgroundType {
  COLOR = 'COLOR',             // 纯色背景
  IMAGE = 'IMAGE',             // 图片背景
  GRADIENT = 'GRADIENT'        // 渐变背景
}

/**
 * 预设背景颜色
 */
export interface PresetBackground {
  /** 背景名称 */
  name: string;
  /** 背景颜色 */
  backgroundColor: string;
  /** 文字颜色 */
  textColor: string;
  /** 预览颜色（用于选择器） */
  previewColor: string;
}

/**
 * 预设背景列表
 */
export const PRESET_BACKGROUNDS: PresetBackground[] = [
  { name: '经典白', backgroundColor: '#FFFFFF', textColor: '#333333', previewColor: '#FFFFFF' },
  { name: '护眼黄', backgroundColor: '#F5F0E1', textColor: '#5D4037', previewColor: '#F5F0E1' },
  { name: '淡绿', backgroundColor: '#E8F5E9', textColor: '#2E7D32', previewColor: '#E8F5E9' },
  { name: '浅蓝', backgroundColor: '#E3F2FD', textColor: '#1565C0', previewColor: '#E3F2FD' },
  { name: '暖粉', backgroundColor: '#FCE4EC', textColor: '#C2185B', previewColor: '#FCE4EC' },
  { name: '深色', backgroundColor: '#1E1E1E', textColor: '#D4D4D4', previewColor: '#1E1E1E' },
  { name: '墨绿', backgroundColor: '#1B3B2F', textColor: '#C8E6C9', previewColor: '#1B3B2F' },
  { name: '深蓝', backgroundColor: '#1A237E', textColor: '#B3E5FC', previewColor: '#1A237E' }
];

/**
 * 自定义背景设置
 */
export interface CustomBackground {
  /** 背景类型 */
  type: BackgroundType;
  /** 背景颜色（当type为COLOR时使用） */
  color?: string;
  /** 背景图片路径（当type为IMAGE时使用） */
  imagePath?: string;
  /** 背景图片不透明度（0-1） */
  imageOpacity?: number;
  /** 渐变起始颜色（当type为GRADIENT时使用） */
  gradientStart?: string;
  /** 渐变结束颜色（当type为GRADIENT时使用） */
  gradientEnd?: string;
  /** 渐变角度（度） */
  gradientAngle?: number;
}

/**
 * 文字样式设置
 */
export interface TextStyleSettings {
  /** 字体大小（vp） */
  fontSize: number;
  /** 行高倍数（相对于字体大小） */
  lineHeight: number;
  /** 段落间距（vp） */
  paragraphSpacing: number;
  /** 首行缩进（em数，0表示不缩进） */
  firstLineIndent: number;
  /** 字间距（vp） */
  letterSpacing: number;
  /** 文字颜色 */
  textColor: string;
  /** 字体粗细 */
  fontWeight: number;
  /** 字体族名称 */
  fontFamily: string;
  /** 自定义字体文件路径（可选） */
  fontPath?: string;
  /** 文字对齐方式 */
  textAlignment: TextAlignment;
}

/**
 * 页面边距设置
 */
export interface PageMargins {
  /** 上边距（vp） */
  top: number;
  /** 下边距（vp） */
  bottom: number;
  /** 左边距（vp） */
  left: number;
  /** 右边距（vp） */
  right: number;
}

/**
 * 保存的背景图片信息
 */
export interface SavedBackgroundImage {
  /** 图片路径 */
  path: string;
  /** 添加时间 */
  addTime: number;
}

/**
 * 听书引擎类型
 */
export enum ReadAloudEngineType {
  SYSTEM = 'SYSTEM',
  LEGADO_COMPAT = 'LEGADO_COMPAT',
  REMOTE = 'REMOTE'
}

export interface RemoteReadAloudPresetConfig {
  endpoint: string;
  apiPath: string;
  apiKey: string;
  model: string;
  voice: string;
  stylePrompt: string;
  audioFormat: string;
  streamEnabled: boolean;
  prefetchSegments: number;
  connectTimeoutMs: number;
  readTimeoutMs: number;
  maxInputChars: number;
  reservedInputChars: number;
  minChunkChars: number;
  targetChunkChars: number;
  maxChunkChars: number;
  cacheAudioFiles: boolean;
  autoConcatAudio: boolean;
  customHeadersJson: string;
  extraBodyJson: string;
}

export interface RemoteReadAloudPreset {
  id: string;
  name: string;
  description: string;
  builtIn?: boolean;
  settings: RemoteReadAloudPresetConfig;
}

export interface RemoteReadAloudSettings extends RemoteReadAloudPresetConfig {
  activePresetId: string;
  presets: RemoteReadAloudPreset[];
}

export interface RemoteReadAloudChoiceOption {
  label: string;
  value: string;
}

export interface RemoteReadAloudStyleCategory {
  label: string;
  styles: string[];
}

interface RemoteReadAloudPresetSource {
  id?: string;
  name?: string;
  description?: string;
  builtIn?: boolean;
  settings?: Partial<RemoteReadAloudPresetConfig> | null;
  config?: Partial<RemoteReadAloudPresetConfig> | null;
  remote?: Partial<RemoteReadAloudPresetConfig> | null;
}

/**
 * 听书设置
 */
export interface ReadAloudSettings {
  /** 听书总开关 */
  enabled: boolean;
  /** 引擎类型 */
  engineType: ReadAloudEngineType;
  /** 语速（0.5-2.0） */
  speed: number;
  /** 音调（0.5-2.0） */
  pitch: number;
  /** 音量（0-1） */
  volume: number;
  /** 后台是否继续播放 */
  continueInBackground: boolean;
  /** 章节切换后是否自动继续 */
  autoPlayNextChapter: boolean;
  /** 手动翻页时是否自动暂停听书 */
  pauseOnManualPageTurn: boolean;
  /** 系统TTS音色语种（空字符串表示跟随系统默认） */
  voiceLanguage?: string;
  /** 系统TTS音色人设（-1 表示跟随系统默认） */
  voicePerson?: number;
  /** 系统TTS音色在线类型（0在线/1离线，-1表示跟随系统默认） */
  voiceOnline?: number;
  remote?: RemoteReadAloudSettings;
}

export const DEFAULT_REMOTE_READ_ALOUD_PRESET_ID: string = 'xiaomi_mimo_v2_tts';

const LEGACY_DEFAULT_REMOTE_READ_ALOUD_SETTINGS: RemoteReadAloudPresetConfig = {
  endpoint: '',
  apiPath: '/v1/audio/speech',
  apiKey: '',
  model: 'gpt-4o-mini-tts',
  voice: 'alloy',
  stylePrompt: '',
  audioFormat: 'mp3',
  streamEnabled: true,
  prefetchSegments: 2,
  connectTimeoutMs: 15000,
  readTimeoutMs: 120000,
  maxInputChars: 3000,
  reservedInputChars: 240,
  minChunkChars: 120,
  targetChunkChars: 540,
  maxChunkChars: 1200,
  cacheAudioFiles: true,
  autoConcatAudio: true,
  customHeadersJson: '',
  extraBodyJson: ''
};

export const DEFAULT_XIAOMI_MIMO_REMOTE_READ_ALOUD_CONFIG: RemoteReadAloudPresetConfig = {
  endpoint: 'https://api.xiaomimimo.com',
  apiPath: '/v1/chat/completions',
  apiKey: '',
  model: 'mimo-v2-tts',
  voice: 'mimo_default',
  stylePrompt: '',
  audioFormat: 'wav',
  streamEnabled: false,
  prefetchSegments: 2,
  connectTimeoutMs: 15000,
  readTimeoutMs: 120000,
  maxInputChars: 3000,
  reservedInputChars: 240,
  minChunkChars: 120,
  targetChunkChars: 540,
  maxChunkChars: 1200,
  cacheAudioFiles: true,
  autoConcatAudio: true,
  customHeadersJson: '',
  extraBodyJson: ''
};

export const DEFAULT_XIAOMI_MIMO_REMOTE_READ_ALOUD_PRESET: RemoteReadAloudPreset = {
  id: DEFAULT_REMOTE_READ_ALOUD_PRESET_ID,
  name: 'Xiaomi MiMo-V2-TTS',
  description: '小米 MiMo 默认预设，支持快捷音色与风格控制，填写 API Key 即可接入',
  builtIn: true,
  settings: DEFAULT_XIAOMI_MIMO_REMOTE_READ_ALOUD_CONFIG
};

export const XIAOMI_MIMO_REMOTE_READ_ALOUD_VOICE_OPTIONS: RemoteReadAloudChoiceOption[] = [
  { label: 'MiMo-默认', value: 'mimo_default' },
  { label: 'MiMo-中文女声', value: 'default_zh' },
  { label: 'MiMo-英文女声', value: 'default_en' }
];

export const XIAOMI_MIMO_REMOTE_READ_ALOUD_STYLE_CATEGORIES: RemoteReadAloudStyleCategory[] = [
  { label: '语速控制', styles: ['变快', '变慢'] },
  { label: '情绪变化', styles: ['开心', '悲伤', '生气'] },
  { label: '角色扮演', styles: ['孙悟空', '林黛玉'] },
  { label: '风格变化', styles: ['悄悄话', '夹子音', '台湾腔'] },
  { label: '方言', styles: ['东北话', '四川话', '河南话', '粤语'] }
];

function createRemoteReadAloudSettings(
  config: RemoteReadAloudPresetConfig,
  activePresetId: string,
  presets: RemoteReadAloudPreset[]
): RemoteReadAloudSettings {
  return {
    endpoint: config.endpoint,
    apiPath: config.apiPath,
    apiKey: config.apiKey,
    model: config.model,
    voice: config.voice,
    stylePrompt: config.stylePrompt,
    audioFormat: config.audioFormat,
    streamEnabled: config.streamEnabled,
    prefetchSegments: config.prefetchSegments,
    connectTimeoutMs: config.connectTimeoutMs,
    readTimeoutMs: config.readTimeoutMs,
    maxInputChars: config.maxInputChars,
    reservedInputChars: config.reservedInputChars,
    minChunkChars: config.minChunkChars,
    targetChunkChars: config.targetChunkChars,
    maxChunkChars: config.maxChunkChars,
    cacheAudioFiles: config.cacheAudioFiles,
    autoConcatAudio: config.autoConcatAudio,
    customHeadersJson: config.customHeadersJson,
    extraBodyJson: config.extraBodyJson,
    activePresetId,
    presets
  };
}

export const DEFAULT_REMOTE_READ_ALOUD_SETTINGS: RemoteReadAloudSettings = createRemoteReadAloudSettings(
  DEFAULT_XIAOMI_MIMO_REMOTE_READ_ALOUD_CONFIG,
  DEFAULT_REMOTE_READ_ALOUD_PRESET_ID,
  [DEFAULT_XIAOMI_MIMO_REMOTE_READ_ALOUD_PRESET]
);

/**
 * 默认听书设置
 */
export const DEFAULT_READ_ALOUD_SETTINGS: ReadAloudSettings = {
  enabled: false,
  engineType: ReadAloudEngineType.SYSTEM,
  speed: 1.0,
  pitch: 1.0,
  volume: 1.0,
  continueInBackground: false,
  autoPlayNextChapter: true,
  pauseOnManualPageTurn: true,
  voiceLanguage: '',
  voicePerson: -1,
  voiceOnline: -1,
  remote: DEFAULT_REMOTE_READ_ALOUD_SETTINGS
};

function clampNumber(value: number, min: number, max: number): number {
  return Math.max(min, Math.min(max, value));
}

export function normalizeRemoteReadAloudStylePrompt(stylePrompt?: string | null): string {
  const raw = typeof stylePrompt === 'string' ? stylePrompt.trim() : '';
  if (raw.length <= 0) {
    return '';
  }
  const matched = raw.match(/^<style>([\s\S]*?)<\/style>$/i);
  const content = matched && typeof matched[1] === 'string' ? matched[1] : raw;
  return content
    .replace(/[\r\n\t]+/g, ' ')
    .replace(/[，,、|/]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

export function splitRemoteReadAloudStylePrompt(stylePrompt?: string | null): string[] {
  const normalized = normalizeRemoteReadAloudStylePrompt(stylePrompt);
  if (normalized.length <= 0) {
    return [];
  }
  const styles: string[] = [];
  const parts = normalized.split(' ');
  for (let index = 0; index < parts.length; index++) {
    const style = parts[index].trim();
    if (style.length <= 0 || styles.indexOf(style) >= 0) {
      continue;
    }
    styles.push(style);
  }
  return styles;
}

export function hasRemoteReadAloudStylePrompt(stylePrompt: string, style: string): boolean {
  const normalizedStyle = normalizeRemoteReadAloudStylePrompt(style);
  if (normalizedStyle.length <= 0) {
    return false;
  }
  return splitRemoteReadAloudStylePrompt(stylePrompt).indexOf(normalizedStyle) >= 0;
}

export function toggleRemoteReadAloudStylePrompt(stylePrompt: string, style: string): string {
  const normalizedStyle = normalizeRemoteReadAloudStylePrompt(style);
  if (normalizedStyle.length <= 0) {
    return normalizeRemoteReadAloudStylePrompt(stylePrompt);
  }
  const styles = splitRemoteReadAloudStylePrompt(stylePrompt);
  const existingIndex = styles.indexOf(normalizedStyle);
  if (existingIndex >= 0) {
    styles.splice(existingIndex, 1);
  } else {
    styles.push(normalizedStyle);
  }
  return styles.join(' ');
}

export function buildXiaomiMimoStyledText(stylePrompt: string, text: string): string {
  const normalizedStyle = normalizeRemoteReadAloudStylePrompt(stylePrompt);
  if (normalizedStyle.length <= 0) {
    return text;
  }
  return `<style>${normalizedStyle}</style>${text}`;
}

export function isXiaomiMimoRemoteReadAloud(
  remote?: RemoteReadAloudSettings | null
): boolean {
  const endpointValue = remote?.endpoint;
  const modelValue = remote?.model;
  const activePresetIdValue = remote?.activePresetId;
  const endpoint = typeof endpointValue === 'string' ? endpointValue.trim().toLowerCase() : '';
  const model = typeof modelValue === 'string' ? modelValue.trim().toLowerCase() : '';
  const activePresetId = typeof activePresetIdValue === 'string' ? activePresetIdValue.trim() : '';
  return activePresetId === DEFAULT_REMOTE_READ_ALOUD_PRESET_ID ||
    endpoint.includes('xiaomimimo.com') ||
    model === 'mimo-v2-tts';
}

export function getXiaomiMimoRemoteReadAloudVoiceLabel(voice: string): string {
  const normalizedVoice = voice.trim();
  for (let index = 0; index < XIAOMI_MIMO_REMOTE_READ_ALOUD_VOICE_OPTIONS.length; index++) {
    const option = XIAOMI_MIMO_REMOTE_READ_ALOUD_VOICE_OPTIONS[index];
    if (option.value === normalizedVoice) {
      return option.label;
    }
  }
  return normalizedVoice.length > 0 ? normalizedVoice : '默认音色';
}

function normalizeRemoteReadAloudPresetConfig(
  remote?: Partial<RemoteReadAloudPresetConfig> | null,
  fallback: RemoteReadAloudPresetConfig = DEFAULT_XIAOMI_MIMO_REMOTE_READ_ALOUD_CONFIG
): RemoteReadAloudPresetConfig {
  const endpoint = (remote?.endpoint ?? fallback.endpoint).trim();
  const apiPathRaw = (remote?.apiPath ?? fallback.apiPath).trim();
  const apiPath = apiPathRaw.length > 0
    ? (
      apiPathRaw.startsWith('/') ||
      apiPathRaw.startsWith('http://') ||
      apiPathRaw.startsWith('https://')
    ) ? apiPathRaw : `/${apiPathRaw}`
    : fallback.apiPath;
  const audioFormatRaw = (remote?.audioFormat ?? fallback.audioFormat).trim().toLowerCase();
  const audioFormat = audioFormatRaw.length > 0 ? audioFormatRaw : fallback.audioFormat;

  return {
    endpoint,
    apiPath,
    apiKey: remote?.apiKey ?? fallback.apiKey,
    model: (remote?.model ?? fallback.model).trim(),
    voice: (remote?.voice ?? fallback.voice).trim(),
    stylePrompt: normalizeRemoteReadAloudStylePrompt(remote?.stylePrompt ?? fallback.stylePrompt),
    audioFormat,
    streamEnabled: remote?.streamEnabled ?? fallback.streamEnabled,
    prefetchSegments: Math.max(1, Math.min(8, Math.floor(remote?.prefetchSegments ?? fallback.prefetchSegments))),
    connectTimeoutMs: Math.max(3000, Math.min(120000, Math.floor(remote?.connectTimeoutMs ?? fallback.connectTimeoutMs))),
    readTimeoutMs: Math.max(5000, Math.min(300000, Math.floor(remote?.readTimeoutMs ?? fallback.readTimeoutMs))),
    maxInputChars: Math.max(256, Math.min(12000, Math.floor(remote?.maxInputChars ?? fallback.maxInputChars))),
    reservedInputChars: Math.max(0, Math.min(2000, Math.floor(remote?.reservedInputChars ?? fallback.reservedInputChars))),
    minChunkChars: Math.max(32, Math.min(5000, Math.floor(remote?.minChunkChars ?? fallback.minChunkChars))),
    targetChunkChars: Math.max(64, Math.min(7000, Math.floor(remote?.targetChunkChars ?? fallback.targetChunkChars))),
    maxChunkChars: Math.max(80, Math.min(9000, Math.floor(remote?.maxChunkChars ?? fallback.maxChunkChars))),
    cacheAudioFiles: remote?.cacheAudioFiles ?? fallback.cacheAudioFiles,
    autoConcatAudio: remote?.autoConcatAudio ?? fallback.autoConcatAudio,
    customHeadersJson: remote?.customHeadersJson ?? fallback.customHeadersJson,
    extraBodyJson: remote?.extraBodyJson ?? fallback.extraBodyJson
  };
}

function getRemoteReadAloudPresetSignature(config: RemoteReadAloudPresetConfig): string {
  const normalized = normalizeRemoteReadAloudPresetConfig(config);
  return [
    normalized.endpoint.trim(),
    normalized.apiPath.trim(),
    normalized.apiKey,
    normalized.model.trim(),
    normalized.voice.trim(),
    normalized.stylePrompt.trim(),
    normalized.audioFormat.trim(),
    String(normalized.streamEnabled),
    String(normalized.prefetchSegments),
    String(normalized.connectTimeoutMs),
    String(normalized.readTimeoutMs),
    String(normalized.maxInputChars),
    String(normalized.reservedInputChars),
    String(normalized.minChunkChars),
    String(normalized.targetChunkChars),
    String(normalized.maxChunkChars),
    String(normalized.cacheAudioFiles),
    String(normalized.autoConcatAudio),
    normalized.customHeadersJson ?? '',
    normalized.extraBodyJson ?? ''
  ].join('|');
}

function isLegacyDefaultRemoteReadAloudSettings(remote?: Partial<RemoteReadAloudSettings> | null): boolean {
  const activePresetIdValue = remote?.activePresetId;
  const presetList = remote?.presets;
  const activePresetId = typeof activePresetIdValue === 'string' ? activePresetIdValue.trim() : '';
  if (activePresetId.length > 0) {
    return false;
  }
  if (Array.isArray(presetList) && presetList.length > 0) {
    return false;
  }
  return getRemoteReadAloudPresetSignature(
    normalizeRemoteReadAloudPresetConfig(remote, LEGACY_DEFAULT_REMOTE_READ_ALOUD_SETTINGS)
  ) === getRemoteReadAloudPresetSignature(LEGACY_DEFAULT_REMOTE_READ_ALOUD_SETTINGS);
}

function normalizeRemoteReadAloudPresets(source?: RemoteReadAloudPresetSource[] | null): RemoteReadAloudPreset[] {
  const presets: RemoteReadAloudPreset[] = [
    {
      id: DEFAULT_XIAOMI_MIMO_REMOTE_READ_ALOUD_PRESET.id,
      name: DEFAULT_XIAOMI_MIMO_REMOTE_READ_ALOUD_PRESET.name,
      description: DEFAULT_XIAOMI_MIMO_REMOTE_READ_ALOUD_PRESET.description,
      builtIn: true,
      settings: normalizeRemoteReadAloudPresetConfig(DEFAULT_XIAOMI_MIMO_REMOTE_READ_ALOUD_PRESET.settings)
    }
  ];
  if (!Array.isArray(source)) {
    return presets;
  }
  const seenIds: Set<string> = new Set<string>([DEFAULT_REMOTE_READ_ALOUD_PRESET_ID]);
  source.forEach((preset: RemoteReadAloudPresetSource, index: number) => {
    if (!preset || typeof preset !== 'object') {
      return;
    }
    const presetId = typeof preset.id === 'string' && preset.id.trim().length > 0
      ? preset.id.trim()
      : `remote_preset_${index + 1}`;
    if (seenIds.has(presetId)) {
      return;
    }
    const presetName = typeof preset.name === 'string' && preset.name.trim().length > 0
      ? preset.name.trim()
      : `远程预设 ${index + 1}`;
    const presetDescription = typeof preset.description === 'string' ? preset.description.trim() : '';
    const rawSettings = preset.settings ?? preset.config ?? preset.remote;
    seenIds.add(presetId);
    presets.push({
      id: presetId,
      name: presetName,
      description: presetDescription,
      builtIn: false,
      settings: normalizeRemoteReadAloudPresetConfig(rawSettings)
    });
  });
  return presets;
}

export function extractRemoteReadAloudPresetConfig(remote?: Partial<RemoteReadAloudSettings> | null): RemoteReadAloudPresetConfig {
  const normalized = normalizeRemoteReadAloudSettings(remote);
  return {
    endpoint: normalized.endpoint,
    apiPath: normalized.apiPath,
    apiKey: normalized.apiKey,
    model: normalized.model,
    voice: normalized.voice,
    stylePrompt: normalized.stylePrompt,
    audioFormat: normalized.audioFormat,
    streamEnabled: normalized.streamEnabled,
    prefetchSegments: normalized.prefetchSegments,
    connectTimeoutMs: normalized.connectTimeoutMs,
    readTimeoutMs: normalized.readTimeoutMs,
    maxInputChars: normalized.maxInputChars,
    reservedInputChars: normalized.reservedInputChars,
    minChunkChars: normalized.minChunkChars,
    targetChunkChars: normalized.targetChunkChars,
    maxChunkChars: normalized.maxChunkChars,
    cacheAudioFiles: normalized.cacheAudioFiles,
    autoConcatAudio: normalized.autoConcatAudio,
    customHeadersJson: normalized.customHeadersJson,
    extraBodyJson: normalized.extraBodyJson
  };
}

export function isRemoteReadAloudPresetConfigEqual(
  left?: Partial<RemoteReadAloudPresetConfig> | null,
  right?: Partial<RemoteReadAloudPresetConfig> | null
): boolean {
  return getRemoteReadAloudPresetSignature(normalizeRemoteReadAloudPresetConfig(left)) ===
    getRemoteReadAloudPresetSignature(normalizeRemoteReadAloudPresetConfig(right));
}

export function normalizeRemoteReadAloudSettings(remote?: Partial<RemoteReadAloudSettings> | null): RemoteReadAloudSettings {
  const currentConfig = isLegacyDefaultRemoteReadAloudSettings(remote)
    ? normalizeRemoteReadAloudPresetConfig(DEFAULT_XIAOMI_MIMO_REMOTE_READ_ALOUD_CONFIG, DEFAULT_XIAOMI_MIMO_REMOTE_READ_ALOUD_CONFIG)
    : normalizeRemoteReadAloudPresetConfig(remote, DEFAULT_XIAOMI_MIMO_REMOTE_READ_ALOUD_CONFIG);
  const presets = normalizeRemoteReadAloudPresets(remote?.presets);
  const activePresetIdValue = remote?.activePresetId;
  const activePresetIdRaw = typeof activePresetIdValue === 'string' ? activePresetIdValue.trim() : '';
  const activePreset = presets.find((preset: RemoteReadAloudPreset) => preset.id === activePresetIdRaw);
  const matchedPreset = presets.find((preset: RemoteReadAloudPreset) =>
    isRemoteReadAloudPresetConfigEqual(currentConfig, preset.settings)
  );

  return createRemoteReadAloudSettings(
    currentConfig,
    activePreset ? activePreset.id : (matchedPreset ? matchedPreset.id : ''),
    presets
  );
}

export function mergeRemoteReadAloudSettings(
  current?: Partial<RemoteReadAloudSettings> | null,
  partial?: Partial<RemoteReadAloudSettings> | null
): RemoteReadAloudSettings {
  const currentValue = normalizeRemoteReadAloudSettings(current);
  if (!partial) {
    return currentValue;
  }
  const mergedConfig: RemoteReadAloudPresetConfig = normalizeRemoteReadAloudPresetConfig({
    endpoint: partial.endpoint ?? currentValue.endpoint,
    apiPath: partial.apiPath ?? currentValue.apiPath,
    apiKey: partial.apiKey ?? currentValue.apiKey,
    model: partial.model ?? currentValue.model,
    voice: partial.voice ?? currentValue.voice,
    stylePrompt: partial.stylePrompt ?? currentValue.stylePrompt,
    audioFormat: partial.audioFormat ?? currentValue.audioFormat,
    streamEnabled: partial.streamEnabled ?? currentValue.streamEnabled,
    prefetchSegments: partial.prefetchSegments ?? currentValue.prefetchSegments,
    connectTimeoutMs: partial.connectTimeoutMs ?? currentValue.connectTimeoutMs,
    readTimeoutMs: partial.readTimeoutMs ?? currentValue.readTimeoutMs,
    maxInputChars: partial.maxInputChars ?? currentValue.maxInputChars,
    reservedInputChars: partial.reservedInputChars ?? currentValue.reservedInputChars,
    minChunkChars: partial.minChunkChars ?? currentValue.minChunkChars,
    targetChunkChars: partial.targetChunkChars ?? currentValue.targetChunkChars,
    maxChunkChars: partial.maxChunkChars ?? currentValue.maxChunkChars,
    cacheAudioFiles: partial.cacheAudioFiles ?? currentValue.cacheAudioFiles,
    autoConcatAudio: partial.autoConcatAudio ?? currentValue.autoConcatAudio,
    customHeadersJson: partial.customHeadersJson ?? currentValue.customHeadersJson,
    extraBodyJson: partial.extraBodyJson ?? currentValue.extraBodyJson
  }, DEFAULT_XIAOMI_MIMO_REMOTE_READ_ALOUD_CONFIG);
  return normalizeRemoteReadAloudSettings(createRemoteReadAloudSettings(
    mergedConfig,
    partial.activePresetId ?? currentValue.activePresetId,
    partial.presets ?? currentValue.presets
  ));
}

export function normalizeReadAloudSettings(settings?: Partial<ReadAloudSettings> | null): ReadAloudSettings {
  const rawEngine = settings?.engineType ?? DEFAULT_READ_ALOUD_SETTINGS.engineType;
  const engineType = (
    rawEngine === ReadAloudEngineType.SYSTEM ||
    rawEngine === ReadAloudEngineType.LEGADO_COMPAT ||
    rawEngine === ReadAloudEngineType.REMOTE
  ) ? rawEngine : ReadAloudEngineType.SYSTEM;
  const voicePersonRaw = settings?.voicePerson ?? DEFAULT_READ_ALOUD_SETTINGS.voicePerson ?? -1;
  const voiceOnlineRaw = settings?.voiceOnline ?? DEFAULT_READ_ALOUD_SETTINGS.voiceOnline ?? -1;
  return {
    enabled: settings?.enabled ?? DEFAULT_READ_ALOUD_SETTINGS.enabled,
    engineType,
    speed: clampNumber(settings?.speed ?? DEFAULT_READ_ALOUD_SETTINGS.speed, 0.5, 2.0),
    pitch: clampNumber(settings?.pitch ?? DEFAULT_READ_ALOUD_SETTINGS.pitch, 0.5, 2.0),
    volume: clampNumber(settings?.volume ?? DEFAULT_READ_ALOUD_SETTINGS.volume, 0, 1),
    continueInBackground: settings?.continueInBackground ?? DEFAULT_READ_ALOUD_SETTINGS.continueInBackground,
    autoPlayNextChapter: settings?.autoPlayNextChapter ?? DEFAULT_READ_ALOUD_SETTINGS.autoPlayNextChapter,
    pauseOnManualPageTurn: settings?.pauseOnManualPageTurn ?? DEFAULT_READ_ALOUD_SETTINGS.pauseOnManualPageTurn,
    voiceLanguage: settings?.voiceLanguage ?? DEFAULT_READ_ALOUD_SETTINGS.voiceLanguage ?? '',
    voicePerson: voicePersonRaw >= 0 ? Math.floor(voicePersonRaw) : -1,
    voiceOnline: (voiceOnlineRaw === 0 || voiceOnlineRaw === 1) ? voiceOnlineRaw : -1,
    remote: normalizeRemoteReadAloudSettings(settings?.remote)
  };
}

/**
 * 文本阅读器设置
 */
export interface TextReaderSettings {
  /** 阅读模式 */
  readingMode: TextReadingMode;
  /** 阅读方向 */
  readingDirection: TextReadingDirection;
  /** 翻页动画类型 */
  pageTurnAnimation: TextPageTurnAnimation;
  /** 背景设置 */
  background: CustomBackground;
  /** 保存的背景图片列表（最多10个） */
  savedBackgroundImages: SavedBackgroundImage[];
  /** 文字样式 */
  textStyle: TextStyleSettings;
  /** 页面边距 */
  pageMargins: PageMargins;
  /** 是否保持屏幕常亮 */
  keepScreenOn: boolean;
  /** 是否显示页码 */
  showPageNumber: boolean;
  /** 是否显示进度百分比 */
  showProgress: boolean;
  /** 是否显示时间 */
  showTime: boolean;
  /** 是否显示电量 */
  showBattery: boolean;
  /** 点击区域翻页 */
  tapToTurn: boolean;
  /** 音量键翻页 */
  volumeKeyNavigation: boolean;
  /** 自动滚动速度（像素/秒） */
  autoScrollSpeed: number;
  /** Auto page turn switch */
  autoPageTurnEnabled?: boolean;
  /** Auto page turn interval in seconds */
  autoPageTurnInterval?: number;
  /** 卷页背面透明度（0-100） */
  curlBackOpacity: number;
  /** 听书设置（可选，兼容旧版本） */
  readAloud?: ReadAloudSettings;
}

/**
 * 默认文字样式
 */
export const DEFAULT_TEXT_STYLE: TextStyleSettings = {
  fontSize: 18,
  lineHeight: 1.8,
  paragraphSpacing: 16,
  firstLineIndent: 2,
  letterSpacing: 0.5,
  textColor: '#333333',
  fontWeight: 400,
  fontFamily: 'HarmonyOS Sans',
  textAlignment: TextAlignment.JUSTIFY
};

/**
 * 默认页面边距
 */
export const DEFAULT_PAGE_MARGINS: PageMargins = {
  top: 48,
  bottom: 48,
  left: 24,
  right: 24
};

/**
 * 默认背景设置
 */
export const DEFAULT_BACKGROUND: CustomBackground = {
  type: BackgroundType.COLOR,
  color: '#F5F0E1',
  imageOpacity: 1.0
};

/**
 * 默认文本阅读器设置
 */
export const DEFAULT_TEXT_READER_SETTINGS: TextReaderSettings = {
  readingMode: TextReadingMode.PAGE,
  readingDirection: TextReadingDirection.HORIZONTAL,
  pageTurnAnimation: TextPageTurnAnimation.CURL,
  background: DEFAULT_BACKGROUND,
  savedBackgroundImages: [],
  textStyle: DEFAULT_TEXT_STYLE,
  pageMargins: DEFAULT_PAGE_MARGINS,
  keepScreenOn: true,
  showPageNumber: true,
  showProgress: true,
  showTime: true,
  showBattery: true,
  tapToTurn: true,
  volumeKeyNavigation: true,
  autoScrollSpeed: 50,
  autoPageTurnEnabled: false,
  autoPageTurnInterval: 8,
  curlBackOpacity: 90,
  readAloud: {
    enabled: DEFAULT_READ_ALOUD_SETTINGS.enabled,
    engineType: DEFAULT_READ_ALOUD_SETTINGS.engineType,
    speed: DEFAULT_READ_ALOUD_SETTINGS.speed,
    pitch: DEFAULT_READ_ALOUD_SETTINGS.pitch,
    volume: DEFAULT_READ_ALOUD_SETTINGS.volume,
    continueInBackground: DEFAULT_READ_ALOUD_SETTINGS.continueInBackground,
    autoPlayNextChapter: DEFAULT_READ_ALOUD_SETTINGS.autoPlayNextChapter,
    pauseOnManualPageTurn: DEFAULT_READ_ALOUD_SETTINGS.pauseOnManualPageTurn,
    voiceLanguage: DEFAULT_READ_ALOUD_SETTINGS.voiceLanguage,
    voicePerson: DEFAULT_READ_ALOUD_SETTINGS.voicePerson,
    voiceOnline: DEFAULT_READ_ALOUD_SETTINGS.voiceOnline,
    remote: DEFAULT_READ_ALOUD_SETTINGS.remote
  }
};

/**
 * 文本页面数据
 */
export interface TextPage {
  /** 页面索引 */
  index: number;
  /** 页面文本内容 */
  content: string;
  /** 起始字符位置 */
  startCharIndex: number;
  /** 结束字符位置 */
  endCharIndex: number;
}

/**
 * 文本章节数据
 */
export interface TextChapter {
  /** 章节ID */
  id: string;
  /** 章节标题 */
  title: string;
  /** 章节索引 */
  index: number;
  /** 章节内容 */
  content: string;
  /** 章节起始字符位置（在全文中） */
  startPosition: number;
  /** 章节结束字符位置（在全文中） */
  endPosition: number;
}

/**
 * 文本阅读进度
 */
export interface TextReadingProgress {
  /** 当前章节索引 */
  currentChapterIndex: number;
  /** 当前页面索引 */
  currentPageIndex: number;
  /** 当前字符位置 */
  currentCharPosition: number;
  /** 阅读进度百分比（0-100） */
  progressPercent: number;
  /** 最后阅读时间 */
  lastReadTime: number;
}

/**
 * 文本阅读器回调接口
 */
export interface TextReaderCallbacks {
  /** 页面切换回调 */
  onPageChange?: (pageIndex: number, totalPages: number) => void;
  /** 当前页字符区间变化回调（用于听书进度映射） */
  onPageCharRangeChange?: (startCharIndex: number, endCharIndex: number) => void;
  /** 章节切换回调 */
  onChapterChange?: (chapterIndex: number) => void;
  /** 进度变化回调 */
  onProgressChange?: (progress: number) => void;
  /** 点击中间区域回调（用于显示/隐藏工具栏） */
  onTapCenter?: () => void;
  /** 长按回调（选择文字） */
  onLongPress?: (event: GestureEvent) => void;
  /** 设置变化回调 */
  onSettingsChange?: (settings: TextReaderSettings) => void;
}

/**
 * 文本阅读器参数接口
 */
export interface TextReaderParams {
  /** 文本内容（完整文本或章节列表） */
  content: string;
  /** 章节列表（可选，如果提供则支持章节导航） */
  chapters?: TextChapter[];
  /** 初始章节索引 */
  initialChapterIndex?: number;
  /** 初始页面索引 */
  initialPageIndex?: number;
  /** 初始字符位置 */
  initialCharPosition?: number;
  /** 阅读设置 */
  settings: TextReaderSettings;
  /** 回调函数 */
  callbacks?: TextReaderCallbacks;
}

/**
 * 支持的纯文本文件扩展名
 */
export const SUPPORTED_TEXT_EXTENSIONS: string[] = [
  'txt', 'text',
  'md', 'markdown',
  'json',
  'xml',
  'html', 'htm',
  'css',
  'js', 'ts',
  'log',
  'ini', 'conf', 'cfg',
  'yaml', 'yml',
  'csv',
  'sql'
];

/**
 * 判断文件是否为纯文本文件
 */
export function isTextFile(filePath: string): boolean {
  const extension = filePath.split('.').pop()?.toLowerCase() || '';
  return SUPPORTED_TEXT_EXTENSIONS.includes(extension);
}

/**
 * 判断文件是否为电子书文件（需要使用官方阅读器）
 */
export function isEBookFile(filePath: string): boolean {
  const extension = filePath.split('.').pop()?.toLowerCase() || '';
  return ['epub', 'mobi', 'azw', 'azw3', 'pdf'].includes(extension);
}
