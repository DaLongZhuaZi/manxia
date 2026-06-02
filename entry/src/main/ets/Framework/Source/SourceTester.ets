import { SafeUtils } from '../../Utils/SafeUtils';
/**
 * 图源测试器
 * 测试图源的各项功能是否正常工作
 */

import { logger } from '../../Utils/Logger';
import { SourceExecutor } from './SourceExecutor';

const TAG = 'SourceTester';

/**
 * 测试结果
 */
export interface TestResult {
  sourceId: number;
  sourceName: string;
  success: boolean;
  totalTests: number;
  passedTests: number;
  failedTests: number;
  tests: TestItemResult[];
  duration: number;
  timestamp: number;
}

/**
 * 单项测试结果
 */
export interface TestItemResult {
  name: string;
  feature: string;
  success: boolean;
  duration: number;
  error?: string;
  details?: string;
}

/**
 * 图源测试器类
 */
export class SourceTester {
  private executor: SourceExecutor;

  constructor() {
    this.executor = new SourceExecutor();
  }

  /**
   * 测试图源
   */
  async testSource(sourceId: number, sourceName: string): Promise<TestResult> {
    const startTime = Date.now();
    const tests: TestItemResult[] = [];

    logger.info(TAG, `开始测试图源: ${sourceName} (ID: ${sourceId})`);

    // 测试热门列表
    tests.push(await this.testPopular(sourceId));

    // 测试最新更新
    tests.push(await this.testLatest(sourceId));

    // 测试搜索
    tests.push(await this.testSearch(sourceId));

    // 测试详情（如果前面的测试成功）
    const popularTest = tests[0];
    if (popularTest.success && popularTest.details) {
      const comicId = this.extractComicId(popularTest.details);
      if (comicId) {
        tests.push(await this.testDetail(sourceId, comicId));
      }
    }

    // 统计结果
    const passedTests = tests.filter((t: TestItemResult) => t.success).length;
    const failedTests = tests.length - passedTests;
    const duration = Date.now() - startTime;

    const result: TestResult = {
      sourceId: sourceId,
      sourceName: sourceName,
      success: failedTests === 0,
      totalTests: tests.length,
      passedTests: passedTests,
      failedTests: failedTests,
      tests: tests,
      duration: duration,
      timestamp: Date.now()
    };

    logger.info(TAG, `测试完成: ${sourceName}, 通过: ${passedTests}/${tests.length}, 耗时: ${duration}ms`);

    return result;
  }

  /**
   * 测试热门列表
   */
  private async testPopular(sourceId: number): Promise<TestItemResult> {
    const startTime = Date.now();
    
    try {
      const comics = await this.executor.getPopular(sourceId, 1, 5);
      
      if (!comics || comics.length === 0) {
        return {
          name: '热门列表',
          feature: 'popular',
          success: false,
          duration: Date.now() - startTime,
          error: '返回结果为空'
        };
      }

      // 验证数据结构
      const firstComic = comics[0];
      if (!firstComic.id || !firstComic.title) {
        return {
          name: '热门列表',
          feature: 'popular',
          success: false,
          duration: Date.now() - startTime,
          error: '数据结构不完整'
        };
      }

      return {
        name: '热门列表',
        feature: 'popular',
        success: true,
        duration: Date.now() - startTime,
        details: JSON.stringify({ count: comics.length, firstId: firstComic.id })
      };
    } catch (error) {
      return {
        name: '热门列表',
        feature: 'popular',
        success: false,
        duration: Date.now() - startTime,
        error: String(error)
      };
    }
  }

  /**
   * 测试最新更新
   */
  private async testLatest(sourceId: number): Promise<TestItemResult> {
    const startTime = Date.now();
    
    try {
      const comics = await this.executor.getLatest(sourceId, 1, 5);
      
      if (!comics || comics.length === 0) {
        return {
          name: '最新更新',
          feature: 'latest',
          success: false,
          duration: Date.now() - startTime,
          error: '返回结果为空'
        };
      }

      return {
        name: '最新更新',
        feature: 'latest',
        success: true,
        duration: Date.now() - startTime,
        details: JSON.stringify({ count: comics.length })
      };
    } catch (error) {
      return {
        name: '最新更新',
        feature: 'latest',
        success: false,
        duration: Date.now() - startTime,
        error: String(error)
      };
    }
  }

  /**
   * 测试搜索
   */
  private async testSearch(sourceId: number): Promise<TestItemResult> {
    const startTime = Date.now();
    
    try {
      const comics = await this.executor.search(sourceId, '测试', 1, 5);
      
      // 搜索可能返回空结果，这是正常的
      return {
        name: '搜索功能',
        feature: 'search',
        success: true,
        duration: Date.now() - startTime,
        details: JSON.stringify({ count: comics.length })
      };
    } catch (error) {
      return {
        name: '搜索功能',
        feature: 'search',
        success: false,
        duration: Date.now() - startTime,
        error: String(error)
      };
    }
  }

  /**
   * 测试详情
   */
  private async testDetail(sourceId: number, comicId: string): Promise<TestItemResult> {
    const startTime = Date.now();
    
    try {
      const detail = await this.executor.getDetail(sourceId, comicId);
      
      if (!detail.id || !detail.title) {
        return {
          name: '漫画详情',
          feature: 'detail',
          success: false,
          duration: Date.now() - startTime,
          error: '数据结构不完整'
        };
      }

      return {
        name: '漫画详情',
        feature: 'detail',
        success: true,
        duration: Date.now() - startTime,
        details: JSON.stringify({ 
          hasChapters: detail.chapters && detail.chapters.length > 0,
          chapterCount: detail.chapters?.length || 0
        })
      };
    } catch (error) {
      return {
        name: '漫画详情',
        feature: 'detail',
        success: false,
        duration: Date.now() - startTime,
        error: String(error)
      };
    }
  }

  /**
   * 从测试详情中提取漫画ID
   */
  private extractComicId(details: string): string | null {
    try {
      const data: ESObject = SafeUtils.parseObj(details) as ESObject;
      return data.firstId as string || null;
    } catch {
      return null;
    }
  }

  /**
   * 生成测试报告
   */
  generateReport(result: TestResult): string {
    let report = `图源测试报告\n`;
    report += `================\n`;
    report += `图源: ${result.sourceName} (ID: ${result.sourceId})\n`;
    report += `状态: ${result.success ? '✅ 通过' : '❌ 失败'}\n`;
    report += `测试项: ${result.passedTests}/${result.totalTests} 通过\n`;
    report += `耗时: ${result.duration}ms\n`;
    report += `时间: ${new Date(result.timestamp).toLocaleString()}\n`;
    report += `\n详细结果:\n`;

    for (const test of result.tests) {
      report += `\n${test.success ? '✅' : '❌'} ${test.name} (${test.feature})\n`;
      report += `   耗时: ${test.duration}ms\n`;
      if (test.error) {
        report += `   错误: ${test.error}\n`;
      }
      if (test.details) {
        report += `   详情: ${test.details}\n`;
      }
    }

    return report;
  }
}
