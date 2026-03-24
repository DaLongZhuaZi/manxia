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
import snappyJS from 'snappyjs'
import fs from '@ohos.file.fs';

export async function snappyCompress(src: string, dest: string): Promise<boolean> {
  try {
    let buf = getFileBuf(src)
    /* 压缩文件*/
    var compressed = snappyJS.compress(buf)
    let writer = fs.openSync(dest, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE);
    await fs.write(writer.fd, compressed);
    fs.closeSync(writer);
    return true;
  } catch (error) {
    return false;
  }
}

/* 解压文件*/
export async function snappyUncompress(src: string, target: string): Promise<boolean> {
  try {
    let buf = getFileBuf(src)
    var uncompressed = snappyJS.uncompress(buf)
    let writer = fs.openSync(target, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE);
    await fs.write(writer.fd, uncompressed);
    fs.closeSync(writer);
    return true;
  } catch (error) {
    return false;
  }
}

function getFileBuf(path): ArrayBuffer {
  let stat = fs.statSync(path);
  const reader = fs.openSync(path, fs.OpenMode.READ_ONLY);
  let buf = new ArrayBuffer(stat.size);
  fs.readSync(reader.fd, buf);
  fs.closeSync(reader);
  return buf
}




