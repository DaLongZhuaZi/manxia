# @wolfx/minizip

## 简介

一个 minizip 分支，添加了流式压缩和流式解压功能。

## 安装

`ohpm install @wolfx/minizip`

## Example

```ts
import { StreamingCompressor, StreamingDecompressor } from '@wolfx/minizip';

@Entry
@Component
struct FinalStreamingUnzipExample {
  @State progressText: string = '未开始解压';
  @State currentFile: string = '';
  @State fileProgress: number = 0;
  @State overallProgress: number = 0;
  @State unzipResult: string = '';

  // 添加日志记录功能
  private logMessage(message: string) {
    console.log(`[FinalStreamingUnzipExample] ${message}`);
  }

  build() {
    Column() {
      Text('最终版流式解压示例')
        .fontSize(24)
        .margin({ bottom: 20 })

      Button('开始流式解压')
        .width('80%')
        .onClick(() => {
          this.startStreamingUnzip();
        })
        .margin({ bottom: 10 })

      Button('开始流式压缩')
        .width('80%')
        .onClick(() => {
          this.startStreamingCompress();
        })
        .margin({ bottom: 20 })

      Text(`整体进度: ${this.overallProgress}%`)
        .fontSize(18)
        .margin({ bottom: 5 })

      Text(`当前文件: ${this.currentFile}`)
        .fontSize(16)
        .margin({ bottom: 5 })

      Text(`文件进度: ${this.fileProgress}%`)
        .fontSize(16)
        .margin({ bottom: 10 })

      Scroll() {
        Text(this.progressText)
          .fontSize(14)
          .textAlign(TextAlign.Start)
          .width('90%')
      }
      .layoutWeight(1)
      .backgroundColor('#f0f0f0')
      .border({ width: 1, color: '#ccc' })
      .padding(10)
      .margin({ bottom: 20 })

      Text(this.unzipResult)
        .fontSize(18)
        .fontColor(this.unzipResult.includes('成功') ? '#008000' : '#ff0000')
    }
    .width('100%')
    .height('100%')
    .padding(20)
  }

  private startStreamingUnzip() {
    // 重置状态
    this.progressText = '';
    this.currentFile = '';
    this.fileProgress = 0;
    this.overallProgress = 0;
    this.unzipResult = '开始流式解压...';
    this.logMessage('开始流式解压');

    // ZIP文件路径和目标解压路径
    const zipFilePath = getContext().resourceDir + '/GBK-code-table-main.zip';
    const targetPath = getContext().cacheDir + '/unzipped';

    try {
      // 创建流式解压器实例
      const decompressor = new StreamingDecompressor();

      // 设置进度回调
      decompressor.setProgressCallback((progress) => {
        this.overallProgress = progress.overallProgress;
        this.fileProgress = progress.fileProgress;
        this.currentFile = progress.currentFile;
        this.progressText = progress.message + '\n' + this.progressText;
        this.unzipResult = `处理中... (${progress.processedFiles}/${progress.totalFiles})`;
      });

      // 开始解压
      decompressor.startStreamingDecompress(zipFilePath, targetPath)
        .then((success) => {
          if (success) {
            this.unzipResult = '流式解压完成: 所有文件已解压';
            this.logMessage(this.unzipResult);
          } else {
            this.unzipResult = '流式解压失败';
            this.logMessage(this.unzipResult);
          }
        })
        .catch((error: Error) => {
          this.unzipResult = `解压过程出错: ${error}`;
          this.logMessage(this.unzipResult);
        });
    } catch (error) {
      this.unzipResult = `解压过程出错: ${error}`;
      this.logMessage(this.unzipResult);
    }
  }

  private startStreamingCompress() {
    // 重置状态
    this.progressText = '';
    this.currentFile = '';
    this.fileProgress = 0;
    this.overallProgress = 0;
    this.unzipResult = '开始流式压缩...';
    this.logMessage('开始流式压缩');

    // 源文件路径和目标压缩路径
    const sourceFilePath = getContext().cacheDir + '/unzipped'; // 压缩解压后的文件
    const zipFilePath = getContext().cacheDir + '/streaming_compressed.zip';

    try {
      // 创建流式压缩器实例
      const compressor = new StreamingCompressor();

      // 设置进度回调
      compressor.setProgressCallback((progress) => {
        this.overallProgress = progress.overallProgress;
        this.fileProgress = progress.fileProgress;
        this.currentFile = progress.currentFile;
        this.progressText = progress.message + '\n' + this.progressText;
        this.unzipResult = `处理中... (${progress.processedFiles}/${progress.totalFiles})`;
      });

      // 开始压缩
      compressor.startStreamingCompress(sourceFilePath, zipFilePath)
        .then((success) => {
          if (success) {
            this.unzipResult = '流式压缩完成: 所有文件已压缩';
            this.logMessage(this.unzipResult);
          } else {
            this.unzipResult = '流式压缩失败';
            this.logMessage(this.unzipResult);
          }
        })
        .catch((error: Error) => {
          this.unzipResult = `压缩过程出错: ${error}`;
          this.logMessage(this.unzipResult);
        });
    } catch (error) {
      this.unzipResult = `压缩过程出错: ${error}`;
      this.logMessage(this.unzipResult);
    }
  }
}
```