# commons-compress
## 简介
本软件是参照开源软件 [Apache Commons Compress](https://github.com/apache/commons-compress) 源码并用 TypeScript 语言实现了相关功能， 在OpenHarmony上支持bzip2、gzip、lzma、xz、Snappy、LZ4、Brotli、DEFLATE、Zstandard 和 ar、cpio、tar、zip、dump、7z等格式的压缩和解压功能。

![compp_zh.gif](compp_zh.gif)
## 下载

```
  ohpm install @ohos/commons-compress
```
OpenHarmony ohpm 环境配置等更多内容，请参考如何安装 [OpenHarmony ohpm 包](https://gitcode.com/openharmony-tpc/docs/blob/master/OpenHarmony_har_usage.md)

## X86模拟器配置

使用模拟器运行应用/服务

## 使用说明

### 配置全局路径

需要在EntryAbility文件配置全局路径

``` javascript
GlobalContext.getContext().setObject("context", this.context);
```

### 文件存储路径说明

开发者在应用开发调试时，可能需要向应用沙箱下推送一些文件以期望在应用内访问或测试，可以参照[推送文件说明文档](https://gitcode.com/openharmony/docs/blob/master/zh-cn/application-dev/file-management/send-file-to-app-sandbox.md#%E5%BA%94%E7%94%A8%E6%B2%99%E7%AE%B1%E8%B7%AF%E5%BE%84%E5%92%8C%E8%B0%83%E8%AF%95%E8%BF%9B%E7%A8%8B%E8%A7%86%E8%A7%92%E4%B8%8B%E7%9A%84%E7%9C%9F%E5%AE%9E%E7%89%A9%E7%90%86%E8%B7%AF%E5%BE%84)

### zip解压缩能力说明

本软件的zip解压缩能力示例是通过调用系统接口 @ohos.zlib 实现的，详细接口说明可以查看[Zip模块](https://docs.openharmony.cn/pages/v4.1/zh-cn/application-dev/reference/apis-basic-services-kit/js-apis-zlib.md) 。

### zip 压缩功能

指定文件夹路径压缩zip文件夹。

``` javascript
import fs from '@ohos.file.fs';
import zlib from '@ohos.zlib';

let filesDir = GlobalContext.getContext().getObject("FilesDir");

jsZipTest(): void {
    try {
      var data = filesDir
      let inFile = data + '/' + this.newFolder + '/hello.txt';
      let outFile = data + '/' + this.newFolder + '.zip';
      let options = {
        level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION,
        memLevel: zlib.MemLevel.MEM_LEVEL_DEFAULT,
        strategy: zlib.CompressStrategy.COMPRESS_STRATEGY_DEFAULT_STRATEGY
      };

      zlib.compressFile(inFile, outFile, options, (errData) => {
        if (errData !== null) {
          console.log(`errData is errCode:${errData.code}  message:${errData.message}`);
        } else {
          AlertDialog.show({ title: '压缩成功',
            message: '请查看沙箱路径 ' + data + '/',
            confirm: { value: 'OK', action: () => {
              this.isDeCompressGZipShow = true
            } }
          })
        }
      })
    } catch (error) {
      console.error('File to obtain the file directory. Cause: ' + error.message);
    }
  }
```

### zip 解压功能

指定文件夹路径解压zip文件夹。

``` javascript
import fs from '@ohos.file.fs';
import zlib from '@ohos.zlib';

let filesDir = GlobalContext.getContext().getObject("FilesDir");

unJsZipTest(): void {
    try {
      var data = filesDir
      let inFile = data + '/' + this.newFolder + '.zip';
      let outFile = data;
      let options = {
        level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION,
        memLevel: zlib.MemLevel.MEM_LEVEL_DEFAULT,
        strategy: zlib.CompressStrategy.COMPRESS_STRATEGY_DEFAULT_STRATEGY
      };

      zlib.decompressFile(inFile, outFile, options, (errData) => {
        if (errData !== null) {
          console.log(`errData is errCode:${errData.code}  message:${errData.message}`);
        }else {
          AlertDialog.show({ title: '解缩成功',
            message: '请查看沙箱路径 ' + data ,
            confirm: { value: 'OK', action: () => {
            } }
          })
        }
      })
    } catch (error) {
      console.error('File to obtain the file directory. Cause: ' + error.message);
    }
  }  
```

### gzip 压缩功能

指定文件夹路径压缩gz文件夹。

``` javascript
import {gzipFile} from '@ohos/commons-compress'
import fs from '@ohos.file.fs';
let filesDir = GlobalContext.getContext().getObject("FilesDir");
  gzipFileTest(): void {
    try{
      var data = filesDir
        console.info('directory obtained. Data:' + data);
        gzipFile(data + '/hello.txt', data + '/test.txt.gz')
          .then((isSuccess) => {
            if (isSuccess) {
              AlertDialog.show({ title: '压缩成功',
                message: '请查看沙箱路径 ' + data + '/test.txt.gz',
                confirm: { value: 'OK', action: () => {
                  this.isDeCompressGZipShow = true
                } }
              })
            }
          });
    }catch(error){
      console.error('File to obtain the file directory. Cause: ' + error.message);
    }
  }
```

### gzip 解压功能

指定文件夹路径解压gz文件夹。

``` javascript
import {unGzipFile} from '@ohos/commons-compress'
import fs from '@ohos.file.fs';
let filesDir = GlobalContext.getContext().getObject("FilesDir");
  unGzipFileTest(): void {
    try{
      var data = filesDir
        unGzipFile(data + '/test.txt.gz', data + '/test.txt')
          .then((isSuccess) => {
            if (isSuccess) {
              AlertDialog.show({ title: '解缩成功',
                message: '请查看沙箱路径 ' + data + '/test.txt',
                confirm: { value: 'OK', action: () => {
                } }
              })
            }
          });
    }catch(error){
      console.error('File to obtain the file directory. Cause: ' + error.message);
    }
  }
```



### xz 压缩功能

指定文件夹路径压缩XZ文件夹。

```javascript
import {File, OutputStream, InputStream, IOUtils, CompressorStreamFactory, CompressorOutputStream } from '@ohos/commons-compress'
import fs from '@ohos.file.fs';
let filesDir = GlobalContext.getContext().getObject("FilesDir");
  testXZCreation(): void {
    try{
      var data = filesDir
        console.info('directory obtained. Data:' + data);
        let input = new File(data, "/hello.txt");
        let output = new File(data, "/hello.txt.xz");
        let out: OutputStream = new OutputStream();
        let input1: InputStream = new InputStream();
        out.setFilePath(output.getPath());
        input1.setFilePath(input.getPath());
        let cos: CompressorOutputStream = new CompressorStreamFactory(false). createCompressorOutputStream("xz", out)
        IOUtils.copyStream(input1, cos);
        cos.close();
        input1.close()
        AlertDialog.show({ title: '压缩成功',
          message: '请查看沙箱路径 ' + data + '/hello.txt.xz',
          confirm: { value: 'OK', action: () => {
            this.isDeCompressBzip2Show = true
          } }
        })
    }catch(error){
      console.error('File to obtain the file directory. Cause: ' + error.message);
    }
  }

```

### xz 解压功能

指定文件夹路径解压XZ文件夹。

```javascript
import {File, OutputStream, InputStream, IOUtils, CompressorStreamFactory, CompressorInputStream} from '@ohos/commons-compress'
import fs from '@ohos.file.fs';
let filesDir = GlobalContext.getContext().getObject("FilesDir");
  unXZFileTest(): void {
    try{
      var data = filesDir
        let input = new File(data, "/hello.txt.xz");
        let output = new File(data, "/hello1.txt");
        let out: OutputStream = new OutputStream();
        let input1: InputStream = new InputStream();
        out.setFilePath(output.getPath());
        input1.setFilePath(input.getPath());
        let inputs: CompressorInputStream = new CompressorStreamFactory(false). createCompressorNameInputStream("xz", input1)
        IOUtils.copyStream(inputs, out);
        out.close();
        input1.close();
        AlertDialog.show({ title: '解缩成功',
          message: '请查看沙箱路径 ' + data + '/hello1.txt',
          confirm: { value: 'OK', action: () => {
          } }
        })
    }catch(error){
      console.error('File to obtain the file directory. Cause: ' + error.message);
    }
  }
```



### Z 解压功能

指定文件夹路径解压Z文件夹。

```javascript
import {File, OutputStream, InputStream, IOUtils, CompressorInputStream, CompressorStreamFactory} from '@ohos/commons-compress'
import fs from '@ohos.file.fs';
let filesDir = GlobalContext.getContext().getObject("FilesDir");
  unZFileTest(): void {
    try{
      var data = filesDir
        let inputStream: InputStream = new InputStream();
        inputStream.setFilePath(data + '/bla.tar.Z');
        let fOut: OutputStream = new OutputStream();
        fOut.setFilePath(data + '/bla.tar');
        let input: CompressorInputStream = new CompressorStreamFactory(false). createCompressorNameInputStream("z", inputStream);
        IOUtils.copyStream(input, fOut);
        inputStream.close();
        fOut.close();
        AlertDialog.show({ title: '解缩成功',
          message: '请查看沙箱路径 ' + data + '/bla.tar',
          confirm: { value: 'OK', action: () => {
          } }
        })
       }catch(error){
      console.error('File to obtain the file directory. Cause: ' + error.message);
    }
  }
```



### zstd 压缩功能

指定文件夹路径压缩zstd 文件夹。

```javascript
import { ZstdCompress } from '@ohos/commons-compress';
let filesDir = GlobalContext.getContext().getObject("FilesDir");
async testZstdCompressed(): Promise<void> {
    try {
        var data = filesDir
        await zstdCompress(data + "/hello.txt", data + "/hello.txt.zstd", 1, 3).then((value) => {
            if (value) {
                AlertDialog.show({ title: '压缩成功',
                    message: '请查看沙箱路径 ' + data + '/hello.txt.zstd',
                    confirm: { value: 'OK', action: () => {
                        this.isDeCompressZstdShow = true
                    } }
                })
            } else {
                AlertDialog.show({ title: '压缩失败',
                    message: '请检查再压缩 ',
                    confirm: { value: 'OK', action: () => {
                    } }
                })
            }
        })
    } catch (error) {
        console.error('File to obtain the file directory. Cause: ' + error.message);
    }
}
```

### zstd 解压功能

指定文件夹路径解压zstd 文件夹。

```javascript
import { ZstdDecompress } from '@ohos/commons-compress';
let filesDir = GlobalContext.getContext().getObject("FilesDir");
async testZstdDecompressed(): Promise<void> {
    try {
        var data = filesDir
        await zstdDecompress(data + "/hello.txt.zstd", data + '/newhello.txt').then((value) => {
            if (value) {
                AlertDialog.show({ title: '解压成功',
                    message: '请查看沙箱路径 ' + data + '/newhello.txt',
                    confirm: { value: 'OK', action: () => {
                    } }
                })
            } else {
                AlertDialog.show({ title: '解压失败',
                    message: '请检查再解压',
                    confirm: { value: 'OK', action: () => {
                    } }
                })
            }
        })
    } catch (error) {
        console.error('File to obtain the file directory. Cause: ' + error.message);
    }
}
```

### ar 压缩功能

指定文件夹路径压缩ar文件夹。

```javascript
import { ArchiveEntry, ArchiveUtils, ArArchiveInputStream, ArArchiveEntry, ArchiveStreamFactory, ArchiveOutputStream, InputStream, File,OutputStream,IOUtils} from '@ohos/commons-compress'
import fs from '@ohos.file.fs';
let filesDir = GlobalContext.getContext().getObject("FilesDir");

  jsArTest(): void {
    try{
      var data = filesDir
        this.testArArchiveCreation(data)
    }catch(error){
      console.error(error.message);
    }
  }

  testArArchiveCreation(data: string) {
    let output: File = new File(data, this.newFolder + '.ar');
    let file1: File = new File(data + '/' + this.newFolder, 'test1.xml');

    let out: OutputStream = new OutputStream();
    let input1: InputStream = new InputStream();
    out.setFilePath(output.getPath());
    input1.setFilePath(file1.getPath());
    let os: ArchiveOutputStream = ArchiveStreamFactory.DEFAULT.createArchiveOutputStream("ar", out, "");
    os.putArchiveEntry(new ArArchiveEntry("test1.xml", Long.fromNumber(file1.length()), 0, 0,
      ArArchiveEntry.DEFAULT_MODE, Long.fromNumber(new Date().getTime() / 1000)));
    IOUtils.copyStream(input1, os);
    os.closeArchiveEntry();
    os.close();
    AlertDialog.show({ title: '压缩成功',
      message: '请查看沙箱路径 ' + data + '/',
      confirm: { value: 'OK', action: () => {
        this.isDeCompressGArShow = true
      } }
    })
  }
```



### ar 解压功能

指定文件夹路径解压ar文件夹。

```javascript
import { ArchiveEntry, ArchiveUtils, ArArchiveInputStream, ArArchiveEntry, ArchiveStreamFactory, ArchiveOutputStream, InputStream, File,OutputStream,IOUtils} from '@ohos/commons-compress'
import fs from '@ohos.file.fs';
let filesDir = GlobalContext.getContext().getObject("FilesDir");
  jsUnArTest(): void {
    try{
      var data = filesDir
        this.testReadLongNamesBSD(data)
    }catch(error){
      console.error( error.message);
    }
  }

  testReadLongNamesBSD(data: string): void {
    let inFile: File = new File(data + '/' + this.newFolder, "longfile_bsd.ar");
    let input: InputStream = new InputStream();
    input.setFilePath(inFile.getPath());
    let s: ArArchiveInputStream = new ArArchiveInputStream(input);
    let tarArchiveEntry: ArchiveEntry = null;
    while ((tarArchiveEntry = s.getNextEntry()) != null) {
      let name: string = tarArchiveEntry.getName();
      let tarFile: File = new File(data + '/' + this.newFolder, name);
      if (name.indexOf('/') != -1) {
        try {
          let splitName: string = name.substring(0, name.lastIndexOf('/'));
          fs.mkdirSync(data + '/' + this.newFolder + '/' + splitName);
        } catch (err) {
        }
      }
      let fos: OutputStream = null;
      try {
        fos = new OutputStream();
        fos.setFilePath(tarFile.getPath())
        let read: number = -1;
        let buffer: Int8Array = new Int8Array(1024);
        while ((read = s.readBytes(buffer)) != -1) {
          fos.writeBytesOffset(buffer, 0, read);
        }
      } catch (e) {
        throw e;
      } finally {
        fos.close();
      }
    }
    AlertDialog.show({ title: '解压成功',
      message: '请查看沙箱路径 ' + data + '/' + this.newFolder,
      confirm: { value: 'OK', action: () => {
      } }
    })
  }
```



### brotli 解压功能

指定文件夹路径解压brotli文件夹。

```javascript
import { CompressorInputStream,CompressorStreamFactory,ArchiveInputStream,ArchiveStreamFactory,ArchiveEntry,InputStream,File,OutputStream,IOUtils} from '@ohos/commons-compress'
import fs from '@ohos.file.fs';

let filesDir = GlobalContext.getContext().getObject("FilesDir");
  brotilTest(): void {
    try{
      var data = filesDir
        this.generateTextFile(data, '/bla.tar.br', compressData)

        let input = new File(data, "/bla.tar.br");
        let output = new File(data, "/bla.tar");
        let out: OutputStream = new OutputStream();
        let input1: InputStream = new InputStream();
        out.setFilePath(output.getPath());
        input1.setFilePath(input.getPath());
        let inputs: CompressorInputStream = new CompressorStreamFactory().createCompressorNameInputStream("br", input1)
        IOUtils.copyStream(inputs, out);
        out.close();
        input1.close();
        AlertDialog.show({ title: '解缩成功',
          message: '请查看沙箱路径 ' + data + '/bla.tar',
          confirm: { value: 'OK', action: () => {
          } }
        })
      }catch(error){
        console.error('File to obtain the file directory. Cause: ' + error.message);
      }
  }

  generateTextFile(data: string, fileName: string, arr: Int8Array | Int32Array): void {
    let srcPath = data;
    try {
      fs.mkdirSync(srcPath);
    } catch (err) {
    }
    const writer = fs.openSync(srcPath + fileName, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE);
    fs.writeSync(writer.fd, arr.buffer);
    fs.closeSync(writer);
  }
```



### bzip2 压缩功能

指定文件夹路径压缩bzip2文件夹。

```javascript
import { CompressorInputStream,CompressorStreamFactory,InputStream,OutputStream,IOUtils,CompressorOutputStream} from '@ohos/commons-compress'
import fs from '@ohos.file.fs';
let filesDir = GlobalContext.getContext().getObject("FilesDir");
  bzip2FileTest(): void {
    try{
      var data = filesDir
        console.info('directory obtained. Data:' + data);
        let inputStream: InputStream = new InputStream();
        inputStream.setFilePath(data + '/hello.txt');
        let fOut: OutputStream = new OutputStream();
        fOut.setFilePath(data + '/hello.txt.bz2');
        let cos: CompressorOutputStream = new CompressorStreamFactory(false).createCompressorOutputStream("bzip2", fOut);
        IOUtils.copyStream(inputStream, cos);
        cos.close();
        inputStream.close();
        AlertDialog.show({ title: '压缩成功',
          message: '请查看沙箱路径 ' + data + '/hello.txt.gz',
          confirm: { value: 'OK', action: () => {
            this.isDeCompressBzip2Show = true
          } }
        })
    }catch(error){
      console.error('File to obtain the file directory. Cause: ' + error.message);
    }
  }

```



### bzip2 解压功能

指定文件夹路径解压bzip2文件夹。

```javascript
import { CompressorInputStream,CompressorStreamFactory,InputStream,OutputStream,IOUtils,CompressorOutputStream} from '@ohos/commons-compress'
import fs from '@ohos.file.fs';
let filesDir = GlobalContext.getContext().getObject("FilesDir");
  unBzip2FileTest(): void {
    try{
      var data = filesDir
        let inputStream: InputStream = new InputStream();
        inputStream.setFilePath(data + '/hello.txt.bz2');
        let fOut: OutputStream = new OutputStream();
        fOut.setFilePath(data + '/hello.txt');
        let input: CompressorInputStream = new CompressorStreamFactory(false).createCompressorNameInputStream("bzip2", inputStream);
        IOUtils.copyStream(input, fOut);
        inputStream.close();
        fOut.close();
        AlertDialog.show({ title: '解缩成功',
          message: '请查看沙箱路径 ' + data + '/hello.txt',
          confirm: { value: 'OK', action: () => {
          } }
        })
      }catch(error){
        console.error('File to obtain the file directory. Cause: ' + error.message);
      }
  }
```

### lz4 压缩功能

指定文件夹路径压缩lz4文件夹。

``` javascript
 import {lz4Compressed} from '@ohos/commons-compress'
import fs from '@ohos.file.fs';
let filesDir = GlobalContext.getContext().getObject("FilesDir");
  lz4CompressedTest(): void {
    try{
      var data = filesDir
        let timer1 = System.currentTimeMillis().toString()
        console.info(this.TAG + timer1)

        lz4Compressed(data + '/bla.tar', data + '/bla.tar.lz4')

        let timer2: string = System.currentTimeMillis().toString()
        console.info(this.TAG + timer2)

        AlertDialog.show({ title: '压缩成功',
          message: '请查看沙箱路径 ' + data + '/test.txt.lz4',
          confirm: { value: 'OK', action: () => {
            this.isDeCompressLz4Show = true
          } }
        })
      }catch(error){
      console.error('File to obtain the file directory. Cause: ' + error.message);
    }
  }
```

### lz4 解压功能

指定文件夹路径解压lz4文件夹。

``` javascript
import {lz4Decompressed} from '@ohos/commons-compress'  
import fs from '@ohos.file.fs';
let filesDir = GlobalContext.getContext().getObject("FilesDir");

  lz4DecompressedTest(): void {
    try{
      var data = filesDir

        let timer1 = System.currentTimeMillis().toString()
        console.info(this.TAG + timer1)

        lz4Decompressed(data + '/bla.tar.lz4-framed.lz4', data + '/bla.tar')

        let timer2: string = System.currentTimeMillis().toString()
        console.info(this.TAG + timer2)

        AlertDialog.show({ title: '解缩成功',
          message: '请查看沙箱路径 ' + data + '/test2.txt',
          confirm: { value: 'OK', action: () => {
          } }
        })
      }catch(error){
      console.error('File to obtain the file directory. Cause: ' + error.message);
    }
  }
```

### lzma，sevenz7 压缩功能

指定文件夹路径压缩lzma，sevenz7文件夹。

``` javascript
  import {Decoder, Encoder,InputStream,OutputStream,Exception,System } from '@ohos/commons-compress'
import fs from '@ohos.file.fs';

   encoder(path) {
    console.info(this.TAG + '开始')
    let inputStream: InputStream = new InputStream();
    let outputStream: OutputStream = new OutputStream();
    outputStream.setFilePath(path + '/test.xml.lzma')
    inputStream.setFilePath(path + '/test.xml')
    let stat = fs.statSync(path + '/test.xml');
    let encoder: Encoder = new Encoder();
    if (!encoder.SetAlgorithm(2))
    return
    if (!encoder.SetDictionarySize(1 << 23))
    return
    if (!encoder.SetNumFastBytes(128))
    return
    if (!encoder.SetMatchFinder(1))
    return
    if (!encoder.SetLcLpPb(3, 0, 2))
    return
    encoder.SetEndMarkerMode(false);
    encoder.WriteCoderProperties(outputStream);
    let fileSize: Long = Long.fromNumber(stat.size);
    for (let i = 0; i < 8; i++) {
      outputStream.write(fileSize.shiftRightUnsigned(8 * i).toInt() & 0xFF);
    }
    encoder.Code(inputStream, outputStream, Long.fromNumber(-1), Long.fromNumber(-1), null);
    outputStream.flush();
    outputStream.close();
    inputStream.close();
    console.info(this.TAG + '结束')
  }
```

### lzma，sevenz7 解压功能

指定文件夹路径解压lzma,sevenz7文件夹。

``` javascript
import {Decoder, Encoder,InputStream,OutputStream,Exception,System } from '@ohos/commons-compress'
import fs from '@ohos.file.fs';

decoder(path) {
    let decoder: Decoder = new Decoder();
    let inputStream: InputStream = new InputStream();
    inputStream.setFilePath(path + '/test.xml.lzma')
    let outputStream: OutputStream = new OutputStream();
    outputStream.setFilePath(path + '/test.xml')
    let propertiesSize = 5;
    let properties: Int8Array = new Int8Array(propertiesSize);
    if (inputStream.readBytesOffset(properties, 0, propertiesSize) != propertiesSize)
    throw new Exception("input .lzma file is too short");
    if (!decoder.SetDecoderProperties(properties))
    throw new Exception("Incorrect stream properties");
    let outSize: Long = Long.fromNumber(0);
    for (let i = 0; i < 8; i++) {
      let v: number = inputStream.read();
      if (v < 0)
      throw new Exception("Can't read stream size");
      outSize = outSize.or(Long.fromNumber(v).shiftLeft(8 * i));
    }
    if (!decoder.Code(inputStream, outputStream, outSize))
    throw new Exception("Error in data stream");
    outputStream.flush();
    outputStream.close();
    inputStream.close();
  }
```



### tar 压缩功能

指定文件夹路径解压tar文件夹。

``` javascript
import { File, InputStream, OutputStream, ArchiveStreamFactory, TarArchiveEntry, IOUtils } from '@ohos/commons-compress'
import fs from '@ohos.file.fs';
let filesDir = GlobalContext.getContext().getObject("FilesDir");
  jsTarTest(): void {
    try{
        this.testArArchiveCreation(filesDir);
    }catch(error){
    }
  }

testArArchiveCreation(data: string) {
    try {
      let output: File = new File(data, this.newFolder + '.tar');
      let file1: File = new File(data + '/' + this.newFolder, 'test1.xml');
      let input1: InputStream = new InputStream();
      input1.setFilePath(file1.getPath());
      let out: OutputStream = new OutputStream();
      out.setFilePath(output.getPath());
      let os: ArchiveOutputStream = ArchiveStreamFactory.DEFAULT.createArchiveOutputStream ("tar", out);
      let entry: TarArchiveEntry = new TarArchiveEntry();
      entry.tarArchiveEntryPreserveAbsolutePath2("testdata/test1.xml", false);
      entry.setModTime(Long.fromNumber(0));
      entry.setSize(Long.fromNumber(file1.length()));
      entry.setUserId(0);
      entry.setGroupId(0);
      entry.setUserName("avalon");
      entry.setGroupName("excalibur");
      entry.setMode(0o100000);
      os.putArchiveEntry(entry);
      IOUtils.copyStream(input1, os);
      os.closeArchiveEntry();
      os.close();
      AlertDialog.show({ title: '压缩成功',
        message: '请查看沙箱路径 ' + data + '/',
        confirm: { value: 'OK', action: () => {
          this.isDeCompressTarShow = true
        } }
      })
    } catch (e) {
      console.error("testArArchiveCreation " + e);
    }
  }
```

### tar 解压功能

指定文件夹路径解压tar文件夹。

``` javascript
import { File, InputStream, OutputStream, TarArchiveInputStream, TarConstants, TarArchiveEntry } from '@ohos/commons-compress'
import fs from '@ohos.file.fs';
let filesDir = GlobalContext.getContext().getObject("FilesDir");
  jsUnTarTest(): void {
    try{
        this.testUnCompressTar(filesDir);
      }catch(error){
      console.error('File to obtain the file directory. Cause: ' + error.message);
    }
  }
testUnCompressTar(data: string) {
    let input: File = new File(data, this.newFolder + '.tar');
    let input1: InputStream = new InputStream();
    input1.setFilePath(input.getPath());
    let tais: TarArchiveInputStream = new TarArchiveInputStream(input1, TarConstants.DEFAULT_BLKSIZE,
      TarConstants.DEFAULT_RCDSIZE, null, false);
    let tarArchiveEntry: TarArchiveEntry = null;
    while ((tarArchiveEntry = tais.getNextTarEntry()) != null) {
      let name: string = tarArchiveEntry.getName();
      let tarFile: File = new File(data + '/' + this.newFolder, name);
      if (name.indexOf('/') != -1) {
        try {
          let splitName: string = name.substring(0, name.lastIndexOf('/'));
          fs.mkdirSync(data + '/' + this.newFolder + '/' + splitName);
        } catch (err) {
        }
      }
      let fos: OutputStream = null;
      try {
        fos = new OutputStream();
        fos.setFilePath(tarFile.getPath())
        let read: number = -1;
        let buffer: Int8Array = new Int8Array(1024);
        while ((read = tais.readBytes(buffer)) != -1) {
          fos.writeBytesOffset(buffer, 0, read);
        }
        AlertDialog.show({ title: '解压成功',
          message: '请查看沙箱路径 ' + data + '/' + this.newFolder,
          confirm: { value: 'OK', action: () => {
            this.isDeCompressTarShow = true
          } }
        })
      } catch (e) {
        throw e;
      } finally {
        fos.close();
      }
    }
  }
```

### snappy 压缩解压功能

指定文件夹路径压缩解压sz文件夹。

``` javascript
import { snappyCompress } from '@ohos/commons-compress'
import fs from '@ohos.file.fs';
let filesDir = GlobalContext.getContext().getObject("FilesDir");
  @State newfile: string = 'bla.txt'
  @State newfile1: string = 'bla1.txt'

  snappyJsTest(value) {
    try {
      var data = filesDir
      if (value) {
        let path = data + '/' + this.newfile
        console.log('snappyCompress');
        snappyCompress(path, path + '.sz')
          .then(() => {
            AlertDialog.show({ title: '压缩成功',
              message: '请查看沙箱路径 ' + path + '.sz',
              confirm: { value: 'OK', action: () => {
                this.isDeCompressSnappyShow = true
              } }
            })
          });
      } else {
        snappyUncompress(data + '/' + this.newfile + '.sz', data + '/' + this.newfile1)
          .then(() => {
            AlertDialog.show({ title: '解缩成功',
              message: '请查看沙箱路径 ' + data + '/' + this.newfile1,
              confirm: { value: 'OK', action: () => {
              } }
            })
          });
      }
    } catch (error) {
      console.error('File to obtain the file directory. Cause: ' + error.message);
    }
  }

```

### dump 解压功能

指定文件夹路径解压dump文件夹。

``` javascript
import { File, InputStream, OutputStream, ArchiveStreamFactory, ArchiveInputStream, ArchiveEntry, IOUtils } from '@ohos/commons-compress'
import fs from '@ohos.file.fs';
let filesDir = GlobalContext.getContext().getObject("FilesDir");
jsDumpTest(): void {
     this.testDumpUnarchiveAll(filesDir,'dump/bla.dump')
}

testDumpUnarchiveAll(data: string, archive: string): void {
    let file1: File = new File(data, archive);
    //    fs.mkdirSync(data+'/lost+found')
    let input1: InputStream = new InputStream();
    input1.setFilePath(file1.getPath());
    let input2: ArchiveInputStream = null;

    input2 = ArchiveStreamFactory.DEFAULT.createArchiveInputStream("dump", input1, null);

    let entry: ArchiveEntry = input2.getNextEntry();
    while (entry != null) {
      let out: OutputStream = new OutputStream();
      let name: string = entry.getName().toString();
      let archiveEntry: File = new File(data, name);
      archiveEntry.getParentFile().getPath();

      if (entry.isDirectory()) {
        let splitName: string = name.substring(0, name.lastIndexOf('/'));
        try {
          fs.mkdirSync(data + '/' + splitName);
        } catch (e) {
          console.log(e);
        }
        entry = input2.getNextEntry();
        continue;
      }
      let output: File = new File(data, name);
      out.setFilePath(output.getPath());
      IOUtils.copyStream(input2, out);
      out.close();
      out = null;
      entry = input2.getNextEntry();
    }
    if (input2 != null) {
      input2.close();
    }
    input1.close();
  }
```

### deflate 压缩功能

指定文件夹路径压缩deflate文件夹。

``` javascript
import { DeflateFile } from '@ohos/commons-compress'
import fs from '@ohos.file.fs';
let filesDir = GlobalContext.getContext().getObject("FilesDir");
  DeflateFileTest(): void {
    try{
      var data = filesDir
        console.info('directory obtained. Data:' + data);
        DeflateFile(data + '/hello.txt', data + '/hello.txt.deflate')
          .then((isSuccess) => {
            if (isSuccess) {
              AlertDialog.show({ title: '压缩成功',
                message: '请查看沙箱路径 ' + data + '/test.txt.deflate',
                confirm: { value: 'OK', action: () => {
                  this.isDeCompressGZipShow = true
                } }
              })
            }
          });
    }catch(error){
      console.error('File to obtain the file directory. Cause: ' + error.message);
    }
  }
```

### deflate 解压功能

指定文件夹路径解压deflate文件夹。

``` javascript
import { InflateFile } from '@ohos/commons-compress'
import fs from '@ohos.file.fs';
let filesDir = GlobalContext.getContext().getObject("FilesDir");
InflateFileTest(): void {
    try{
      var data = filesDir
        InflateFile(data + "/hello.txt.deflate", data + '/test.txt')
          .then(() => {
            AlertDialog.show({ title: '解缩成功',
              message: '请查看沙箱路径 ' + data + '/test.txt',
              confirm: { value: 'OK', action: () => {
              } }
            })
          });
    }catch(error){
      console.error('File to obtain the file directory. Cause: ' + error.message);
    }
  }
```

### cpio 压缩功能

指定文件夹路径压缩cpio文件夹。

``` javascript
import {File, InputStream, OutputStream, ArchiveStreamFactory, ArchiveOutputStream, CpioArchiveEntry, IOUtils } from '@ohos/commons-compress'
import fs from '@ohos.file.fs';
let filesDir = GlobalContext.getContext().getObject("FilesDir");
  jsCpioTest(): void {
    try{
        this.testReadLongNamesBSD(filesDir)
      }catch(error){
        console.error('File to obtain the file directory. Cause: ' + error.message);
      }
  }

  testReadLongNamesBSD(data: string): void {
    let output: File = new File(data, this.newFolder + ".cpio");

    let file1: File = new File(data + '/' + this.newFolder, "test1.xml");
    let inputStream1 = new InputStream();
    inputStream1.setFilePath(file1.getPath());

    let out: OutputStream = new OutputStream();
    out.setFilePath(output.getPath());
    let os: ArchiveOutputStream = ArchiveStreamFactory.DEFAULT.createArchiveOutputStream("cpio", out);
    let archiveEntry1: CpioArchiveEntry = new CpioArchiveEntry();
    archiveEntry1.initCpioArchiveEntryNameSize("test1.xml", Long.fromNumber(file1.length()));
    os.putArchiveEntry(archiveEntry1);
    IOUtils.copyStream(inputStream1, os);
    os.closeArchiveEntry();

    os.close();
    out.close();

    AlertDialog.show({ title: '压缩成功',
      message: '请查看沙箱路径 ' + data + '/',
      confirm: { value: 'OK', action: () => {
        this.isDeCompressGArShow = true
      } }
    })
  }
```

### cpio 解压功能

指定文件夹路径解压cpio文件夹。

``` javascript
import {File, InputStream, OutputStream, CpioArchiveInputStream, CpioArchiveEntry, CpioConstants } from '@ohos/commons-compress'
import fs from '@ohos.file.fs';
let filesDir = GlobalContext.getContext().getObject("FilesDir");

jsUnCpioTest(): void {
try{
        this.testUnCompressCpio(filesDir)
      }catch(error){
        console.error('File to obtain the file directory. Cause: ' + error.message);
      }
}

  testUnCompressCpio(data: string) {
    let input: File = new File(data, this.newFolder + '.cpio');
    let input1: InputStream = new InputStream();
    input1.setFilePath(input.getPath());
    let tais = new CpioArchiveInputStream(input1, CpioConstants.BLOCK_SIZE, CharacterSetECI.ASCII.getName());
    let cpioArchiveEntry: CpioArchiveEntry = null;
    while ((cpioArchiveEntry = tais.getNextCPIOEntry()) != null) {
      let name: string = cpioArchiveEntry.getName();
      let tarFile: File = new File(data + '/' + this.newFolder, name);

      if (name.indexOf('/') != -1) {
        try {
          let splitName: string = name.substring(0, name.lastIndexOf('/'));
          fs.mkdirSync(data + '/' + this.newFolder + '/' + splitName);
        } catch (err) {
        }
      }

      let fos: OutputStream = null;
      try {
        fos = new OutputStream();
        fos.setFilePath(tarFile.getPath())
        let read: number = -1;
        let buffer: Int8Array = new Int8Array(1024);
        while ((read = tais.readBytes(buffer)) != -1) {
          fos.writeBytesOffset(buffer, 0, read);
        }
      } catch (e) {
        throw e;
      } finally {
        fos.close();
      }
    }
    AlertDialog.show({ title: '解压成功',
      message: '请查看沙箱路径' + data + '/' + this.newFolder + '/test1.xml',
      confirm: { value: 'OK', action: () => {
        this.isCompressGArFileShow = true
      } }
    })
  }
```

## 目录

```
/commons-compress # 三方库源代码
├── src      # 框架代码
│   └── main
│   	└── cpp 
│           ├── zstd   	# # zstd C源码目录
│           └── zstd.cpp     # zstd Napi封装接口
│   	└── ets
│   		└── components
│       		└── archivers
│           		├── ar  	# ar源代码存放目录
│           		├── cpio   	# cpio源代码存放目录
│           		├── dump  	# dump源代码存放目录
│           		├── lzma    # lzma源代码存放目录
│           		├── tar   	# tar源代码存放目录
│           		└── zip     # zip源代码存放目录
│       		└── compressors
│           		├── brotli  # brotli源代码存放目录
│           		├── bzip2   # bzip2源代码存放目录
│           		├── lz77support  # lz77support源代码存放目录
│           		├── lzw     # lzw源代码存放目录
│           		├── snappy  # snappy源代码存放目录
│           		├── xz     	# xz源代码存放目录
│           		└── z    	# z源代码存放目录
│       		├── deflate     # deflate源代码存放目录
│       		├── gzip  # gzip源代码存放目录
│       		├── lz4   # lz4源代码存放目录
│       		├── util  # 工具源代码存放目录
│       		└── zstd  # zstd源代码存放目录

```



## 接口说明

| **接口**                                                     | 参数                                                                                        | 功能                                           |
| ------------------------------------------------------------ |-------------------------------------------------------------------------------------------| ---------------------------------------------- |
| createArchiveOutputStream(archiverName: string, out: OutputStream) | archiverName：存档名称<br/>out：存档输出流                                                           | 创建存档输出流。                               |
| zlib.compressFile(inFile: string, outFile: string, options: Options, callback: AsyncCallback<void>): void   | inFile：要压缩的文件的路径。<br/>inFile：要压缩的文件的路径。 <br/>Options：压缩文件的选项。<br/>callback-压缩文件结果的回调。 | zip压缩方法。                                  |
| zlib.decompressFile(inFile: string, outFile: string, options: Options, callback: AsyncCallback<void>): void | inFile：要解压缩的文件的路径。<br/>outFile：输出解压缩文件的路径。<br/>Options：解压缩文件的选项。<br/>callback：解压缩文件结果的回调。 | zip解压方法。                                  |
| gzipFile(src: string, dest: string)                          | src：文件路径<br/>dest：生成后的文件名称                                                                | gzip压缩方法。                                 |
| unGzipFile(src: string, target: string)                      | path：解压后的文件路径和名称<br/>target：解压后的路径                                                        | gzip解压方法。                                 |
| createCompressorOutputStream(name: string, out: OutputStream) | name：压缩器名称<br/>out：输出流                                                                    | 从存档程序名称和输出流创建存档输出流。         |
| createCompressorInputStream(  name: string,  inputStream: InputStream, actualDecompressConcatenated: boolean) | name：压缩器名称<br/>inputStream：输入流<br/>actualDecompressConcatenated：解压级                       | 从存档程序名称和输入流创建存档输入流。         |
| copy(input: InputStream, output: OutputStream)               | input：输入流<br/>output：输出流                                                                  | 将输入流的内容复制到输出流中。                 |
| setFilePath(path: string)                                    | path：指定路径                                                                                 | 打开指定文件路径。                             |
| createCompressorInputStream2(name: string, inputStream: InputStream) | name：压缩器名称<br/>inputStream：输入流                                                            | 从压缩器名称和输入创建压缩器输入流。           |
| readFully(input: InputStream, array: Int8Array)              | input：输入流<br/>array：需要填充数组                                                                | 从输入中读取尽可能多的信息，以填充给定的数组。 |
| ZSTDCompress(path: string, filepath: string, level: number)               | path：需要压缩的文件包路径， filepath：压缩文件存放的路径，level：压缩等级（1~9）                                       | zstd压缩方法                                |
| ZSTDDecompress(path: string, dest: string) | path：需要解压的文件包路径,dest：解压文件存放的路径                                                            | zstd解压方法。                               |
| lz4Compressed(src: string, dest: string)                     | src：文件路径<br/>dest：生成后的文件名称                                                                | 压缩为lz4文件。                                |
| lz4Decompressed(src: string, target: string)                 | path：解压后的文件路径和名称<br/>target：解压后的路径                                                        | 解压lz4文件。                                  |
| createArchiveOutputStreamLittle(archiverName: string, out: OutputStream) | archiverName：存档名称<br/>out：输出流                                                             | 创建存档输出流。                               |
| createArchiveInputStream(  archiverName: string,  inputStream: InputStream,  actualEncoding: string) | archiverName：存档名称<br/>inputStream：输入流<br/>actualEncoding：条目编码                             | 从存档程序名称和输入流创建存档输入流。         |
| snappyCompress(path, newfile)                                | path：文件路径<br/>newfile：生成后的文件名称                                                            | 压缩为sz文件。                                 |
| snappyUncompress(path, newfolder, newfile, newfile1)         | path：文件路径<br/>newfolder： 文件名称<br/>newfile：生成后的文件名称<br/>newfile1：文件名称                      | 解压sz文件。                                   |
| DeflateFile(src: string, dest: string)                       | src：文件路径<br/>dest：生成后的文件名称                                                                | 压缩为deflate文件。                            |
| InflateFile(src: string, target: string)                     | src：解压后的文件路径和名称<br/>target：解压后的路径                                                         | 解压deflate文件。                              |
| CpioArchiveInputStream(input: InputStream, blockSize: number, encoding: string)   | input: 文件输入流<br/>blockSize: 块大小<br/>encoding: 字符集的名称  | 处理 CPIO 文件的输入流类。        |
| CpioArchiveEntry                    | -                                           | CPIO文件类                 |

## 关于混淆
- 代码混淆，请查看[代码混淆简介](https://docs.openharmony.cn/pages/v5.0/zh-cn/application-dev/arkts-utils/source-obfuscation.md)
- 如果希望commons-compress库在代码混淆过程中不会被混淆，需要在混淆规则配置文件obfuscation-rules.txt中添加相应的排除规则：
```
-keep
./oh_modules/@ohos/commons-compress
```

## 约束与限制

在下述版本验证通过：

- DevEco Studio: NEXT Beta1-5.0.3.806, SDK:API12 Release(5.0.0.66)
- Deveco Studio:4.0 (4.0.3.512),SDK:API10 (4.0.10.9)
- DevEco Studio版本: 4.0Canary1(4.0.3.212), SDK: API10(4.0.8.3)

## 开源协议

本项目基于 [Apache License 2.0](https://gitcode.com/openharmony-tpc/CommonsCompress/blob/master/LICENSE) ，请自由地享受和参与开源。

## 贡献代码

使用过程中发现任何问题都可以提 [Issue](https://gitcode.com/openharmony-tpc/CommonsCompress/issues) 给组件，当然，也非常欢迎发 [PR](https://gitcode.com/openharmony-tpc/CommonsCompress/pulls) 共建。

## 相关项目

- [zstd](https://github.com/facebook/zstd) —— Zstandard是一种快速无损压缩算法， 针对 ZLIB 级别的实时压缩场景和更好的压缩比。
- [7z](https://www.7-zip.org/sdk.html) —— 7z是新的存档格式，提供高压缩比。
- [long.js](https://github.com/dcodeIO/long.js) —— long.js是一个 Long 类，用于表示从闭包库派生的 64 位二进制补码整数值，以供独立使用，并使用无符号支持进行扩展。
- [xz](https://tukaani.org/xz/java.html) —— xz是一款免费的通用数据压缩软件，具有较高的压缩比。