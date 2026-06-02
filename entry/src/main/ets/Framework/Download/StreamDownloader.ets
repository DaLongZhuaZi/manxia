import { SafeFileUtils } from '../../Utils/SafeFileUtils';
/**
 * 流式下载器（场景 B-2：下载 + 处理）
 *
 * 适用场景：下载图片/内容并在下载过程中进行处理（解码、校验、变换等）
 * 无法使用 request.agent 系统代理（因需自定义中间处理逻辑）
 *
 * 技术方案：
 *   - DATA_TRANSFER 后台长时任务：APP 挂起后网络和磁盘 I/O 可继续
 *   - requestInStream 事件驱动流式写入：内存占用低，适合大文件
 *   - 进度心跳机制：每 8 分钟主动更新时间戳，防止系统因"10 分钟无进度"而强制取消任务
 *
 * 文件路径: entry/src/main/ets/Framework/Download/StreamDownloader.ets
 */

import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';
import { BackgroundTaskHelper } from '../Task/BackgroundTaskHelper';
import { logger } from '../../Utils/Logger';

const TAG = 'StreamDownloader';

/** 进度心跳检测间隔（每分钟检查一次） */
const HEARTBEAT_CHECK_MS = 60 * 1000;
/** 触发主动刷新的无进度阈值（8 分钟，系统限制为 10 分钟） */
const HEARTBEAT_REFRESH_THRESHOLD_MS = 8 * 60 * 1000;

/**
 * 流式下载器
 *
 * 使用示例：
 * ```typescript
 * const downloader = new StreamDownloader();
 * await downloader.downloadWithProcessing(this.context, imageUrls, outputDir, {
 *   onProgress: (done, total) => console.log(`${done}/${total}`),
 *   fileNameProvider: (i, url) => `page_${String(i).padStart(4, '0')}.webp`
 * });
 * ```
 */
export class StreamDownloader {
  private heartbeatTimer: number = -1;
  private lastProgressTime: number = 0;

  // ─── 心跳管理 ────────────────────────────────────────────────────────────────

  /**
   * 启动进度心跳定时器
   * 防止 DATA_TRANSFER 任务因超过 10 分钟无进度被系统强制取消
   */
  private startHeartbeat(): void {
    this.lastProgressTime = Date.now();
    this.heartbeatTimer = setInterval(() => {
      const now = Date.now();
      if (now - this.lastProgressTime >= HEARTBEAT_REFRESH_THRESHOLD_MS) {
        // 超过 8 分钟仍未有新的文件完成，主动刷新时间戳
        this.lastProgressTime = now;
        logger.debug(TAG, '进度心跳：已超过 8 分钟无进度，主动刷新时间戳');
      }
    }, HEARTBEAT_CHECK_MS) as number;
  }

  /** 停止进度心跳定时器 */
  private stopHeartbeat(): void {
    if (this.heartbeatTimer !== -1) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = -1;
    }
  }

  /** 每完成一个文件后调用，重置心跳计时 */
  private tickProgress(): void {
    this.lastProgressTime = Date.now();
  }

  // ─── 公开接口 ─────────────────────────────────────────────────────────────────

  /**
   * 批量流式下载并写入文件
   *
   * @param context         UIAbility 上下文（后台任务申请）
   * @param urls            下载 URL 列表
   * @param outputDir       文件输出目录（需确保已存在）
   * @param options         可选配置
   */
  async downloadWithProcessing(
    context: common.UIAbilityContext,
    urls: string[],
    outputDir: string,
    options?: {
      /** 进度回调：(已完成数, 总数) */
      onProgress?: (completed: number, total: number) => void;
      /** 自定义文件名，默认 page_0000.jpg */
      fileNameProvider?: (index: number, url: string) => string;
      /** 请求头，默认含 User-Agent */
      headers?: Record<string, string>;
    }
  ): Promise<void> {
    const { onProgress, fileNameProvider, headers } = options ?? {};
    const backgroundTaskOwner = `stream_downloader_${Date.now()}_${urls.length}`;

    logger.info(TAG, `开始流式下载 ${urls.length} 个文件 -> ${outputDir}`);

    await BackgroundTaskHelper.startDataTransferTask(context, backgroundTaskOwner);
    this.startHeartbeat();

    let completedCount = 0;
    try {
      for (let i = 0; i < urls.length; i++) {
        const url = urls[i];
        const fileName = fileNameProvider
          ? fileNameProvider(i, url)
          : `page_${String(i).padStart(4, '0')}.jpg`;
        const destPath = `${outputDir}/${fileName}`;

        await this.downloadSingleStream(url, destPath, headers);

        completedCount++;
        this.tickProgress();                           // 更新心跳时间戳
        onProgress?.(completedCount, urls.length);
        logger.debug(TAG, `流式进度 ${completedCount}/${urls.length}: ${fileName}`);
      }
    } finally {
      this.stopHeartbeat();
      await BackgroundTaskHelper.stopDataTransferTask(context, backgroundTaskOwner);
    }

    logger.info(TAG, `流式下载完成，共 ${completedCount}/${urls.length} 个文件`);
  }

  // ─── 私有核心 ─────────────────────────────────────────────────────────────────

  /**
   * 单文件流式下载
   * 使用 requestInStream 事件驱动逐块写入，避免将整个文件载入内存
   */
  private async downloadSingleStream(
    url: string,
    dest: string,
    extraHeaders?: Record<string, string>
  ): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const httpRequest = http.createHttp();

      // 打开目标文件（CREATE | WRITE_ONLY）
      let file: fs.File | null = null;
      try {
        file = SafeFileUtils.openSync(dest, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      } catch (openErr) {
        httpRequest.destroy();
        reject(new Error(`打开目标文件失败 [${dest}]: ${String(openErr)}`));
        return;
      }

      // ── 接收数据块，流式写入磁盘 ──────────────────────────────────────────
      httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        try {
          if (file) {
            SafeFileUtils.writeSync(file.fd, data);
          }
        } catch (writeErr) {
          logger.warn(TAG, `写入数据块失败: ${String(writeErr)}`);
        }
      });

      // ── 传输完成 ──────────────────────────────────────────────────────────
      httpRequest.on('dataEnd', () => {
        if (file) {
          try { SafeFileUtils.closeSync(file.fd); } catch {}
          file = null;
        }
        httpRequest.destroy();
        resolve();
      });

      // ── 接收错误 ──────────────────────────────────────────────────────────
      httpRequest.on('dataReceiveErr', (err: Object) => {
        if (file) {
          try { SafeFileUtils.closeSync(file.fd); } catch {}
          file = null;
        }
        httpRequest.destroy();
        reject(new Error(`数据接收失败: ${String(err)}`));
      });

      // ── 发起流式 HTTP 请求 ─────────────────────────────────────────────────
      const requestHeaders: Record<string, string> = {
        'User-Agent': 'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36',
        ...extraHeaders
      };

      httpRequest.requestInStream(url, {
        method: http.RequestMethod.GET,
        header: requestHeaders
      }).catch((reqErr: Error) => {
        if (file) {
          try { SafeFileUtils.closeSync(file.fd); } catch {}
          file = null;
        }
        httpRequest.destroy();
        reject(new Error(`流式请求失败 [${url}]: ${String(reqErr)}`));
      });
    });
  }
}
