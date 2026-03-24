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
import InputStream from '../util/InputStream';
import type ArchiveEntry from './ArchiveEntry';
import Long from "../util/long/index";

export default abstract class ArchiveInputStream extends InputStream {
    private single: Int8Array = new Int8Array(1);
    private static BYTE_MASK: number = 0xFF;
    private bytesRead: Long = Long.fromNumber(0);

    public abstract getNextEntry(): ArchiveEntry;

    public read(): number {
        let num: number = this.readBytesOffset(this.single, 0, 1);
        return num == -1 ? -1 : this.single[0] & ArchiveInputStream.BYTE_MASK;
    }

    protected count(read: number): void {
        this.countLong(Long.fromNumber(read));
    }

    protected countLong(read: Long): void {
        if (read.notEquals(-1)) {
            this.bytesRead = this.bytesRead.add(read);
        }
    }

    protected pushedBackBytes(pushedBack: Long): void {
        this.bytesRead = this.bytesRead.subtract(pushedBack);
    }

    public getBytesRead(): Long {
        return this.bytesRead;
    }

    public canReadEntryData(archiveEntry: ArchiveEntry): boolean {
        return true;
    }
}