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
import IllegalArgumentException from '../../util/IllegalArgumentException';
import InputStream from '../../util/InputStream';
import ArchiveUtils from '../../util/ArchiveUtils';
import IOUtils from '../../util/IOUtils';
import Integer from '../../util/Integer';
import ZipEncodingHelper from '../zip/ZipEncodingHelper';
import Exception from '../../util/Exception';
import System from '../../util/System';
import ArchiveInputStream from '../ArchiveInputStream';
import type ZipEncoding from '../zip/ZipEncoding'
import CpioConstants from './CpioConstants'
import CpioArchiveEntry from './CpioArchiveEntry'
import Long from "../../util/long/index";
import CpioUtil from "./CpioUtil"
import { LogUtil } from '../../LogUtil';

export default class CpioArchiveInputStream extends ArchiveInputStream {
    private closed: boolean;
    private entry: CpioArchiveEntry;
    private entryBytesRead: Long;
    private entryEOF: boolean;
    private tmpbuf: Int8Array = new Int8Array(4096);
    private crc: Long;
    private input: InputStream;
    private twoBytesBuf: Int8Array = new Int8Array(2);
    private fourBytesBuf: Int8Array = new Int8Array(4);
    private sixBytesBuf: Int8Array = new Int8Array(6);
    private blockSize: number;
    private zipEncoding: ZipEncoding;
    private signature: Int8Array;
    encoding: string;

    constructor(input: InputStream, blockSize: number, encoding: string) {
        super()
        this.input = input;
        if (blockSize <= 0) {
            throw new IllegalArgumentException("blockSize must be bigger than 0");
        }
        this.blockSize = blockSize;
        this.encoding = encoding;
        this.zipEncoding = ZipEncodingHelper.getZipEncoding(encoding);
    }

    public available(): number {
        this.ensureOpen();
        if (this.entryEOF) {
            return 0;
        }
        return 1;
    }

    public close(): void {
        if (!this.closed) {
            this.input.close();
            this.closed = true;
        }
    }

    private closeEntry(): void  {
        while (this.skip(Integer.MAX_VALUE) == Integer.MAX_VALUE) {
        }
    }

    private ensureOpen(): void  {
        if (this.closed) {
            throw new Exception("Stream closed");
        }
    }

    public getNextCPIOEntry(): CpioArchiveEntry {
        LogUtil.info('getNextCPIOEntry');
        this.ensureOpen();
        if (this.entry != null) {
            this.closeEntry();
        }
        this.readFully(this.twoBytesBuf, 0, this.twoBytesBuf.length);
        if (CpioUtil.byteArray2long(this.twoBytesBuf, false).equals(CpioConstants.MAGIC_OLD_BINARY)) {
            this.entry = this.readOldBinaryEntry(false);
        } else if (CpioUtil.byteArray2long(this.twoBytesBuf, true).equals(CpioConstants.MAGIC_OLD_BINARY)) {
            this.entry = this.readOldBinaryEntry(true);
        } else {
            System.arraycopy(this.twoBytesBuf, 0, this.sixBytesBuf, 0,
                this.twoBytesBuf.length);
            this.readFully(this.sixBytesBuf, this.twoBytesBuf.length,
                this.fourBytesBuf.length);
            let magicString: string = ArchiveUtils.toAsciiString(this.sixBytesBuf);
            switch (magicString) {
                case CpioConstants.MAGIC_NEW:
                    this.entry = this.readNewEntry(false);
                    break;
                case CpioConstants.MAGIC_NEW_CRC:
                    this.entry = this.readNewEntry(true);
                    break;
                case CpioConstants.MAGIC_OLD_ASCII:
                    this.entry = this.readOldAsciiEntry();
                    break;
                default:
                    throw new Exception("Unknown magic [" + magicString + "]. Occurred at byte: " + this.getBytesRead());
            }
        }
        this.entryBytesRead = Long.fromNumber(0);
        this.entryEOF = false;
        this.crc = Long.fromNumber(0);
        if (this.entry.getName() == CpioConstants.CPIO_TRAILER) {
            this.entryEOF = true;
            this.skipRemainderOfLastBlock();
            return null;
        }
        return this.entry;
    }

    public skipBytes(bytes: number): number {
        if (bytes > 0) {
            this.readFully(this.fourBytesBuf, 0, bytes);
        }
        return
    }

    public readBytesOffset(b: Int8Array, off: number, len: number): number
    {
        this.ensureOpen();
        if (off < 0 || len < 0 || off > b.length - len) {
            throw new Exception();
        }
        if (len == 0) {
            return 0;
        }

        if (this.entry == null || this.entryEOF) {
            return -1;
        }
        if (this.entryBytesRead.equals(this.entry.getSize())) {
            this.skipBytes(this.entry.getDataPadCount());
            this.entryEOF = true;
            if (this.entry.getFormat() === CpioConstants.FORMAT_NEW_CRC
            && !this.crc.equals(this.entry.getChksum())) {
                throw new Exception("CRC Error. Occurred at byte: "
                + this.getBytesRead());
            }
            return -1;
        }
        let tmplength: number = Math.min(len, this.entry.getSize().toNumber() - this.entryBytesRead.toNumber());
        if (tmplength < 0) {
            return -1;
        }

        let tmpread: number = this.readFully(b, off, tmplength);
        if (this.entry.getFormat() === CpioConstants.FORMAT_NEW_CRC) {
            for (let pos: number = 0; pos < tmpread; pos++) {
                this.crc = this.crc.add(b[pos] & 0xFF);
                this.crc = this.crc.and(0xFFFFFFFF);
            }
        }
        if (tmpread > 0) {
            this.entryBytesRead = this.entryBytesRead.add(tmpread);
        }
        return tmpread;
    }

    private readFully(b: Int8Array, off: number, len: number): number
    {
        let num: number = IOUtils.readFull(this.input, b, off, len);
        this.count(num);
        if (num < len) {
            throw new Exception();
        }
        return num;
    }

    private readRange(len: number): Int8Array
    {
        let b: Int8Array = IOUtils.readRange(this.input, len);
        this.count(b.length);
        if (b.length < len) {
            throw new Exception();
        }
        return b;
    }

    private readBinaryLong(length: number, swapHalfWord: boolean): Long
    {
        let tmp: Int8Array = this.readRange(length);
        return CpioUtil.byteArray2long(tmp, swapHalfWord);
    }

    private readAsciiLong(length: number, radix: number): Long
    {
        let tmpBuffer: Int8Array = this.readRange(length);
        return Long.fromNumber(parseInt(ArchiveUtils.toAsciiString(tmpBuffer), radix));
    }

    private readNewEntry(hasCrc: boolean): CpioArchiveEntry
    {
        LogUtil.info('readNewEntry');
        let ret: CpioArchiveEntry;
        if (hasCrc) {
            ret = new CpioArchiveEntry();
            ret.initCpioArchiveEntryFormat(CpioConstants.FORMAT_NEW_CRC)
        } else {
            ret = new CpioArchiveEntry();
            ret.initCpioArchiveEntryFormat(CpioConstants.FORMAT_NEW)
        }

        ret.setInode(this.readAsciiLong(8, 16));
        let mode: Long = this.readAsciiLong(8, 16);
        if (CpioUtil.fileType(mode).notEquals(0)) {
            ret.setMode(mode);
        }
        ret.setUID(this.readAsciiLong(8, 16));
        ret.setGID(this.readAsciiLong(8, 16));
        ret.setNumberOfLinks(this.readAsciiLong(8, 16));
        ret.setTime(this.readAsciiLong(8, 16));
        ret.setSize(this.readAsciiLong(8, 16));
        if (ret.getSize().lessThan(0)) {
            throw new Exception("Found illegal entry with negative length");
        }
        ret.setDeviceMaj(this.readAsciiLong(8, 16));
        ret.setDeviceMin(this.readAsciiLong(8, 16));
        ret.setRemoteDeviceMaj(this.readAsciiLong(8, 16));
        ret.setRemoteDeviceMin(this.readAsciiLong(8, 16));
        let namesize: Long = this.readAsciiLong(8, 16);
        if (namesize.lessThan(0)) {
            throw new Exception("Found illegal entry with negative name length");
        }
        ret.setChksum(this.readAsciiLong(8, 16));
        let name: string = this.readCString(namesize.toNumber());
        ret.setName(name);
        if (CpioUtil.fileType(mode).equals(0) && name !== CpioConstants.CPIO_TRAILER) {
            throw new Exception("Mode 0 only allowed in the trailer. Found entry name: "

            + " Occurred at byte: " + this.getBytesRead());
        }
        this.skipBytes(ret.getHeaderPadCountLong(namesize.sub(1)));

        return ret;
    }

    private readOldAsciiEntry(): CpioArchiveEntry {
        LogUtil.info('readOldAsciiEntry');
        let ret: CpioArchiveEntry = new CpioArchiveEntry();
        ret.initCpioArchiveEntryFormat(CpioConstants.FORMAT_OLD_ASCII)
        ret.setDevice(this.readAsciiLong(6, 8));
        ret.setInode(this.readAsciiLong(6, 8));
        let mode: Long = this.readAsciiLong(6, 8);
        if (CpioUtil.fileType(mode) != Long.fromNumber(0)) {
            ret.setMode(mode);
        }
        ret.setUID(this.readAsciiLong(6, 8));
        ret.setGID(this.readAsciiLong(6, 8));
        ret.setNumberOfLinks(this.readAsciiLong(6, 8));
        ret.setRemoteDevice(this.readAsciiLong(6, 8));
        ret.setTime(this.readAsciiLong(11, 8));
        let namesize: number = this.readAsciiLong(6, 8).toNumber();
        if (namesize < 0) {
            throw new Exception("Found illegal entry with negative name length");
        }
        ret.setSize(this.readAsciiLong(11, 8));
        if (ret.getSize().lessThan(0)) {
            throw new Exception("Found illegal entry with negative length");
        }
        let name: string = this.readCString(namesize);
        ret.setName(name);
        if (CpioUtil.fileType(mode).equals(0) && name != CpioConstants.CPIO_TRAILER) {
            throw new Exception("Mode 0 only allowed in the trailer. Found entry: "
            + " Occurred at byte: " + this.getBytesRead());
        }
        return ret;
    }

    private readOldBinaryEntry(swapHalfWord: boolean): CpioArchiveEntry
    {
        LogUtil.info('readOldBinaryEntry');
        let ret: CpioArchiveEntry = new CpioArchiveEntry();
        ret.initCpioArchiveEntryFormat(CpioConstants.FORMAT_OLD_BINARY)
        ret.setDevice(this.readBinaryLong(2, swapHalfWord));
        ret.setInode(this.readBinaryLong(2, swapHalfWord));
        let mode: Long = this.readBinaryLong(2, swapHalfWord);
        if (CpioUtil.fileType(mode).notEquals(0)) {
            ret.setMode(mode);
        }
        ret.setUID(this.readBinaryLong(2, swapHalfWord));
        ret.setGID(this.readBinaryLong(2, swapHalfWord));
        ret.setNumberOfLinks(this.readBinaryLong(2, swapHalfWord));
        ret.setRemoteDevice(this.readBinaryLong(2, swapHalfWord));
        ret.setTime(this.readBinaryLong(4, swapHalfWord));
        let namesize: Long = this.readBinaryLong(2, swapHalfWord);
        if (namesize.lessThan(0)) {
            throw new Exception("Found illegal entry with negative name length");
        }
        ret.setSize(this.readBinaryLong(4, swapHalfWord));
        if (ret.getSize().lessThan(0)) {
            throw new Exception("Found illegal entry with negative length");
        }
        let name: string = this.readCString(namesize.toNumber());
        ret.setName(name);
        if (CpioUtil.fileType(mode).toNumber() == 0 && name !== CpioConstants.CPIO_TRAILER) {
            throw new Exception("Mode 0 only allowed in the trailer. Found entry: "
            + "Occurred at byte: " + this.getBytesRead());
        }
        this.skip(ret.getHeaderPadCountLong(namesize.sub(1)));
        return ret;
    }

    private readCString(length: number): string {
        let tmpBuffer: Int8Array = this.readRange(length - 1);
        if (this.input.read() == -1) {
        }
        return this.zipEncoding.decode(tmpBuffer);
    }

    public skip(n: number): number {
        if (n < 0) {
            throw new IllegalArgumentException("Negative skip length");
        }
        this.ensureOpen();
        let max: number = Math.min(n, Integer.MAX_VALUE);
        let total: number = 0;
        while (total < max) {
            let len: number = max - total;
            if (len > this.tmpbuf.length) {
                len = this.tmpbuf.length;
            }
            len = this.readBytesOffset(this.tmpbuf, 0, len);
            if (len == -1) {
                this.entryEOF = true;
                break;
            }
            total += len;
        }
        return total;
    }

    public getNextEntry(): CpioArchiveEntry  {
        return this.getNextCPIOEntry();
    }

    private skipRemainderOfLastBlock(): void  {
        let readFromLastBlock: Long = this.getBytesRead().rem(this.blockSize);
        let remainingBytes: Long = readFromLastBlock.equals(0) ? Long.fromNumber(0)
                                                               : Long.fromNumber(this.blockSize).sub(readFromLastBlock);
        while (remainingBytes.greaterThan(0)) {
            let skipped: number = this.skip(this.blockSize - readFromLastBlock.toNumber());
            if (skipped <= 0) {
                break;
            }
            remainingBytes = remainingBytes.subtract(skipped);
        }
    }

    public matches(signature: Int8Array, length: number): boolean {
        if (length < 6) {
            return false;
        }
        if (signature[0] == 0x71 && (signature[1] & 0xFF) == 0xc7) {
            return true;
        }
        if (signature[1] == 0x71 && (signature[0] & 0xFF) == 0xc7) {
            return true;
        }

        if (signature[0] != 0x30) {
            return false;
        }
        if (signature[1] != 0x37) {
            return false;
        }
        if (signature[2] != 0x30) {
            return false;
        }
        if (signature[3] != 0x37) {
            return false;
        }
        if (signature[4] != 0x30) {
            return false;
        }

        if (signature[5] == 0x31) {
            return true;
        }
        if (signature[5] == 0x32) {
            return true;
        }
        if (signature[5] == 0x37) {
            return true;
        }
        return false;
    }
}
