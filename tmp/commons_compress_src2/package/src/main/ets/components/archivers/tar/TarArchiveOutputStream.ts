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
import TarConstants from './TarConstants';
import TarArchiveEntry from './TarArchiveEntry';
import type ArchiveEntry from '../ArchiveEntry';
import ArchiveOutputStream from '../ArchiveOutputStream';
import File from '../../util/File';
import { LinkOption } from '../../util/LinkOption';
import OutputStream from '../../util/OutputStream';
import FixedLengthBlockOutputStream from '../../util/FixedLengthBlockOutputStream';
import IllegalArgumentException from '../../util/IllegalArgumentException';
import IllegalStateException from '../../util/IllegalStateException';
import Exception from '../../util/Exception';
import Arrays from '../../util/Arrays';
import CharacterSetECI from '../../util/CharacterSetECI';
import Long from "../../util/long/index";
import type ZipEncoding from '../zip/ZipEncoding';
import ZipEncodingHelper from '../zip/ZipEncodingHelper';

export default class TarArchiveOutputStream extends ArchiveOutputStream {
    public static LONGFILE_ERROR: number = 0;
    public static LONGFILE_TRUNCATE: number = 1;
    public static LONGFILE_GNU: number = 2;
    public static LONGFILE_POSIX: number = 3;
    public static BIGNUMBER_ERROR: number = 0;
    public static BIGNUMBER_STAR: number = 1;
    public static BIGNUMBER_POSIX: number = 2;
    private static RECORD_SIZE: number = 512;
    private currSize: Long;
    private currName: string;
    private currBytes: Long;
    private recordBuf: Int8Array;
    private longFileMode: number = TarArchiveOutputStream.LONGFILE_ERROR;
    private bigNumberMode: number = TarArchiveOutputStream.BIGNUMBER_ERROR;
    private recordsWritten: number;
    private recordsPerBlock: number;
    private closed: boolean;
    private haveUnclosedEntry: boolean;
    private finished: boolean;
    private out: FixedLengthBlockOutputStream;
    private countingOut: OutputStream;
    private zipEncoding: ZipEncoding;
    encoding: string;
    private addPaxHeadersForNonAsciiNames: boolean;
    private static ASCII: ZipEncoding = ZipEncodingHelper.getZipEncoding("ASCII");
    public static BLOCK_SIZE_UNSPECIFIED: number = -511;

    constructor(os: OutputStream, blockSize: number, encoding?: string) {
        super();
        let realBlockSize: number;
        if (TarArchiveOutputStream.BLOCK_SIZE_UNSPECIFIED == blockSize) {
            realBlockSize = TarArchiveOutputStream.RECORD_SIZE;
        } else {
            realBlockSize = blockSize;
        }

        if (realBlockSize <= 0 || realBlockSize % TarArchiveOutputStream.RECORD_SIZE != 0) {
            throw new IllegalArgumentException("Block size must be a multiple of 512 bytes. Attempt to use set size of " + blockSize);
        }
        this.countingOut = os;
        this.out = new FixedLengthBlockOutputStream(this.countingOut, TarArchiveOutputStream.RECORD_SIZE);
        this.encoding = encoding;
        this.zipEncoding = ZipEncodingHelper.getZipEncoding(encoding);
        this.recordBuf = new Int8Array(TarArchiveOutputStream.RECORD_SIZE);
        this.recordsPerBlock = realBlockSize / TarArchiveOutputStream.RECORD_SIZE;
    }

    public setLongFileMode(longFileMode: number): void {
        this.longFileMode = longFileMode;
    }

    public setBigNumberMode(bigNumberMode: number): void {
        this.bigNumberMode = bigNumberMode;
    }

    public setAddPaxHeadersForNonAsciiNames(b: boolean): void {
        this.addPaxHeadersForNonAsciiNames = b;
    }

    public getBytesWritten(): Long {
        return Long.fromNumber(this.countingOut.count);
    }

    public finish(): void {
        if (this.finished) {
            throw new Exception("This archive has already been finished");
        }

        if (this.haveUnclosedEntry) {
            throw new Exception("This archive contains unclosed entries.");
        }
        this.writeEOFRecord();
        this.writeEOFRecord();
        this.padAsNeeded();
        this.out.flush();
        this.finished = true;
    }

    public close(): void {
        try {
            if (!this.finished) {
                this.finish();
            }
        } finally {
            if (!this.closed) {
                this.out.close();
                this.closed = true;
            }
        }
    }

    public putArchiveEntry(archiveEntry: ArchiveEntry): void {
        if (this.finished) {
            throw new Exception("Stream has already been finished");
        }
        let entry: TarArchiveEntry = archiveEntry as TarArchiveEntry;
        if (entry.isGlobalPaxHeader()) {
            let data: Int8Array = this.encodeExtendedPaxHeadersContents(entry.getExtraPaxHeaders());
            entry.setSize(Long.fromNumber(data.length));
            entry.writeEntryHeaderEncoding(this.recordBuf, this.zipEncoding, this.bigNumberMode
            == TarArchiveOutputStream.BIGNUMBER_STAR);
            this.writeRecord(this.recordBuf);
            this.currSize = entry.getSize();
            this.currBytes = Long.fromNumber(0);
            this.haveUnclosedEntry = true;
            this.writeBytes(data);
            this.closeArchiveEntry();
        } else {
            let paxHeaders: Map<string, string> = new Map<string, string>();
            let entryName: string = entry.getName();
            let paxHeaderContainsPath: boolean = this.handleLongName(entry, entryName, paxHeaders, "path",
                TarConstants.LF_GNUTYPE_LONGNAME, "file name");

            let linkName: string = entry.getLinkName();
            let paxHeaderContainsLinkPath: boolean = linkName != null && linkName.length != 0
            && this.handleLongName(entry, linkName, paxHeaders, "linkpath",
                TarConstants.LF_GNUTYPE_LONGLINK, "link name");

            if (this.bigNumberMode == TarArchiveOutputStream.BIGNUMBER_POSIX) {
                this.addPaxHeadersForBigNumbers(paxHeaders, entry);
            } else if (this.bigNumberMode != TarArchiveOutputStream.BIGNUMBER_STAR) {
                this.failForBigNumbers(entry);
            }

            if (this.addPaxHeadersForNonAsciiNames && !paxHeaderContainsPath
            && !TarArchiveOutputStream.ASCII.canEncode(entryName)) {
                paxHeaders.set("path", entryName);
            }

            if (this.addPaxHeadersForNonAsciiNames && !paxHeaderContainsLinkPath
            && (entry.isLink() || entry.isSymbolicLink())
            && !TarArchiveOutputStream.ASCII.canEncode(linkName)) {
                paxHeaders.set("linkpath", linkName);
            }
            paxHeaders = Object.assign(paxHeaders, entry.getExtraPaxHeaders())

            if (paxHeaders.size != 0) {
                this.writePaxHeaders(entry, entryName, paxHeaders);
            }

            entry.writeEntryHeaderEncoding(this.recordBuf, this.zipEncoding, this.bigNumberMode == TarArchiveOutputStream.BIGNUMBER_STAR);
            this.writeRecord(this.recordBuf);

            this.currBytes = Long.fromNumber(0);

            if (entry.isDirectory()) {
                this.currSize = Long.fromNumber(0);
            } else {
                this.currSize = entry.getSize();
            }
            this.currName = entryName;
            this.haveUnclosedEntry = true;
        }
    }

    public closeArchiveEntry(): void {
        if (this.finished) {
            throw new Exception("Stream has already been finished");
        }
        if (!this.haveUnclosedEntry) {
            throw new Exception("No current entry to close");
        }
        this.out.flushBlock();
        if (this.currBytes.lessThan(this.currSize)) {
            throw new Exception("Entry '" + this.currName + "' closed at '"
            + this.currBytes
            + "' before the '" + this.currSize
            + "' bytes specified in the header were written");
        }
        this.recordsWritten += (this.currSize.divide(TarArchiveOutputStream.RECORD_SIZE)).toNumber();
        if (!this.currSize.rem(TarArchiveOutputStream.RECORD_SIZE).equals(0)) {
            this.recordsWritten++;
        }
        this.haveUnclosedEntry = false;
    }

    public writeBytesOffset(wBuf: Int8Array, wOffset: /*int*/
    number, numToWrite: /*int*/
    number): void {
        if (!this.haveUnclosedEntry) {
            throw new IllegalStateException("No current tar entry");
        }
        if (this.currBytes.add(numToWrite).greaterThan(this.currSize)) {
            throw new Exception("Request to write '" + numToWrite
            + "' bytes exceeds size in header of '"
            + this.currSize + "' bytes for entry '"
            + this.currName + "'");
        }
        this.out.writeBytesOffset(wBuf, wOffset, numToWrite);
        this.currBytes = this.currBytes.add(numToWrite);
    }

    writePaxHeaders(entry: TarArchiveEntry, entryName: string, headers: Map<string, string>): void {
        let name: string = "./PaxHeaders.X/" + this.stripTo7Bits(entryName);
        if (name.length >= TarConstants.NAMELEN) {
            name = name.substring(0, TarConstants.NAMELEN - 1);
        }
        let pex: TarArchiveEntry = new TarArchiveEntry();
        pex.tarArchiveEntryLinkFlag(name, TarConstants.LF_PAX_EXTENDED_HEADER_LC);
        this.transferModTime(entry, pex);

        let data: Int8Array = this.encodeExtendedPaxHeadersContents(headers);
        pex.setSize(Long.fromNumber(data.length));
        this.putArchiveEntry(pex);
        this.writeBytes(data);
        this.closeArchiveEntry();
    }

    private encodeExtendedPaxHeadersContents(headers: Map<string, string>): Int8Array {
        let w: string = '';
        headers.forEach((value, key) => {
            let len: number = key.length + value.length
            + 3 /* blank, equals and newline */
            + 2 /* guess 9 < actual length < 100 */
            ;
            let line: string = len + " " + key + "=" + value + "\n";
            let actualLength: number = ZipEncodingHelper.encode(line, CharacterSetECI.UTF8).length;
            while (len != actualLength) {

                len = actualLength;
                line = len + " " + key + "=" + value + "\n";
                actualLength = ZipEncodingHelper.encode(line, CharacterSetECI.UTF8).length;
            }
            w = w + line;
        });
        return new Int8Array(ZipEncodingHelper.encode(w, CharacterSetECI.UTF8).buffer);
    }

    private stripTo7Bits(name: string): string {
        let length: number = name.length;
        let result: string = "";
        for (let i = 0; i < length; i++) {
            let stripped: number = (name.charCodeAt(i) & 0x7F);
            if (this.shouldBeReplaced(stripped)) {
                result = result + "_";
            } else {
                result = result + String.fromCharCode(stripped);
            }
        }
        return result;
    }

    private shouldBeReplaced(c: number): boolean {
        return c == 0 // would be read as Trailing null
        || c == '/'.charCodeAt(0) // when used as last character TAE will consider the PAX header a directory
        || c == '\\'.charCodeAt(0); // same as '/' as slashes get "normalized" on Windows
    }

    private writeEOFRecord(): void {
        Arrays.fill(this.recordBuf, 0);
        this.writeRecord(this.recordBuf);
    }

    public flush(): void {
        this.out.flush();
    }

    public createArchiveEntry(inputFile: File, entryName: string): ArchiveEntry {
        if (this.finished) {
            throw new Exception("Stream has already been finished");
        }
        let tarArchiveEntry: TarArchiveEntry = new TarArchiveEntry();
        tarArchiveEntry.tarArchiveEntryFile(inputFile, entryName);
        return tarArchiveEntry;
    }

    public createArchiveEntryOptions(inputPath: string, entryName: string, ...options: LinkOption[]): ArchiveEntry {
        if (this.finished) {
            throw new Exception("Stream has already been finished");
        }
        let tarArchiveEntry: TarArchiveEntry = new TarArchiveEntry();
        let file: File = new File(inputPath, '');
        tarArchiveEntry.tarArchiveEntryLinkOptions(file, entryName, ...options);
        return tarArchiveEntry;
    }

    private writeRecord(record: Int8Array): void {
        if (record.length != TarArchiveOutputStream.RECORD_SIZE) {
            throw new Exception("Record to write has length '"
            + record.length
            + "' which is not the record size of '"
            + TarArchiveOutputStream.RECORD_SIZE + "'");
        }

        this.out.writeBytes(record);
        this.recordsWritten++;
    }

    private padAsNeeded(): void {
        let start: number = this.recordsWritten % this.recordsPerBlock;
        if (start != 0) {
            for (let i: number = start; i < this.recordsPerBlock; i++) {
                this.writeEOFRecord();
            }
        }
    }

    private addPaxHeadersForBigNumbers(paxHeaders: Map<string, string>, entry: TarArchiveEntry): void {
        this.addPaxHeaderForBigNumber(paxHeaders, "size", entry.getSize(),
            TarConstants.MAXSIZE);
        this.addPaxHeaderForBigNumber(paxHeaders, "gid", entry.getLongGroupId(),
            TarConstants.MAXID);
        this.addPaxHeaderForBigNumber(paxHeaders, "mtime",
        Long.fromNumber(entry.getModTime().getTime() / 1000),
            TarConstants.MAXSIZE);
        this.addPaxHeaderForBigNumber(paxHeaders, "uid", entry.getLongUserId(),
            TarConstants.MAXID);
        this.addPaxHeaderForBigNumber(paxHeaders, "SCHILY.devmajor",
        Long.fromNumber(entry.getDevMajor()), TarConstants.MAXID);
        this.addPaxHeaderForBigNumber(paxHeaders, "SCHILY.devminor",
        Long.fromNumber(entry.getDevMinor()), TarConstants.MAXID);
        this.failForBigNumber("mode", Long.fromNumber(entry.getMode()), TarConstants.MAXID);
    }

    private addPaxHeaderForBigNumber(paxHeaders: Map<string, string>, header: string, value: Long, maxValue: Long): void {
        if (value.lessThan(0) || value.greaterThan(maxValue)) {
            paxHeaders.set(header, value.toString());
        }
    }

    private failForBigNumbers(entry: TarArchiveEntry): void {
        this.failForBigNumber("entry size", entry.getSize(), TarConstants.MAXSIZE);
        this.failForBigNumberWithPosixMessage("group id", entry.getLongGroupId(), TarConstants.MAXID);
        this.failForBigNumber("last modification time",
        Long.fromNumber(entry.getModTime().getTime() / 1000),
            TarConstants.MAXSIZE);
        this.failForBigNumber("user id", entry.getLongUserId(), TarConstants.MAXID);
        this.failForBigNumber("mode", Long.fromNumber(entry.getMode()), TarConstants.MAXID);
        this.failForBigNumber("major device number", Long.fromNumber(entry.getDevMajor()),
            TarConstants.MAXID);
        this.failForBigNumber("minor device number", Long.fromNumber(entry.getDevMinor()),
            TarConstants.MAXID);
    }

    private failForBigNumberWithPosixMessage(field: string, value: Long, maxValue: Long): void {
        this.failForBigNumber(field, value, maxValue,
            " Use STAR or POSIX extensions to overcome this limit");
    }

    private failForBigNumber(field: string, value: Long, maxValue: Long, additionalMsg?: string): void {
        additionalMsg = additionalMsg == undefined ? '' : additionalMsg

        if (value.lessThan(0) || value.greaterThan(maxValue)) {
            throw new IllegalArgumentException(field + " '" + value //NOSONAR
            + "' is too big ( > "
            + maxValue + " )." + additionalMsg);
        }
    }

    private handleLongName(entry: TarArchiveEntry, name: string,
                           paxHeaders: Map<string, string>,
                           paxHeaderName: string, linkType: number, fieldName: string): boolean {
        let encodedName: Int8Array = this.zipEncoding.encode(name);
        let len: number = encodedName.length;
        if (len >= TarConstants.NAMELEN) {

            if (this.longFileMode == TarArchiveOutputStream.LONGFILE_POSIX) {
                paxHeaders.set(paxHeaderName, name);
                return true;
            }
            if (this.longFileMode == TarArchiveOutputStream.LONGFILE_GNU) {
                let longLinkEntry: TarArchiveEntry = new TarArchiveEntry();
                longLinkEntry.tarArchiveEntryLinkFlag(TarConstants.GNU_LONGLINK, linkType);
                longLinkEntry.setSize(Long.fromNumber(1).add(len)); // +1 for NUL
                this.transferModTime(entry, longLinkEntry);
                this.putArchiveEntry(longLinkEntry);
                this.writeBytesOffset(encodedName, 0, len);
                this.write(0); // NUL terminator
                this.closeArchiveEntry();
            } else if (this.longFileMode != TarArchiveOutputStream.LONGFILE_TRUNCATE) {
                throw new IllegalArgumentException(fieldName + " '" + name //NOSONAR
                + "' is too long ( > "
                + TarConstants.NAMELEN + " bytes)");
            }
        }
        return false;
    }

    private transferModTime(fromValue: TarArchiveEntry, to: TarArchiveEntry): void {
        let fromModTime: Date = fromValue.getModTime();
        let fromModTimeSeconds: Long = Long.fromNumber(fromModTime.getTime() / 1000);
        if (fromModTimeSeconds.lessThan(0) || fromModTimeSeconds.greaterThan(TarConstants.MAXSIZE)) {
            fromModTime = new Date(0);
        }
        to.setModTimeDate(fromModTime);
    }
}