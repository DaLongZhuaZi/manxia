// 文件路径: entry/src/main/ets/Framework/Components/PdfViewerComponent.ets
/**
 * PDF预览组件
 * 使用Web组件加载和显示PDF文件
 */

import { webview } from '@kit.ArkWeb';
import { logger } from '../../Utils/Logger';

const TAG = 'PdfViewerComponent';

/**
 * PDF预览器参数接口
 */
export interface PdfViewerParams {
  filePath: string; // PDF文件路径（支持file://协议）
  onLoadFinished?: () => void; // 加载完成回调
  onLoadError?: (errorMsg: string) => void; // 加载错误回调
}

/**
 * PDF预览组件
 */
@Component
export struct PdfViewerComponent {
  @Prop filePath: string = '';
  onLoadFinished?: () => void;
  onLoadError?: (errorMsg: string) => void;
  
  private webviewController: webview.WebviewController = new webview.WebviewController();
  @State isLoading: boolean = true;
  @State errorMessage: string = '';

  aboutToAppear(): void {
    logger.info(TAG, `PDF预览组件初始化: ${this.filePath}`);
  }

  aboutToDisappear(): void {
    logger.info(TAG, 'PDF预览组件销毁');
  }

  build() {
    Stack() {
      // Web组件用于显示PDF
      Web({
        src: this.filePath,
        controller: this.webviewController
      })
        .fileAccess(true) // 允许访问本地文件
        .domStorageAccess(true) // 允许DOM存储（PDF预览器需要）
        .javaScriptAccess(true) // 允许JavaScript执行
        .zoomAccess(true) // 允许缩放
        .width('100%')
        .height('100%')
        .onPageBegin((event) => {
          if (event && event.url) {
            logger.info(TAG, `开始加载PDF: ${event.url}`);
            this.isLoading = true;
            this.errorMessage = '';
          }
        })
        .onPageEnd((event) => {
          if (event && event.url) {
            logger.info(TAG, `PDF加载完成: ${event.url}`);
            this.isLoading = false;
            if (this.onLoadFinished) {
              this.onLoadFinished();
            }
          }
        })
        .onErrorReceive((event) => {
          if (event) {
            const errorMsg = `PDF加载失败: ${event.error.getErrorInfo()}`;
            logger.error(TAG, errorMsg);
            this.isLoading = false;
            this.errorMessage = errorMsg;
            if (this.onLoadError) {
              this.onLoadError(errorMsg);
            }
          }
        })

      // 加载指示器
      if (this.isLoading) {
        Column({ space: 16 }) {
          LoadingProgress()
            .width(60)
            .height(60)
            .color(Color.Blue)
          
          Text('正在加载PDF...')
            .fontSize(14)
            .fontColor(Color.Gray)
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('#80FFFFFF')
      }

      // 错误提示
      if (this.errorMessage.length > 0) {
        Column({ space: 16 }) {
          Image($r('app.media.ic_error'))
            .width(80)
            .height(80)
            .fillColor(Color.Red)
          
          Text('PDF加载失败')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.Red)
          
          Text(this.errorMessage)
            .fontSize(14)
            .fontColor(Color.Gray)
            .maxLines(3)
            .textAlign(TextAlign.Center)
            .width('80%')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor(Color.White)
        .padding(20)
      }
    }
    .width('100%')
    .height('100%')
  }
}

