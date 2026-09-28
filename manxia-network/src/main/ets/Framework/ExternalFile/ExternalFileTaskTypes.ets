import { SafeUtils } from 'manxia_core/src/main/ets/Utils/SafeUtils';

export enum ExternalFileTaskKind {
  AVIF = 'avif',
  IMAGE = 'image',
  BACKUP = 'backup',
  COMIC = 'comic',
  EBOOK = 'ebook',
  PDF = 'pdf',
  JSON = 'json',
  FONT = 'font',
  CODE = 'code',
  UNKNOWN = 'unknown'
}

export enum ExternalFileTaskSource {
  FILE_OPEN = 'file_open',
  FILE_CONTEXT_MENU = 'file_context_menu',
  SYSTEM_SHARE = 'system_share',
  NETWORK_FOLDER = 'network_folder',
  TRANSFER = 'transfer',
  FALLBACK = 'fallback'
}

export class ExternalFileTaskParams {
  public kind: ExternalFileTaskKind = ExternalFileTaskKind.UNKNOWN;
  public uris: string[] = [];
  public mimeType: string = '';
  public language: string = '';
  public displayName: string = '';
  public source: ExternalFileTaskSource = ExternalFileTaskSource.FILE_OPEN;
  public target: string = '';
  public transferRecordId: string = '';
  public titleHint: string = '';
  public taskInstanceId: string = '';
  public createdAt: number = 0;
}

export class ExternalFileTaskParamsJson {
  public kind?: string;
  public uris?: string[];
  public mimeType?: string;
  public language?: string;
  public displayName?: string;
  public source?: string;
  public target?: string;
  public transferRecordId?: string;
  public titleHint?: string;
  public taskInstanceId?: string;
  public createdAt?: number;
}

export class ExternalFileTaskFactory {
  public static createSingleFileTask(
    kind: ExternalFileTaskKind,
    uri: string,
    mimeType: string,
    source: ExternalFileTaskSource,
    displayName: string = '',
    language: string = '',
    target: string = '',
    transferRecordId: string = ''
  ): ExternalFileTaskParams {
    const params = new ExternalFileTaskParams();
    params.kind = kind;
    params.uris = [uri];
    params.mimeType = mimeType;
    params.source = source;
    params.displayName = displayName;
    params.language = language;
    params.target = target;
    params.transferRecordId = transferRecordId;
    params.createdAt = Date.now();
    return params;
  }

  public static createShareTask(
    kind: ExternalFileTaskKind,
    uris: string[],
    source: ExternalFileTaskSource = ExternalFileTaskSource.SYSTEM_SHARE,
    displayName: string = ''
  ): ExternalFileTaskParams {
    const params = new ExternalFileTaskParams();
    params.kind = kind;
    params.uris = ExternalFileTaskFactory.copyStringArray(uris);
    params.source = source;
    params.displayName = displayName;
    params.createdAt = Date.now();
    return params;
  }

  public static clone(source: ExternalFileTaskParams): ExternalFileTaskParams {
    const params = new ExternalFileTaskParams();
    params.kind = source.kind;
    params.uris = ExternalFileTaskFactory.copyStringArray(source.uris);
    params.mimeType = source.mimeType;
    params.language = source.language;
    params.displayName = source.displayName;
    params.source = source.source;
    params.target = source.target;
    params.transferRecordId = source.transferRecordId;
    params.titleHint = source.titleHint;
    params.taskInstanceId = source.taskInstanceId;
    params.createdAt = source.createdAt;
    return params;
  }

  public static withInstanceId(source: ExternalFileTaskParams, instanceId: string): ExternalFileTaskParams {
    const params = ExternalFileTaskFactory.clone(source);
    params.taskInstanceId = instanceId;
    return params;
  }

  public static serialize(params: ExternalFileTaskParams): string {
    return SafeUtils.stringifyJson(params, '');
  }

  public static deserialize(json: string): ExternalFileTaskParams | null {
    const raw = SafeUtils.parseOptional<ExternalFileTaskParamsJson>(json);
    if (!raw) {
      return null;
    }
    return ExternalFileTaskFactory.fromJson(raw);
  }

  public static fromJson(raw: ExternalFileTaskParamsJson): ExternalFileTaskParams {
    const params = new ExternalFileTaskParams();
    params.kind = ExternalFileTaskFactory.normalizeKind(raw.kind);
    params.uris = ExternalFileTaskFactory.copyStringArray(raw.uris);
    params.mimeType = ExternalFileTaskFactory.normalizeString(raw.mimeType);
    params.language = ExternalFileTaskFactory.normalizeString(raw.language);
    params.displayName = ExternalFileTaskFactory.normalizeString(raw.displayName);
    params.source = ExternalFileTaskFactory.normalizeSource(raw.source);
    params.target = ExternalFileTaskFactory.normalizeString(raw.target);
    params.transferRecordId = ExternalFileTaskFactory.normalizeString(raw.transferRecordId);
    params.titleHint = ExternalFileTaskFactory.normalizeString(raw.titleHint);
    params.taskInstanceId = ExternalFileTaskFactory.normalizeString(raw.taskInstanceId);
    params.createdAt = typeof raw.createdAt === 'number' ? raw.createdAt : Date.now();
    return params;
  }

  public static normalizeKind(value: string | undefined): ExternalFileTaskKind {
    switch (value) {
      case ExternalFileTaskKind.AVIF:
        return ExternalFileTaskKind.AVIF;
      case ExternalFileTaskKind.IMAGE:
        return ExternalFileTaskKind.IMAGE;
      case ExternalFileTaskKind.BACKUP:
        return ExternalFileTaskKind.BACKUP;
      case ExternalFileTaskKind.COMIC:
        return ExternalFileTaskKind.COMIC;
      case ExternalFileTaskKind.EBOOK:
        return ExternalFileTaskKind.EBOOK;
      case ExternalFileTaskKind.PDF:
        return ExternalFileTaskKind.PDF;
      case ExternalFileTaskKind.JSON:
        return ExternalFileTaskKind.JSON;
      case ExternalFileTaskKind.FONT:
        return ExternalFileTaskKind.FONT;
      case ExternalFileTaskKind.CODE:
        return ExternalFileTaskKind.CODE;
      default:
        return ExternalFileTaskKind.UNKNOWN;
    }
  }

  public static normalizeSource(value: string | undefined): ExternalFileTaskSource {
    switch (value) {
      case ExternalFileTaskSource.FILE_CONTEXT_MENU:
        return ExternalFileTaskSource.FILE_CONTEXT_MENU;
      case ExternalFileTaskSource.SYSTEM_SHARE:
        return ExternalFileTaskSource.SYSTEM_SHARE;
      case ExternalFileTaskSource.NETWORK_FOLDER:
        return ExternalFileTaskSource.NETWORK_FOLDER;
      case ExternalFileTaskSource.TRANSFER:
        return ExternalFileTaskSource.TRANSFER;
      case ExternalFileTaskSource.FALLBACK:
        return ExternalFileTaskSource.FALLBACK;
      case ExternalFileTaskSource.FILE_OPEN:
      default:
        return ExternalFileTaskSource.FILE_OPEN;
    }
  }

  public static resolvePrimaryUri(params: ExternalFileTaskParams | null): string {
    if (!params || params.uris.length <= 0) {
      return '';
    }
    return params.uris[0];
  }

  public static resolveDisplayName(params: ExternalFileTaskParams | null): string {
    if (!params) {
      return '';
    }
    const explicitName = params.displayName.trim();
    if (explicitName.length > 0) {
      return explicitName;
    }
    const uri = ExternalFileTaskFactory.resolvePrimaryUri(params);
    if (uri.length <= 0) {
      return '';
    }
    return ExternalFileTaskFactory.extractFileName(uri);
  }

  public static extractFileName(uri: string): string {
    const trimmed = uri.trim();
    if (trimmed.length <= 0) {
      return '';
    }
    const queryIndex = trimmed.indexOf('?');
    const hashIndex = trimmed.indexOf('#');
    let endIndex = trimmed.length;
    if (queryIndex >= 0 && hashIndex >= 0) {
      endIndex = Math.min(queryIndex, hashIndex);
    } else if (queryIndex >= 0) {
      endIndex = queryIndex;
    } else if (hashIndex >= 0) {
      endIndex = hashIndex;
    }
    const pathPart = trimmed.substring(0, endIndex);
    const slashIndex = pathPart.lastIndexOf('/');
    const rawName = slashIndex >= 0 ? pathPart.substring(slashIndex + 1) : pathPart;
    try {
      return decodeURIComponent(rawName);
    } catch (_error) {
      return rawName;
    }
  }

  private static copyStringArray(value: string[] | undefined): string[] {
    const result: string[] = [];
    if (!value) {
      return result;
    }
    for (let i = 0; i < value.length; i++) {
      const item = value[i];
      if (typeof item === 'string' && item.trim().length > 0) {
        result.push(item);
      }
    }
    return result;
  }

  private static normalizeString(value: string | undefined): string {
    return value ? value : '';
  }
}
