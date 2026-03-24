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
import ArchiveException from '../ArchiveException'
import ArchiveInputStream from '../ArchiveInputStream'
import IOUtils from '../../util/IOUtils'
import DumpArchiveSummary from './DumpArchiveSummary'
import DumpArchiveEntry from './DumpArchiveEntry'
import Long from "../../util/long/index"
import { int, byte } from '../../util/CustomTypings'
import DumpArchiveConstants from './DumpArchiveConstants'
import TapeInputStream from './TapeInputStream'
import Dirent from './Dirent'
import Queue from './Queue'
import PriorityQueue from './PriorityQueue'
import { SEGMENT_TYPE } from './Enumeration'
import DumpArchiveUtil from './DumpArchiveUtil'
import System from '../../util/System'
import InvalidFormatException from './InvalidFormatException'
import UnrecognizedFormatException from './UnrecognizedFormatException'
import IllegalStateException from '../../util/IllegalStateException'
import Arrays from '../../util/Arrays'
import type ZipEncoding from '../zip/ZipEncoding'
import ZipEncodingHelper from '../zip/ZipEncodingHelper'
import InputStream from '../../util/InputStream'
import Exception from '../../util/Exception'

export default class DumpArchiveInputStream extends ArchiveInputStream {
    private summary: DumpArchiveSummary;
    private active: DumpArchiveEntry;
    private isClosed: boolean;
    private hasHitEOF: boolean;
    private entrySize: Long;
    private entryOffset: Long;
    private readIdx: int;
    private readBuf: Int8Array = new Int8Array(DumpArchiveConstants.TP_SIZE);
    private blockBuffer: Int8Array;
    private recordOffset: int;
    private filepos: Long;
    protected raw: TapeInputStream;
    private names = new Map()
    private pending: Map<number, DumpArchiveEntry> = new Map<number, DumpArchiveEntry>();
    private queue: Queue<DumpArchiveEntry> = new Queue<DumpArchiveEntry>();
    private zipEncoding: ZipEncoding;
    private encoding: string;

    constructor(is: InputStream, encoding: string) {
        super()
        this.raw = new TapeInputStream(is);
        this.hasHitEOF = false;
        this.encoding = encoding;
        this.zipEncoding = ZipEncodingHelper.getZipEncoding(encoding);

        try {
            let headerBytes: Int8Array = this.raw.readRecord();

            if (!DumpArchiveUtil.verify(headerBytes)) {
                throw new UnrecognizedFormatException("");
            }
            this.summary = new DumpArchiveSummary(headerBytes, this.zipEncoding);
            this.raw.resetBlockSize(this.summary.getNTRec(), this.summary.isCompressed());
            this.blockBuffer = new Int8Array(4 * DumpArchiveConstants.TP_SIZE);
            this.readCLRI();
            this.readBITS();
        } catch (ex) {
            throw new ArchiveException(ex.getMessage(), ex);
        }

        let root: Dirent = new Dirent(2, 2, 4, ".");
        this.names.set(2, root);
        this.queue = new PriorityQueue<DumpArchiveEntry>()

    }

    public getBytesRead(): Long {
        return this.raw.getBytesRead();
    }

    public getSummary(): DumpArchiveSummary {
        return this.summary;
    }

    private readCLRI(): void {
        let buffer: Int8Array = this.raw.readRecord();

        if (!DumpArchiveUtil.verify(buffer)) {
            throw new InvalidFormatException();
        }

        this.active = DumpArchiveEntry.parse(buffer);

        if (SEGMENT_TYPE.CLRI != this.active.getHeaderType()) {
            throw new InvalidFormatException();
        }

        if (this.raw.skip(DumpArchiveConstants.TP_SIZE * this.active.getHeaderCount()) == -1) {
            throw new Exception();
        }
        this.readIdx = this.active.getHeaderCount();
    }

    private readBITS(): void {
        let buffer: Int8Array = this.raw.readRecord();

        if (!DumpArchiveUtil.verify(buffer)) {
            throw new InvalidFormatException();
        }

        this.active = DumpArchiveEntry.parse(buffer);

        if (SEGMENT_TYPE.BITS != this.active.getHeaderType()) {
            throw new InvalidFormatException();
        }
        if (this.raw.skip(DumpArchiveConstants.TP_SIZE * this.active.getHeaderCount()) == -1) {
            throw new Exception();
        }
        this.readIdx = this.active.getHeaderCount();
    }

    public getNextDumpEntry(): DumpArchiveEntry {
        return this.getNextEntry();
    }

    public getNextEntry(): DumpArchiveEntry {
        let entry: DumpArchiveEntry = null;
        let path: string = null;
        if (!this.queue.isEmpty()) {
            return this.queue.dequeue();
        }
        while (entry == null) {
            if (this.hasHitEOF) {
                return null;
            }
            while (this.readIdx < this.active.getHeaderCount()) {
                if (!this.active.isSparseRecord(this.readIdx++)
                && this.raw.skip(DumpArchiveConstants.TP_SIZE) == -1) {
                    throw new Exception();
                }
            }
            this.readIdx = 0;
            this.filepos = this.raw.getBytesRead();

            let headerBytes: Int8Array = this.raw.readRecord();

            if (!DumpArchiveUtil.verify(headerBytes)) {
                throw new InvalidFormatException();
            }

            this.active = DumpArchiveEntry.parse(headerBytes);

            while (SEGMENT_TYPE.ADDR == this.active.getHeaderType()) {
                if (this.raw.skip(DumpArchiveConstants.TP_SIZE
                * (this.active.getHeaderCount()
                - this.active.getHeaderHoles())) == -1) {
                    throw new Exception();
                }

                this.filepos = this.raw.getBytesRead();
                headerBytes = this.raw.readRecord();

                if (!DumpArchiveUtil.verify(headerBytes)) {
                    throw new InvalidFormatException();
                }

                this.active = DumpArchiveEntry.parse(headerBytes);
            }

            if (SEGMENT_TYPE.END == this.active.getHeaderType()) {
                this.hasHitEOF = true;

                return null;
            }

            entry = this.active;
            if (entry.isDirectory()) {
                this.readDirectoryEntry(this.active);
                // now we create an empty InputStream.
                this.entryOffset = Long.fromNumber(0);
                this.entrySize = Long.fromNumber(0);
                this.readIdx = this.active.getHeaderCount();
            } else {
                this.entryOffset = Long.fromNumber(0);
                this.entrySize = this.active.getEntrySize();
                this.readIdx = 0;
            }

            this.recordOffset = this.readBuf.length;

            path = this.getPath(entry);

            if (path == null) {
                entry = null;
            }
        }
        entry.setName(path);
        entry.setSimpleName(this.getNameMapValueByKey(entry.getIno()).getName());
        entry.setOffset(this.filepos);
        return entry;
    }

    private readDirectoryEntry(entry: DumpArchiveEntry): void{
        let size: number = entry.getEntrySize().toNumber();
        let first: boolean = true;
        while (first ||
        SEGMENT_TYPE.ADDR == entry.getHeaderType()) {
            if (!first) {
                this.raw.readRecord();
            }

            if (!this.names.get(entry.getIno()) &&
            SEGMENT_TYPE.INODE == entry.getHeaderType()) {
            }

            let datalen: int = DumpArchiveConstants.TP_SIZE * entry.getHeaderCount();

            if (this.blockBuffer.length < datalen) {
                this.blockBuffer = IOUtils.readRange(this.raw, datalen);
                if (this.blockBuffer.length != datalen) {
                    throw new Exception();
                }
            } else if (this.raw.readBytesOffset(this.blockBuffer, 0, datalen) != datalen) {
                throw new Exception();
            }

            let reclen: int = 0;

            for (let i: int = 0; i < datalen - 8 && i < size - 8;
                 i += reclen) {
                let ino: int = DumpArchiveUtil.convert32(this.blockBuffer, i);
                reclen = DumpArchiveUtil.convert16(this.blockBuffer, i + 4);

                let typeFiled: byte = this.blockBuffer[i + 6];

                let name: string = DumpArchiveUtil.decode(this.zipEncoding, this.blockBuffer, i + 8, this.blockBuffer[i + 7]);
                name = name.replace(/\u0000/g, "")

                if ('.' === name || '..' === name) {
                    continue;
                }

                let d: Dirent = new Dirent(ino, entry.getIno(), typeFiled, name);

                this.names.set(ino, d);

                this.pending.forEach((value, key) => {
                    let newVar = value;
                    let path: string = this.getPath(newVar);
                    if (path != null) {
                        newVar.setName(path);
                        newVar.setSimpleName(this.names.get(key).getName());
                        this.queue.enqueue(newVar);
                    }
                });

                for (let i = 0; i < this.queue.getSize(); i++) {
                    let e: DumpArchiveEntry;
                    this.pending.delete(e.getIno());
                }
            }
            let peekBytes: Int8Array = this.raw.peek();

            if (!DumpArchiveUtil.verify(peekBytes)) {
                throw new InvalidFormatException();
            }
            entry = DumpArchiveEntry.parse(peekBytes);
            first = false;
            size -= DumpArchiveConstants.TP_SIZE;
        }
    }

    private isNameMapHasKey(key): boolean{
        for (let entry of this.names.entries()) {
            if (entry[0] === key) {
                return true;
            }
        }
        return false;
    }

    private getNameMapValueByKey(inKey): Dirent{
        for (let [key, value] of this.names) {
            if (inKey === key) {
                return value;
            }
        }
        return null;
    }

    private getPath(entry: DumpArchiveEntry): string {
        let elements: Array<string> = new Array<string>();
        let dirent: Dirent = null;
        for (let ino: number = entry.getIno();; ino = dirent.getParentIno()) {
            if (!this.isNameMapHasKey(ino)) {
                elements = [];
                break;
            }
            dirent = this.getNameMapValueByKey(ino);
            elements.push(dirent.getName());
            if (dirent.getIno() == dirent.getParentIno()) {
                break;
            }
        }
        if (!elements.length) {
            this.pending.set(entry.getIno(), entry);
            return null;
        }
        // generate full path from stack of elements.
        let sb: string = elements.pop();
        while (elements.length) {
            sb = sb.concat('/');
            sb = sb.concat(elements.pop());
        }
        return sb;
    }

    public readBytesOffset(buf: Int8Array, off: int, len: int): int {
        if (len == 0) {
            return 0;
        }
        let totalRead: int = 0;

        if (this.hasHitEOF || this.isClosed || this.entryOffset >= this.entrySize) {
            return -1;
        }

        if (this.active == null) {
            throw new IllegalStateException();
        }

        if (this.entryOffset.add(len).gt(this.entrySize)) {
            len = this.entrySize.sub(this.entryOffset).toNumber();
        }

        while (len > 0) {
            let sz: int = len > this.readBuf.length - this.recordOffset
                ? this.readBuf.length - this.recordOffset : len;

            if (this.recordOffset + sz <= this.readBuf.length) {
                System.arraycopy(this.readBuf, this.recordOffset, buf, off, sz);
                totalRead += sz;
                this.recordOffset += sz;
                len -= sz;
                off += sz;
            }

            if (len > 0) {
                if (this.readIdx >= 512) {
                    let headerBytes: Int8Array = this.raw.readRecord();

                    if (!DumpArchiveUtil.verify(headerBytes)) {
                        throw new InvalidFormatException();
                    }

                    this.active = DumpArchiveEntry.parse(headerBytes);
                    this.readIdx = 0;
                }

                if (!this.active.isSparseRecord(this.readIdx++)) {
                    let r: int = this.raw.readBytesOffset(this.readBuf, 0, this.readBuf.length);
                    if (r != this.readBuf.length) {
                        throw new Exception();
                    }
                } else {
                    Arrays.fill(this.readBuf, 0);
                }

                this.recordOffset = 0;
            }
        }

        this.entryOffset = this.entryOffset.add(totalRead);

        return totalRead;
    }

    public close(): void {
        if (!this.isClosed) {
            this.isClosed = true;
            this.raw.close();
        }
    }

    public static matches(buffer: Int8Array, length: int): boolean {
        if (length < 32) {
            return false;
        }

        if (length >= DumpArchiveConstants.TP_SIZE) {
            return DumpArchiveUtil.verify(buffer);
        }

        return DumpArchiveConstants.NFS_MAGIC == DumpArchiveUtil.convert32(buffer, 24);
    }
}
