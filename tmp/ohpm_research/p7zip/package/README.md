# p7zip

## 简介

[p7zip]，是一个 OpenHarmony/HarmonyOS 7zip解压缩库，基于 ohos-rs 开发，支持使用 API13 以上。

## 下载安装

```shell
ohpm install @dove/p7zip
```

## 接口和使用

```typescript
///将文件/文件夹压缩到指定路径下
export declare function compressToPath(src: string, dest: string): Promise<boolean>;

///将文件/文件夹压缩到指定路径下并设置密码
export declare function compressToPathEncrypted(src: string, dest: string, passwd: string): Promise<boolean>;

///将文件/文件夹压缩到指定路径下并指定压缩等级
export declare function compressWithPreset(srcPath: string, createPath: string, passwd: string, preset: number): Promise<boolean>;

///将压缩包文件解压到指定路径下
export declare function decompressFile(srcPath: string, dest: string): Promise<boolean>

///将有密码的压缩包文件解压到指定路径下
export declare function decompressFileWithPassword(srcPath: string, dest: string, passwd: string): Promise<boolean>
```