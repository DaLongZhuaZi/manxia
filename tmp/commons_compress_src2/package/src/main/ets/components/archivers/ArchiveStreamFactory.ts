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
import type ArchiveStreamProvider from './ArchiveStreamProvider';
import ArchiveInputStream from './ArchiveInputStream';
import ArchiveOutputStream from './ArchiveOutputStream';
import ArArchiveInputStream from './ar/ArArchiveInputStream';
import ArArchiveOutputStream from './ar/ArArchiveOutputStream';
import TarArchiveOutputStream from './tar/TarArchiveOutputStream';
import TarArchiveInputStream from './tar/TarArchiveInputStream';
import DumpArchiveInputStream from './dump/DumpArchiveInputStream';
import CpioArchiveOutputStream from './cpio/CpioArchiveOutputStream';
import TarConstants from './tar/TarConstants';
import ArchiveException from './ArchiveException';
import InputStream from '../util/InputStream';
import OutputStream from '../util/OutputStream';
import Exception from '../util/Exception';
import IOUtils from '../util/IOUtils';
import { LogUtil } from '../LogUtil';

export default class ArchiveStreamFactory implements ArchiveStreamProvider {
    private static DEFAULT_ENCODING: string = "UTF-8";
    private static TAR_HEADER_SIZE: number = 512;
    private static DUMP_SIGNATURE_SIZE: number = 32;
    private static SIGNATURE_SIZE: number = 12;
    public static DEFAULT: ArchiveStreamFactory = new ArchiveStreamFactory(ArchiveStreamFactory.DEFAULT_ENCODING);
    public static AR: string = "ar";
    public static ARJ: string = "arj";
    public static CPIO: string = "cpio";
    public static DUMP: string = "dump";
    public static JAR: string = "jar";
    public static TAR: string = "tar";
    public static ZIP: string = "zip";
    public static SEVEN_Z: string = "7z";
    private encoding: string;
    private entryEncoding: string;
    private archiveInputStreamProviders: Map<string, ArchiveStreamProvider>;
    private archiveOutputStreamProviders: Map<string, ArchiveStreamProvider>;

    private static findArchiveStreamProviders(): Array<ArchiveStreamProvider> {
        let array: ArchiveStreamProvider[] = new Array<ArchiveStreamProvider>();
        array.push(new ArchiveStreamFactory(ArchiveStreamFactory.DEFAULT_ENCODING));
        return array;
    }

    static putAll(names: Set<string>, provider: ArchiveStreamProvider, map: Map<string, ArchiveStreamProvider>): void {
        let name: string;
        for (name in names) {
            map.set(ArchiveStreamFactory.toKey(name), provider);
        }
    }

    private static toKey(name: string): string {
        return name.toUpperCase();
    }

    public static findAvailableArchiveInputStreamProviders(): Map<string, ArchiveStreamProvider> {
        var map = new Map<string, ArchiveStreamProvider>();
        this.putAll(ArchiveStreamFactory.DEFAULT.getInputStreamArchiveNames(), ArchiveStreamFactory.DEFAULT, map);
        let provider: ArchiveStreamProvider;
        for (provider of this.findArchiveStreamProviders()) {
            this.putAll(provider.getInputStreamArchiveNames(), provider, map);
        }
        return map;
    }

    public static findAvailableArchiveOutputStreamProviders(): Map<string, ArchiveStreamProvider> {
        let map = new Map<string, ArchiveStreamProvider>();
        this.putAll(ArchiveStreamFactory.DEFAULT.getOutputStreamArchiveNames(), ArchiveStreamFactory.DEFAULT, map);
        let provider: ArchiveStreamProvider;
        for (provider of this.findArchiveStreamProviders()) {
            this.putAll(provider.getOutputStreamArchiveNames(), provider, map);
        }
        return map;
    }

    constructor(encoding: string) {
        this.encoding = encoding;

        this.entryEncoding = encoding;
    }

    public getEntryEncoding(): string {
        return this.entryEncoding;
    }

    public createArchiveInputStream(archiverName: string, inputStream: InputStream,
                                    actualEncoding?: string): ArchiveInputStream {
        LogUtil.info('createArchiveInputStream');
        actualEncoding = actualEncoding == undefined ? this.entryEncoding : actualEncoding;

        if (archiverName == null) {
            LogUtil.error('Archivername must not be null.');
            throw new Exception("Archivername must not be null.");
        }

        if (inputStream == null) {
            LogUtil.error('InputStream must not be null.');
            throw new Exception("InputStream must not be null.");
        }

        if (ArchiveStreamFactory.AR.toLowerCase() == archiverName.toLowerCase()) {
            return new ArArchiveInputStream(inputStream);
        }

        if (ArchiveStreamFactory.DUMP.toLowerCase() == archiverName.toLowerCase()) {
            return new DumpArchiveInputStream(inputStream, actualEncoding);
        }

        let archiveStreamProvider: ArchiveStreamProvider = this.getArchiveInputStreamProviders()
            .get(ArchiveStreamFactory.toKey(archiverName));

        if (archiveStreamProvider != null) {
            return archiveStreamProvider.createArchiveInputStream(archiverName, inputStream, actualEncoding);
        }
        LogUtil.error('Archiver: ' + archiverName + ' not found.');
        throw new ArchiveException("Archiver: " + archiverName + " not found.", null);
    }

    public createArchiveOutputStream(archiverName: string, out: OutputStream, actualEncoding?: string): ArchiveOutputStream {
        LogUtil.info('createArchiveOutputStream');
        actualEncoding = actualEncoding == undefined ? this.entryEncoding : actualEncoding;

        if (archiverName == null) {
            LogUtil.error('Archivername must not be null.');
            throw new Exception("Archivername must not be null.");
        }
        if (out == null) {
            LogUtil.error('OutputStream must not be null.');
            throw new Exception("OutputStream must not be null.");
        }

        if (ArchiveStreamFactory.AR.toLowerCase() == archiverName.toLowerCase()) {
            return new ArArchiveOutputStream(out);
        }

        if (ArchiveStreamFactory.TAR.toLowerCase() == archiverName.toLowerCase()) {
            return new TarArchiveOutputStream(out, TarArchiveOutputStream.BLOCK_SIZE_UNSPECIFIED, actualEncoding);
        }

        if (ArchiveStreamFactory.CPIO.toLowerCase() == archiverName.toLowerCase()) {
            return new CpioArchiveOutputStream(out);
        }

        let archiveStreamProvider: ArchiveStreamProvider =
        this.getArchiveOutputStreamProviders()
            .get(ArchiveStreamFactory.toKey(archiverName));
        if (archiveStreamProvider != null) {
            return archiveStreamProvider.createArchiveOutputStream(archiverName, out, actualEncoding);
        }
        LogUtil.error('Archiver: ' + archiverName + ' not found.');
        throw new ArchiveException("Archiver: " + archiverName + " not found.", null);
    }

    public createArchiveInput(inputStream: InputStream): ArchiveInputStream {
        return this.createArchiveInputStream(ArchiveStreamFactory.detect(inputStream), inputStream);
    }

    public static detect(inputStream: InputStream): string {
        if (inputStream == null) {
            throw new Exception("Stream must not be null.");
        }

        let signature: Int8Array = new Int8Array(ArchiveStreamFactory.SIGNATURE_SIZE);
        inputStream.mark(signature.length);
        let signatureLength: number = -1;
        try {
            signatureLength = IOUtils.readFull(inputStream, signature);
            inputStream.reset();
        } catch (e) {
            throw new ArchiveException("IOException while reading signature.", e);
        }

        // Tar needs an even bigger buffer to check the signature; read the first block
        let tarHeader: Int8Array = new Int8Array(ArchiveStreamFactory.TAR_HEADER_SIZE);
        inputStream.mark(tarHeader.length);
        try {
            signatureLength = IOUtils.readFull(inputStream, tarHeader);
            inputStream.reset();
        } catch (e) {
            throw new ArchiveException("IOException while reading tar signature", e);
        }
        if (ArArchiveInputStream.matches(signature, signatureLength)) {
            return ArchiveStreamFactory.AR;
        }

        if (TarArchiveInputStream.matches(tarHeader, signatureLength)) {
            return ArchiveStreamFactory.TAR;
        }
        // COMPRESS-117 - improve auto-recognition
        if (signatureLength >= ArchiveStreamFactory.TAR_HEADER_SIZE) {
            let tais: TarArchiveInputStream = null;
            try {
                tais = new TarArchiveInputStream(inputStream, TarConstants.DEFAULT_BLKSIZE,
                    TarConstants.DEFAULT_RCDSIZE, null, false);

                if (tais.getNextTarEntry().isCheckSumOK()) {
                    return ArchiveStreamFactory.TAR;
                }
            } catch (e) {
            } finally {
                tais.close();
            }
        }
        throw new ArchiveException("No Archiver found for the stream signature", null);
    }

    public getArchiveInputStreamProviders(): Map<string, ArchiveStreamProvider> {
        this.archiveInputStreamProviders = this.archiveInputStreamProviders == null ?
        ArchiveStreamFactory.findAvailableArchiveInputStreamProviders() : this.archiveInputStreamProviders;
        return this.archiveInputStreamProviders;
    }

    public getArchiveOutputStreamProviders(): Map<string, ArchiveStreamProvider> {
        this.archiveOutputStreamProviders = this.archiveOutputStreamProviders == null ?
        ArchiveStreamFactory.findAvailableArchiveOutputStreamProviders() : this.archiveOutputStreamProviders;
        return this.archiveOutputStreamProviders;
    }

    public getInputStreamArchiveNames(): Set<string> {
        return new Set([ArchiveStreamFactory.AR, ArchiveStreamFactory.ARJ, ArchiveStreamFactory.ZIP,
        ArchiveStreamFactory.TAR, ArchiveStreamFactory.JAR, ArchiveStreamFactory.CPIO,
        ArchiveStreamFactory.DUMP, ArchiveStreamFactory.SEVEN_Z]);
    }

    public getOutputStreamArchiveNames(): Set<string> {
        return new Set([ArchiveStreamFactory.AR, ArchiveStreamFactory.ZIP,
        ArchiveStreamFactory.TAR, ArchiveStreamFactory.JAR,
        ArchiveStreamFactory.CPIO, ArchiveStreamFactory.SEVEN_Z]);
    }
}