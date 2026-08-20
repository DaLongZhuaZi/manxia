/**
 * WebDAV Native Module 测试工具
 * 用于验证Native C++ WebDAV客户端是否正常工作
 * 
 * 文件路径: entry/src/main/ets/Framework/WebDAV/WebDAVNativeTest.ets
 */

import { WebDAVNativeClient, WebDAVNativeConfig, createWebDAVNativeClient } from './WebDAVNativeClient';
import { logger } from 'manxia_core/src/main/ets/Utils/Logger';

const TAG = 'WebDAVNativeTest';

/**
 * 测试结果接口
 */
export interface TestResult {
  testName: string;
  success: boolean;
  message: string;
  duration: number;
}

/**
 * WebDAV Native模块测试类
 */
export class WebDAVNativeTest {
  private client: WebDAVNativeClient | null = null;
  private testResults: TestResult[] = [];

  /**
   * 初始化测试客户端
   */
  async initClient(config: WebDAVNativeConfig): Promise<boolean> {
    try {
      logger.info(TAG, '初始化测试客户端...');
      this.client = createWebDAVNativeClient(config);
      const result = await this.client.initialize();
      logger.info(TAG, `客户端初始化结果: ${result}`);
      return result;
    } catch (error) {
      logger.error(TAG, `初始化失败: ${error}`);
      return false;
    }
  }

  /**
   * 运行所有测试
   */
  async runAllTests(): Promise<TestResult[]> {
    this.testResults = [];

    if (!this.client) {
      logger.error(TAG, '客户端未初始化');
      return this.testResults;
    }

    // 测试1: 连接测试
    await this.runTest('连接测试', async () => {
      const result = await this.client!.testConnection();
      if (!result.success) {
        throw new Error(result.message);
      }
      return `连接成功: ${result.message}`;
    });

    // 测试2: 目录列表
    await this.runTest('目录列表', async () => {
      const files = await this.client!.list('');
      return `获取到 ${files.length} 个文件/目录`;
    });

    // 测试3: 创建测试目录
    const testDir = `_webdav_test_${Date.now()}`;
    await this.runTest('创建目录', async () => {
      const result = await this.client!.createDirectory(testDir);
      if (!result.success) {
        throw new Error(result.message);
      }
      return `目录创建成功: ${testDir}`;
    });

    // 测试4: 检查目录是否存在
    await this.runTest('检查存在', async () => {
      const exists = await this.client!.exists(testDir);
      if (!exists) {
        throw new Error('目录不存在');
      }
      return '目录存在检查通过';
    });

    // 测试5: 上传文件
    const testFile = `${testDir}/test.txt`;
    const testContent = `WebDAV Native Test - ${new Date().toISOString()}`;
    await this.runTest('上传文件', async () => {
      const result = await this.client!.putFileContents(testFile, testContent);
      if (!result.success) {
        throw new Error(result.message);
      }
      return `文件上传成功: ${testFile}`;
    });

    // 测试6: 下载文件
    await this.runTest('下载文件', async () => {
      const content = await this.client!.getFileContents(testFile);
      if (content !== testContent) {
        throw new Error(`内容不匹配: 期望 "${testContent}", 实际 "${content}"`);
      }
      return `文件下载成功，内容匹配`;
    });

    // 测试7: 删除文件
    await this.runTest('删除文件', async () => {
      const result = await this.client!.deleteFile(testFile);
      if (!result.success) {
        throw new Error(result.message);
      }
      return '文件删除成功';
    });

    // 测试8: 删除测试目录
    await this.runTest('删除目录', async () => {
      const result = await this.client!.deleteFile(testDir);
      if (!result.success) {
        throw new Error(result.message);
      }
      return '目录删除成功';
    });

    // 测试9: 获取配额信息
    await this.runTest('获取配额', async () => {
      const quota = await this.client!.getQuota();
      if (quota.success) {
        const usedGB = (quota.usedBytes / 1024 / 1024 / 1024).toFixed(2);
        const availableGB = (quota.availableBytes / 1024 / 1024 / 1024).toFixed(2);
        return `已用: ${usedGB}GB, 可用: ${availableGB}GB`;
      } else {
        return `配额查询不支持: ${quota.message}`;
      }
    });

    return this.testResults;
  }

  /**
   * 运行单个测试
   */
  private async runTest(testName: string, testFn: () => Promise<string>): Promise<void> {
    const startTime = Date.now();
    try {
      logger.info(TAG, `开始测试: ${testName}`);
      const message = await testFn();
      const duration = Date.now() - startTime;
      
      this.testResults.push({
        testName,
        success: true,
        message,
        duration
      });
      
      logger.info(TAG, `✓ ${testName}: ${message} (${duration}ms)`);
    } catch (error) {
      const duration = Date.now() - startTime;
      const errorMsg = error instanceof Error ? error.message : String(error);
      
      this.testResults.push({
        testName,
        success: false,
        message: errorMsg,
        duration
      });
      
      logger.error(TAG, `✗ ${testName}: ${errorMsg} (${duration}ms)`);
    }
  }

  /**
   * 获取测试摘要
   */
  getTestSummary(): string {
    const total = this.testResults.length;
    const passed = this.testResults.filter(r => r.success).length;
    const failed = total - passed;
    const totalDuration = this.testResults.reduce((sum, r) => sum + r.duration, 0);

    let summary = `\n========== WebDAV Native 测试结果 ==========\n`;
    summary += `总计: ${total} | 通过: ${passed} | 失败: ${failed} | 耗时: ${totalDuration}ms\n`;
    summary += `=============================================\n\n`;

    for (const result of this.testResults) {
      const status = result.success ? '✓' : '✗';
      summary += `${status} ${result.testName}: ${result.message} (${result.duration}ms)\n`;
    }

    return summary;
  }

  /**
   * 销毁客户端
   */
  destroy(): void {
    if (this.client) {
      this.client.destroy();
      this.client = null;
    }
  }
}

/**
 * 快速测试函数
 * 使用方法:
 * ```
 * import { quickTestWebDAVNative } from './WebDAVNativeTest';
 * 
 * const config = {
 *   serverUrl: 'https://your-webdav-server.com',
 *   username: 'your-username',
 *   password: 'your-password',
 *   basePath: '/dav'
 * };
 * 
 * const summary = await quickTestWebDAVNative(config);
 * console.log(summary);
 * ```
 */
export async function quickTestWebDAVNative(config: WebDAVNativeConfig): Promise<string> {
  const tester = new WebDAVNativeTest();
  
  try {
    const initialized = await tester.initClient(config);
    if (!initialized) {
      return '❌ 客户端初始化失败';
    }

    await tester.runAllTests();
    return tester.getTestSummary();
  } finally {
    tester.destroy();
  }
}
