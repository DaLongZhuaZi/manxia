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
import NullPointerException from '../util/NullPointerException';
import Long from "./long/index";
import fs from '@ohos.file.fs';

enum PathStatus { INVALID, CHECKED }

export default class File {
    private path: string;
    private status: PathStatus = null;

    isInvalid(): boolean {
        let s: PathStatus = this.status;
        if (s == null) {
            s = (this.path.indexOf('\u0000') < 0) ? PathStatus.CHECKED
                                                  : PathStatus.INVALID;
            this.status = s;
        }
        return s == PathStatus.INVALID;
    }

    private prefixLength: number = 0;

    getPrefixLength(): number {
        return this.prefixLength;
    }

    public static separatorChar: number = 47;
    public static separator: string = '/';
    public static pathSeparatorChar: number = 47;
    public static pathSeparator: string = '/';

    constructor(parent: string, child: string) {
        if (parent == null || parent == '') {
            throw new NullPointerException();
        }
        if (child == null) {
            throw new NullPointerException();
        }
        if (!(parent.substring(parent.length - 1, parent.length) == File.separator)) {
            parent = parent + File.separator;
        }
        if (!(child == '') && child.substring(0, 1) == File.separator) {
            child = child.substring(1, child.length);
        }
        this.path = parent + child;
        this.prefixLength = this.initPrefixLength(this.path);
    }

    //计算路径中前缀字符串的长度
    public initPrefixLength(pathname: string): number {
        if (pathname.length == 0) return 0;
        //如果以/开头则返回1，否则返回0
        return (pathname.charAt(0) == File.separator) ? 1 : 0;
    }

    public getName(): string {
        let index: number = this.path.lastIndexOf(File.separator);
        if (index < this.prefixLength) return this.path.substring(this.prefixLength);
        return this.path.substring(index + 1);
    }

    public getParent(): string {
        let index: number = this.path.lastIndexOf(File.separator);
        if (index < this.prefixLength) {
            if ((this.prefixLength > 0) && (this.path.length > this.prefixLength))
            return this.path.substring(0, this.prefixLength);
            return null;
        }
        return this.path.substring(0, index);
    }

    public getParentFile(): File {
        let p: string = this.getParent();
        if (p == null) return null;
        return new File(p, '');
    }

    public getPath(): string {
        return this.path;
    }

    public getAbsolutePath(): string {
        return this.path;
    }

    public isDirectory(): boolean {
        let stat = fs.statSync(this.path);
        return stat.isDirectory();
    }

    public isFile(): boolean {
        let stat = fs.statSync(this.path);
        return stat.isFile();
    }

    public length(): number {
        let stat = fs.statSync(this.path)
        return stat.size;
    }

    public lastModified(): Long {
        let stat = fs.statSync(this.path);
        let ctime: string = stat.ctime + '000';
        return Long.fromString(ctime);
    }

    public getUid(): number {
        let stat = fs.statSync(this.path);
        return stat.uid;
    }

    public getGid(): number {
        let stat = fs.statSync(this.path);
        return stat.gid;
    }
}