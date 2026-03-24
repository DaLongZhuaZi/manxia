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

/**
 * xz
 */
export { default as XZCompressorInputStream } from './src/main/ets/components/compressors/xz/XZCompressorInputStream'

export { default as XZCompressorOutputStream } from './src/main/ets/components/compressors/xz/XZCompressorOutputStream'

/**
 * z
 */
export { default as ZCompressorInputStream } from './src/main/ets/components/compressors/z/ZCompressorInputStream'

/**
 * zstd
 */
export { zstdCompress, zstdDecompress } from './src/main/ets/components/zstd/zstdApi'

/**
 * ar
 */
export { default as ArArchiveEntry } from './src/main/ets/components/archivers/ar/ArArchiveEntry'

export { default as ArArchiveInputStream } from './src/main/ets/components/archivers/ar/ArArchiveInputStream'

export { default as ArArchiveOutputStream } from './src/main/ets/components/archivers/ar/ArArchiveOutputStream'

/**
 * cpio
 */
export { default as CpioArchiveEntry } from './src/main/ets/components/archivers/cpio/CpioArchiveEntry'

export { default as CpioArchiveInputStream } from './src/main/ets/components/archivers/cpio/CpioArchiveInputStream'

export { default as CpioArchiveOutputStream } from './src/main/ets/components/archivers/cpio/CpioArchiveOutputStream'

export { default as CpioConstants } from './src/main/ets/components/archivers/cpio/CpioConstants'

export { default as CpioUtil } from './src/main/ets/components/archivers/cpio/CpioUtil'

/**
 * dump
 */
export { default as Dirent } from './src/main/ets/components/archivers/dump/Dirent'

export { default as DumpArchiveConstants } from './src/main/ets/components/archivers/dump/DumpArchiveConstants'

export { default as DumpArchiveEntry } from './src/main/ets/components/archivers/dump/DumpArchiveEntry'

export { default as DumpArchiveSummary } from './src/main/ets/components/archivers/dump/DumpArchiveSummary'

export { default as DumpArchiveUtil } from './src/main/ets/components/archivers/dump/DumpArchiveUtil'

export { default as TapeInputStream } from './src/main/ets/components/archivers/dump/TapeInputStream'

export { default as DumpArchiveInputStream } from './src/main/ets/components/archivers/dump/DumpArchiveInputStream'

export { default as ByteUtils } from './src/main/ets/components/archivers/dump/ByteUtils'

export { TYPE } from './src/main/ets/components/archivers/dump/Enumeration'

/**
 * brotli
 */
export { default as BrotliCompressorInputStream } from './src/main/ets/components/compressors/brotli/BrotliCompressorInputStream'

export { default as BrotliUtils } from './src/main/ets/components/compressors/brotli/BrotliUtils'

/**
 * bzip2
 */
export { default as BlockSort } from './src/main/ets/components/compressors/bzip2/BlockSort'

export { default as BZip2CompressorInputStream } from './src/main/ets/components/compressors/bzip2/BZip2CompressorInputStream'

export { Data, BZip2CompressorOutputStream } from './src/main/ets/components/compressors/bzip2/BZip2CompressorOutputStream'

export { default as BZip2Constants } from './src/main/ets/components/compressors/bzip2/BZip2Constants'

export { default as CRC } from './src/main/ets/components/compressors/bzip2/CRC'

export { default as Rand } from './src/main/ets/components/compressors/bzip2/Rand'

/**
 * deflate
 */
export { DeflateFile, InflateFile } from './src/main/ets/components/deflate/deflate'

/**
 * gzip
 */
export { gzipFile, unGzipFile } from './src/main/ets/components/gzip/gzip'

//lz4
export { lz4Compressed, lz4Decompressed } from './src/main/ets/components/lz4/lz4'

// compressors/lz77
export {
  default as AbstractLZ77CompressorInputStream
} from './src/main/ets/components/compressors/lz77support/AbstractLZ77CompressorInputStream'

export { default as CompressorInputStreams } from './src/main/ets/components/compressors/lz77support/CompressorInputStream'

export { LZ77Compressor, Block, LiteralBlock } from './src/main/ets/components/compressors/lz77support/LZ77Compressor'

export { default as subParameters } from './src/main/ets/components/compressors/lz77support/Parameters'

// archivers/lzma,sevenz
export { default as Decoder } from './src/main/ets/components/archivers/lzma/Decoder'

export { default as Encoder } from './src/main/ets/components/archivers/lzma/Encoder'

// compressors/snappy
export { snappyCompress, snappyUncompress } from './src/main/ets/components/compressors/snappy/jsSnappy'

// archivers/tar
export { default as TarArchiveEntry } from './src/main/ets/components/archivers/tar/TarArchiveEntry'

export { default as TarConstants } from './src/main/ets/components/archivers/tar/TarConstants'

export { default as TarArchiveInputStream } from './src/main/ets/components/archivers/tar/TarArchiveInputStream'

export { default as TarArchiveOutputStream } from './src/main/ets/components/archivers/tar/TarArchiveOutputStream'

//util
export { default as File } from './src/main/ets/components/util/File'

export { default as InputStream } from './src/main/ets/components/util/InputStream'

export { default as OutputStream } from './src/main/ets/components/util/OutputStream'

export { default as System } from './src/main/ets/components/util/System'

export { default as IOUtils } from './src/main/ets/components/util/IOUtils'

export { default as Exception } from './src/main/ets/components/util/Exception'

export { default as ByteArrayInputStream } from './src/main/ets/components/util/ByteArrayInputStream'

export { default as ArchiveUtils } from './src/main/ets/components/util/ArchiveUtils'

export { default as CharacterSetECI } from './src/main/ets/components/util/CharacterSetECI'

export { default as Arrays } from './src/main/ets/components/util/Arrays'

export { default as Long } from './src/main/ets/components/util/long/index'

export { default as StringBuilder } from './src/main/ets/components/util/StringBuilder'

export { default as ByteArrayOutputStream } from './src/main/ets/components/util/ByteArrayOutputStream'

// archivers
export { default as ArchiveEntry } from './src/main/ets/components/archivers/ArchiveEntry'

export { default as ArchiveInputStream } from './src/main/ets/components/archivers/ArchiveInputStream'

export { default as ArchiveOutputStream } from './src/main/ets/components/archivers/ArchiveOutputStream'

export { default as ArchiveStreamFactory } from './src/main/ets/components/archivers/ArchiveStreamFactory'

// compressors
export { default as CompressorStreamFactory } from './src/main/ets/components/compressors/CompressorStreamFactory'

export { default as CompressorInputStream } from './src/main/ets/components/compressors/CompressorInputStream'

export { default as CompressorOutputStream } from './src/main/ets/components/compressors/CompressorOutputStream'

export { default as CompressorException } from './src/main/ets/components/compressors/CompressorException'
