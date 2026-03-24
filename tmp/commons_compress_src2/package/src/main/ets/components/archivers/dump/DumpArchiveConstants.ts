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
import { int } from '../../util/CustomTypings'

export default class DumpArchiveConstants {
    public static TP_SIZE: int = 1024;
    public static NTREC: int = 10;
    public static HIGH_DENSITY_NTREC: int = 32;
    public static OFS_MAGIC: int = 60011;
    public static NFS_MAGIC: int = 60012;
    public static FS_UFS2_MAGIC: int = 0x19540119;
    public static CHECKSUM: int = 84446;
    public static LBLSIZE: int = 16;
    public static NAMELEN: int = 64;

    private constructor() {
    }
}
