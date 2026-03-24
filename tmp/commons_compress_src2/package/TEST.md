# commons-compress单元测试用例

该测试用例基于OpenHarmony系统下

单元测试用例覆盖情况

|             接口名              |是否通过	|备注|
|:----------------------------:|:---:|:---:|
|      ArchiveStreamFactory.DEFAULT.createArchiveOutputStream()       |pass||
|  ArArchiveEntry()  |pass||
|      putArchiveEntry()       |pass ||
| copyStream() |pass ||
|      closeArchiveEntry()       |pass||
|  currentTimeMillis()  |pass||
|      close()       |pass ||
| OutputStream() |pass ||
|      setFilePath()       |pass||
|  getPath()  |pass||
|      InputStream()       |pass ||
| File() |pass ||
|      getNextEntry()       |pass||
|  getName()  |pass||
|      getParentFile()       |pass ||
| ArArchiveInputStream() |pass ||
|  getSize()  |pass||
|      readBytes()       |pass ||
| ArchiveUtils.toAsciiString() |pass ||
|      CpioArchiveEntry()       |pass||
|  initCpioArchiveEntryNameSize()  |pass||
|      StringBuilder()       |pass ||
| append() |pass ||
|      CpioArchiveInputStream()       |pass||
|  read()  |pass||
|      toByteArray()       |pass ||
| CpioArchiveOutputStream() |pass ||
|      initCpioArchiveEntryFormatInputFileEntryName()       |pass||
|  getNextCPIOEntry()  |pass||
|      long2byteArray()       |pass ||
| byteArray2long() |pass ||
|  DumpArchiveEntry()  |pass||
|      getSimpleName()       |pass ||
| getOriginalName() |pass ||
|      DumpArchiveInputStream()       |pass||
|  readRange()  |pass||
|      DumpArchiveUtil.convert32()       |pass ||
| DumpArchiveUtil.convert16() |pass ||
|      isDirectory()       |pass||
|  TarArchiveEntry()  |pass||
|      tarArchiveEntryPreserveAbsolutePath2()       |pass ||
| setModTime() |pass ||
|      setSize()       |pass||
|  setUserId()  |pass||
|      setGroupId()       |pass ||
| setUserName() |pass ||
|  setGroupName()  |pass||
|      setMode()       |pass ||
| TarArchiveInputStream() |pass ||
|      getNextTarEntry()       |pass||
|  BrotliCompressorInputStream()  |pass||
|      available()       |pass ||
| readFull() |pass ||
|      ByteArrayOutputStream()       |pass||
|  write()  |pass||
|      new CompressorStreamFactory().createCompressorOutputStream()       |pass ||
| arraycopy() |pass ||
|      BlockSort()       |pass||
|  blockSort()  |pass||
|      LZ77Compressor()       |pass ||
| compressByte() |pass ||
| finish() |pass ||
| LiteralBlock() |pass ||
|      copyOfRangeInt()       |pass||
|  getData()  |pass||
|      getOffset()       |pass ||
| builder() |pass ||
| build() |pass ||
| withMinBackReferenceLength() |pass ||
|      withMaxBackReferenceLength()       |pass||
|  withMaxOffset()  |pass||
|      withMaxLiteralLength()       |pass ||
| readLiteral() |pass ||
| readBackReference() |pass ||
| startLiteral() |pass ||
|      ByteArrayInputStream()       |pass||
|  startBackReference()  |pass||
|      prefill()       |pass ||
| getWindowSize() |pass ||
| getMinBackReferenceLength() |pass ||
|      getMaxBackReferenceLength()       |pass||
|  getMaxOffset()  |pass||
|      getMaxLiteralLength()       |pass ||
| newParameters() |pass ||
| XZCompressorInputStream() |pass ||
| matches() |pass ||
| XZCompressorOutputStream() |pass ||
|      ZCompressorInputStream()       |pass||
|  zstdCompress()  |pass||
|      zstdDecompress()       |pass ||
| lzmaCompress() |pass ||
|      lzmaUncompress()       |pass||
|  Encoder()  |pass||
|      SetAlgorithm()       |pass ||
| SetDictionarySize() |pass ||
| SetNumFastBytes() |pass ||
|  SetMatchFinder()  |pass||
|      SetLcLpPb()       |pass ||
| SetEndMarkerMode() |pass ||
| WriteCoderProperties() |pass ||
|      Code()       |pass||
|  flush()  |pass||
|      Decoder()       |pass ||
| SetDecoderProperties() |pass ||
| readBytesOffset() |pass ||
| DeflateFile() |pass ||
| InflateFile() |pass ||
| lz4Compressed() |pass ||
| lz4Decompressed() |pass ||
| snappyCompress() |pass ||
| snappyUncompress() |pass ||