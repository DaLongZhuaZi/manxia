# 1.0.4

- Release official version 1.0.4

# 1.0.4-rc.0

- Fixed the issue where decompressing a Zip file with empty content would cause the execution flow to enter the catch block.

# 1.0.3

- The shared library is compiled with -O3 optimization and supports LTO
- Fix CVE-2019-12900, CVE-2016-3189

## 1.0.3-rc.0

- MinizipNative add IsEncrypto() & IsUtf8() functions.

## 1.0.2

- Fixed the issue where the unzipToDirectory interface did not return an error when the password error failed

## 1.0.2-rc.2

- Added the encryption compression interface and the compression to "arrarybuffer" interface

## 1.0.2-rc.1

- Fixed an issue in unzipToDirectory where fs.write was returned without execution

## 1.0.2-rc.0

- Fix the issue of failed file creation for unzippToDirectory interface decompression

## 1.0.1

- Update the version to 1.0.1.

## 1.0.1-rc.2

- Upgrade the dependent aki version to 1.2.13

## 1.0.1-rc.1

- unzipToDirectory supports user-defined character encoding.

## 1.0.1-rc.0

- Fix the issue of Chinese character garbling.
  - Add new interfaces SetCharEncoding(charEncoding : number)
- Fix the issue of failing to create multi-level directories.
- Fix the issue of unzipToDirectory interface failing to decompress 0KB files.

## 1.0.0

- Support decryption and decompression of zip packages, including support for the GetEntryNames (get the list of files in the archive) and ExtractFileToJS (decompress file content) interfaces.
