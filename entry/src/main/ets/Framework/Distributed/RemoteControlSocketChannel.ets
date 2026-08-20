// 文件路径: src/main/ets/Framework/Distributed/RemoteControlSocketChannel.ets
/**
 * 遥控器独立连接通道（局域网 TCP）
 *
 * 背景：分布式数据对象（distributedDataObject）通道在部分设备（如场景板）被平台级封禁
 * （objectstore 调用 GetAnonyLocalUdid 无权限，会话无法跨设备组网）。为保证遥控功能
 * 不依赖该平台能力，接续时额外建立一条设备间局域网 TCP 直连：
 * - 源端（遥控端）在接续打包时启动 TCP 服务，并把本机 IP + 端口写入 wantParam；
 * - 目标端（被控端）接续恢复时按该地址回连；
 * - 连接建立后双方以 '\n' 分隔的 JSON 行互发阅读状态快照（指令、进度、ack）。
 *
 * 与分布式数据对象通道并存：真实设备上两条通道会同时送达同一指令，接收方按
 * timestamp 去重（阅读器已有 lastRemoteInstructionTimestamp 守卫），进度为幂等覆盖。
 */

import socket from '@ohos.net.socket';
import { util } from '@kit.ArkTS';
import { fileIo } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { connection } from '@kit.NetworkKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';
import { getContext } from 'manxia_core/src/main/ets/GlobalContext';
import { EBookDataManager } from 'manxia_core/src/main/ets/Framework/Data/EBookDataManager';
import { DataManager } from '../Data/DataManager';
import {
  MangaTransferBundle,
  MangaTransferFileEntry,
  MangaChapterPagesEntry,
  MangaBundleReceiveResult,
  RemoteComicMetadata,
  RemoteChapterMetadata,
  RemotePageMetadata
} from './MangaTransferTypes';

const TAG = 'RemoteControlSocketChannel';
const REMOTE_CONTROL_CHANNEL_PORT = 15224;
const LISTEN_RETRY_DELAY_MS = 400;
const LISTEN_MAX_ATTEMPTS = 5;
const CONNECT_RETRY_DELAY_MS = 700;
const CONNECT_MAX_ATTEMPTS = 10;
const SOCKET_CONNECT_TIMEOUT_MS = 4000;
const MAX_RECEIVE_BUFFER_CHARS = 64 * 1024;
const FILE_STREAM_CHUNK_SIZE = 256 * 1024;
const FILE_HASH_CHUNK_SIZE = 1024 * 1024;
const FILE_REQUEST_TIMEOUT_MS = 300000;

function bytesToHex(bytes: Uint8Array): string {
  const hexChars = '0123456789abcdef';
  let result = '';
  for (let index = 0; index < bytes.length; index++) {
    const value = bytes[index];
    result += hexChars.charAt((value >> 4) & 0x0F);
    result += hexChars.charAt(value & 0x0F);
  }
  return result;
}

export interface RemoteControlSocketMessage {
  sessionId: string;
  bookId: string;
  sourceType: string;
  chapterIndex: number;
  pageIndex: number;
  offset: number;
  instructionType: string;
  instructionPayload: string;
  timestamp: number;
}

/** 文件流协议头（独立第二条 TCP 连接上使用，'\n' 结尾的单行 JSON） */
interface RemoteFileStreamHeader {
  kind: 'file_request' | 'file_start' | 'file_error';
  bookId: string;
  fileName?: string;
  totalBytes?: number;
  fileHash?: string;
  reason?: string;
}

/** 目标端文件接收结果 */
export interface RemoteFileReceiveResult {
  tempPath: string;
  fileName: string;
}

/** 书籍文件请求选项：超时时间 + 接收进度回调（用于接续传输加载动画） */
export interface RemoteFileRequestOptions {
  timeoutMs?: number;
  onProgress?: (receivedBytes: number, totalBytes: number) => void;
}

/** 漫画流协议头（与文件流共用第二条 TCP 连接，'\n' 结尾的 JSON 行） */
interface RemoteMangaStreamHeader {
  kind: 'file_request' | 'file_start' | 'file_error' | 'manga_request' | 'manga_start' | 'file_part' | 'manga_end';
  bookId?: string;
  totalBytes?: number;
  bundle?: MangaTransferBundle;
  relPath?: string;
  originalPath?: string;
  size?: number;
  hash?: string;
  reason?: string;
}

export class RemoteControlSocketChannel {
  private static instance: RemoteControlSocketChannel | null = null;

  private server: socket.TCPSocketServer | null = null;
  private serverConnection: socket.TCPSocketConnection | null = null;
  private fileConnection: socket.TCPSocketConnection | null = null;
  private client: socket.TCPSocket | null = null;
  private sessionId: string = '';
  private connected: boolean = false;
  private connectEpoch: number = 0;
  private receiveBuffer: string = '';
  private remoteIp: string = '';
  private remotePort: number = 0;
  private fileRequestEpoch: number = 0;
  private onMessageCallback: ((message: RemoteControlSocketMessage) => void) | null = null;
  private onStatusCallback: ((connected: boolean, detail: string) => void) | null = null;
  private readonly decoder: util.TextDecoder = new util.TextDecoder('utf-8');
  private readonly encoder: util.TextEncoder = new util.TextEncoder();

  private constructor() {}

  public static getInstance(): RemoteControlSocketChannel {
    if (!RemoteControlSocketChannel.instance) {
      RemoteControlSocketChannel.instance = new RemoteControlSocketChannel();
    }
    return RemoteControlSocketChannel.instance;
  }

  public setOnMessage(callback: (message: RemoteControlSocketMessage) => void): void {
    this.onMessageCallback = callback;
  }

  public setOnStatus(callback: (connected: boolean, detail: string) => void): void {
    this.onStatusCallback = callback;
  }

  public isConnected(): boolean {
    return this.connected;
  }

  /**
   * 同步解析本机局域网 IPv4 地址（onContinue 打包时调用，必须同步拿到结果）
   */
  public resolveLocalLanIp(): string {
    try {
      const netHandle = connection.getDefaultNetSync();
      const properties = connection.getConnectionPropertiesSync(netHandle);
      for (const linkAddress of properties.linkAddresses) {
        const host = linkAddress.address.address;
        if (host.length > 0 && host.indexOf(':') < 0 && host !== '127.0.0.1') {
          return host;
        }
      }
    } catch (error) {
      logger.warn(TAG, `获取本地局域网IP失败: ${String(error)}`);
    }
    return '';
  }

  /**
   * 源端：准备 TCP 服务（同步返回端口，异步开始监听）。重复调用会先释放旧通道。
   */
  public prepareServer(sessionId: string): number {
    this.teardown();
    this.sessionId = sessionId;
    void this.startListeningWithRetry(1);
    return REMOTE_CONTROL_CHANNEL_PORT;
  }

  /**
   * 目标端：按源端随 Want 携带的地址回连。重复调用会先释放旧通道。
   */
  public connectToRemote(sessionId: string, ip: string, port: number): void {
    this.teardown();
    this.sessionId = sessionId;
    this.remoteIp = ip;
    this.remotePort = port;
    this.connectEpoch += 1;
    const epoch = this.connectEpoch;
    logger.info(TAG, `开始回连遥控通道: ${ip}:${port}, sessionId=${sessionId}`);
    void this.connectAttempt(epoch, ip, port, 1);
  }

  /**
   * 经当前活跃连接发送一条消息（未连接时静默忽略）
   */
  public send(message: RemoteControlSocketMessage): void {
    if (!this.connected) {
      return;
    }
    let payload = '';
    try {
      payload = JSON.stringify(message);
    } catch (error) {
      logger.warn(TAG, `序列化通道消息失败: ${String(error)}`);
      return;
    }
    const line = `${payload}\n`;
    if (this.serverConnection !== null) {
      this.sendViaServerConnection(this.serverConnection, line);
      return;
    }
    if (this.client !== null) {
      this.sendViaClient(this.client, line);
    }
  }

  /**
   * 释放全部资源（会话结束 / 通道重建时调用）
   */
  public teardown(): void {
    this.connectEpoch += 1;
    this.receiveBuffer = '';
    const serverConnection = this.serverConnection;
    this.serverConnection = null;
    if (serverConnection !== null) {
      try {
        serverConnection.off('message');
        serverConnection.off('close');
        serverConnection.off('error');
      } catch (offError) {
        logger.debug(TAG, `移除服务连接监听失败: ${String(offError)}`);
      }
      try {
        void serverConnection.close();
      } catch (closeError) {
        logger.debug(TAG, `关闭服务连接失败: ${String(closeError)}`);
      }
    }
    const fileConnection = this.fileConnection;
    this.fileConnection = null;
    if (fileConnection !== null) {
      try {
        fileConnection.off('message');
        fileConnection.off('close');
        fileConnection.off('error');
      } catch (offError) {
        logger.debug(TAG, `移除文件流连接监听失败: ${String(offError)}`);
      }
      try {
        void fileConnection.close();
      } catch (closeError) {
        logger.debug(TAG, `关闭文件流连接失败: ${String(closeError)}`);
      }
    }
    const client = this.client;
    this.client = null;
    if (client !== null) {
      try {
        client.off('connect');
        client.off('message');
        client.off('close');
        client.off('error');
      } catch (offError) {
        logger.debug(TAG, `移除客户端监听失败: ${String(offError)}`);
      }
      try {
        void client.close();
      } catch (closeError) {
        logger.debug(TAG, `关闭客户端失败: ${String(closeError)}`);
      }
    }
    const server = this.server;
    this.server = null;
    if (server !== null) {
      try {
        server.off('connect');
        server.off('error');
      } catch (offError) {
        logger.debug(TAG, `移除服务监听失败: ${String(offError)}`);
      }
      try {
        void server.close();
      } catch (closeError) {
        logger.debug(TAG, `关闭服务失败: ${String(closeError)}`);
      }
    }
    const wasConnected = this.connected;
    this.connected = false;
    this.sessionId = '';
    if (wasConnected) {
      this.notifyStatus(false, 'channel teardown');
    }
  }

  private async startListeningWithRetry(attempt: number): Promise<void> {
    try {
      const server = socket.constructTCPSocketServerInstance();
      server.on('connect', (clientConnection: socket.TCPSocketConnection) => {
        this.attachServerConnection(clientConnection);
      });
      server.on('error', (error: Error) => {
        logger.warn(TAG, `遥控通道服务异常: ${String(error)}`);
      });
      const listenAddress: connection.NetAddress = {
        address: '0.0.0.0',
        family: 1,
        port: REMOTE_CONTROL_CHANNEL_PORT
      };
      await server.listen(listenAddress);
      this.server = server;
      logger.info(TAG, `遥控通道服务已监听: 0.0.0.0:${REMOTE_CONTROL_CHANNEL_PORT}, sessionId=${this.sessionId}`);
    } catch (error) {
      logger.warn(TAG, `遥控通道监听失败(第${attempt}/${LISTEN_MAX_ATTEMPTS}次): ${String(error)}`);
      if (attempt < LISTEN_MAX_ATTEMPTS) {
        setTimeout(() => {
          void this.startListeningWithRetry(attempt + 1);
        }, LISTEN_RETRY_DELAY_MS);
      }
    }
  }

  private attachServerConnection(clientConnection: socket.TCPSocketConnection): void {
    // 第二条连接作为文件流通道（本地书跨端接续时目标端发起）
    if (this.serverConnection !== null) {
      this.attachFileStreamConnection(clientConnection);
      return;
    }
    this.serverConnection = clientConnection;
    this.connected = true;
    logger.info(TAG, `遥控通道已接入被控端连接: clientId=${clientConnection.clientId}, sessionId=${this.sessionId}`);
    this.notifyStatus(true, 'server accepted');
    clientConnection.on('message', (messageInfo: socket.SocketMessageInfo) => {
      this.handleIncomingBytes(messageInfo.message);
    });
    clientConnection.on('close', () => {
      logger.info(TAG, '遥控通道被控端连接已断开');
      this.handleDisconnect();
    });
    clientConnection.on('error', (error: Error) => {
      logger.warn(TAG, `遥控通道连接异常: ${String(error)}`);
      this.handleDisconnect();
    });
  }

  /**
   * 源端：处理目标端发起的书籍文件流连接。
   * 协议：首行 JSON（file_request）→ 源端回 file_start 头 → 原始字节流 → 关闭连接。
   */
  private attachFileStreamConnection(clientConnection: socket.TCPSocketConnection): void {
    this.fileConnection = clientConnection;
    logger.info(TAG, `书籍文件流连接已接入: clientId=${clientConnection.clientId}`);
    let headerBuffer = '';
    const decoder = new util.TextDecoder('utf-8');
    let requestHandled = false;
    clientConnection.on('message', (messageInfo: socket.SocketMessageInfo) => {
      if (requestHandled) {
        return;
      }
      headerBuffer += decoder.decodeToString(new Uint8Array(messageInfo.message));
      const newlineIndex = headerBuffer.indexOf('\n');
      if (newlineIndex < 0) {
        return;
      }
      const headerText = headerBuffer.substring(0, newlineIndex).trim();
      headerBuffer = '';
      requestHandled = true;
      try {
        const header = JSON.parse(headerText) as RemoteMangaStreamHeader;
        if (header.kind === 'manga_request' && header.bookId && header.bookId.length > 0) {
          void this.streamMangaBundleTo(clientConnection, header.bookId);
          return;
        }
        if (header.kind !== 'file_request' || !header.bookId || header.bookId.length <= 0) {
          logger.warn(TAG, `文件流请求头无效: ${headerText}`);
          void this.sendFileErrorAndClose(clientConnection, '文件流请求头无效');
          return;
        }
        void this.streamBookFileTo(clientConnection, header.bookId);
      } catch (error) {
        logger.warn(TAG, `解析文件流请求失败: ${String(error)}`);
        void this.sendFileErrorAndClose(clientConnection, `解析文件流请求失败: ${String(error)}`);
      }
    });
    clientConnection.on('close', () => {
      if (this.fileConnection === clientConnection) {
        this.fileConnection = null;
      }
      logger.info(TAG, '书籍文件流连接已关闭');
    });
    clientConnection.on('error', (error: Error) => {
      logger.warn(TAG, `书籍文件流连接异常: ${String(error)}`);
      if (this.fileConnection === clientConnection) {
        this.fileConnection = null;
      }
    });
  }

  private async sendFileErrorAndClose(conn: socket.TCPSocketConnection, reason: string): Promise<void> {
    try {
      await this.sendTextLine(conn, JSON.stringify({ kind: 'file_error', bookId: '', reason: reason } as RemoteFileStreamHeader));
    } catch (error) {
      logger.debug(TAG, `发送文件错误响应失败: ${String(error)}`);
    }
    try {
      await conn.close();
    } catch (closeError) {
      logger.debug(TAG, `关闭文件流连接失败: ${String(closeError)}`);
    }
  }

  private async sendTextLine(conn: socket.TCPSocketConnection, line: string): Promise<void> {
    const sendOptions: socket.TCPSendOptions = {
      data: `${line}\n`,
      encoding: 'UTF-8'
    };
    await conn.send(sendOptions);
  }

  private async streamBookFileTo(conn: socket.TCPSocketConnection, bookId: string): Promise<void> {
    try {
      const ebook = await EBookDataManager.getInstance().getEBookById(bookId);
      if (!ebook || !ebook.filePath || ebook.filePath.length <= 0) {
        await this.sendFileErrorAndClose(conn, `源端未找到书籍文件: ${bookId}`);
        return;
      }
      let totalBytes = ebook.fileSize > 0 ? ebook.fileSize : 0;
      try {
        const stat = SafeFileUtils.statSync(ebook.filePath);
        if (stat.size > 0) {
          totalBytes = stat.size;
        }
      } catch (statError) {
        logger.debug(TAG, `获取书籍文件大小失败，使用记录值: ${String(statError)}`);
      }
      const file = SafeFileUtils.openSync(ebook.filePath);
      if (typeof file.fd !== 'number' || file.fd < 0) {
        await this.sendFileErrorAndClose(conn, `源端打开书籍文件失败: ${ebook.filePath}`);
        return;
      }
      const fd = file.fd;
      const fileHash = await this.computeFileHash(ebook.filePath);
      await this.sendTextLine(conn, JSON.stringify({
        kind: 'file_start',
        bookId: bookId,
        fileName: this.extractFileName(ebook.filePath),
        totalBytes: totalBytes,
        fileHash: fileHash
      } as RemoteFileStreamHeader));
      const buffer = new ArrayBuffer(FILE_STREAM_CHUNK_SIZE);
      let offset = 0;
      let readBytes = 0;
      // [修复] 不带 ReadOptions：readSync 的 options.offset 是文件内偏移（pread 语义，不推进文件指针），
      // 传 offset 会导致永远重读同一段数据（服务端无限重发）
      while ((readBytes = SafeFileUtils.readSync(fd, buffer)) > 0) {
        const chunk = buffer.slice(0, readBytes);
        await conn.send({ data: chunk });
        offset += readBytes;
      }
      SafeFileUtils.closeSync(fd);
      logger.info(TAG, `书籍文件流发送完成: bookId=${bookId}, bytes=${offset}`);
      try {
        await conn.close();
      } catch (closeError) {
        logger.debug(TAG, `关闭文件流连接失败: ${String(closeError)}`);
      }
    } catch (error) {
      logger.warn(TAG, `书籍文件流发送失败: ${String(error)}`);
      try {
        await conn.close();
      } catch (closeError) {
        logger.debug(TAG, `关闭文件流连接失败: ${String(closeError)}`);
      }
    }
  }

  private extractFileName(filePath: string): string {
    const lastSlashIndex = filePath.lastIndexOf('/');
    if (lastSlashIndex >= 0) {
      return filePath.substring(lastSlashIndex + 1);
    }
    return filePath;
  }

  /**
   * 源端：组装漫画接续传输元数据包（漫画行 + 章节 + 页面 + 文件清单）。
   * 本地漫画（comic_info）附带封面与各章节目录下的图片文件；在线漫画仅携带元数据，
   * 目标端按 sourceId/externalId 联网恢复章节。
   */
  private async buildMangaTransferBundle(comicId: string): Promise<MangaTransferBundle | null> {
    try {
      const dataManager = DataManager.getInstance();
      let comicMeta: RemoteComicMetadata | null = null;
      // 先用简单查询（comic_info 单表），部分数据形态下 UNION 查询存在查不到的情况；
      // 再用 UNION 查询兜底，最后诊断输出各表命中情况。
      let localComic = await dataManager.getComicInfo(comicId);
      if (!localComic) {
        localComic = await dataManager.getComicById(comicId);
      }
      if (localComic) {
        comicMeta = {
          id: localComic.id,
          title: localComic.title,
          author: localComic.author,
          description: localComic.description,
          coverUrl: localComic.coverUrl,
          coverLocalPath: localComic.coverLocalPath || '',
          sourceId: localComic.sourceId,
          externalId: localComic.externalId || localComic.id,
          status: String(localComic.status),
          tags: localComic.tags || [],
          rating: localComic.rating,
          chapterCount: localComic.chapterCount,
          lastUpdateTime: localComic.lastUpdateTime,
          addTime: localComic.addTime,
          contentType: localComic.contentType || 'manga',
          isNSFW: localComic.isNSFW === true || localComic.isNSFW === 1 ? 1 : 0,
          isPrivate: localComic.isPrivate === true || localComic.isPrivate === 1 ? 1 : 0
        };
      } else {
        const onlineComic = await dataManager.getOnlineComicInfoById(comicId);
        if (onlineComic) {
          comicMeta = {
            id: onlineComic.id,
            title: onlineComic.title,
            author: onlineComic.author,
            description: onlineComic.description,
            coverUrl: onlineComic.coverUrl,
            coverLocalPath: '',
            sourceId: onlineComic.sourceId,
            externalId: onlineComic.externalId || onlineComic.id,
            status: 'ongoing',
            tags: onlineComic.tags || [],
            rating: onlineComic.rating,
            chapterCount: 0,
            lastUpdateTime: onlineComic.lastUpdateTime,
            addTime: onlineComic.addTime,
            contentType: 'manga',
            isNSFW: onlineComic.isNSFW === 1 ? 1 : 0,
            isPrivate: onlineComic.isPrivate === 1 ? 1 : 0
          };
        } else {
          const diagnostics = await dataManager.getMangaLookupDiagnostics(comicId);
          logger.warn(TAG, `漫画父记录缺失诊断: comicId=${comicId}, ${diagnostics}`);
        }
      }
      if (!comicMeta) {
        return null;
      }

      const chapters = await dataManager.getChaptersByMangaId(comicId);
      const chapterMetas: RemoteChapterMetadata[] = [];
      const chapterPages: MangaChapterPagesEntry[] = [];
      const files: MangaTransferFileEntry[] = [];
      const seenPaths = new Set<string>();

      // 封面文件
      const coverPath = comicMeta.coverLocalPath.length > 0 ? comicMeta.coverLocalPath : comicMeta.coverUrl;
      if (coverPath.length > 0 && !coverPath.startsWith('http') && SafeFileUtils.accessSync(coverPath)) {
        const coverStat = SafeFileUtils.statSync(coverPath);
        if (coverStat.isFile()) {
          const coverHash = await this.computeFileHash(coverPath);
          files.push({
            originalPath: coverPath,
            relPath: `cover/${this.extractFileName(coverPath)}`,
            size: coverStat.size,
            hash: coverHash
          });
        }
      }

      for (const chapter of chapters) {
        chapterMetas.push({
          id: chapter.id,
          title: chapter.title,
          index: chapter.index,
          pageCount: chapter.pageCount,
          isDownloaded: chapter.isDownloaded,
          downloadPath: chapter.downloadPath || '',
          publishTime: chapter.publishTime,
          addTime: chapter.addTime || Date.now(),
          externalId: chapter.externalId || chapter.id
        });
        const pages = await dataManager.getChapterPages(chapter.id);
        const pageMetas: RemotePageMetadata[] = [];
        for (const page of pages) {
          pageMetas.push({
            id: page.id,
            index: page.index,
            imageUrl: page.imageUrl,
            localPath: page.localPath || '',
            width: page.width,
            height: page.height,
            fileSize: page.fileSize
          });
        }
        chapterPages.push({ chapterId: chapter.id, pages: pageMetas });

        // 本地章节：遍历下载目录收集图片文件
        const dir = chapter.downloadPath || '';
        if (dir.length > 0 && SafeFileUtils.accessSync(dir)) {
          const relFiles = SafeFileUtils.listFileSync(dir, { recursion: true });
          for (const rel of relFiles) {
            const absPath = `${dir}${rel}`;
            if (seenPaths.has(absPath)) {
              continue;
            }
            const stat = SafeFileUtils.statSync(absPath);
            if (!stat.isFile()) {
              continue;
            }
            seenPaths.add(absPath);
            const fileHash = await this.computeFileHash(absPath);
            files.push({
              originalPath: absPath,
              relPath: `chapter_${chapter.id}${rel}`,
              size: stat.size,
              hash: fileHash
            });
          }
        }
      }

      const bundle: MangaTransferBundle = {
        comic: comicMeta,
        chapters: chapterMetas,
        chapterPages: chapterPages,
        files: files
      };
      logger.info(TAG, `漫画接续元数据已组装: comicId=${comicId}, chapters=${chapterMetas.length}, files=${files.length}`);
      return bundle;
    } catch (error) {
      logger.warn(TAG, `组装漫画接续元数据失败: ${String(error)}`);
      return null;
    }
  }

  /**
   * 源端：向目标端流式发送漫画接续数据。
   * 协议：manga_start（元数据）→ 逐个 file_part（JSON 行 + 原始字节）→ manga_end → 关闭连接。
   */
  private async streamMangaBundleTo(conn: socket.TCPSocketConnection, comicId: string): Promise<void> {
    try {
      const bundle = await this.buildMangaTransferBundle(comicId);
      if (!bundle) {
        await this.sendFileErrorAndClose(conn, `源端未找到漫画数据: ${comicId}`);
        return;
      }
      let totalBytes = 0;
      for (const entry of bundle.files) {
        totalBytes += entry.size;
      }
      const startHeader: RemoteMangaStreamHeader = {
        kind: 'manga_start',
        bookId: comicId,
        totalBytes: totalBytes,
        bundle: bundle
      };
      await this.sendTextLine(conn, JSON.stringify(startHeader));
      for (const entry of bundle.files) {
        const partHeader: RemoteMangaStreamHeader = {
          kind: 'file_part',
          bookId: comicId,
          relPath: entry.relPath,
          originalPath: entry.originalPath,
          size: entry.size,
          hash: entry.hash
        };
        await this.sendTextLine(conn, JSON.stringify(partHeader));
        const file = SafeFileUtils.openSync(entry.originalPath);
        if (typeof file.fd !== 'number' || file.fd < 0) {
          await this.sendFileErrorAndClose(conn, `源端打开漫画文件失败: ${entry.originalPath}`);
          return;
        }
        const buffer = new ArrayBuffer(FILE_STREAM_CHUNK_SIZE);
        let readBytes = 0;
        let sentBytes = 0;
        while ((readBytes = SafeFileUtils.readSync(file.fd, buffer)) > 0) {
          await conn.send({ data: buffer.slice(0, readBytes) });
          sentBytes += readBytes;
        }
        SafeFileUtils.closeSync(file.fd);
        logger.debug(TAG, `漫画文件已发送: relPath=${entry.relPath}, bytes=${sentBytes}/${entry.size}`);
      }
      const endHeader: RemoteMangaStreamHeader = {
        kind: 'manga_end',
        bookId: comicId
      };
      await this.sendTextLine(conn, JSON.stringify(endHeader));
      logger.info(TAG, `漫画接续数据发送完成: comicId=${comicId}, files=${bundle.files.length}, bytes=${totalBytes}`);
      try {
        await conn.close();
      } catch (closeError) {
        logger.debug(TAG, `关闭漫画流连接失败: ${String(closeError)}`);
      }
    } catch (error) {
      logger.warn(TAG, `漫画接续数据发送失败: ${String(error)}`);
      try {
        await conn.close();
      } catch (closeError) {
        logger.debug(TAG, `关闭漫画流连接失败: ${String(closeError)}`);
      }
    }
  }

  /**
   * 计算文件 SHA-256（分块读取，避免整文件载入内存）。
   * 用于源端在文件流头中携带哈希、目标端接收后校验完整性。
   */
  private async computeFileHash(filePath: string): Promise<string> {
    try {
      const file = SafeFileUtils.openSync(filePath);
      if (typeof file.fd !== 'number' || file.fd < 0) {
        return '';
      }
      const md = cryptoFramework.createMd('SHA256');
      const buffer = new ArrayBuffer(FILE_HASH_CHUNK_SIZE);
      let readBytes = 0;
      while ((readBytes = SafeFileUtils.readSync(file.fd, buffer)) > 0) {
        const blob: cryptoFramework.DataBlob = {
          data: new Uint8Array(buffer.slice(0, readBytes))
        };
        await md.update(blob);
      }
      SafeFileUtils.closeSync(file.fd);
      const digest = await md.digest();
      return bytesToHex(digest.data);
    } catch (error) {
      logger.warn(TAG, `计算书籍文件哈希失败: ${String(error)}`);
      return '';
    }
  }

  private async verifyReceivedFileAndSettle(
    bookId: string,
    result: RemoteFileReceiveResult,
    expectedHash: string,
    settleOnce: (result: RemoteFileReceiveResult | null) => void
  ): Promise<void> {
    const actualHash = await this.computeFileHash(result.tempPath);
    if (actualHash.length <= 0 || actualHash.toLowerCase() !== expectedHash.toLowerCase()) {
      logger.error(TAG, `书籍文件完整性校验失败: bookId=${bookId}, expected=${expectedHash}, actual=${actualHash}`);
      SafeFileUtils.unlinkSync(result.tempPath);
      settleOnce(null);
      return;
    }
    logger.info(TAG, `书籍文件完整性校验通过: bookId=${bookId}, sha256=${actualHash}`);
    settleOnce(result);
  }

  /**
   * 目标端：经独立第二条 TCP 连接向源端请求书籍文件，接收完成后写入临时文件并返回路径与原文件名。
   * @param options 超时时间与接收进度回调（进度回调用于接续传输加载动画）
   * @returns 接收结果；失败/超时/完整性校验不通过返回 null
   */
  public requestBookFile(bookId: string, options?: RemoteFileRequestOptions): Promise<RemoteFileReceiveResult | null> {
    const timeoutMs = options?.timeoutMs !== undefined ? options.timeoutMs : FILE_REQUEST_TIMEOUT_MS;
    const onProgress = options?.onProgress;
    // 清理历史遗留的临时接收文件（防止异常中断累积占用空间）
    this.cleanTempTransferDir();
    return new Promise<RemoteFileReceiveResult | null>((resolve) => {
      this.fileRequestEpoch += 1;
      const epoch = this.fileRequestEpoch;
      let settled = false;
      const settle = (result: RemoteFileReceiveResult | null): void => {
        if (settled) {
          return;
        }
        settled = true;
        resolve(result);
      };
      const timer = setTimeout(() => {
        logger.warn(TAG, `书籍文件请求超时: bookId=${bookId}`);
        settle(null);
      }, timeoutMs);
      void this.performFileRequest(epoch, bookId, settle, onProgress).then(() => {
        clearTimeout(timer);
      });
    });
  }

  private cleanTempTransferDir(): void {
    try {
      const filesDir = getContext().filesDir;
      const tempDir = `${filesDir}/remote_transfer`;
      const files = SafeFileUtils.listFileSync(tempDir);
      for (const fileName of files) {
        SafeFileUtils.unlinkSync(`${tempDir}/${fileName}`);
      }
    } catch (error) {
      logger.debug(TAG, `清理传输临时目录失败: ${String(error)}`);
    }
  }

  private async performFileRequest(
    epoch: number,
    bookId: string,
    settle: (result: RemoteFileReceiveResult | null) => void,
    onProgress?: (receivedBytes: number, totalBytes: number) => void
  ): Promise<void> {
    let client: socket.TCPSocket | null = null;
    let settled = false;
    const settleOnce = (result: RemoteFileReceiveResult | null): void => {
      if (!settled) {
        settled = true;
        settle(result);
      }
    };
    try {
      if (this.remoteIp.length <= 0 || this.remotePort <= 0) {
        logger.warn(TAG, '无源端通道地址，无法请求书籍文件');
        settleOnce(null);
        return;
      }
      client = socket.constructTCPSocketInstance();
      let phase: 'header' | 'data' = 'header';
      let headerBuffer = '';
      const decoder = new util.TextDecoder('utf-8');
      const dataChunks: Uint8Array[] = [];
      let dataBytes = 0;
      let expectedBytes = 0;
      let expectedHash = '';
      let receivedFileName = '';
      let hashVerifying = false;
      // [修复] 幂等落盘：'close' 事件可能重复触发，且 writeTempFile 作为 settleOnce 实参会被急切求值，
      // 因此只允许真正写入一次，后续调用直接返回缓存结果，避免重复写出多个 88MB 临时文件。
      let writeAttempted = false;
      let writtenResult: RemoteFileReceiveResult | null = null;
      const writeTempFile = (): RemoteFileReceiveResult | null => {
        if (writeAttempted) {
          return writtenResult;
        }
        writeAttempted = true;
        try {
          const filesDir = getContext().filesDir;
          const tempDir = `${filesDir}/remote_transfer`;
          SafeFileUtils.mkdirSync(tempDir, true);
          const tempFilePath = `${tempDir}/received_${bookId}_${Date.now()}.part`;
          const outFile = SafeFileUtils.openSync(tempFilePath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
          if (typeof outFile.fd !== 'number' || outFile.fd < 0) {
            logger.warn(TAG, '创建临时接收文件失败');
            return null;
          }
          for (const chunk of dataChunks) {
            // [修复] 严禁传 WriteOptions：fileIo.writeSync 的 options.offset 是文件内偏移
            // （filePointer + offset，pwrite 语义，写后不推进文件指针）。此前传 {offset:0} 导致
            // 每个分块都覆盖写回文件位置 0，最终文件只剩最后一个分块（字节计数却正常），
            // 这是传输文件“字节数对但内容损坏”的根因。这里用精确大小的独立缓冲区顺序写。
            const exactBuffer = new ArrayBuffer(chunk.length);
            const exactView = new Uint8Array(exactBuffer);
            exactView.set(chunk);
            SafeFileUtils.writeSync(outFile.fd, exactBuffer);
          }
          SafeFileUtils.closeSync(outFile.fd);
          logger.info(TAG, `书籍文件接收完成: bookId=${bookId}, bytes=${dataBytes}, path=${tempFilePath}`);
          const result: RemoteFileReceiveResult = {
            tempPath: tempFilePath,
            fileName: receivedFileName.length > 0 ? receivedFileName : `received_${bookId}.epub`
          };
          writtenResult = result;
          return result;
        } catch (error) {
          logger.warn(TAG, `写入临时接收文件失败: ${String(error)}`);
          return null;
        }
      };
      const closeClientQuietly = (): void => {
        if (client !== null) {
          try {
            void client.close();
          } catch (closeError) {
            logger.debug(TAG, `关闭文件客户端失败: ${String(closeError)}`);
          }
        }
      };
      client.on('message', (messageInfo: socket.SocketMessageInfo) => {
        if (epoch !== this.fileRequestEpoch || settled) {
          return;
        }
        const chunk = new Uint8Array(messageInfo.message);
        let pos = 0;
        while (pos < chunk.length && !settled) {
          if (phase === 'header') {
            const newlineIndex = chunk.subarray(pos).indexOf(10);
            if (newlineIndex < 0) {
              headerBuffer += decoder.decodeToString(chunk.subarray(pos));
              pos = chunk.length;
              continue;
            }
            headerBuffer += decoder.decodeToString(chunk.subarray(pos, pos + newlineIndex));
            pos += newlineIndex + 1;
            const headerText = headerBuffer.trim();
            headerBuffer = '';
            try {
              const header = JSON.parse(headerText) as RemoteFileStreamHeader;
              if (header.kind === 'file_error') {
                logger.warn(TAG, `源端文件传输失败: ${header.reason}`);
                settleOnce(null);
                closeClientQuietly();
                return;
              }
              if (header.kind !== 'file_start' || header.totalBytes === undefined) {
                logger.warn(TAG, `文件流响应头无效: ${headerText}`);
                settleOnce(null);
                closeClientQuietly();
                return;
              }
              expectedBytes = header.totalBytes;
              if (header.fileName) {
                receivedFileName = header.fileName;
              }
              if (header.fileHash && header.fileHash.length > 0) {
                expectedHash = header.fileHash;
              }
              phase = 'data';
            } catch (error) {
              logger.warn(TAG, `解析文件流响应失败: ${String(error)}`);
              settleOnce(null);
              closeClientQuietly();
              return;
            }
            continue;
          }
          // [修复] slice() 为拷贝而非 subarray() 视图：部分平台会复用 socket 消息缓冲区，
          // 视图会在后续消息到达时被覆盖，导致落盘文件内容错乱（字节数一致但数据损坏）。
          const slice = chunk.slice(pos);
          if (slice.length > 0) {
            dataChunks.push(slice);
            dataBytes += slice.length;
            if (onProgress) {
              onProgress(dataBytes, expectedBytes > 0 ? expectedBytes : 0);
            }
          }
          pos = chunk.length;
          if (expectedBytes > 0 && dataBytes >= expectedBytes) {
            const result = writeTempFile();
            if (result !== null && expectedHash.length > 0) {
              hashVerifying = true;
              void this.verifyReceivedFileAndSettle(bookId, result, expectedHash, settleOnce);
              closeClientQuietly();
              return;
            }
            settleOnce(result);
            closeClientQuietly();
            return;
          }
        }
      });
      client.on('close', () => {
        if (epoch !== this.fileRequestEpoch) {
          return;
        }
        // 完整性校验进行中：由校验流程负责结算，避免提前返回未校验文件
        if (hashVerifying) {
          return;
        }
        // 服务端正常流式传输结束会主动关闭：若尚未完成则按已收数据落盘（totalBytes=0 场景）
        if (phase === 'data' && dataBytes > 0 && expectedBytes > 0 && dataBytes >= expectedBytes) {
          settleOnce(writeTempFile());
          return;
        }
        logger.warn(TAG, `书籍文件连接提前关闭: bookId=${bookId}, received=${dataBytes}/${expectedBytes}`);
        settleOnce(null);
      });
      client.on('error', (error: Error) => {
        logger.warn(TAG, `书籍文件客户端异常: ${String(error)}`);
        if (epoch === this.fileRequestEpoch) {
          settleOnce(null);
        }
      });
      const connectOptions: socket.TCPConnectOptions = {
        address: {
          address: this.remoteIp,
          family: 1,
          port: this.remotePort
        },
        timeout: SOCKET_CONNECT_TIMEOUT_MS
      };
      await client.connect(connectOptions);
      const requestHeader: RemoteFileStreamHeader = {
        kind: 'file_request',
        bookId: bookId
      };
      const requestOptions: socket.TCPSendOptions = {
        data: `${JSON.stringify(requestHeader)}\n`,
        encoding: 'UTF-8'
      };
      await client.send(requestOptions);
      logger.info(TAG, `已发送书籍文件请求: bookId=${bookId}`);
    } catch (error) {
      logger.warn(TAG, `书籍文件请求失败: ${String(error)}`);
      settleOnce(null);
      if (client !== null) {
        try {
          await client.close();
        } catch (closeError) {
          logger.debug(TAG, `关闭文件客户端失败: ${String(closeError)}`);
        }
      }
    }
  }

  /**
   * 目标端：经独立第二条 TCP 连接向源端请求漫画接续数据（元数据 + 本地图片文件）。
   * 文件直接写入应用沙箱 `filesDir/manga_transfer/<comicId>_<ts>/`，并把元数据中的
   * 本地路径改写为沙箱内路径，随后由 DataManager 入库。
   */
  public requestMangaBundle(
    bookId: string,
    onProgress?: (receivedBytes: number, totalBytes: number) => void
  ): Promise<MangaBundleReceiveResult | null> {
    return new Promise<MangaBundleReceiveResult | null>((resolve) => {
      this.fileRequestEpoch += 1;
      const epoch = this.fileRequestEpoch;
      let settled = false;
      const settle = (result: MangaBundleReceiveResult | null): void => {
        if (!settled) {
          settled = true;
          resolve(result);
        }
      };
      const timer = setTimeout(() => {
        logger.warn(TAG, `漫画接续数据请求超时: bookId=${bookId}`);
        settle(null);
      }, FILE_REQUEST_TIMEOUT_MS);
      void this.performMangaBundleRequest(epoch, bookId, settle, onProgress).then(() => {
        clearTimeout(timer);
      });
    });
  }

  private async performMangaBundleRequest(
    epoch: number,
    bookId: string,
    settle: (result: MangaBundleReceiveResult | null) => void,
    onProgress?: (receivedBytes: number, totalBytes: number) => void
  ): Promise<void> {
    let client: socket.TCPSocket | null = null;
    let settled = false;
    const settleOnce = (result: MangaBundleReceiveResult | null): void => {
      if (!settled) {
        settled = true;
        settle(result);
      }
    };
    try {
      if (this.remoteIp.length <= 0 || this.remotePort <= 0) {
        logger.warn(TAG, '无源端通道地址，无法请求漫画数据');
        settleOnce(null);
        return;
      }
      const filesDir = getContext().filesDir;
      const targetRoot = `${filesDir}/manga_transfer/${bookId}_${Date.now()}`;
      client = socket.constructTCPSocketInstance();
      const decoder = new util.TextDecoder('utf-8');
      let lineBuffer = '';
      let bundle: MangaTransferBundle | null = null;
      let totalBytes = 0;
      let receivedBytes = 0;
      let inFileData = false;
      let currentEntry: MangaTransferFileEntry | null = null;
      let currentFd: number = -1;
      let currentTargetPath = '';
      let currentRemaining = 0;
      let hashVerifying = false;
      const receivedFiles: MangaTransferFileEntry[] = [];

      const closeCurrentFile = (): void => {
        if (currentFd >= 0) {
          SafeFileUtils.closeSync(currentFd);
          currentFd = -1;
        }
      };

      const ensureParentDir = (filePath: string): void => {
        const lastSlash = filePath.lastIndexOf('/');
        if (lastSlash > 0) {
          SafeFileUtils.mkdirSync(filePath.substring(0, lastSlash), true);
        }
      };

      const handleMangaLine = (line: string): void => {
        try {
          const header = JSON.parse(line) as RemoteMangaStreamHeader;
          if (header.kind === 'file_error') {
            logger.warn(TAG, `源端漫画传输失败: ${header.reason}`);
            closeCurrentFile();
            settleOnce(null);
            return;
          }
          if (header.kind === 'manga_start') {
            bundle = header.bundle || null;
            totalBytes = header.totalBytes || 0;
            if (!bundle) {
              logger.warn(TAG, '漫画接续元数据为空');
              settleOnce(null);
            }
            return;
          }
          if (header.kind === 'file_part') {
            const relPath = header.relPath || '';
            const size = header.size || 0;
            if (relPath.length <= 0) {
              logger.warn(TAG, '漫画文件条目缺少相对路径');
              closeCurrentFile();
              settleOnce(null);
              return;
            }
            const entry: MangaTransferFileEntry = {
              originalPath: header.originalPath || '',
              relPath: relPath,
              size: size,
              hash: header.hash || ''
            };
            currentEntry = entry;
            currentTargetPath = `${targetRoot}/${relPath}`;
            ensureParentDir(currentTargetPath);
            const outFile = SafeFileUtils.openSync(currentTargetPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
            if (typeof outFile.fd !== 'number' || outFile.fd < 0) {
              logger.warn(TAG, `创建漫画接收文件失败: ${currentTargetPath}`);
              closeCurrentFile();
              settleOnce(null);
              return;
            }
            currentFd = outFile.fd;
            currentRemaining = size;
            inFileData = true;
            return;
          }
          if (header.kind === 'manga_end') {
            hashVerifying = true;
            void this.finishMangaBundle(bookId, bundle, receivedFiles, targetRoot, settleOnce);
            return;
          }
          logger.warn(TAG, `漫画流响应头无效: ${line.substring(0, 200)}`);
          closeCurrentFile();
          settleOnce(null);
        } catch (error) {
          logger.warn(TAG, `解析漫画流响应失败: ${String(error)}`);
          closeCurrentFile();
          settleOnce(null);
        }
      };

      client.on('message', (messageInfo: socket.SocketMessageInfo) => {
        if (epoch !== this.fileRequestEpoch || settled || hashVerifying) {
          return;
        }
        const chunk = new Uint8Array(messageInfo.message);
        let pos = 0;
        while (pos < chunk.length && !settled && !hashVerifying) {
          if (!inFileData) {
            const view = chunk.subarray(pos);
            const newlineIndex = view.indexOf(10);
            if (newlineIndex < 0) {
              lineBuffer += decoder.decodeToString(view);
              pos = chunk.length;
              continue;
            }
            lineBuffer += decoder.decodeToString(chunk.subarray(pos, pos + newlineIndex));
            pos += newlineIndex + 1;
            const line = lineBuffer.trim();
            lineBuffer = '';
            handleMangaLine(line);
            continue;
          }
          if (currentEntry === null || currentFd < 0) {
            logger.warn(TAG, '漫画文件数据阶段状态异常');
            closeCurrentFile();
            settleOnce(null);
            return;
          }
          const take = Math.min(chunk.length - pos, currentRemaining);
          if (take > 0) {
            // [修复] 精确大小独立缓冲区顺序写，绝不传 WriteOptions（pwrite 语义会导致覆盖写）
            const slice = chunk.slice(pos, pos + take);
            const exactBuffer = new ArrayBuffer(slice.length);
            const exactView = new Uint8Array(exactBuffer);
            exactView.set(slice);
            SafeFileUtils.writeSync(currentFd, exactBuffer);
            pos += take;
            currentRemaining -= take;
            receivedBytes += take;
            if (onProgress) {
              onProgress(receivedBytes, totalBytes > 0 ? totalBytes : 0);
            }
          }
          if (currentRemaining <= 0) {
            closeCurrentFile();
            if (currentEntry !== null) {
              receivedFiles.push(currentEntry);
            }
            currentEntry = null;
            currentTargetPath = '';
            inFileData = false;
          }
        }
      });
      client.on('close', () => {
        if (epoch !== this.fileRequestEpoch || hashVerifying) {
          return;
        }
        closeCurrentFile();
        logger.warn(TAG, `漫画接续连接提前关闭: bookId=${bookId}, received=${receivedBytes}/${totalBytes}`);
        settleOnce(null);
      });
      client.on('error', (error: Error) => {
        logger.warn(TAG, `漫画接续客户端异常: ${String(error)}`);
        if (epoch === this.fileRequestEpoch) {
          closeCurrentFile();
          settleOnce(null);
        }
      });
      const connectOptions: socket.TCPConnectOptions = {
        address: {
          address: this.remoteIp,
          family: 1,
          port: this.remotePort
        },
        timeout: SOCKET_CONNECT_TIMEOUT_MS
      };
      await client.connect(connectOptions);
      const requestHeader: RemoteMangaStreamHeader = {
        kind: 'manga_request',
        bookId: bookId
      };
      const requestOptions: socket.TCPSendOptions = {
        data: `${JSON.stringify(requestHeader)}\n`,
        encoding: 'UTF-8'
      };
      await client.send(requestOptions);
      logger.info(TAG, `已发送漫画接续数据请求: bookId=${bookId}`);
    } catch (error) {
      logger.warn(TAG, `漫画接续数据请求失败: ${String(error)}`);
      settleOnce(null);
      if (client !== null) {
        try {
          await client.close();
        } catch (closeError) {
          logger.debug(TAG, `关闭漫画客户端失败: ${String(closeError)}`);
        }
      }
    }
  }

  private async finishMangaBundle(
    bookId: string,
    bundle: MangaTransferBundle | null,
    receivedFiles: MangaTransferFileEntry[],
    targetRoot: string,
    settleOnce: (result: MangaBundleReceiveResult | null) => void
  ): Promise<void> {
    if (!bundle) {
      logger.warn(TAG, `漫画接续元数据为空，无法完成接收: bookId=${bookId}`);
      settleOnce(null);
      return;
    }
    // 逐文件校验完整性（哈希不匹配即整体失败，避免入库损坏数据）
    const fileMap = new Map<string, string>();
    for (const entry of receivedFiles) {
      const targetPath = `${targetRoot}/${entry.relPath}`;
      if (entry.hash.length > 0) {
        const actualHash = await this.computeFileHash(targetPath);
        if (actualHash.length <= 0 || actualHash.toLowerCase() !== entry.hash.toLowerCase()) {
          logger.error(TAG, `漫画文件完整性校验失败: relPath=${entry.relPath}, expected=${entry.hash}, actual=${actualHash}`);
          settleOnce(null);
          return;
        }
      }
      if (entry.originalPath.length > 0) {
        fileMap.set(entry.originalPath, targetPath);
      }
    }
    // 元数据路径改写为沙箱内路径
    this.rewriteMangaBundlePaths(bundle, fileMap, targetRoot);
    logger.info(TAG, `漫画接续数据接收完成: bookId=${bookId}, files=${receivedFiles.length}`);
    const result: MangaBundleReceiveResult = {
      bundle: bundle,
      targetRoot: targetRoot
    };
    settleOnce(result);
  }

  private rewriteMangaBundlePaths(bundle: MangaTransferBundle, fileMap: Map<string, string>, targetRoot: string): void {
    if (bundle.comic.coverLocalPath.length > 0) {
      const mappedCover = fileMap.get(bundle.comic.coverLocalPath);
      if (mappedCover) {
        bundle.comic.coverLocalPath = mappedCover;
      }
    }
    if (bundle.comic.coverUrl.length > 0 && !bundle.comic.coverUrl.startsWith('http')) {
      const mappedCoverUrl = fileMap.get(bundle.comic.coverUrl);
      if (mappedCoverUrl) {
        bundle.comic.coverUrl = mappedCoverUrl;
      }
    }
    for (const chapter of bundle.chapters) {
      if (chapter.downloadPath.length > 0) {
        chapter.downloadPath = `${targetRoot}/chapter_${chapter.id}`;
      }
    }
    for (const entry of bundle.chapterPages) {
      for (const page of entry.pages) {
        if (page.localPath.length > 0) {
          const mappedLocal = fileMap.get(page.localPath);
          if (mappedLocal) {
            page.localPath = mappedLocal;
          }
        }
        if (page.imageUrl.length > 0 && !page.imageUrl.startsWith('http')) {
          const mappedUrl = fileMap.get(page.imageUrl);
          if (mappedUrl) {
            page.imageUrl = mappedUrl;
          }
        }
      }
    }
  }

  private async connectAttempt(epoch: number, ip: string, port: number, attempt: number): Promise<void> {
    if (epoch !== this.connectEpoch) {
      return;
    }
    let client: socket.TCPSocket | null = null;
    try {
      client = socket.constructTCPSocketInstance();
      client.on('connect', () => {
        if (epoch === this.connectEpoch) {
          this.onClientConnected(epoch, client);
        }
      });
      client.on('message', (messageInfo: socket.SocketMessageInfo) => {
        if (epoch === this.connectEpoch) {
          this.handleIncomingBytes(messageInfo.message);
        }
      });
      client.on('close', () => {
        if (epoch === this.connectEpoch) {
          logger.info(TAG, '遥控通道与源端连接已关闭');
          this.handleDisconnect();
        }
      });
      client.on('error', (error: Error) => {
        logger.warn(TAG, `遥控通道客户端异常: ${String(error)}`);
        if (epoch === this.connectEpoch) {
          this.handleDisconnect();
        }
      });
      const connectOptions: socket.TCPConnectOptions = {
        address: {
          address: ip,
          family: 1,
          port: port
        },
        timeout: SOCKET_CONNECT_TIMEOUT_MS
      };
      await client.connect(connectOptions);
      if (epoch === this.connectEpoch) {
        this.onClientConnected(epoch, client);
      }
    } catch (error) {
      logger.warn(TAG, `遥控通道连接失败(第${attempt}/${CONNECT_MAX_ATTEMPTS}次): ${String(error)}`);
      if (client !== null) {
        try {
          await client.close();
        } catch (closeError) {
          logger.debug(TAG, `关闭失败连接异常: ${String(closeError)}`);
        }
      }
      if (epoch === this.connectEpoch && attempt < CONNECT_MAX_ATTEMPTS) {
        setTimeout(() => {
          void this.connectAttempt(epoch, ip, port, attempt + 1);
        }, CONNECT_RETRY_DELAY_MS);
      }
    }
  }

  private onClientConnected(epoch: number, client: socket.TCPSocket | null): void {
    if (epoch !== this.connectEpoch || client === null || this.connected) {
      return;
    }
    this.client = client;
    this.connected = true;
    logger.info(TAG, `遥控通道已连上源端, sessionId=${this.sessionId}`);
    this.notifyStatus(true, 'client connected');
  }

  private handleDisconnect(): void {
    if (!this.connected) {
      return;
    }
    this.connected = false;
    this.serverConnection = null;
    this.client = null;
    this.notifyStatus(false, 'disconnected');
  }

  private notifyStatus(connected: boolean, detail: string): void {
    if (this.onStatusCallback) {
      try {
        this.onStatusCallback(connected, detail);
      } catch (error) {
        logger.warn(TAG, `通道状态回调异常: ${String(error)}`);
      }
    }
  }

  private handleIncomingBytes(buffer: ArrayBuffer): void {
    let chunk = '';
    try {
      chunk = this.decoder.decodeToString(new Uint8Array(buffer));
    } catch (error) {
      logger.warn(TAG, `解码通道数据失败: ${String(error)}`);
      return;
    }
    this.receiveBuffer += chunk;
    let newlineIndex = this.receiveBuffer.indexOf('\n');
    while (newlineIndex >= 0) {
      const line = this.receiveBuffer.substring(0, newlineIndex).trim();
      this.receiveBuffer = this.receiveBuffer.substring(newlineIndex + 1);
      if (line.length > 0) {
        this.dispatchLine(line);
      }
      newlineIndex = this.receiveBuffer.indexOf('\n');
    }
    if (this.receiveBuffer.length > MAX_RECEIVE_BUFFER_CHARS) {
      logger.warn(TAG, '通道接收缓冲过大，已清空');
      this.receiveBuffer = '';
    }
  }

  private dispatchLine(line: string): void {
    try {
      const message = JSON.parse(line) as RemoteControlSocketMessage;
      if (this.onMessageCallback) {
        this.onMessageCallback(message);
      }
    } catch (error) {
      logger.warn(TAG, `解析通道消息失败: ${String(error)}`);
    }
  }

  private sendViaServerConnection(serverConnection: socket.TCPSocketConnection, payload: string): void {
    const sendOptions: socket.TCPSendOptions = {
      data: payload,
      encoding: 'UTF-8'
    };
    serverConnection.send(sendOptions).then(() => {
      logger.debug(TAG, '通道消息已发出(服务端)');
    }).catch((error: Error) => {
      logger.warn(TAG, `通道消息发送失败(服务端): ${String(error)}`);
    });
  }

  private sendViaClient(client: socket.TCPSocket, payload: string): void {
    const sendOptions: socket.TCPSendOptions = {
      data: payload,
      encoding: 'UTF-8'
    };
    client.send(sendOptions).then(() => {
      logger.debug(TAG, '通道消息已发出(客户端)');
    }).catch((error: Error) => {
      logger.warn(TAG, `通道消息发送失败(客户端): ${String(error)}`);
    });
  }
}
