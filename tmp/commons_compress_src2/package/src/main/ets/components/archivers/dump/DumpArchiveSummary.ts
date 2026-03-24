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
import DumpArchiveUtil from './DumpArchiveUtil'
import DumpArchiveConstants from './DumpArchiveConstants'
import type ZipEncoding from '../zip/ZipEncoding'

export default class DumpArchiveSummary {
    private dumpDate: number = 0;
    private previousDumpDate: number = 0;
    private volume: int;
    private label: string;
    private level: int;
    private filesys: string;
    private devname: string;
    private hostname: string;
    private flags: int;
    private firstrec: int;
    private ntrec: int;

    constructor(buffer: Int8Array, encoding: ZipEncoding) {
        this.dumpDate = 1000 * DumpArchiveUtil.convert32(buffer, 4);
        this.previousDumpDate = 1000 * DumpArchiveUtil.convert32(buffer, 8);
        this.volume = DumpArchiveUtil.convert32(buffer, 12);
        this.label = DumpArchiveUtil.decode(encoding, buffer, 676, DumpArchiveConstants.LBLSIZE).trim();
        this.level = DumpArchiveUtil.convert32(buffer, 692);
        this.filesys = DumpArchiveUtil.decode(encoding, buffer, 696, DumpArchiveConstants.NAMELEN).trim();
        this.devname = DumpArchiveUtil.decode(encoding, buffer, 760, DumpArchiveConstants.NAMELEN).trim();
        this.hostname = DumpArchiveUtil.decode(encoding, buffer, 824, DumpArchiveConstants.NAMELEN).trim();
        this.flags = DumpArchiveUtil.convert32(buffer, 888);
        this.firstrec = DumpArchiveUtil.convert32(buffer, 892);
        this.ntrec = DumpArchiveUtil.convert32(buffer, 896);
    }

    public getDumpDate(): Date {
        return new Date(this.dumpDate);
    }

    public setDumpDate(dumpDate: Date): void {
        this.dumpDate = dumpDate.getTime();
    }

    public getPreviousDumpDate(): Date {
        return new Date(this.previousDumpDate);
    }

    public setPreviousDumpDate(previousDumpDate: Date): void {
        this.previousDumpDate = previousDumpDate.getTime();
    }

    public getVolume(): int {
        return this.volume;
    }

    public setVolume(volume: int): void {
        this.volume = volume;
    }

    public getLevel(): int {
        return this.level;
    }

    public setLevel(level: int): void {
        this.level = level;
    }

    public getLabel(): string {
        return this.label;
    }

    public setLabel(label: string): void {
        this.label = label;
    }

    public getFilesystem(): string {
        return this.filesys;
    }

    public setFilesystem(fileSystem: string): void {
        this.filesys = fileSystem;
    }

    public getDevname(): string {
        return this.devname;
    }

    public setDevname(devname: string): void {
        this.devname = devname;
    }

    public getHostname(): string {
        return this.hostname;
    }

    public setHostname(hostname: string): void {
        this.hostname = hostname;
    }

    public getFlags(): int {
        return this.flags;
    }

    public setFlags(flags: int): void {
        this.flags = flags;
    }

    public getFirstRecord(): int {
        return this.firstrec;
    }

    public setFirstRecord(firstrec: int): void {
        this.firstrec = firstrec;
    }

    public getNTRec(): int {
        return this.ntrec;
    }

    public setNTRec(ntrec: int): void {
        this.ntrec = ntrec;
    }

    public isNewHeader(): boolean {
        return (this.flags & 0x0001) == 0x0001;
    }

    public isNewInode(): boolean {
        return (this.flags & 0x0002) == 0x0002;
    }

    public isCompressed(): boolean {
        return (this.flags & 0x0080) == 0x0080;
    }

    public isMetaDataOnly(): boolean {
        return (this.flags & 0x0100) == 0x0100;
    }

    public isExtendedAttributes(): boolean {
        return (this.flags & 0x8000) == 0x8000;
    }

    public hashCode(): int {
        let hash: int = 17;

        if (this.label != null) {
            hash = this.hashCode();
        }

        hash += 31 * this.dumpDate;

        if (this.hostname != null) {
            hash = (31 * this.hashCode()) + 17;
        }

        if (this.devname != null) {
            hash = (31 * this.hashCode()) + 17;
        }

        return hash;
    }

    public equals(o: Object): boolean {
        if (this == o) {
            return true;
        }

        if (o == null || !(o instanceof DumpArchiveSummary)) {
            return false;
        }

        let rhs: DumpArchiveSummary = o as DumpArchiveSummary;

        if (this.dumpDate != rhs.dumpDate) {
            return false;
        }

        if ((this.getHostname() == null) ||
        !(this.getHostname() == rhs.getHostname())) {
            return false;
        }

        return (this.getDevname() != null) && this.getDevname() == rhs.getDevname();
    }
}
