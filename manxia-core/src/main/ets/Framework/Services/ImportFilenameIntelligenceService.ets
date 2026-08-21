import { EBookMetadata } from '../../Models/EBookModels';

export type ImportSuggestedContentKind = 'manga' | 'ebook' | 'unknown';

export interface ImportFilenameMetadataCandidate {
  key: string;
  title: string;
  author: string;
  publisher: string;
  publishDate: string;
  isbn: string;
  language: string;
  tags: string[];
  chapterNumber?: number;
  chapterTitle?: string;
  volumeNumber?: number;
  reason: string;
  confidence: number;
  recommendedContentKind: ImportSuggestedContentKind;
}

export interface ImportFilenameParseResult {
  rawInput: string;
  fileName: string;
  fileStem: string;
  cleanedStem: string;
  bestCandidate: ImportFilenameMetadataCandidate;
  candidates: ImportFilenameMetadataCandidate[];
  titleOptions: string[];
  authorOptions: string[];
  publisherOptions: string[];
  isbnOptions: string[];
  languageOptions: string[];
}

interface ExtractedValue {
  value: string;
  fullMatch: string;
}

interface ChapterExtraction {
  chapterNumber?: number;
  chapterTitle?: string;
  volumeNumber?: number;
  fullMatch: string;
}

interface PairCandidate {
  title: string;
  author: string;
  reason: string;
  confidence: number;
}

class ChapterPattern {
  regex: RegExp;
  titlePrefix: string;
  titleSuffix: string;
  volume: boolean;

  constructor(regex: RegExp, titlePrefix: string, titleSuffix: string, volume: boolean = false) {
    this.regex = regex;
    this.titlePrefix = titlePrefix;
    this.titleSuffix = titleSuffix;
    this.volume = volume;
  }

  buildTitle(num: number): string {
    return `${this.titlePrefix}${num}${this.titleSuffix}`;
  }
}

export class ImportFilenameIntelligenceService {
  private static instance: ImportFilenameIntelligenceService | null = null;

  private readonly authorLabels: string[] = [
    '作者', '著者', '原著', '著', '作', '编著', '编', '作者名',
    'author', 'authors', 'writer', 'writers', 'illustrator', 'artist', 'by',
    '著者名', '原作', '漫画', '作画', '文', '글', '저자', '원작'
  ];

  private readonly publisherLabels: string[] = [
    '出版社', '出版', '出版方', '发行', '発行', '出版元', 'publisher', 'publishing', 'press', 'imprint',
    '출판', '출판사'
  ];

  private readonly tagKeywords: string[] = [
    '完结', '完結', '全彩', '彩色', '汉化', '漢化', '简中', '繁中', '中文', '英文', '日文', '韩文',
    'raw', 'digital', 'scan', 'web', '合集', '合订版', '合本', '单行本', '特装版', '限定版', '无修正',
    '無修正', '全年龄', 'R18', 'R-18'
  ];

  public static getInstance(): ImportFilenameIntelligenceService {
    if (!ImportFilenameIntelligenceService.instance) {
      ImportFilenameIntelligenceService.instance = new ImportFilenameIntelligenceService();
    }
    return ImportFilenameIntelligenceService.instance;
  }

  public parseFileName(input: string): ImportFilenameParseResult {
    const rawInput = input || '';
    const fileName = this.extractFileName(rawInput);
    const fileStem = this.removeExtension(fileName);
    const cleanedStem = this.normalizeForParsing(fileStem);
    const bracketSegments = this.collectBracketSegments(fileStem);
    const combinedContext = [cleanedStem].concat(bracketSegments).join(' ');

    const quotedTitle = this.extractQuotedTitle(fileStem);
    const authorExtraction = this.extractLabeledValue(combinedContext, this.authorLabels);
    const publisherExtraction = this.extractLabeledValue(combinedContext, this.publisherLabels);
    const isbnExtraction = this.extractIsbn(combinedContext);
    const publishDateExtraction = this.extractPublishDate(combinedContext);
    const chapterExtraction = this.extractChapterInfo(combinedContext);
    const language = this.detectLanguage([combinedContext].concat(bracketSegments).join(' '));
    const pairCandidates = this.extractSeparatedPairs(cleanedStem);
    const meaningfulSegments = this.extractMeaningfulSegments(cleanedStem);

    const titleOptions: string[] = [];
    const authorOptions: string[] = [];
    const publisherOptions: string[] = [];
    const isbnOptions: string[] = [];
    const languageOptions: string[] = [];

    this.pushUnique(titleOptions, quotedTitle);
    for (const pairCandidate of pairCandidates) {
      this.pushUnique(titleOptions, pairCandidate.title);
      this.pushUnique(authorOptions, pairCandidate.author);
    }

    const sanitizedTitle = this.buildSanitizedTitle(
      fileStem,
      bracketSegments,
      authorExtraction.fullMatch,
      publisherExtraction.fullMatch,
      isbnExtraction.fullMatch,
      publishDateExtraction.fullMatch,
      chapterExtraction.fullMatch,
      language
    );
    this.pushUnique(titleOptions, sanitizedTitle);

    for (const segment of meaningfulSegments) {
      this.pushUnique(titleOptions, segment);
    }

    if (authorExtraction.value.length > 0) {
      this.pushUnique(authorOptions, authorExtraction.value);
    }
    for (const segment of bracketSegments) {
      const authorFromBracket = this.extractLabeledValue(segment, this.authorLabels).value;
      this.pushUnique(authorOptions, authorFromBracket);
      if (this.isLikelyPersonName(segment)) {
        this.pushUnique(authorOptions, this.cleanSegment(segment));
      }
    }

    if (publisherExtraction.value.length > 0) {
      this.pushUnique(publisherOptions, publisherExtraction.value);
    }
    for (const segment of bracketSegments) {
      const publisherFromBracket = this.extractLabeledValue(segment, this.publisherLabels).value;
      this.pushUnique(publisherOptions, publisherFromBracket);
    }

    if (isbnExtraction.value.length > 0) {
      this.pushUnique(isbnOptions, isbnExtraction.value);
    }
    if (language.length > 0) {
      this.pushUnique(languageOptions, language);
    }
    for (const segment of bracketSegments) {
      const bracketLanguage = this.detectLanguage(segment);
      this.pushUnique(languageOptions, bracketLanguage);
    }

    if (titleOptions.length === 0) {
      this.pushUnique(titleOptions, this.cleanupTitle(this.normalizeForParsing(fileStem)));
    }

    const bestPublisher = publisherOptions.length > 0 ? publisherOptions[0] : '';
    const bestIsbn = isbnOptions.length > 0 ? isbnOptions[0] : '';
    const bestLanguage = languageOptions.length > 0 ? languageOptions[0] : '';
    const bestPublishDate = publishDateExtraction.value;
    const tags = this.extractTags(bracketSegments, cleanedStem);

    const candidates: ImportFilenameMetadataCandidate[] = [];

    if (quotedTitle.length > 0) {
      this.pushCandidate(candidates, {
        key: '',
        title: quotedTitle,
        author: authorOptions.length > 0 ? authorOptions[0] : '',
        publisher: bestPublisher,
        publishDate: bestPublishDate,
        isbn: bestIsbn,
        language: bestLanguage,
        tags: tags,
        chapterNumber: chapterExtraction.chapterNumber,
        chapterTitle: chapterExtraction.chapterTitle,
        volumeNumber: chapterExtraction.volumeNumber,
        reason: '书名号/引号提取',
        confidence: authorOptions.length > 0 ? 0.97 : 0.94,
        recommendedContentKind: 'unknown'
      });
    }

    for (const pairCandidate of pairCandidates) {
      this.pushCandidate(candidates, {
        key: '',
        title: pairCandidate.title,
        author: pairCandidate.author,
        publisher: bestPublisher,
        publishDate: bestPublishDate,
        isbn: bestIsbn,
        language: bestLanguage,
        tags: tags,
        chapterNumber: chapterExtraction.chapterNumber,
        chapterTitle: chapterExtraction.chapterTitle,
        volumeNumber: chapterExtraction.volumeNumber,
        reason: pairCandidate.reason,
        confidence: pairCandidate.confidence,
        recommendedContentKind: 'unknown'
      });
    }

    if (sanitizedTitle.length > 0) {
      this.pushCandidate(candidates, {
        key: '',
        title: sanitizedTitle,
        author: authorOptions.length > 0 ? authorOptions[0] : '',
        publisher: bestPublisher,
        publishDate: bestPublishDate,
        isbn: bestIsbn,
        language: bestLanguage,
        tags: tags,
        chapterNumber: chapterExtraction.chapterNumber,
        chapterTitle: chapterExtraction.chapterTitle,
        volumeNumber: chapterExtraction.volumeNumber,
        reason: '元信息清理后结果',
        confidence: 0.88,
        recommendedContentKind: 'unknown'
      });
    }

    for (let index = 0; index < titleOptions.length && index < 3; index++) {
      const title = titleOptions[index];
      const author = authorOptions.length > index ? authorOptions[index] : (authorOptions.length > 0 ? authorOptions[0] : '');
      this.pushCandidate(candidates, {
        key: '',
        title: title,
        author: author,
        publisher: bestPublisher,
        publishDate: bestPublishDate,
        isbn: bestIsbn,
        language: bestLanguage,
        tags: tags,
        chapterNumber: chapterExtraction.chapterNumber,
        chapterTitle: chapterExtraction.chapterTitle,
        volumeNumber: chapterExtraction.volumeNumber,
        reason: index === 0 ? '主候选' : `候选 ${index + 1}`,
        confidence: Math.max(0.68, 0.83 - index * 0.06),
        recommendedContentKind: 'unknown'
      });
    }

    if (candidates.length === 0) {
      const fallbackTitle = this.cleanupTitle(fileStem);
      this.pushCandidate(candidates, {
        key: '',
        title: fallbackTitle,
        author: authorOptions.length > 0 ? authorOptions[0] : '',
        publisher: bestPublisher,
        publishDate: bestPublishDate,
        isbn: bestIsbn,
        language: bestLanguage,
        tags: tags,
        chapterNumber: chapterExtraction.chapterNumber,
        chapterTitle: chapterExtraction.chapterTitle,
        volumeNumber: chapterExtraction.volumeNumber,
        reason: '文件名兜底',
        confidence: 0.6,
        recommendedContentKind: 'unknown'
      });
    }

    const extension = this.extractExtension(fileName);
    for (const candidate of candidates) {
      candidate.recommendedContentKind = this.resolveContentKind(extension, cleanedStem, candidate);
      candidate.key = this.buildCandidateKey(candidate);
      candidate.confidence = this.clampConfidence(candidate.confidence);
    }

    candidates.sort((left: ImportFilenameMetadataCandidate, right: ImportFilenameMetadataCandidate) => {
      if (right.confidence !== left.confidence) {
        return right.confidence - left.confidence;
      }
      return right.title.length - left.title.length;
    });

    const bestCandidate = candidates.length > 0
      ? candidates[0]
      : this.createEmptyCandidate();

    return {
      rawInput: rawInput,
      fileName: fileName,
      fileStem: fileStem,
      cleanedStem: cleanedStem,
      bestCandidate: bestCandidate,
      candidates: candidates,
      titleOptions: titleOptions,
      authorOptions: authorOptions,
      publisherOptions: publisherOptions,
      isbnOptions: isbnOptions,
      languageOptions: languageOptions
    };
  }

  public applyBestCandidateToEBookMetadata(metadata: EBookMetadata, input: string): EBookMetadata {
    const result = this.parseFileName(input);
    const candidate = result.bestCandidate;
    const mergedTags = this.mergeTags(metadata.tags, candidate.tags);
    return {
      title: metadata.title || candidate.title,
      author: metadata.author || candidate.author,
      description: metadata.description,
      publisher: metadata.publisher || candidate.publisher,
      publishDate: metadata.publishDate || candidate.publishDate,
      isbn: metadata.isbn || candidate.isbn,
      language: metadata.language || candidate.language,
      coverImagePath: metadata.coverImagePath,
      tags: mergedTags,
      rating: metadata.rating
    };
  }

  private extractFileName(input: string): string {
    const withoutQuery = this.stripSuffix(input, '?');
    const withoutFragment = this.stripSuffix(withoutQuery, '#');
    const normalized = withoutFragment.replace(/\\/g, '/');
    const lastSlashIndex = normalized.lastIndexOf('/');
    if (lastSlashIndex >= 0) {
      return normalized.substring(lastSlashIndex + 1);
    }
    return normalized;
  }

  private stripSuffix(input: string, marker: string): string {
    const index = input.indexOf(marker);
    if (index >= 0) {
      return input.substring(0, index);
    }
    return input;
  }

  private removeExtension(fileName: string): string {
    return fileName.replace(/\.[^.]+$/i, '');
  }

  private extractExtension(fileName: string): string {
    const match = fileName.match(/\.([^.]+)$/i);
    return match && match[1] ? match[1].toLowerCase() : '';
  }

  private normalizeForParsing(value: string): string {
    let result = this.toHalfWidth(value);
    result = result.replace(/[_]+/g, ' ');
    result = result.replace(/[·•・]+/g, ' ');
    result = result.replace(/[—–]+/g, ' - ');
    result = result.replace(/\s*\|\s*/g, ' | ');
    result = result.replace(/\s*｜\s*/g, ' | ');
    result = result.replace(/\s+/g, ' ').trim();
    result = result.replace(/^\d{8,14}[-_\s]+/, '');
    result = result.replace(/^[A-Za-z]{0,4}\d{8,14}[-_\s]+/, '');
    result = result.replace(/^\[[^\]]{1,12}\]\s+/, '');
    return result;
  }

  private toHalfWidth(value: string): string {
    let result = '';
    for (let index = 0; index < value.length; index++) {
      const code = value.charCodeAt(index);
      if (code === 12288) {
        result += ' ';
      } else if (code >= 65281 && code <= 65374) {
        result += String.fromCharCode(code - 65248);
      } else {
        result += value[index];
      }
    }
    return result;
  }

  private collectBracketSegments(value: string): string[] {
    const result: string[] = [];
    const regex = /[\[\(\{【（〔［「『<〈]([^\]\)\}】）〕］」』>〉]{1,80})[\]\)\}】）〕］」』>〉]/g;
    let match: RegExpExecArray | null = regex.exec(value);
    while (match) {
      this.pushUnique(result, this.cleanSegment(match[1]));
      match = regex.exec(value);
    }
    return result;
  }

  private extractQuotedTitle(value: string): string {
    const patterns: RegExp[] = [
      /《([^》]{1,120})》/,
      /「([^」]{1,120})」/,
      /『([^』]{1,120})』/,
      /〈([^〉]{1,120})〉/,
      /"([^"]{2,120})"/,
      /'([^']{2,120})'/
    ];
    for (const pattern of patterns) {
      const match = value.match(pattern);
      if (match && match[1]) {
        return this.cleanupTitle(match[1]);
      }
    }
    return '';
  }

  private extractLabeledValue(value: string, labels: string[]): ExtractedValue {
    const labelPattern = labels.map((label: string) => this.escapeRegExp(label)).join('|');
    const regex = new RegExp(`(?:^|[\\s\\[\\(【（])(?:${labelPattern})[\\s:：=\\-]*([^\\]\\)】）\\|｜,，]{1,60})`, 'i');
    const match = value.match(regex);
    if (!match || !match[1]) {
      return { value: '', fullMatch: '' };
    }
    return {
      value: this.cleanSegment(match[1]),
      fullMatch: this.cleanSegment(match[0])
    };
  }

  private extractIsbn(value: string): ExtractedValue {
    const regex = /ISBN(?:-1[03])?[\s:：-]*((?:97[89][\s-]?)?[0-9Xx][0-9Xx\s-]{8,20}[0-9Xx])/i;
    const match = value.match(regex);
    if (!match || !match[1]) {
      return { value: '', fullMatch: '' };
    }
    const normalized = match[1].replace(/[\s-]/g, '').toUpperCase();
    return {
      value: normalized,
      fullMatch: this.cleanSegment(match[0])
    };
  }

  private extractPublishDate(value: string): ExtractedValue {
    const patterns: RegExp[] = [
      /((?:19|20)\d{2}[./_-](?:0?[1-9]|1[0-2])(?:[./_-](?:0?[1-9]|[12]\d|3[01]))?)/,
      /((?:19|20)\d{2}年(?:\d{1,2}月(?:\d{1,2}日)?)?)/,
      /((?:19|20)\d{2}\/\d{1,2}\/\d{1,2})/
    ];
    for (const pattern of patterns) {
      const match = value.match(pattern);
      if (match && match[1]) {
        return {
          value: this.cleanSegment(match[1]),
          fullMatch: this.cleanSegment(match[0])
        };
      }
    }
    return { value: '', fullMatch: '' };
  }

  private extractChapterInfo(value: string): ChapterExtraction {
    const patterns: ChapterPattern[] = [
      new ChapterPattern(/第\s*(\d{1,4})\s*(?:话|話|章|回|集)/i, '第', '话'),
      new ChapterPattern(/第\s*(\d{1,4})\s*(?:卷|册|冊)/i, '第', '卷', true),
      new ChapterPattern(/(?:ch(?:apter)?|ep(?:isode)?)[.\s_-]*(\d{1,4})/i, 'Chapter ', ''),
      new ChapterPattern(/(?:vol(?:ume)?|book)[.\s_-]*(\d{1,4})/i, 'Volume ', '', true)
    ];
    for (const pattern of patterns) {
      const match = value.match(pattern.regex);
      if (match && match[1]) {
        const numberValue = parseInt(match[1], 10);
        if (numberValue > 0) {
          return {
            chapterNumber: pattern.volume ? undefined : numberValue,
            chapterTitle: pattern.volume ? undefined : pattern.buildTitle(numberValue),
            volumeNumber: pattern.volume ? numberValue : undefined,
            fullMatch: this.cleanSegment(match[0])
          };
        }
      }
    }
    return { fullMatch: '' };
  }

  private detectLanguage(value: string): string {
    const lowerValue = value.toLowerCase();
    if (/(?:简中|简体|简体中文|chs|zh-cn|zh_cn|zh-hans|中文|汉化)/i.test(lowerValue)) {
      return 'zh-CN';
    }
    if (/(?:繁中|繁体|繁體|繁体中文|繁體中文|cht|zh-tw|zh_tw|zh-hant|港版)/i.test(lowerValue)) {
      return 'zh-TW';
    }
    if (/(?:english|eng\b|英文|en-us|en_gb|英訳)/i.test(lowerValue)) {
      return 'en';
    }
    if (/(?:日本語|日文|日语|japanese|jpn\b|ja\b|jp\b)/i.test(lowerValue) || /[ぁ-んァ-ヶ]/.test(value)) {
      return 'ja';
    }
    if (/(?:한국어|韩文|韓文|korean|kor\b|ko\b|kr\b)/i.test(lowerValue) || /[가-힣]/.test(value)) {
      return 'ko';
    }
    return '';
  }

  private extractSeparatedPairs(value: string): PairCandidate[] {
    const result: PairCandidate[] = [];
    const segments = value.split(/\s+\|\s+|\s+-\s+|\s+—\s+|\s+–\s+|\s+_\s+/)
      .map((segment: string) => this.cleanSegment(segment))
      .filter((segment: string) => segment.length > 0);

    for (let index = 0; index < segments.length - 1; index++) {
      const left = segments[index];
      const right = segments[index + 1];
      if (!this.isLikelyTitleSegment(left) && !this.isLikelyTitleSegment(right)) {
        continue;
      }

      if (this.hasAuthorLabel(left) && this.isLikelyTitleSegment(right)) {
        result.push({
          title: this.cleanupTitle(right),
          author: this.stripLeadingLabel(left),
          reason: '分隔符配对',
          confidence: 0.93
        });
        continue;
      }

      if (this.hasAuthorLabel(right) && this.isLikelyTitleSegment(left)) {
        result.push({
          title: this.cleanupTitle(left),
          author: this.stripLeadingLabel(right),
          reason: '分隔符配对',
          confidence: 0.93
        });
        continue;
      }

      if (this.isLikelyPersonName(right) && this.isLikelyTitleSegment(left)) {
        result.push({
          title: this.cleanupTitle(left),
          author: this.cleanSegment(right),
          reason: '标题 + 作者',
          confidence: 0.89
        });
        continue;
      }

      if (this.isLikelyPersonName(left) && this.isLikelyTitleSegment(right)) {
        result.push({
          title: this.cleanupTitle(right),
          author: this.cleanSegment(left),
          reason: '作者 + 标题',
          confidence: 0.83
        });
      }
    }

    return result;
  }

  private extractMeaningfulSegments(value: string): string[] {
    const result: string[] = [];
    const working = value.replace(/[\[\]【】\(\)（）{}「」『』《》]/g, ' ');
    const segments = working.split(/\s+\|\s+|\s+-\s+|\s+—\s+|\s+–\s+|\s+_\s+|\s{2,}/)
      .map((segment: string) => this.cleanupTitle(segment));
    for (const segment of segments) {
      if (!this.isLikelyTitleSegment(segment)) {
        continue;
      }
      if (this.isLikelyPersonName(segment) && segment.length <= 10) {
        continue;
      }
      this.pushUnique(result, segment);
    }
    return result;
  }

  private buildSanitizedTitle(
    value: string,
    bracketSegments: string[],
    authorFullMatch: string,
    publisherFullMatch: string,
    isbnFullMatch: string,
    publishDateFullMatch: string,
    chapterFullMatch: string,
    language: string
  ): string {
    let result = this.normalizeForParsing(value);
    for (const segment of bracketSegments) {
      if (this.shouldTreatBracketAsMetadata(segment)) {
        result = result.replace(new RegExp(this.escapeRegExp(segment), 'ig'), ' ');
      }
    }

    const removals: string[] = [authorFullMatch, publisherFullMatch, isbnFullMatch, publishDateFullMatch, chapterFullMatch, language];
    for (const removal of removals) {
      if (removal.length > 0) {
        result = result.replace(new RegExp(this.escapeRegExp(removal), 'ig'), ' ');
      }
    }

    result = result.replace(/ISBN(?:-1[03])?[\s:：-]*[0-9Xx\s-]+/ig, ' ');
    result = result.replace(/第\s*\d{1,4}\s*(?:话|話|章|回|集|卷|册|冊)/ig, ' ');
    result = result.replace(/(?:ch(?:apter)?|ep(?:isode)?|vol(?:ume)?|book)[.\s_-]*\d{1,4}/ig, ' ');
    result = result.replace(/[\[\]【】\(\)（）{}「」『』《》<>〈〉]/g, ' ');
    result = result.replace(/(?:作者|著者|原著|著|author|writer|illustrator|artist|by|出版社|出版|publisher|press)\s*[:：=\-]?/ig, ' ');
    result = result.replace(/(?:简中|繁中|chs|cht|eng|jpn|kor|raw|digital|scan)\b/ig, ' ');
    result = result.replace(/\s+/g, ' ').trim();
    return this.cleanupTitle(result);
  }

  private extractTags(bracketSegments: string[], cleanedStem: string): string[] {
    const result: string[] = [];
    for (const segment of bracketSegments) {
      const cleaned = this.cleanSegment(segment);
      if (cleaned.length === 0) {
        continue;
      }
      if (this.isLikelyTagSegment(cleaned)) {
        this.pushUnique(result, cleaned);
      }
    }

    for (const keyword of this.tagKeywords) {
      if (cleanedStem.toLowerCase().includes(keyword.toLowerCase())) {
        this.pushUnique(result, keyword);
      }
    }

    return result;
  }

  private resolveContentKind(
    extension: string,
    cleanedStem: string,
    candidate: ImportFilenameMetadataCandidate
  ): ImportSuggestedContentKind {
    if (['epub', 'mobi', 'azw3', 'fb2', 'txt'].includes(extension)) {
      return 'ebook';
    }
    if (['cbz', 'cbr'].includes(extension)) {
      return 'manga';
    }

    if (candidate.chapterNumber !== undefined || candidate.volumeNumber !== undefined) {
      return 'manga';
    }

    if (candidate.isbn.length > 0 || candidate.publisher.length > 0 || candidate.publishDate.length > 0) {
      return 'ebook';
    }

    if (/(?:小说|文库|文学|ebook|book|novel|light\s*novel|全集|选集)/i.test(cleanedStem)) {
      return 'ebook';
    }

    if (/(?:漫画|漫本|comic|manga|同人|画集|番外|短篇|单话|单行本)/i.test(cleanedStem)) {
      return 'manga';
    }

    return 'unknown';
  }

  private cleanupTitle(value: string): string {
    let result = this.cleanSegment(value);
    result = result.replace(/^(?:[-_|｜:：]+)\s*/, '');
    result = result.replace(/\s*(?:[-_|｜:：]+)$/, '');
    result = result.replace(/\s+/g, ' ').trim();
    return result;
  }

  private cleanSegment(value: string): string {
    let result = this.toHalfWidth(value || '').trim();
    result = result.replace(/^[\s\[\]【】\(\)（）{}「」『』《》<>〈〉'"`]+/, '');
    result = result.replace(/[\s\[\]【】\(\)（）{}「」『』《》<>〈〉'"`]+$/, '');
    result = result.replace(/\s+/g, ' ').trim();
    return result;
  }

  private hasAuthorLabel(value: string): boolean {
    const lowerValue = value.toLowerCase();
    for (const label of this.authorLabels) {
      if (lowerValue.includes(label.toLowerCase())) {
        return true;
      }
    }
    return false;
  }

  private stripLeadingLabel(value: string): string {
    let result = value;
    const labels = this.authorLabels.concat(this.publisherLabels);
    for (const label of labels) {
      result = result.replace(new RegExp(`^${this.escapeRegExp(label)}\\s*[:：=\\-]?\\s*`, 'i'), '');
    }
    return this.cleanSegment(result);
  }

  private isLikelyPersonName(value: string): boolean {
    const cleaned = this.cleanSegment(this.stripLeadingLabel(value));
    if (cleaned.length === 0 || cleaned.length > 32) {
      return false;
    }
    if (/\d/.test(cleaned)) {
      return false;
    }
    if (this.isLikelyTagSegment(cleaned) || this.shouldTreatBracketAsMetadata(cleaned)) {
      return false;
    }
    const wordCount = cleaned.split(/\s+/).filter((part: string) => part.length > 0).length;
    if (wordCount > 4) {
      return false;
    }
    return /[A-Za-z\u4e00-\u9fffぁ-んァ-ヶ가-힣]/.test(cleaned);
  }

  private isLikelyTitleSegment(value: string): boolean {
    const cleaned = this.cleanupTitle(value);
    if (cleaned.length < 2 || cleaned.length > 120) {
      return false;
    }
    if (/^\d+$/.test(cleaned)) {
      return false;
    }
    if (this.shouldTreatBracketAsMetadata(cleaned)) {
      return false;
    }
    return true;
  }

  private shouldTreatBracketAsMetadata(value: string): boolean {
    const cleaned = this.cleanSegment(value);
    if (cleaned.length === 0) {
      return false;
    }
    if (this.isLikelyTagSegment(cleaned)) {
      return true;
    }
    if (this.hasAuthorLabel(cleaned) || this.extractLabeledValue(cleaned, this.authorLabels).value.length > 0) {
      return true;
    }
    if (this.extractLabeledValue(cleaned, this.publisherLabels).value.length > 0) {
      return true;
    }
    if (this.detectLanguage(cleaned).length > 0) {
      return true;
    }
    if (this.extractIsbn(cleaned).value.length > 0 || this.extractPublishDate(cleaned).value.length > 0) {
      return true;
    }
    return /^(?:raw|digital|scan|web|pdf|epub|mobi)$/i.test(cleaned);
  }

  private isLikelyTagSegment(value: string): boolean {
    const cleaned = this.cleanSegment(value);
    const lowerValue = cleaned.toLowerCase();
    if (cleaned.length === 0 || cleaned.length > 24) {
      return false;
    }
    if (this.detectLanguage(cleaned).length > 0) {
      return true;
    }
    for (const keyword of this.tagKeywords) {
      if (lowerValue.includes(keyword.toLowerCase())) {
        return true;
      }
    }
    return /^(?:raw|digital|scan|web|pdf|epub|mobi|vol\.?\s*\d+|ch\.?\s*\d+)$/i.test(lowerValue);
  }

  private mergeTags(existing: string[], additions: string[]): string[] {
    const result: string[] = [];
    for (const item of existing || []) {
      this.pushUnique(result, item);
    }
    for (const item of additions || []) {
      this.pushUnique(result, item);
    }
    return result;
  }

  private buildCandidateKey(candidate: ImportFilenameMetadataCandidate): string {
    const normalizedTitle = this.normalizeComparisonValue(candidate.title);
    const normalizedAuthor = this.normalizeComparisonValue(candidate.author);
    const normalizedChapter = candidate.chapterNumber !== undefined ? `${candidate.chapterNumber}` : '';
    return `${normalizedTitle}|${normalizedAuthor}|${normalizedChapter}|${candidate.recommendedContentKind}`;
  }

  private normalizeComparisonValue(value: string): string {
    const fileName = this.extractFileName(value);
    const withoutExtension = this.removeExtension(fileName);
    return this.toHalfWidth(withoutExtension)
      .toLowerCase()
      .replace(/[\s_\-|｜【】\[\]\(\)（）{}「」『』《》<>〈〉'"`.:：]+/g, '');
  }

  private clampConfidence(value: number): number {
    if (value < 0) {
      return 0;
    }
    if (value > 0.99) {
      return 0.99;
    }
    return value;
  }

  private createEmptyCandidate(): ImportFilenameMetadataCandidate {
    return {
      key: 'empty',
      title: '',
      author: '',
      publisher: '',
      publishDate: '',
      isbn: '',
      language: '',
      tags: [],
      reason: '无候选',
      confidence: 0,
      recommendedContentKind: 'unknown'
    };
  }

  private pushUnique(target: string[], value: string): void {
    const cleaned = this.cleanSegment(value);
    if (cleaned.length === 0) {
      return;
    }
    const normalized = this.normalizeComparisonValue(cleaned);
    for (const existing of target) {
      if (this.normalizeComparisonValue(existing) === normalized) {
        return;
      }
    }
    target.push(cleaned);
  }

  private pushCandidate(target: ImportFilenameMetadataCandidate[], candidate: ImportFilenameMetadataCandidate): void {
    const cleanedTitle = this.cleanupTitle(candidate.title);
    if (cleanedTitle.length === 0) {
      return;
    }
    const nextCandidate: ImportFilenameMetadataCandidate = {
      key: '',
      title: cleanedTitle,
      author: this.cleanSegment(candidate.author),
      publisher: this.cleanSegment(candidate.publisher),
      publishDate: this.cleanSegment(candidate.publishDate),
      isbn: this.cleanSegment(candidate.isbn),
      language: this.cleanSegment(candidate.language),
      tags: this.mergeTags([], candidate.tags || []),
      chapterNumber: candidate.chapterNumber,
      chapterTitle: this.cleanSegment(candidate.chapterTitle || ''),
      volumeNumber: candidate.volumeNumber,
      reason: candidate.reason,
      confidence: candidate.confidence,
      recommendedContentKind: candidate.recommendedContentKind
    };

    const nextKey = this.normalizeComparisonValue(nextCandidate.title) + '|' + this.normalizeComparisonValue(nextCandidate.author);
    for (let index = 0; index < target.length; index++) {
      const existing = target[index];
      const existingKey = this.normalizeComparisonValue(existing.title) + '|' + this.normalizeComparisonValue(existing.author);
      if (existingKey === nextKey) {
        if (nextCandidate.confidence > existing.confidence) {
          target[index] = nextCandidate;
        }
        return;
      }
    }
    target.push(nextCandidate);
  }

  private escapeRegExp(value: string): string {
    return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  }
}
