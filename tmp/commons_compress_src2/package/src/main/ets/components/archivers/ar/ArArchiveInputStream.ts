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
import InputStream from '../../util/InputStream';
import ArchiveUtils from '../../util/ArchiveUtils';
import IOUtils from '../../util/IOUtils';
import Arrays from '../../util/Arrays';
import Exception from '../../util/Exception';
import IllegalStateException from '../../util/IllegalStateException';
import ArchiveInputStream from '../ArchiveInputStream';
import type ArchiveEntry from '../ArchiveEntry';
import Long from "../../util/long/index";
import { LogUtil } from '../../LogUtil';

export default class ArArchiveInputStream extends ArchiveInputStream {
    private input: InputStream;
    private offset: Long = Long.fromNumber(0);
    private closed: boolean;
    private currentEntry: ArArchiveEntry;
    private namebuffer: Int8Array;
    private entryOffset: Long = Long.fromNumber(-1);
    private static NAME_OFFSET: number = 0;
    private static NAME_LEN: number = 16;
    private static LAST_MODIFIED_OFFSET: number = ArArchiveInputStream.NAME_LEN;
    private static LAST_MODIFIED_LEN: number = 12;
    private static USER_ID_OFFSET: number = ArArchiveInputStream.LAST_MODIFIED_OFFSET + ArArchiveInputStream.LAST_MODIFIED_LEN;
    private static USER_ID_LEN: number = 6;
    private static GROUP_ID_OFFSET: number = ArArchiveInputStream.USER_ID_OFFSET + ArArchiveInputStream.USER_ID_LEN;
    private static GROUP_ID_LEN: number = 6;
    private static FILE_MODE_OFFSET = ArArchiveInputStream.GROUP_ID_OFFSET + ArArchiveInputStream.GROUP_ID_LEN;
    private static FILE_MODE_LEN: number = 8;
    private static LENGTH_OFFSET: number = ArArchiveInputStream.FILE_MODE_OFFSET + ArArchiveInputStream.FILE_MODE_LEN;
    private static LENGTH_LEN: number = 10;
    private metaData: Int8Array =
        new Int8Array(ArArchiveInputStream.NAME_LEN + ArArchiveInputStream.LAST_MODIFIED_LEN
        + ArArchiveInputStream.USER_ID_LEN + ArArchiveInputStream.GROUP_ID_LEN
        + ArArchiveInputStream.FILE_MODE_LEN + ArArchiveInputStream.LENGTH_LEN);

    public constructor(pInput: InputStream) {
        super();
        this.input = pInput;
        this.closed = false;
    }

    public getNextArEntry(): ArArchiveEntry {
        LogUtil.info('getNextArEntry');
        if (this.currentEntry != null) {
            let entryEnd: Long = this.entryOffset.add(this.currentEntry.getLength());
            let skipped: Long = IOUtils.skip(this.input, entryEnd.sub(this.offset));
            this.trackReadBytes(skipped);
            this.currentEntry = null;
        }

        if (this.offset.eq(0)) {
            let expected: Int8Array = ArchiveUtils.toAsciiBytes(ArArchiveEntry.HEADER);
            let realized: Int8Array = IOUtils.readRange(this.input, expected.length);
            let read: number = realized.length;
            this.trackReadBytes(Long.fromNumber(read));
            if (read != expected.length) {
                LogUtil.info('Failed to read header. Occurred at byte: ' +
                    this.getBytesRead().toNumber());
                throw new Exception("Failed to read header. Occurred at byte: " + this.getBytesRead().toNumber());
            }
            if (!Arrays.equals(expected, realized)) {
                LogUtil.info('Invalid header : ' +
                    ArchiveUtils.toAsciiString(realized));
                throw new Exception("Invalid header " + ArchiveUtils.toAsciiString(realized));
            }
        }

        if (this.offset.toNumber() % 2 != 0) {
            if (this.input.read() < 0) {
                // hit eof
                return null;
            }
            this.trackReadBytes(Long.fromNumber(1));
        }

        {
            let read: number = IOUtils.readFull(this.input, this.metaData);
            this.trackReadBytes(Long.fromNumber(read));
            if (read == 0) {
                return null;
            }
            if (read < this.metaData.length) {
                LogUtil.info('Truncated ar archive');
                throw new Exception("Truncated ar archive");
            }
        }

        {
            let expected: Int8Array = ArchiveUtils.toAsciiBytes(ArArchiveEntry.TRAILER);
            let realized: Int8Array = IOUtils.readRange(this.input, expected.length);
            let read: number = realized.length;
            this.trackReadBytes(Long.fromNumber(read));
            if (read != expected.length) {
                throw new Exception("Failed to read entry trailer. Occurred at byte: " + this.getBytesRead().toNumber());
            }
            if (!Arrays.equals(expected, realized)) {
                throw new Exception("Invalid entry trailer. not read the content? Occurred at byte: " + this.getBytesRead().toNumber());
            }
        }

        this.entryOffset = this.offset.add(0);

        let temp: string = ArchiveUtils.toAsciiStringView(this.metaData, ArArchiveInputStream.NAME_OFFSET, ArArchiveInputStream.NAME_LEN).trim();
        if (ArArchiveInputStream.isGNUStringTable(temp)) { // GNU extended filenames entry
            this.currentEntry = this.readGNUStringTable(this.metaData, ArArchiveInputStream.LENGTH_OFFSET, ArArchiveInputStream.LENGTH_LEN);
            return this.getNextArEntry();
        }

        let len: Long = this.asLong(this.metaData, ArArchiveInputStream.LENGTH_OFFSET, ArArchiveInputStream.LENGTH_LEN);
        if (temp.endsWith("/")) { // GNU terminator
            temp = temp.substring(0, temp.length - 1);
        } else if (this.isGNULongName(temp)) {
            let off: number = parseInt(temp.substring(1)); // get the offset
            temp = this.getExtendedName(off); // convert to the long name
        } else if (ArArchiveInputStream.isBSDLongName(temp)) {
            temp = this.getBSDLongName(temp);
            let nameLen: number = temp.length;
            len = len.sub(nameLen);
            this.entryOffset = this.entryOffset.add(nameLen);
        }

        if (len.lessThan(0)) {
            throw new Exception("broken archive, entry with negative size");
        }

        this.currentEntry = new ArArchiveEntry(temp, len,
        this.asIntBoolean(this.metaData, ArArchiveInputStream.USER_ID_OFFSET, ArArchiveInputStream.USER_ID_LEN, true),
        this.asIntBoolean(this.metaData, ArArchiveInputStream.GROUP_ID_OFFSET, ArArchiveInputStream.GROUP_ID_LEN, true),
        this.asIntNumber(this.metaData, ArArchiveInputStream.FILE_MODE_OFFSET, ArArchiveInputStream.FILE_MODE_LEN, 8),
        this.asLong(this.metaData, ArArchiveInputStream.LAST_MODIFIED_OFFSET, ArArchiveInputStream.LAST_MODIFIED_LEN));
        return this.currentEntry;
    }

    /**
     * Get an extended name from the GNU extended name buffer.
     */
    private getExtendedName(offset: number): string {
        if (this.namebuffer == null) {
            throw new Exception("Cannot process GNU long filename as no // record was found");
        }
        for (let i: number = offset; i < this.namebuffer.length; i++) {
            if (this.namebuffer[i] == 10 || this.namebuffer[i] == 0) {
                if (this.namebuffer[i - 1] == '/'.charCodeAt(0)) {
                    i--; // drop trailing /
                }
                return ArchiveUtils.toAsciiStringView(this.namebuffer, offset, i - offset);
            }
        }
        throw new Exception("Failed to read entry: " + offset);
    }

    private asLong(byteArray: Int8Array, offset: number, len: number): Long {
        return Long.fromString(ArchiveUtils.toAsciiStringView(byteArray, offset, len).trim());
    }

    private asIntBoolean(byteArray: Int8Array, offset: number, len: number, treatBlankAsZero: boolean): number {
        return this.asInt(byteArray, offset, len, 10, treatBlankAsZero);
    }

    private asIntNumber(byteArray: Int8Array, offset: number, len: number, base: number): number {
        return this.asInt(byteArray, offset, len, base, false);
    }

    private asInt(byteArray: Int8Array, offset: number, len: number, base?: number, treatBlankAsZero?: boolean): number {
        base = base == undefined ? 10 : base;
        treatBlankAsZero = treatBlankAsZero == undefined ? false : treatBlankAsZero;

        let stringValue: string = ArchiveUtils.toAsciiStringView(byteArray, offset, len).trim();
        if (stringValue.length && treatBlankAsZero) {
            return 0;
        }
        return parseInt(stringValue, base);
    }

    public getNextEntry(): ArchiveEntry {
        return this.getNextArEntry();
    }

    public close(): void {
        if (!this.closed) {
            this.closed = true;
            this.input.close();
        }
        this.currentEntry = null;
    }

    public readBytesOffset(b: Int8Array, off: number, len: number): number {
        if (len == 0) {
            return 0;
        }
        if (this.currentEntry == null) {
            throw new IllegalStateException("No current ar entry");
        }
        let entryEnd: Long = this.entryOffset.add(this.currentEntry.getLength());
        if (len < 0 || this.offset.gte(entryEnd)) {
            return -1;
        }
        let toRead: number = Math.min(len, entryEnd.sub(this.offset).toNumber());
        let ret: number = this.input.readBytesOffset(b, off, toRead);
        this.trackReadBytes(Long.fromNumber(ret));
        return ret;
    }

    public static matches(signature: Int8Array, length: number): boolean {
        // 3c21 7261 6863 0a3e

        return length >= 8 && signature[0] == 0x21 &&
        signature[1] == 0x3c && signature[2] == 0x61 &&
        signature[3] == 0x72 && signature[4] == 0x63 &&
        signature[5] == 0x68 && signature[6] == 0x3e &&
        signature[7] == 0x0a;
    }

    static BSD_LONGNAME_PREFIX: string = "#1/";
    private static BSD_LONGNAME_PREFIX_LEN: number = ArArchiveInputStream.BSD_LONGNAME_PREFIX.length;
    private static BSD_LONGNAME_PATTERN: string = "^" + ArArchiveInputStream.BSD_LONGNAME_PREFIX + "\\d+";

    private static isBSDLongName(name: string): boolean {
        var regExp = new RegExp(ArArchiveInputStream.BSD_LONGNAME_PATTERN);
        return name != null && regExp.test(name);
    }

    private getBSDLongName(bsdLongName: string): string {
        let nameLen: number = parseInt(bsdLongName.substring(ArArchiveInputStream.BSD_LONGNAME_PREFIX_LEN));
        let name: Int8Array = IOUtils.readRange(this.input, nameLen);
        let read: number = name.length;
        this.trackReadBytes(Long.fromNumber(read));
        if (read != nameLen) {
            throw new Exception("ArArchiveInputStream getBSDLongName read != nameLen");
        }
        return ArchiveUtils.toAsciiString(name);
    }

    public static GNU_STRING_TABLE_NAME: string = "//";

    private static isGNUStringTable(name: string): boolean {
        return ArArchiveInputStream.GNU_STRING_TABLE_NAME == name;
    }

    private trackReadBytes(read: Long): void {
        this.count(read.toNumber());
        if (read.toNumber() > 0) {
            this.offset = this.offset.add(read);
        }
    }

    private readGNUStringTable(length: Int8Array, offset: number, len: number): ArArchiveEntry {
        let bufflen: number = this.asInt(length, offset, len); // Assume length will fit in an int
        this.namebuffer = IOUtils.readRange(this.input, bufflen);
        let read: number = this.namebuffer.length;
        this.trackReadBytes(Long.fromNumber(read));
        if (read != bufflen) {
            throw new Exception("Failed to read complete // record: expected="
            + bufflen + " read=" + read);
        }
        var timestamp: number = new Date().getTime();
        return new ArArchiveEntry(ArArchiveInputStream.GNU_STRING_TABLE_NAME, Long.fromNumber(bufflen), 0, 0,
            ArArchiveEntry.DEFAULT_MODE, Long.fromNumber(timestamp / 1000));
    }

    private static GNU_LONGNAME_PATTERN: string = "^/\\d+";

    private isGNULongName(name: string): boolean {
        var regExp = new RegExp(ArArchiveInputStream.GNU_LONGNAME_PATTERN);
        return name != null && regExp.test(name);
    }
}