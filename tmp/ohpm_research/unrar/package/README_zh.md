# Unrar

## 简介

本库基于[Unrar](https://www.rarlab.com/rar_add.htm) 原库进行适配，使其可以运行在 OpenHarmony，并沿用其现有用法和特性。[Unrar](https://www.rarlab.com/rar_add.htm) ，是一个解压rar文件的库。功能如下：

- 判断压缩包名是否加密
- 解压文件到指定目标路径
- 解压无加密/加密压缩包

![unrar1](./entry/src/main/resources/base/media/unrar1.png)

## 下载安装

```
ohpm install @ohos/unrar
```
- OpenHarmony ohpm 环境配置等更多内容，请参考[如何安装 OpenHarmony ohpm 包](https://gitcode.com/openharmony-tpc/docs/blob/master/OpenHarmony_har_usage.md)


## X86模拟器配置

[使用模拟器运行应用/服务](https://developer.huawei.com/consumer/cn/deveco-developer-suite/enabling/kit?currentPage=1&pageSize=100)


## 使用说明
```javascript
import unrar from '@ohos/unrar'
```

### isEncrypted 判断压缩包名是否加密方法示例

```
// path:文件所在路径 path目前只支持沙箱路径
unrar.isEncrypted(path)

```

### 解压无加密文件方法示例

```
unrar.RarFiles_Extract(path, globalThis.context.filesDir).then((value) => {
                let resultss;
                if (value == '解压成功') {
                  resultss = '解压testRar5.rar文件解压成功,解压文件在:' + globalThis.context.filesDir;
                } else {
                  resultss = value;
                }
                this.tag = true;
                this.showDialog(resultss)
              }).catch((error) => {
                this.tag = true;
                this.showDialog('解压失败')
              });

```

### 解压加密文件方法示例

```
unrar.RarFiles_Extract(path, globalThis.context.filesDir, passwords).then((value) => {
                  let resultss;
                  if (value == '解压成功') {
                    resultss = 'name_encrypted.rar文件解压成功,解压文件在:' + globalThis.context.filesDir;
                  } else {
                    resultss = '解压失败';
                  }
                  this.showDialog(resultss)
                }).catch((error) => {
                  this.showDialog('解压失败')
                });
```

## 接口说明
| **属性**                                                                               |                                  **入参类型**                                  | **说明**                                                    |
|--------------------------------------------------------------------------------------|:--------------------------------------------------------------------------:| ----------------------------------------------------------- |
| isEncrypted                                                        |                           (path:string)=>number                            | 判断文件是否加密 |
| extract                               |          (path: string, dest: string, password?: string)=>string           | 同步解压文件                      |
| RarFiles_Extract | (path: string, dest: string, callBack: ICallBack, password?: string)=>void | 异步解压文件 |

## 关于混淆
- 代码混淆，请查看[代码混淆简介](https://docs.openharmony.cn/pages/v5.0/zh-cn/application-dev/arkts-utils/source-obfuscation.md)
- 如果希望unrar库在代码混淆过程中不会被混淆，需要在混淆规则配置文件obfuscation-rules.txt中添加相应的排除规则：
```
-keep
./oh_modules/@ohos/unrar
```

## 约束与限制

在下述版本验证通过：

DevEco Studio： (5.0.3.122), SDK: API12 (5.0.0.17)

## 目录结构
```javascript
|---- ohosunrar
|     |---- entry  # 示例代码文件夹
|     |---- library  # unrar 库文件夹
|           |---- src   #  unrar库解压核心代码
|                 |---- cpp # unrar 核心代码
|     |---- README.MD  # 安装使用方法
```

## 贡献代码

使用过程中发现任何问题都可以提[Issue](https://gitcode.com/openharmony-tpc/openharmony_tpc_samples/issues) ，当然，也非常欢迎提[PR](https://gitcode.com/openharmony-tpc/openharmony_tpc_samples/pulls)。

## 开源协议

本项目基于 [Apache License 2.0](https://gitcode.com/openharmony-tpc/openharmony_tpc_samples/blob/master/unrar/LICENSE)，请自由地享受和参与开源。

