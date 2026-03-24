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
import Long from "../util/long/index";
import File from '../util/File';
import { LinkOption } from '../util/LinkOption';
import type ArchiveEntry from './ArchiveEntry';
import OutputStream from '../util/OutputStream';

export default abstract class ArchiveOutputStream extends OutputStream {
    private oneByte: Int8Array = new Int8Array(1);
    static BYTE_MASK: number = 0xFF;
    private bytesWritten: Long = Long.fromNumber(0);

    public abstract putArchiveEntry(entry: ArchiveEntry): void;

    public abstract closeArchiveEntry(): void;

    public abstract finish(): void;

    public abstract createArchiveEntry(inputFile: File, entryName: string): ArchiveEntry;

    public createArchiveEntryOptions(inputPath: string, entryName: string, ...options: LinkOption[]): ArchiveEntry {
        return this.createArchiveEntry(new File(inputPath, ""), entryName);
    }

    public write(b: number): void {
        this.oneByte[0] = (b & ArchiveOutputStream.BYTE_MASK);
        this.writeBytesOffset(this.oneByte, 0, 1);
    }

    protected counts(written: number): void {
        this.countLong(Long.fromNumber(written));
    }

    protected countLong(written: Long): void {
        if (!written.compare(-1)) {
            this.bytesWritten = this.bytesWritten.add(written);
        }
    }

    public getBytesWritten(): Long {
        return this.bytesWritten;
    }

    public canWriteEntryData(archiveEntry: ArchiveEntry): boolean {
        return true;
    }
}