import {
  DEFAULT_READ_ALOUD_SETTINGS,
  DEFAULT_REMOTE_READ_ALOUD_SETTINGS,
  ReadAloudEngineType,
  RemoteReadAloudPreset,
  ReadAloudSettings,
  normalizeReadAloudSettings
} from 'manxia_core/src/main/ets/Models/TextReaderModels';
import { SettingKeys, SettingsManager } from '../Managers/SettingsManager';

let globalReadAloudPersistQueue: Promise<void> = Promise.resolve();

export function loadGlobalReadAloudSettings(settingsManager: SettingsManager): ReadAloudSettings {
  const engineRaw = settingsManager.getString(
    SettingKeys.GLOBAL_TEXT_READ_ALOUD_ENGINE,
    DEFAULT_READ_ALOUD_SETTINGS.engineType
  ) as ReadAloudEngineType;

  return normalizeReadAloudSettings({
    enabled: settingsManager.getBoolean(SettingKeys.GLOBAL_TEXT_READ_ALOUD_ENABLED, DEFAULT_READ_ALOUD_SETTINGS.enabled),
    engineType: engineRaw,
    speed: settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_READ_ALOUD_SPEED, DEFAULT_READ_ALOUD_SETTINGS.speed),
    pitch: settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_READ_ALOUD_PITCH, DEFAULT_READ_ALOUD_SETTINGS.pitch),
    volume: settingsManager.getNumber(SettingKeys.GLOBAL_TEXT_READ_ALOUD_VOLUME, DEFAULT_READ_ALOUD_SETTINGS.volume),
    continueInBackground: settingsManager.getBoolean(
      SettingKeys.GLOBAL_TEXT_READ_ALOUD_CONTINUE_BG,
      DEFAULT_READ_ALOUD_SETTINGS.continueInBackground
    ),
    autoPlayNextChapter: settingsManager.getBoolean(
      SettingKeys.GLOBAL_TEXT_READ_ALOUD_AUTO_PLAY_NEXT_CHAPTER,
      DEFAULT_READ_ALOUD_SETTINGS.autoPlayNextChapter
    ),
    pauseOnManualPageTurn: settingsManager.getBoolean(
      SettingKeys.GLOBAL_TEXT_READ_ALOUD_PAUSE_ON_MANUAL_PAGE_TURN,
      DEFAULT_READ_ALOUD_SETTINGS.pauseOnManualPageTurn
    ),
    voiceLanguage: settingsManager.getString(
      SettingKeys.GLOBAL_TEXT_READ_ALOUD_VOICE_LANGUAGE,
      DEFAULT_READ_ALOUD_SETTINGS.voiceLanguage ?? ''
    ),
    voicePerson: settingsManager.getNumber(
      SettingKeys.GLOBAL_TEXT_READ_ALOUD_VOICE_PERSON,
      DEFAULT_READ_ALOUD_SETTINGS.voicePerson ?? -1
    ),
    voiceOnline: settingsManager.getNumber(
      SettingKeys.GLOBAL_TEXT_READ_ALOUD_VOICE_ONLINE,
      DEFAULT_READ_ALOUD_SETTINGS.voiceOnline ?? -1
    ),
    remote: {
      endpoint: settingsManager.getString(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_ENDPOINT,
        DEFAULT_REMOTE_READ_ALOUD_SETTINGS.endpoint
      ),
      apiPath: settingsManager.getString(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_API_PATH,
        DEFAULT_REMOTE_READ_ALOUD_SETTINGS.apiPath
      ),
      apiKey: settingsManager.getString(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_API_KEY,
        DEFAULT_REMOTE_READ_ALOUD_SETTINGS.apiKey
      ),
      model: settingsManager.getString(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_MODEL,
        DEFAULT_REMOTE_READ_ALOUD_SETTINGS.model
      ),
      voice: settingsManager.getString(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_VOICE,
        DEFAULT_REMOTE_READ_ALOUD_SETTINGS.voice
      ),
      stylePrompt: settingsManager.getString(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_STYLE_PROMPT,
        DEFAULT_REMOTE_READ_ALOUD_SETTINGS.stylePrompt
      ),
      audioFormat: settingsManager.getString(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_AUDIO_FORMAT,
        DEFAULT_REMOTE_READ_ALOUD_SETTINGS.audioFormat
      ),
      streamEnabled: settingsManager.getBoolean(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_STREAM_ENABLED,
        DEFAULT_REMOTE_READ_ALOUD_SETTINGS.streamEnabled
      ),
      prefetchSegments: settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_PREFETCH_SEGMENTS,
        DEFAULT_REMOTE_READ_ALOUD_SETTINGS.prefetchSegments
      ),
      connectTimeoutMs: settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_CONNECT_TIMEOUT_MS,
        DEFAULT_REMOTE_READ_ALOUD_SETTINGS.connectTimeoutMs
      ),
      readTimeoutMs: settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_READ_TIMEOUT_MS,
        DEFAULT_REMOTE_READ_ALOUD_SETTINGS.readTimeoutMs
      ),
      maxInputChars: settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_MAX_INPUT_CHARS,
        DEFAULT_REMOTE_READ_ALOUD_SETTINGS.maxInputChars
      ),
      reservedInputChars: settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_RESERVED_INPUT_CHARS,
        DEFAULT_REMOTE_READ_ALOUD_SETTINGS.reservedInputChars
      ),
      minChunkChars: settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_MIN_CHUNK_CHARS,
        DEFAULT_REMOTE_READ_ALOUD_SETTINGS.minChunkChars
      ),
      targetChunkChars: settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_TARGET_CHUNK_CHARS,
        DEFAULT_REMOTE_READ_ALOUD_SETTINGS.targetChunkChars
      ),
      maxChunkChars: settingsManager.getNumber(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_MAX_CHUNK_CHARS,
        DEFAULT_REMOTE_READ_ALOUD_SETTINGS.maxChunkChars
      ),
      cacheAudioFiles: settingsManager.getBoolean(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_CACHE_AUDIO_FILES,
        DEFAULT_REMOTE_READ_ALOUD_SETTINGS.cacheAudioFiles
      ),
      autoConcatAudio: settingsManager.getBoolean(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_AUTO_CONCAT_AUDIO,
        DEFAULT_REMOTE_READ_ALOUD_SETTINGS.autoConcatAudio
      ),
      customHeadersJson: settingsManager.getString(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_CUSTOM_HEADERS_JSON,
        DEFAULT_REMOTE_READ_ALOUD_SETTINGS.customHeadersJson
      ),
      extraBodyJson: settingsManager.getString(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_EXTRA_BODY_JSON,
        DEFAULT_REMOTE_READ_ALOUD_SETTINGS.extraBodyJson
      ),
      activePresetId: settingsManager.getString(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_ACTIVE_PRESET_ID,
        DEFAULT_REMOTE_READ_ALOUD_SETTINGS.activePresetId
      ),
      presets: settingsManager.getJSON<RemoteReadAloudPreset[]>(
        SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_PRESETS_JSON,
        DEFAULT_REMOTE_READ_ALOUD_SETTINGS.presets
      )
    }
  });
}

export async function persistGlobalReadAloudSettings(settingsManager: SettingsManager, settings: ReadAloudSettings): Promise<void> {
  const normalized = normalizeReadAloudSettings(settings);
  const remote = normalized.remote ?? DEFAULT_REMOTE_READ_ALOUD_SETTINGS;

  const persistTask = globalReadAloudPersistQueue.catch(() => {}).then(async () => {
    // Remote read-aloud settings are split across many keys. Serialize writes so
    // stale snapshots cannot interleave with newer ones and clear apiKey by mistake.
    await settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_READ_ALOUD_ENABLED, normalized.enabled);
    await settingsManager.setString(SettingKeys.GLOBAL_TEXT_READ_ALOUD_ENGINE, normalized.engineType);
    await settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_READ_ALOUD_SPEED, normalized.speed);
    await settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_READ_ALOUD_PITCH, normalized.pitch);
    await settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_READ_ALOUD_VOLUME, normalized.volume);
    await settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_READ_ALOUD_CONTINUE_BG, normalized.continueInBackground);
    await settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_READ_ALOUD_AUTO_PLAY_NEXT_CHAPTER, normalized.autoPlayNextChapter);
    await settingsManager.setBoolean(
      SettingKeys.GLOBAL_TEXT_READ_ALOUD_PAUSE_ON_MANUAL_PAGE_TURN,
      normalized.pauseOnManualPageTurn
    );
    await settingsManager.setString(SettingKeys.GLOBAL_TEXT_READ_ALOUD_VOICE_LANGUAGE, normalized.voiceLanguage ?? '');
    await settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_READ_ALOUD_VOICE_PERSON, normalized.voicePerson ?? -1);
    await settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_READ_ALOUD_VOICE_ONLINE, normalized.voiceOnline ?? -1);

    await settingsManager.setString(SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_ENDPOINT, remote.endpoint);
    await settingsManager.setString(SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_API_PATH, remote.apiPath);
    await settingsManager.setString(SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_API_KEY, remote.apiKey);
    await settingsManager.setString(SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_MODEL, remote.model);
    await settingsManager.setString(SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_VOICE, remote.voice);
    await settingsManager.setString(SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_STYLE_PROMPT, remote.stylePrompt);
    await settingsManager.setString(SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_AUDIO_FORMAT, remote.audioFormat);
    await settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_STREAM_ENABLED, remote.streamEnabled);
    await settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_PREFETCH_SEGMENTS, remote.prefetchSegments);
    await settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_CONNECT_TIMEOUT_MS, remote.connectTimeoutMs);
    await settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_READ_TIMEOUT_MS, remote.readTimeoutMs);
    await settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_MAX_INPUT_CHARS, remote.maxInputChars);
    await settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_RESERVED_INPUT_CHARS, remote.reservedInputChars);
    await settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_MIN_CHUNK_CHARS, remote.minChunkChars);
    await settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_TARGET_CHUNK_CHARS, remote.targetChunkChars);
    await settingsManager.setNumber(SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_MAX_CHUNK_CHARS, remote.maxChunkChars);
    await settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_CACHE_AUDIO_FILES, remote.cacheAudioFiles);
    await settingsManager.setBoolean(SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_AUTO_CONCAT_AUDIO, remote.autoConcatAudio);
    await settingsManager.setString(SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_CUSTOM_HEADERS_JSON, remote.customHeadersJson);
    await settingsManager.setString(SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_EXTRA_BODY_JSON, remote.extraBodyJson);
    await settingsManager.setString(SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_ACTIVE_PRESET_ID, remote.activePresetId);
    await settingsManager.setJSON<RemoteReadAloudPreset[]>(SettingKeys.GLOBAL_TEXT_READ_ALOUD_REMOTE_PRESETS_JSON, remote.presets);
  });

  globalReadAloudPersistQueue = persistTask;
  return await persistTask;
}
