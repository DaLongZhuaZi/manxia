# Archive

## 简介

本库是基于 [libarchive](https://gitee.com/openharmony-sig/tpc_c_cplusplus/tree/master/thirdparty/libarchive)
开发完成，支持常见的 `7z`, `tar`, `zip`, `gz`, `xz` 格式解压缩。

## 安装

```
ohpm i @mysoft/archive
```

环境配置等更多内容，请参考[如何安装 ohpm 包](https://ohpm.openharmony.cn/#/cn/help/downloadandinstall)

## 效果

<img src="https://s2.loli.net/2025/01/15/jO3SPHagJm5KQUz.gif" alt="harmony-archive.gif" width="250">

## API

### archiveLib.compress

compress(options: archiveLib.CompressOptions): Promise<archiveLib.Result>

压缩文件，压缩的结果使用Promise异步返回。成功时返回`{code: 0, message: 'Success'}`，失败时返回错误码和具体的错误内容。

#### 参数：

| 参数名 | 类型                        | 必填 | 说明       |
|:---:|:--------------------------|:--:|:---------|
| options | archiveLib.CompressOptions | 是  | 压缩选项配置对象 |

**CompressOptions 属性：**

|    属性名     | 类型                           | 必填 | 说明                                                                                                                                                                |
|:----------:|:-----------------------------|:--:|:------------------------------------------------------------------------------------------------------------------------------------------------------------------|
|   inFile   | string                       | 是  | 指定压缩的文件夹路径或者文件路径，路径必须为沙箱路径，沙箱路径可以通过context获取。<br/>inFile：/a/b/c；执行结果：压缩文件夹c<br/>inFile：/a/b/c/；执行结果：压缩文件夹c下的所有文件和文件夹<br/>inFile：/a/b/c/test.txt；执行结果：压缩文件test.txt |
|  outFile   | string                       | 是  | 指定的压缩结果的文件路径。如果outFile已存在，则直接覆盖。多个线程同时压缩文件时，outFile不能相同。                                                                                                          |
|   format   | archiveLib.CompressFormat    | 是  | 压缩格式，支持 `7z`, `tar`, `zip`, `gz`, `xz`                                                                                                                            |
| onProgress | archiveLib.ProgressCallback  | 否  | 进度回调函数，参数为 `(current: number, total: number)`，分别表示已处理字节数和总字节数                                                                                                     |

#### 返回值

|             类型             | 说明                                                                     |
|:--------------------------:|:-----------------------------------------------------------------------|
| Promise<archiveLib.Result> | Promise对象，返回 `archiveLib.Result` 说明:<br/>`code`：错误码<br/>`message`：错误详情 |

#### 示例

```typescript
import { archiveLib } from '@mysoft/archive'

// 方式一：使用 options 对象（推荐）
const ret = await archiveLib.compress({
  inFile: '/path/to/source',
  outFile: '/path/to/output.zip',
  format: 'zip',
  onProgress: (current, total) => {
    console.log(`压缩进度: ${current}/${total} 字节`)
  }
})

// 方式二：使用多参数（兼容旧版本）
const ret2 = await archiveLib.compress(inFile, outFile, 'zip', (current, total) => {
  console.log(`压缩进度: ${current}/${total} 字节`)
})

if (ret.code === 0) {
  console.log('压缩成功')
} else {
  console.log(`压缩失败，code: ${ret.code}, message: ${ret.message}`)
}
```

### archiveLib.decompress

decompress(options: archiveLib.DecompressOptions): Promise<archiveLib.Result>

解压文件，解压的结果使用Promise异步返回。成功时返回`{code: 0, message: 'Success'}`，失败时返回错误码和具体的错误内容。

#### 参数：

| 参数名 | 类型                          | 必填 | 说明       |
|:---:|:----------------------------|:--:|:---------|
| options | archiveLib.DecompressOptions | 是  | 解压选项配置对象 |

**DecompressOptions 属性：**

|    属性名     | 类型                          | 必填 | 说明                                                                                                                                          |
|:----------:|:----------------------------|:--:|:--------------------------------------------------------------------------------------------------------------------------------------------|
|   inFile   | string                      | 是  | 指定的待解压缩文件的文件路径。文件路径必须为沙箱路径，沙箱路径可以通过context获取。                                                                                               |
|  outFile   | string                      | 是  | 指定的解压后的文件夹路径，文件夹目录路径需要在系统中存在，不存在则会解压失败。路径必须为沙箱路径，沙箱路径可以通过context获取。如果待解压的文件或文件夹在解压后的路径下已经存在，则会直接覆盖同名文件或同名文件夹中的同名文件。多个线程同时解压文件时，outFile不能相同。 |
| onProgress | archiveLib.ProgressCallback | 否  | 进度回调函数，参数为 `(current: number, total: number)`，分别表示已处理字节数和总字节数                                                                               |

#### 返回值

|             类型             | 说明                                                                     |
|:--------------------------:|:-----------------------------------------------------------------------|
| Promise<archiveLib.Result> | Promise对象，返回 `archiveLib.Result` 说明:<br/>`code`：错误码<br/>`message`：错误详情 |

#### 示例

```typescript
import { archiveLib } from '@mysoft/archive'

// 方式一：使用 options 对象（推荐）
const ret = await archiveLib.decompress({
  inFile: '/path/to/archive.zip',
  outFile: '/path/to/output',
  onProgress: (current, total) => {
    console.log(`解压进度: ${current}/${total} 字节`)
  }
})

// 方式二：使用多参数（兼容旧版本）
const ret2 = await archiveLib.decompress(inFile, outFile, (current, total) => {
  console.log(`解压进度: ${current}/${total} 字节`)
})

if (ret.code === 0) {
  console.log('解压成功')
} else {
  console.log(`解压失败，code: ${ret.code}, message: ${ret.message}`)
}
```

## 沟通与交流

使用过程中发现任何问题都可以提 [Issue](https://gitee.com/mysoft-harmony/mysoft-archive/issues)；
当然，我们也非常欢迎发 [PR](https://gitee.com/mysoft-harmony/mysoft-archive/pulls) 。

## 开源协议

本项目基于 [Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0.html) ，在拷贝和借鉴代码时，请务必注明出处。