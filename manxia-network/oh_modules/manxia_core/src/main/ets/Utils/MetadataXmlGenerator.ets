/**
 * 元数据XML生成器
 * 用于生成漫画、电子书、小说的元数据XML文件
 */

import { logger } from './Logger';

const TAG = 'MetadataXmlGenerator';

/**
 * 漫画元数据接口
 */
export interface MangaMetadata {
  title: string;
  series?: string;
  author?: string;
  artist?: string;
  description?: string;
  genre?: string[];
  tags?: string[];
  status?: string;
  coverUrl?: string;
  sourceId?: string;
  sourceName?: string;
  url?: string;
  chapterCount?: number;
  lastUpdateTime?: number;
  isFavorite?: boolean;
  isPrivate?: boolean;
  isNSFW?: boolean;
}

/**
 * 电子书元数据接口
 */
export interface EBookMetadata {
  id: string;
  title: string;
  author?: string;
  publisher?: string;
  publishDate?: string;
  isbn?: string;
  language?: string;
  description?: string;
  format?: string;
  fileSize?: number;
  totalWordCount?: number;
  isFavorite?: boolean;
  isPrivate?: boolean;
}

/**
 * 小说元数据接口
 */
export interface NovelMetadata {
  id: string;
  name: string;
  author?: string;
  intro?: string;
  kind?: string;
  coverUrl?: string;
  sourceId?: string;
  sourceName?: string;
  bookUrl?: string;
  wordCount?: string | number;
  chapterCount?: number;
  isFavorite?: boolean;
  isPrivate?: boolean;
  isNSFW?: boolean;
}

/**
 * 元数据XML生成器类
 */
export class MetadataXmlGenerator {
  
  /**
   * 生成ComicInfo.xml内容（漫画元数据）
   * 遵循ComicInfo.xml标准格式
   */
  static generateComicInfoXml(metadata: MangaMetadata): string {
    const lines: string[] = [];
    lines.push('<?xml version="1.0" encoding="UTF-8"?>');
    lines.push('<ComicInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">');
    
    if (metadata.title) {
      lines.push(`  <Title>${MetadataXmlGenerator.escapeXml(metadata.title)}</Title>`);
    }
    if (metadata.series) {
      lines.push(`  <Series>${MetadataXmlGenerator.escapeXml(metadata.series)}</Series>`);
    }
    if (metadata.author) {
      lines.push(`  <Writer>${MetadataXmlGenerator.escapeXml(metadata.author)}</Writer>`);
    }
    if (metadata.artist) {
      lines.push(`  <Penciller>${MetadataXmlGenerator.escapeXml(metadata.artist)}</Penciller>`);
    }
    if (metadata.description) {
      lines.push(`  <Summary>${MetadataXmlGenerator.escapeXml(metadata.description)}</Summary>`);
    }
    if (metadata.genre && metadata.genre.length > 0) {
      lines.push(`  <Genre>${MetadataXmlGenerator.escapeXml(metadata.genre.join(', '))}</Genre>`);
    }
    if (metadata.tags && metadata.tags.length > 0) {
      lines.push(`  <Tags>${MetadataXmlGenerator.escapeXml(metadata.tags.join(', '))}</Tags>`);
    }
    if (metadata.status) {
      lines.push(`  <Status>${MetadataXmlGenerator.escapeXml(metadata.status)}</Status>`);
    }
    if (metadata.chapterCount !== undefined) {
      lines.push(`  <Count>${metadata.chapterCount}</Count>`);
    }
    
    // 自定义扩展字段（用于恢复时识别）
    lines.push('  <Notes>');
    lines.push(`    <SourceId>${MetadataXmlGenerator.escapeXml(metadata.sourceId || '')}</SourceId>`);
    lines.push(`    <SourceName>${MetadataXmlGenerator.escapeXml(metadata.sourceName || '')}</SourceName>`);
    lines.push(`    <Url>${MetadataXmlGenerator.escapeXml(metadata.url || '')}</Url>`);
    lines.push(`    <CoverUrl>${MetadataXmlGenerator.escapeXml(metadata.coverUrl || '')}</CoverUrl>`);
    lines.push(`    <LastUpdateTime>${metadata.lastUpdateTime || 0}</LastUpdateTime>`);
    lines.push(`    <IsFavorite>${metadata.isFavorite ? 'true' : 'false'}</IsFavorite>`);
    lines.push(`    <IsPrivate>${metadata.isPrivate ? 'true' : 'false'}</IsPrivate>`);
    lines.push(`    <IsNSFW>${metadata.isNSFW ? 'true' : 'false'}</IsNSFW>`);
    lines.push('  </Notes>');
    
    lines.push('</ComicInfo>');
    
    return lines.join('\n');
  }

  /**
   * 生成电子书元数据XML
   */
  static generateEBookMetadataXml(metadata: EBookMetadata): string {
    const lines: string[] = [];
    lines.push('<?xml version="1.0" encoding="UTF-8"?>');
    lines.push('<EBookInfo>');
    
    lines.push(`  <Id>${MetadataXmlGenerator.escapeXml(metadata.id)}</Id>`);
    lines.push(`  <Title>${MetadataXmlGenerator.escapeXml(metadata.title)}</Title>`);
    if (metadata.author) {
      lines.push(`  <Author>${MetadataXmlGenerator.escapeXml(metadata.author)}</Author>`);
    }
    if (metadata.publisher) {
      lines.push(`  <Publisher>${MetadataXmlGenerator.escapeXml(metadata.publisher)}</Publisher>`);
    }
    if (metadata.publishDate) {
      lines.push(`  <PublishDate>${MetadataXmlGenerator.escapeXml(metadata.publishDate)}</PublishDate>`);
    }
    if (metadata.isbn) {
      lines.push(`  <ISBN>${MetadataXmlGenerator.escapeXml(metadata.isbn)}</ISBN>`);
    }
    if (metadata.language) {
      lines.push(`  <Language>${MetadataXmlGenerator.escapeXml(metadata.language)}</Language>`);
    }
    if (metadata.description) {
      lines.push(`  <Description>${MetadataXmlGenerator.escapeXml(metadata.description)}</Description>`);
    }
    if (metadata.format) {
      lines.push(`  <Format>${MetadataXmlGenerator.escapeXml(metadata.format)}</Format>`);
    }
    if (metadata.fileSize !== undefined) {
      lines.push(`  <FileSize>${metadata.fileSize}</FileSize>`);
    }
    if (metadata.totalWordCount !== undefined) {
      lines.push(`  <TotalWordCount>${metadata.totalWordCount}</TotalWordCount>`);
    }
    lines.push(`  <IsFavorite>${metadata.isFavorite ? 'true' : 'false'}</IsFavorite>`);
    lines.push(`  <IsPrivate>${metadata.isPrivate ? 'true' : 'false'}</IsPrivate>`);
    
    lines.push('</EBookInfo>');
    
    return lines.join('\n');
  }

  /**
   * 生成小说元数据XML
   */
  static generateNovelMetadataXml(metadata: NovelMetadata): string {
    const lines: string[] = [];
    lines.push('<?xml version="1.0" encoding="UTF-8"?>');
    lines.push('<NovelInfo>');
    
    lines.push(`  <Id>${MetadataXmlGenerator.escapeXml(metadata.id)}</Id>`);
    lines.push(`  <Name>${MetadataXmlGenerator.escapeXml(metadata.name)}</Name>`);
    if (metadata.author) {
      lines.push(`  <Author>${MetadataXmlGenerator.escapeXml(metadata.author)}</Author>`);
    }
    if (metadata.intro) {
      lines.push(`  <Intro>${MetadataXmlGenerator.escapeXml(metadata.intro)}</Intro>`);
    }
    if (metadata.kind) {
      lines.push(`  <Kind>${MetadataXmlGenerator.escapeXml(metadata.kind)}</Kind>`);
    }
    if (metadata.coverUrl) {
      lines.push(`  <CoverUrl>${MetadataXmlGenerator.escapeXml(metadata.coverUrl)}</CoverUrl>`);
    }
    if (metadata.sourceId) {
      lines.push(`  <SourceId>${MetadataXmlGenerator.escapeXml(metadata.sourceId)}</SourceId>`);
    }
    if (metadata.sourceName) {
      lines.push(`  <SourceName>${MetadataXmlGenerator.escapeXml(metadata.sourceName)}</SourceName>`);
    }
    if (metadata.bookUrl) {
      lines.push(`  <BookUrl>${MetadataXmlGenerator.escapeXml(metadata.bookUrl)}</BookUrl>`);
    }
    if (metadata.wordCount !== undefined) {
      lines.push(`  <WordCount>${metadata.wordCount}</WordCount>`);
    }
    if (metadata.chapterCount !== undefined) {
      lines.push(`  <ChapterCount>${metadata.chapterCount}</ChapterCount>`);
    }
    lines.push(`  <IsFavorite>${metadata.isFavorite ? 'true' : 'false'}</IsFavorite>`);
    lines.push(`  <IsPrivate>${metadata.isPrivate ? 'true' : 'false'}</IsPrivate>`);
    lines.push(`  <IsNSFW>${metadata.isNSFW ? 'true' : 'false'}</IsNSFW>`);
    
    lines.push('</NovelInfo>');
    
    return lines.join('\n');
  }

  /**
   * 解析ComicInfo.xml内容
   */
  static parseComicInfoXml(xmlContent: string): MangaMetadata | null {
    try {
      const getTagValue = (tagName: string): string => {
        const regex = new RegExp(`<${tagName}>([\\s\\S]*?)</${tagName}>`, 'i');
        const match = xmlContent.match(regex);
        return match ? MetadataXmlGenerator.unescapeXml(match[1].trim()) : '';
      };

      const metadata: MangaMetadata = {
        title: getTagValue('Title') || getTagValue('Series'),
        series: getTagValue('Series'),
        author: getTagValue('Writer'),
        artist: getTagValue('Penciller'),
        description: getTagValue('Summary'),
        genre: getTagValue('Genre').split(',').map(g => g.trim()).filter(g => g),
        tags: getTagValue('Tags').split(',').map(t => t.trim()).filter(t => t),
        status: getTagValue('Status'),
        sourceId: getTagValue('SourceId'),
        sourceName: getTagValue('SourceName'),
        url: getTagValue('Url'),
        coverUrl: getTagValue('CoverUrl'),
        isFavorite: getTagValue('IsFavorite') === 'true',
        isPrivate: getTagValue('IsPrivate') === 'true',
        isNSFW: getTagValue('IsNSFW') === 'true'
      };

      const countStr = getTagValue('Count');
      if (countStr) {
        metadata.chapterCount = parseInt(countStr, 10);
      }

      const lastUpdateStr = getTagValue('LastUpdateTime');
      if (lastUpdateStr) {
        metadata.lastUpdateTime = parseInt(lastUpdateStr, 10);
      }

      return metadata;
    } catch (error) {
      logger.error(TAG, `解析ComicInfo.xml失败: ${error}`);
      return null;
    }
  }

  /**
   * 解析电子书元数据XML
   */
  static parseEBookMetadataXml(xmlContent: string): EBookMetadata | null {
    try {
      const getTagValue = (tagName: string): string => {
        const regex = new RegExp(`<${tagName}>([\\s\\S]*?)</${tagName}>`, 'i');
        const match = xmlContent.match(regex);
        return match ? MetadataXmlGenerator.unescapeXml(match[1].trim()) : '';
      };

      const metadata: EBookMetadata = {
        id: getTagValue('Id'),
        title: getTagValue('Title'),
        author: getTagValue('Author'),
        publisher: getTagValue('Publisher'),
        publishDate: getTagValue('PublishDate'),
        isbn: getTagValue('ISBN'),
        language: getTagValue('Language'),
        description: getTagValue('Description'),
        format: getTagValue('Format'),
        isFavorite: getTagValue('IsFavorite') === 'true',
        isPrivate: getTagValue('IsPrivate') === 'true'
      };

      const fileSizeStr = getTagValue('FileSize');
      if (fileSizeStr) {
        metadata.fileSize = parseInt(fileSizeStr, 10);
      }

      const wordCountStr = getTagValue('TotalWordCount');
      if (wordCountStr) {
        metadata.totalWordCount = parseInt(wordCountStr, 10);
      }

      return metadata;
    } catch (error) {
      logger.error(TAG, `解析电子书元数据XML失败: ${error}`);
      return null;
    }
  }

  /**
   * 解析小说元数据XML
   */
  static parseNovelMetadataXml(xmlContent: string): NovelMetadata | null {
    try {
      const getTagValue = (tagName: string): string => {
        const regex = new RegExp(`<${tagName}>([\\s\\S]*?)</${tagName}>`, 'i');
        const match = xmlContent.match(regex);
        return match ? MetadataXmlGenerator.unescapeXml(match[1].trim()) : '';
      };

      const metadata: NovelMetadata = {
        id: getTagValue('Id'),
        name: getTagValue('Name'),
        author: getTagValue('Author'),
        intro: getTagValue('Intro'),
        kind: getTagValue('Kind'),
        coverUrl: getTagValue('CoverUrl'),
        sourceId: getTagValue('SourceId'),
        sourceName: getTagValue('SourceName'),
        bookUrl: getTagValue('BookUrl'),
        isFavorite: getTagValue('IsFavorite') === 'true',
        isPrivate: getTagValue('IsPrivate') === 'true',
        isNSFW: getTagValue('IsNSFW') === 'true'
      };

      const wordCountStr = getTagValue('WordCount');
      if (wordCountStr) {
        metadata.wordCount = parseInt(wordCountStr, 10);
      }

      const chapterCountStr = getTagValue('ChapterCount');
      if (chapterCountStr) {
        metadata.chapterCount = parseInt(chapterCountStr, 10);
      }

      return metadata;
    } catch (error) {
      logger.error(TAG, `解析小说元数据XML失败: ${error}`);
      return null;
    }
  }

  /**
   * XML特殊字符转义
   */
  private static escapeXml(text: string): string {
    if (!text) return '';
    return text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&apos;');
  }

  /**
   * XML特殊字符反转义
   */
  private static unescapeXml(text: string): string {
    if (!text) return '';
    return text
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&apos;/g, "'");
  }
}
