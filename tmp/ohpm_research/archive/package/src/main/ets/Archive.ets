import archive from 'libmyarchive.so'

export namespace archiveLib {
  export interface Result {
    code: number
    message: string
  }

  export type ProgressCallback = (current: number, total: number) => void

  export type CompressFormat = '7z' | 'tar' | 'zip' | 'gz' | 'xz'

  export interface DecompressOptions {
    inFile: string
    outFile: string
    onProgress?: ProgressCallback
  }

  export interface CompressOptions {
    inFile: string
    outFile: string
    format: CompressFormat
    onProgress?: ProgressCallback
  }

  export async function decompress(options: DecompressOptions): Promise<Result>
  export async function decompress(inFile: string, outFile: string, onProgress?: ProgressCallback): Promise<Result>
  export async function decompress(
    optionsOrInFile: DecompressOptions | string,
    outFile?: string,
    onProgress?: ProgressCallback
  ): Promise<Result> {
    if (typeof optionsOrInFile === 'string') {
      return archive.decompress(optionsOrInFile, outFile!, onProgress) as Result
    }
    return archive.decompress(optionsOrInFile.inFile, optionsOrInFile.outFile, optionsOrInFile.onProgress) as Result
  }

  export async function compress(options: CompressOptions): Promise<Result>
  export async function compress(inFile: string, outFile: string, format: CompressFormat, onProgress?: ProgressCallback): Promise<Result>
  export async function compress(
    optionsOrInFile: CompressOptions | string,
    outFile?: string,
    format?: CompressFormat,
    onProgress?: ProgressCallback
  ): Promise<Result> {
    if (typeof optionsOrInFile === 'string') {
      return archive.compress(optionsOrInFile, outFile!, format!, onProgress) as Result
    }
    return archive.compress(optionsOrInFile.inFile, optionsOrInFile.outFile, optionsOrInFile.format, optionsOrInFile.onProgress) as Result
  }
}