# ohos_minizip

## Introduction
This project provides a decompression library based on minizip_ng.

## How to Install

```shell
ohpm install @ohos/minizip
```
For details about the OpenHarmony ohpm environment configuration, see [OpenHarmony HAR](https://gitcode.com/openharmony-tpc/docs/blob/master/OpenHarmony_har_usage.md).

### How to Build

This project depends on the bzip2, minizip-ng, openssl, xz, and zstd libraries. You need to compile the generated .so files and header files yourself.

Refer to [bzip2 local compilation script](https://gitcode.com/openharmony-sig/tpc_c_cplusplus/tree/master/community/bzip2_1_0_8)

Refer to [minizip-ng local compilation script](https://gitcode.com/openharmony-sig/tpc_c_cplusplus/tree/master/community/minizip-ng)

Refer to [openssl local compilation script](https://gitcode.com/openharmony-sig/tpc_c_cplusplus/tree/master/thirdparty/openssl)

Refer to [xz local compilation script](https://gitcode.com/openharmony-sig/tpc_c_cplusplus/tree/master/community/xz)

Refer to [zstd local compilation script](https://gitcode.com/openharmony-sig/tpc_c_cplusplus/tree/master/thirdparty/zstd)

Under the cpp directory, create a third_party folder, then copy the compiled libraries bzip2_1_0_8, minizip-ng, openssl, xz, and zstd into this folder. Rename bzip2_1_0_8 to bzip2, as shown in the following diagram:

![img.png](image/third.png)

## How to Use

### Decompressing a ZIP File to Obtain Its Content

```typescript
import { MinizipNative } from '@ohos/minizip'

let minizipEntry = new MinizipNative(this.selectFilePath);
if (minizipEntry.Open() == 0) {
  let entryNames = minizipEntry.GetEntryNames();
  for (let i = 0; i < entryNames.length; i++) {
    console.log('Minizip names:' + entryNames[i]);
    if(!entryNames[i].endsWith("/")) {
      let arrBuffer = minizipEntry.ExtractFileToJS(entryNames[i], this.password);
      console.log("Minizip arrBuffer: " + arrBuffer?.byteLength)
    }
  }
}
```

1. Use a third-party library to decompress a ZIP file to the memory and return the file content to the JS side.
2. Call **GetEntryNames()** to obtain all folder paths and file paths of the ZIP file.
3. Use **ExtractFileToJS(entryname, password)** to decompress the specified file and return the file content to the JS side. If the file does not have a password, call the code below:
```typescript
ExtractFileToJS(entryname, "");
```

### Decompressing a ZIP File to a Disk
```typescript
import { unzipToDirectory } from '@ohos/minizip'

unzipToDirectory(this.selectFilePath, this.targetPath, this.password).then(() => {
  
}).catch(() => {
 
});
```

### Compress the file into a ZIP package and retrieve the file content

```typescript
import { MinizipCompressNative } from '@ohos/minizip'

let minizipCompressEntry = new MinizipCompressNative(this.selectFilePath);
if (minizipCompressEntry.Create() == 0) {
  let arrBuffer = minizipCompressEntry.CompressToJS(this.targetPath, this.password);
  console.log("Minizip arrBuffer: " + arrBuffer?.byteLength)
}
```

1. Use a third-party library to compress file contents into a zip package and return the result to JS.
2. CompressToJS(entryname, password),Compresses the specified file(s) and returns the content to the JS side. If the file has no password, pass an empty string, e.g.:
```typescript
CompressToJS(entryname, "");
```

### Compress the ZIP package to disk

```typescript
import { MinizipCompressNative } from '@ohos/minizip'

let minizipCompressEntry = new MinizipCompressNative(this.selectFilePath， this.selectFilePath);
if (minizipCompressEntry.Create() == 0) {
  let code : number = minizipCompressEntry.Compress(this.targetPath, this.password);
  console.log("" + code);
  minizipCompressEntry.Close();
}
```

## Available APIs

| API            | Parameter                                                        | Parameter Description                                                                                                                                                                                                               | Return Value                                                                                                                                                                 | API Description            |
| ---------------- | ------------------------------------------------------------ |-------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------------| --------------------- |
| MinizipNative    | path:string                                                  | Path of the ZIP file                                                                                                                                                                                                                | **MinizipNative** instance                                                                                                                                                   | Creates a **MinizipNative** instance|
| Open             | N/A                                                          | N/A                                                                                                                                                                                                                                 | **0** if the file is opened successfully                                                                                                                                     | Opens a file             |
| SetCharEncoding  | charEncoding:number                                          | **charEncoding**: character encoding type. The value can be **437** (for English and some Western European languages), **932** (for Japanese), **936** (for Simplified Chinese), **950** (for Traditional Chinese), or **65001** (for UTF-8) | N/A                                                                                                                                                                          | Sets the character encoding type |
| GetEntryNames    | N/A                                                          | N/A                                                                                                                                                                                                                                 | **Array\<string>**: list of files obtained. If **SetCharEncoding** has been called to set the character encoding type, the file name string encoded in UTF-8 format is returned | Obtains the file list       |
| ExtractFileToJS  | entryName : string, password : string                        | **entryName**: file name<br>**password**: password                                                                                                                                                                                  | **ArrayBuffer** or **undefined**: decompressed file content. If the password is incorrect or **entryName** is a folder name, **undefined** is returned                       | Decompresses a file        |
| unzipToDirectory | selectPath: string, targetPath: string, password?: string, charEncoding?: number | **selectPath**: path of the file to decompress<br>**targetPath**: path to which the file is decompressed<br>**password?**: password<br>**charEncoding?**: character encoding format                                                 | **Promise\< string >**: whether the file is decompressed successfully                                                                                                        | Decompresses a file to a folder |
| IsEncrypto       | entryName : string                                                               | entryName: entry file name                                                                                                                                                                                                          | **boolean**: Determine whether the file is encrypted                                                                                                                         | Determine whether the file is encrypted  |
| IsUtf8           | entryName : string                                                               | entryName: entry file name                                                                                                                                                                                                          | **boolean**: Determine whether the file path is utf8 encoded                                                                                                                 | Determine whether the file path is utf8 encoded |


| API                   | Parameter                            | Parameter Description                                        | Return Value                                                 | API Description                         |
| --------------------- | ------------------------------------ | ------------------------------------------------------------ | ------------------------------------------------------------ | --------------------------------------- |
| MinizipCompressNative | catchPath:string, zipFilePath:string | catchPath:Temporary storage path for the zip content，zipFilePath:Path to the zip file | MinizipCompressNative instance                               | Creates a MinizipCompressNative instance |
| Create                | N/A                                  | N/A                                                          | Returns `0` on successful file creation                      | Creates a zip file                      |
| Close                 | N/A                                  | N/A                                                          | N/A                                                          | Closes the zip file                     |
| SetCompressMethod     | compressMethod:number                | compressMethod: Compression method，The value can be 0(No compression) 8(Deflate compression) 12(Bzip2 compression) 14(LZMA1 compression) 93(ZSTD compression) 95(XZ compression) | Returns `0` on success                                       | Sets the compression method             |
| SetCompressLevel      | compressLevel:number                 | compressLevel：Compression level，The value can be -1(Default compression  level) 2(Fast compression  level) 6(Mid compression  level) 9(Slow compression  level) | Returns `0` on success                                       | Sets the compression level              |
| SetzipFilePath        | zipFilePath:string                   | zipFilePath：Name of the zip file                            | N/A                                                          | Sets the zip file name                  |
| Compress              | entries : Array, password : string   | entries : Files to compress, password : Password             | Returns `0` on success                                       | Compresses files                        |
| CompressToJS          | entries : Array,  password : string  | entries :Files to compress， password：Password              | Returns an `ArrayBuffer` (compressed data) or `undefined` (if failed or wrong password) | Compresses files and retrieves content  |

## Precautions
- To create a **minizipNative** object, you must pass in a complete file path, which consists of the file path and file name.

- You must call the **Open** function after creating an object. The **Open** function can be called only once each time the **new minizipNative** function is called. If the return value of the **Open** function is not **0**, the file fails to be opened.

## About obfuscation
- Code obfuscation, please see[Code Obfuscation](https://docs.openharmony.cn/pages/v5.0/zh-cn/application-dev/arkts-utils/source-obfuscation.md).
- If you want the minizip library not to be obfuscated during code obfuscation, you need to add corresponding exclusion rules in the obfuscation rule configuration file obfuscation-rules.txt：
```
-keep
./oh_modules/@ohos/minizip
```

## Constraints
This project has been verified in the following version:

DevEco Studio: NEXT Beta1-5.0.3.806, SDK: API12 Release (5.0.0.66).

DevEco Studio: NEXT Developer Beta1-5.0.3.320, SDK: API 12 (5.0.0.23).

## Directory Structure
````
|----ohos_minizip  
|     |---- entry  # Sample code
|     |---- library  
|                |---- cpp # C/C++ and NAPI code
|                      |---- minizipAdapter # NAPI logic code of minizip
|                      |---- CMakeLists.txt  # Build script
|                      |---- thirdparty # Third-party dependencies
|                      |---- types # API declaration
|           |---- index.ets  # External APIs
|     |---- README.md  # Readme
|     |---- README_zh.md  # Readme
````

## How to Contribute
If you find any problem when using the project, submit an [issue](https://gitcode.com/openharmony-tpc/openharmony_tpc_samples/issues) or a [PR](https://gitcode.com/openharmony-tpc/openharmony_tpc_samples/pulls).

## License
This project is licensed under [Apache License License - v 2.0](https://gitcode.com/openharmony-tpc/openharmony_tpc_samples/blob/master/ohos_minizip/LICENSE).
    
