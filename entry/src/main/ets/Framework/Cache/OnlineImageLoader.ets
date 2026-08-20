// 文件路径: src/main/ets/Framework/Cache/OnlineImageLoader.ets
/**
 * 在线图片加载器
 * 专门处理在线漫画图片的加载，与本地图片加载分离
 * 特性：
 * 1. 请求队列管理（按优先级排序）
 * 2. 并发控制（最多2个并发请求，避免触发服务器限流）
 * 3. 轻量级内存缓存（不写磁盘）
 * 4. 智能重试机制
 */

import { image } from '@kit.ImageKit';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { http } from '@kit.NetworkKit';
import { webview } from '@kit.ArkWeb';
import CookieManager from '../Managers/CookieManager';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { DiskCacheManager } from 'manxia_network/src/main/ets/Framework/Cache/DiskCacheManager';
import { DataManager, PageCacheUpdate } from '../Data/DataManager';
import { JinmantiantangDescrambler, JinmantiantangParameters } from 'manxia_core/src/main/ets/Framework/ImageProcessing/JinmantiantangDescrambler';
import { UserAgentManager } from '../Managers/UserAgentManager';
import { AvifDecoder, isAvifFormat } from '../Image/AvifDecoder';
import { GlobalWebViewContainer, WebViewEventCallbacks } from 'manxia_source_engine/src/main/ets/Framework/WebView/WebViewContainerPage';
import { WebViewSourceConfig } from 'manxia_source_engine/src/main/ets/Framework/WebView/WebViewImageLoader';
import { OnlineMangaArchiveService } from '../Download/OnlineMangaArchiveService';
import { DownloadCacheFlowMonitor, getDownloadCacheFlowMonitor } from 'manxia_network/src/main/ets/Framework/Download/DownloadCacheFlowMonitor';
import { DownloadCacheFailureTtlCache, getDownloadCacheFailureTtlCache } from 'manxia_network/src/main/ets/Framework/Download/DownloadCacheFailureTtlCache';
import {
  DownloadCacheLimiterPermit,
  DownloadCacheSourceLimiter,
  getDownloadCacheSourceLimiter
} from 'manxia_network/src/main/ets/Framework/Download/DownloadCacheSourceLimiter';
import {
  DownloadCacheContentType,
  DownloadCacheEntrySource,
  DownloadCacheFlowEvent,
  DownloadCacheFlowEventType,
  DownloadCacheFlowSessionInfo,
  DownloadCacheFlowSeverity,
  DownloadCacheFlowStage
} from 'manxia_network/src/main/ets/Framework/Download/DownloadCacheFlowTypes';
import {
  LegadoImageTransportTrace,
  LegadoImageTransportTraceContext
} from 'manxia_network/src/main/ets/Framework/Network/LegadoImageTransportTrace';
import {
  getNetworkTransportFailureCoordinator,
  NetworkTransportCircuitDecision,
  NetworkTransportFailureCoordinator,
  NetworkTransportFailureDescriptor
} from 'manxia_network/src/main/ets/Framework/Network/NetworkTransportFailureCoordinator';


const TAG = 'OnlineImageLoader';

// 禁漫天堂解扰器实例（懒加载）
let jinmantiantangDescrambler: JinmantiantangDescrambler | null = null;

function getJinmantiantangDescrambler(): JinmantiantangDescrambler {
  if (jinmantiantangDescrambler === null) {
    jinmantiantangDescrambler = new JinmantiantangDescrambler();
  }
  return jinmantiantangDescrambler;
}

export interface OnlineLoadOptions {
  width?: number;
  height?: number;
  headers?: RequestHeaders;
  sourceId?: number;
  priority?: number;  // 优先级：10=当前页，5=下一页，3=下下页，1=其他
  partitionKey?: string;
  downloadCacheFlowId?: string;
  visibleLoad?: boolean;
  prefetch?: boolean;
  skipFailureTtl?: boolean;
  forceRefresh?: boolean;
  /** Present only for Legado IMAGE V2 evidence; contains no raw target or header value. */
  legadoImageTrace?: LegadoImageTransportTraceContext;
}


export interface RequestHeaderEntry {
  name: string;
  value: string;
}

export interface RequestHeaders {
  userAgent?: string;
  accept?: string;
  referer?: string;
  origin?: string;
  cookie?: string;
  authorization?: string;
  acceptLanguage?: string;
  cacheControl?: string;
  pragma?: string;
  secFetchDest?: string;
  secFetchMode?: string;
  secFetchSite?: string;
  cachePartition?: string;
  extraHeaders?: RequestHeaderEntry[];
}


interface HttpHeadersObject {
  userAgent?: string;
  origin?: string;
  accept?: string;
  referer?: string;
  cookie?: string;
  authorization?: string;
  acceptLanguage?: string;
  cacheControl?: string;
  pragma?: string;
  secFetchDest?: string;
  secFetchMode?: string;
  secFetchSite?: string;
  extraHeaders?: RequestHeaderEntry[];
}

interface QueuedRequest {
  url: string;
  options: OnlineLoadOptions;
  cacheKey: string;
  loadingKey: string;
  flowId: string;
  sourceKey: string;
  visibleLoad: boolean;
  priority: number;
  resolve: (value: image.PixelMap | null) => void;
  reject: (reason: Error) => void;
  retryCount: number;
}

interface CacheEntry {
  pixelMap: image.PixelMap;
  size: number;
  timestamp: number;
}

interface CookieCacheEntry {
  cookie: string;
  timestamp: number;
}

interface CacheStatusUpdateValue {
  localPath: string;
  fileSize: number;
  flowId: string;
  sourceId: number;
  sourceKey: string;
  cacheKey: string;
}

interface CacheStatusUpdatePayload {
  imageUrl: string;
  localPath: string;
  fileSize: number;
  flowId: string;
  sourceId: number;
  sourceKey: string;
  cacheKey: string;
}

interface WebViewLoadWaiter {
  resolve: () => void;
  reject: (reason: Error) => void;
}

export interface CacheStatsInfo {
  count: number;
  size: number;
  queueSize: number;
  activeRequests: number;
}

export class OnlineImageLoader {
  private static instance: OnlineImageLoader | null = null;
  private readonly rmcdnFallbackPrefix: string = 'online_image_rmcdn_fallback';
  private readonly photos18FallbackPrefix: string = 'online_image_photos18_fallback';
  
  // 请求队列

  private requestQueue: QueuedRequest[] = [];
  private activeRequests: number = 0;
  private readonly MAX_CONCURRENT = 2;  // 保守并发，避免漫画站/CDN图片请求被限流或误判
  
  // [修复] 正在加载的URL集合，用于去重
  private loadingKeys = new Set<string>();
  private downloadCacheFlowMonitor: DownloadCacheFlowMonitor = getDownloadCacheFlowMonitor();
  private failureTtlCache: DownloadCacheFailureTtlCache = getDownloadCacheFailureTtlCache();
  private sourceLimiter: DownloadCacheSourceLimiter = getDownloadCacheSourceLimiter();
  private transportFailureCoordinator: NetworkTransportFailureCoordinator =
    getNetworkTransportFailureCoordinator();

  // 缓存状态写库队列（按URL去重，批量异步落库）
  private pendingCacheStatusUpdates = new Map<string, CacheStatusUpdateValue>();
  private cacheStatusFlushTimer: number | null = null;
  private isFlushingCacheStatusUpdates = false;
  private readonly CACHE_STATUS_FLUSH_DELAY = 150;
  
  // 轻量级内存缓存

  private memoryCache = new Map<string, CacheEntry>();
  private memoryCacheSize = 0;
  private readonly MAX_CACHE_SIZE = 50 * 1024 * 1024;  // 50MB
  private readonly MAX_CACHE_COUNT = 50;  // 最多缓存50张
  
  // Cookie缓存
  private cookieCache = new Map<number, CookieCacheEntry>();
  private readonly COOKIE_CACHE_TTL = 5 * 60 * 1000;  // 5分钟
  
  // 配置
  private readonly TIMEOUT = 30000;  // 30秒超时（适应26秒限流）
  private readonly MAX_RETRIES = 2;
  private readonly RETRY_DELAY = 1000;
  private readonly MIN_REQUEST_INTERVAL = 50;  // 50ms最小请求间隔（优化条漫体验）
  private readonly WEBVIEW_FALLBACK_ATTACH_RETRIES = 12;
  private readonly WEBVIEW_FALLBACK_ATTACH_DELAY = 120;
  private readonly WEBVIEW_FALLBACK_LOAD_TIMEOUT = 15000;
  private readonly WEBVIEW_FALLBACK_SETTLE_DELAY = 250;
  private lastRequestTime = 0;

  private constructor() {
    logger.info(TAG, '在线图片加载器初始化');
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): OnlineImageLoader {
    if (!OnlineImageLoader.instance) {
      OnlineImageLoader.instance = new OnlineImageLoader();
    }
    return OnlineImageLoader.instance;
  }

  /**
   * 加载在线图片（三级缓存：内存->磁盘->网络）
   */
  public async load(url: string, options?: OnlineLoadOptions): Promise<image.PixelMap | null> {
    const effectiveOptions: OnlineLoadOptions = this.cloneLoadOptions(options);
    const cacheKey = this.generateCacheKey(url, effectiveOptions);
    const loadingKey: string = effectiveOptions.forceRefresh ? `${cacheKey}|force_refresh` : cacheKey;
    const sourceKey = this.resolveSourceKey(url, effectiveOptions);
    const flowId = this.ensureImageFlow(url, cacheKey, effectiveOptions);
    effectiveOptions.downloadCacheFlowId = flowId;
    const priority = effectiveOptions.priority || 1;
    
    // 1. 检查内存缓存

    const cached = effectiveOptions.forceRefresh ? null : this.getFromCache(cacheKey);
    if (cached) {
      logger.info(TAG, `✅ 内存缓存命中: ${url.substring(0, 80)}`);
      this.recordImageFlowEvent(
        flowId,
        DownloadCacheFlowEventType.CACHE_MEMORY_HIT,
        DownloadCacheFlowStage.DISK_CACHE,
        'online_image_memory_cache_hit',
        url,
        cacheKey,
        effectiveOptions,
        true,
        '',
        0,
        0
      );
      if (effectiveOptions.legadoImageTrace !== undefined) {
        LegadoImageTransportTrace.recordCacheHit(effectiveOptions.legadoImageTrace, 'memory');
      }
      return cached;
    }
    
    // 2. 检查磁盘缓存（仅在已初始化时）
    try {
      const diskCache = DiskCacheManager.getInstance();
      // 检查是否已初始化，避免警告日志泛滥
      if (diskCache.isInitialized()) {
        const diskCacheUrl = this.buildDiskCacheUrl(url, effectiveOptions);
        const diskCached = effectiveOptions.forceRefresh ? null : await diskCache.get(diskCacheUrl);

        if (diskCached) {
          logger.info(TAG, `✅ 磁盘缓存命中: ${url.substring(0, 80)}`);
          // 存入内存缓存
          await this.putToCache(cacheKey, diskCached);
          this.recordImageFlowEvent(
            flowId,
            DownloadCacheFlowEventType.CACHE_DISK_HIT,
            DownloadCacheFlowStage.DISK_CACHE,
            'online_image_disk_cache_hit',
            url,
            cacheKey,
            effectiveOptions,
            true,
            '',
            0,
            0
          );
          if (effectiveOptions.legadoImageTrace !== undefined) {
            LegadoImageTransportTrace.recordCacheHit(effectiveOptions.legadoImageTrace, 'disk');
          }
          this.syncCacheStatusToDatabaseAsync(url, diskCacheUrl, diskCache, flowId, effectiveOptions.sourceId || 0, sourceKey, cacheKey);
          return diskCached;
        }
      }
    } catch (error) {
      logger.debug(TAG, `磁盘缓存读取失败: ${String(error)}`);
    }

    const allowFailureSkip = this.shouldAllowFailureTtlSkip(effectiveOptions);
    const circuitDecision: NetworkTransportCircuitDecision = this.transportFailureCoordinator.shouldSuppress(
      url,
      allowFailureSkip,
      effectiveOptions.forceRefresh === true
    );
    if (circuitDecision.suppressed) {
      logger.debug(
        TAG,
        `后台图片请求命中主机熔断: fingerprint=${circuitDecision.descriptor.fingerprint}, ` +
          `remaining=${circuitDecision.remainingMs}ms`
      );
      if (effectiveOptions.legadoImageTrace !== undefined) {
        LegadoImageTransportTrace.recordTransportFailure(
          effectiveOptions.legadoImageTrace,
          circuitDecision.descriptor.canonicalMessage
        );
      }
      this.recordImageFlowEvent(
        flowId,
        DownloadCacheFlowEventType.FAILURE_TTL_HIT,
        DownloadCacheFlowStage.NETWORK,
        'background_host_circuit_open',
        url,
        cacheKey,
        effectiveOptions,
        true,
        circuitDecision.descriptor.canonicalMessage,
        0,
        0
      );
      throw new Error(circuitDecision.descriptor.canonicalMessage);
    }
    if (this.failureTtlCache.shouldSkip(effectiveOptions.sourceId || 0, sourceKey, cacheKey, 'network', allowFailureSkip)) {
      const message = this.failureTtlCache.getErrorMessage(effectiveOptions.sourceId || 0, sourceKey, cacheKey, 'network');
      logger.debug(TAG, `预取命中失败TTL，跳过后台请求: ${url.substring(0, 80)}, error=${message}`);
      this.recordImageFlowEvent(
        flowId,
        DownloadCacheFlowEventType.FAILURE_TTL_HIT,
        DownloadCacheFlowStage.NETWORK,
        'background_prefetch_failure_ttl_hit',
        url,
        cacheKey,
        effectiveOptions,
        true,
        message,
        0,
        0
      );
      return null;
    }
    
    // 3. [修复] 检查是否已在加载中
    if (this.loadingKeys.has(loadingKey)) {
      logger.debug(TAG, `缓存Key已在加载队列中，等待现有加载完成: ${url.substring(0, 80)}, key=${cacheKey}`);
      this.recordImageFlowEvent(
        flowId,
        DownloadCacheFlowEventType.CACHE_DEDUP_WAIT,
        DownloadCacheFlowStage.QUEUE,
        'online_image_cache_key_dedup_wait',
        url,
        cacheKey,
        effectiveOptions,
        true,
        '',
        0,
        0
      );
      // 等待现有加载完成，然后从缓存返回
      return this.waitForLoading(url, loadingKey, cacheKey, effectiveOptions, flowId);

    }
    
    // 4. 标记为正在加载
    this.loadingKeys.add(loadingKey);
    
    // 4. 加入请求队列
    return new Promise<image.PixelMap | null>((resolve, reject) => {
      const request: QueuedRequest = {
        url: url,
        options: effectiveOptions,
        cacheKey: cacheKey,
        loadingKey: loadingKey,
        flowId: flowId,
        sourceKey: sourceKey,
        visibleLoad: this.isVisibleLoad(effectiveOptions),
        priority: priority,
        resolve: resolve,
        reject: reject,
        retryCount: 0
      };
      
      this.requestQueue.push(request);
      this.sortQueue();
      
      logger.debug(TAG, `加入队列: url=${url.substring(0, 80)}, priority=${priority}, queueSize=${this.requestQueue.length}`);
      this.recordImageFlowEvent(
        flowId,
        DownloadCacheFlowEventType.CACHE_QUEUE_ENQUEUED,
        DownloadCacheFlowStage.QUEUE,
        'online_image_request_enqueued',
        url,
        cacheKey,
        effectiveOptions,
        true,
        '',
        0,
        0
      );
      
      // 触发队列处理
      this.processQueue();
    });
  }
  
  /**
   * [新增] 等待URL加载完成
   */
  private async waitForLoading(
    url: string,
    loadingKey: string,
    cacheKey: string,
    options: OnlineLoadOptions,
    flowId: string
  ): Promise<image.PixelMap | null> {
    const maxWaitTime = 30000; // 最多等待30秒
    const checkInterval = 100; // 每100ms检查一次
    const startTime = Date.now();
    
    while (this.loadingKeys.has(loadingKey)) {
      if (Date.now() - startTime > maxWaitTime) {
        logger.warn(TAG, `等待URL加载超时: ${url.substring(0, 80)}`);
        this.recordImageFlowEvent(
          flowId,
          DownloadCacheFlowEventType.IMAGE_DOWNLOAD_FAILED,
          DownloadCacheFlowStage.QUEUE,
          'online_image_dedup_wait_timeout',
          url,
          cacheKey,
          options,
          false,
          'wait_for_loading_timeout',
          Date.now() - startTime,
          0
        );
        return null;
      }
      
      // 等待100ms后再检查
      await new Promise<void>((resolve) => setTimeout(resolve, checkInterval));
      
      // 检查缓存是否已更新
      const cached = this.getFromCache(cacheKey);
      if (cached) {
        this.recordImageFlowEvent(
          flowId,
          DownloadCacheFlowEventType.CACHE_MEMORY_HIT,
          DownloadCacheFlowStage.DISK_CACHE,
          'online_image_dedup_wait_cache_hit',
          url,
          cacheKey,
          options,
          true,
          '',
          Date.now() - startTime,
          0
        );
        return cached;
      }
    }
    
    // 加载完成，从缓存返回
    return this.getFromCache(cacheKey);
  }


  /**
   * 处理请求队列
   */
  private async processQueue(): Promise<void> {
    // 检查是否可以处理新请求
    if (this.activeRequests >= this.MAX_CONCURRENT || this.requestQueue.length === 0) {
      return;
    }
    
    // 取出优先级最高的请求
    const request = this.requestQueue.shift();
    if (!request) {
      return;
    }
    
    this.activeRequests++;
    let permit: DownloadCacheLimiterPermit | null = null;
    
    try {
      const circuitDecision: NetworkTransportCircuitDecision = this.transportFailureCoordinator.shouldSuppress(
        request.url,
        this.shouldAllowFailureTtlSkip(request.options),
        request.options.forceRefresh === true
      );
      if (circuitDecision.suppressed) {
        logger.debug(
          TAG,
          `队列后台请求命中主机熔断: fingerprint=${circuitDecision.descriptor.fingerprint}, ` +
            `remaining=${circuitDecision.remainingMs}ms`
        );
        if (request.options.legadoImageTrace !== undefined) {
          LegadoImageTransportTrace.recordTransportFailure(
            request.options.legadoImageTrace,
            circuitDecision.descriptor.canonicalMessage
          );
        }
        this.recordImageFlowEvent(
          request.flowId,
          DownloadCacheFlowEventType.FAILURE_TTL_HIT,
          DownloadCacheFlowStage.NETWORK,
          'queued_background_host_circuit_open',
          request.url,
          request.cacheKey,
          request.options,
          true,
          circuitDecision.descriptor.canonicalMessage,
          0,
          0
        );
        this.loadingKeys.delete(request.loadingKey);
        request.reject(new Error(circuitDecision.descriptor.canonicalMessage));
        return;
      }

      await this.waitForInterval();

      const limiterActiveBefore = this.sourceLimiter.getActiveCount(request.sourceKey);
      if (limiterActiveBefore >= 1) {
        this.recordImageFlowEvent(
          request.flowId,
          DownloadCacheFlowEventType.SOURCE_LIMIT_WAIT_STARTED,
          DownloadCacheFlowStage.QUEUE,
          'online_image_source_limit_wait_started',
          request.url,
          request.cacheKey,
          request.options,
          true,
          '',
          0,
          0
        );
      }
      permit = await this.sourceLimiter.acquire(request.sourceKey);
      if (permit.waitedMs > 0) {
        this.recordImageFlowEvent(
          request.flowId,
          DownloadCacheFlowEventType.SOURCE_LIMIT_WAIT_COMPLETED,
          DownloadCacheFlowStage.QUEUE,
          'online_image_source_limit_wait_completed',
          request.url,
          request.cacheKey,
          request.options,
          true,
          '',
          permit.waitedMs,
          0
        );
      }

      // 执行HTTP请求
      const pixelMap = await this.httpRequest(request.url, request.options);
      
      if (pixelMap) {
        this.transportFailureCoordinator.recordSuccess(request.url);
        // 存入内存缓存
        await this.putToCache(request.cacheKey, pixelMap);
        
        // [新增] 存入磁盘缓存（仅在已初始化时）
        try {
          const diskCache = await this.getDiskCacheForRequest(request.options);
          if (diskCache && diskCache.isInitialized()) {
            const diskCacheUrl = this.buildDiskCacheUrl(request.url, request.options);
            const diskWriteStart = Date.now();
            this.recordImageFlowEvent(
              request.flowId,
              DownloadCacheFlowEventType.DISK_WRITE_STARTED,
              DownloadCacheFlowStage.DISK_CACHE,
              'online_image_disk_write_started',
              request.url,
              request.cacheKey,
              request.options,
              true,
              '',
              0,
              0
            );
            await diskCache.put(diskCacheUrl, pixelMap);
            logger.debug(TAG, `已保存到磁盘缓存: ${request.url.substring(0, 80)}`);
            this.recordImageFlowEvent(
              request.flowId,
              DownloadCacheFlowEventType.DISK_WRITE_COMPLETED,
              DownloadCacheFlowStage.DISK_CACHE,
              'online_image_disk_write_completed',
              request.url,
              request.cacheKey,
              request.options,
              true,
              '',
              Date.now() - diskWriteStart,
              0
            );

            // [P1] 缓存状态写库异步批量化，避免阻塞主加载链路
            this.syncCacheStatusToDatabaseAsync(
              request.url,
              diskCacheUrl,
              diskCache,
              request.flowId,
              request.options.sourceId || 0,
              request.sourceKey,
              request.cacheKey
            );
          }
        } catch (error) {
          logger.warn(TAG, `保存到磁盘缓存失败: ${String(error)}`);
          this.recordImageFlowEvent(
            request.flowId,
            DownloadCacheFlowEventType.DISK_WRITE_FAILED,
            DownloadCacheFlowStage.DISK_CACHE,
            'online_image_disk_write_failed',
            request.url,
            request.cacheKey,
            request.options,
            false,
            String(error),
            0,
            0
          );
        }

        
        request.resolve(pixelMap);
        
        // [修复] 加载成功，从loadingKeys中移除
        this.loadingKeys.delete(request.loadingKey);
      } else {
        const emptyMessage = 'online_image_empty_pixel_map';
        this.recordImageFlowEvent(
          request.flowId,
          DownloadCacheFlowEventType.IMAGE_DOWNLOAD_FAILED,
          DownloadCacheFlowStage.NETWORK,
          emptyMessage,
          request.url,
          request.cacheKey,
          request.options,
          false,
          emptyMessage,
          0,
          0
        );
        if (this.shouldAllowFailureTtlSkip(request.options)) {
          this.failureTtlCache.recordFailure(request.options.sourceId || 0, request.sourceKey, request.cacheKey, 'network', emptyMessage);
          this.recordImageFlowEvent(
            request.flowId,
            DownloadCacheFlowEventType.FAILURE_TTL_RECORDED,
            DownloadCacheFlowStage.NETWORK,
            'background_prefetch_failure_ttl_recorded',
            request.url,
            request.cacheKey,
            request.options,
            true,
            emptyMessage,
            0,
            0
          );
        }
        request.resolve(null);
        
        // [修复] 加载失败，从loadingKeys中移除
        this.loadingKeys.delete(request.loadingKey);
      }
      
    } catch (error) {
      const errorObj: Error = error instanceof Error ? error : new Error(String(error));
      const transportFailure: NetworkTransportFailureDescriptor =
        this.transportFailureCoordinator.describe(request.url, errorObj.message);
      const reportedErrorMessage: string = transportFailure.recognized
        ? transportFailure.canonicalMessage
        : errorObj.message;
      const stopBackgroundRetry: boolean = transportFailure.circuitEligible &&
        this.shouldAllowFailureTtlSkip(request.options);
      // 重试逻辑
      if (request.retryCount < this.MAX_RETRIES && !stopBackgroundRetry) {
        request.retryCount++;
        const retryTarget: string = transportFailure.recognized
          ? `fingerprint=${transportFailure.fingerprint}`
          : request.url.substring(0, 80);
        logger.warn(TAG, `请求失败，准备重试 (${request.retryCount}/${this.MAX_RETRIES}): ${retryTarget}`);
        this.recordImageFlowEvent(
          request.flowId,
          DownloadCacheFlowEventType.IMAGE_DOWNLOAD_RETRY,
          DownloadCacheFlowStage.NETWORK,
          'online_image_download_retry',
          request.url,
          request.cacheKey,
          request.options,
          false,
          reportedErrorMessage,
          0,
          0
        );
        
        // 重新加入队列（降低优先级）
        request.priority = Math.max(1, request.priority - 1);
        this.requestQueue.push(request);
        this.sortQueue();
        
        // 延迟后重试
        setTimeout(() => this.processQueue(), this.RETRY_DELAY);
      } else {
        if (transportFailure.recognized) {
          logger.warn(
            TAG,
            `请求最终失败（已按传输根因聚合）: ${transportFailure.canonicalMessage}, ` +
              `background=${this.shouldAllowFailureTtlSkip(request.options)}`
          );
        } else {
          logger.error(TAG, `请求最终失败: ${request.url.substring(0, 80)}, error=${String(errorObj)}`);
        }
        this.recordImageFlowEvent(
          request.flowId,
          DownloadCacheFlowEventType.IMAGE_DOWNLOAD_FAILED,
          DownloadCacheFlowStage.NETWORK,
          'online_image_download_final_failed',
          request.url,
          request.cacheKey,
          request.options,
          false,
          reportedErrorMessage,
          0,
          0
        );
        if (this.shouldAllowFailureTtlSkip(request.options)) {
          this.failureTtlCache.recordFailure(
            request.options.sourceId || 0,
            request.sourceKey,
            request.cacheKey,
            'network',
            reportedErrorMessage
          );
          this.recordImageFlowEvent(
            request.flowId,
            DownloadCacheFlowEventType.FAILURE_TTL_RECORDED,
            DownloadCacheFlowStage.NETWORK,
            'background_prefetch_failure_ttl_recorded',
            request.url,
            request.cacheKey,
            request.options,
            true,
            reportedErrorMessage,
            0,
            0
          );
        }
        request.reject(new Error(reportedErrorMessage));
        
        // [修复] 最终失败，从loadingKeys中移除
        this.loadingKeys.delete(request.loadingKey);
      }
    } finally {
      if (permit !== null) {
        this.sourceLimiter.release(permit);
      }
      this.activeRequests--;
      
      // 继续处理队列
      this.processQueue();
    }
  }

  private async getDiskCacheForRequest(_options?: OnlineLoadOptions): Promise<DiskCacheManager | null> {
    return DiskCacheManager.getInstance();
  }

  /**
   * 获取在线图片磁盘缓存文件路径。
   * 这里复用内部 cache partition 规则，避免调用方复制图源特例逻辑。
   */
  public async getCachedFilePath(url: string, options?: OnlineLoadOptions): Promise<string | null> {
    try {
      const diskCache = await this.getDiskCacheForRequest(options);
      if (!diskCache || !diskCache.isInitialized()) {
        return null;
      }
      const diskCacheUrl = this.buildDiskCacheUrl(url, options);
      return await diskCache.getCacheFilePath(diskCacheUrl);
    } catch (error) {
      logger.warn(TAG, `获取在线图片缓存文件路径失败: ${String(error)}`);
      return null;
    }
  }

  /**
   * 从已有在线图片缓存读取 PixelMap，不触发新的网络请求。
   * 调用方获得的是独立 PixelMap，使用完成后需要释放。
   */
  public async getCachedPixelMap(url: string, options?: OnlineLoadOptions): Promise<image.PixelMap | null> {
    try {
      const effectiveOptions: OnlineLoadOptions = this.cloneLoadOptions(options);
      const cacheKey = this.generateCacheKey(url, effectiveOptions);
      const memoryCached = this.getFromCache(cacheKey);
      if (memoryCached) {
        return memoryCached;
      }

      const diskCache = await this.getDiskCacheForRequest(effectiveOptions);
      if (!diskCache || !diskCache.isInitialized()) {
        return null;
      }

      const diskCacheUrl = this.buildDiskCacheUrl(url, effectiveOptions);
      const diskCached = await diskCache.get(diskCacheUrl);
      if (!diskCached) {
        return null;
      }

      await this.putToCache(cacheKey, diskCached);
      const sourceKey = this.resolveSourceKey(url, effectiveOptions);
      const flowId = this.ensureImageFlow(url, cacheKey, effectiveOptions);
      effectiveOptions.downloadCacheFlowId = flowId;
      this.syncCacheStatusToDatabaseAsync(url, diskCacheUrl, diskCache, flowId, effectiveOptions.sourceId || 0, sourceKey, cacheKey);
      return diskCached;
    } catch (error) {
      logger.warn(TAG, `获取在线图片缓存PixelMap失败: ${String(error)}`);
      return null;
    }
  }

  private buildDiskCacheUrl(url: string, options?: OnlineLoadOptions): string {
    if (!this.isPhotos18Request(options || {} as OnlineLoadOptions, url)) {
      return url;
    }
    const partition = this.resolveCachePartition(options, url);
    return `${url}#cache_partition=${partition}`;
  }

  private resolveCachePartition(options?: OnlineLoadOptions, url?: string): string {
    const explicitPartition = options?.partitionKey;
    if (explicitPartition && explicitPartition.length > 0) {
      return explicitPartition;
    }
    const headerPartition = options?.headers?.cachePartition;
    if (headerPartition && headerPartition.length > 0) {
      return headerPartition;
    }
    if (url && url.includes('/cover/')) {
      return 'detail-cover';
    }
    return 'default';
  }

  private syncCacheStatusToDatabaseAsync(
    imageUrl: string,
    cacheUrl: string,
    diskCache: DiskCacheManager,
    flowId: string,
    sourceId: number,
    sourceKey: string,
    cacheKey: string
  ): void {

    (async () => {
      try {
        const filePath = await diskCache.getCacheFilePath(cacheUrl);
        const fileSize = await diskCache.getCacheFileSize(cacheUrl);

        if (filePath && fileSize > 0) {
          this.enqueueCacheStatusUpdate(imageUrl, filePath, fileSize, flowId, sourceId, sourceKey, cacheKey);
        }
      } catch (error) {
        logger.warn(TAG, `准备缓存状态同步失败: ${String(error)}`);
        const optionsForEvent: OnlineLoadOptions = this.createFlowOptions(sourceId, flowId);
        this.recordImageFlowEvent(
          flowId,
          DownloadCacheFlowEventType.DB_FLUSH_FAILED,
          DownloadCacheFlowStage.DATABASE,
          'online_image_cache_status_prepare_failed',
          imageUrl,
          cacheKey,
          optionsForEvent,
          false,
          String(error),
          0,
          0
        );
      }
    })().catch((error: Error) => {
      logger.warn(TAG, `异步缓存状态同步失败: ${String(error)}`);
    });
  }

  private enqueueCacheStatusUpdate(
    imageUrl: string,
    localPath: string,
    fileSize: number,
    flowId: string,
    sourceId: number,
    sourceKey: string,
    cacheKey: string
  ): void {
    const updateValue: CacheStatusUpdateValue = {
      localPath: localPath,
      fileSize: fileSize,
      flowId: flowId,
      sourceId: sourceId,
      sourceKey: sourceKey,
      cacheKey: cacheKey
    };
    this.pendingCacheStatusUpdates.set(imageUrl, updateValue);
    this.scheduleCacheStatusFlush();
  }

  private scheduleCacheStatusFlush(): void {
    if (this.cacheStatusFlushTimer !== null) {
      return;
    }

    this.cacheStatusFlushTimer = setTimeout(() => {
      this.cacheStatusFlushTimer = null;
      this.flushCacheStatusUpdates().catch((error: Error) => {
        logger.warn(TAG, `批量同步缓存状态到数据库失败: ${String(error)}`);
      });
    }, this.CACHE_STATUS_FLUSH_DELAY) as number;
  }

  private async flushCacheStatusUpdates(): Promise<void> {
    if (this.isFlushingCacheStatusUpdates || this.pendingCacheStatusUpdates.size === 0) {
      return;
    }

    this.isFlushingCacheStatusUpdates = true;
    const updates: Array<CacheStatusUpdatePayload> = [];
    const pageCacheUpdates: Array<PageCacheUpdate> = [];
    this.pendingCacheStatusUpdates.forEach((value, imageUrl) => {
      updates.push({
        imageUrl: imageUrl,
        localPath: value.localPath,
        fileSize: value.fileSize,
        flowId: value.flowId,
        sourceId: value.sourceId,
        sourceKey: value.sourceKey,
        cacheKey: value.cacheKey
      });
      pageCacheUpdates.push({
        imageUrl: imageUrl,
        localPath: value.localPath,
        fileSize: value.fileSize
      } as PageCacheUpdate);
    });
    this.pendingCacheStatusUpdates.clear();

    try {
      const flushStartedAt = Date.now();
      this.recordCacheStatusFlushEvent(
        updates,
        DownloadCacheFlowEventType.DB_FLUSH_STARTED,
        'online_image_cache_status_flush_started',
        true,
        '',
        0
      );
      const dataManager = DataManager.getInstance();
      const chapterIds = await dataManager.batchUpdateOnlinePageCacheStatus(pageCacheUpdates);
      logger.debug(TAG, `Flushed cache status updates: count=${updates.length}`);
      logger.debug(TAG, `已批量同步缓存状态到数据库: ${updates.length}条`);
      this.recordCacheStatusFlushEvent(
        updates,
        DownloadCacheFlowEventType.DB_FLUSH_COMPLETED,
        'online_image_cache_status_flush_completed',
        true,
        '',
        Date.now() - flushStartedAt
      );
      await this.archiveCompletedOnlineChapterCaches(chapterIds, updates);
    } catch (error) {
      logger.warn(TAG, `批量同步缓存状态到数据库失败: ${String(error)}`);
      this.recordCacheStatusFlushEvent(
        updates,
        DownloadCacheFlowEventType.DB_FLUSH_FAILED,
        'online_image_cache_status_flush_failed',
        false,
        String(error),
        0
      );
    } finally {
      this.isFlushingCacheStatusUpdates = false;
      if (this.pendingCacheStatusUpdates.size > 0) {
        this.scheduleCacheStatusFlush();
      }
    }
  }

  private async archiveCompletedOnlineChapterCaches(
    chapterIds: string[],
    updates: Array<CacheStatusUpdatePayload>
  ): Promise<void> {
    if (chapterIds.length === 0) {
      return;
    }

    const archiveService = OnlineMangaArchiveService.getInstance();
    let queuedCount = 0;
    for (let i = 0; i < chapterIds.length; i++) {
      archiveService.enqueueArchiveCachedOnlineChapter(chapterIds[i], 'reader_cache_complete');
      queuedCount++;
    }
    logger.debug(TAG, `阅读缓存归档任务已投递: count=${queuedCount}`);
    this.recordCacheStatusFlushEvent(
      updates,
      DownloadCacheFlowEventType.ARCHIVE_STARTED,
      'online_image_reader_cache_archive_enqueued',
      true,
      '',
      0
    );
  }

  private cloneLoadOptions(options?: OnlineLoadOptions): OnlineLoadOptions {
    const cloned: OnlineLoadOptions = {} as OnlineLoadOptions;
    if (!options) {
      return cloned;
    }
    cloned.width = options.width;
    cloned.height = options.height;
    cloned.headers = options.headers;
    cloned.sourceId = options.sourceId;
    cloned.priority = options.priority;
    cloned.partitionKey = options.partitionKey;
    cloned.downloadCacheFlowId = options.downloadCacheFlowId;
    cloned.visibleLoad = options.visibleLoad;
    cloned.prefetch = options.prefetch;
    cloned.skipFailureTtl = options.skipFailureTtl;
    cloned.forceRefresh = options.forceRefresh;
    cloned.legadoImageTrace = options.legadoImageTrace;
    return cloned;
  }

  private createFlowOptions(sourceId: number, flowId: string): OnlineLoadOptions {
    const options: OnlineLoadOptions = {} as OnlineLoadOptions;
    options.sourceId = sourceId;
    options.downloadCacheFlowId = flowId;
    return options;
  }

  private ensureImageFlow(url: string, cacheKey: string, options: OnlineLoadOptions): string {
    try {
      const providedFlowId = options.downloadCacheFlowId ? options.downloadCacheFlowId : '';
      const flowId = providedFlowId.length > 0 ? providedFlowId : this.downloadCacheFlowMonitor.createSessionId('online_image');
      const info: DownloadCacheFlowSessionInfo = new DownloadCacheFlowSessionInfo();
      info.sessionId = flowId;
      info.entrySource = DownloadCacheEntrySource.ONLINE_IMAGE_LOADER;
      info.contentType = DownloadCacheContentType.IMAGE;
      info.sourceId = options.sourceId || 0;
      info.sourceKey = this.resolveSourceKey(url, options);
      info.url = url;
      info.cacheKey = cacheKey;
      info.totalCount = 1;
      info.pageName = 'OnlineImageLoader';
      info.startedAt = Date.now();
      return this.downloadCacheFlowMonitor.ensureSession(info);
    } catch (error) {
      logger.warn(TAG, `创建在线图片下载缓存链路失败: ${String(error)}`);
      return options.downloadCacheFlowId ? options.downloadCacheFlowId : '';
    }
  }

  private recordImageFlowEvent(
    flowId: string,
    eventType: DownloadCacheFlowEventType,
    stage: DownloadCacheFlowStage,
    reason: string,
    url: string,
    cacheKey: string,
    options: OnlineLoadOptions,
    success: boolean,
    errorMessage: string,
    elapsedMs: number,
    byteCount: number
  ): void {
    try {
      const event: DownloadCacheFlowEvent = this.downloadCacheFlowMonitor.createEvent(flowId, eventType, stage, reason);
      event.entrySource = DownloadCacheEntrySource.ONLINE_IMAGE_LOADER;
      event.contentType = DownloadCacheContentType.IMAGE;
      event.sourceId = options.sourceId || 0;
      event.sourceKey = this.resolveSourceKey(url, options);
      event.url = url;
      event.cacheKey = cacheKey;
      event.success = success;
      event.severity = this.resolveEventSeverity(eventType, success);
      event.errorMessage = errorMessage;
      event.elapsedMs = elapsedMs;
      event.byteCount = byteCount;
      event.queueSize = this.requestQueue.length;
      event.activeCount = this.activeRequests;
      event.cacheHit = eventType === DownloadCacheFlowEventType.CACHE_MEMORY_HIT ||
        eventType === DownloadCacheFlowEventType.CACHE_DISK_HIT;
      event.visibleLoad = this.isVisibleLoad(options);
      event.detail = `priority=${options.priority || 0}, source=${event.sourceKey}`;
      this.safeRecordDownloadCacheFlowEvent(event);
    } catch (error) {
      logger.warn(TAG, `记录在线图片下载缓存链路失败: ${String(error)}`);
    }
  }

  private recordCacheStatusFlushEvent(
    updates: Array<CacheStatusUpdatePayload>,
    eventType: DownloadCacheFlowEventType,
    reason: string,
    success: boolean,
    errorMessage: string,
    elapsedMs: number
  ): void {
    for (let i = 0; i < updates.length; i++) {
      const update = updates[i];
      const options: OnlineLoadOptions = this.createFlowOptions(update.sourceId, update.flowId);
      this.recordImageFlowEvent(
        update.flowId,
        eventType,
        eventType === DownloadCacheFlowEventType.ARCHIVE_STARTED ? DownloadCacheFlowStage.ARCHIVE : DownloadCacheFlowStage.DATABASE,
        reason,
        update.imageUrl,
        update.cacheKey,
        options,
        success,
        errorMessage,
        elapsedMs,
        update.fileSize
      );
    }
  }

  private safeRecordDownloadCacheFlowEvent(event: DownloadCacheFlowEvent): void {
    try {
      this.downloadCacheFlowMonitor.record(event);
    } catch (error) {
      logger.warn(TAG, `在线图片链路事件写入失败: ${String(error)}`);
    }
  }

  private resolveEventSeverity(eventType: DownloadCacheFlowEventType, success: boolean): DownloadCacheFlowSeverity {
    if (!success) {
      return DownloadCacheFlowSeverity.ERROR;
    }
    if (eventType === DownloadCacheFlowEventType.CACHE_MEMORY_HIT ||
      eventType === DownloadCacheFlowEventType.CACHE_DISK_HIT ||
      eventType === DownloadCacheFlowEventType.CACHE_DEDUP_WAIT ||
      eventType === DownloadCacheFlowEventType.CACHE_QUEUE_ENQUEUED ||
      eventType === DownloadCacheFlowEventType.SOURCE_LIMIT_WAIT_STARTED ||
      eventType === DownloadCacheFlowEventType.SOURCE_LIMIT_WAIT_COMPLETED) {
      return DownloadCacheFlowSeverity.DEBUG;
    }
    return DownloadCacheFlowSeverity.INFO;
  }

  private resolveSourceKey(url: string, options?: OnlineLoadOptions): string {
    const sourceId = options?.sourceId || 0;
    if (sourceId > 0) {
      return `source_${sourceId}`;
    }
    const host = this.extractHost(url);
    return host.length > 0 ? host : 'unknown_source';
  }

  private isVisibleLoad(options?: OnlineLoadOptions): boolean {
    if (options?.visibleLoad === true) {
      return true;
    }
    const priority = options?.priority || 0;
    return priority >= 10;
  }

  private shouldAllowFailureTtlSkip(options?: OnlineLoadOptions): boolean {
    if (options?.skipFailureTtl === true) {
      return false;
    }
    if (this.isVisibleLoad(options)) {
      return false;
    }
    if (options?.prefetch === true) {
      return true;
    }
    const priority = options?.priority || 0;
    return priority <= 0;
  }

  /**
   * HTTP请求
   */
  private async httpRequest(url: string, options: OnlineLoadOptions): Promise<image.PixelMap | null> {
    // 首先尝试原始URL
    try {
      return await this.doHttpRequest(url, options);
    } catch (error) {
      const errObj = error as Object;
      const errCode = (errObj as Record<string, Object>)['code'];
      const errMsg = error instanceof Error ? error.message : String(error);
      
      if (this.isPhotos18Request(options, url) && errMsg.includes('HTTP请求失败: 403')) {
        logger.warn(TAG, `Photos18图片请求403，尝试刷新Cookie后重试: ${url.substring(0, 80)}`);
        const recovered = await this.retryPhotos18WithFreshCookie(url, options);
        if (recovered) {
          return recovered;
        }
      }

      if (this.isHttp403Error(errMsg) && this.hasRelaxable403Headers(options)) {
        logger.warn(TAG, `HTTP 403，尝试使用精简请求头重试: ${url.substring(0, 80)}`);
        try {
          return await this.doHttpRequest(url, this.buildRelaxed403RetryOptions(options));
        } catch (retryError) {
          logger.warn(TAG, `精简请求头重试仍失败: ${String(retryError)}`);
        }
      }
      
      // 如果是SSL错误(2300060)且URL是HTTPS，尝试降级为HTTP
      if (this.isRmcdnRequest(url) && this.isHttp403Error(errMsg)) {
        logger.warn(TAG, `rmcdn鍥剧墖HTTP 403锛屽皾璇昗ebView鍏滃簳鍔犺浇: ${url.substring(0, 80)}`);
        const fallbackStart = Date.now();
        this.recordWebViewFallbackEvent(url, options, true, 'rmcdn_webview_fallback_started', '', 0);
        const recovered = await this.retryRmcdnWithWebView(url, options);
        if (recovered) {
          this.recordWebViewFallbackEvent(url, options, true, 'rmcdn_webview_fallback_completed', '', Date.now() - fallbackStart);
          return recovered;
        }
        this.recordWebViewFallbackEvent(url, options, false, 'rmcdn_webview_fallback_failed', errMsg, Date.now() - fallbackStart);
      }

      if (this.isPhotos18Request(options, url) && this.isHttp403Error(errMsg)) {
        logger.warn(TAG, `Photos18 HTTP 403锛屽皾璇曚娇鐢║ebView鍏滃簳鍔犺浇: ${url.substring(0, 80)}`);
        const fallbackStart = Date.now();
        this.recordWebViewFallbackEvent(url, options, true, 'photos18_webview_fallback_started', '', 0);
        const recovered = await this.retryPhotos18WithWebView(url, options);
        if (recovered) {
          this.recordWebViewFallbackEvent(url, options, true, 'photos18_webview_fallback_completed', '', Date.now() - fallbackStart);
          return recovered;
        }
        this.recordWebViewFallbackEvent(url, options, false, 'photos18_webview_fallback_failed', errMsg, Date.now() - fallbackStart);
      }

      if (errCode === 2300060 && url.startsWith('https://')) {
        const httpUrl = url.replace('https://', 'http://');
        logger.info(TAG, `SSL错误，尝试HTTP降级: ${httpUrl.substring(0, 80)}`);

        try {
          return await this.doHttpRequest(httpUrl, options);
        } catch (retryError) {
          // HTTP降级也失败，抛出原始错误
          logger.warn(TAG, `HTTP降级也失败: ${httpUrl.substring(0, 80)}`);
          throw error instanceof Error ? error : new Error(String(error));
        }
      }

      // Pixiv CDN HTTP模块无法连接，使用WebView降级加载
      if (this.isPixivCdnUrl(url)) {
        logger.warn(TAG, `Pixiv CDN HTTP加载失败(code=${errCode})，尝试WebView降级: ${url.substring(0, 80)}`);
        const fallbackStart = Date.now();
        this.recordWebViewFallbackEvent(url, options, true, 'pixiv_webview_fallback_started', '', 0);
        const recovered = await this.retryPixivWithWebView(url, options);
        if (recovered) {
          this.recordWebViewFallbackEvent(url, options, true, 'pixiv_webview_fallback_completed', '', Date.now() - fallbackStart);
          return recovered;
        }
        this.recordWebViewFallbackEvent(url, options, false, 'pixiv_webview_fallback_failed', errMsg, Date.now() - fallbackStart);
      }

      throw error instanceof Error ? error : new Error(String(error));
    }
  }

  private recordWebViewFallbackEvent(
    url: string,
    options: OnlineLoadOptions,
    success: boolean,
    reason: string,
    errorMessage: string,
    elapsedMs: number
  ): void {
    const cacheKey = this.generateCacheKey(url, options);
    const flowId = options.downloadCacheFlowId && options.downloadCacheFlowId.length > 0
      ? options.downloadCacheFlowId
      : this.ensureImageFlow(url, cacheKey, options);
    let eventType = DownloadCacheFlowEventType.WEBVIEW_FALLBACK_COMPLETED;
    if (reason.includes('started')) {
      eventType = DownloadCacheFlowEventType.WEBVIEW_FALLBACK_STARTED;
    } else if (!success) {
      eventType = DownloadCacheFlowEventType.WEBVIEW_FALLBACK_FAILED;
    }
    this.recordImageFlowEvent(
      flowId,
      eventType,
      DownloadCacheFlowStage.NETWORK,
      reason,
      url,
      cacheKey,
      options,
      success,
      errorMessage,
      elapsedMs,
      0
    );
  }

  private isPhotos18Request(options: OnlineLoadOptions, url: string): boolean {
    if (url.includes('photos18.com')) {
      return true;
    }
    const sourceId = options.sourceId;
    if (!sourceId) {
      return false;
    }
    const headers = options.headers;
    if (headers && headers.referer && headers.referer.includes('photos18.com')) {
      return true;
    }
    return false;
  }

  private isPixivCdnUrl(url: string): boolean {
    return url.includes('i.pximg.net') || url.includes('.pximg.net');
  }

  private async retryPixivWithWebView(url: string, options: OnlineLoadOptions): Promise<image.PixelMap | null> {
    const controller = new webview.WebviewController();
    const headers = await this.buildHeaders(url, options);
    const userAgent = headers.userAgent ? headers.userAgent : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
    const sourceId = `pixiv_cdn_${Date.now()}`;
    const config: WebViewSourceConfig = {
      sourceId: sourceId,
      userAgent: userAgent,
      enableJavaScript: true,
      enableImages: true,
      cookiePolicy: 'accept_all',
      timeout: this.TIMEOUT
    };

    let resolveImage: (buffer: ArrayBuffer) => void = (): void => {};
    let rejectImage: (error: Error) => void = (): void => {};

    const imageLoadPromise = new Promise<ArrayBuffer>((resolve, reject) => {
      resolveImage = resolve;
      rejectImage = reject;
    });

    const extractScript = `(() => {
      const img = document.querySelector('img');
      if (!img) { return 'NO_IMG'; }
      if (!img.complete || img.naturalWidth === 0) { return 'NOT_READY'; }
      try {
        const canvas = document.createElement('canvas');
        canvas.width = img.naturalWidth;
        canvas.height = img.naturalHeight;
        const ctx = canvas.getContext('2d');
        ctx.drawImage(img, 0, 0);
        const dataUrl = canvas.toDataURL('image/png');
        const base64 = dataUrl.split(',')[1];
        const binary = atob(base64);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i++) { bytes[i] = binary.charCodeAt(i); }
        return bytes.buffer;
      } catch (e) { return 'ERROR:' + e.message; }
    })();`;

    const callbacks: WebViewEventCallbacks = {
      onPageEnd: async (_loadedUrl: string) => {
        let attempts = 0;
        const maxAttempts = 5;
        while (attempts < maxAttempts) {
          try {
            await this.delay(attempts === 0 ? 300 : 500);
            const jsResult = await controller.runJavaScriptExt(extractScript);
            const resultType = jsResult.getType();
            if (resultType === webview.JsMessageType.ARRAY_BUFFER) {
              resolveImage(jsResult.getArrayBuffer());
              return;
            } else if (resultType === webview.JsMessageType.STRING) {
              const str = jsResult.getString();
              if (str === 'NO_IMG') {
                rejectImage(new Error('Pixiv WebView: no img element found'));
                return;
              }
              if (str === 'NOT_READY') {
                attempts++;
                continue;
              }
              if (str && str.startsWith('ERROR:')) {
                rejectImage(new Error(`Pixiv WebView canvas error: ${str}`));
                return;
              }
              rejectImage(new Error(`Pixiv WebView unexpected: ${str}`));
              return;
            }
          } catch (e) {
            rejectImage(e instanceof Error ? e : new Error(String(e)));
            return;
          }
          attempts++;
        }
        rejectImage(new Error('Pixiv WebView: image not ready after retries'));
      },
      onError: (error: string) => {
        rejectImage(new Error(error));
      }
    };

    GlobalWebViewContainer.addWebView(sourceId, controller, config, callbacks, 'about:blank');

    try {
      await this.loadWebViewUrlWithRetry(controller, url, headers, userAgent);
      const timeoutPromise = new Promise<never>((_resolve, reject) => {
        setTimeout(() => reject(new Error('Pixiv WebView load timeout')), this.WEBVIEW_FALLBACK_LOAD_TIMEOUT);
      });
      const imageBuffer = await Promise.race([imageLoadPromise, timeoutPromise]);
      if (!imageBuffer || imageBuffer.byteLength === 0) {
        throw new Error('Pixiv WebView returned empty buffer');
      }
      const pixelMap = await this.createPixelMapFromBuffer(imageBuffer, options);
      logger.info(TAG, `Pixiv WebView降级加载成功: bytes=${imageBuffer.byteLength}`);
      return pixelMap;
    } catch (error) {
      const errMsg = error instanceof Error ? error.message : String(error);
      logger.warn(TAG, `Pixiv WebView降级加载失败: ${errMsg}`);
      return null;
    } finally {
      try {
        controller.loadUrl('about:blank');
      } catch (_loadBlankError) {
      }
      GlobalWebViewContainer.removeWebView(sourceId);
    }
  }

  private async retryPhotos18WithFreshCookie(url: string, options: OnlineLoadOptions): Promise<image.PixelMap | null> {
    const sourceId = options.sourceId;
    if (!sourceId) {
      return null;
    }
    try {
      this.clearCookieCache(sourceId);
      const cookieManager = CookieManager.getInstance();
      const freshCookie = await cookieManager.getCookieStringForUrl(sourceId, url);
      if (!freshCookie || freshCookie.length === 0) {
        logger.warn(TAG, 'Photos18 refresh cookie returned empty, skip retry');
        /*
        logger.warn(TAG, 'Photos18刷新Cookie后仍为空，放弃重试');
        return null;
      }
        */
        return null;
      }
      const retriedHeaders: RequestHeaders = {
        userAgent: options.headers?.userAgent,
        accept: options.headers?.accept,
        referer: options.headers?.referer,
        origin: options.headers?.origin,
        cookie: freshCookie,
        authorization: options.headers?.authorization,
        acceptLanguage: options.headers?.acceptLanguage,
        cacheControl: options.headers?.cacheControl,
        pragma: options.headers?.pragma,
        secFetchDest: options.headers?.secFetchDest,
        secFetchMode: options.headers?.secFetchMode,
        secFetchSite: options.headers?.secFetchSite,
        cachePartition: options.headers?.cachePartition,
        extraHeaders: this.cloneHeaderEntries(options.headers?.extraHeaders)
      };
      const retriedOptions: OnlineLoadOptions = {
        width: options.width,
        height: options.height,
        headers: retriedHeaders,
        sourceId: options.sourceId,
        priority: options.priority,
        partitionKey: options.partitionKey,
        downloadCacheFlowId: options.downloadCacheFlowId,
        visibleLoad: options.visibleLoad,
        prefetch: options.prefetch,
        skipFailureTtl: options.skipFailureTtl,
        forceRefresh: options.forceRefresh,
        legadoImageTrace: options.legadoImageTrace
      };

      return await this.doHttpRequest(url, retriedOptions);
    } catch (error) {
      logger.warn(TAG, `Photos18刷新Cookie重试失败: ${String(error)}`);
      return null;
    }
  }

  private async retryPhotos18WithWebView(url: string, options: OnlineLoadOptions): Promise<image.PixelMap | null> {
    const fallbackSourceId = `${this.photos18FallbackPrefix}_${Date.now()}_${Math.floor(Math.random() * 1000)}`;
    const controller = new webview.WebviewController();
    const headers = await this.buildHeaders(url, options);
    const userAgent = headers.userAgent ? headers.userAgent : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
    const config: WebViewSourceConfig = {
      sourceId: fallbackSourceId,
      userAgent: userAgent,
      enableJavaScript: true,
      enableImages: true,
      cookiePolicy: 'accept_all',
      timeout: this.TIMEOUT
    };

    let waiter: WebViewLoadWaiter | null = null;
    const pageLoadPromise = new Promise<void>((resolve, reject) => {
      waiter = { resolve: resolve, reject: reject };
    });
    const callbacks: WebViewEventCallbacks = {
      onPageEnd: (_loadedUrl: string) => {
        if (waiter) {
          waiter.resolve();
          waiter = null;
        }
      },
      onError: (error: string) => {
        if (waiter) {
          waiter.reject(new Error(error));
          waiter = null;
        }
      }
    };

    GlobalWebViewContainer.addWebView(fallbackSourceId, controller, config, callbacks, 'about:blank');

    try {
      await this.loadWebViewUrlWithRetry(controller, url, headers, userAgent);
      await this.waitForPromiseWithTimeout(pageLoadPromise, this.WEBVIEW_FALLBACK_LOAD_TIMEOUT, 'Photos18 WebView load timeout');
      await this.delay(this.WEBVIEW_FALLBACK_SETTLE_DELAY);
      const imageBuffer = await this.extractPhotos18ArrayBuffer(controller);
      const pixelMap = await this.createPixelMapFromBuffer(imageBuffer, options);
      logger.info(TAG, `Photos18 WebView鍏滃簳鍔犺浇鎴愬姛: bytes=${imageBuffer.byteLength}`);
      return pixelMap;
    } catch (error) {
      const errMsg = error instanceof Error ? error.message : String(error);
      logger.warn(TAG, `Photos18 WebView鍏滃簳鍔犺浇澶辫触: ${errMsg}`);
      return null;
    } finally {
      try {
        controller.loadUrl('about:blank');
      } catch (_loadBlankError) {
      }
      GlobalWebViewContainer.removeWebView(fallbackSourceId);
    }
  }

  /**
   * 执行HTTP请求（内部方法）
   */
  private isRmcdnRequest(url: string): boolean {
    return url.includes('rmcdn');
  }

  private isDogeMangaImageRequest(url: string): boolean {
    return url.includes('dogemanga.com/images/');
  }

  private isHttp403Error(message: string): boolean {
    return message.includes('403');
  }

  private hasRelaxable403Headers(options: OnlineLoadOptions): boolean {
    const headers = options.headers;
    if (!headers) {
      return false;
    }
    if (headers.origin && headers.origin.length > 0) {
      return true;
    }
    if (headers.secFetchDest && headers.secFetchDest.length > 0) {
      return true;
    }
    if (headers.secFetchMode && headers.secFetchMode.length > 0) {
      return true;
    }
    if (headers.secFetchSite && headers.secFetchSite.length > 0) {
      return true;
    }
    if (headers.cacheControl && headers.cacheControl.length > 0) {
      return true;
    }
    if (headers.pragma && headers.pragma.length > 0) {
      return true;
    }
    return false;
  }

  private buildRelaxed403RetryOptions(options: OnlineLoadOptions): OnlineLoadOptions {
    const relaxedOptions: OnlineLoadOptions = {
      width: options.width,
      height: options.height,
      sourceId: options.sourceId,
      priority: options.priority,
      partitionKey: options.partitionKey,
      downloadCacheFlowId: options.downloadCacheFlowId,
      visibleLoad: options.visibleLoad,
      prefetch: options.prefetch,
      skipFailureTtl: options.skipFailureTtl,
      forceRefresh: options.forceRefresh,
      legadoImageTrace: options.legadoImageTrace
    };
    const headers = options.headers;
    if (headers) {
      const relaxedHeaders: RequestHeaders = {} as RequestHeaders;
      if (headers.userAgent) {
        relaxedHeaders.userAgent = String(headers.userAgent);
      }
      if (headers.accept) {
        relaxedHeaders.accept = String(headers.accept);
      }
      if (headers.referer) {
        relaxedHeaders.referer = String(headers.referer);
      }
      if (headers.origin) {
        relaxedHeaders.origin = String(headers.origin);
      }
      if (headers.cookie) {
        relaxedHeaders.cookie = String(headers.cookie);
      }
      if (headers.authorization) {
        relaxedHeaders.authorization = String(headers.authorization);
      }
      if (headers.acceptLanguage) {
        relaxedHeaders.acceptLanguage = String(headers.acceptLanguage);
      }
      if (headers.cacheControl) {
        relaxedHeaders.cacheControl = String(headers.cacheControl);
      }
      if (headers.pragma) {
        relaxedHeaders.pragma = String(headers.pragma);
      }
      if (headers.secFetchDest) {
        relaxedHeaders.secFetchDest = String(headers.secFetchDest);
      }
      if (headers.secFetchMode) {
        relaxedHeaders.secFetchMode = String(headers.secFetchMode);
      }
      if (headers.secFetchSite) {
        relaxedHeaders.secFetchSite = String(headers.secFetchSite);
      }
      if (headers.cachePartition) {
        relaxedHeaders.cachePartition = String(headers.cachePartition);
      }
      relaxedHeaders.extraHeaders = this.cloneHeaderEntries(headers.extraHeaders);
      relaxedOptions.headers = relaxedHeaders;
    }
    return relaxedOptions;
  }

  private async retryRmcdnWithWebView(url: string, options: OnlineLoadOptions): Promise<image.PixelMap | null> {
    const fallbackSourceId = `${this.rmcdnFallbackPrefix}_${Date.now()}_${Math.floor(Math.random() * 1000)}`;
    const controller = new webview.WebviewController();
    const headers = await this.buildHeaders(url, options);
    const userAgent = headers.userAgent ? headers.userAgent : 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
    const config: WebViewSourceConfig = {
      sourceId: fallbackSourceId,
      userAgent: userAgent,
      enableJavaScript: true,
      enableImages: true,
      cookiePolicy: 'accept_all',
      timeout: this.TIMEOUT
    };

    let waiter: WebViewLoadWaiter | null = null;
    const pageLoadPromise = new Promise<void>((resolve, reject) => {
      waiter = { resolve: resolve, reject: reject };
    });
    const callbacks: WebViewEventCallbacks = {
      onPageEnd: (_loadedUrl: string) => {
        if (waiter) {
          waiter.resolve();
          waiter = null;
        }
      },
      onError: (error: string) => {
        if (waiter) {
          waiter.reject(new Error(error));
          waiter = null;
        }
      }
    };

    GlobalWebViewContainer.addWebView(fallbackSourceId, controller, config, callbacks, 'about:blank');

    try {
      await this.loadWebViewUrlWithRetry(controller, url, headers, userAgent);
      await this.waitForPromiseWithTimeout(pageLoadPromise, this.WEBVIEW_FALLBACK_LOAD_TIMEOUT, 'rmcdn WebView load timeout');
      await this.delay(this.WEBVIEW_FALLBACK_SETTLE_DELAY);
      const imageBuffer = await this.extractRmcdnArrayBuffer(controller);
      const pixelMap = await this.createPixelMapFromBuffer(imageBuffer, options);
      logger.info(TAG, `rmcdn WebView鍏滃簳鍔犺浇鎴愬姛: bytes=${imageBuffer.byteLength}`);
      return pixelMap;
    } catch (error) {
      const errMsg = error instanceof Error ? error.message : String(error);
      logger.warn(TAG, `rmcdn WebView鍏滃簳鍔犺浇澶辫触: ${errMsg}`);
      return null;
    } finally {
      try {
        controller.loadUrl('about:blank');
      } catch (_loadBlankError) {
      }
      GlobalWebViewContainer.removeWebView(fallbackSourceId);
    }
  }

  private async loadWebViewUrlWithRetry(
    controller: webview.WebviewController,
    url: string,
    headers: HttpHeadersObject,
    userAgent: string
  ): Promise<void> {
    const webHeaders = this.buildWebHeaders(headers);
    let attempt = 0;
    let lastError: Error | null = null;

    while (attempt < this.WEBVIEW_FALLBACK_ATTACH_RETRIES) {
      try {
        controller.setCustomUserAgent(userAgent);
        if (webHeaders.length > 0) {
          controller.loadUrl(url, webHeaders);
        } else {
          controller.loadUrl(url);
        }
        return;
      } catch (error) {
        lastError = error instanceof Error ? error : new Error(String(error));
        attempt = attempt + 1;
        await this.delay(this.WEBVIEW_FALLBACK_ATTACH_DELAY);
      }
    }

    if (lastError) {
      throw lastError;
    }
    throw new Error('WebView loadUrl failed');
  }

  private buildWebHeaders(headers: HttpHeadersObject): Array<webview.WebHeader> {
    const result: Array<webview.WebHeader> = [];
    const pairs: Array<[string, string | undefined]> = [
      ['User-Agent', headers.userAgent],
      ['Origin', headers.origin],
      ['Accept', headers.accept],
      ['Referer', headers.referer],
      ['Cookie', headers.cookie],
      ['Authorization', headers.authorization],
      ['Accept-Language', headers.acceptLanguage],
      ['Cache-Control', headers.cacheControl],
      ['Pragma', headers.pragma],
      ['Sec-Fetch-Dest', headers.secFetchDest],
      ['Sec-Fetch-Mode', headers.secFetchMode],
      ['Sec-Fetch-Site', headers.secFetchSite]
    ];
    let index = 0;
    while (index < pairs.length) {
      const pair = pairs[index];
      const headerValue = pair[1];
      if (headerValue && headerValue.length > 0) {
        result.push({
          headerKey: pair[0],
          headerValue: headerValue
        });
      }
      index = index + 1;
    }
    const extraHeaders = this.cloneHeaderEntries(headers.extraHeaders);
    if (extraHeaders) {
      let extraIndex = 0;
      while (extraIndex < extraHeaders.length) {
        const extraHeader = extraHeaders[extraIndex];
        if (extraHeader.name.length > 0 && extraHeader.value.length > 0) {
          result.push({
            headerKey: extraHeader.name,
            headerValue: extraHeader.value
          });
        }
        extraIndex = extraIndex + 1;
      }
    }
    return result;
  }

  private async waitForPromiseWithTimeout(task: Promise<void>, timeoutMs: number, message: string): Promise<void> {
    let timeoutId: number | null = null;
    return await new Promise<void>((resolve, reject) => {
      timeoutId = setTimeout(() => {
        reject(new Error(message));
      }, timeoutMs);

      task.then(() => {
        if (timeoutId !== null) {
          clearTimeout(timeoutId);
        }
        resolve();
      }).catch((error: Error) => {
        if (timeoutId !== null) {
          clearTimeout(timeoutId);
        }
        reject(error);
      });
    });
  }

  private async extractRmcdnArrayBuffer(controller: webview.WebviewController): Promise<ArrayBuffer> {
    const script = `
      (() => {
        const imageElement = document.images && document.images.length > 0 ? document.images[0] : null;
        let requestUrl = '';
        if (imageElement && imageElement.src) {
          requestUrl = String(imageElement.src);
        } else if (window && window.location && window.location.href) {
          requestUrl = String(window.location.href);
        }
        if (!requestUrl) {
          throw new Error('rmcdn request url missing');
        }
        const xhr = new XMLHttpRequest();
        xhr.open('GET', requestUrl, false);
        xhr.responseType = 'arraybuffer';
        xhr.send(null);
        if (xhr.status >= 400) {
          throw new Error('rmcdn xhr failed with status ' + String(xhr.status));
        }
        if (!xhr.response) {
          throw new Error('rmcdn xhr returned empty buffer');
        }
        return xhr.response;
      })();
    `;
    return await this.runArrayBufferScript(controller, script, 'rmcdn');
  }

  private async extractPhotos18ArrayBuffer(controller: webview.WebviewController): Promise<ArrayBuffer> {
    const script = `
      (() => {
        const imageElement = document.images && document.images.length > 0 ? document.images[0] : null;
        let requestUrl = '';
        if (imageElement && imageElement.src) {
          requestUrl = String(imageElement.src);
        } else if (window && window.location && window.location.href) {
          requestUrl = String(window.location.href);
        }
        if (!requestUrl) {
          throw new Error('photos18 request url missing');
        }
        const xhr = new XMLHttpRequest();
        xhr.open('GET', requestUrl, false);
        xhr.responseType = 'arraybuffer';
        xhr.send(null);
        if (xhr.status >= 400) {
          throw new Error('photos18 xhr failed with status ' + String(xhr.status));
        }
        if (!xhr.response) {
          throw new Error('photos18 xhr returned empty buffer');
        }
        return xhr.response;
      })();
    `;
    return await this.runArrayBufferScript(controller, script, 'photos18');
  }

  private async runArrayBufferScript(
    controller: webview.WebviewController,
    script: string,
    sourceLabel: string
  ): Promise<ArrayBuffer> {
    const jsResult = await controller.runJavaScriptExt(script);
    const resultType = jsResult.getType();
    if (resultType === webview.JsMessageType.ARRAY_BUFFER) {
      return jsResult.getArrayBuffer();
    }
    if (resultType === webview.JsMessageType.STRING) {
      throw new Error(`${sourceLabel} WebView script returned string: ${jsResult.getString()}`);
    }
    const errorDescription = jsResult.getErrorDescription();
    if (errorDescription) {
      throw new Error(errorDescription);
    }
    throw new Error(`${sourceLabel} WebView script returned unsupported type: ${resultType}`);
  }

  private async doHttpRequest(url: string, options: OnlineLoadOptions): Promise<image.PixelMap | null> {
    const cacheKey = this.generateCacheKey(url, options);
    const flowId = options.downloadCacheFlowId && options.downloadCacheFlowId.length > 0
      ? options.downloadCacheFlowId
      : this.ensureImageFlow(url, cacheKey, options);
    options.downloadCacheFlowId = flowId;
    const startTs = Date.now();
    this.recordImageFlowEvent(
      flowId,
      DownloadCacheFlowEventType.HTTP_STARTED,
      DownloadCacheFlowStage.NETWORK,
      'online_image_http_started',
      url,
      cacheKey,
      options,
      true,
      '',
      0,
      0
    );
    try {
      const httpRequest = http.createHttp();
      
      // 构建请求头
      const headers = await this.buildHeaders(url, options);
      if (options.legadoImageTrace !== undefined) {
        await LegadoImageTransportTrace.recordRequest(
          options.legadoImageTrace,
          this.getRequestHeaderNames(headers),
          headers.userAgent || ''
        );
      }
      
      logger.debug(TAG, `发起HTTP请求: url=${url}, timeout=${this.TIMEOUT}`);
      
      const requestOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: this.TIMEOUT,
        readTimeout: this.TIMEOUT,
        header: this.createRequestHeadersObject(headers) as Object,
        expectDataType: http.HttpDataType.ARRAY_BUFFER
      };
      
      // 发送请求
      const response = await httpRequest.request(url, requestOptions);
      const responseContentType: string = this.getResponseContentType(response.header);
      
      if (response.responseCode === 200 && response.result) {
        const duration = Date.now() - startTs;
        const imageBuffer = response.result as ArrayBuffer;
        const bytesLen = imageBuffer.byteLength;
        if (options.legadoImageTrace !== undefined) {
          LegadoImageTransportTrace.recordHttpResponse(
            options.legadoImageTrace,
            Number(response.responseCode),
            responseContentType,
            bytesLen
          );
        }
        
        logger.info(TAG, `HTTP响应成功: code=200, bytes=${bytesLen}, duration=${duration}ms`);
        this.recordImageFlowEvent(
          flowId,
          DownloadCacheFlowEventType.HTTP_COMPLETED,
          DownloadCacheFlowStage.NETWORK,
          'online_image_http_completed',
          url,
          cacheKey,
          options,
          true,
          '',
          duration,
          bytesLen
        );
        
        // 检查是否需要解扰/解密
        let finalBuffer = imageBuffer;
        const processStart = Date.now();
        this.recordImageFlowEvent(
          flowId,
          DownloadCacheFlowEventType.IMAGE_PROCESS_STARTED,
          DownloadCacheFlowStage.IMAGE_PROCESS,
          'online_image_process_started',
          url,
          cacheKey,
          options,
          true,
          '',
          0,
          bytesLen
        );
        try {
        
          // 禁漫天堂图片解扰（检查URL是否包含media/photos）
          if (url.includes('media/photos')) {
            const imageInfo = JinmantiantangDescrambler.extractImageInfo(url);
            if (imageInfo !== null) {
              const descrambler = getJinmantiantangDescrambler();
              const params: JinmantiantangParameters = {
                aid: imageInfo.aid,
                imgIndex: imageInfo.imgIndex
              };
              
              // 检查是否需要解扰（aid >= 220980）
              if (descrambler.shouldDescramble(url, params)) {
                logger.info(TAG, `检测到禁漫天堂加扰图片，开始解扰: aid=${imageInfo.aid}, imgIndex=${imageInfo.imgIndex}`);
                try {
                  finalBuffer = await descrambler.descramble(imageBuffer, params);
                  logger.info(TAG, `禁漫天堂图片解扰完成，原始大小: ${imageBuffer.byteLength}, 解扰后: ${finalBuffer.byteLength}`);
                } catch (descrambleError) {
                  const errMsg = descrambleError instanceof Error ? descrambleError.message : String(descrambleError);
                  logger.error(TAG, `禁漫天堂图片解扰失败: ${errMsg}`);
                  // 解扰失败时使用原始图片
                  finalBuffer = imageBuffer;
                }
              }
            }
          }
          
          // Manwa图片AES解密
          if (url.endsWith('?v=20220724')) {
            logger.debug(TAG, `检测到加密图片，开始AES解密: ${url.substring(0, 80)}`);
            try {
              // 记录原始数据的前16字节（加密头）
              const encryptedView = new Uint8Array(imageBuffer);
              const encHeader = Array.from(encryptedView.slice(0, 16)).map(b => b.toString(16).padStart(2, '0')).join(' ');
              logger.debug(TAG, `加密数据头(hex): ${encHeader}`);
              
              finalBuffer = await this.decryptManwaImage(imageBuffer);
              
              // 记录解密后的前16字节（应该是WEBP文件头: RIFF....WEBP）
              const decryptedView = new Uint8Array(finalBuffer);
              const decHeader = Array.from(decryptedView.slice(0, 16)).map(b => b.toString(16).padStart(2, '0')).join(' ');
              logger.debug(TAG, `解密数据头(hex): ${decHeader}`);
              
              // 检查是否是有效的WEBP文件（RIFF开头）
              const isValidWebP = decryptedView[0] === 0x52 && decryptedView[1] === 0x49 && 
                                 decryptedView[2] === 0x46 && decryptedView[3] === 0x46;
              logger.debug(TAG, `AES解密完成，解密后大小: ${finalBuffer.byteLength}, 是否有效WEBP: ${isValidWebP}`);
              
              if (!isValidWebP) {
                logger.warn(TAG, `解密后的数据不是有效的WEBP格式！前4字节: ${decHeader.substring(0, 11)}`);
              }
            } catch (decryptError) {
              logger.error(TAG, `AES解密失败: ${decryptError}`);
              throw new Error(`图片解密失败: ${decryptError}`);
            }
          }
          
          // 创建PixelMap
          const pixelMap = await this.createPixelMapFromBuffer(finalBuffer, options);
          if (options.legadoImageTrace !== undefined) {
            LegadoImageTransportTrace.recordDecode(
              options.legadoImageTrace,
              pixelMap !== null,
              finalBuffer.byteLength
            );
          }
          this.recordImageFlowEvent(
            flowId,
            DownloadCacheFlowEventType.IMAGE_PROCESS_COMPLETED,
            DownloadCacheFlowStage.IMAGE_PROCESS,
            'online_image_process_completed',
            url,
            cacheKey,
            options,
            pixelMap !== null,
            pixelMap === null ? 'pixel_map_empty' : '',
            Date.now() - processStart,
            finalBuffer.byteLength
          );
        /*
        let pixelMap: image.PixelMap | null = null;
        
        // 检查是否为AVIF格式，使用专用解码器
        if (isAvifFormat(finalBuffer)) {
          logger.info(TAG, `检测到AVIF格式图片，使用AVIF解码器`);
          const avifDecoder = AvifDecoder.getInstance();
          if (avifDecoder.isSupported()) {
            pixelMap = await avifDecoder.decode(finalBuffer);
            if (pixelMap) {
              logger.info(TAG, `AVIF解码成功`);
            } else {
              logger.warn(TAG, `AVIF解码失败，尝试系统解码器`);
            }
          } else {
            logger.warn(TAG, `AVIF解码器不可用（libavif未安装），尝试系统解码器`);
          }
        }
        
        // 如果AVIF解码失败或不是AVIF格式，使用系统解码器
        if (!pixelMap) {
          const imageSource = image.createImageSource(finalBuffer);
          const decodingOptions: image.DecodingOptions = {
            desiredSize: options.width && options.height ? 
              { width: options.width, height: options.height } : undefined,
            desiredPixelFormat: image.PixelMapFormat.RGBA_8888
          };
          
          pixelMap = await imageSource.createPixelMap(decodingOptions);
        }
        
        */
          httpRequest.destroy();
          return pixelMap;
        } catch (processError) {
          const processMessage = processError instanceof Error ? processError.message : String(processError);
          if (options.legadoImageTrace !== undefined) {
            LegadoImageTransportTrace.recordDecode(
              options.legadoImageTrace,
              false,
              finalBuffer.byteLength
            );
          }
          this.recordImageFlowEvent(
            flowId,
            DownloadCacheFlowEventType.IMAGE_PROCESS_FAILED,
            DownloadCacheFlowStage.IMAGE_PROCESS,
            'online_image_process_failed',
            url,
            cacheKey,
            options,
            false,
            processMessage,
            Date.now() - processStart,
            finalBuffer.byteLength
          );
          throw processError instanceof Error ? processError : new Error(String(processError));
        }
        
      } else {
        const duration = Date.now() - startTs;
        if (options.legadoImageTrace !== undefined) {
          LegadoImageTransportTrace.recordHttpResponse(
            options.legadoImageTrace,
            Number(response.responseCode),
            responseContentType,
            0
          );
        }
        logger.warn(TAG, `HTTP响应失败: code=${response.responseCode}, duration=${duration}ms`);
        throw new Error(`HTTP请求失败: ${response.responseCode}`);
      }
      
    } catch (error) {
      // 【修复】详细记录错误信息，包括错误码和完整URL
      // HarmonyOS的BusinessError对象包含code和message属性
      let errMsg = '';
      if (error instanceof Error) {
        errMsg = error.message;
      } else if (typeof error === 'object' && error !== null) {
        // 尝试提取message，如果是对象则序列化
        const msg = (error as Record<string, Object>)['message'];
        if (typeof msg === 'object') {
          try {
            errMsg = JSON.stringify(error as Object);
          } catch (e) {
            errMsg = String(error);
          }
        } else {
          errMsg = String(msg || error);
        }
      } else {
        errMsg = String(error);
      }

      const errCode = (error as Record<string, Object>)['code'];
      const errData = (error as Record<string, Object>)['data'];

      const transportFailure: NetworkTransportFailureDescriptor = this.transportFailureCoordinator.recordFailure(
        url,
        errMsg,
        String(errCode)
      );
      const reportedErrorMessage: string = transportFailure.recognized
        ? transportFailure.canonicalMessage
        : `${errMsg} (code=${String(errCode)})`;
      if (options.legadoImageTrace !== undefined) {
        LegadoImageTransportTrace.recordTransportFailure(options.legadoImageTrace, reportedErrorMessage);
      }

      if (transportFailure.recognized) {
        if (this.transportFailureCoordinator.claimDiagnosticError(transportFailure.fingerprint)) {
          logger.error(TAG, `HTTP传输失败: ${transportFailure.canonicalMessage}`);
        } else {
          logger.warn(TAG, `HTTP传输失败（重复根因）: ${transportFailure.canonicalMessage}`);
        }
      } else {
        logger.error(TAG, `HTTP请求异常: message=${errMsg}, code=${errCode}, data=${errData}, url=${url}`);
      }
      this.recordImageFlowEvent(
        flowId,
        DownloadCacheFlowEventType.HTTP_FAILED,
        DownloadCacheFlowStage.NETWORK,
        'online_image_http_failed',
        url,
        cacheKey,
        options,
        false,
        reportedErrorMessage,
        Date.now() - startTs,
        0
      );
      
      // 重新抛出错误
      throw new Error(reportedErrorMessage);
    }
  }

  /**
   * 构建请求头
   */
  private async createPixelMapFromBuffer(buffer: ArrayBuffer, options: OnlineLoadOptions): Promise<image.PixelMap | null> {
    let pixelMap: image.PixelMap | null = null;

    if (isAvifFormat(buffer)) {
      logger.info(TAG, '妫€娴嬪埌AVIF鏍煎紡鍥剧墖锛屼娇鐢ˋVIF瑙ｇ爜鍣?');
      const avifDecoder = AvifDecoder.getInstance();
      if (avifDecoder.isSupported()) {
        pixelMap = await avifDecoder.decode(buffer);
        if (pixelMap) {
          logger.info(TAG, 'AVIF瑙ｇ爜鎴愬姛');
        } else {
          logger.warn(TAG, 'AVIF瑙ｇ爜澶辫触锛屽皾璇曠郴缁熻В鐮佸櫒');
        }
      } else {
        logger.warn(TAG, 'AVIF瑙ｇ爜鍣ㄤ笉鍙敤锛坙ibavif鏈畨瑁咃級锛屽皾璇曠郴缁熻В鐮佸櫒');
      }
    }

    if (!pixelMap) {
      const imageSource = image.createImageSource(buffer);
      const decodingOptions: image.DecodingOptions = {
        desiredSize: options.width && options.height ?
          { width: options.width, height: options.height } : undefined,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888
      };
      pixelMap = await imageSource.createPixelMap(decodingOptions);
    }

    return pixelMap;
  }

  private getRequestHeaderNames(headers: HttpHeadersObject): string[] {
    const names: string[] = [];
    if (headers.userAgent) names.push('User-Agent');
    if (headers.origin) names.push('Origin');
    if (headers.accept) names.push('Accept');
    if (headers.referer) names.push('Referer');
    if (headers.cookie) names.push('Cookie');
    if (headers.authorization) names.push('Authorization');
    if (headers.acceptLanguage) names.push('Accept-Language');
    if (headers.cacheControl) names.push('Cache-Control');
    if (headers.pragma) names.push('Pragma');
    if (headers.secFetchDest) names.push('Sec-Fetch-Dest');
    if (headers.secFetchMode) names.push('Sec-Fetch-Mode');
    if (headers.secFetchSite) names.push('Sec-Fetch-Site');
    const extraHeaders: RequestHeaderEntry[] | undefined = headers.extraHeaders;
    if (extraHeaders !== undefined) {
      for (let index: number = 0; index < extraHeaders.length; index++) {
        if (extraHeaders[index].name.length > 0 && extraHeaders[index].value.length > 0) {
          names.push(extraHeaders[index].name);
        }
      }
    }
    return names;
  }

  private getResponseContentType(headers: Object): string {
    const entries: [string, Object][] = Object.entries(headers) as [string, Object][];
    for (let index: number = 0; index < entries.length; index++) {
      const name: string = entries[index][0].trim().toLowerCase();
      if (name === 'content-type' || name === 'contenttype') {
        return String(entries[index][1]);
      }
    }
    return '';
  }

  private createRequestHeadersObject(headers: HttpHeadersObject): Record<string, string> {
    const requestHeaders: Record<string, string> = {} as Record<string, string>;
    const standardHeaders: Array<[string, string | undefined]> = [
      ['User-Agent', headers.userAgent],
      ['Origin', headers.origin],
      ['Accept', headers.accept],
      ['Referer', headers.referer],
      ['Cookie', headers.cookie],
      ['Authorization', headers.authorization],
      ['Accept-Language', headers.acceptLanguage],
      ['Cache-Control', headers.cacheControl],
      ['Pragma', headers.pragma],
      ['Sec-Fetch-Dest', headers.secFetchDest],
      ['Sec-Fetch-Mode', headers.secFetchMode],
      ['Sec-Fetch-Site', headers.secFetchSite]
    ];
    let index = 0;
    while (index < standardHeaders.length) {
      const headerEntry = standardHeaders[index];
      const headerKey = headerEntry[0];
      const headerValue = headerEntry[1];
      if (headerValue && headerValue.length > 0) {
        requestHeaders[headerKey] = headerValue;
      }
      index = index + 1;
    }
    const extraHeaders = this.cloneHeaderEntries(headers.extraHeaders);
    if (extraHeaders) {
      let extraIndex = 0;
      while (extraIndex < extraHeaders.length) {
        const extraHeader = extraHeaders[extraIndex];
        if (extraHeader.name.length > 0 && extraHeader.value.length > 0) {
          requestHeaders[extraHeader.name] = extraHeader.value;
        }
        extraIndex = extraIndex + 1;
      }
    }
    return requestHeaders;
  }

  private async buildHeaders(url: string, options: OnlineLoadOptions): Promise<HttpHeadersObject> {
    await this.getDiskCacheForRequest(options);

    const defaultUa = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
    const dogeMangaUa = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
    const defaultAccept = 'image/avif,image/webp,image/png,image/jpeg;q=0.9,*/*;q=0.5';
    const defaultLang = 'zh-CN,zh;q=0.9,en-US;q=0.8,en;q=0.7';
    const isDogeMangaImage = this.isDogeMangaImageRequest(url);
    
    // 优先使用传入的UA，否则通过UserAgentManager获取（支持图源级别和全局设置）
    let ua = options.headers?.userAgent || '';
    if (!ua && options.sourceId) {
      ua = await UserAgentManager.getInstance().getUserAgent(options.sourceId);
      logger.info(TAG, `通过UserAgentManager获取UA: sourceId=${options.sourceId}, ua=${ua.substring(0, 50)}...`);
    }
    if (isDogeMangaImage && (!ua || ua.includes('Chrome/142.0.0.0'))) {
      ua = dogeMangaUa;
      logger.debug(TAG, '为漫画狗图片使用站点兼容UA');
    }
    if (!ua) {
      ua = defaultUa;
      logger.debug(TAG, `使用默认UA`);
    }
    const accept = options.headers?.accept || defaultAccept;
    let referer = options.headers?.referer || '';
    let origin = options.headers?.origin || '';
    
    // 自动为特定CDN添加Referer（解决防盗链和SSL问题）
    if (!referer && (url.includes('amh1234.wszwhg.net') || url.includes('gmh1234.wszwhg.net'))) {
      referer = 'https://b.amh1234.com/';
      origin = 'https://b.amh1234.com';
    }

    // Pixiv CDN防盗链：i.pximg.net 必须携带 Referer
    if (url.includes('i.pximg.net') || url.includes('.pximg.net')) {
      if (!referer) {
        referer = 'https://www.pixiv.net/';
      }
      if (!origin) {
        origin = 'https://www.pixiv.net';
      }
    }

    if (isDogeMangaImage) {
      if (!referer) {
        referer = 'https://dogemanga.com/';
      }
      if (!origin) {
        origin = 'https://dogemanga.com';
      }
    }
    const normalizedOrigin = this.normalizeOriginValue(origin, referer);
    
    // 获取Cookie
    let cookie = options.headers?.cookie || '';
    if (options.sourceId && this.isPhotos18Request(options, url)) {
      cookie = await this.getCachedCookie(options.sourceId, url);
    } else if (!cookie && options.sourceId) {
      cookie = await this.getCachedCookie(options.sourceId);
    }
    
    const authorization = options.headers?.authorization || '';
    const acceptLanguage = options.headers?.acceptLanguage || defaultLang;
    const cacheControl = options.headers?.cacheControl || '';
    const pragma = options.headers?.pragma || '';
    const secFetchDest = options.headers?.secFetchDest || 'image';
    const secFetchMode = options.headers?.secFetchMode || 'no-cors';
    
    const secFetchSite = this.resolveSecFetchSiteValue(url, referer, options.headers?.secFetchSite);
    
    const headerObj: HttpHeadersObject = {
      userAgent: ua,
      origin: normalizedOrigin || undefined,
      accept: accept,
      referer: referer || undefined,
      cookie: cookie || undefined,
      authorization: authorization || undefined,
      acceptLanguage: acceptLanguage || undefined,
      cacheControl: cacheControl || undefined,
      pragma: pragma || undefined,
      secFetchDest: secFetchDest || undefined,
      secFetchMode: secFetchMode || undefined,
      secFetchSite: secFetchSite || undefined,
      extraHeaders: this.cloneHeaderEntries(options.headers?.extraHeaders)
    };
    
    return headerObj;
  }

  private cloneHeaderEntries(entries?: RequestHeaderEntry[]): RequestHeaderEntry[] | undefined {
    if (!entries || entries.length === 0) {
      return undefined;
    }
    const result: RequestHeaderEntry[] = [];
    let index = 0;
    while (index < entries.length) {
      const entry = entries[index];
      if (entry && entry.name && entry.value) {
        result.push({
          name: String(entry.name),
          value: String(entry.value)
        } as RequestHeaderEntry);
      }
      index = index + 1;
    }
    return result.length > 0 ? result : undefined;
  }

  /**
   * 获取缓存的Cookie
   */
  private async getCachedCookie(sourceId: number, url?: string): Promise<string> {
    if (url && url.includes('photos18.com')) {
      try {
        return await CookieManager.getInstance().getCookieStringForUrl(sourceId, url);
      } catch (error) {
        logger.warn(TAG, `按URL获取在线图片Cookie失败，回退普通缓存: sourceId=${sourceId}, error=${String(error)}`);
      }
    }

    const now = Date.now();
    const cached = this.cookieCache.get(sourceId);
    
    if (cached && (now - cached.timestamp) < this.COOKIE_CACHE_TTL) {
      return cached.cookie;
    }
    
    // 从数据库获取
    try {
      const cookieManager = CookieManager.getInstance();
      const cookie = await cookieManager.getCookieString(sourceId);
      if (cookie) {
        const entry: CookieCacheEntry = { cookie: cookie, timestamp: now };
        this.cookieCache.set(sourceId, entry);
        return cookie;
      }
    } catch (error) {
      const errMsg = error instanceof Error ? error.message : String(error);
      logger.warn(TAG, `获取Cookie失败: sourceId=${sourceId}, error=${errMsg}`);
    }
    
    return '';
  }

  public clearCookieCache(sourceId?: number): void {
    if (sourceId !== undefined) {
      this.cookieCache.delete(sourceId);
      logger.debug(TAG, `清除在线图片Cookie缓存: sourceId=${sourceId}`);
      return;
    }
    this.cookieCache.clear();
    logger.debug(TAG, '清除全部在线图片Cookie缓存');
  }

  /**
   * 提取主机名
   */
  private extractHost(url: string): string {
    try {
      const match = url.match(/^https?:\/\/([^\/]+)/);
      if (match && match.length > 1) {
        return match[1];
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  private extractOrigin(url: string): string {
    try {
      const match = url.match(/^(https?:\/\/[^\/]+)/);
      if (match && match.length > 1) {
        return match[1];
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  private normalizeOriginValue(origin: string, referer: string): string {
    const trimmedOrigin = origin.trim();
    if (trimmedOrigin.length > 0) {
      const normalizedOrigin = this.extractOrigin(trimmedOrigin);
      if (normalizedOrigin.length > 0) {
        return normalizedOrigin;
      }
    }
    const trimmedReferer = referer.trim();
    if (trimmedReferer.length > 0) {
      return this.extractOrigin(trimmedReferer);
    }
    return '';
  }

  private detectSecFetchSite(url: string, referer: string): string {
    const refererHost = this.extractHost(referer);
    const urlHost = this.extractHost(url);
    if (refererHost.length === 0 || urlHost.length === 0) {
      return 'same-origin';
    }
    return urlHost === refererHost ? 'same-origin' : 'cross-site';
  }

  private resolveSecFetchSiteValue(url: string, referer: string, provided?: string): string {
    const detectedValue = this.detectSecFetchSite(url, referer);
    if (!provided || provided.trim().length === 0) {
      return detectedValue;
    }
    const trimmedValue = provided.trim();
    if ((trimmedValue === 'same-origin' || trimmedValue === 'cross-site') && trimmedValue !== detectedValue) {
      logger.debug(TAG, `修正Sec-Fetch-Site: provided=${trimmedValue}, detected=${detectedValue}`);
      return detectedValue;
    }
    return trimmedValue;
  }

  /**
   * 等待请求间隔
   */
  private async waitForInterval(): Promise<void> {
    const now = Date.now();
    const elapsed = now - this.lastRequestTime;
    
    if (elapsed < this.MIN_REQUEST_INTERVAL) {
      const waitTime = this.MIN_REQUEST_INTERVAL - elapsed;
      await new Promise<void>(resolve => setTimeout(resolve, waitTime));
    }
    
    this.lastRequestTime = Date.now();
  }

  /**
   * 队列排序（按优先级降序）
   */
  private async delay(ms: number): Promise<void> {
    await new Promise<void>((resolve) => {
      setTimeout(() => {
        resolve();
      }, ms);
    });
  }

  private sortQueue(): void {
    this.requestQueue.sort((a, b) => b.priority - a.priority);
  }

  /**
   * 生成缓存键
   */
  private generateCacheKey(url: string, options?: OnlineLoadOptions): string {
    let base = url;
    if (options?.partitionKey && options.partitionKey.length > 0) {
      base = `${base}#p=${options.partitionKey}`;
    }
    if (options?.headers?.cachePartition && options.headers.cachePartition.length > 0) {
      base = `${base}#hp=${options.headers.cachePartition}`;
    }
    if (options?.headers?.referer && options.headers.referer.length > 0) {
      base = `${base}#r=${options.headers.referer}`;
    }
    if (options?.headers?.extraHeaders && options.headers.extraHeaders.length > 0) {
      base = `${base}#xh=${JSON.stringify(options.headers.extraHeaders)}`;
    }
    // 使用URL的hash作为缓存键
    let hash = 0;
    for (let i = 0; i < base.length; i++) {
      const char = base.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash;
    }
    return `online_${Math.abs(hash).toString(36)}`;
  }


  /**
   * 从缓存获取
   */
  private getFromCache(cacheKey: string): image.PixelMap | null {
    const entry = this.memoryCache.get(cacheKey);
    if (entry) {
      // 更新时间戳
      entry.timestamp = Date.now();
      try {
        // 缓存只持有自己的 PixelMap，返回给调用方时必须克隆。
        // 否则 LRU 淘汰释放缓存对象时，会把阅读器正在显示的同一个 PixelMap 释放掉。
        return entry.pixelMap.cloneSync();
      } catch (error) {
        const message: string = error instanceof Error ? error.message : String(error);
        this.memoryCache.delete(cacheKey);
        this.memoryCacheSize = Math.max(0, this.memoryCacheSize - entry.size);
        try {
          entry.pixelMap.release();
        } catch (_releaseError) {}
        logger.warn(TAG, `内存缓存PixelMap克隆失败，已移除缓存: key=${cacheKey}, error=${message}`);
      }
    }
    return null;
  }

  /**
   * 存入缓存
   */
  private async putToCache(cacheKey: string, pixelMap: image.PixelMap): Promise<void> {
    try {
      let cachePixelMap: image.PixelMap;
      try {
        cachePixelMap = pixelMap.cloneSync();
      } catch (cloneError) {
        const message: string = cloneError instanceof Error ? cloneError.message : String(cloneError);
        logger.warn(TAG, `缓存PixelMap克隆失败，跳过内存缓存: key=${cacheKey}, error=${message}`);
        return;
      }

      const size = await this.calculatePixelMapSize(cachePixelMap);
      
      // 检查是否需要清理
      this.evictCacheIfNeeded(size);

      const oldEntry = this.memoryCache.get(cacheKey);
      if (oldEntry) {
        this.memoryCacheSize = Math.max(0, this.memoryCacheSize - oldEntry.size);
        this.memoryCache.delete(cacheKey);
        try {
          oldEntry.pixelMap.release();
        } catch (_releaseError) {}
      }
      
      const entry: CacheEntry = {
        pixelMap: cachePixelMap,
        size,
        timestamp: Date.now()
      };
      
      this.memoryCache.set(cacheKey, entry);
      this.memoryCacheSize += size;
      
      logger.debug(TAG, `存入缓存: key=${cacheKey}, size=${size}, total=${this.memoryCacheSize}`);
      
    } catch (error) {
      logger.error(TAG, `存入缓存失败: ${String(error)}`);
    }
  }

  /**
   * 计算PixelMap大小
   */
  private async calculatePixelMapSize(pixelMap: image.PixelMap): Promise<number> {
    try {
      const imageInfo = await pixelMap.getImageInfo();
      return imageInfo.size.width * imageInfo.size.height * 4;  // RGBA
    } catch (e) {
      return 1024 * 1024;  // 默认1MB
    }
  }

  /**
   * 缓存淘汰
   */
  private evictCacheIfNeeded(newSize: number): void {
    // 检查大小和数量限制
    while (
      (this.memoryCacheSize + newSize > this.MAX_CACHE_SIZE) ||
      (this.memoryCache.size >= this.MAX_CACHE_COUNT)
    ) {
      if (this.memoryCache.size === 0) break;
      
      // LRU淘汰：找到最旧的条目
      let oldestKey: string | null = null;
      let oldestTime = Date.now();
      
      const entries = this.memoryCache.entries();
      let result = entries.next();
      while (!result.done) {
        const key = result.value[0];
        const entry = result.value[1];
        if (entry.timestamp < oldestTime) {
          oldestTime = entry.timestamp;
          oldestKey = key;
        }
        result = entries.next();
      }
      
      if (oldestKey) {
        const entry = this.memoryCache.get(oldestKey);
        if (entry) {
          this.memoryCacheSize -= entry.size;
          this.memoryCache.delete(oldestKey);
          try {
            entry.pixelMap.release();
          } catch (_e) {}
          logger.debug(TAG, `淘汰缓存: key=${oldestKey}, size=${entry.size}`);
        }
      } else {
        break;
      }
    }
  }

  /**
   * 清空缓存
   */
  public clearCache(): void {
    this.memoryCache.forEach((entry) => {
      try {
        entry.pixelMap.release();
      } catch (_e) {}
    });
    this.memoryCache.clear();
    this.memoryCacheSize = 0;
    logger.info(TAG, '缓存已清空');
  }

  /**
   * 获取缓存统计
   */
  public getCacheStats(): CacheStatsInfo {
    const stats: CacheStatsInfo = {
      count: this.memoryCache.size,
      size: this.memoryCacheSize,
      queueSize: this.requestQueue.length,
      activeRequests: this.activeRequests
    };
    return stats;
  }

  /**
   * 取消所有待处理请求
   */
  public cancelAll(): void {
    const count = this.requestQueue.length;
    this.requestQueue.forEach(req => {
      req.reject(new Error('Request cancelled'));
    });
    this.requestQueue = [];
    logger.info(TAG, `已取消 ${count} 个待处理请求`);
  }

  /**
   * 解密 Manwa 加密图片
   * 使用 AES-CBC 解密，密钥和IV都是 "my2ecret782ecret"
   */
  private async decryptManwaImage(encryptedBuffer: ArrayBuffer): Promise<ArrayBuffer> {
    const keyStr = 'my2ecret782ecret';
    const keyData = this.stringToUint8Array(keyStr);
    
    // 创建对称密钥生成器
    const symKeyGenerator = cryptoFramework.createSymKeyGenerator('AES128');
    const keyBlob: cryptoFramework.DataBlob = { data: keyData };
    const symKey = await symKeyGenerator.convertKey(keyBlob);
    
    // 创建解密器 AES-CBC-NoPadding
    const cipher = cryptoFramework.createCipher('AES128|CBC|NoPadding');
    
    // 初始化解密器，IV 同密钥
    const ivBlob: cryptoFramework.DataBlob = { data: keyData };
    const params: cryptoFramework.IvParamsSpec = {
      algName: 'IvParamsSpec',
      iv: ivBlob
    };
    await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, params);
    
    // 执行解密
    const encryptedData: cryptoFramework.DataBlob = { data: new Uint8Array(encryptedBuffer) };
    const decryptedBlob = await cipher.doFinal(encryptedData);
    
    if (!decryptedBlob || !decryptedBlob.data) {
      throw new Error('解密结果为空');
    }
    
    // 【修复】正确复制解密数据到新的 ArrayBuffer
    // Uint8Array.buffer 可能包含额外的偏移量，需要创建精确大小的新 buffer
    const decryptedData = decryptedBlob.data;
    const resultBuffer = new ArrayBuffer(decryptedData.length);
    const resultView = new Uint8Array(resultBuffer);
    resultView.set(decryptedData);
    
    return resultBuffer;
  }

  /**
   * 字符串转 Uint8Array
   */
  private stringToUint8Array(str: string): Uint8Array {
    const arr = new Uint8Array(str.length);
    for (let i = 0; i < str.length; i++) {
      arr[i] = str.charCodeAt(i);
    }
    return arr;
  }
}
