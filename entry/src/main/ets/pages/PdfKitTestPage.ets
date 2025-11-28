// 文件路径: entry/src/main/ets/pages/PdfKitTestPage.ets
/**
 * PDF Kit 最小化测试页面
 * 用于独立测试 PDF Kit API 对 PDF 格式的支持
 * 
 * 此页面与其他功能完全隔离，仅用于验证 PDF Kit 是否可用
 * 
 * PDF Kit 功能：
 * 1. PdfView 组件 - 预览 PDF 文档
 * 2. pdfService.PdfDocument - 加载和操作 PDF 文档
 * 3. 支持添加批注、页眉页脚、水印、背景、书签等
 * 4. 支持 PDF 转图片、图片转 PDF
 */

import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import { fileUri } from '@kit.CoreFileKit';
import { logger } from '../Utils/Logger';
// 导入 PDF Kit
import { pdfService, pdfViewManager, PdfView } from '@kit.PDFKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'PdfKitTestPage';

// 检测 PDF Kit 是否可用
let pdfKitAvailable = true;
try {
  // 尝试创建控制器来验证模块是否可用
  const testController = new pdfViewManager.PdfController();
  pdfKitAvailable = true;
} catch (e) {
  pdfKitAvailable = false;
}

interface TestResult {
  step: string;
  success: boolean;
  message: string;
  data?: string;
}

/**
 * PDF 文档信息接口
 */
interface PdfDocumentInfo {
  pageCount: number;
  title?: string;
  author?: string;
  subject?: string;
  keywords?: string;
  creator?: string;
  producer?: string;
  creationDate?: string;
  modificationDate?: string;
}

@Component
export struct PdfKitTestPage {
  @State testResults: TestResult[] = [];
  @State isLoading: boolean = false;
  @State selectedFilePath: string = '';
  @State selectedFileName: string = '';
  @State pdfKitStatus: string = pdfKitAvailable ? '✅ PDF Kit 模块已加载' : '❌ PDF Kit 模块加载失败';
  
  // PDF 预览相关
  @State showPdfPreview: boolean = false;
  @State pdfPageCount: number = 0;
  @State currentPage: number = 1;
  
  // PDF Kit 控制器
  private pdfController: pdfViewManager.PdfController = new pdfViewManager.PdfController();
  // PDF 文档对象（用于获取文档信息和操作）
  private pdfDocument: pdfService.PdfDocument | null = null;
  
  private pathStack: NavPathStack = new NavPathStack();
  private context: common.UIAbilityContext | null = null;

  aboutToAppear(): void {
    this.context = getContext(this) as common.UIAbilityContext;
    this.addResult('初始化', true, this.pdfKitStatus);
    
    // 注册页数变化监听器
    this.pdfController.registerPageCountChangedListener((pageCount: number) => {
      logger.info(TAG, `PDF 页数变化: ${pageCount}`);
      this.pdfPageCount = pageCount;
      this.addResult('页数监听', true, `PDF 共 ${pageCount} 页`);
    });
  }

  aboutToDisappear(): void {
    // 释放 PDF 资源
    try {
      this.pdfController.releaseDocument();
      if (this.pdfDocument) {
        this.pdfDocument = null;
      }
    } catch (e) {
      logger.warn(TAG, `释放 PDF 资源时出错: ${String(e)}`);
    }
  }

  private addResult(step: string, success: boolean, message: string, data?: string): void {
    this.testResults.push({ step, success, message, data });
    logger.info(TAG, `[${step}] ${success ? '✅' : '❌'} ${message}`);
  }

  private clearResults(): void {
    this.testResults = [];
    this.showPdfPreview = false;
    this.pdfPageCount = 0;
    this.currentPage = 1;
    this.addResult('初始化', true, this.pdfKitStatus);
  }

  /**
   * 选择 PDF 文件
   */
  private async selectFile(): Promise<void> {
    try {
      this.clearResults();
      this.addResult('选择文件', true, '正在打开文件选择器...');
      
      const documentPicker = new picker.DocumentViewPicker(this.context!);
      const selectOptions: picker.DocumentSelectOptions = {
        maxSelectNumber: 1,
        fileSuffixFilters: ['.pdf'],
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
          this.selectedFileName = decodeURIComponent(uri.split('/').pop() || 'unknown.pdf');
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
   * 复制文件到沙箱
   */
  private copyToSandbox(uri: string): void {
    try {
      this.addResult('复制文件', true, '正在复制到沙箱...');
      logger.info(TAG, `开始复制文件: ${uri}`);
      
      if (!this.context) {
        this.addResult('复制文件', false, 'Context 未初始化');
        return;
      }
      
      const targetDir = `${this.context.filesDir}/pdfkit_test`;
      
      // 构建安全的文件名
      const safeName = `test_pdf_${Date.now()}.pdf`;
      const targetPath = `${targetDir}/${safeName}`;
      logger.info(TAG, `目标路径: ${targetPath}`);
      
      // 确保目录存在
      try {
        if (!fs.accessSync(targetDir)) {
          fs.mkdirSync(targetDir);
        }
      } catch (e) {
        try {
          fs.mkdirSync(targetDir);
        } catch (mkErr) {
          this.addResult('复制文件', false, `创建目录失败: ${mkErr}`);
          return;
        }
      }
      
      // 打开源文件
      let srcFile: fs.File;
      try {
        srcFile = fs.openSync(uri, fs.OpenMode.READ_ONLY);
        logger.info(TAG, `源文件打开成功，fd: ${srcFile.fd}`);
      } catch (openError) {
        const openErrMsg = openError instanceof Error ? openError.message : String(openError);
        this.addResult('复制文件', false, `打开源文件失败: ${openErrMsg}`);
        return;
      }
      
      // 创建目标文件
      let destFile: fs.File;
      try {
        destFile = fs.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY);
      } catch (destError) {
        const destErrMsg = destError instanceof Error ? destError.message : String(destError);
        fs.closeSync(srcFile);
        this.addResult('复制文件', false, `创建目标文件失败: ${destErrMsg}`);
        return;
      }
      
      // 复制文件内容
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
      this.addResult('复制文件', true, `复制成功: ${(totalBytes / 1024).toFixed(1)} KB`, targetPath);
      
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      this.addResult('复制文件', false, `复制失败: ${errorMsg}`);
    }
  }

  /**
   * 测试 PDF Kit 基础功能 - 使用 pdfService.PdfDocument
   */
  private async testPdfDocument(): Promise<void> {
    if (!this.selectedFilePath) {
      this.addResult('PDF Document 测试', false, '请先选择文件');
      return;
    }
    
    this.isLoading = true;
    
    try {
      this.addResult('PDF Document 测试', true, '开始测试 pdfService.PdfDocument...');
      
      // 步骤1: 创建 PdfDocument 对象
      this.addResult('创建 PdfDocument', true, '正在创建 PdfDocument 对象...');
      this.pdfDocument = new pdfService.PdfDocument();
      this.addResult('创建 PdfDocument', true, 'PdfDocument 对象创建成功');
      
      // 步骤2: 加载 PDF 文档
      this.addResult('加载文档', true, `正在加载: ${this.selectedFilePath}`);
      const loadResult: pdfService.ParseResult = this.pdfDocument.loadDocument(this.selectedFilePath);
      this.addResult('加载文档', true, `加载结果: ${JSON.stringify(loadResult)}`);
      
      // 步骤3: 获取页数
      const pageCount = this.pdfDocument.getPageCount();
      this.pdfPageCount = pageCount;
      this.addResult('获取页数', true, `PDF 共 ${pageCount} 页`);
      
      // 步骤4: 获取第一页信息
      if (pageCount > 0) {
        this.addResult('获取页面', true, '正在获取第一页信息...');
        const firstPage: pdfService.PdfPage = this.pdfDocument.getPage(0);
        const pageWidth = firstPage.getWidth();
        const pageHeight = firstPage.getHeight();
        this.addResult('页面信息', true, `第一页尺寸: ${pageWidth} x ${pageHeight}`);
      }
      
      this.addResult('PDF Document 测试', true, '✅ pdfService.PdfDocument 测试通过！');
      
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      this.addResult('PDF Document 测试', false, `测试失败: ${errorMsg}`);
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 测试 PDF Kit 预览功能 - 使用 PdfView 组件
   */
  private async testPdfView(): Promise<void> {
    if (!this.selectedFilePath) {
      this.addResult('PdfView 测试', false, '请先选择文件');
      return;
    }
    
    this.isLoading = true;
    
    try {
      this.addResult('PdfView 测试', true, '开始测试 PdfView 组件...');
      
      // 使用 PdfController 加载文档
      this.addResult('加载文档', true, `正在通过 PdfController 加载: ${this.selectedFilePath}`);
      
      this.pdfController.loadDocument(this.selectedFilePath)
        .then((loadResult: pdfService.ParseResult) => {
          logger.info(TAG, `PdfView 加载成功: ${JSON.stringify(loadResult)}`);
          this.addResult('PdfView 加载', true, `加载成功: ${JSON.stringify(loadResult)}`);
          this.showPdfPreview = true;
          this.addResult('PdfView 测试', true, '✅ PdfView 组件测试通过！');
          this.isLoading = false;
        })
        .catch((err: BusinessError) => {
          logger.error(TAG, `PdfView 加载失败: ${JSON.stringify(err)}`);
          this.addResult('PdfView 加载', false, `加载失败: ${err.message}`);
          this.isLoading = false;
        });
      
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      this.addResult('PdfView 测试', false, `测试失败: ${errorMsg}`);
      this.isLoading = false;
    }
  }

  /**
   * 测试 PDF 转图片功能
   */
  private async testConvertToImage(): Promise<void> {
    if (!this.pdfDocument) {
      this.addResult('转图片测试', false, '请先运行 PDF Document 测试');
      return;
    }
    
    this.isLoading = true;
    
    try {
      this.addResult('转图片测试', true, '开始测试 PDF 转图片...');
      
      // 创建输出目录
      const outputDir = `${this.context!.filesDir}/pdfkit_output/`;
      try {
        fs.mkdirSync(outputDir);
      } catch (e) {
        // 目录可能已存在
      }
      
      // 转换第一页为图片
      this.addResult('转换图片', true, `输出目录: ${outputDir}`);
      const result = this.pdfDocument.convertToImage(outputDir, 0);
      this.addResult('转换图片', true, `转换结果: ${JSON.stringify(result)}`);
      
      // 检查输出文件
      const outputFiles = fs.listFileSync(outputDir);
      this.addResult('输出文件', true, `生成文件: ${outputFiles.join(', ')}`);
      
      this.addResult('转图片测试', true, '✅ PDF 转图片测试通过！');
      
    } catch (error) {
      const errorMsg = error instanceof Error ? error.message : String(error);
      this.addResult('转图片测试', false, `测试失败: ${errorMsg}`);
    } finally {
      this.isLoading = false;
    }
  }

  build() {
    NavDestination() {
      Column() {
        // 标题
        Text('PDF Kit 测试')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .margin({ bottom: 16 })
        
        // 状态显示
        Text(this.pdfKitStatus)
          .fontSize(16)
          .fontColor(pdfKitAvailable ? '#00AA00' : '#FF0000')
          .margin({ bottom: 8 })
        
        // 已选文件
        if (this.selectedFileName) {
          Text(`已选文件: ${this.selectedFileName}`)
            .fontSize(14)
            .fontColor('#666666')
            .margin({ bottom: 8 })
        }
        
        // 页数信息
        if (this.pdfPageCount > 0) {
          Text(`PDF 页数: ${this.pdfPageCount}`)
            .fontSize(14)
            .fontColor('#007AFF')
            .margin({ bottom: 8 })
        }
        
        // 操作按钮 - 第一行
        Row({ space: 12 }) {
          Button('选择 PDF')
            .onClick(() => this.selectFile())
            .enabled(!this.isLoading)
            .fontSize(14)
            .height(36)
          
          Button('Document 测试')
            .onClick(() => this.testPdfDocument())
            .enabled(!this.isLoading && !!this.selectedFilePath)
            .fontSize(14)
            .height(36)
        }
        .margin({ bottom: 8 })
        
        // 操作按钮 - 第二行
        Row({ space: 12 }) {
          Button('PdfView 测试')
            .onClick(() => this.testPdfView())
            .enabled(!this.isLoading && !!this.selectedFilePath)
            .fontSize(14)
            .height(36)
          
          Button('转图片测试')
            .onClick(() => this.testConvertToImage())
            .enabled(!this.isLoading && !!this.pdfDocument)
            .fontSize(14)
            .height(36)
          
          Button('清除')
            .onClick(() => this.clearResults())
            .enabled(!this.isLoading)
            .fontSize(14)
            .height(36)
        }
        .margin({ bottom: 16 })
        
        // 加载指示器
        if (this.isLoading) {
          LoadingProgress()
            .width(40)
            .height(40)
            .margin({ bottom: 10 })
        }
        
        // PDF 预览区域
        if (this.showPdfPreview) {
          Column() {
            Text('PDF 预览')
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .margin({ bottom: 8 })
            
            PdfView({
              controller: this.pdfController,
              pageFit: pdfService.PageFit.FIT_WIDTH,
              isContinuous: true,
              showScroll: true
            })
              .width('100%')
              .height(300)
              .border({ width: 1, color: '#CCCCCC', radius: 8 })
          }
          .width('100%')
          .margin({ bottom: 16 })
        }
        
        // 测试结果列表
        Text('测试结果:')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 8 })
        
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
                    .maxLines(3)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                }
              }
              .padding(10)
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
    .title('PDF Kit 测试')
    .onReady((context: NavDestinationContext) => {
      this.pathStack = context.pathStack;
    })
    .onBackPressed(() => {
      this.pathStack.pop();
      return true;
    })
  }
}
