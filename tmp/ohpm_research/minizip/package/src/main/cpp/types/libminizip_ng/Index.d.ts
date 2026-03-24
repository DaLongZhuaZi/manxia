/*
 * Copyright (c) 2024 Huawei Device Co., Ltd.
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

export class MinizipNative{
  constructor(path : string);
  // 打开文件路径
  Open : () => number;
  // 设置字符编码
  SetCharEncoding : (charEncoding : number) => void;
  // 获取文件列表
  GetEntryNames : () => Array<string>;
  //解压文件
  ExtractFileToJS : (entryName : string, password : string) => ArrayBuffer | undefined;
  //判断是否加密
  IsEncrypto : (entryName : string) => boolean;
  //判断编码格式
  IsUtf8 : (entryName : string) => boolean;
}

export class MinizipCompressNative{
  constructor(catchPath : string, zipFilePath : string = "");
  // 打开文件路径
  Create : () => number;
  // 关闭文件路径
  Close : () => void;
  // 设置压缩方法
  SetCompressMethod : (compressMethod : number) => number;
  // 设置压缩等级
  SetCompressLevel : (compressLevel : number) => number;
  // 设置压缩包名
  SetzipFilePath : (zipFilePath : string) => number;
  // 压缩文件
  Compress : (entries : Array<string>, password : string = "") => number;
  // 获取压缩包二进制流
  CompressToJS : (entries : Array<string>, password : string = "") => ArrayBuffer | undefined;
}

