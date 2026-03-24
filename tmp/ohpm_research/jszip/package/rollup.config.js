/*
 * Copyright (C) 2023 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
const path = require("path");
const alias = require("@rollup/plugin-alias");
const resolve = require("@rollup/plugin-node-resolve");
const commonjs = require("@rollup/plugin-commonjs");

const input = path.resolve(__dirname,"./src/main/core/jszip-master/lib/index.js")
const output = {
    file:path.resolve(__dirname,"./src/main/dist/dist.js"),
    format:"es"
}

module.exports = {
    input,
    output,
    external:[
        /^@ohos\/node-polyfill\/src\/main\/dist\/.+/
    ],
    plugins:[
        alias({
            entries:{
                "buffer":"@ohos/node-polyfill/src/main/dist/buffer",
                "crypto":"@ohos/node-polyfill/src/main/dist/crypto",
                "events":"@ohos/node-polyfill/src/main/dist/events",
                "net":"@ohos/node-polyfill/src/main/dist/net",
                "path":"@ohos/node-polyfill/src/main/dist/path",
                "process":"@ohos/node-polyfill/src/main/dist/process",
                "querystring":"@ohos/node-polyfill/src/main/dist/querystring",
                "stream":"@ohos/node-polyfill/src/main/dist/stream",
                "string_decoder":"@ohos/node-polyfill/src/main/dist/string_decoder",
                "timers":"@ohos/node-polyfill/src/main/dist/timers",
                "url":"@ohos/node-polyfill/src/main/dist/url",
                "util":"@ohos/node-polyfill/src/main/dist/util",
            }
        }),
        commonjs(),
        resolve()
    ]

}