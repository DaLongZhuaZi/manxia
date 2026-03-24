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
import type ArchiveEntry from '../ArchiveEntry';
import CpioConstants from './CpioConstants'
import Exception from '../../util/Exception';
import File from '../../util/File';
import IllegalArgumentException from '../../util/IllegalArgumentException';
import CpioUtil from './CpioUtil';
import Long from "../../util/long/index";
import Charset from '../../util/Charset';
import ZipEncodingHelper from '../../archivers/zip/ZipEncodingHelper';
import { LinkOption } from '../../util/LinkOption';

export default class CpioArchiveEntry implements ArchiveEntry {
    SIZE_UNKNOWN: number = -1;
    private fileFormat: number = 0;
    private headerSize: number = 0;
    private alignmentBoundary: number = 0;
    private chksum: Long = Long.fromNumber(0);
    private filesize: Long = Long.fromNumber(0);
    private gid: Long = Long.fromNumber(0);
    private inode: Long = Long.fromNumber(0);
    private maj: Long = Long.fromNumber(0);
    private min: Long = Long.fromNumber(0);
    private mode: Long = Long.fromNumber(0);
    private mtime: Long = Long.fromNumber(0);
    private name: string;
    private nlink: Long = Long.fromNumber(0);
    private rmaj: Long = Long.fromNumber(0);
    private rmin: Long = Long.fromNumber(0);
    private uid: Long = Long.fromNumber(0);

    constructor() {
    }

    public initCpioArchiveEntryFormat(format: number) {
        switch (format) {
            case CpioConstants.FORMAT_NEW:
                this.headerSize = 110;
                this.alignmentBoundary = 4;
                break;
            case CpioConstants.FORMAT_NEW_CRC:
                this.headerSize = 110;
                this.alignmentBoundary = 4;
                break;
            case CpioConstants.FORMAT_OLD_ASCII:
                this.headerSize = 76;
                this.alignmentBoundary = 0;
                break;
            case CpioConstants.FORMAT_OLD_BINARY:
                this.headerSize = 26;
                this.alignmentBoundary = 2;
                break;
            default:
                throw new IllegalArgumentException("Unknown header type");
        }
        this.fileFormat = format;
    }

    public initCpioArchiveEntryName(name: string) {
        this.initCpioArchiveEntryFormatName(CpioConstants.FORMAT_NEW, name);
    }

    public initCpioArchiveEntryFormatName(format: number, name: string) {
        this.initCpioArchiveEntryFormat(format);
        this.name = name;
    }

    public initCpioArchiveEntryNameSize(name: string, size: Long) {
        this.initCpioArchiveEntryName(name);
        this.setSize(size);
    }

    public initCpioArchiveEntryFormatNameSize(format: number, name: string, size: Long) {
        this.initCpioArchiveEntryFormatName(format, name);
        this.setSize(size);
    }

    public initCpioArchiveEntryInputFileEntryName(inputFile: File, entryName: string) {
        this.initCpioArchiveEntryFormatInputFileEntryName(CpioConstants.FORMAT_NEW, inputFile, entryName);
    }

    public initCpioArchiveEntryFormatInputFileEntryName(format: number, inputFile: File, entryName: string) {
        this.initCpioArchiveEntryFormatNameSize(format, entryName, inputFile.isFile() ? Long.fromNumber(inputFile.length()) : Long.fromNumber(0));
        if (inputFile.isDirectory()) {
            this.setMode(Long.fromNumber(CpioConstants.C_ISDIR));
        } else if (inputFile.isFile()) {
            this.setMode(Long.fromNumber(CpioConstants.C_ISREG));
        } else {
            throw new IllegalArgumentException("Cannot determine type of file "
            + inputFile.getName());
        }
        this.setTime(inputFile.lastModified().divide(1000))
    }

    public initCpioArchiveEntryFormatInputPathEntryNameOptions(format: number, inputPath: string, entryName: string, options: LinkOption) {
        let file = new File(inputPath, "");
        this.initCpioArchiveEntryFormatNameSize(format, entryName,!file.isDirectory() ? Long.fromNumber(file.length()) : Long.fromNumber(0));
        if (file.isDirectory()) {
            this.setMode(Long.fromNumber(CpioConstants.C_ISDIR));
        } else {
            this.setMode(Long.fromNumber(CpioConstants.C_ISREG));
        }
        // TODO set other fields as needed
        this.setTime(file.lastModified());
    }

    public initCpioArchiveEntryInputPathEntryNameOptions(inputPath: string, entryName: string, options: LinkOption) {
        this.initCpioArchiveEntryFormatInputPathEntryNameOptions(CpioConstants.FORMAT_NEW, inputPath, entryName, options);
    }

    private checkNewFormat(): void {
        if ((this.fileFormat & CpioConstants.FORMAT_NEW_MASK) == 0) {
            throw new Exception();
        }
    }

    private checkOldFormat(): void {
        if ((this.fileFormat & CpioConstants.FORMAT_OLD_MASK) == 0) {
            throw new Exception();
        }
    }

    public getChksum(): Long {
        this.checkNewFormat();
        return this.chksum.and(0xFFFFFFFF);
    }

    public getDevice(): Long {
        this.checkOldFormat();
        return this.min;
    }

    public getDeviceMaj(): Long {
        this.checkNewFormat();
        return this.maj;
    }

    public getDeviceMin(): Long {
        this.checkNewFormat();
        return this.min;
    }

    public getSize(): Long {
        return this.filesize;
    }

    public getFormat(): number {
        return this.fileFormat;
    }

    public getGID(): Long {
        return this.gid;
    }

    public getHeaderSize(): number {
        return this.headerSize;
    }

    public getAlignmentBoundary(): number {
        return this.alignmentBoundary;
    }

    public getHeaderPadCount(charset?: Charset): number {
        charset = charset == undefined ? null : charset

        if (this.name == null) {
            return 0;
        }
        if (charset == null) {
            return this.getHeaderPadCountLong(Long.fromNumber(this.name.length));
        }
        return this.getHeaderPadCountLong(Long.fromNumber(ZipEncodingHelper.encode(this.name, charset).length));
    }

    public getHeaderPadCountLong(namesize: Long): number {
        if (this.alignmentBoundary == 0) {
            return 0;
        }
        let size: number = this.headerSize + 1; // Name has terminating null
        if (this.name != null) {
            size = namesize.toNumber() + size;
        }
        let remain: number = size % this.alignmentBoundary;
        if (remain > 0) {
            return this.alignmentBoundary - remain;
        }
        return 0;
    }

    public getDataPadCount(): number{
        if (this.alignmentBoundary == 0) {
            return 0;
        }
        let size: Long = this.filesize;
        let remain: number = size.toNumber() % this.alignmentBoundary;
        if (remain > 0) {
            return this.alignmentBoundary - remain;
        }
        return 0;
    }

    public getInode(): Long {
        return this.inode;
    }

    public getMode(): Long {
        return this.mode.equals(0) && CpioConstants.CPIO_TRAILER != this.name ?
        Long.fromNumber(CpioConstants.C_ISREG) : this.mode;
    }

    public getName(): string {
        return this.name;
    }

    public getNumberOfLinks(): Long {
        return this.nlink.equals(0) ?
            this.isDirectory() ? Long.fromNumber(2) : Long.fromNumber(1)
                                    : this.nlink;
    }

    public getRemoteDevice(): Long{
        this.checkOldFormat();
        return this.rmin;
    }

    public getRemoteDeviceMaj(): Long {
        this.checkNewFormat();
        return this.rmaj;
    }

    public getRemoteDeviceMin(): Long {
        this.checkNewFormat();
        return this.rmin;
    }

    public getTime(): Long {
        return this.mtime;
    }

    public getLastModifiedDate(): Date {
        return new Date(this.getTime().multiply(1000).toString());
    }

    public getUID(): Long {
        return this.uid;
    }

    public isBlockDevice(): boolean {
        return CpioUtil.fileType(this.mode).equals(CpioConstants.C_ISBLK);
    }

    public isCharacterDevice(): boolean {
        return CpioUtil.fileType(this.mode).equals(CpioConstants.C_ISCHR);
    }

    public isDirectory(): boolean {
        return CpioUtil.fileType(this.mode).equals(CpioConstants.C_ISDIR);
    }

    public isNetwork(): boolean {
        return CpioUtil.fileType(this.mode).equals(CpioConstants.C_ISNWK);
    }

    public isPipe(): boolean {
        return CpioUtil.fileType(this.mode).equals(CpioConstants.C_ISFIFO);
    }

    public isRegularFile(): boolean {
        return CpioUtil.fileType(this.mode).equals(CpioConstants.C_ISREG);
    }

    public isSocket(): boolean {
        return CpioUtil.fileType(this.mode).equals(CpioConstants.C_ISSOCK);
    }

    public isSymbolicLink(): boolean {
        return CpioUtil.fileType(this.mode).equals(CpioConstants.C_ISLNK);
    }

    public setChksum(chksum: Long): void{
        this.checkNewFormat();
        this.chksum = chksum.and(0xFFFFFFFF);
    }

    public setDevice(device: Long): void {
        this.checkOldFormat();
        this.min = device;
    }

    public setDeviceMaj(maj: Long): void {
        this.checkNewFormat();
        this.maj = maj;
    }

    public setDeviceMin(min: Long): void{
        this.checkNewFormat();
        this.min = min;
    }

    public setSize(size: Long): void {
        if (size.lessThan(0) || size.greaterThan(0xFFFFFFFF)) {
            throw new IllegalArgumentException("Invalid entry size <" + size
            + ">");
        }
        this.filesize = size;
    }

    public setGID(gid: Long): void {
        this.gid = gid;
    }

    public setInode(inode: Long): void {
        this.inode = inode;
    }

    public setMode(mode: Long): void {
        let maskedMode: Long = mode.and(CpioConstants.S_IFMT);
        switch (maskedMode.toNumber()) {
            case CpioConstants.C_ISDIR:
            case CpioConstants.C_ISLNK:
            case CpioConstants.C_ISREG:
            case CpioConstants.C_ISFIFO:
            case CpioConstants.C_ISCHR:
            case CpioConstants.C_ISBLK:
            case CpioConstants.C_ISSOCK:
            case CpioConstants.C_ISNWK:
                break;
            default:
                throw new IllegalArgumentException(
                    "Unknown mode. "
                );
        }

        this.mode = mode;
    }

    public setName(name: string): void {
        this.name = name;
    }

    public setNumberOfLinks(nlink: Long): void {
        this.nlink = nlink;
    }

    public setRemoteDevice(device: Long): void {
        this.checkOldFormat();
        this.rmin = device;
    }

    public setRemoteDeviceMaj(rmaj: Long): void {
        this.checkNewFormat();
        this.rmaj = rmaj;
    }

    public setRemoteDeviceMin(rmin: Long): void {
        this.checkNewFormat();
        this.rmin = rmin;
    }

    public setTime(time: Long): void {
        this.mtime = time;
    }

    public setUID(uid: Long): void {
        this.uid = uid;
    }
}

