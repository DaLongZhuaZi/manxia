/**
 * Streaming JSON document reader for large Legado source packages.
 *
 * The reader deliberately emits each top-level source object as its original
 * JSON text.  It never materializes a dynamic ArkTS object, so the V2 import
 * compiler remains the sole authority for parsing, hashing and persistence.
 */

import { fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';
import { SafeFileUtils } from 'manxia_core/src/main/ets/Utils/SafeFileUtils';

const TAG = 'LargeFileJSONParser';

export interface ParseProgressCallback {
  onFileProgress?: (bytesRead: number, totalBytes: number) => void;
  onDocumentParsed?: (parsedCount: number, rawDocument: string) => Promise<void>;
  onBatchComplete?: (batchIndex: number, batchSize: number, totalParsed: number) => void;
  onError?: (error: string, recoverable: boolean) => void;
}

export interface ParseConfig {
  chunkSize?: number;
  batchSize?: number;
  batchDelayMs?: number;
  maxObjectSize?: number;
}

interface ResolvedParseConfig {
  chunkSize: number;
  batchSize: number;
  batchDelayMs: number;
  maxObjectSize: number;
}

export interface ParseResult {
  success: boolean;
  totalParsed: number;
  errors: string[];
  elapsedMs: number;
}

enum JsonRootState {
  INITIAL = 0,
  ARRAY_EXPECT_FIRST_VALUE = 1,
  ARRAY_EXPECT_VALUE = 2,
  ARRAY_EXPECT_DELIMITER = 3,
  ARRAY_COMPLETE = 4,
  SINGLE_EXPECT_END = 5
}

class EmptyParseProgressCallback implements ParseProgressCallback {}

/**
 * Keeps raw source text and an exact UTF-8 byte count while scanning one
 * document.  Surrogate pairs are counted as one four-byte UTF-8 sequence.
 */
class RawJsonDocumentBuffer {
  private rawDocument: string = '';
  private byteLength: number = 0;
  private hasPendingHighSurrogate: boolean = false;

  begin(): void {
    this.rawDocument = '{';
    this.byteLength = 1;
    this.hasPendingHighSurrogate = false;
  }

  append(character: string): void {
    this.rawDocument += character;
    this.byteLength += this.getUtf8ByteIncrement(character);
  }

  getRawDocument(): string {
    return this.rawDocument;
  }

  getByteLength(): number {
    return this.byteLength;
  }

  clear(): void {
    this.rawDocument = '';
    this.byteLength = 0;
    this.hasPendingHighSurrogate = false;
  }

  private getUtf8ByteIncrement(character: string): number {
    const codeUnit = character.charCodeAt(0);
    if (this.hasPendingHighSurrogate) {
      this.hasPendingHighSurrogate = false;
      if (codeUnit >= 0xDC00 && codeUnit <= 0xDFFF) {
        // The preceding high surrogate was provisionally counted as three
        // bytes; a complete pair is four bytes in UTF-8.
        return 1;
      }
    }
    if (codeUnit <= 0x7F) {
      return 1;
    }
    if (codeUnit <= 0x7FF) {
      return 2;
    }
    if (codeUnit >= 0xD800 && codeUnit <= 0xDBFF) {
      this.hasPendingHighSurrogate = true;
    }
    return 3;
  }
}

/**
 * Reads a JSON object or an array of JSON objects without decoding a chunk as
 * Latin-1.  `TextDecoder` is kept in streaming mode so a UTF-8 sequence split
 * between two file reads remains intact.
 */
export class LargeFileJSONParser {
  private static readonly DEFAULT_CONFIG: ResolvedParseConfig = {
    chunkSize: 512 * 1024,
    batchSize: 50,
    batchDelayMs: 10,
    maxObjectSize: 1024 * 1024
  };

  private readonly config: ResolvedParseConfig;
  private readonly callback: ParseProgressCallback;

  constructor(config?: ParseConfig, callback?: ParseProgressCallback) {
    this.config = {
      chunkSize: config?.chunkSize ?? LargeFileJSONParser.DEFAULT_CONFIG.chunkSize,
      batchSize: config?.batchSize ?? LargeFileJSONParser.DEFAULT_CONFIG.batchSize,
      batchDelayMs: config?.batchDelayMs ?? LargeFileJSONParser.DEFAULT_CONFIG.batchDelayMs,
      maxObjectSize: config?.maxObjectSize ?? LargeFileJSONParser.DEFAULT_CONFIG.maxObjectSize
    };
    this.callback = callback ?? new EmptyParseProgressCallback();
  }

  async parseFromFile(filePath: string): Promise<ParseResult> {
    const startTime = Date.now();
    const result: ParseResult = {
      success: false,
      totalParsed: 0,
      errors: [],
      elapsedMs: 0
    };
    let file: fs.File | null = null;

    try {
      // A DocumentViewPicker or file-association Want can supply a temporary
      // `file://docs` grant.  Such URIs must be opened exactly once and then
      // streamed through that FD; converting them to a path, or stat'ing the
      // URI before opening it, can consume or bypass the grant.
      const isGrantedUri = filePath.includes('://');
      if (isGrantedUri) {
        file = SafeFileUtils.openSyncStrict(filePath, fs.OpenMode.READ_ONLY);
      }
      const stat = isGrantedUri && file !== null
        ? SafeFileUtils.statSyncStrict(file.fd)
        : SafeFileUtils.statSyncStrict(filePath);
      const totalSize = stat.size;
      if (totalSize <= 0) {
        throw new Error('书源文件为空或无法读取文件大小。');
      }
      logger.info(TAG, `开始流式读取书源文件: ${this.formatSize(totalSize)}`);
      if (file === null) {
        file = SafeFileUtils.openSync(filePath, fs.OpenMode.READ_ONLY);
      }
      await this.parseFileStream(file, totalSize, result);
      result.success = true;
    } catch (error) {
      const errorMessage = `文件解析失败: ${String(error)}`;
      result.errors.push(errorMessage);
      this.callback.onError?.(errorMessage, false);
      logger.error(TAG, errorMessage);
    } finally {
      if (file !== null) {
        SafeFileUtils.closeSync(file);
      }
      result.elapsedMs = Date.now() - startTime;
    }

    logger.info(
      TAG,
      `流式读取完成: documents=${result.totalParsed}, elapsedMs=${result.elapsedMs}, errors=${result.errors.length}`
    );
    return result;
  }

  private async parseFileStream(file: fs.File, totalSize: number, result: ParseResult): Promise<void> {
    const buffer = new ArrayBuffer(this.config.chunkSize);
    const decoder = util.TextDecoder.create('utf-8', {
      ignoreBOM: true,
      fatal: true
    });
    const documentBuffer = new RawJsonDocumentBuffer();
    let bytesRead = 0;
    let rootState: JsonRootState = JsonRootState.INITIAL;
    let braceDepth = 0;
    let inString = false;
    let escapeNext = false;
    let batchSize = 0;
    let batchIndex = 0;

    while (bytesRead < totalSize) {
      // `readSync` advances the file pointer. Supplying the accumulated byte
      // count as an offset would skip every subsequent chunk.
      const readLength = SafeFileUtils.readSync(file.fd, buffer);
      if (readLength <= 0) {
        break;
      }
      bytesRead += readLength;
      this.callback.onFileProgress?.(bytesRead, totalSize);
      const bytes = new Uint8Array(buffer, 0, readLength);
      const decodedChunk: string = decoder.decodeToString(bytes, { stream: true });
      const streamState: StreamParserState = await this.consumeChunk(
        decodedChunk,
        documentBuffer,
        rootState,
        braceDepth,
        inString,
        escapeNext,
        batchSize,
        batchIndex,
        result
      );
      rootState = streamState.rootState;
      braceDepth = streamState.braceDepth;
      inString = streamState.inString;
      escapeNext = streamState.escapeNext;
      batchSize = streamState.batchSize;
      batchIndex = streamState.batchIndex;
    }

    const trailingChunk: string = decoder.decodeToString(new Uint8Array(0), { stream: false });
    if (trailingChunk.length > 0) {
      const streamState: StreamParserState = await this.consumeChunk(
        trailingChunk,
        documentBuffer,
        rootState,
        braceDepth,
        inString,
        escapeNext,
        batchSize,
        batchIndex,
        result
      );
      rootState = streamState.rootState;
      braceDepth = streamState.braceDepth;
      inString = streamState.inString;
      escapeNext = streamState.escapeNext;
      batchSize = streamState.batchSize;
      batchIndex = streamState.batchIndex;
    }

    if (bytesRead !== totalSize) {
      throw new Error(`文件读取不完整: expected=${totalSize}, actual=${bytesRead}`);
    }
    this.validateCompletedStream(rootState, braceDepth, inString, escapeNext);
    if (batchSize > 0) {
      this.callback.onBatchComplete?.(batchIndex, batchSize, result.totalParsed);
    }
  }

  private async consumeChunk(
    chunk: string,
    documentBuffer: RawJsonDocumentBuffer,
    initialRootState: JsonRootState,
    initialBraceDepth: number,
    initialInString: boolean,
    initialEscapeNext: boolean,
    initialBatchSize: number,
    initialBatchIndex: number,
    result: ParseResult
  ): Promise<StreamParserState> {
    let rootState = initialRootState;
    let braceDepth = initialBraceDepth;
    let inString = initialInString;
    let escapeNext = initialEscapeNext;
    let batchSize = initialBatchSize;
    let batchIndex = initialBatchIndex;

    for (let index = 0; index < chunk.length; index++) {
      const character = chunk.charAt(index);
      if (braceDepth === 0) {
        const outsideState = this.consumeOutsideDocument(character, rootState, documentBuffer);
        rootState = outsideState.rootState;
        braceDepth = outsideState.braceDepth;
        inString = outsideState.inString;
        escapeNext = outsideState.escapeNext;
        continue;
      }

      documentBuffer.append(character);
      if (documentBuffer.getByteLength() > this.config.maxObjectSize) {
        throw new Error(`单个书源原始 JSON 超过限制: ${this.formatSize(documentBuffer.getByteLength())}`);
      }

      if (inString) {
        if (escapeNext) {
          escapeNext = false;
        } else if (character === '\\') {
          escapeNext = true;
        } else if (character === '"') {
          inString = false;
        }
        continue;
      }

      if (character === '"') {
        inString = true;
        continue;
      }
      if (character === '{') {
        braceDepth++;
        continue;
      }
      if (character === '}') {
        braceDepth--;
        if (braceDepth < 0) {
          throw new Error('JSON 对象括号层级无效。');
        }
        if (braceDepth === 0) {
          result.totalParsed++;
          const rawDocument = documentBuffer.getRawDocument();
          const documentCallback = this.callback.onDocumentParsed;
          if (documentCallback !== undefined) {
            await documentCallback(result.totalParsed, rawDocument);
          }
          documentBuffer.clear();
          batchSize++;
          if (batchSize >= this.config.batchSize) {
            this.callback.onBatchComplete?.(batchIndex, batchSize, result.totalParsed);
            batchSize = 0;
            batchIndex++;
            await this.sleep(this.config.batchDelayMs);
          }
        }
      }
    }

    return new StreamParserState(rootState, braceDepth, inString, escapeNext, batchSize, batchIndex);
  }

  private consumeOutsideDocument(
    character: string,
    currentState: JsonRootState,
    documentBuffer: RawJsonDocumentBuffer
  ): OutsideDocumentState {
    if (this.isTopLevelWhitespace(character)) {
      return new OutsideDocumentState(currentState, 0, false, false);
    }
    switch (currentState) {
      case JsonRootState.INITIAL:
        if (character === '[') {
          return new OutsideDocumentState(JsonRootState.ARRAY_EXPECT_FIRST_VALUE, 0, false, false);
        }
        if (character === '{') {
          documentBuffer.begin();
          return new OutsideDocumentState(JsonRootState.SINGLE_EXPECT_END, 1, false, false);
        }
        break;
      case JsonRootState.ARRAY_EXPECT_FIRST_VALUE:
        if (character === ']') {
          return new OutsideDocumentState(JsonRootState.ARRAY_COMPLETE, 0, false, false);
        }
        if (character === '{') {
          documentBuffer.begin();
          return new OutsideDocumentState(JsonRootState.ARRAY_EXPECT_DELIMITER, 1, false, false);
        }
        break;
      case JsonRootState.ARRAY_EXPECT_VALUE:
        if (character === '{') {
          documentBuffer.begin();
          return new OutsideDocumentState(JsonRootState.ARRAY_EXPECT_DELIMITER, 1, false, false);
        }
        break;
      case JsonRootState.ARRAY_EXPECT_DELIMITER:
        if (character === ',') {
          return new OutsideDocumentState(JsonRootState.ARRAY_EXPECT_VALUE, 0, false, false);
        }
        if (character === ']') {
          return new OutsideDocumentState(JsonRootState.ARRAY_COMPLETE, 0, false, false);
        }
        break;
      case JsonRootState.ARRAY_COMPLETE:
      case JsonRootState.SINGLE_EXPECT_END:
        break;
    }
    throw new Error(`书源 JSON 顶层结构无效: ${character}`);
  }

  /**
   * `TextDecoder` normally consumes a leading UTF-8 BOM when ignoreBOM is
   * enabled, but the scanner also accepts it explicitly.  This keeps the
   * top-level grammar correct on implementations that surface U+FEFF.
   */
  private isTopLevelWhitespace(character: string): boolean {
    return character <= ' ' || character === '\uFEFF';
  }

  private validateCompletedStream(
    rootState: JsonRootState,
    braceDepth: number,
    inString: boolean,
    escapeNext: boolean
  ): void {
    if (braceDepth !== 0 || inString || escapeNext) {
      throw new Error('JSON 文档在文件结尾处不完整。');
    }
    if (rootState === JsonRootState.INITIAL ||
      rootState === JsonRootState.ARRAY_EXPECT_FIRST_VALUE ||
      rootState === JsonRootState.ARRAY_EXPECT_VALUE ||
      rootState === JsonRootState.ARRAY_EXPECT_DELIMITER) {
      throw new Error('书源 JSON 顶层数组未正确结束。');
    }
  }

  private sleep(delayMs: number): Promise<void> {
    return new Promise<void>((resolve: () => void): void => {
      setTimeout(resolve, delayMs);
    });
  }

  private formatSize(bytes: number): string {
    if (bytes < 1024) {
      return `${bytes}B`;
    }
    if (bytes < 1024 * 1024) {
      return `${(bytes / 1024).toFixed(1)}KB`;
    }
    return `${(bytes / 1024 / 1024).toFixed(1)}MB`;
  }

  static async parseFile(
    filePath: string,
    config?: ParseConfig,
    callback?: ParseProgressCallback
  ): Promise<ParseResult> {
    const parser = new LargeFileJSONParser(config, callback);
    return parser.parseFromFile(filePath);
  }

  /**
   * Test-only streaming entrypoint. It drives the exact decoder and scanner
   * used by parseFromFile while allowing a conformance test to place a UTF-8
   * character on a deterministic chunk boundary without requiring a fixture
   * file provider. Production imports must use parseFile.
   */
  static async parseUtf8ChunksForConformance(
    bytes: Uint8Array,
    chunkSize: number
  ): Promise<string[]> {
    if (chunkSize <= 0) {
      throw new Error('Conformance chunk size must be greater than zero.');
    }
    const documents: string[] = [];
    const callback: ParseProgressCallback = {
      onDocumentParsed: async (_parsedCount: number, rawDocument: string): Promise<void> => {
        documents.push(rawDocument);
      }
    };
    const parser = new LargeFileJSONParser({
      chunkSize: chunkSize,
      batchSize: Number.MAX_SAFE_INTEGER,
      batchDelayMs: 0,
      maxObjectSize: Math.max(bytes.length * 2, 1024)
    }, callback);
    const decoder = util.TextDecoder.create('utf-8', {
      ignoreBOM: true,
      fatal: true
    });
    const documentBuffer = new RawJsonDocumentBuffer();
    const result: ParseResult = {
      success: false,
      totalParsed: 0,
      errors: [],
      elapsedMs: 0
    };
    let rootState: JsonRootState = JsonRootState.INITIAL;
    let braceDepth = 0;
    let inString = false;
    let escapeNext = false;
    let batchSize = 0;
    let batchIndex = 0;

    for (let offset = 0; offset < bytes.length; offset += chunkSize) {
      const end = Math.min(offset + chunkSize, bytes.length);
      const chunk = bytes.slice(offset, end);
      const decodedChunk: string = decoder.decodeToString(chunk, { stream: true });
      const streamState: StreamParserState = await parser.consumeChunk(
        decodedChunk,
        documentBuffer,
        rootState,
        braceDepth,
        inString,
        escapeNext,
        batchSize,
        batchIndex,
        result
      );
      rootState = streamState.rootState;
      braceDepth = streamState.braceDepth;
      inString = streamState.inString;
      escapeNext = streamState.escapeNext;
      batchSize = streamState.batchSize;
      batchIndex = streamState.batchIndex;
    }

    const trailingChunk: string = decoder.decodeToString(new Uint8Array(0), { stream: false });
    if (trailingChunk.length > 0) {
      const streamState: StreamParserState = await parser.consumeChunk(
        trailingChunk,
        documentBuffer,
        rootState,
        braceDepth,
        inString,
        escapeNext,
        batchSize,
        batchIndex,
        result
      );
      rootState = streamState.rootState;
      braceDepth = streamState.braceDepth;
      inString = streamState.inString;
      escapeNext = streamState.escapeNext;
    }
    parser.validateCompletedStream(rootState, braceDepth, inString, escapeNext);
    return documents;
  }
}

class OutsideDocumentState {
  readonly rootState: JsonRootState;
  readonly braceDepth: number;
  readonly inString: boolean;
  readonly escapeNext: boolean;

  constructor(rootState: JsonRootState, braceDepth: number, inString: boolean, escapeNext: boolean) {
    this.rootState = rootState;
    this.braceDepth = braceDepth;
    this.inString = inString;
    this.escapeNext = escapeNext;
  }
}

class StreamParserState {
  readonly rootState: JsonRootState;
  readonly braceDepth: number;
  readonly inString: boolean;
  readonly escapeNext: boolean;
  readonly batchSize: number;
  readonly batchIndex: number;

  constructor(
    rootState: JsonRootState,
    braceDepth: number,
    inString: boolean,
    escapeNext: boolean,
    batchSize: number,
    batchIndex: number
  ) {
    this.rootState = rootState;
    this.braceDepth = braceDepth;
    this.inString = inString;
    this.escapeNext = escapeNext;
    this.batchSize = batchSize;
    this.batchIndex = batchIndex;
  }
}
