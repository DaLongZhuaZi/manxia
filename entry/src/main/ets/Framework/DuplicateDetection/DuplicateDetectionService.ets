/**
 * 内容重复检测服务
 * 单例模式，在内容添加到书库前检测是否已存在相似内容
 */

import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { DataManager } from '../Data/DataManager';
import { EBookDataManager } from 'manxia_core/src/main/ets/Framework/Data/EBookDataManager';
import { NovelDataManager } from '../Novel/NovelDataManager';
import { SettingsManager } from 'manxia_core/src/main/ets/Framework/Managers/SettingsManager';
import { normalizeText, combinedSimilarity } from './StringSimilarity';
import {
  DuplicateCheckInput,
  DuplicateCheckContentType,
  DuplicateCheckScope,
  DuplicateCandidateItem,
  DuplicateMatchItem,
  DuplicateCheckResult,
  DuplicateDetectionConfig,
  DEFAULT_DUPLICATE_DETECTION_CONFIG
} from './DuplicateDetectionModels';

const TAG = 'DuplicateDetection';

export class DuplicateDetectionService {
  private static instance: DuplicateDetectionService | null = null;

  private constructor() {
  }

  public static getInstance(): DuplicateDetectionService {
    if (DuplicateDetectionService.instance === null) {
      DuplicateDetectionService.instance = new DuplicateDetectionService();
    }
    return DuplicateDetectionService.instance;
  }

  public static destroyInstance(): void {
    DuplicateDetectionService.instance = null;
  }

  /**
   * 主入口：检测是否有重复内容
   */
  public async checkDuplicates(input: DuplicateCheckInput): Promise<DuplicateCheckResult> {
    const config = await this.loadConfig();

    logger.info(TAG, `checkDuplicates: enabled=${config.enabled}, threshold=${config.threshold}, scope=${config.checkScope}, titleWeight=${config.titleWeight}`);

    if (!config.enabled) {
      logger.info(TAG, '重复检测已关闭，跳过检测');
      return { hasDuplicates: false, matches: [], checkedCount: 0 };
    }

    const candidates = await this.getCandidates(input, config);
    // 排除自身：如果候选的ID与输入的externalId匹配，跳过
    const filteredCandidates = candidates.filter((candidate: DuplicateCandidateItem) => {
      if (input.externalId && candidate.id === input.externalId) {
        logger.debug(TAG, `排除自身候选: id=${candidate.id}, title="${candidate.title}"`);
        return false;
      }
      if (input.sourceId && candidate.sourceName === input.sourceId) {
        // 同源且标题完全相同的也排除（可能是同一内容的不同缓存记录）
        const normalizedInputTitle = normalizeText(input.title);
        const normalizedCandidateTitle = normalizeText(candidate.title);
        if (normalizedInputTitle === normalizedCandidateTitle && normalizedInputTitle.length > 0) {
          logger.debug(TAG, `排除同源同标题候选: sourceName=${candidate.sourceName}, title="${candidate.title}"`);
          return false;
        }
      }
      return true;
    });
    logger.debug(TAG, `检查重复: "${input.title}" by "${input.author}", 候选数=${filteredCandidates.length}(过滤前${candidates.length}), 阈值=${config.threshold}`);

    const matches: DuplicateMatchItem[] = [];
    const normalizedInputTitle = normalizeText(input.title);
    const normalizedInputAuthor = normalizeText(input.author);

    for (let i = 0; i < filteredCandidates.length; i++) {
      const candidate = filteredCandidates[i];
      const match = this.calculateMatch(normalizedInputTitle, normalizedInputAuthor, candidate, config);
      if (match.overallSimilarity >= config.threshold) {
        matches.push(match);
      }
    }

    // 按相似度降序排序
    matches.sort((a: DuplicateMatchItem, b: DuplicateMatchItem) => b.overallSimilarity - a.overallSimilarity);

    if (matches.length > 0) {
      logger.info(TAG, `检测到 ${matches.length} 个可能重复: "${input.title}"`);
    }

    return {
      hasDuplicates: matches.length > 0,
      matches: matches,
      checkedCount: candidates.length
    };
  }

  /**
   * 从用户设置加载检测配置
   */
  private async loadConfig(): Promise<DuplicateDetectionConfig> {
    const settingsManager = SettingsManager.getInstance();
    const enabled = await settingsManager.getDuplicateDetectionEnabled();
    const threshold = await settingsManager.getDuplicateDetectionThreshold();
    const scope = await settingsManager.getDuplicateDetectionScope();
    const titleWeight = await settingsManager.getDuplicateDetectionTitleWeight();

    return {
      enabled: enabled,
      threshold: threshold,
      checkScope: scope === 'all_types' ? DuplicateCheckScope.ALL_TYPES : DuplicateCheckScope.SAME_TYPE,
      titleWeight: titleWeight,
      authorWeight: 1.0 - titleWeight
    };
  }

  /**
   * 获取候选内容列表
   */
  private async getCandidates(input: DuplicateCheckInput, config: DuplicateDetectionConfig): Promise<DuplicateCandidateItem[]> {
    const candidates: DuplicateCandidateItem[] = [];
    const typesToCheck = this.getContentTypesToCheck(input.contentType, config.checkScope);

    logger.info(TAG, `getCandidates: 检查类型=[${typesToCheck.join(', ')}], 输入类型=${input.contentType}, 范围=${config.checkScope}`);

    for (let i = 0; i < typesToCheck.length; i++) {
      const contentType = typesToCheck[i];
      const items = await this.getCandidatesForType(contentType);
      candidates.push(...items);
    }

    return candidates;
  }

  /**
   * 根据检测范围决定检查哪些类型
   */
  private getContentTypesToCheck(inputType: DuplicateCheckContentType, scope: DuplicateCheckScope): DuplicateCheckContentType[] {
    if (scope === DuplicateCheckScope.SAME_TYPE) {
      return [inputType];
    }
    // ALL_TYPES: 检查所有三种类型
    return [DuplicateCheckContentType.MANGA, DuplicateCheckContentType.EBOOK, DuplicateCheckContentType.NOVEL];
  }

  /**
   * 从对应 DataManager 查询候选内容
   */
  private async getCandidatesForType(contentType: DuplicateCheckContentType): Promise<DuplicateCandidateItem[]> {
    const candidates: DuplicateCandidateItem[] = [];

    try {
      if (contentType === DuplicateCheckContentType.MANGA) {
        const dataManager = DataManager.getInstance();
        const comics = await dataManager.getNonPrivateComics();
        for (let i = 0; i < comics.length; i++) {
          const comic = comics[i];
          candidates.push({
            id: comic.id,
            title: comic.title,
            author: comic.author,
            coverUrl: comic.coverUrl,
            contentType: DuplicateCheckContentType.MANGA,
            chapterCount: comic.chapterCount,
            sourceName: '',
            isFavorite: true
          });
        }
        // 也检查在线漫画
        const onlineComics = await dataManager.getNonPrivateOnlineComics();
        for (let i = 0; i < onlineComics.length; i++) {
          const comic = onlineComics[i];
          candidates.push({
            id: comic.id,
            title: comic.title,
            author: comic.author,
            coverUrl: comic.coverUrl,
            contentType: DuplicateCheckContentType.MANGA,
            chapterCount: 0,
            sourceName: comic.sourceName,
            isFavorite: true
          });
        }
      } else if (contentType === DuplicateCheckContentType.EBOOK) {
        const ebookManager = EBookDataManager.getInstance();
        const ebooks = await ebookManager.getNonPrivateEBooks();
        for (let i = 0; i < ebooks.length; i++) {
          const ebook = ebooks[i];
          candidates.push({
            id: ebook.id,
            title: ebook.metadata.title,
            author: ebook.metadata.author,
            coverUrl: ebook.metadata.coverImagePath,
            contentType: DuplicateCheckContentType.EBOOK,
            chapterCount: ebook.chapters.length,
            sourceName: ebook.format,
            isFavorite: ebook.isFavorite
          });
        }
      } else if (contentType === DuplicateCheckContentType.NOVEL) {
        const novelManager = NovelDataManager.getInstance();
        const novels = await novelManager.getNonPrivateBooks();
        for (let i = 0; i < novels.length; i++) {
          const novel = novels[i];
          candidates.push({
            id: novel.id,
            title: novel.name,
            author: novel.author,
            coverUrl: novel.coverUrl || '',
            contentType: DuplicateCheckContentType.NOVEL,
            chapterCount: novel.chapterCount,
            sourceName: novel.sourceName,
            isFavorite: novel.isFavorite
          });
        }
      }
    } catch (error) {
      logger.error(TAG, `查询候选内容失败: ${contentType}`, String(error));
    }

    logger.info(TAG, `getCandidatesForType(${contentType}): 返回 ${candidates.length} 个候选`);
    return candidates;
  }

  /**
   * 计算单个候选的匹配度
   */
  private calculateMatch(
    normalizedInputTitle: string,
    normalizedInputAuthor: string,
    candidate: DuplicateCandidateItem,
    config: DuplicateDetectionConfig
  ): DuplicateMatchItem {
    const normalizedCandidateTitle = normalizeText(candidate.title);
    const normalizedCandidateAuthor = normalizeText(candidate.author);

    // 标题相似度：归一化后完全匹配则直接 1.0
    let titleSimilarity: number;
    if (normalizedInputTitle === normalizedCandidateTitle && normalizedInputTitle.length > 0) {
      titleSimilarity = 1.0;
    } else {
      titleSimilarity = combinedSimilarity(normalizedInputTitle, normalizedCandidateTitle);
    }

    // 作者相似度：空作者时视为不参与匹配
    let authorSimilarity: number;
    if (normalizedInputAuthor.length === 0 || normalizedCandidateAuthor.length === 0) {
      authorSimilarity = 0.0;
    } else if (normalizedInputAuthor === normalizedCandidateAuthor) {
      authorSimilarity = 1.0;
    } else {
      authorSimilarity = combinedSimilarity(normalizedInputAuthor, normalizedCandidateAuthor);
    }

    // 加权综合相似度
    let overallSimilarity: number;
    if (normalizedInputAuthor.length === 0 || normalizedCandidateAuthor.length === 0) {
      // 无作者信息时，标题权重为 1.0
      overallSimilarity = titleSimilarity;
    } else {
      overallSimilarity = config.titleWeight * titleSimilarity + config.authorWeight * authorSimilarity;
    }

    return {
      id: candidate.id,
      title: candidate.title,
      author: candidate.author,
      coverUrl: candidate.coverUrl,
      contentType: candidate.contentType,
      titleSimilarity: titleSimilarity,
      authorSimilarity: authorSimilarity,
      overallSimilarity: overallSimilarity,
      chapterCount: candidate.chapterCount,
      sourceName: candidate.sourceName,
      isFavorite: candidate.isFavorite
    };
  }
}
