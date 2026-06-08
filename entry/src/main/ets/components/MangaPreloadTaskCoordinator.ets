// 职责: 预加载任务调度，不接触 UI 渲染和页面数据结构

import { logger } from '../Utils/Logger';
import { ImageLoadStateManager } from './ImageLoadStateManager';
import { PreloadManager, PreloadTaskItem } from './PreloadManager';

const TAG = 'MangaPreloadTaskCoordinator';

export class MangaPreloadRunnableBatch {
  public tasks: PreloadTaskItem[] = [];
  public availableSlots: number = 0;
  public skippedTasks: number = 0;
}

export class MangaPreloadTaskCoordinator {
  public isOnlineContent(contentType: string): boolean {
    return contentType === 'OnlineUndownloaded' || contentType === 'OnlineDownloaded';
  }

  public takeRunnableTasks(
    preloadManager: PreloadManager,
    imageLoadStateManager: ImageLoadStateManager,
    contentType: string
  ): MangaPreloadRunnableBatch {
    const batch: MangaPreloadRunnableBatch = new MangaPreloadRunnableBatch();
    const loadingCount: number = imageLoadStateManager.getLoadingCount();
    const isOnline: boolean = this.isOnlineContent(contentType);
    batch.availableSlots = preloadManager.getAvailableLoadSlots(isOnline, loadingCount);

    if (batch.availableSlots <= 0) {
      return batch;
    }

    const candidates: PreloadTaskItem[] = preloadManager.getNextBatchToLoad(batch.availableSlots);
    for (let i = 0; i < candidates.length; i++) {
      const task: PreloadTaskItem = candidates[i];
      if (imageLoadStateManager.isLoading(task.pageId) ||
        imageLoadStateManager.isCompleted(task.pageId)) {
        preloadManager.clearPage(task.pageIndex);
        batch.skippedTasks++;
        continue;
      }
      batch.tasks.push(task);
    }

    if (batch.skippedTasks > 0) {
      logger.debug(TAG, `跳过已处理预加载任务: count=${batch.skippedTasks}`);
    }
    return batch;
  }

  public markTaskPageMissing(
    preloadManager: PreloadManager,
    imageLoadStateManager: ImageLoadStateManager,
    task: PreloadTaskItem
  ): void {
    preloadManager.clearPage(task.pageIndex);
    imageLoadStateManager.clearPage(task.pageId);
  }

  public markTaskReady(
    imageLoadStateManager: ImageLoadStateManager,
    task: PreloadTaskItem
  ): void {
    imageLoadStateManager.initPage(task.pageId, task.pageIndex);
  }
}
