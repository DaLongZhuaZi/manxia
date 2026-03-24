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
import zstd from "libzstdnapi.so";

/**
 * 压缩文件
 * src:需要压缩的文件包路径
 * archive:压缩文件存放的路径
 * level:压缩等级,默认为1级
 * nbThreads:线程数,默认为3
 * boolean:返回值，压缩成功则返回true，否则返回false
 */
export function zstdCompress(src: string, archive: string, level?: number, nbThreads?: number): Promise<boolean> {
    return zstd.zstdCompress(src, archive, level ? level : 1, nbThreads ? nbThreads : 3).then(value => {
        return value === -1 ? false : true;
    });
}

/**
 * 解压文件
 * archive:需要解压的文件包路径
 * dest:解压文件存放的路径
 * boolean:返回值，解压成功则返回true，否则返回false
 */
export function zstdDecompress(archive: string, dest: string): Promise<boolean> {
    return zstd.zstdDecompress(archive, dest).then(value => {
        return value === -1 ? false : true;
    });
}