// 文件路径: entry/src/main/ets/Framework/Parsers/ParserInitializer.ets
// 职责: 初始化所有电子书解析器

import { EBookParserFactory } from './EBookParser';
import { TxtParser } from './TxtParser';
import { EpubParser } from './EpubParser';
import { GenericEBookParser } from './GenericEBookParser';
import { EBookFormat } from '../../Models/EBookModels';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG = 'ParserInitializer';

/**
 * 初始化所有电子书解析器
 */
export function initializeEBookParsers(): void {
  try {
    // 注册TXT解析器
    EBookParserFactory.registerParser(EBookFormat.TXT, new TxtParser());

    // 注册EPUB解析器
    EBookParserFactory.registerParser(EBookFormat.EPUB, new EpubParser());

    // 注册MOBI解析器（占位符）
    EBookParserFactory.registerParser(EBookFormat.MOBI, new GenericEBookParser(EBookFormat.MOBI));

    // 注册AZW解析器（占位符）
    EBookParserFactory.registerParser(EBookFormat.AZW, new GenericEBookParser(EBookFormat.AZW));

    // 注册AZW3解析器（占位符）
    EBookParserFactory.registerParser(EBookFormat.AZW3, new GenericEBookParser(EBookFormat.AZW3));

    // 注册PDF解析器（占位符）
    EBookParserFactory.registerParser(EBookFormat.PDF, new GenericEBookParser(EBookFormat.PDF));

    logger.info(TAG, '电子书解析器初始化完成');
  } catch (error) {
    logger.error(TAG, `电子书解析器初始化失败: ${String(error)}`);
  }
}

