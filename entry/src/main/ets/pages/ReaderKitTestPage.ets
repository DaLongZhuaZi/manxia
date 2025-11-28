// 文件路径: entry/src/main/ets/pages/ReaderKitTestPage.ets
/**
 * Reader Kit 最小化测试页面
 * 用于独立测试 Reader Kit API 对 EPUB/MOBI/AZW 等格式的支持
 * 
 * 此页面与其他功能完全隔离，仅用于验证 Reader Kit 是否可用
 */

import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { fileUri } from '@kit.CoreFileKit';
import { logger } from '../Utils/Logger';
// 直接导入 Reader Kit - 如果模块不可用会在编译/运行时报错
import { bookParser } from '@kit.ReaderKit';

const readerKitAvailable = true; // 如果导入成功，则可用

const TAG = 'ReaderKitTestPage';

interface TestResult {
  step: string;
  success: boolean;
  message: string;
  data?: string;
}

@Component
export struct ReaderKitTestPage {
  @State testResults: TestResult[] = [];
  @State isLoading: boolean = false;
  @State selectedFilePath: string = '';
  @State selectedFileName: string = '';
  @State readerKitStatus: string = readerKitAvailable ? '✅ Reader Kit 模块已加载' : '❌ Reader Kit 模块加载失败';
  
  private pathStack: NavPathStack = new NavPathStack();
  private context: common.UIAbilityContext | null = null;

  aboutToAppear(): void {
    this.context = getContext(this) as common.UIAbilityContext;
    this.addResult('初始化', true, this.readerKitStatus);
  }

  private addResult(step: string, success: boolean, message: string, data?: string): void {
    this.testResults.push({ step, success, message, data });
    logger.info(TAG, `[${step}] ${success ? '✅' : '❌'} ${message}`);
  }

  private clearResults(): void {
    this.testResults = [];
    this.addResult('初始化', true, this.readerKitStatus);
  }

  /**
   * 选择电子书文件
   */
  private async selectFile(): Promise<void> {
    try {
      this.clearResults();
      this.addResult('选择文件', true, '正在打开文件选择器...');
      
      const documentPicker = new picker.DocumentViewPicker(this.context!);
      const selectOptions: picker.DocumentSelectOptions = {
        maxSelectNumber: 1,
        fileSuffixFilters: ['.epub', '.mobi', '.azw', '.azw3', '.txt'],
      };

      documentPicker.select(selectOptions).then((result: Array<string>) => {
        if (!result || result.length === 0) {
          this.addResult('选择文件', false, '未选择任何文件');
          return;
        }

        const uri = result[0];
        this.addResult('选择文件', true, `已选择: ${uri}`);
        
        // 获取文件名
        try {
          const uriObj = new fileUri.FileUri(uri);
          this.selectedFileName = uriObj.name;
        } catch {
          this.selectedFileName = decodeURIComponent(uri.split('/').pop() || 'unknown');
        }
        
        // 复制到沙箱
        this.copyToSandbox(uri);
      }).catch((err: Error) => {
        this.addResult('选择文件', false, `选择失败: ${err.message}`);
      });
    } catch (error) {
      this.addResult('选择文件', false, `异常: ${String(error)}`);
    }
  }

  /**
   * 复制文件到沙箱（在 picker 回调中调用）
   * 使用 fs 模块处理 file://docs URI
   */
  private copyToSandbox(uri: string): void {
    try {
      this.addResult('复制文件', true, '正在复制到沙箱...');
      logger.info(TAG, `开始复制文件: ${uri}`);
      logger.info(TAG, `context.filesDir: ${this.context?.filesDir}`);
      
      if (!this.context) {
        this.addResult('复制文件', false, 'Context 未初始化');
        return;
      }
      
      const targetDir = `${this.context.filesDir}/readerkit_test`;
      
      // 使用更安全的文件名（移除特殊字符，但保留扩展名）
      // 获取原始扩展名
      let extension = '.txt';
      const dotIndex = this.selectedFileName.lastIndexOf('.');
      if (dotIndex > 0) {
        extension = this.selectedFileName.substring(dotIndex);
      }
      
      // 构建安全的文件名
      const safeName = `test_file_${Date.now()}${extension}`;
      const targetPath = `${targetDir}/${safeName}`;
      logger.info(TAG, `目标路径: ${targetPath}`);
      
      // 确保目录存在
      try {
        if (!fs.accessSync(targetDir)) {
             fs.mkdirSync(targetDir);
        }
        logger.info(TAG, `目录检查完毕: ${targetDir}`);
      } catch (e) {
        // accessSync 抛错说明不存在或无权限
        try {
          fs.mkdirSync(targetDir);
          logger.info(TAG, `创建目录: ${targetDir}`);
        } catch (mkErr) {
           logger.error(TAG, `创建目录失败: ${mkErr}`);
           this.addResult('复制文件', false, `创建目录失败: ${mkErr}`);
           return;
        }
      }
      
      // 使用 fs 模块打开源文件
      // 注意：file://docs URI 的临时权限只允许打开一次，不能关闭后重新打开
      logger.info(TAG, `尝试打开源文件: ${uri}`);
      let srcFile: fs.File;
      try {
        srcFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        logger.info(TAG, `源文件打开成功，fd: ${srcFile.fd}`);
      } catch (openError) {
        const openErrMsg = openError instanceof Error ? openError.message : String(openError);
        logger.error(TAG, `打开源文件失败: ${openErrMsg}`);
        this.addResult('复制文件', false, `打开源文件失败: ${openErrMsg}`);
        return;
      }
      
      // 打开目标文件
      logger.info(TAG, `尝试创建目标文件: ${targetPath}`);
      let destFile: fs.File;
      try {
        destFile = fs.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
        logger.info(TAG, `目标文件创建成功，fd: ${destFile.fd}`);
      } catch (destError) {
        const destErrMsg = destError instanceof Error ? destError.message : String(destError);
        logger.error(TAG, `创建目标文件失败: ${destErrMsg}`);
        fs.closeSync(srcFile); // 记得关闭源文件
        this.addResult('复制文件', false, `创建目标文件失败: ${destErrMsg}`);
        return;
      }
      
      // 直接开始读取和写入（不要先读取验证再重新打开，因为临时权限只能打开一次）
      const BUFFER_SIZE = 4096;
      const buffer = new ArrayBuffer(BUFFER_SIZE);
      let totalBytes = 0;
      let readLen: number;
      
      while ((readLen = fs.readSync(srcFile.fd, buffer)) > 0) {
        if (readLen === BUFFER_SIZE) {
          fs.writeSync(destFile.fd, buffer);
        } else {
          fs.writeSync(destFile.fd, buffer.slice(0, readLen));
        }
        totalBytes += readLen;
      }
      
      fs.closeSync(srcFile);
      fs.closeSync(destFile);
      
      logger.info(TAG, `文件复制成功: ${totalBytes} 字节 -> ${targetPath}`);
      this.selectedFilePath = targetPath;
      this.addResult('复制文件', true, `复制成功: ${totalBytes} 字节`, targetPath);
      
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      logger.error(TAG, `文件复制失败: ${errorMsg}`);
      this.addResult('复制文件', false, `复制失败: ${errorMsg}`);
    }
  }

  /**
   * 测试 Reader Kit 解析
   */
  private async testReaderKit(): Promise<void> {
    if (!this.selectedFilePath) {
      this.addResult('Reader Kit 测试', false, '请先选择文件');
      return;
    }
    
    if (!readerKitAvailable) {
      this.addResult('Reader Kit 测试', false, 'Reader Kit 模块不可用');
      return;
    }
    
    this.isLoading = true;
    
    try {
      this.addResult('Reader Kit 测试', true, '开始解析...');
      
      // 步骤1: 获取解析器处理器
      this.addResult('获取 Handler', true, '正在获取 BookParserHandler...');
      const parserHandler: bookParser.BookParserHandler = await bookParser.getDefaultHandler(this.selectedFilePath);
      this.addResult('获取 Handler', true, `Handler 获取成功`);
      
      // 步骤2: 获取书籍信息
      this.addResult('获取书籍信息', true, '正在获取 BookInfo...');
      const bookInfo: bookParser.BookInfo = await parserHandler.getBookInfo();
      // 使用 JSON.stringify 显示完整的 BookInfo 对象，以便查看实际的属性名
      const bookInfoJson = JSON.stringify(bookInfo, null, 2);
      this.addResult('获取书籍信息', true, `BookInfo 获取成功`, bookInfoJson);
      
      // 步骤3: 获取目录
      this.addResult('获取目录', true, '正在获取 CatalogList...');
      const catalog: Array<bookParser.CatalogItem> = await parserHandler.getCatalogList();
      this.addResult('获取目录', true, `目录获取成功，共 ${catalog?.length || 0} 个章节`);
      
      // 步骤4: 显示目录信息
      if (catalog && catalog.length > 0) {
        const firstChapter: bookParser.CatalogItem = catalog[0];
        // 使用 JSON.stringify 显示完整的 CatalogItem 对象
        const catalogJson = JSON.stringify(firstChapter, null, 2);
        this.addResult('目录详情', true, `第一个目录项`, catalogJson);
      }
      
      this.addResult('测试完成', true, '✅ Reader Kit 测试全部通过！');
      
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      this.addResult('Reader Kit 测试', false, `解析失败: ${errorMsg}`);
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    NavDestination() {
      Column() {
        // 标题
        Text('Reader Kit 测试')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 20 })
        
        // 状态显示
        Text(this.readerKitStatus)
          .fontSize(16)
          .fontColor(readerKitAvailable ? '#00AA00' : '#FF0000')
          .margin({ bottom: 10 })
        
        // 已选文件
        if (this.selectedFileName) {
          Text(`已选文件: ${this.selectedFileName}`)
            .fontSize(14)
            .fontColor('#666666')
            .margin({ bottom: 10 })
        }
        
        // 操作按钮
        Row({ space: 16 }) {
          Button('选择电子书')
            .onClick(() => this.selectFile())
            .enabled(!this.isLoading)
          
          Button('测试 Reader Kit')
            .onClick(() => this.testReaderKit())
            .enabled(!this.isLoading && !!this.selectedFilePath)
          
          Button('清除结果')
            .onClick(() => this.clearResults())
            .enabled(!this.isLoading)
        }
        .margin({ bottom: 20 })
        
        // 加载指示器
        if (this.isLoading) {
          LoadingProgress()
            .width(40)
            .height(40)
            .margin({ bottom: 10 })
        }
        
        // 测试结果列表
        Text('测试结果:')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 10 })
        
        List() {
          ForEach(this.testResults, (result: TestResult, index: number) => {
            ListItem() {
              Column() {
                Row() {
                  Text(result.success ? '✅' : '❌')
                    .fontSize(14)
                    .margin({ right: 8 })
                  Text(`[${result.step}]`)
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor('#333333')
                  Text(result.message)
                    .fontSize(14)
                    .fontColor('#666666')
                    .layoutWeight(1)
                    .maxLines(2)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
                .width('100%')
                
                if (result.data) {
                  Text(result.data)
                    .fontSize(12)
                    .fontColor('#999999')
                    .backgroundColor('#F5F5F5')
                    .padding(8)
                    .borderRadius(4)
                    .margin({ top: 4 })
                    .maxLines(5)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .padding(12)
              .backgroundColor(index % 2 === 0 ? '#FFFFFF' : '#FAFAFA')
            }
          })
        }
        .layoutWeight(1)
        .width('100%')
        .divider({ strokeWidth: 1, color: '#EEEEEE' })
      }
      .width('100%')
      .height('100%')
      .padding(16)
    }
    .title('Reader Kit 测试')
    .onBackPressed(() => {
      this.pathStack.pop();
      return true;
    })
  }
}
