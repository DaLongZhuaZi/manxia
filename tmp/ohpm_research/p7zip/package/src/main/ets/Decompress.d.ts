import { FileInfo } from "./FileInfo";
export declare class Decompress {
    static readEntries(o: string, p: string): Promise<Array<FileInfo>>;
    static decompressFile(m: string, n: string): Promise<void>;
    static decompressFileWithPassword(j: string, k: string, l: string): Promise<void>;
}
