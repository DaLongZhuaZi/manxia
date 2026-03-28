# node-polyfill 

## Introduction

This project provides a polyfill that includes a subset of NodeJs modules. It is used for API adaptation of the Node.js built-in basic module in the npm repository. Currently, Currently supports [partial interfaces of the following modules(#interface).

## How to Install

```
ohpm install @ohos/node-polyfill
```

For details about the OpenHarmony ohpm environment configuration, see [OpenHarmony HAR](https://gitcode.com/openharmony-tpc/docs/blob/master/OpenHarmony_har_usage.en.md).


## Example
Refer to the code below to use the buffer module.

```javascript
import { buffer } from "@ohos/node-polyfill";

const log = (message) => {
    console.log(message)
}

export function run_buffer (){
    const str = "This is a piece of text...";
    log("------ buffer demo start ------")
    const base64Str = buffer.Buffer.from(str).toString("base64");
    log ("str to base64 result: "+ base64Str);
    log("------ buffer demo end ------")
}
```

## APIS <a id="interface">
Currently, the [Node APIs](http://nodejs.cn/api-v16/) of the following modules are included:

|   Node.js Module   |       Description      |                                 Remarks                                 |
|:----------------:|:--------:|:-----------------------------------------------------------------------:|
|     [events]     |  Event triggering and listening.  |         [events Introduction](https://nodejs.cn/api-v16/events.html)         |
|      [path]      |  Paths of files and directories. |           [path Introduction](https://nodejs.cn/api-v16/path.html)           |
|     [buffer]     |  Buffer.         |      [buffer Introduction](https://nodejs.cn/api-v16/buffer.html)       |
|     [stream]     |  Stream.         |         [stream Introduction](https://nodejs.cn/api-v16/stream.html)         |
|    [process]     |  Process.        |        [process Introduction](https://nodejs.cn/api-v16/process.html)        |
|  [querystring]   |  Query strings.  |    [querystring Introduction](https://nodejs.cn/api-v16/querystring.html)    |
|      [util]      |  Utilities.      |           [util Introduction](https://nodejs.cn/api-v16/util.html)           |
|      [url]       |  URLs.           |            [url Introduction](https://nodejs.cn/api-v16/url.html)            |
|     [timers]     |  Timers.         |         [timers Introduction](https://nodejs.cn/api-v16/timers.html)         |
|      [net]       |  Network         |            [net Introduction](https://nodejs.cn/api-v16/net.html)            |
|     [crypto]     |  Encryption.     |         [crypto Introduction](https://nodejs.cn/api-v16/crypto.html)         |
| [string_decoder] |  String decoder. | [string_decoder Introduction](https://nodejs.cn/api-v16/string_decoder.html) |

## About obfuscation
- Code obfuscation, please see[Code Obfuscation](https://docs.openharmony.cn/pages/v5.0/zh-cn/application-dev/arkts-utils/source-obfuscation.md)
- If you want the node-polyfill library not to be obfuscated during code obfuscation, you need to add corresponding exclusion rules in the obfuscation rule configuration file obfuscation-rules.txt：
```
-keep
./oh_modules/@ohos/node-polyfill
```

## Constraints

This project has been verified in the following version:

DevEco Studio: NEXT Beta1-5.0.3.806, SDK:API12 Release(5.0.0.66)
DevEco Studio: 4.1.3.213, SDK: API 11 (4.1.2.5)

## How to Contribute

If you find any problem during the use, submit an [issue](https://gitcode.com/openharmony-sig/ohos_polyfill/issues) or a [PR](https://gitcode.com/openharmony-sig/ohos_polyfill/pulls).

## License

This project is licensed under [Apache License 2.0](https://gitcode.com/openharmony-sig/ohos_polyfill/blob/master/LICENSE).
