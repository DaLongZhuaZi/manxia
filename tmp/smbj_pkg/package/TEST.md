# smbj单元测试用例

该测试用例基于OpenHarmony系统下，导出的接口进行单元测试

单元测试用例覆盖情况

|                                     接口名                                     |是否通过	|备注|
|:---------------------------------------------------------------------------:|:---:|:---:|
|                           exists(path, callback)                            |    pass        |       |
|                            mkdir(path, callback)                            |pass   |        |
|                           readdir(path, callback)                           |pass   |        |
| readFile(filename: string, options?: { encoding: 'UTF-8' }, callback?: any) |pass   |        |
|                     rename(oldPath, newPath, callback)                      |pass   |        |
|                           writeFile(filename, data, encoding?: string, callback?: any)                           |pass   |        |
|                     rmdir(path, callback)                     |pass  |     |
|                     unlink(path, callback)                    |   pass  |          |
|                             close()                            | pass |  |
|
