export const decompress: (inFile: string, outFile: string, onProgress?: (current: number, total: number) => void) => object

export const compress: (inFile: string, outFile: string, format: string, onProgress?: (current: number, total: number) => void) => object