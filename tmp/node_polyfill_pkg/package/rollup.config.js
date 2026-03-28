/*
 * Copyright (c) 2021 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the 'License');
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an 'AS IS' BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
const path = require("path");
const commonjs = require("@rollup/plugin-commonjs");

const modules = ["buffer", "crypto", "events", "net", "path", "process", "querystring", "stream", "string_decoder", "url", "util","timers"]
const input = {};
const output = {
    dir:path.resolve(__dirname,"./src/main/dist"),
    format:"es"
};

function init_input() {
    modules.forEach(v => {
        input[v] = v === "stream"
            ? path.resolve(__dirname, "./src/main/core/stream/lib/ours/index.js")
            : path.resolve(__dirname, `./src/main/core/${v}/index.js`)
    })
}

init_input();

module.exports = {
    input,
    output,
    plugins: [
    commonjs()
    ]
}