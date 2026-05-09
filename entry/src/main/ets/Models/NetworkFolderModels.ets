/**
 * Network folder models and helpers.
 */

export type NetworkFolderProtocol = 'webdav' | 'ftp' | 'ftps' | 'sftp' | 'smb';

export type NetworkFolderImportCategory =
  'comic' |
  'ebook' |
  'pdf' |
  'backup' |
  'json' |
  'font' |
  'code' |
  'avif' |
  'image' |
  'unknown' |
  'unsupported';

export interface NetworkFolderConnection {
  id: string;
  name: string;
  protocol: NetworkFolderProtocol;
  serverUrl: string;
  host: string;
  shareName: string;
  domain: string;
  clientIP: string;
  port: number;
  username: string;
  password: string;
  basePath: string;
  passive: boolean;
  verifySSL: boolean;
  verifyHostKey: boolean;
  timeoutMs: number;
  createdAt: number;
  lastUsedAt: number;
}

export interface NetworkFolderConnectionDraft {
  id?: string;
  name: string;
  protocol: NetworkFolderProtocol;
  serverUrl: string;
  host: string;
  shareName: string;
  domain: string;
  clientIP: string;
  port: number;
  username: string;
  password: string;
  basePath: string;
  passive: boolean;
  verifySSL: boolean;
  verifyHostKey: boolean;
  timeoutMs: number;
}

export interface NetworkFolderEntry {
  key: string;
  name: string;
  relativePath: string;
  actualPath: string;
  size: number;
  isDirectory: boolean;
  lastModified: number;
  etag: string;
  contentType: string;
  permissions: string;
  importCategory: NetworkFolderImportCategory;
  cacheStatus: 'none' | 'cached' | 'stale';
  cachedLocalPath: string;
  versionTag: string;
}

export interface NetworkFolderBrowseResult {
  success: boolean;
  message: string;
  entries: NetworkFolderEntry[];
  fromCache: boolean;
  stale: boolean;
  loadedAt: number;
}

export interface NetworkFolderCacheStats {
  directoryCount: number;
  fileCount: number;
  totalBytes: number;
}

export interface NetworkFolderDirectoryCacheDetail {
  connectionId: string;
  relativePath: string;
  fetchedAt: number;
  entryCount: number;
}

export interface NetworkFolderDownloadCacheDetail {
  connectionId: string;
  relativePath: string;
  localPath: string;
  fileName: string;
  size: number;
  versionTag: string;
  cachedAt: number;
  lastAccessedAt: number;
  importCategory: NetworkFolderImportCategory;
  fileExists: boolean;
}

export interface NetworkFolderCacheDetail {
  stats: NetworkFolderCacheStats;
  directories: NetworkFolderDirectoryCacheDetail[];
  files: NetworkFolderDownloadCacheDetail[];
}

export interface NetworkFolderDownloadResult {
  success: boolean;
  message: string;
  localPath: string;
  fileUri: string;
  reusedCache: boolean;
  importCategory: NetworkFolderImportCategory;
}

export const NETWORK_FOLDER_COMIC_EXTENSIONS: string[] = [
  'zip', 'cbz', 'rar', 'cbr', '7z', 'tar', 'gz', 'tgz', 'bz2', 'xz', 'lzma'
];

export const NETWORK_FOLDER_EBOOK_EXTENSIONS: string[] = [
  'epub', 'mobi', 'azw', 'azw3', 'txt'
];

export const NETWORK_FOLDER_BACKUP_EXTENSIONS: string[] = [
  'mxbak', 'mxbackup'
];

export const NETWORK_FOLDER_JSON_EXTENSIONS: string[] = [
  'json', 'json5'
];

export const NETWORK_FOLDER_FONT_EXTENSIONS: string[] = [
  'ttf', 'otf', 'ttc', 'woff', 'woff2'
];

export const NETWORK_FOLDER_AVIF_EXTENSIONS: string[] = [
  'avif'
];

export const NETWORK_FOLDER_IMAGE_EXTENSIONS: string[] = [
  'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif', 'svg'
];

export const NETWORK_FOLDER_CODE_EXTENSIONS: string[] = [
  'ets', 'ts', 'tsx', 'js', 'jsx',
  'jsonc', 'xml', 'yaml', 'yml', 'md', 'markdown',
  'java', 'kt', 'c', 'cpp', 'h', 'hpp', 'py', 'rs',
  'cs', 'go', 'swift', 'rb', 'php', 'html', 'htm',
  'css', 'scss', 'less', 'sql', 'sh', 'bash', 'zsh',
  'ps1', 'bat', 'cmd', 'log', 'ini', 'conf', 'cfg',
  'toml', 'lua', 'r', 'dart', 'vue', 'svelte'
];

export function createEmptyNetworkFolderDraft(): NetworkFolderConnectionDraft {
  const draft: NetworkFolderConnectionDraft = {
    name: '',
    protocol: 'webdav',
    serverUrl: '',
    host: '',
    shareName: '',
    domain: '',
    clientIP: '',
    port: 443,
    username: '',
    password: '',
    basePath: '/',
    passive: true,
    verifySSL: true,
    verifyHostKey: true,
    timeoutMs: 30000
  };
  return draft;
}

export function createNetworkFolderConnection(
  draft: NetworkFolderConnectionDraft,
  existingId?: string
): NetworkFolderConnection {
  const now = Date.now();
  const connection: NetworkFolderConnection = {
    id: existingId ?? generateNetworkFolderConnectionId(),
    name: draft.name.trim(),
    protocol: draft.protocol,
    serverUrl: draft.serverUrl.trim(),
    host: draft.host.trim(),
    shareName: draft.shareName.trim(),
    domain: draft.domain.trim(),
    clientIP: draft.clientIP.trim(),
    port: sanitizePort(draft.protocol, draft.port),
    username: draft.username.trim(),
    password: draft.password,
    basePath: normalizeConnectionBasePath(draft.basePath),
    passive: draft.passive,
    verifySSL: draft.verifySSL,
    verifyHostKey: draft.verifyHostKey !== false,
    timeoutMs: sanitizeTimeout(draft.timeoutMs),
    createdAt: now,
    lastUsedAt: 0
  };
  return connection;
}

export function draftFromNetworkFolderConnection(
  connection: NetworkFolderConnection
): NetworkFolderConnectionDraft {
  const draft: NetworkFolderConnectionDraft = {
    id: connection.id,
    name: connection.name,
    protocol: connection.protocol,
    serverUrl: connection.serverUrl,
    host: connection.host,
    shareName: connection.shareName,
    domain: connection.domain,
    clientIP: connection.clientIP,
    port: connection.port,
    username: connection.username,
    password: connection.password,
    basePath: connection.basePath,
    passive: connection.passive,
    verifySSL: connection.verifySSL,
    verifyHostKey: connection.verifyHostKey !== false,
    timeoutMs: connection.timeoutMs
  };
  return draft;
}

export function normalizeConnectionBasePath(path: string): string {
  if (!path || path.trim().length === 0) {
    return '/';
  }
  let normalized = path.trim().replace(/\\/g, '/');
  if (!normalized.startsWith('/')) {
    normalized = `/${normalized}`;
  }
  normalized = normalized.replace(/\/+/g, '/');
  if (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized.length > 0 ? normalized : '/';
}

export function normalizeRelativeNetworkFolderPath(path: string): string {
  if (!path || path.trim().length === 0 || path === '/') {
    return '/';
  }
  let normalized = path.trim().replace(/\\/g, '/');
  if (!normalized.startsWith('/')) {
    normalized = `/${normalized}`;
  }
  normalized = normalized.replace(/\/+/g, '/');
  if (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized.length > 0 ? normalized : '/';
}

export function joinRelativeNetworkFolderPath(parentPath: string, name: string): string {
  const cleanParent = normalizeRelativeNetworkFolderPath(parentPath);
  const cleanName = name.trim().replace(/^\/+/, '').replace(/\/+$/, '');
  if (cleanName.length === 0) {
    return cleanParent;
  }
  if (cleanParent === '/') {
    return `/${cleanName}`;
  }
  return `${cleanParent}/${cleanName}`;
}

function normalizeNetworkFolderFileNameForDetect(fileName: string): string {
  const trimmed = fileName.trim();
  if (trimmed.length === 0) {
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

  const withoutQuery = trimmed.substring(0, endIndex);
  try {
    return decodeURIComponent(withoutQuery).trim().toLowerCase();
  } catch {
    return withoutQuery.trim().toLowerCase();
  }
}

export function getNetworkFolderFileExtension(fileName: string): string {
  const normalizedName = normalizeNetworkFolderFileNameForDetect(fileName);
  if (normalizedName.length === 0) {
    return '';
  }
  const lastDotIndex = normalizedName.lastIndexOf('.');
  if (lastDotIndex < 0 || lastDotIndex >= normalizedName.length - 1) {
    return '';
  }
  return normalizedName.substring(lastDotIndex + 1);
}

export function inferNetworkFolderImportCategory(fileName: string): NetworkFolderImportCategory {
  const extension = getNetworkFolderFileExtension(fileName);
  if (extension.length === 0) {
    return 'unsupported';
  }

  if (NETWORK_FOLDER_BACKUP_EXTENSIONS.includes(extension)) {
    return 'backup';
  }
  if (NETWORK_FOLDER_COMIC_EXTENSIONS.includes(extension)) {
    return 'comic';
  }
  if (extension === 'pdf') {
    return 'pdf';
  }
  if (NETWORK_FOLDER_EBOOK_EXTENSIONS.includes(extension)) {
    return 'ebook';
  }
  if (NETWORK_FOLDER_JSON_EXTENSIONS.includes(extension)) {
    return 'json';
  }
  if (NETWORK_FOLDER_FONT_EXTENSIONS.includes(extension)) {
    return 'font';
  }
  if (NETWORK_FOLDER_AVIF_EXTENSIONS.includes(extension)) {
    return 'avif';
  }
  if (NETWORK_FOLDER_IMAGE_EXTENSIONS.includes(extension)) {
    return 'image';
  }
  if (NETWORK_FOLDER_CODE_EXTENSIONS.includes(extension)) {
    return 'code';
  }
  return 'unknown';
}

export function isNetworkFolderImportSupported(category: NetworkFolderImportCategory): boolean {
  return category !== 'unsupported';
}

export function getNetworkFolderProtocolLabel(protocol: NetworkFolderProtocol): string {
  switch (protocol) {
    case 'webdav':
      return 'WebDAV';
    case 'ftp':
      return 'FTP';
    case 'ftps':
      return 'FTPS';
    case 'sftp':
      return 'SFTP';
    case 'smb':
      return 'SMB';
    default:
      return protocol;
  }
}

function generateNetworkFolderConnectionId(): string {
  return `network_folder_${Date.now().toString(36)}_${Math.random().toString(36).slice(2, 9)}`;
}

function sanitizePort(protocol: NetworkFolderProtocol, port: number): number {
  if (typeof port === 'number' && Number.isFinite(port) && port > 0 && port <= 65535) {
    return Math.floor(port);
  }
  if (protocol === 'ftps') {
    return 990;
  }
  if (protocol === 'ftp') {
    return 21;
  }
  if (protocol === 'sftp') {
    return 22;
  }
  if (protocol === 'smb') {
    return 445;
  }
  return 443;
}

function sanitizeTimeout(timeoutMs: number): number {
  if (typeof timeoutMs !== 'number' || !Number.isFinite(timeoutMs)) {
    return 30000;
  }
  return Math.max(5000, Math.min(120000, Math.floor(timeoutMs)));
}

// ==================== Network Scan Types ====================

export interface ProtocolPort {
  protocol: number;
  port: number;
}

export interface NetworkScanHost {
  ip: string;
  hostname: string;
  protocols: number[];
  protocolPorts: ProtocolPort[];
}

export interface NetworkScanProgress {
  scannedHosts: number;
  totalHosts: number;
  currentIP: string;
}

export interface NetworkSMBShare {
  name: string;
  remark: string;
  type: number;
  isHidden: boolean;
  isDiskShare: boolean;
}

export interface NetworkSMBEnumResult {
  success: boolean;
  message: string;
  shares: NetworkSMBShare[];
}

export function mapScanProtocolToFolderProtocol(protocol: number): NetworkFolderProtocol {
  switch (protocol) {
    case 0: return 'ftp';
    case 1: return 'sftp';
    case 2: return 'ftps';
    case 3: return 'webdav';
    case 4: return 'webdav';
    case 5: return 'smb';
    default: return 'webdav';
  }
}

export function getScanProtocolLabel(protocol: number): string {
  switch (protocol) {
    case 0: return 'FTP';
    case 1: return 'SFTP';
    case 2: return 'FTPS';
    case 3: return 'WebDAV';
    case 4: return 'WebDAV (HTTPS)';
    case 5: return 'SMB';
    default: return 'Unknown';
  }
}

export function draftFromScanResult(
  host: NetworkScanHost,
  protocol: NetworkFolderProtocol
): NetworkFolderConnectionDraft {
  const draft = createEmptyNetworkFolderDraft();
  draft.protocol = protocol;
  draft.host = host.ip;
  draft.name = host.hostname.length > 0 ? `${host.hostname} (${host.ip})` : host.ip;

  // Find the actual port from protocolPorts
  const protocolNum = protocol === 'ftp' ? 0 :
    protocol === 'sftp' ? 1 :
    protocol === 'ftps' ? 2 :
    protocol === 'webdav' ? 3 :
    protocol === 'smb' ? 5 : -1;

  // For WebDAV, check if there's a secure variant (WEBDAVS = 4)
  if (protocol === 'webdav') {
    const webdavsEntry = host.protocolPorts.find((pp: ProtocolPort) => pp.protocol === 4);
    const webdavEntry = host.protocolPorts.find((pp: ProtocolPort) => pp.protocol === 3);
    if (webdavsEntry) {
      draft.port = webdavsEntry.port;
      draft.serverUrl = `https://${host.ip}:${webdavsEntry.port}`;
      draft.verifySSL = true;
    } else if (webdavEntry) {
      draft.port = webdavEntry.port;
      draft.serverUrl = `http://${host.ip}:${webdavEntry.port}`;
      draft.verifySSL = false;
    } else {
      draft.port = 80;
      draft.serverUrl = `http://${host.ip}`;
      draft.verifySSL = false;
    }
  } else {
    // For other protocols, find the matching entry
    const entry = host.protocolPorts.find((pp: ProtocolPort) => pp.protocol === protocolNum);
    if (entry) {
      draft.port = entry.port;
    } else {
      // Fallback to default ports
      if (protocol === 'smb') {
        draft.port = 445;
      } else if (protocol === 'ftps') {
        draft.port = 990;
      } else if (protocol === 'sftp') {
        draft.port = 22;
      } else {
        draft.port = 21;
      }
    }
  }
  return draft;
}
