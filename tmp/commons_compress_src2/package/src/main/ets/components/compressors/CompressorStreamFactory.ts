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
import XZCompressorInputStream from './xz/XZCompressorInputStream';
import XZCompressorOutputStream from './xz/XZCompressorOutputStream';
import CompressorInputStream from './CompressorInputStream';
import CompressorOutputStream from './CompressorOutputStream';
import type CompressorStreamProvider from './CompressorStreamProvider';
import CompressorException from './CompressorException';
import InputStream from '../util/InputStream';
import OutputStream from '../util/OutputStream';
import IOUtils from '../util/IOUtils';
import IllegalArgumentException from '../util/IllegalArgumentException';
import BZip2CompressorInputStream from './bzip2/BZip2CompressorInputStream';
import { BZip2CompressorOutputStream } from './bzip2/BZip2CompressorOutputStream';
import ZCompressorInputStream from './z/ZCompressorInputStream';
import BrotliCompressorInputStream from './brotli/BrotliCompressorInputStream'


export default class CompressorStreamFactory implements CompressorStreamProvider {
    public static readonly SINGLETON: CompressorStreamFactory = new CompressorStreamFactory(false);
    public static BROTLI: string = "br";
    public static BZIP2: string = "bzip2";
    public static GZIP: string = "gz";
    public static PACK200: string = "pack200";
    public static XZ: string = "xz";
    public static LZMA: string = "lzma";
    public static SNAPPY_FRAMED: string = "snappy-framed";
    public static SNAPPY_RAW: string = "snappy-raw";
    public static Z: string = "z";
    public static DEFLATE: string = "deflate";
    public static DEFLATE64: string = "deflate64";
    public static LZ4_BLOCK: string = "lz4-block";
    public static LZ4_FRAMED: string = "lz4-framed";
    public static ZSTANDARD: string = "zstd";
    private static YOU_NEED_BROTLI_DEC: string = CompressorStreamFactory.youNeed("Google Brotli Dec",
        "https://github.com/google/brotli/");
    private static YOU_NEED_XZ_JAVA: string = CompressorStreamFactory.youNeed("XZ for Java",
        "https://tukaani.org/xz/java.html");
    private static YOU_NEED_ZSTD_JNI: string = CompressorStreamFactory.youNeed("Zstd JNI",
        "https://github.com/luben/zstd-jni");

    private static youNeed(name: string, url: string): string {
        return " In addition to Apache Commons Compress you need the " + name + " library - see " + url;
    }

    public static findAvailableCompressorInputStreamProviders(): Map<string, CompressorStreamProvider> {
        let map = new Map<string, CompressorStreamProvider>();
        this.putAll(CompressorStreamFactory.SINGLETON.getInputStreamCompressorNames(),
            CompressorStreamFactory.SINGLETON, map);
        let provider: CompressorStreamProvider;
        for (provider of CompressorStreamFactory.findCompressorStreamProviders()) {
            this.putAll(provider.getInputStreamCompressorNames(), provider, map);
        }
        return map;
    }

    public static findAvailableCompressorOutputStreamProviders(): Map<string, CompressorStreamProvider>  {
        let map: Map<string, CompressorStreamProvider> = new Map<string, CompressorStreamProvider>();
        this.putAll(CompressorStreamFactory.SINGLETON.getOutputStreamCompressorNames(),
            CompressorStreamFactory.SINGLETON, map);
        let provider: CompressorStreamProvider;
        for (provider of CompressorStreamFactory.findCompressorStreamProviders()) {
            this.putAll(provider.getOutputStreamCompressorNames(), provider, map);
        }
        return map;
    }

    private static findCompressorStreamProviders(): Array<CompressorStreamProvider> {
        let array: CompressorStreamProvider[] = new Array<CompressorStreamProvider>();
        array.push(new CompressorStreamFactory(false));
        return array;
    }

    public static getBrotli(): string {
        return CompressorStreamFactory.BROTLI;
    }

    public static getBzip2(): string {
        return CompressorStreamFactory.BZIP2;
    }

    public static getDeflate(): string {
        return CompressorStreamFactory.DEFLATE;
    }

    public static getDeflate64(): string {
        return CompressorStreamFactory.DEFLATE64;
    }

    public static getGzip(): string {
        return CompressorStreamFactory.GZIP;
    }

    public static getLzma(): string {
        return CompressorStreamFactory.LZMA;
    }

    public static getPack200(): string {
        return CompressorStreamFactory.PACK200;
    }

    public static getSingleton(): CompressorStreamFactory {
        return CompressorStreamFactory.SINGLETON;
    }

    public static getSnappyFramed(): string {
        return CompressorStreamFactory.SNAPPY_FRAMED;
    }

    public static getSnappyRaw(): string {
        return CompressorStreamFactory.SNAPPY_RAW;
    }

    public static getXz(): string {
        return CompressorStreamFactory.XZ;
    }

    public static getZ(): string {
        return CompressorStreamFactory.Z;
    }

    public static getLZ4Framed(): string {
        return CompressorStreamFactory.LZ4_FRAMED;
    }

    public static getLZ4Block(): string {
        return CompressorStreamFactory.LZ4_BLOCK;
    }

    public static getZstandard(): string {
        return CompressorStreamFactory.ZSTANDARD;
    }

    static putAll(names: Set<string>, provider: CompressorStreamProvider,
                  map: Map<string, CompressorStreamProvider>): void {
        for (let name of names) {
            map.set(CompressorStreamFactory.toKey(name), provider);
        }
    }

    private static toKey(name: string): string {
        return name.toUpperCase();
    }

    private decompressUntilEOF: Boolean;
    private compressorInputStreamProviders: Map<string, CompressorStreamProvider>;
    private compressorOutputStreamProviders: Map<string, CompressorStreamProvider>;
    private decompressConcatenated: boolean;
    private memoryLimitInKb: number;

    constructor(decompressUntilEOF?: boolean) {
        this.decompressUntilEOF = decompressUntilEOF;

        this.decompressConcatenated = decompressUntilEOF;
        this.memoryLimitInKb = -1;
    }

    public static detect(inputStream: InputStream): string {
        if (inputStream == null) {
            throw new IllegalArgumentException("Stream must not be null.");
        }

        if (!inputStream.markSupported()) {
            throw new IllegalArgumentException("Mark is not supported.");
        }

        let signature: Int8Array = new Int8Array(12);
        inputStream.mark(signature.length);
        let signatureLength: number = -1;
        try {
            signatureLength = IOUtils.readFull(inputStream, signature);
            inputStream.reset();
        } catch (e) {
            throw new CompressorException("IOException while reading signature.");
        }

        if (BZip2CompressorInputStream.matches(signature, signatureLength)) {
            return CompressorStreamFactory.BZIP2;
        }
        throw new CompressorException("No Compressor found for the stream signature.");
    }

    public createCompressorInputStream(inputStream: InputStream): CompressorInputStream {
        return this.createCompressorNameInputStream(CompressorStreamFactory.detect(inputStream), inputStream);
    }

    public createCompressorNameInputStream(name: string, inputStream: InputStream,
                                           actualDecompressConcatenated?: boolean): CompressorInputStream {
        actualDecompressConcatenated = actualDecompressConcatenated == undefined ? this.decompressConcatenated : actualDecompressConcatenated

        if (name == null || inputStream == null) {
            throw new IllegalArgumentException("Compressor name and stream must not be null.");
        }

        try {
            if (CompressorStreamFactory.BZIP2.toLocaleLowerCase() == name.toLocaleLowerCase()) {
                return new BZip2CompressorInputStream(inputStream, actualDecompressConcatenated);
            }

            if (CompressorStreamFactory.Z.toLocaleLowerCase() == name.toLocaleLowerCase()) {
                return new ZCompressorInputStream(inputStream, this.memoryLimitInKb);
            }

            if (CompressorStreamFactory.XZ.toLocaleLowerCase() == name.toLocaleLowerCase()) {
                return new XZCompressorInputStream(inputStream, actualDecompressConcatenated, this.memoryLimitInKb);
            }

            if (CompressorStreamFactory.BROTLI.toLocaleLowerCase() == name.toLocaleLowerCase()) {
                return new BrotliCompressorInputStream(inputStream);
            }
        } catch (e) {
            throw new CompressorException("Could not create CompressorInputStream.");
        }
        let compressorStreamProvider: CompressorStreamProvider = this.getCompressorInputStreamProviders()
            .get(CompressorStreamFactory.toKey(name));
        if (compressorStreamProvider != null) {
            return compressorStreamProvider.createCompressorNameInputStream(name, inputStream, actualDecompressConcatenated);
        }
        throw new CompressorException("Compressor: " + name + " not found.");
    }

    public createCompressorOutputStream(name: string, out: OutputStream): CompressorOutputStream {
        if (name == null || out == null) {
            throw new IllegalArgumentException("Compressor name and stream must not be null.");
        }
        try {
            if (CompressorStreamFactory.BZIP2.toLocaleLowerCase() == name.toLocaleLowerCase()) {
                return new BZip2CompressorOutputStream(out, BZip2CompressorOutputStream.MAX_BLOCKSIZE);
            }

            if (CompressorStreamFactory.XZ.toLocaleLowerCase() == name.toLocaleLowerCase()) {
                return new XZCompressorOutputStream(out);
            }

        } catch (e) {
            throw new CompressorException("Could not create CompressorOutputStream");
        }

        let compressorStreamProvider: CompressorStreamProvider = this.getCompressorOutputStreamProviders()
            .get(CompressorStreamFactory.toKey(name));
        if (compressorStreamProvider != null) {
            return compressorStreamProvider.createCompressorOutputStream(name, out);
        }
        throw new CompressorException("Compressor: " + name + " not found.");
    }

    public getCompressorInputStreamProviders(): Map<string, CompressorStreamProvider> {
        if (this.compressorInputStreamProviders == null) {
            this.compressorInputStreamProviders = CompressorStreamFactory.findAvailableCompressorInputStreamProviders();
        }
        return this.compressorInputStreamProviders;
    }

    public getCompressorOutputStreamProviders(): Map<string, CompressorStreamProvider> {
        if (this.compressorOutputStreamProviders == null) {
            this.compressorOutputStreamProviders = CompressorStreamFactory.findAvailableCompressorOutputStreamProviders();
        }
        return this.compressorOutputStreamProviders;
    }

    getDecompressConcatenated(): boolean {
        return this.decompressConcatenated;
    }

    public getDecompressUntilEOF(): Boolean {
        return this.decompressUntilEOF;
    }

    public getInputStreamCompressorNames(): Set<string> {
        return new Set([CompressorStreamFactory.GZIP, CompressorStreamFactory.BROTLI, CompressorStreamFactory.BZIP2,
        CompressorStreamFactory.XZ, CompressorStreamFactory.LZMA, CompressorStreamFactory.PACK200,
        CompressorStreamFactory.DEFLATE, CompressorStreamFactory.SNAPPY_RAW, CompressorStreamFactory.SNAPPY_FRAMED,
        CompressorStreamFactory.Z, CompressorStreamFactory.LZ4_BLOCK,
        CompressorStreamFactory.LZ4_FRAMED, CompressorStreamFactory.ZSTANDARD, CompressorStreamFactory.DEFLATE64]);
    }

    public getOutputStreamCompressorNames(): Set<string> {
        return new Set([CompressorStreamFactory.GZIP, CompressorStreamFactory.BZIP2, CompressorStreamFactory.XZ,
        CompressorStreamFactory.LZMA, CompressorStreamFactory.PACK200, CompressorStreamFactory.DEFLATE,
        CompressorStreamFactory.SNAPPY_FRAMED, CompressorStreamFactory.LZ4_BLOCK, CompressorStreamFactory.LZ4_FRAMED,
        CompressorStreamFactory.ZSTANDARD]);
    }
}
