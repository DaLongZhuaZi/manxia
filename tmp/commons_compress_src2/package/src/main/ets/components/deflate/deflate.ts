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
import pako from "pako";
import fs from '@ohos.file.fs';


export async function DeflateFile(src: string, dest: string): Promise<boolean> {
    try {
        let stat = fs.statSync(src);
        const buf = new ArrayBuffer(stat.size);
        const reader = fs.openSync(src, fs.OpenMode.READ_ONLY);
        fs.readSync(reader.fd, buf);
        const writer = fs.openSync(dest, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE);
        const options = { deflate: true, level: 9 };
        fs.writeSync(writer.fd, pako.deflate(new Uint8Array(buf), options).buffer);
        fs.closeSync(reader);
        fs.closeSync(writer);
        return true;
    } catch (error) {
        return false;
    }
}


export async function InflateFile(src: string, target: string): Promise<boolean> {
    try {
        const reader = fs.openSync(src, fs.OpenMode.READ_ONLY);
        const stat = fs.statSync(src);
        const buf = new ArrayBuffer(stat.size);
        await fs.read(reader.fd, buf);
        const options = { deflate: true, level: 9 };
        const data = pako.inflate(new Uint8Array(buf), options);
        const writer = fs.openSync(target, fs.OpenMode.WRITE_ONLY | fs.OpenMode.CREATE);
        fs.writeSync(writer.fd, data.buffer);
        fs.closeSync(writer);
        fs.closeSync(reader);
        return true;
    } catch (error) {
        return false;
    }
}