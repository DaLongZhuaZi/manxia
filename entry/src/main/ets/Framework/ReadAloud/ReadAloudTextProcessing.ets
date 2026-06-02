import { SafeUtils } from '../../Utils/SafeUtils';
import { preferences } from '@kit.ArkData';
import { logger } from '../../Utils/Logger';
import { getNovelContentProcessor, ContentProcessConfig } from '../Novel/NovelContentProcessor';
import { uiContextManager } from '../Managers/UIContextManager';

const TAG = 'ReadAloudTextProcessing';

export const NOVEL_SETTINGS_STORE = 'novel_settings';
export const NOVEL_BOOK_RULE_SETTINGS_STORE = 'novel_book_rule_settings';
export const NOVEL_BOOK_REPLACE_RULE_IDS_PREFIX = 'book_replace_rule_ids_';
export const NOVEL_SETTING_ENABLE_REPLACE_RULES = 'enableNovelReplaceRules';

export interface ReadAloudNovelContentProcessSnapshot {
  useReplace: boolean;
  sourceId: string;
  enabledRuleIds?: string[];
}

function sanitizeRuleIdArray(rawValue: string): string[] {
  if (!rawValue || rawValue.length <= 0) {
    return [];
  }
  try {
    const parsed = SafeUtils.parseArr(rawValue) as Array<string>;
    if (!Array.isArray(parsed)) {
      return [];
    }
    const result: string[] = [];
    for (let index = 0; index < parsed.length; index++) {
      const item = parsed[index];
      if (typeof item === 'string' && item.length > 0) {
        result.push(item);
      }
    }
    return result;
  } catch (error) {
    logger.warn(TAG, `parse scoped replace rule ids failed: ${String(error)}`);
    return [];
  }
}

async function loadScopedReplaceRuleIds(bookId: string): Promise<string[] | undefined> {
  if (!bookId || bookId.length <= 0) {
    return undefined;
  }
  const abilityContext = uiContextManager.getAbilityContext();
  if (!abilityContext) {
    return undefined;
  }
  try {
    const store = await preferences.getPreferences(abilityContext, NOVEL_BOOK_RULE_SETTINGS_STORE);
    const raw = await store.get(`${NOVEL_BOOK_REPLACE_RULE_IDS_PREFIX}${bookId}`, '') as string;
    const parsed = sanitizeRuleIdArray(raw);
    return parsed.length > 0 ? parsed : undefined;
  } catch (error) {
    logger.warn(TAG, `load scoped replace rule ids failed: bookId=${bookId}, error=${String(error)}`);
    return undefined;
  }
}

export async function loadReadAloudNovelContentProcessSnapshot(
  bookId: string,
  sourceId: string
): Promise<ReadAloudNovelContentProcessSnapshot> {
  const abilityContext = uiContextManager.getAbilityContext();
  let useReplace = true;
  if (abilityContext) {
    try {
      const store = await preferences.getPreferences(abilityContext, NOVEL_SETTINGS_STORE);
      useReplace = await store.get(NOVEL_SETTING_ENABLE_REPLACE_RULES, true) as boolean;
    } catch (error) {
      logger.warn(TAG, `load replace rules toggle failed, fallback to enabled: ${String(error)}`);
    }
  }
  const enabledRuleIds = await loadScopedReplaceRuleIds(bookId);
  return {
    useReplace,
    sourceId,
    enabledRuleIds
  };
}

export function buildReadAloudNovelContentProcessConfig(
  snapshot: ReadAloudNovelContentProcessSnapshot
): ContentProcessConfig {
  return {
    useReplace: snapshot.useReplace,
    chineseConvert: 0,
    reSegment: false,
    includeTitle: true,
    paragraphIndent: '',
    sourceId: snapshot.sourceId,
    enabledRuleIds: snapshot.enabledRuleIds
  };
}

export function processReadAloudNovelContent(
  rawContent: string,
  chapterTitle: string,
  bookTitle: string,
  snapshot: ReadAloudNovelContentProcessSnapshot
): string {
  const processor = getNovelContentProcessor();
  return processor.processContent(
    rawContent,
    chapterTitle,
    bookTitle,
    buildReadAloudNovelContentProcessConfig(snapshot)
  ).content;
}

export async function processReadAloudNovelContentByBook(
  rawContent: string,
  chapterTitle: string,
  bookTitle: string,
  sourceId: string,
  bookId: string
): Promise<string> {
  const snapshot = await loadReadAloudNovelContentProcessSnapshot(bookId, sourceId);
  return processReadAloudNovelContent(rawContent, chapterTitle, bookTitle, snapshot);
}
