import { MangaSourceConfigParser, ParseResult } from '../WebView/MangaSourceConfigParser';
import { SourceValidationResult } from './SourceEditorTypes';

export class SourceConfigValidator {
  private parser: MangaSourceConfigParser = new MangaSourceConfigParser();

  public validate(jsonContent: string): SourceValidationResult {
    const result: ParseResult = this.parser.parseConfig(jsonContent);
    if (!result.success) {
      const failure: SourceValidationResult = {
        valid: false,
        message: result.error || '图源配置校验失败',
        warnings: []
      };
      return failure;
    }
    const success: SourceValidationResult = {
      valid: true,
      message: '图源配置校验通过',
      warnings: result.warnings ? result.warnings : []
    };
    return success;
  }
}

