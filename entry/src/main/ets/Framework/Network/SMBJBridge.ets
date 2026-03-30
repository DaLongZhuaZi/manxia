import fs from '@ohos.file.fs';
import util from '@ohos.util';
import { logger } from '../../Utils/Logger';

const TAG = 'SMBJBridge';
const SMB_MODULE_NAME = '@ohos/smbj';
const SMB_RUNTIME_MODULE_PATH = './SMBJBridgeRuntime';
const FILE_ATTRIBUTE_DIRECTORY = 0x00000010;

export interface SMBJBridgeConfig {
  host: string;
  shareName: string;
  port: number;
  username: string;
  password: string;
  domain: string;
  clientIP: string;
  timeoutMs: number;
  packetConcurrency: number;
}

export interface SMBJBridgeOperationResult {
  success: boolean;
  message: string;
}

export interface SMBJBridgeDirectoryEntry {
  name: string;
  isDirectory: boolean;
  size: number;
  lastModified: number;
  attributes: number;
}

export interface SMBJBridgeDirectoryListResult extends SMBJBridgeOperationResult {
  entries: SMBJBridgeDirectoryEntry[];
}

interface SMB2ClientOptions {
  share: string;
  port?: number;
  packetConcurrency?: number;
  autoCloseTimeout?: number;
  domain: string;
  username: string;
  password: string;
  clientIP?: string;
}

interface SMBReadFileOptions {
  encoding?: 'UTF-8';
}

interface SMBJRuntimeModule {
  createClient(options: SMB2ClientOptions): ESObject;
  readdir(client: ESObject, path: string, callback: (error: ESObject | null, files: string[]) => void): void;
  readFile(
    client: ESObject,
    path: string,
    options: SMBReadFileOptions,
    callback: (error: ESObject | null, content: ESObject) => void
  ): void;
  close(client: ESObject): void;
}

interface SMBJClientHandle {
  runtime: SMBJRuntimeModule;
  client: ESObject;
}

let smbRuntimeModulePromise: Promise<SMBJRuntimeModule> | null = null;

async function loadSMB2Module(): Promise<SMBJRuntimeModule> {
  if (!smbRuntimeModulePromise) {
    smbRuntimeModulePromise = import('./SMBJBridgeRuntime')
      .then((namespace: ESObject) => {
        const moduleValue = namespace as SMBJRuntimeModule;
        if (!moduleValue ||
          typeof moduleValue.createClient !== 'function' ||
          typeof moduleValue.readdir !== 'function' ||
          typeof moduleValue.readFile !== 'function' ||
          typeof moduleValue.close !== 'function') {
          throw new Error('Invalid SMB runtime module export');
        }
        logger.info(TAG, `Loaded SMB runtime module: ${SMB_RUNTIME_MODULE_PATH} -> ${SMB_MODULE_NAME}`);
        return moduleValue;
      })
      .catch((error: Object) => {
        smbRuntimeModulePromise = null;
        throw new Error(extractErrorMessage(error));
      });
  }
  return smbRuntimeModulePromise;
}

function createClientOptions(config: SMBJBridgeConfig): SMB2ClientOptions {
  return {
    share: `\\\\${config.host}\\${config.shareName}`,
    port: config.port,
    packetConcurrency: config.packetConcurrency,
    autoCloseTimeout: config.timeoutMs,
    domain: config.domain,
    username: config.username,
    password: config.password,
    clientIP: config.clientIP
  };
}

function extractErrorMessage(error: Object): string {
  if (error && typeof (error as Error).message === 'string' && (error as Error).message.length > 0) {
    return (error as Error).message;
  }
  try {
    const serialized = JSON.stringify(error);
    if (serialized && serialized !== '{}') {
      return serialized;
    }
  } catch (_ignored) {
  }
  return String(error);
}

function buildErrorMessage(prefix: string, error: Object): string {
  const detail = extractErrorMessage(error);
  return detail.length > 0 ? `${prefix}: ${detail}` : prefix;
}

function normalizeRemotePath(remotePath: string): string {
  const trimmed = remotePath.trim();
  if (trimmed === '\\' || trimmed === '/') {
    return '';
  }
  return trimmed;
}

function joinRemotePath(basePath: string, name: string): string {
  const normalizedBase = normalizeRemotePath(basePath);
  const normalizedName = name.trim().replace(/^\\+/, '').replace(/^\/+/, '');
  if (normalizedBase.length === 0) {
    return normalizedName;
  }
  if (normalizedName.length === 0) {
    return normalizedBase;
  }
  return `${normalizedBase}\\${normalizedName}`;
}

function readByte(bufferLike: ESObject, index: number): number {
  const record = bufferLike as Record<string, ESObject>;
  const readUInt8Value: ESObject = record['readUInt8'];
  if (typeof readUInt8Value === 'function') {
    return Number((readUInt8Value as (position: number) => number)(index)) & 0xFF;
  }
  const rawValue: ESObject = record[`${index}`];
  if (typeof rawValue === 'number') {
    return Number(rawValue) & 0xFF;
  }
  return 0;
}

function getBufferLength(bufferLike: ESObject): number {
  const record = bufferLike as Record<string, ESObject>;
  const byteLengthValue: ESObject = record['byteLength'];
  if (typeof byteLengthValue === 'number') {
    return Math.max(0, Math.floor(Number(byteLengthValue)));
  }
  const lengthValue: ESObject = record['length'];
  if (typeof lengthValue === 'number') {
    return Math.max(0, Math.floor(Number(lengthValue)));
  }
  return 0;
}

function toArrayBuffer(bufferLike: ESObject): ArrayBuffer {
  if (bufferLike instanceof ArrayBuffer) {
    return bufferLike.slice(0);
  }
  if (ArrayBuffer.isView(bufferLike)) {
    const view = bufferLike as Uint8Array;
    return view.buffer.slice(view.byteOffset, view.byteOffset + view.byteLength);
  }

  if (typeof bufferLike === 'string') {
    return new util.TextEncoder().encodeInto(bufferLike).buffer;
  }

  const length = getBufferLength(bufferLike);
  const bytes = new Uint8Array(length);
  for (let index = 0; index < length; index++) {
    bytes[index] = readByte(bufferLike, index);
  }
  return bytes.buffer;
}

function safeClose(handle: SMBJClientHandle | null): void {
  if (!handle) {
    return;
  }
  try {
    handle.runtime.close(handle.client);
  } catch (_ignored) {
  }
}

async function createClient(config: SMBJBridgeConfig): Promise<SMBJClientHandle> {
  const runtime = await loadSMB2Module();
  return {
    runtime: runtime,
    client: runtime.createClient(createClientOptions(config))
  };
}

function readdirAsync(handle: SMBJClientHandle, remotePath: string): Promise<string[]> {
  const requestPath = normalizeRemotePath(remotePath);
  return new Promise<string[]>((resolve, reject) => {
    try {
      handle.runtime.readdir(handle.client, requestPath, (error: ESObject | null, files: string[]) => {
        if (error) {
          reject(error);
          return;
        }
        resolve(Array.isArray(files) ? files : []);
      });
    } catch (error) {
      reject(error as Object);
    }
  });
}

function readFileAsync(handle: SMBJClientHandle, remotePath: string): Promise<ESObject> {
  const requestPath = normalizeRemotePath(remotePath);
  const readOptions: SMBReadFileOptions = {
  };
  return new Promise<ESObject>((resolve, reject) => {
    try {
      handle.runtime.readFile(handle.client, requestPath, readOptions, (error: ESObject | null, content: ESObject) => {
        if (error) {
          reject(error);
          return;
        }
        resolve(content);
      });
    } catch (error) {
      reject(error as Object);
    }
  });
}

async function isDirectoryPath(handle: SMBJClientHandle, remotePath: string): Promise<boolean> {
  try {
    await readdirAsync(handle, remotePath);
    return true;
  } catch (_ignored) {
    return false;
  }
}

async function listDirectoryEntries(handle: SMBJClientHandle, remotePath: string): Promise<SMBJBridgeDirectoryEntry[]> {
  const names = await readdirAsync(handle, remotePath);
  const entries: SMBJBridgeDirectoryEntry[] = [];

  for (let index = 0; index < names.length; index++) {
    const trimmedName = String(names[index] || '').trim();
    if (trimmedName.length === 0 || trimmedName === '.' || trimmedName === '..') {
      continue;
    }
    const childPath = joinRemotePath(remotePath, trimmedName);
    const isDirectory = await isDirectoryPath(handle, childPath);
    entries.push({
      name: trimmedName,
      isDirectory: isDirectory,
      size: 0,
      lastModified: 0,
      attributes: isDirectory ? FILE_ATTRIBUTE_DIRECTORY : 0
    });
  }

  return entries;
}

export class SMBJBridgeClient {
  public async testConnection(
    config: SMBJBridgeConfig,
    remotePath: string
  ): Promise<SMBJBridgeOperationResult> {
    let handle: SMBJClientHandle | null = null;
    try {
      handle = await createClient(config);
      await readdirAsync(handle, remotePath);
      return {
        success: true,
        message: 'SMB connection success'
      };
    } catch (error) {
      return {
        success: false,
        message: buildErrorMessage('SMB connection failed', error as Object)
      };
    } finally {
      safeClose(handle);
    }
  }

  public async listDirectory(
    config: SMBJBridgeConfig,
    remotePath: string
  ): Promise<SMBJBridgeDirectoryListResult> {
    let handle: SMBJClientHandle | null = null;
    try {
      handle = await createClient(config);
      const entries = await listDirectoryEntries(handle, remotePath);
      return {
        success: true,
        message: `SMB directory loaded: ${entries.length} entries`,
        entries: entries
      };
    } catch (error) {
      return {
        success: false,
        message: buildErrorMessage('SMB directory load failed', error as Object),
        entries: []
      };
    } finally {
      safeClose(handle);
    }
  }

  public async downloadFile(
    config: SMBJBridgeConfig,
    remotePath: string,
    localPath: string
  ): Promise<SMBJBridgeOperationResult> {
    let handle: SMBJClientHandle | null = null;
    let localFile: fs.File | null = null;
    try {
      handle = await createClient(config);
      const content: ESObject = await readFileAsync(handle, remotePath);
      localFile = fs.openSync(localPath, fs.OpenMode.CREATE | fs.OpenMode.TRUNC | fs.OpenMode.WRITE_ONLY);
      fs.writeSync(localFile.fd, toArrayBuffer(content));
      return {
        success: true,
        message: 'SMB download success'
      };
    } catch (error) {
      return {
        success: false,
        message: buildErrorMessage('SMB download failed', error as Object)
      };
    } finally {
      if (localFile) {
        try {
          fs.closeSync(localFile);
        } catch (_ignored) {
        }
      }
      safeClose(handle);
    }
  }
}
