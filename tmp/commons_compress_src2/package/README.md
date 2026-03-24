# commons-compress
## Introduction
**commons-compress** provides APIs for working with various compression/decompression formats based on the open-source [Apache Commons Compress](https://github.com/apache/commons-compress) in TypeScript. It supports a wide variety of formats, including bzip2, gzip, LZMA, XZ, Snappy, LZ4, Brotli, Deflate, Zstandard, ar, cpio, tar, zip, dump, and 7z, on OpenHarmony.

![compp.gif](compp.gif)
## How to Install

```
  ohpm install @ohos/commons-compress
```
For details, see [Installing an OpenHarmony HAR](https://gitcode.com/openharmony-tpc/docs/blob/master/OpenHarmony_har_usage.en.md).

## Configuring the x86 Emulator

Running Your App/Service on an Emulator.

## How to Use

### Configuring a Global Path

Configure a global path in the EntryAbility file.

``` javascript
GlobalContext.getContext().setObject("context", this.context);
```

### File Storage Path

During application development and debugging, you may need to push files to the application sandbox to access or test the files in the application. For details, see [Pushing Files to an Application Sandbox Directory](https://gitcode.com/openharmony/docs/blob/master/en/application-dev/file-management/send-file-to-app-sandbox.md#%E5%BA%94%E7%94%A8%E6%B2%99%E7%AE%B1%E8%B7%AF%E5%BE%84%E5%92%8C%E8%B0%83%E8%AF%95%E8%BF%9B%E7%A8%8B%E8%A7%86%E8%A7%92%E4%B8%8B%E7%9A%84%E7%9C%9F%E5%AE%9E%E7%89%A9%E7%90%86%E8%B7%AF%E5%BE%84).

### zip Decompression Capability

The zip decompression capability of this software is implemented by calling the system API @ohos.zlib. For details, see [@ohos.zlib (Zip)](https://docs.openharmony.cn/pages/v4.1/en/application-dev/reference/apis-basic-services-kit/js-apis-zlib.md).

### zip Compression

Compress a folder as .zip in the specified directory.

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
          AlertDialog.show ({title: 'Compression successful',
            message: 'Check the sandbox path.' + data + '/',
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

### zip Decompression

Decompress a .zip file in the specified directory.

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
          AlertDialog.show ({title: 'Decompression successful.',
            message: 'Check the sandbox path.' + data,
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

### gzip Compression

Compress a folder as .gz in the specified directory.

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
              AlertDialog.show ({title: 'Compression successful',
                message: 'Check the sandbox path.' + data + '/test.txt.gz',
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

### gzip Decompression

Decompress a .gz file in the specified directory.

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
              AlertDialog.show ({title: 'Decompression successful.',
                message: 'Check the sandbox path.' + data + '/test.txt',
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



### XZ Compression

Compress a folder as .xz in the specified directory.

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
        AlertDialog.show ({title: 'Compression successful',
          message: 'Check the sandbox path.' + data + '/hello.txt.xz',
          confirm: { value: 'OK', action: () => {
            this.isDeCompressBzip2Show = true
          } }
        })
    }catch(error){
      console.error('File to obtain the file directory. Cause: ' + error.message);
    }
  }

```

### XZ Decompression

Decompress an .xz file in the specified directory.

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
        AlertDialog.show ({title: 'Decompression successful.',
          message: 'Check the sandbox path.' + data + '/hello1.txt',
          confirm: { value: 'OK', action: () => {
          } }
        })
    }catch(error){
      console.error('File to obtain the file directory. Cause: ' + error.message);
    }
  }
```



### Z Decompression

Decompress a .Z file in the specified directory.

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
        AlertDialog.show ({title: 'Decompression successful.',
          message: 'Check the sandbox path.' + data + '/bla.tar',
          confirm: { value: 'OK', action: () => {
          } }
        })
       }catch(error){
      console.error('File to obtain the file directory. Cause: ' + error.message);
    }
  }
```



### Zstandard Compression

Compress a folder as .zstd in the specified directory.

```javascript
import { ZstdCompress } from '@ohos/commons-compress';
let filesDir = GlobalContext.getContext().getObject("FilesDir");
async testZstdCompressed(): Promise<void> {
    try {
        var data = filesDir
        await zstdCompress(data + "/hello.txt", data + "/hello.txt.zstd", 1, 3).then((value) => {
            if (value) {
                AlertDialog.show ({title: 'Compression successful',
                    message: 'Check the sandbox path.' + data + '/hello.txt.zstd',
                    confirm: { value: 'OK', action: () => {
                        this.isDeCompressZstdShow = true
                    } }
                })
            } else {
                AlertDialog.show ({title: 'Compression failed.',
                    message: 'Check and try again.',
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

### Zstandard Decompression

Decompress a .zstd file in the specified directory.

```javascript
import { ZstdDecompress } from '@ohos/commons-compress';
let filesDir = GlobalContext.getContext().getObject("FilesDir");
async testZstdDecompressed(): Promise<void> {
    try {
        var data = filesDir
        await zstdDecompress(data + "/hello.txt.zstd", data + '/newhello.txt').then((value) => {
            if (value) {
                AlertDialog.show ({title: 'Decompression successful',
                    message: 'Check the sandbox path.' + data + '/newhello.txt',
                    confirm: { value: 'OK', action: () => {
                    } }
                })
            } else {
                AlertDialog.show ({title: 'Decompression failed.',
                    message: 'Check and try again.',
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

### ar Compression

Compress a folder as .ar in the specified directory.

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
    AlertDialog.show ({title: 'Compression successful',
      message: 'Check the sandbox path.' + data + '/',
      confirm: { value: 'OK', action: () => {
        this.isDeCompressGArShow = true
      } }
    })
  }
```



### ar Decompression

Decompress an .ar file in the specified directory.

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
    AlertDialog.show ({title: 'Decompression successful',
      message: 'Check the sandbox path.' + data + '/' + this.newFolder,
      confirm: { value: 'OK', action: () => {
      } }
    })
  }
```



### Brotli Decompression

Decompress a .br file in the specified directory.

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
        AlertDialog.show ({title: 'Decompression successful.',
          message: 'Check the sandbox path.' + data + '/bla.tar',
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



### bzip2 Compression

Compress a folder as .bz2 in the specified directory.

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
        AlertDialog.show ({title: 'Compression successful',
          message: 'Check the sandbox path.' + data + '/hello.txt.gz',
          confirm: { value: 'OK', action: () => {
            this.isDeCompressBzip2Show = true
          } }
        })
    }catch(error){
      console.error('File to obtain the file directory. Cause: ' + error.message);
    }
  }

```



### bzip2 Decompression

Decompress a .bz2 file in the specified directory.

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
        AlertDialog.show ({title: 'Decompression successful.',
          message: 'Check the sandbox path.' + data + '/hello.txt',
          confirm: { value: 'OK', action: () => {
          } }
        })
      }catch(error){
        console.error('File to obtain the file directory. Cause: ' + error.message);
      }
  }
```

### LZ4 Compression

Compress a folder as .lz4 in the specified directory.

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

        AlertDialog.show ({title: 'Compression successful',
          message: 'Check the sandbox path.' + data + '/test.txt.lz4',
          confirm: { value: 'OK', action: () => {
            this.isDeCompressLz4Show = true
          } }
        })
      }catch(error){
      console.error('File to obtain the file directory. Cause: ' + error.message);
    }
  }
```

### LZ4 Decompression

Decompress an .lz4 file in the specified directory.

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

        AlertDialog.show ({title: 'Decompression successful.',
          message: 'Check the sandbox path.' + data + '/test2.txt',
          confirm: { value: 'OK', action: () => {
          } }
        })
      }catch(error){
      console.error('File to obtain the file directory. Cause: ' + error.message);
    }
  }
```

### LZMA and 7z Compression

Compress a folder as .lzma in the specified directory.

``` javascript
  import {Decoder, Encoder,InputStream,OutputStream,Exception,System } from '@ohos/commons-compress'
import fs from '@ohos.file.fs';

   encoder(path) {
    console.info (this.TAG + 'Start')
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
    console.info (this.TAG + 'End')
  }
```

### LZMA and 7z Decompression

Decompress an .lzma file in the specified directory.

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



### tar Compression

Compress a folder as .tar in the specified directory.

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
      AlertDialog.show ({title: 'Compression successful',
        message: 'Check the sandbox path.' + data + '/',
        confirm: { value: 'OK', action: () => {
          this.isDeCompressTarShow = true
        } }
      })
    } catch (e) {
      console.error("testArArchiveCreation " + e);
    }
  }
```

### tar Decompression

Decompress a .tar file in the specified directory.

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
        AlertDialog.show ({title: 'Decompression successful',
          message: 'Check the sandbox path.' + data + '/' + this.newFolder,
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

### Snappy Compression and Decompression

Compress a folder as .sz, and decompress an .sz file.

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
            AlertDialog.show ({title: 'Compression successful',
              message: 'Check the sandbox path.' + path + '.sz',
              confirm: { value: 'OK', action: () => {
                this.isDeCompressSnappyShow = true
              } }
            })
          });
      } else {
        snappyUncompress(data + '/' + this.newfile + '.sz', data + '/' + this.newfile1)
          .then(() => {
            AlertDialog.show ({title: 'Decompression successful.',
              message: 'Check the sandbox path.' + data + '/' + this.newfile1,
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

### dump Decompression

Decompress a .dump file in the specified directory.

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

### Deflate Compression

Compress a folder in Deflate format in the specified directory.

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
              AlertDialog.show ({title: 'Compression successful',
                message: 'Check the sandbox path.' + data + '/test.txt.deflate',
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

### Deflate Decompression

Decompress a file in Deflate format in the specified directory.

``` javascript
import { InflateFile } from '@ohos/commons-compress'
import fs from '@ohos.file.fs';
let filesDir = GlobalContext.getContext().getObject("FilesDir");
InflateFileTest(): void {
    try{
      var data = filesDir
        InflateFile(data + "/hello.txt.deflate", data + '/test.txt')
          .then(() => {
            AlertDialog.show ({title: 'Decompression successful.',
              message: 'Check the sandbox path.' + data + '/test.txt',
              confirm: { value: 'OK', action: () => {
              } }
            })
          });
    }catch(error){
      console.error('File to obtain the file directory. Cause: ' + error.message);
    }
  }
```

### cpio Compression

Compress a folder as .cpio in the specified directory.

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

    AlertDialog.show ({title: 'Compression successful',
      message: 'Check the sandbox path.' + data + '/',
      confirm: { value: 'OK', action: () => {
        this.isDeCompressGArShow = true
      } }
    })
  }
```

### cpio Decompression

Decompress a .cpio file in the specified directory.

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
    AlertDialog.show ({title: 'Decompression successful',
      message: 'Check the sandbox path.' + data + '/' + this.newFolder + '/test1.xml',
      confirm: { value: 'OK', action: () => {
        this.isCompressGArFileShow = true
      } }
    })
  }
```

## Directory Structure

```
/commons-compress # Source code of the commons-compress library
├── src      # Framework code
│   └── main
│   	└── cpp 
│           ├── zstd   	     # zstd C source code
│           └── zstd.cpp     # Zstandard Node-API
│   	└── ets
│   		└── components
│       		└── archivers
│           		├── ar  	# ar source code
│           		├── cpio   	# cpio source code
│           		├── dump  	# dump source code
│           		├── lzma    # LZMA source code
│           		├── tar   	# tar source code
│           		└── zip     # zip source code
│       		└── compressors
│           		├── brotli       # Brotli source code
│           		├── bzip2        # bzip2 source code
│           		├── lz77support  # LZ77 source code
│           		├── lzw          # LZW source code
│           		├── snappy       # Snappy source code
│           		├── xz     	     # XZ source code
│           		└── z    	     # Z source code
│       		├── deflate          # Deflate source code
│       		├── gzip  # gzip source code
│       		├── lz4   # LZ4 source code
│       		├── util  # Utility source code
│       		└── zstd  # Zstandard source code

```



## Available APIs

| API                                                    | Parameter                                                                                       | Description                                          |
| ------------------------------------------------------------ |-------------------------------------------------------------------------------------------| ---------------------------------------------- |
| createArchiveOutputStream(archiverName: string, out: OutputStream) | **archiverName**: archiver name.<br>**out**: archive output stream created.                                                          | Creates an archive output stream.                              |
| zlib.compressFile(inFile: string, outFile: string, options: Options, callback: AsyncCallback<void>): void   | **inFile**: path of the file to compress.<br>**outFile**: path of the file compressed.<br>**Options**: options for compressing the file.<br>**callback**: callback used to return the file compression result.| Compresses a file in .zip format.                                 |
| zlib.decompressFile(inFile: string, outFile: string, options: Options, callback: AsyncCallback<void>): void | **inFile**: path of the file to decompress.<br>**outFile**: path of the decompressed file.<br>**Options**: options for decompressing the file.<br>**callback**: callback used to return the file decompression result.| Decompresses a .zip file.                                 |
| gzipFile(src: string, dest: string)                          | **src**: path of the file to compress.<br>**dest**: name of the generated file.                                                               | Compresses a file in .gzip format.                                |
| unGzipFile(src: string, target: string)                      | **src**: path and name of the file to decompress.<br>**target**: path of the file decompressed.                                                       | Decompresses a .gzip file.                                |
| createCompressorOutputStream(name: string, out: OutputStream) | **name**: name of the compressor.<br>**out**: output stream.                                                                   | Creates a compressor output stream based on the specified compressor name and output stream.        |
| createCompressorInputStream(  name: string,  inputStream: InputStream, actualDecompressConcatenated: boolean) | **name**: name of the compressor.<br>**inputStream**: input stream.<br>**actualDecompressConcatenated**: whether to handle concatenated compressed streams.                      | Creates a compressor input stream based on the specified compressor name and input stream.        |
| copy(input: InputStream, output: OutputStream)               | **input**: input stream.<br>**output**: output stream.                                                                 | Copies data from an input stream to an output stream.                |
| setFilePath(path: string)                                    | **path**: path of the file to set.                                                                                | Sets a file path.                            |
| createCompressorInputStream2(name: string, inputStream: InputStream) | **name**: name of the compressor.<br>**inputStream**: input stream.                                                           | Creates a compressor input stream based on the specified compressor name and input stream. Compared with **createCompressorInputStream()**, this API does not have the option for handling concatenated streams.          |
| readFully(input: InputStream, array: Int8Array)              | **input**: input stream.<br>**array**: array to be filled.                                                               | Reads data from an input stream and fills a given array until the array is fully populated.|
| ZSTDCompress(path: string, filepath: string, level: number)               | **path**: path of the file to compress.<br>**filepath**: path of the compressed file.<br>**level**: compression level, which ranges from 1 to 9.                                      | Compresses a file using the Zstandard algorithm with the given compression level.                               |
| ZSTDDecompress(path: string, dest: string) | **path**: path of the file to decompress.<br>**dest**: path of the decompressed file.                                                           | Decompresses a file using the Zstandard algorithm.                              |
| lz4Compressed(src: string, dest: string)                     | **src**: path of the file to compress.<br>**dest**: name of the generated file.                                                               | Compresses a file using the LZ4 algorithm.                               |
| lz4Decompressed(src: string, target: string)                 | **src**: path and name of the file to decompress.<br>**target**: path of the file decompressed.                                                       | Decompresses a file using the LZ4 algorithm.                                 |
| createArchiveOutputStreamLittle(archiverName: string, out: OutputStream) | **archiverName**: archiver name.<br>**out**: output stream.                                                            | Creates an archive output stream.                              |
| createArchiveInputStream(  archiverName: string,  inputStream: InputStream,  actualEncoding: string) | **archiverName**: archiver name.<br>**inputStream**: input stream.<br>**actualEncoding**: encoding.                            | Creates an archive input stream with the specified encoding format.        |
| snappyCompress(path, newfile)                                | **Path**: path of the file to compress.<br>**newfile**: name of the generated file.                                                           | Compresses a file using Snappy.                                |
| snappyUncompress(path, newfolder, newfile, newfile1)         | **Path**: path of the file to decompress.<br>**newfolder**: Directory where the decompressed file is generated.<br>**newfile**: name of the decompressed file.<br>**newfile1**: alternative name of the decompressed file.                     | Decompresses a file using Snappy.                                  |
| DeflateFile(src: string, dest: string)                       | **src**: path of the file to compress.<br>**dest**: name of the generated file.                                                               | Compresses a file using Deflate.                           |
| InflateFile(src: string, target: string)                     | **src**: path and name of the file to decompress.<br>**target**: path of the file decompressed.                                                        | Decompresses a file using Deflate.                             |
| CpioArchiveInputStream(input: InputStream, blockSize: number, encoding: string)   | **input**: File input stream<br/>**blockSize**: Block size<br/>**encoding**: Name of character set                                                                                                                         | Class for processing input streams of CPIO files. |
| CpioArchiveEntry                    | -                                                                                                                                                                                                                          | CPIO File Entry             |
## About obfuscation
- Code obfuscation, please see[Code Obfuscation](https://docs.openharmony.cn/pages/v5.0/zh-cn/application-dev/arkts-utils/source-obfuscation.md)
- If you want the commons-compress library not to be obfuscated during code obfuscation, you need to add corresponding exclusion rules in the obfuscation rule configuration file obfuscation-rules.txt：
```
-keep
./oh_modules/@ohos/commons-compress
```

## Constraints

This project has been verified in the following versions:

- DevEco Studio: NEXT Beta1-5.0.3.806, SDK:API12 Release(5.0.0.66)
- DevEco Studio: 4.0 (4.0.3.512),SDK:API10 (4.0.10.9)
- DevEco Studio: 4.0Canary1 (4.0.3.212); SDK: API10(4.0.8.3)

## License

This project is licensed under [Apache License 2.0](https://gitcode.com/openharmony-tpc/CommonsCompress/blob/master/LICENSE).

## How to Contribute

If you find any problem during the use, submit an [issue](https://gitcode.com/openharmony-tpc/CommonsCompress/issues) or a [PR](https://gitcode.com/openharmony-tpc/CommonsCompress/pulls).

## Related Projects

- [zstd](https://github.com/facebook/zstd): a fast lossless compression algorithm, targeting real-time compression scenarios at zlib-level and better compression ratios.
- [7z](https://www.7-zip.org/sdk.html): a new archive format that provides high compression ratio.
- [long.js](https://github.com/dcodeIO/long.js): a Long class for representing a 64 bit two's-complement integer value derived from the Closure Library for stand-alone use and extended with unsigned support.
- [xz](https://tukaani.org/xz/java.html): a free data compression software with a high compression ratio. xz creates much smaller archives than gzip while using the same options.

