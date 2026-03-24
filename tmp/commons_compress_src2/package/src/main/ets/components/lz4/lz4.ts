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
import LZ4 from 'lz4js';
import fs from '@ohos.file.fs';

export async function lz4Compressed(src: string, dest: string): Promise<boolean> {
  try {
    let stat = fs.statSync(src);
    let reader = fs.openSync(src, fs.OpenMode.READ_ONLY);
    let buf = new ArrayBuffer(stat.size);
    fs.readSync(reader.fd, buf);
    let unitArray = new Uint8Array(buf);
    let compressed = LZ4.compress(unitArray);
    //生成文件
    let newpath = fs.openSync(dest, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE);
    fs.writeSync(newpath.fd, compressed.buffer);
    fs.closeSync(reader);
    fs.closeSync(newpath);
    return true;
  } catch (error) {
    return false;
  }
}

export async function lz4Decompressed(src: string, target: string): Promise<boolean> {
  try {
    let stat = fs.statSync(src);
    let reader = fs.openSync(src, fs.OpenMode.READ_ONLY);
    let buf = new ArrayBuffer(stat.size);
    fs.readSync(reader.fd, buf);
    let unitArray = new Uint8Array(buf);
    let decompress = LZ4.decompress(unitArray);
    let newpath = fs.openSync(target, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE);
    fs.writeSync(newpath.fd, decompress.buffer);
    fs.closeSync(reader);
    fs.closeSync(newpath);
    return true;
  } catch (error) {
    return false;
  }
}