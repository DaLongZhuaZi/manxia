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
import ArArchiveEntry from './ArArchiveEntry';
import ArArchiveInputStream from './ArArchiveInputStream';
import ArchiveOutputStream from '../ArchiveOutputStream';
import ArchiveUtils from '../../util/ArchiveUtils';
import Exception from '../../util/Exception';
import File from '../../util/File';
import OutputStream from '../../util/OutputStream';
import type ArchiveEntry from '../ArchiveEntry';
import Long from "../../util/long/index";
import { LogUtil } from '../../LogUtil';

export default class ArArchiveOutputStream extends ArchiveOutputStream {
    public static LONGFILE_ERROR: number = 0;
    public static LONGFILE_BSD: number = 1;
    private out: OutputStream;
    private entryOffset: Long = Long.fromNumber(0);
    private prevEntry: ArArchiveEntry;
    private haveUnclosedEntry: boolean;
    private longFileMode: number = ArArchiveOutputStream.LONGFILE_ERROR;
    private finished: boolean;

    constructor(pOut: OutputStream) {
        super();
        this.out = pOut;
    }

    public setLongFileMode(longFileMode: number): void {
        this.longFileMode = longFileMode;
    }

    private writeArchiveHeader(): void {
        let header: Int8Array = ArchiveUtils.toAsciiBytes(ArArchiveEntry.HEADER);
        this.out.writeBytes(header);
    }

    public closeArchiveEntry(): void {
        LogUtil.info('closeArchiveEntry');
        if (this.finished) {
            LogUtil.error('Stream has already been finished.');
            throw new Exception("Stream has already been finished");
        }
        if (this.prevEntry == null || !this.haveUnclosedEntry) {
            LogUtil.error('No current entry to close.');
            throw new Exception("No current entry to close");
        }
        if (this.entryOffset.toNumber() % 2 != 0) {
            this.out.write('\n'.charCodeAt(0)); // Pad byte
        }
        this.haveUnclosedEntry = false;
    }

    public putArchiveEntry(pEntry: ArchiveEntry): void {
        LogUtil.info('putArchiveEntry');
        if (this.finished) {
            LogUtil.error('Stream has already been finished.');
            throw new Exception("Stream has already been finished");
        }

        let pArEntry: ArArchiveEntry = pEntry as ArArchiveEntry;
        if (this.prevEntry == null) {
            this.writeArchiveHeader();
        } else {
            if (!this.prevEntry.getLength().eq(this.entryOffset)) {
                LogUtil.error('Length does not match entry (' + this.prevEntry.getLength() +
                    ' != ' + this.entryOffset);
                throw new Exception("Length does not match entry (" + this.prevEntry.getLength() + " != " +
                this.entryOffset);
            }

            if (this.haveUnclosedEntry) {
                this.closeArchiveEntry();
            }
        }

        this.prevEntry = pArEntry;

        this.writeEntryHeader(pArEntry);

        this.entryOffset = Long.fromNumber(0);
        this.haveUnclosedEntry = true;
    }

    private fill(pOffset: Long, pNewOffset: Long, pFill: number): Long {
        let diff: Long = pNewOffset.sub(pOffset);

        if (diff.greaterThan(0)) {
            for (let i = 0; i < diff.toNumber(); i++) {
                this.write(pFill);
            }
        }
        return pNewOffset;
    }

    private writeString(data: string): Long {
        let bytes: Int8Array = ArchiveUtils.toAsciiBytes(data);
        this.writeBytes(bytes);
        return Long.fromNumber(bytes.length);
    }

    private writeEntryHeader(pEntry: ArArchiveEntry): void {
        let offset: Long = Long.fromNumber(0);
        let mustAppendName: boolean = false;

        let n: string = pEntry.getName();
        let nLength: number = n.length;
        if (ArArchiveOutputStream.LONGFILE_ERROR == this.longFileMode && nLength > 16) {
            throw new Exception("File name too long, > 16 chars: " + n);
        }
        if (ArArchiveOutputStream.LONGFILE_BSD == this.longFileMode &&
        (nLength > 16 || n.indexOf(" ") != -1)) {
            mustAppendName = true;
            offset = offset.add(this.writeString(ArArchiveInputStream.BSD_LONGNAME_PREFIX + nLength));
        } else {
            offset = offset.add(this.writeString(n));
        }

        offset = this.fill(offset, Long.fromNumber(16), ' '.charCodeAt(0));
        let m: string = "" + pEntry.getLastModified();
        if (m.length > 12) {
            throw new Exception("Last modified too long");
        }
        offset = offset.add(this.writeString(m));

        offset = this.fill(offset, Long.fromNumber(28), ' '.charCodeAt(0));
        let u: string = "" + pEntry.getUserId();
        if (u.length > 6) {
            throw new Exception("User id too long");
        }
        offset = offset.add(this.writeString(u));

        offset = this.fill(offset, Long.fromNumber(34), ' '.charCodeAt(0));
        let g: string = "" + pEntry.getGroupId();
        if (g.length > 6) {
            throw new Exception("Group id too long");
        }
        offset = offset.add(this.writeString(g));

        offset = this.fill(offset, Long.fromNumber(40), ' '.charCodeAt(0));
        let fm: string = "" + pEntry.getMode().toString(8);
        if (fm.length > 8) {
            throw new Exception("Filemode too long");
        }
        offset = offset.add(this.writeString(fm));

        offset = this.fill(offset, Long.fromNumber(48), ' '.charCodeAt(0));
        let s: string = pEntry.getLength().add((mustAppendName ? nLength : 0)).toString();
        if (s.length > 10) {
            throw new Exception("Size too long");
        }
        offset = offset.add(this.writeString(s));

        offset = this.fill(offset, Long.fromNumber(58), ' '.charCodeAt(0));

        offset = offset.add(this.writeString(ArArchiveEntry.TRAILER));

        if (mustAppendName) {
            offset = offset.add(this.writeString(n));
        }
    }

    public writeBytesOffset(b: Int8Array, off: /*int*/
    number, len: /*int*/
    number): void {
        this.out.writeBytesOffset(b, off, len);
        this.counts(len);
        this.entryOffset = this.entryOffset.add(len);
    }

    public close(): void {
        try {
            if (!this.finished) {
                this.finish();
            }
        } finally {
            this.out.close();
            this.prevEntry = null;
        }
    }

    public createArchiveEntry(inputFile: File, entryName: string): ArchiveEntry {
        if (this.finished) {
            throw new Exception("Stream has already been finished");
        }
        return new ArArchiveEntry(entryName, Long.fromNumber(inputFile.isFile() ? inputFile.length() : 0),
            0, 0, ArArchiveEntry.DEFAULT_MODE, inputFile.lastModified().divide(1000));
    }

    public finish(): void {
        if (this.haveUnclosedEntry) {
            throw new Exception("This archive contains unclosed entries.");
        }
        if (this.finished) {
            throw new Exception("This archive has already been finished");
        }
        this.finished = true;
    }
}