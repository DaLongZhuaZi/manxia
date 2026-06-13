import { UnifiedChapter } from '../../Models/UnifiedContentModels';
import { TxtTocRule } from '../Novel/NovelTxtTocRuleManager';

const UNRESOLVED_ORDER_VALUE: number = 9000000;

export interface ChapterRuleSortResult {
  orderedChapters: UnifiedChapter[];
  matchedCount: number;
  movedCount: number;
  unresolvedCount: number;
  message: string;
  appliedRuleName: string;
}

interface ChapterRuleSortEntry {
  chapter: UnifiedChapter;
  originalIndex: number;
  matched: boolean;
  category: number;
  orderValue: number;
  ruleOrder: number;
}

interface ChapterTitleParseResult {
  category: number;
  orderValue: number;
}

interface CompiledTxtTocRule {
  id: string;
  name: string;
  serialNumber: number;
  pattern: RegExp | null;
}

export class ChapterOrderRuleSorter {
  public sortByTxtRules(
    chapters: UnifiedChapter[],
    rules: TxtTocRule[],
    selectedRuleId: string = ''
  ): ChapterRuleSortResult {
    const sourceChapters = this.cloneChapterArray(chapters);
    const emptyResult = this.createResult(sourceChapters, 0, 0, sourceChapters.length, '没有可排序的章节', '');
    if (sourceChapters.length <= 1) {
      return emptyResult;
    }

    const compiledRules = this.compileRules(rules, selectedRuleId);
    if (compiledRules.length === 0) {
      return this.createResult(sourceChapters, 0, 0, sourceChapters.length, '没有可用的TXT章节规则', '');
    }

    const entries: ChapterRuleSortEntry[] = [];
    let matchedCount = 0;
    for (let i = 0; i < sourceChapters.length; i++) {
      const chapter = sourceChapters[i];
      const matchedRule = this.matchRule(chapter.title, compiledRules);
      const parseResult = matchedRule !== null
        ? this.parseChapterTitle(chapter.title)
        : this.createUnresolvedParseResult();
      const matched = matchedRule !== null && parseResult.category !== 2;
      if (matched) {
        matchedCount++;
      }
      const entry: ChapterRuleSortEntry = {
        chapter: chapter,
        originalIndex: i,
        matched: matched,
        category: parseResult.category,
        orderValue: parseResult.orderValue,
        ruleOrder: matchedRule !== null ? matchedRule.serialNumber : UNRESOLVED_ORDER_VALUE
      };
      entries.push(entry);
    }

    if (matchedCount === 0) {
      const appliedRuleName = this.buildAppliedRuleName(compiledRules, selectedRuleId);
      return this.createResult(sourceChapters, 0, 0, sourceChapters.length, 'TXT规则未匹配到可排序章节', appliedRuleName);
    }

    entries.sort((left: ChapterRuleSortEntry, right: ChapterRuleSortEntry) => this.compareEntries(left, right));

    const ordered: UnifiedChapter[] = [];
    for (let i = 0; i < entries.length; i++) {
      ordered.push(entries[i].chapter);
    }
    const movedCount = this.countMoved(sourceChapters, ordered);
    const unresolvedCount = sourceChapters.length - matchedCount;
    const appliedName = this.buildAppliedRuleName(compiledRules, selectedRuleId);
    const message = movedCount > 0
      ? `TXT规则已生成排序草稿，匹配 ${matchedCount} 章，移动 ${movedCount} 章`
      : `TXT规则已匹配 ${matchedCount} 章，章节顺序未变化`;
    return this.createResult(ordered, matchedCount, movedCount, unresolvedCount, message, appliedName);
  }

  private compileRules(rules: TxtTocRule[], selectedRuleId: string): CompiledTxtTocRule[] {
    const result: CompiledTxtTocRule[] = [];
    for (let i = 0; i < rules.length; i++) {
      const rule = rules[i];
      if (!rule.enabled) {
        continue;
      }
      if (selectedRuleId.length > 0 && rule.id !== selectedRuleId) {
        continue;
      }
      const compiled: CompiledTxtTocRule = {
        id: rule.id,
        name: rule.name,
        serialNumber: rule.serialNumber,
        pattern: this.compilePattern(rule.rule)
      };
      if (compiled.pattern !== null) {
        result.push(compiled);
      }
    }
    result.sort((left: CompiledTxtTocRule, right: CompiledTxtTocRule) => left.serialNumber - right.serialNumber);
    return result;
  }

  private compilePattern(ruleText: string): RegExp | null {
    if (ruleText.length === 0) {
      return null;
    }
    try {
      return new RegExp(ruleText, 'm');
    } catch (firstError) {
      try {
        return new RegExp(ruleText);
      } catch (secondError) {
        return null;
      }
    }
  }

  private matchRule(title: string, rules: CompiledTxtTocRule[]): CompiledTxtTocRule | null {
    const safeTitle = title.trim();
    if (safeTitle.length === 0) {
      return null;
    }
    for (let i = 0; i < rules.length; i++) {
      const rule = rules[i];
      const pattern = rule.pattern;
      if (pattern === null) {
        continue;
      }
      pattern.lastIndex = 0;
      if (pattern.test(safeTitle)) {
        return rule;
      }
    }
    return null;
  }

  private parseChapterTitle(title: string): ChapterTitleParseResult {
    const safeTitle = title.trim();
    const prefaceOrder = this.resolvePrefaceOrder(safeTitle);
    if (prefaceOrder >= 0) {
      return {
        category: 0,
        orderValue: prefaceOrder
      };
    }

    const endingOrder = this.resolveEndingOrder(safeTitle);
    if (endingOrder >= 0) {
      return {
        category: 3,
        orderValue: endingOrder
      };
    }

    const numericOrder = this.extractNumericOrder(safeTitle);
    if (numericOrder >= 0) {
      return {
        category: 1,
        orderValue: numericOrder
      };
    }

    return this.createUnresolvedParseResult();
  }

  private createUnresolvedParseResult(): ChapterTitleParseResult {
    return {
      category: 2,
      orderValue: UNRESOLVED_ORDER_VALUE
    };
  }

  private resolvePrefaceOrder(title: string): number {
    const lowerTitle = title.toLowerCase();
    if (title.indexOf('前言') >= 0 || title.indexOf('文案') >= 0 || title.indexOf('简介') >= 0 ||
      title.indexOf('序文') >= 0 || lowerTitle.indexOf('foreword') >= 0 ||
      lowerTitle.indexOf('preface') >= 0 || lowerTitle.indexOf('introduction') >= 0) {
      return 0;
    }
    if (title.indexOf('序章') >= 0 || title.indexOf('序幕') >= 0 || title.indexOf('序') === 0 ||
      title.indexOf('プロローグ') >= 0 || title.indexOf('프롤로그') >= 0 ||
      lowerTitle.indexOf('prologue') >= 0 || lowerTitle === 'intro') {
      return 1;
    }
    if (title.indexOf('楔子') >= 0 || title.indexOf('引子') >= 0 ||
      lowerTitle.indexOf('interlude') >= 0) {
      return 2;
    }
    if (title.indexOf('正文') >= 0) {
      return 3;
    }
    if (title.indexOf('封面') >= 0 || title.indexOf('表紙') >= 0 || title.indexOf('カバー') >= 0 ||
      title.indexOf('커버') >= 0 || lowerTitle.indexOf('cover') >= 0) {
      return 4;
    }
    if (title.indexOf('预览') >= 0 || title.indexOf('預覽') >= 0 || title.indexOf('プレビュー') >= 0 ||
      title.indexOf('미리보기') >= 0 || lowerTitle.indexOf('preview') >= 0 ||
      lowerTitle.indexOf('teaser') >= 0 || lowerTitle.indexOf('trailer') >= 0) {
      return 5;
    }
    return -1;
  }

  private resolveEndingOrder(title: string): number {
    const lowerTitle = title.toLowerCase();
    if (title.indexOf('终章') >= 0 || title.indexOf('終章') >= 0 ||
      title.indexOf('最终话') >= 0 || title.indexOf('最終話') >= 0 ||
      title.indexOf('최종화') >= 0 || lowerTitle.indexOf('final') >= 0) {
      return 0;
    }
    if (title.indexOf('尾声') >= 0 || title.indexOf('尾聲') >= 0 ||
      title.indexOf('エピローグ') >= 0 || title.indexOf('에필로그') >= 0 ||
      lowerTitle.indexOf('epilogue') >= 0) {
      return 1;
    }
    if (title.indexOf('后记') >= 0 || title.indexOf('後記') >= 0 ||
      title.indexOf('후기') >= 0 || lowerTitle.indexOf('afterword') >= 0) {
      return 2;
    }
    if (title.indexOf('番外') >= 0 || title.indexOf('外传') >= 0 || title.indexOf('外傳') >= 0 ||
      title.indexOf('番外編') >= 0 || title.indexOf('外伝') >= 0 || title.indexOf('おまけ') >= 0 ||
      title.indexOf('オマケ') >= 0 || title.indexOf('特別編') >= 0 || title.indexOf('특별편') >= 0 ||
      title.indexOf('特典') >= 0 || title.indexOf('彩页') >= 0 || title.indexOf('彩頁') >= 0 ||
      title.indexOf('カラーページ') >= 0 || title.indexOf('巻頭カラー') >= 0 ||
      title.indexOf('センターカラー') >= 0 || title.indexOf('외전') >= 0 || title.indexOf('번외') >= 0 ||
      title.indexOf('후일담') >= 0 || title.indexOf('특전') >= 0 || title.indexOf('보너스') >= 0 ||
      title.indexOf('스페셜') >= 0 ||
      lowerTitle.indexOf('extra') >= 0 || lowerTitle.indexOf('bonus') >= 0 ||
      lowerTitle.indexOf('special') >= 0 || lowerTitle.indexOf('side story') >= 0 ||
      lowerTitle.indexOf('side chapter') >= 0 || lowerTitle.indexOf('after story') >= 0 ||
      lowerTitle.indexOf('omake') >= 0 || lowerTitle.indexOf('one-shot') >= 0 ||
      lowerTitle.indexOf('oneshot') >= 0 || lowerTitle.indexOf('translator note') >= 0 ||
      lowerTitle.indexOf('credit') >= 0 || lowerTitle.indexOf('color page') >= 0 ||
      lowerTitle.indexOf('pin-up') >= 0 || lowerTitle.indexOf('pin up') >= 0 ||
      lowerTitle.indexOf('spread') >= 0) {
      const numberValue = this.extractNumericOrder(title);
      return numberValue >= 0 ? 100 + numberValue : 100;
    }
    return -1;
  }

  private extractNumericOrder(title: string): number {
    const arabicNumber = this.extractFirstArabicNumber(title);
    if (arabicNumber >= 0) {
      return arabicNumber;
    }
    const chineseNumberText = this.extractChineseNumberText(title);
    if (chineseNumberText.length > 0) {
      return this.parseChineseNumber(chineseNumberText);
    }
    const romanNumber = this.extractLabelledRomanNumber(title);
    if (romanNumber >= 0) {
      return romanNumber;
    }
    return -1;
  }

  private extractFirstArabicNumber(title: string): number {
    let value = -1;
    let current = '';
    for (let i = 0; i < title.length; i++) {
      const char = title.charAt(i);
      const digit = this.resolveArabicDigit(char);
      if (digit >= 0) {
        current += `${digit}`;
      } else if (current.length > 0) {
        break;
      }
    }
    if (current.length > 0) {
      const parsed = Number(current);
      if (Number.isFinite(parsed)) {
        value = Math.floor(parsed);
      }
    }
    return value;
  }

  private resolveArabicDigit(char: string): number {
    if (char >= '0' && char <= '9') {
      return Number(char);
    }
    const fullWidthDigits = '０１２３４５６７８９';
    const fullWidthIndex = fullWidthDigits.indexOf(char);
    if (fullWidthIndex >= 0) {
      return fullWidthIndex;
    }
    return -1;
  }

  private extractChineseNumberText(title: string): string {
    const validChars = '零〇一二两三四五六七八九十百千万萬壹贰叁肆伍陆柒捌玖拾佰仟壱弐参';
    let current = '';
    let best = '';
    for (let i = 0; i < title.length; i++) {
      const char = title.charAt(i);
      if (validChars.indexOf(char) >= 0) {
        current += char;
      } else {
        if (current.length > best.length) {
          best = current;
        }
        current = '';
      }
    }
    if (current.length > best.length) {
      best = current;
    }
    return best;
  }

  private parseChineseNumber(text: string): number {
    if (text.length === 0) {
      return -1;
    }
    let total = 0;
    let section = 0;
    let number = 0;
    for (let i = 0; i < text.length; i++) {
      const digit = this.resolveChineseDigit(text.charAt(i));
      if (digit >= 0) {
        number = digit;
        continue;
      }
      const unit = this.resolveChineseUnit(text.charAt(i));
      if (unit === 10000) {
        section = (section + number) * unit;
        total += section;
        section = 0;
        number = 0;
      } else if (unit > 0) {
        const safeNumber = number === 0 ? 1 : number;
        section += safeNumber * unit;
        number = 0;
      }
    }
    const result = total + section + number;
    return result > 0 ? result : -1;
  }

  private extractLabelledRomanNumber(title: string): number {
    const pattern = /(?:Chapter|Chap\.?|Ch\.?|Episode|Ep\.?|Volume|Vol\.?|Part|Book|Season|Issue|No\.?|Act|File|Manga|Comic|Webtoon|Manhwa|Manhua|Tank(?:o|ō)bon|Doujinshi|Anthology|Magazine|Serial|Arc)\s+([IVXLCDMivxlcdm]{1,10})/;
    const match = pattern.exec(title);
    if (match === null || match.length < 2) {
      return -1;
    }
    return this.parseRomanNumber(match[1]);
  }

  private parseRomanNumber(text: string): number {
    if (text.length === 0) {
      return -1;
    }
    let total = 0;
    let previous = 0;
    for (let i = text.length - 1; i >= 0; i--) {
      const value = this.resolveRomanDigit(text.charAt(i));
      if (value <= 0) {
        return -1;
      }
      if (value < previous) {
        total -= value;
      } else {
        total += value;
        previous = value;
      }
    }
    return total > 0 ? total : -1;
  }

  private resolveRomanDigit(char: string): number {
    const upperChar = char.toUpperCase();
    if (upperChar === 'I') {
      return 1;
    }
    if (upperChar === 'V') {
      return 5;
    }
    if (upperChar === 'X') {
      return 10;
    }
    if (upperChar === 'L') {
      return 50;
    }
    if (upperChar === 'C') {
      return 100;
    }
    if (upperChar === 'D') {
      return 500;
    }
    if (upperChar === 'M') {
      return 1000;
    }
    return -1;
  }

  private resolveChineseDigit(char: string): number {
    if (char === '零' || char === '〇') {
      return 0;
    }
    if (char === '一' || char === '壹' || char === '壱') {
      return 1;
    }
    if (char === '二' || char === '两' || char === '贰' || char === '弐') {
      return 2;
    }
    if (char === '三' || char === '叁' || char === '参') {
      return 3;
    }
    if (char === '四' || char === '肆') {
      return 4;
    }
    if (char === '五' || char === '伍') {
      return 5;
    }
    if (char === '六' || char === '陆') {
      return 6;
    }
    if (char === '七' || char === '柒') {
      return 7;
    }
    if (char === '八' || char === '捌') {
      return 8;
    }
    if (char === '九' || char === '玖') {
      return 9;
    }
    return -1;
  }

  private resolveChineseUnit(char: string): number {
    if (char === '十' || char === '拾') {
      return 10;
    }
    if (char === '百' || char === '佰') {
      return 100;
    }
    if (char === '千' || char === '仟') {
      return 1000;
    }
    if (char === '万' || char === '萬') {
      return 10000;
    }
    return -1;
  }

  private compareEntries(left: ChapterRuleSortEntry, right: ChapterRuleSortEntry): number {
    if (left.category !== right.category) {
      return left.category - right.category;
    }
    if (left.orderValue !== right.orderValue) {
      return left.orderValue - right.orderValue;
    }
    if (left.ruleOrder !== right.ruleOrder) {
      return left.ruleOrder - right.ruleOrder;
    }
    return left.originalIndex - right.originalIndex;
  }

  private countMoved(source: UnifiedChapter[], ordered: UnifiedChapter[]): number {
    let moved = 0;
    for (let i = 0; i < source.length && i < ordered.length; i++) {
      if (source[i].id !== ordered[i].id || source[i].index !== ordered[i].index) {
        moved++;
      }
    }
    return moved;
  }

  private buildAppliedRuleName(rules: CompiledTxtTocRule[], selectedRuleId: string): string {
    if (selectedRuleId.length === 0) {
      return '全部启用规则';
    }
    for (let i = 0; i < rules.length; i++) {
      if (rules[i].id === selectedRuleId) {
        return rules[i].name;
      }
    }
    return '指定规则';
  }

  private createResult(
    orderedChapters: UnifiedChapter[],
    matchedCount: number,
    movedCount: number,
    unresolvedCount: number,
    message: string,
    appliedRuleName: string
  ): ChapterRuleSortResult {
    return {
      orderedChapters: orderedChapters,
      matchedCount: matchedCount,
      movedCount: movedCount,
      unresolvedCount: unresolvedCount,
      message: message,
      appliedRuleName: appliedRuleName
    };
  }

  private cloneChapterArray(chapters: UnifiedChapter[]): UnifiedChapter[] {
    const result: UnifiedChapter[] = [];
    for (let i = 0; i < chapters.length; i++) {
      result.push(chapters[i]);
    }
    return result;
  }
}

export function getChapterOrderRuleSorter(): ChapterOrderRuleSorter {
  return new ChapterOrderRuleSorter();
}
