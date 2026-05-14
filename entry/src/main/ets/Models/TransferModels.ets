/**
 * 局域网传书功能模型定义
 */

import {
  NETWORK_FOLDER_AVIF_EXTENSIONS,
  NETWORK_FOLDER_BACKUP_EXTENSIONS,
  NETWORK_FOLDER_CODE_EXTENSIONS,
  NETWORK_FOLDER_COMIC_EXTENSIONS,
  NETWORK_FOLDER_EBOOK_EXTENSIONS,
  NETWORK_FOLDER_FONT_EXTENSIONS,
  NETWORK_FOLDER_JSON_EXTENSIONS
} from './NetworkFolderModels';
import type { NetworkFolderImportCategory } from './NetworkFolderModels';

export type TransferServerStatus = 'stopped' | 'starting' | 'running' | 'stopping' | 'error';
export type TransferSessionStatus = 'idle' | 'ready' | 'paired' | 'expired';
export type TransferRuntimePhase = 'scaffold' | 'upload_pending' | 'active';
export type TransferUploadStatus = 'received' | 'handoff_sent' | 'imported' | 'import_failed' | 'import_cancelled';

export interface TransferConfig {
  port: number;
  autoStopMinutes: number;
  maxFileSizeMb: number;
  allowBackgroundTransfer: boolean;
  wsEnabled: boolean;
}

export interface TransferLocalAddress {
  label: string;
  host: string;
  port: number;
  url: string;
  isPrimary: boolean;
}

export interface TransferSessionInfo {
  sessionId: string;
  pairCode: string;
  token: string;
  status: TransferSessionStatus;
  createdAt: number;
  expiresAt: number;
  lastAccessAt: number;
  clientName: string;
  clientIp: string;
}

export interface TransferServerRuntime {
  status: TransferServerStatus;
  phase: TransferRuntimePhase;
  activePort: number;
  webSocketPort: number;
  startedAt: number;
  lastError: string;
  infoMessage: string;
  backgroundRunning: boolean;
  localAddresses: TransferLocalAddress[];
  session: TransferSessionInfo | null;
}

export interface TransferInfoResponse {
  ok: boolean;
  phase: TransferRuntimePhase;
  serviceStatus: TransferServerStatus;
  appName: string;
  protocolVersion: string;
  message: string;
  pairCode: string;
  sessionStatus: TransferSessionStatus;
  sessionExpiresAt: number;
  sessionClientName: string;
  sessionClientIp: string;
  port: number;
  webSocketPort: number;
  backgroundRunning: boolean;
  uploadEnabled: boolean;
  maxFileSizeMb: number;
  addressList: TransferLocalAddress[];
  supportedFileTypes: string[];
}

export interface TransferUploadRecord {
  id: string;
  fileName: string;
  localPath: string;
  localUri: string;
  fileSizeBytes: number;
  contentType: string;
  importCategory: NetworkFolderImportCategory;
  clientName: string;
  clientIp: string;
  source: string;
  receivedAt: number;
  status: TransferUploadStatus;
}

export const TRANSFER_PROTOCOL_VERSION: string = 'mx-transfer/0.1';

export const TRANSFER_SUPPORTED_FILE_TYPES: string[] = [
  ...NETWORK_FOLDER_COMIC_EXTENSIONS,
  ...NETWORK_FOLDER_EBOOK_EXTENSIONS,
  'pdf',
  ...NETWORK_FOLDER_BACKUP_EXTENSIONS,
  ...NETWORK_FOLDER_JSON_EXTENSIONS,
  ...NETWORK_FOLDER_FONT_EXTENSIONS,
  ...NETWORK_FOLDER_CODE_EXTENSIONS,
  ...NETWORK_FOLDER_AVIF_EXTENSIONS
];

export function createDefaultTransferConfig(): TransferConfig {
  const config: TransferConfig = {
    port: 15124,
    autoStopMinutes: 15,
    maxFileSizeMb: 2048,
    allowBackgroundTransfer: true,
    wsEnabled: true
  };
  return config;
}

export function createEmptyTransferServerRuntime(): TransferServerRuntime {
  const runtime: TransferServerRuntime = {
    status: 'stopped',
    phase: 'scaffold',
    activePort: 0,
    webSocketPort: 0,
    startedAt: 0,
    lastError: '',
    infoMessage: '服务未启动。',
    backgroundRunning: false,
    localAddresses: [],
    session: null
  };
  return runtime;
}

export function cloneTransferConfig(config: TransferConfig): TransferConfig {
  const cloned: TransferConfig = {
    port: config.port,
    autoStopMinutes: config.autoStopMinutes,
    maxFileSizeMb: config.maxFileSizeMb,
    allowBackgroundTransfer: config.allowBackgroundTransfer,
    wsEnabled: config.wsEnabled
  };
  return cloned;
}

export function cloneTransferLocalAddress(address: TransferLocalAddress): TransferLocalAddress {
  const cloned: TransferLocalAddress = {
    label: address.label,
    host: address.host,
    port: address.port,
    url: address.url,
    isPrimary: address.isPrimary
  };
  return cloned;
}

export function cloneTransferSessionInfo(session: TransferSessionInfo | null): TransferSessionInfo | null {
  if (session === null) {
    return null;
  }
  const cloned: TransferSessionInfo = {
    sessionId: session.sessionId,
    pairCode: session.pairCode,
    token: session.token,
    status: session.status,
    createdAt: session.createdAt,
    expiresAt: session.expiresAt,
    lastAccessAt: session.lastAccessAt,
    clientName: session.clientName,
    clientIp: session.clientIp
  };
  return cloned;
}

export function cloneTransferServerRuntime(runtime: TransferServerRuntime): TransferServerRuntime {
  const addresses: TransferLocalAddress[] = [];
  for (const address of runtime.localAddresses) {
    addresses.push(cloneTransferLocalAddress(address));
  }
  const cloned: TransferServerRuntime = {
    status: runtime.status,
    phase: runtime.phase,
    activePort: runtime.activePort,
    webSocketPort: runtime.webSocketPort,
    startedAt: runtime.startedAt,
    lastError: runtime.lastError,
    infoMessage: runtime.infoMessage,
    backgroundRunning: runtime.backgroundRunning,
    localAddresses: addresses,
    session: cloneTransferSessionInfo(runtime.session)
  };
  return cloned;
}

export function cloneTransferUploadRecord(record: TransferUploadRecord): TransferUploadRecord {
  const cloned: TransferUploadRecord = {
    id: record.id,
    fileName: record.fileName,
    localPath: record.localPath,
    localUri: record.localUri,
    fileSizeBytes: record.fileSizeBytes,
    contentType: record.contentType,
    importCategory: record.importCategory,
    clientName: record.clientName,
    clientIp: record.clientIp,
    source: record.source,
    receivedAt: record.receivedAt,
    status: record.status
  };
  return cloned;
}

export function cloneTransferUploadRecords(records: TransferUploadRecord[]): TransferUploadRecord[] {
  const result: TransferUploadRecord[] = [];
  for (const record of records) {
    result.push(cloneTransferUploadRecord(record));
  }
  return result;
}

export function sanitizeTransferConfig(source: TransferConfig): TransferConfig {
  const sanitized: TransferConfig = {
    port: sanitizeTransferPort(source.port),
    autoStopMinutes: sanitizeTransferAutoStopMinutes(source.autoStopMinutes),
    maxFileSizeMb: sanitizeTransferMaxFileSizeMb(source.maxFileSizeMb),
    allowBackgroundTransfer: source.allowBackgroundTransfer,
    wsEnabled: source.wsEnabled
  };
  return sanitized;
}

export function buildTransferInfoResponse(
  runtime: TransferServerRuntime,
  config: TransferConfig
): TransferInfoResponse {
  const addressList: TransferLocalAddress[] = [];
  for (const address of runtime.localAddresses) {
    addressList.push(cloneTransferLocalAddress(address));
  }
  const response: TransferInfoResponse = {
    ok: runtime.status === 'running',
    phase: runtime.phase,
    serviceStatus: runtime.status,
    appName: '漫匣',
    protocolVersion: TRANSFER_PROTOCOL_VERSION,
    message: runtime.infoMessage,
    pairCode: runtime.session !== null ? runtime.session.pairCode : '',
    sessionStatus: runtime.session !== null ? runtime.session.status : 'idle',
    sessionExpiresAt: runtime.session !== null ? runtime.session.expiresAt : 0,
    sessionClientName: runtime.session !== null ? runtime.session.clientName : '',
    sessionClientIp: runtime.session !== null ? runtime.session.clientIp : '',
    port: runtime.activePort,
    webSocketPort: runtime.webSocketPort,
    backgroundRunning: runtime.backgroundRunning,
    uploadEnabled: true,
    maxFileSizeMb: config.maxFileSizeMb,
    addressList: addressList,
    supportedFileTypes: cloneTransferSupportedFileTypes()
  };
  return response;
}

export function cloneTransferSupportedFileTypes(): string[] {
  const result: string[] = [];
  for (const fileType of TRANSFER_SUPPORTED_FILE_TYPES) {
    result.push(fileType);
  }
  return result;
}

export function isSupportedTransferFileName(fileName: string): boolean {
  const extension = getTransferFileExtension(fileName);
  if (extension.length <= 0) {
    return false;
  }
  for (const fileType of TRANSFER_SUPPORTED_FILE_TYPES) {
    if (fileType === extension) {
      return true;
    }
  }
  return false;
}

export function getTransferFileExtension(fileName: string): string {
  const normalizedName = fileName.trim().toLowerCase();
  const lastDot = normalizedName.lastIndexOf('.');
  if (lastDot < 0 || lastDot >= normalizedName.length - 1) {
    return '';
  }
  return normalizedName.substring(lastDot + 1);
}

export function isTransferAcceptedImportCategory(category: NetworkFolderImportCategory): boolean {
  return category === 'comic' ||
    category === 'ebook' ||
    category === 'pdf' ||
    category === 'backup' ||
    category === 'json' ||
    category === 'font' ||
    category === 'code' ||
    category === 'avif';
}

export function sanitizeTransferPort(port: number): number {
  if (!Number.isFinite(port)) {
    return 15124;
  }
  const normalized = Math.floor(port);
  if (normalized < 1024) {
    return 1024;
  }
  if (normalized > 65535) {
    return 65535;
  }
  return normalized;
}

export function sanitizeTransferAutoStopMinutes(minutes: number): number {
  if (!Number.isFinite(minutes)) {
    return 15;
  }
  const normalized = Math.floor(minutes);
  if (normalized < 1) {
    return 1;
  }
  if (normalized > 180) {
    return 180;
  }
  return normalized;
}

export function sanitizeTransferMaxFileSizeMb(sizeMb: number): number {
  if (!Number.isFinite(sizeMb)) {
    return 2048;
  }
  const normalized = Math.floor(sizeMb);
  if (normalized < 50) {
    return 50;
  }
  if (normalized > 10240) {
    return 10240;
  }
  return normalized;
}
