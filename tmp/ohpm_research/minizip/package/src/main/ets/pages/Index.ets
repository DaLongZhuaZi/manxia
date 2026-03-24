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

import { MinizipNative } from "libminizip_ng.so";
import fs from '@ohos.file.fs';
import { BusinessError } from '@ohos.base';
import { LogUtil } from '../utils/LogUtil';

export function unzipToDirectory(selectPath: string, targetPath: string, password?: string, charEncoding?: number): Promise<string> {
  return new Promise((resolve, reject) => {
    if(!fs.accessSync(selectPath)) {
      reject("selectPath not exists");
    }
    if(!fs.accessSync(targetPath)) {
      fs.mkdirSync(targetPath, true);
    }
    if(!password) {
      password = ""
    }
    let minizipEntry = new MinizipNative(selectPath);
    if(!!charEncoding) {
      minizipEntry.SetCharEncoding(charEncoding);
    }
    let code: number = minizipEntry.Open()
    if(code == 0) {
      let entryNames: Array<string> = minizipEntry.GetEntryNames();
      for(let i = 0; i < entryNames.length; i++) {
        let path: string = targetPath + "/" + entryNames[i];
        if(entryNames[i].endsWith("/")) {
          if(!fs.accessSync(path)) {
            fs.mkdirSync(path, true);
          }
        } else {
          createFolders(path);
          let file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
          let arrBuffer: ArrayBuffer | undefined = minizipEntry.ExtractFileToJS(entryNames[i], password);
          if(arrBuffer != undefined) {
            try {
              fs.writeSync(file.fd,arrBuffer)
            }catch (err){
              reject("fs.write failed: " + entryNames[i])
            }
            fs.closeSync(file);
          } else {
            LogUtil.debug("minizip ExtractFileToJS failed:" + entryNames[i])
            fs.closeSync(file)
            reject("unzip failed")
          }
        }
      }
      resolve("unzip success")
    } else {
      reject("Open failed")
    }
  })
}

function createFolders(path: string) {
  const parts = path.split('/');
  if (parts.length <= 1) {
    return
  }
  const folders = parts.slice(0, -1).join('/');
  try {
    if (!fs.accessSync(folders)) {
      fs.mkdirSync(folders, true);
    }
  }catch (err) {
    LogUtil.debug('minizip mkdir failed:' + JSON.stringify(err));
  }
}