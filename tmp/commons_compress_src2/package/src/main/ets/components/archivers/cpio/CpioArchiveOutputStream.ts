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
import OutputStream from '../../util/OutputStream';
import ArchiveUtils from '../../util/ArchiveUtils';
import Arrays from '../../util/Arrays';
import Exception from '../../util/Exception';
import type ZipEncoding from '../zip/ZipEncoding'
import IndexOutOfBoundsException from '../../util/IndexOutOfBoundsException'
import CharsetNames from '../../util/CharsetNames'
import System from '../../util/System'
import StringBuilder from '../../util/StringBuilder'
import CpioConstants from './CpioConstants'
import ArchiveOutputStream from '../ArchiveOutputStream'
import type ArchiveEntry from '../ArchiveEntry';
import CpioArchiveEntry from './CpioArchiveEntry'
import CpioUtil from './CpioUtil'
import Long from "../../util/long/index";
import ZipEncodingHelper from '../zip/ZipEncodingHelper'
import IllegalArgumentException from '../../util/IllegalArgumentException'
import File from '../../util/File'
import { LogUtil } from '../../LogUtil';

export default class CpioArchiveOutputStream extends ArchiveOutputStream implements CpioConstants {
    private entry: CpioArchiveEntry;
    private closed: boolean;
    private finished: boolean;
    private entryFormat: number;
    private names: Map<String, CpioArchiveEntry> = new Map<String, CpioArchiveEntry>();
    private crc: Long;
    private written: Long;
    private out: OutputStream;
    private blockSize: number;
    private nextArtificalDeviceAndInode: Long = Long.fromNumber(1);
    private zipEncoding: ZipEncoding;
    encoding: string;

    constructor(out: OutputStream, format: number=CpioConstants.FORMAT_NEW,
                blockSize: number=CpioConstants.BLOCK_SIZE, encoding: string=CharsetNames.US_ASCII) {
        super()
        this.out = out;
        switch (format) {
            case CpioConstants.FORMAT_NEW:
            case CpioConstants.FORMAT_NEW_CRC:
            case CpioConstants.FORMAT_OLD_ASCII:
            case CpioConstants.FORMAT_OLD_BINARY:
                break;
            default:
                throw new IllegalArgumentException("Unknown format: " + format);
        }
        this.entryFormat = format;
        this.blockSize = blockSize;
        this.encoding = encoding;
        this.zipEncoding = ZipEncodingHelper.getZipEncoding(encoding);
    }

    private ensureOpen(): void {
        if (this.closed) {
            throw new Exception("Stream closed");
        }
    }

    public putArchiveEntry(entry: ArchiveEntry): void {
        LogUtil.info('putArchiveEntry');
        if (this.finished) {
            throw new Exception("Stream has already been finished");
        }
        let e: CpioArchiveEntry = entry as CpioArchiveEntry;
        this.ensureOpen();
        if (this.entry != null) {
            this.closeArchiveEntry(); // close previous entry
        }
        if (e.getTime().equals(-1)) {
            e.setTime(Long.fromNumber(System.currentTimeMillis() / 1000));
        }
        let format: number = e.getFormat();
        if (format != this.entryFormat) {
            throw new Exception("Header format: " + format + " does not match existing format: " + this.entryFormat);
        }

        if (this.names.has(e.getName())) {
            throw new Exception("Duplicate entry: " + e.getName());
        }
        this.names.set(e.getName(), e);
        this.writeHeader(e);
        this.entry = e;
        this.written = Long.fromNumber(0);
    }

    private writeHeader(e: CpioArchiveEntry): void {
        LogUtil.info('writeHeader');
        switch (e.getFormat()) {
            case CpioConstants.FORMAT_NEW:
                this.out.writeBytes(ArchiveUtils.toAsciiBytes(CpioConstants.MAGIC_NEW));
                this.counts(6);
                this.writeNewEntry(e);
                break;
            case CpioConstants.FORMAT_NEW_CRC:
                this.out.writeBytes(ArchiveUtils.toAsciiBytes(CpioConstants.MAGIC_NEW_CRC));
                this.counts(6);
                this.writeNewEntry(e);
                break;
            case CpioConstants.FORMAT_OLD_ASCII:
                this.out.writeBytes(ArchiveUtils.toAsciiBytes(CpioConstants.MAGIC_OLD_ASCII));
                this.counts(6);
                this.writeOldAsciiEntry(e);
                break;
            case CpioConstants.FORMAT_OLD_BINARY:
                let swapHalfWord: boolean = true;
                this.writeBinaryLong(Long.fromNumber(CpioConstants.MAGIC_OLD_BINARY), 2, swapHalfWord);
                this.writeOldBinaryEntry(e, swapHalfWord);
                break;
            default:
                throw new Exception("Unknown format " + e.getFormat());
        }
    }

    private writeNewEntry(entry: CpioArchiveEntry): void  {
        LogUtil.info('writeNewEntry');
        let inode: Long = entry.getInode();
        let devMin: Long = entry.getDeviceMin();
        if (CpioConstants.CPIO_TRAILER === entry.getName()) {
            inode = devMin = Long.fromNumber(0);
        } else {
            if (inode.equals(0) && devMin.equals(0)) {
                inode = this.nextArtificalDeviceAndInode.and(0xFFFFFFFF);
                this.nextArtificalDeviceAndInode = this.nextArtificalDeviceAndInode.add(1)
                devMin = this.nextArtificalDeviceAndInode.shiftRight(32).and(0xFFFFFFFF);
            } else {
                this.nextArtificalDeviceAndInode = Long.fromNumber(Math.max(this.nextArtificalDeviceAndInode.toNumber(),
                (devMin.multiply(0x100000000).add(inode)).toNumber()) + 1)
            }
        }
        this.writeAsciiLong(inode, 8, 16);
        this.writeAsciiLong(entry.getMode(), 8, 16);
        this.writeAsciiLong(entry.getUID(), 8, 16);
        this.writeAsciiLong(entry.getGID(), 8, 16);
        this.writeAsciiLong(entry.getNumberOfLinks(), 8, 16);
        this.writeAsciiLong(entry.getTime(), 8, 16);
        this.writeAsciiLong(entry.getSize(), 8, 16);
        this.writeAsciiLong(entry.getDeviceMaj(), 8, 16);
        this.writeAsciiLong(devMin, 8, 16);
        this.writeAsciiLong(entry.getRemoteDeviceMaj(), 8, 16);
        this.writeAsciiLong(entry.getRemoteDeviceMin(), 8, 16);
        let name: Int8Array = this.encode(entry.getName());
        this.writeAsciiLong(Long.fromNumber(name.length + 1), 8, 16);
        this.writeAsciiLong(entry.getChksum(), 8, 16);
        this.writeCString(name);
        this.pad(entry.getHeaderPadCountLong(Long.fromNumber(name.length)));
    }

    private writeOldAsciiEntry(entry: CpioArchiveEntry): void
    {
        LogUtil.info('writeOldAsciiEntry');
        let inode: Long = entry.getInode();
        let device: Long = entry.getDevice();
        if (CpioConstants.CPIO_TRAILER === entry.getName()) {
            inode = device = Long.fromNumber(0);
        } else {
            if (inode.equals(0) && device.equals(0)) {
                inode = this.nextArtificalDeviceAndInode.and(0o777777);
                this.nextArtificalDeviceAndInode = this.nextArtificalDeviceAndInode.add(1)
                device = (this.nextArtificalDeviceAndInode.shiftRight(18)).and(0o777777);
            } else {
                this.nextArtificalDeviceAndInode = Long.fromNumber(Math.max(this.nextArtificalDeviceAndInode.toNumber(),
                (device.multiply(0o1000000).add(inode)).toNumber()) + 1)
            }
        }

        this.writeAsciiLong(device, 6, 8);
        this.writeAsciiLong(inode, 6, 8);
        this.writeAsciiLong(entry.getMode(), 6, 8);
        this.writeAsciiLong(entry.getUID(), 6, 8);
        this.writeAsciiLong(entry.getGID(), 6, 8);
        this.writeAsciiLong(entry.getNumberOfLinks(), 6, 8);
        this.writeAsciiLong(entry.getRemoteDevice(), 6, 8);
        this.writeAsciiLong(entry.getTime(), 11, 8);
        let name: Int8Array = this.encode(entry.getName());
        this.writeAsciiLong(Long.fromNumber(name.length + 1), 6, 8);
        this.writeAsciiLong(entry.getSize(), 11, 8);
        this.writeCString(name);
    }

    private writeOldBinaryEntry(entry: CpioArchiveEntry,
                                swapHalfWord: boolean): void  {
        LogUtil.info('writeOldBinaryEntry');
        let inode: Long = entry.getInode();
        let device: Long = entry.getDevice();
        if (CpioConstants.CPIO_TRAILER === entry.getName()) {
            inode = device = Long.fromNumber(0);
        } else {
            if (inode.equals(0) && device.equals(0)) {
                inode = this.nextArtificalDeviceAndInode.and(0xFFFF);
                this.nextArtificalDeviceAndInode = this.nextArtificalDeviceAndInode.add(1)
                device = this.nextArtificalDeviceAndInode.shiftRight(16).and(0xFFFF);
            } else {
                this.nextArtificalDeviceAndInode = Long.fromNumber(Math.max(this.nextArtificalDeviceAndInode.toNumber(),
                (device.multiply(0x10000).add(inode)).toNumber()) + 1)

            }
        }

        this.writeBinaryLong(device, 2, swapHalfWord);
        this.writeBinaryLong(inode, 2, swapHalfWord);
        this.writeBinaryLong(entry.getMode(), 2, swapHalfWord);
        this.writeBinaryLong(entry.getUID(), 2, swapHalfWord);
        this.writeBinaryLong(entry.getGID(), 2, swapHalfWord);
        this.writeBinaryLong(entry.getNumberOfLinks(), 2, swapHalfWord);
        this.writeBinaryLong(entry.getRemoteDevice(), 2, swapHalfWord);
        this.writeBinaryLong(entry.getTime(), 4, swapHalfWord);
        let name: Int8Array = this.encode(entry.getName());
        this.writeBinaryLong(Long.fromNumber(name.length + 1), 2, swapHalfWord);
        this.writeBinaryLong(entry.getSize(), 4, swapHalfWord);
        this.writeCString(name);
        this.pad(entry.getHeaderPadCountLong(Long.fromNumber(name.length)));
    }

    public closeArchiveEntry(): void  {
        if (this.finished) {
            throw new Exception("Stream has already been finished");
        }
        this.ensureOpen();
        if (this.entry == null) {
            throw new Exception("Trying to close non-existent entry");
        }
        if (this.entry.getSize().notEquals(this.written)) {
            throw new Exception("Invalid entry size (expected "
            + this.entry.getSize() + " but got " + this.written
            + " bytes)");
        }
        this.pad(this.entry.getDataPadCount());
        if (this.entry.getFormat() == CpioConstants.FORMAT_NEW_CRC
        && this.crc.notEquals(this.entry.getChksum())) {
            throw new Exception("CRC Error");
        }
        this.entry = null;
        this.crc = Long.fromNumber(0);
        this.written = Long.fromNumber(0);
    }

    public writeBytesOffset(b: Int8Array, off: number, len: number): void
    {
        this.ensureOpen();
        if (off < 0 || len < 0 || off > b.length - len) {
            throw new IndexOutOfBoundsException();
        }
        if (len == 0) {
            return;
        }

        if (this.entry == null) {
            throw new Exception("No current CPIO entry");
        }
        if (this.written.add(len).greaterThan(this.entry.getSize())) {
            throw new Exception("Attempt to write past end of STORED entry");
        }
        this.out.writeBytesOffset(b, off, len);
        this.written = this.written.add(len);
        if (this.entry.getFormat() == CpioConstants.FORMAT_NEW_CRC) {
            for (let pos: number = 0; pos < len; pos++) {
                this.crc = this.crc.add(b[pos] & (0xFF));
                this.crc = this.crc.and(0xFFFFFFFF);
            }
        }
        this.counts(len);
    }

    public finish(): void  {
        this.ensureOpen();
        if (this.finished) {
            throw new Exception("This archive has already been finished");
        }

        if (this.entry != null) {
            throw new Exception("This archive contains unclosed entries.");
        }
        this.entry = new CpioArchiveEntry();
        this.entry.initCpioArchiveEntryFormat(this.entryFormat)
        this.entry.setName(CpioConstants.CPIO_TRAILER);
        this.entry.setNumberOfLinks(Long.fromNumber(1));
        this.writeHeader(this.entry);
        this.closeArchiveEntry();

        let lengthOfLastBlock: number = this.getBytesWritten().toNumber() % this.blockSize;
        if (lengthOfLastBlock != 0) {
            this.pad(this.blockSize - lengthOfLastBlock);
        }

        this.finished = true;
    }

    public close(): void  {
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

    private pad(count: number): void {
        if (count > 0) {
            let buff: Int8Array = new Int8Array(count);
            this.out.writeBytes(buff);
            this.counts(count);
        }
    }

    private writeBinaryLong(number: Long, length: number,
                            swapHalfWord: boolean): void {
        let tmp: Int8Array = CpioUtil.long2byteArray(number, length, swapHalfWord);
        this.out.writeBytes(tmp);
        this.counts(tmp.length);
    }

    private writeAsciiLong(number: Long, length: number,
                           radix: number): void  {
        let tmp: StringBuilder = new StringBuilder();
        let tmpStr: string;
        if (radix == 16) {
            tmp.append(number.toString(16));
        } else if (radix == 8) {
            tmp.append(number.toString(8));
        } else {
            tmp.append(number.toString());
        }

        if (tmp.length() <= length) {
            let insertLength: number = length - tmp.length();
            for (let pos: number = 0; pos < insertLength; pos++) {
                tmp.insert(0, "0");
            }
            tmpStr = tmp.toString();

        }
        else {

            tmpStr = tmp.substring(tmp.length() - length, null);
        }

        let b: Int8Array = ArchiveUtils.toAsciiBytes(tmpStr);
        this.out.writeBytes(b);
        this.counts(b.length);
    }

    private encode(str: string): Int8Array  {
        let buf: Int8Array = this.zipEncoding.encode(str);
        let len: number = buf.length;
        return Arrays.copyOfRangeByte(buf, 0, len);
    }

    private writeCString(str: Int8Array): void  {
        this.out.writeBytes(str);
        this.out.write(0);
        this.counts(str.length + 1);
    }

    public createArchiveEntryFile(inputFile: File, entryName: string): ArchiveEntry
    {
        if (this.finished) {
            throw new Exception("Stream has already been finished");
        }

        let bean = new CpioArchiveEntry();
        bean.initCpioArchiveEntryInputFileEntryName(inputFile, entryName)
        return bean;

    }

    public createArchiveEntry(inputFile: File, entryName: string): ArchiveEntry {
        return null;
    }

    public createArchiveEntryOption(inputPath: string, entryName: string, options): ArchiveEntry
    {
        if (this.finished) {
            throw new Exception("Stream has already been finished");
        }
        let path = new CpioArchiveEntry()
        path.initCpioArchiveEntryInputPathEntryNameOptions(inputPath, entryName, options)
        return path;
    }
}
