/*
 * Copyright (c) 2022 Huawei Device Co., Ltd.
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

import unrar_napi from "libunrar.so";
import { ICallBack } from "./ICallBack"

export class UnrarApi {

  /**
   * 判断文件是否加密
   * path:文件路径
   * number:返回值 0代表没加密，1代表加密
   */
  static isEncrypted(path: string): number {
    return unrar_napi.isEncrypted(path);
  }

  /**
   * 同步解压文件
   * path:文件包路径
   * dest:要解压文件存放的路径
   * password:密码.
   * string:返回值，解压成功则返回解压成功，否则返回失败
   */
  static extract(path: string, dest: string, password?: string): string {
    return unrar_napi.extract(path, dest, password);
  }

  /**
   * 异步步解压文件
   * @param path 文件包路径
   * @param dest 要解压文件存放的路径
   * @param callBack 返回值，解压成功则返回解压成功，否则返回失败
   * @param password 密码.
   */
  static RarFiles_Extract(path: string, dest: string, callBack: ICallBack, password?: string): void {
    unrar_napi.RarFiles_Extract(path, dest, password).then( (value:string)=> {
      callBack.callBackResult(value)
    });


  }
}