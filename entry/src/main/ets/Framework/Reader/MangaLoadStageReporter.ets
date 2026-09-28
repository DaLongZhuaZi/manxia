// 职责: 汇聚"图片加载到了哪个阶段"这一事实，供缓存层上报、由界面层订阅。
//
// 为什么需要它：远端图源取页可能耗时几十秒，在此之前界面只有一句固定的"加载中..."，
// 用户无法区分"在排队 / 正在下载 / 正在解码 / 已经失败"，只能盯着空白页。
// 这一层刻意不依赖任何 UI，避免 Framework 反向依赖 components。

/**
 * 图片加载阶段。
 */
export enum MangaLoadStage {
  /** 已进入取图队列，等待并发通道 */
  QUEUED = 'queued',
  /** 正在从服务器下载 */
  DOWNLOADING = 'downloading',
  /** 字节已就绪，正在解码 */
  DECODING = 'decoding',
  /** 可以显示了 */
  READY = 'ready',
  /** 失败，detail 里带原因 */
  FAILED = 'failed'
}

export interface MangaLoadStageEvent {
  /** 页面图片地址，界面按它匹配到具体页面 */
  url: string;
  stage: MangaLoadStage;
  /** 阶段补充说明（失败原因等） */
  detail: string;
  timestamp: number;
}

export type MangaLoadStageListener = (event: MangaLoadStageEvent) => void;

export class MangaLoadStageReporter {
  private static instance: MangaLoadStageReporter | null = null;
  private listeners: MangaLoadStageListener[] = [];

  private constructor() {
  }

  public static getInstance(): MangaLoadStageReporter {
    if (MangaLoadStageReporter.instance === null) {
      MangaLoadStageReporter.instance = new MangaLoadStageReporter();
    }
    return MangaLoadStageReporter.instance;
  }

  public addListener(listener: MangaLoadStageListener): void {
    if (!this.listeners.includes(listener)) {
      this.listeners.push(listener);
    }
  }

  public removeListener(listener: MangaLoadStageListener): void {
    const index: number = this.listeners.indexOf(listener);
    if (index >= 0) {
      this.listeners.splice(index, 1);
    }
  }

  /**
   * 上报一个阶段。任何一次上报失败都不能影响加载本身，因此整体包在 try 里。
   */
  public report(url: string, stage: MangaLoadStage, detail: string = ''): void {
    if (url.length <= 0 || this.listeners.length <= 0) {
      return;
    }
    const event: MangaLoadStageEvent = {
      url: url,
      stage: stage,
      detail: detail,
      timestamp: Date.now()
    };
    const snapshot: MangaLoadStageListener[] = this.listeners.slice();
    for (let index = 0; index < snapshot.length; index++) {
      try {
        snapshot[index](event);
      } catch (_error) {
      }
    }
  }
}

export function getMangaLoadStageReporter(): MangaLoadStageReporter {
  return MangaLoadStageReporter.getInstance();
}
