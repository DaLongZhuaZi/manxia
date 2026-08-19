import { RssFeedFormat, RssFeedItem, RssSubscriptionSource } from '../../Models/RssSubscriptionModels';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { LegadoRuleAnalyzer } from '../Novel/LegadoRuleAnalyzer';

export interface ParsedRssFeed {
  format: RssFeedFormat;
  title: string;
  items: RssFeedItem[];
}

const MAX_FEED_ITEMS = 500;
const MAX_TEXT_LENGTH = 12000;
const TAG = 'RssFeedParser';

export class RssFeedParser {
  parse(rawXml: string, source: RssSubscriptionSource): ParsedRssFeed {
    const xml = rawXml.trim();
    const format = this.detectFormat(xml);
    if (format === RssFeedFormat.UNKNOWN) {
      logger.warn(TAG, `检测到未知订阅格式: ${source.name}`);
    }
    const title = this.extractFirstTagText(xml, ['title']);

    const items = format === RssFeedFormat.ATOM
      ? this.parseAtomItems(xml, source)
      : this.parseRssItems(xml, source);

    const parsed: ParsedRssFeed = {
      format,
      title: this.trimText(this.decodeXml(this.stripCdata(title)), 300),
      items
    };
    logger.info(TAG, `解析订阅源完成: ${source.name}, 格式=${format}, 条目=${parsed.items.length}`);
    return parsed;
  }

  async parseByRulesAsync(rawContent: string, source: RssSubscriptionSource): Promise<ParsedRssFeed> {
    const content = rawContent.trim();
    let ruleArticles = (source.ruleArticles || '').trim();
    if (ruleArticles.length === 0) {
      return this.parse(content, source);
    }

    let reverse = false;
    if (ruleArticles.startsWith('-')) {
      reverse = true;
      ruleArticles = ruleArticles.substring(1).trim();
    }

    if (ruleArticles.length === 0) {
      return this.parse(content, source);
    }

    try {
      const analyzer = new LegadoRuleAnalyzer();
      analyzer.setJsLib(source.jsLib || '');
      analyzer.setContent(content, source.url, false);
      const blocks = await analyzer.getElementsAsync(ruleArticles);
      if (blocks.length === 0) {
        logger.warn(TAG, `规则解析未命中条目，回退默认解析: ${source.name}`);
        return this.parse(content, source);
      }

      const items: RssFeedItem[] = [];
      const now = Date.now();
      for (let i = 0; i < blocks.length && items.length < MAX_FEED_ITEMS; i++) {
        const block = blocks[i];
        const itemAnalyzer = new LegadoRuleAnalyzer();
        itemAnalyzer.setJsLib(source.jsLib || '');
        itemAnalyzer.setContent(block, source.url, false);

        const titleRule = (source.ruleTitle || 'title').trim();
        const linkRule = (source.ruleLink || 'link').trim();
        const pubDateRule = (source.rulePubDate || 'pubDate').trim();
        const descriptionRule = (source.ruleDescription || 'description').trim();
        const contentRule = (source.ruleContent || '').trim();

        const titleRaw = titleRule.length > 0 ? await itemAnalyzer.getStringAsync(titleRule) : '';
        const linkRaw = linkRule.length > 0 ? await itemAnalyzer.getStringAsync(linkRule) : '';
        const pubDateRaw = pubDateRule.length > 0 ? await itemAnalyzer.getStringAsync(pubDateRule) : '';
        const descriptionRaw = descriptionRule.length > 0 ? await itemAnalyzer.getStringAsync(descriptionRule) : '';
        const contentRaw = contentRule.length > 0 ? await itemAnalyzer.getStringAsync(contentRule) : '';
        const imageRaw = source.ruleImage && source.ruleImage.trim().length > 0
          ? await itemAnalyzer.getStringAsync(source.ruleImage)
          : '';

        const link = this.trimText(this.toAbsoluteUrl(source.url, this.decodeXml(this.stripCdata(linkRaw))), 2048);
        const title = this.trimText(this.decodeXml(this.stripCdata(titleRaw)), 300);
        if (title.length === 0 && link.length === 0) {
          continue;
        }

        const descriptionText = descriptionRaw.length > 0
          ? descriptionRaw
          : (contentRaw.length > 0 ? contentRaw : imageRaw);
        const description = this.trimText(
          this.normalizeSummary(this.decodeXml(this.stripCdata(descriptionText))),
          3000
        );
        const contentText = contentRaw.length > 0 ? contentRaw : descriptionRaw;
        const parsedContent = this.trimText(
          this.decodeXml(this.stripCdata(contentText)),
          MAX_TEXT_LENGTH
        );
        const pubDate = this.parseDateToTimestamp(pubDateRaw);

        items.push({
          id: `${source.id}_${this.stableHash(link.length > 0 ? link : `${title}_${i}`)}`,
          sourceId: source.id,
          sourceName: source.name,
          title: title.length > 0 ? title : (link.length > 0 ? link : `未命名条目 ${i + 1}`),
          link,
          description,
          content: parsedContent,
          author: '',
          category: '',
          guid: '',
          pubDate: pubDate > 0 ? pubDate : now,
          isRead: false,
          isStarred: false,
          createTime: now,
          updateTime: now
        });

        if (i > 0 && i % 50 === 0) {
          await new Promise<void>((resolve: () => void) => setTimeout((): void => resolve(), 0));
        }
      }

      if (reverse) {
        items.reverse();
      }

      logger.info(TAG, `规则解析订阅源完成: ${source.name}, 条目=${items.length}`);
      return {
        format: RssFeedFormat.UNKNOWN,
        title: source.name,
        items
      } as ParsedRssFeed;
    } catch (error) {
      logger.warn(TAG, `规则解析异常，回退默认解析: ${source.name}, ${String(error)}`);
      return this.parse(content, source);
    }
  }

  private detectFormat(xml: string): RssFeedFormat {
    if (/<feed[\s>]/i.test(xml) && /<entry[\s>]/i.test(xml)) {
      return RssFeedFormat.ATOM;
    }
    if (/<rss[\s>]/i.test(xml) || /<item[\s>]/i.test(xml)) {
      return RssFeedFormat.RSS;
    }
    return RssFeedFormat.UNKNOWN;
  }

  private parseRssItems(xml: string, source: RssSubscriptionSource): RssFeedItem[] {
    const itemRegex = /<item\b[\s\S]*?<\/item>/gi;
    const blocks = xml.match(itemRegex) || [];
    return this.buildItemsFromBlocks(blocks, source, false);
  }

  private parseAtomItems(xml: string, source: RssSubscriptionSource): RssFeedItem[] {
    const entryRegex = /<entry\b[\s\S]*?<\/entry>/gi;
    const blocks = xml.match(entryRegex) || [];
    return this.buildItemsFromBlocks(blocks, source, true);
  }

  private buildItemsFromBlocks(blocks: string[], source: RssSubscriptionSource, atom: boolean): RssFeedItem[] {
    const items: RssFeedItem[] = [];
    const now = Date.now();
    for (let i = 0; i < blocks.length && items.length < MAX_FEED_ITEMS; i++) {
      const block = blocks[i];
      const titleRaw = this.extractFirstTagText(block, ['title']);
      const linkRaw = atom ? this.extractAtomLink(block) : this.extractFirstTagText(block, ['link']);
      const summaryRaw = atom
        ? this.extractFirstTagText(block, ['summary', 'content'])
        : this.extractFirstTagText(block, ['description', 'content:encoded']);
      const contentRaw = atom
        ? this.extractFirstTagText(block, ['content', 'summary'])
        : this.extractFirstTagText(block, ['content:encoded', 'description']);
      const authorRaw = atom
        ? this.extractAtomAuthor(block)
        : this.extractFirstTagText(block, ['author', 'dc:creator']);
      const categoryRaw = atom
        ? this.extractAtomCategory(block)
        : this.extractFirstTagText(block, ['category']);
      const guidRaw = atom
        ? this.extractFirstTagText(block, ['id'])
        : this.extractFirstTagText(block, ['guid']);
      const pubDateRaw = atom
        ? this.extractFirstTagText(block, ['updated', 'published'])
        : this.extractFirstTagText(block, ['pubDate', 'dc:date', 'date', 'time']);

      const link = this.trimText(this.decodeXml(this.stripCdata(linkRaw || guidRaw)), 2048);
      const title = this.trimText(this.decodeXml(this.stripCdata(titleRaw)), 300);
      if (title.length === 0 && link.length === 0) {
        continue;
      }

      const description = this.trimText(
        this.normalizeSummary(this.decodeXml(this.stripCdata(summaryRaw))),
        3000
      );
      const content = this.trimText(this.decodeXml(this.stripCdata(contentRaw)), MAX_TEXT_LENGTH);
      const author = this.trimText(this.decodeXml(this.stripCdata(authorRaw)), 200);
      const category = this.trimText(this.decodeXml(this.stripCdata(categoryRaw)), 100);
      const guid = this.trimText(this.decodeXml(this.stripCdata(guidRaw)), 300);
      const pubDate = this.parseDateToTimestamp(pubDateRaw);

      items.push({
        id: `${source.id}_${this.stableHash(link.length > 0 ? link : `${guid}_${i}`)}`,
        sourceId: source.id,
        sourceName: source.name,
        title: title.length > 0 ? title : (link.length > 0 ? link : `未命名条目 ${i + 1}`),
        link,
        description,
        content,
        author,
        category,
        guid,
        pubDate: pubDate > 0 ? pubDate : now,
        isRead: false,
        isStarred: false,
        createTime: now,
        updateTime: now
      });
    }
    return items;
  }

  private extractFirstTagText(content: string, tags: string[]): string {
    for (const tag of tags) {
      const regex = new RegExp(`<${tag}\\b[^>]*>([\\s\\S]*?)<\\/${tag}>`, 'i');
      const match = content.match(regex);
      if (match && match[1]) {
        return match[1].trim();
      }
    }
    return '';
  }

  private extractAtomLink(block: string): string {
    const alternateRegex = /<link\b[^>]*\brel=["']alternate["'][^>]*\bhref=["']([^"']+)["'][^>]*\/?>/i;
    const hrefRegex = /<link\b[^>]*\bhref=["']([^"']+)["'][^>]*\/?>/i;
    const textRegex = /<link\b[^>]*>([\s\S]*?)<\/link>/i;
    const alternateMatch = block.match(alternateRegex);
    if (alternateMatch && alternateMatch[1]) {
      return alternateMatch[1];
    }
    const hrefMatch = block.match(hrefRegex);
    if (hrefMatch && hrefMatch[1]) {
      return hrefMatch[1];
    }
    const textMatch = block.match(textRegex);
    if (textMatch && textMatch[1]) {
      return textMatch[1];
    }
    return '';
  }

  private extractAtomAuthor(block: string): string {
    const nameRegex = /<author\b[^>]*>[\s\S]*?<name\b[^>]*>([\s\S]*?)<\/name>[\s\S]*?<\/author>/i;
    const textRegex = /<author\b[^>]*>([\s\S]*?)<\/author>/i;
    const nameMatch = block.match(nameRegex);
    if (nameMatch && nameMatch[1]) {
      return nameMatch[1];
    }
    const textMatch = block.match(textRegex);
    if (textMatch && textMatch[1]) {
      return textMatch[1];
    }
    return '';
  }

  private extractAtomCategory(block: string): string {
    const termRegex = /<category\b[^>]*\bterm=["']([^"']+)["'][^>]*\/?>/i;
    const textRegex = /<category\b[^>]*>([\s\S]*?)<\/category>/i;
    const termMatch = block.match(termRegex);
    if (termMatch && termMatch[1]) {
      return termMatch[1];
    }
    const textMatch = block.match(textRegex);
    if (textMatch && textMatch[1]) {
      return textMatch[1];
    }
    return '';
  }

  private stripCdata(text: string): string {
    return text.replace(/^<!\[CDATA\[/i, '').replace(/\]\]>$/i, '');
  }

  private stripHtml(text: string): string {
    return text
      .replace(/<script\b[\s\S]*?<\/script>/gi, ' ')
      .replace(/<style\b[\s\S]*?<\/style>/gi, ' ')
      .replace(/<[^>]+>/g, ' ');
  }

  private normalizeSummary(text: string): string {
    const withoutHtml = this.stripHtml(text);
    return withoutHtml.replace(/\s+/g, ' ').trim();
  }

  private decodeXml(text: string): string {
    return text
      .replace(/&#x([0-9a-fA-F]+);/g, (_m, hex: string) => {
        const code = parseInt(hex, 16);
        return Number.isNaN(code) ? _m : String.fromCharCode(code);
      })
      .replace(/&#(\d+);/g, (_m, num: string) => {
        const code = parseInt(num, 10);
        return Number.isNaN(code) ? _m : String.fromCharCode(code);
      })
      .replace(/&quot;/g, '"')
      .replace(/&apos;/g, '\'')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&')
      .trim();
  }

  private trimText(text: string, maxLength: number): string {
    if (text.length <= maxLength) {
      return text;
    }
    return text.substring(0, maxLength);
  }

  private parseDateToTimestamp(dateText: string): number {
    const text = dateText.trim();
    if (text.length === 0) {
      return Date.now();
    }

    const num = Number(text);
    if (!Number.isNaN(num) && Number.isFinite(num) && num > 0) {
      return num < 1_000_000_000_000 ? num * 1000 : num;
    }

    const directParse = Date.parse(text);
    if (!Number.isNaN(directParse)) {
      return directParse;
    }

    const fallbackText = text.replace(/,/g, '').replace(/\s+/g, ' ').trim();
    const fallbackParse = Date.parse(fallbackText);
    if (!Number.isNaN(fallbackParse)) {
      return fallbackParse;
    }

    return Date.now();
  }

  private toAbsoluteUrl(baseUrl: string, urlText: string): string {
    const text = urlText.trim();
    if (text.length === 0) {
      return '';
    }
    if (/^https?:\/\//i.test(text)) {
      return text;
    }
    const base = baseUrl.trim();
    if (!/^https?:\/\//i.test(base)) {
      return text;
    }
    const protocolMatch = base.match(/^(https?:)\/\//i);
    const hostMatch = base.match(/^(https?:\/\/[^/]+)/i);
    const protocol = protocolMatch && protocolMatch[1] ? protocolMatch[1] : 'https:';
    const host = hostMatch && hostMatch[1] ? hostMatch[1] : '';
    if (text.startsWith('//')) {
      return `${protocol}${text}`;
    }
    if (text.startsWith('/')) {
      return `${host}${text}`;
    }
    let baseDir = base;
    if (!base.endsWith('/')) {
      const lastSlash = base.lastIndexOf('/');
      if (host.length > 0 && lastSlash <= host.length - 1) {
        baseDir = `${host}/`;
      } else if (lastSlash > 0) {
        baseDir = base.substring(0, lastSlash + 1);
      } else {
        baseDir = `${host}/`;
      }
    }
    return `${baseDir}${text}`;
  }

  private stableHash(input: string): string {
    let hash = 0;
    for (let i = 0; i < input.length; i++) {
      hash = ((hash << 5) - hash) + input.charCodeAt(i);
      hash |= 0;
    }
    return `${Math.abs(hash)}`;
  }
}
