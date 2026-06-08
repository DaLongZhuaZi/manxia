import { logger } from '../../Utils/Logger';
import { MangaAssetLoader } from './MangaAssetLoader';
import { MangaAssetMonitor, MangaAssetMetricsSnapshot } from './MangaAssetMonitor';
import {
  buildMangaAssetRequestKey,
  MangaAssetLoadRequest,
  MangaAssetLoadResult,
  MangaPixivImageLoader
} from './MangaAssetTypes';

const TAG = 'MangaAssetLoadCoordinator';

export class MangaAssetLoadCoordinator {
  private loader: MangaAssetLoader;
  private monitor: MangaAssetMonitor;
  private activeTasks: Map<string, Promise<MangaAssetLoadResult>> = new Map();
  private generation: number = 0;

  public constructor(loader: MangaAssetLoader, monitor: MangaAssetMonitor) {
    this.loader = loader;
    this.monitor = monitor;
  }

  public setPixivImageLoader(loader: MangaPixivImageLoader | null): void {
    this.loader.setPixivImageLoader(loader);
  }

  public async load(request: MangaAssetLoadRequest): Promise<MangaAssetLoadResult> {
    if (!request.requestKey || request.requestKey.length <= 0) {
      request.requestKey = buildMangaAssetRequestKey(request);
    }

    const existingTask: Promise<MangaAssetLoadResult> | undefined = this.activeTasks.get(request.requestKey);
    if (existingTask) {
      this.monitor.markDeduped(request);
      logger.debug(TAG, `复用进行中的漫画资产加载: key=${request.requestKey}, page=${request.pageId}`);
      return await existingTask;
    }

    this.monitor.markStart(request);
    const taskGeneration: number = this.generation;
    const task: Promise<MangaAssetLoadResult> = this.loader.load(request);
    this.activeTasks.set(request.requestKey, task);

    try {
      const result: MangaAssetLoadResult = await task;
      if (taskGeneration === this.generation) {
        this.monitor.markFinish(request, result);
      }
      return result;
    } finally {
      const activeTask: Promise<MangaAssetLoadResult> | undefined = this.activeTasks.get(request.requestKey);
      if (activeTask === task) {
        this.activeTasks.delete(request.requestKey);
      }
    }
  }

  public getMetricsSnapshot(): MangaAssetMetricsSnapshot {
    return this.monitor.createSnapshot();
  }

  public clearActiveTasks(): void {
    this.generation++;
    this.activeTasks.clear();
  }

  public resetMetrics(): void {
    this.monitor.reset();
  }
}
