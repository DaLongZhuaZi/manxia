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

import { int } from '../../util/CustomTypings'
import type ArchiveEntry from '../ArchiveEntry'
import { SEGMENT_TYPE, TYPE, PERMISSION } from './Enumeration'
import Long from "../../util/long/index"
import System from '../../util/System'
import DumpArchiveSummary from './DumpArchiveSummary'
import DumpArchiveUtil from './DumpArchiveUtil'
import TapeSegmentHeader from './TapeSegmentHeader'

export default class DumpArchiveEntry implements ArchiveEntry {
    public name: string;
    public typeFiled: TYPE = TYPE.UNKNOWN;
    private mode: int;
    private permissions: Array<PERMISSION> = new Array<PERMISSION>();
    private size: Long;
    private atime: number;
    private mtime: number;
    private uid: int;
    private gid: int;
    private status: SEGMENT_TYPE = null
    SIZE_UNKNOWN: number;
    public parentIno: int;
    private summary: DumpArchiveSummary = null;
    private header: TapeSegmentHeader = new TapeSegmentHeader();
    private simpleName: string;
    private originalName: string;
    private volume: int;
    private offset: Long;
    public ino: int;
    private nlink: int;
    private ctime: number;
    private generation: int;
    private isDelete: boolean;

    constructor(name: string, simpleName: string, ino: int, typeFiled: TYPE) {
        this.setType(typeFiled);
        this.setName(name);
        this.simpleName = simpleName;
        this.ino = ino;
        this.offset = Long.fromNumber(0);
    }

    public getSimpleName(): string {
        return this.simpleName;
    }

    public getParentIno(): int {
        return this.parentIno;
    }

    public setSimpleName(simpleName: string): void {
        this.simpleName = simpleName;
    }

    public getIno(): int {
        return this.header.getIno();
    }

    public getNlink(): int {
        return this.nlink;
    }

    public setNlink(nlink: int): void {
        this.nlink = nlink;
    }

    public getCreationTime(): Date  {
        return new Date(this.ctime);
    }

    public setCreationTime(ctime: Date): void {
        this.ctime = ctime.getTime();
    }

    public getGeneration(): int {
        return this.generation;
    }

    public setGeneration(generation: int): void {
        this.generation = generation;
    }

    public isDeleted(): boolean {
        return this.isDelete;
    }

    public setDeleted(isDeleted: boolean): void {
        this.isDelete = isDeleted;
    }

    public getOffset(): Long {
        return this.offset;
    }

    public setOffset(offset: Long): void {
        this.offset = offset;
    }

    public getVolume(): int {
        return this.volume;
    }

    public setVolume(volume: int): void {
        this.volume = volume;
    }

    public getHeaderType(): SEGMENT_TYPE {
        return this.header.getType();
    }

    public getHeaderCount(): int  {
        return this.header.getCount();
    }

    public getHeaderHoles(): int {
        return this.header.getHoles();
    }

    public isSparseRecord(idx: int): boolean {
        return (this.header.getCdata(idx) & 0x01) == 0;
    }

    public hashCode(): int {
        return this.ino;
    }

    public equals(o: object): boolean {
        if (o == this) {
            return true;
        }
        if (o == null) {
            return false;
        }

        let rhs: DumpArchiveEntry;

        if (rhs.header == null) {
            return false;
        }

        if (this.ino !== rhs.ino) {
            return false;
        }

        if ((this.summary == null && rhs.summary != null)
        || (this.summary != null && !this.summary.equals(rhs.summary))) {
            return false;
        }

        return true;
    }

    public toString(): string {
        return this.getName();
    }

    static parse(buffer: Int8Array): DumpArchiveEntry {
        let entry: DumpArchiveEntry = new DumpArchiveEntry(null, null, null, null);
        let header: TapeSegmentHeader = entry.header;

        header.typeField = SEGMENT_TYPE[SEGMENT_TYPE[DumpArchiveUtil.convert32(buffer, 0)]];

        header.volume = DumpArchiveUtil.convert32(buffer, 12);
        entry.ino = header.ino = DumpArchiveUtil.convert32(buffer, 20);
        let m: int = DumpArchiveUtil.convert16(buffer, 32);

        entry.setType(TYPE[TYPE[(m >> 12) & 0x0F]]);
        entry.setMode(m);

        entry.nlink = DumpArchiveUtil.convert16(buffer, 34);
        entry.setSize(DumpArchiveUtil.convert64(buffer, 40));

        let t: number = (1000 * DumpArchiveUtil.convert32(buffer, 48)) +
        (DumpArchiveUtil.convert32(buffer, 52) / 1000);
        entry.setAccessTime(new Date(t));
        t = (1000 * DumpArchiveUtil.convert32(buffer, 56)) +
        (DumpArchiveUtil.convert32(buffer, 60) / 1000);
        entry.setLastModifiedDate(new Date(t));
        t = (1000 * DumpArchiveUtil.convert32(buffer, 64)) +
        (DumpArchiveUtil.convert32(buffer, 68) / 1000);
        entry.ctime = t;

        entry.generation = DumpArchiveUtil.convert32(buffer, 140);
        entry.setUserId(DumpArchiveUtil.convert32(buffer, 144));
        entry.setGroupId(DumpArchiveUtil.convert32(buffer, 148));
        header.count = DumpArchiveUtil.convert32(buffer, 160);

        header.holes = 0;

        for (let i: int = 0; (i < 512) && (i < header.count); i++) {
            if (buffer[164 + i] == 0) {
                header.holes++;
            }
        }

        System.arraycopy(buffer, 164, header.cdata, 0, 512);
        entry.volume = header.getVolume();

        return entry;
    }

    update(buffer: Int8Array) {
        this.header.volume = DumpArchiveUtil.convert32(buffer, 16);
        this.header.count = DumpArchiveUtil.convert32(buffer, 160);

        this.header.holes = 0;

        for (let i: int = 0; (i < 512) && (i < this.header.count); i++) {
            if (buffer[164 + i] == 0) {
                this.header.holes++;
            }
        }

        System.arraycopy(buffer, 164, this.header.cdata, 0, 512);
    }

    public getName(): string {
        return this.name;
    }

    getOriginalName(): string {
        return this.originalName;
    }

    public setName(name: string): void {
        this.originalName = name;
        if (name != null) {
            if (this.isDirectory() && !name.endsWith("/")) {
                name += "/";
            }
            if (name.startsWith("./")) {
                name = name.substring(2);
            }
        }
        this.name = name;
    }

    public getLastModifiedDate(): Date {
        return new Date(this.mtime);
    }

    public isDirectory(): boolean {
        return this.typeFiled == TYPE.DIRECTORY;
    }

    public isFile(): boolean {
        return this.typeFiled == TYPE.FILE;
    }

    public isSocket(): boolean {
        return this.typeFiled == TYPE.SOCKET;
    }

    public isChrDev(): boolean {
        return this.typeFiled == TYPE.CHRDEV;
    }

    public isBlkDev(): boolean {
        return this.typeFiled == TYPE.BLKDEV;
    }

    public isFifo(): boolean {
        return this.typeFiled == TYPE.FIFO;
    }

    public getType(): TYPE {
        return this.typeFiled;
    }

    public setType(typeFiled: TYPE): void {
        this.typeFiled = typeFiled;
    }

    public getMode(): int {
        return this.mode;
    }

    public setMode(mode: int): void {
        this.mode = mode;
    }

    public getPermissions() {
        return this.permissions;
    }

    public getSize(): Long {
        return this.isDirectory() ? Long.fromNumber(0) : this.size;
    }

    getEntrySize(): Long {
        return this.size;
    }

    public setSize(size: Long): void {
        this.size = size;
    }

    public setLastModifiedDate(mtime: Date): void {
        this.mtime = mtime.getTime();
    }

    public getAccessTime(): Date {
        return new Date(this.atime);
    }

    public setAccessTime(atime: Date): void {
        this.atime = atime.getTime();
    }

    public getUserId(): int {
        return this.uid;
    }

    public setUserId(uid: int): void {
        this.uid = uid;
    }

    public getGroupId(): int {
        return this.gid;
    }

    public setGroupId(gid: int): void {
        this.gid = gid;
    }
}


