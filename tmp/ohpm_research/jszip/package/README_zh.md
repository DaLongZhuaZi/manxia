# jszip

## 简介

[jszip](https://github.com/xqdoo00o/jszip) ，是一个支持创建、编辑以及生成压缩文件的工具库。本库基于[jszip](https://github.com/xqdoo00o/jszip) 原库 v3.5.0 版本进行适配，使其可以运行在 OpenHarmony，并沿用其现有用法和特性。

## 下载安装

```javascript
ohpm install @ohos/jszip
```

OpenHarmony ohpm 环境配置等更多内容，请参考[如何安装 OpenHarmony ohpm 包](https://gitcode.com/openharmony-tpc/docs/blob/master/OpenHarmony_har_usage.md)

## 接口和属性列表

接口列表

| **接口**                                         | 参数                                                                     | 功能             |
| ------------------------------------------------ | ------------------------------------------------------------------------ | ---------------- |
| file                       | (path,data[, options])                                            | 创建文件         |
| folder                                     | (name)                                            | 创建文件夹         |
| forEach    | (callback:(relativePath,file) => void)                                           | 遍历目录及文件         |
| filter | (predicate:(relativePath,file) => boolean)     | 支持过滤目录/文件    |
| remove                                    | (path)   | 移除目录或者文件 |
| generateAsync                  | (options,onUpdate) | 异步生成压缩文件，支持设置密码   |
| loadAsync                          | (data,options) | 异步加载压缩文件  |



## 使用示例
创建zip实例
```javascript
import JSZip from "@ohos/jszip";

const jszip = new JSZip();
```

创建文件

```javascript
jszip.file("xxx.txt","这是一段文本");
```

创建文件夹

```javascript
jszip.folder("xxx");
```

指定目录下创建文件或文件夹
```javascript
const folder = jszip.folder("xxx");

folder.folder("xxx");
folder.file("xxx.txt","这是一段文本");
```


异步生成压缩文件
```javascript
jszip.generateAsync({ type: "arraybuffer"})
```
异步生成加密压缩文件
```javascript
jszip.generateAsync({ type: "arraybuffer", password: "1234", encryptStrength: 3 })
```

异步加载压缩文件
```javascript
jszip.loadAsync(data)
```

解压缩加密的压缩文件

1.直接解压缩本Demo生成的加密压缩文件

2.将加密好的文件导入应用沙箱内的cache或者files文件夹，然后解压缩（注意导入之后的文件一定要是可读写的，否则会报错没有权限）

以上两种场景的压缩文件解压缩示例代码如下：

```typescript
 // 参数校验
 if (!this.filePath || this.filePath.length < 1) {
  promptAction.showToast({
    message: `暂无可用文件，请先加密压缩文件`
  })
  return;
}
if (!this.password || this.password.length < 1) {
  promptAction.showToast({
    message: `请先输入解压缩密码`
  })
  return;
}
try {

   // 检查是否有权限处理文件
  let isAccess: boolean = fs.accessSync(this.filePath)
  if (!isAccess) {
    promptAction.showToast({
      message: `暂无权限处理文件 ${this.filePath}`
    })
    return
  }
   // 将应用沙箱内的本地文件读取出来，转化为 Uint8Array  注意文件不能太大 否则造成OOM
  let totalSize = fs.statSync(this.filePath).size;
  let fileId = fs.openSync(this.filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE)
  let cacheData: Uint8Array = new Uint8Array(totalSize);
  let readLength = 0;
  let buff = new ArrayBuffer(8 * 1024)
  let readSize = 0;
  while (readLength < totalSize) {
    if (readLength + buff.byteLength < totalSize) {
      readSize = fs.readSync(fileId.fd, buff, {
        offset: readLength,
        length: buff.byteLength
      })
      cacheData.set(new Uint8Array(buff), readLength)
    } else {
      let trueLength = totalSize - readLength
      readSize = fs.readSync(fileId.fd, buff, {
        offset: readLength,
        length: trueLength
      })
      let trueBuff = buff.slice(0, trueLength)
      cacheData.set(new Uint8Array(trueBuff), readLength)
    }
    readLength += readSize;
  }
  // 添加密码解压缩文件
  JSZip.loadAsync(cacheData, {
    password: this.password
  }).then((data: JSZip) => {
    promptAction.showToast({
      message: `解压缩解密文件成功  ${JSON.stringify(data)}`
    })
  }).catch((err: Error) => {
    promptAction.showToast({
      message: `解压缩加密文件失败！ 错误原因： ${err.message}`
    })
  })
} catch (err) {
  promptAction.showToast({
    message: `解压缩加密文件出错！ 错误原因： ${err.message}`
  })
}

```

3.还可以解压缩放在项目rawfile文件夹内的加密压缩文件

```typescript
  try {
   // 传入rawfile文件名 加密压缩文件可以是PC端的软件加密的文件
  loadAsyncFromRawFile(this.rawFileName).then((res: Uint8Array | void) => {
    if (!res) {
      promptAction.showToast({
        message: `没有找到此压缩文件！`
      })
      this.closeLoading()
      return
    }
      // 读取到文件数据之后传递给JSZIP去解压缩
    this.instance.loadAsync(res, {
      password: this.password
    }).then((data: JSZip) => {
      promptAction.showToast({
        message: `解压缩加密文件成功  ￥${JSON.stringify(data)}`
      })
    }).catch((err: Error) => {
      promptAction.showToast({
        message: `解压缩加密文件失败！ 错误原因： ${err.message}`
      })
    })
  })
} catch (err) {
  promptAction.showToast({
    message: `解压缩加密文件出错！ 错误原因： ${err.message}`
  })
}
```


## 关于混淆
- 代码混淆，请查看[代码混淆简介](https://docs.openharmony.cn/pages/v5.0/zh-cn/application-dev/arkts-utils/source-obfuscation.md)
- 如果希望jszip库在代码混淆过程中不会被混淆，需要在混淆规则配置文件obfuscation-rules.txt中添加相应的排除规则：
```
-keep
./oh_modules/@ohos/jszip
```

## 约束与限制

在下述版本验证通过：
DevEco Studio: NEXT Beta1-5.0.3.806, SDK: API12 Release(5.0.0.66)
DevEco Studio: 4.1.3.313, SDK: API11(4.1.2.1)

## 目录结构

```javascript
|---- jszip
|     |---- AppScrope  # 示例代码文件夹
|     |---- entry  # 示例代码文件夹
|     |---- jszip  # jszip库文件夹
|           |---- src  # 模块代码
|                |---- core   # jszip核心代码
|                |---- dist   # 打包脚本生成代码
|                |---- type   # 类型声明文件
|           |---- index.ets        # 入口文件
|           |---- *.json5      # 配置文件
|           |---- rollup.config.js      # rollup配置文件
|     |---- README.md  # 安装使用方法
|     |---- README_zh.md  # 安装使用方法    
|     |---- README.OpenSource  # 开源说明
|     |---- CHANGELOG.md  # 更新日志
```

## 开源协议

本项目基于 [Apache License 2.0](https://gitcode.com/openharmony-tpc/openharmony_tpc_samples/blob/master/jszipDemo/LICENSE ) ，请自由地享受和参与开源。

## 贡献代码

使用过程中发现任何问题都可以提 [Issue](https://gitcode.com/openharmony-tpc/openharmony_tpc_samples/issues) 给组件，当然，也非常欢迎发 [PR](https://gitcode.com/openharmony-tpc/openharmony_tpc_samples/pulls)共建。
