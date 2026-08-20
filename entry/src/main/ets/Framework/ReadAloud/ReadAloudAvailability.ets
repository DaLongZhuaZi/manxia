import { textToSpeech } from '@kit.CoreSpeechKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import {
  ReadAloudEngineType,
  ReadAloudSettings,
  RemoteReadAloudSettings,
  normalizeReadAloudSettings
} from 'manxia_core/src/main/ets/Models/TextReaderModels';
import { ReadAloudRequestIdGenerator } from 'manxia_novel/src/main/ets/Framework/ReadAloud/ReadAloudRequestIdGenerator';
import { SettingsManager } from 'manxia_core/src/main/ets/Framework/Managers/SettingsManager';
import { loadGlobalReadAloudSettings } from './ReadAloudSettingsStore';

const TAG = 'ReadAloudAvailability';
const SYSTEM_TTS_ONLINE_MODE: number = 0;
const SYSTEM_TTS_OFFLINE_MODE: number = 1;

interface ReadAloudProbeErrorLike {
  code?: number | string;
  errorCode?: number | string;
  message?: string;
  errorMessage?: string;
  errMsg?: string;
}

export interface ReadAloudEngineAvailabilityMap {
  SYSTEM: boolean;
  LEGADO_COMPAT: boolean;
  REMOTE: boolean;
}

const DEFAULT_AVAILABILITY: ReadAloudEngineAvailabilityMap = {
  SYSTEM: true,
  LEGADO_COMPAT: true,
  REMOTE: false
};

export class ReadAloudAvailability {
  private static cached: ReadAloudEngineAvailabilityMap | null = null;
  private static cachedAt: number = 0;
  private static readonly CACHE_MS: number = 60 * 1000;
  private static lastSystemProbeErrorMessage: string = '';
  private static lastRemoteProbeErrorMessage: string = '';
  private static lastRemoteValidationLogSignature: string = '';

  static getCachedOrDefault(): ReadAloudEngineAvailabilityMap {
    if (ReadAloudAvailability.cached === null) {
      return ReadAloudAvailability.cloneAvailability(DEFAULT_AVAILABILITY);
    }
    return ReadAloudAvailability.cloneAvailability(ReadAloudAvailability.cached);
  }

  static async refresh(force: boolean = false, settingsOverride?: ReadAloudSettings): Promise<ReadAloudEngineAvailabilityMap> {
    const now = Date.now();
    if (
      !force &&
      settingsOverride === undefined &&
      ReadAloudAvailability.cached !== null &&
      (now - ReadAloudAvailability.cachedAt) < ReadAloudAvailability.CACHE_MS
    ) {
      return ReadAloudAvailability.cloneAvailability(ReadAloudAvailability.cached);
    }

    const systemAvailable = await ReadAloudAvailability.checkSystemTtsAvailable();
    const remoteAvailable = ReadAloudAvailability.checkRemoteTtsConfigured(settingsOverride);
    const result: ReadAloudEngineAvailabilityMap = {
      SYSTEM: systemAvailable,
      // LEGADO_COMPAT 当前复用系统TTS能力，可用性与SYSTEM保持一致。
      LEGADO_COMPAT: systemAvailable,
      REMOTE: remoteAvailable
    };
    if (settingsOverride === undefined) {
      ReadAloudAvailability.cached = result;
      ReadAloudAvailability.cachedAt = now;
    }
    return ReadAloudAvailability.cloneAvailability(result);
  }

  static isAvailableSync(engineType: ReadAloudEngineType, settingsOverride?: ReadAloudSettings): boolean {
    if (engineType === ReadAloudEngineType.REMOTE && settingsOverride !== undefined) {
      return ReadAloudAvailability.checkRemoteTtsConfigured(settingsOverride);
    }
    const map = ReadAloudAvailability.getCachedOrDefault();
    if (engineType === ReadAloudEngineType.SYSTEM) {
      return map.SYSTEM;
    }
    if (engineType === ReadAloudEngineType.LEGADO_COMPAT) {
      return map.LEGADO_COMPAT;
    }
    if (engineType === ReadAloudEngineType.REMOTE) {
      return map.REMOTE;
    }
    return false;
  }

  static getLastSystemProbeErrorMessage(): string {
    return ReadAloudAvailability.lastSystemProbeErrorMessage;
  }

  static getLastRemoteProbeErrorMessage(): string {
    return ReadAloudAvailability.lastRemoteProbeErrorMessage;
  }

  private static cloneAvailability(source: ReadAloudEngineAvailabilityMap): ReadAloudEngineAvailabilityMap {
    return {
      SYSTEM: source.SYSTEM === true,
      LEGADO_COMPAT: source.LEGADO_COMPAT === true,
      REMOTE: source.REMOTE === true
    };
  }

  private static reportRemoteValidationFailure(
    reason: string,
    remote?: RemoteReadAloudSettings | null
  ): boolean {
    ReadAloudAvailability.lastRemoteProbeErrorMessage = reason;

    const endpoint = remote?.endpoint.trim() ?? '';
    const model = remote?.model.trim() ?? '';
    const voice = remote?.voice.trim() ?? '';
    const apiKey = remote?.apiKey ?? '';
    const customHeadersLower = (remote?.customHeadersJson ?? '').toLowerCase();
    const hasAuthorizationHeader = customHeadersLower.includes('"authorization"');
    const hasApiKeyHeader = customHeadersLower.includes('"api-key"');
    const activePresetId = remote?.activePresetId?.trim() ?? '';
    const signature = [
      reason,
      endpoint,
      model,
      voice,
      String(apiKey.length),
      String(hasAuthorizationHeader),
      String(hasApiKeyHeader),
      activePresetId
    ].join('|');

    if (signature !== ReadAloudAvailability.lastRemoteValidationLogSignature) {
      logger.warn(
        TAG,
        `REMOTE TTS 配置校验失败: reason=${reason}, endpoint=${endpoint.length > 0 ? endpoint : 'empty'}, model=${model.length > 0 ? model : 'empty'}, voice=${voice.length > 0 ? voice : 'empty'}, hasApiKey=${apiKey.trim().length > 0}, apiKeyLength=${apiKey.length}, hasAuthorizationHeader=${hasAuthorizationHeader}, hasApiKeyHeader=${hasApiKeyHeader}, activePresetId=${activePresetId.length > 0 ? activePresetId : 'none'}`
      );
      ReadAloudAvailability.lastRemoteValidationLogSignature = signature;
    }

    return false;
  }

  private static reportRemoteValidationSuccess(): boolean {
    ReadAloudAvailability.lastRemoteProbeErrorMessage = '';
    ReadAloudAvailability.lastRemoteValidationLogSignature = '';
    return true;
  }

  private static async checkSystemTtsAvailable(): Promise<boolean> {
    ReadAloudAvailability.lastSystemProbeErrorMessage = '';
    let lastCreateEngineError: string = '';
    const candidates: textToSpeech.CreateEngineParams[] = [
      { language: 'zh-CN', person: 0, online: SYSTEM_TTS_ONLINE_MODE },
      { language: 'zh-CN', person: 0, online: SYSTEM_TTS_OFFLINE_MODE },
      { language: 'zh_CN', person: 0, online: SYSTEM_TTS_ONLINE_MODE },
      { language: 'zh_CN', person: 0, online: SYSTEM_TTS_OFFLINE_MODE },
      { language: 'en-US', person: 0, online: SYSTEM_TTS_ONLINE_MODE },
      { language: 'en-US', person: 0, online: SYSTEM_TTS_OFFLINE_MODE }
    ];

    for (const candidate of candidates) {
      let engine: textToSpeech.TextToSpeechEngine | null = null;
      try {
        engine = await textToSpeech.createEngine(candidate);
        try {
          const voices = await engine.listVoices({
            requestId: ReadAloudRequestIdGenerator.next('probe_voice'),
            online: candidate.online
          });
          logger.info(
            TAG,
            `SYSTEM TTS 可用性探测成功: language=${candidate.language}, person=${candidate.person}, online=${candidate.online}, voices=${voices.length}`
          );
        } catch (voiceError) {
          const voiceErrorText = ReadAloudAvailability.formatError(voiceError);
          logger.warn(
            TAG,
            `SYSTEM TTS 引擎已创建但音色查询失败: language=${candidate.language}, person=${candidate.person}, online=${candidate.online}, error=${voiceErrorText}`
          );
        }
        logger.info(
          TAG,
          `SYSTEM TTS 引擎可用: language=${candidate.language}, person=${candidate.person}, online=${candidate.online}`
        );
        ReadAloudAvailability.lastSystemProbeErrorMessage = '';
        return true;
      } catch (error) {
        lastCreateEngineError = ReadAloudAvailability.formatError(error);
      } finally {
        if (engine) {
          try {
            engine.shutdown();
          } catch (shutdownError) {
            logger.debug(TAG, `SYSTEM TTS 回退引擎释放失败: ${String(shutdownError)}`);
          }
        }
      }
    }

    if (lastCreateEngineError.length > 0) {
      if (ReadAloudAvailability.lastSystemProbeErrorMessage.length > 0) {
        ReadAloudAvailability.lastSystemProbeErrorMessage =
          `${ReadAloudAvailability.lastSystemProbeErrorMessage}; createEngine 失败: ${lastCreateEngineError}`;
      } else {
        ReadAloudAvailability.lastSystemProbeErrorMessage = `createEngine 失败: ${lastCreateEngineError}`;
      }
      logger.warn(TAG, `SYSTEM TTS 可用性探测失败: ${ReadAloudAvailability.lastSystemProbeErrorMessage}`);
    }
    return false;
  }

  private static checkRemoteTtsConfigured(settingsOverride?: ReadAloudSettings): boolean {
    try {
      const settings = settingsOverride !== undefined
        ? normalizeReadAloudSettings(settingsOverride)
        : loadGlobalReadAloudSettings(SettingsManager.getInstance());
      const remote = settings.remote;
      if (!remote) {
        return ReadAloudAvailability.reportRemoteValidationFailure('remote settings is empty', null);
      }
      const endpoint = remote.endpoint.trim();
      if (endpoint.length <= 0) {
        return ReadAloudAvailability.reportRemoteValidationFailure('remote endpoint is empty', remote);
      }
      const model = remote.model.trim();
      if (model.length <= 0) {
        return ReadAloudAvailability.reportRemoteValidationFailure('remote model is empty', remote);
      }
      const voice = remote.voice.trim();
      if (voice.length <= 0) {
        return ReadAloudAvailability.reportRemoteValidationFailure('remote voice is empty', remote);
      }
      const apiKey = remote.apiKey.trim();
      const customHeadersLower = (remote.customHeadersJson ?? '').toLowerCase();
      if (
        apiKey.length <= 0 &&
        !customHeadersLower.includes('"authorization"') &&
        !customHeadersLower.includes('"api-key"')
      ) {
        return ReadAloudAvailability.reportRemoteValidationFailure('remote api key is empty', remote);
      }
      return ReadAloudAvailability.reportRemoteValidationSuccess();
    } catch (error) {
      ReadAloudAvailability.lastRemoteProbeErrorMessage = ReadAloudAvailability.formatError(error);
      ReadAloudAvailability.lastRemoteValidationLogSignature = '';
      logger.warn(TAG, `REMOTE TTS availability check failed: ${ReadAloudAvailability.lastRemoteProbeErrorMessage}`);
      return false;
    }
  }

  private static formatError(error: Object | string): string {
    if (typeof error === 'string') {
      return error;
    }
    const errorLike = error as ReadAloudProbeErrorLike;
    const errorObj = error as Error;
    const rawCode: number | string | undefined = (
      typeof errorLike.code === 'number' || typeof errorLike.code === 'string'
    ) ? errorLike.code : errorLike.errorCode;
    const hasCode = typeof rawCode === 'number' || typeof rawCode === 'string';
    const detailMessage = (
      errorObj.message && errorObj.message.length > 0
    ) ? errorObj.message : (
      errorLike.message && errorLike.message.length > 0
    ) ? errorLike.message : (
      errorLike.errorMessage && errorLike.errorMessage.length > 0
    ) ? errorLike.errorMessage : (
      errorLike.errMsg && errorLike.errMsg.length > 0
    ) ? errorLike.errMsg : '';
    if (detailMessage.length > 0) {
      if (hasCode) {
        return `code=${rawCode}, message=${detailMessage}`;
      }
      return detailMessage;
    }
    try {
      const jsonText = JSON.stringify(error);
      if (jsonText && jsonText.length > 0 && jsonText !== '{}') {
        return jsonText;
      }
    } catch (formatError) {
      logger.debug(TAG, `格式化探测错误信息失败: ${String(formatError)}`);
    }
    if (hasCode) {
      return `code=${rawCode}`;
    }
    return String(error);
  }
}
