# node-polyfill 

## 简介

该项目是一个 polyfill，包含 NodeJs 部分模块的子集。用于 npm 仓中 Node.js built-in 基础模块的 api 适配。目前支持[如下模块部分接口](#interface)。



## 下载安装

```
ohpm install @ohos/node-polyfill
```

OpenHarmony ohpm 环境配置等更多内容，请参考[如何安装 OpenHarmony ohpm 包](https://gitcode.com/openharmony-tpc/docs/blob/master/OpenHarmony_har_usage.md)


## 使用示例
使用buffer模块

```javascript
import { buffer } from "@ohos/node-polyfill";

const log = (message) => {
    console.log(message)
}

export function run_buffer (){
    const str = "这是一段文本...";
    log("------ buffer demo start ------")
    const base64Str = buffer.Buffer.from(str).toString("base64");
    log("str to base64结果：" + base64Str);
    log("------ buffer demo end ------")
}
```
## 接口说明 <a id="interface">
目前包括如下模块部分接口 [Node Apis](http://nodejs.cn/api-v16/)。

|  Node.js 模块  |       描述       |                                 使用说明                                  |
| :-----------: | :--------------: |:---------------------------------------------------------------------:|
|   [events]    |  事件触发与监听  |        [events 方法和参数介绍](https://nodejs.cn/api-v16/events.html)        |
|    [path]     | 文件和目录的路径 |          [path 方法和参数介绍](https://nodejs.cn/api-v16/path.html)          |
|   [buffer]    |      缓冲区      |        [buffer 方法和参数介绍](https://nodejs.cn/api-v16/buffer.html)        |
|   [stream]    |        流        |        [stream 方法和参数介绍](https://nodejs.cn/api-v16/stream.html)        |
|   [process]   |       进程       |       [process 方法和参数介绍](https://nodejs.cn/api-v16/process.html)       |
| [querystring] |    查询字符串    |   [querystring 方法和参数介绍](https://nodejs.cn/api-v16/querystring.html)   |
|    [util]     |       工具       |          [util 方法和参数介绍](https://nodejs.cn/api-v16/util.html)          |
|     [url]     |   统一资源定位   |           [url 方法和参数介绍](https://nodejs.cn/api-v16/url.html)           |
|   [timers]    |      定时器      |        [timers 方法和参数介绍](https://nodejs.cn/api-v16/timers.html)        |
|   [net]    |      网络      |           [net 方法和参数介绍](https://nodejs.cn/api-v16/net.html)           |
|   [crypto]    |      加密      |        [crypto 方法和参数介绍](https://nodejs.cn/api-v16/crypto.html)        |
|   [string_decoder]    |      字符串解码器      | [string_decoder 方法和参数介绍](https://nodejs.cn/api-v16/string_decoder.html) |

## 关于混淆
- 代码混淆，请查看[代码混淆简介](https://docs.openharmony.cn/pages/v5.0/zh-cn/application-dev/arkts-utils/source-obfuscation.md)
- 如果希望node-polyfill库在代码混淆过程中不会被混淆，需要在混淆规则配置文件obfuscation-rules.txt中添加相应的排除规则：
```
-keep
./oh_modules/@ohos/node-polyfill
```

## 约束与限制

在下述版本验证通过：

DevEco Studio: NEXT Beta1-5.0.3.806,SDK:API12 Release(5.0.0.66)
DevEco Studio: 4.1.3.213, SDK: API11(4.1.2.5)


## 贡献代码

使用过程中发现任何问题都可以提[Issue](https://gitcode.com/openharmony-sig/ohos_polyfill/issues) 给组件，当然，也非常欢迎给发[PR](https://gitcode.com/openharmony-sig/ohos_polyfill/pulls)共建 。

## 开源协议

本项目基于 [Apache License 2.0](https://gitcode.com/openharmony-sig/ohos_polyfill/blob/master/LICENSE) ，请自由地享受和参与开源。
