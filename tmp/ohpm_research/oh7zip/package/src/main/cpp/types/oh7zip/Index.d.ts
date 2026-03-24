/*
 * Copyright (C) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the 'License');
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an 'AS IS' BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

export interface Config7z {
  src: string | Array<string>
  dst: string
  pwd?: string
  /*
  * 可选参数，压缩时启用， 默认压缩7z格式; 压缩支持可带加密的格式"zip", "7z",  不加密格式 "tar"
  * 不加密且非目录文件，xz, gzip, bzip2
  */
  fmt?: string
  xr?:string | Array<string>
}

/*
* 错误码对照表
* 0 成功
* 1 传入的config解析为空
* 2 传入了非法src
* 3 传入了非法dst
* 4 传入的dst路径没有权限
* 5 压缩失败
* 6 解压失败
* 7 异步数据指针为空
* 8 压缩格式不支持
* 9 指定压缩格式的src不合法，例如压缩gzip格式时，src传入的是一个目录
* 10 压缩包需要正确的密码，请输入正确的密码
*/

export class Uncompress {
  constructor()
  extractSync: (config: Config7z) => number;
  extractAsync: (config: Config7z) => Promise<number>;
}

export class Compress {
  constructor()
  compressSync: (config: Config7z) => number;
  compressAsync: (config: Config7z) => Promise<number>;
}