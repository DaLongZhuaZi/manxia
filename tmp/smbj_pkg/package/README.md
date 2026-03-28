# SMBJ

## Introduction

>SMBJ is used to share files between computers. It supports security protection, and allows users to access shared directories, open files, and read and write files.


## How to Install
```shell
ohpm install @ohos/smbj 
```
For details about the OpenHarmony ohpm environment configuration, see [OpenHarmony HAR](https://gitcode.com/openharmony-tpc/docs/blob/master/OpenHarmony_har_usage.en.md).


## How to Use

### Importing SMB2
   ```
   // One:
   import { SMB2} from '@ohos/smbj'
   
   // Two:
   let client = new SMB2(
      {
        share: '\\\\10.50.40.30\\test_smbj',
        domain:'DOMAIN',
        username: 'Administrator',
        password: 'pass123',
        clientIP:'10.50.40.52'
      }
    )
    // Three:
     client.exists(check, function (err, exit) {
            if (err) {
              console.log('smb erro:' + err.message)
              throw err;

            }
     prompt.showToast ({message:"Whether the folder or file exists"+exit,duration:5000})
   ```
## Available APIs  
1. Checks whether a file or folder exists.
   ```
    public exists(path, callback)
   ```
2. Creates a folder.
   ```
   public mkdir(path, callback)
   ```
3. Reads a folder.
   ```
   readdir(path, callback)
   ```
4. Reads the file content.
   ```
   public readFile(filename: string, options?: { encoding: 'UTF-8' }, callback?: any)
   ```
5. Renames a file or folder.
   ```
   public rename(oldPath, newPath, callback)
   ```
6. Writes a file.
   ```
   public writeFile(filename, data, encoding?: string, callback?: any)
   ```
7. Deletes a folder.
   ```
   public rmdir(path, callback) 
   ```
8. Deletes a file.
   ```
   public unlink(path, callback) 
   ```
9. Performs resumable file upload.
   ```
   public sendFile(filename, data, callback) 
   ```

## About obfuscation
- Code obfuscation, please see[Code Obfuscation](https://docs.openharmony.cn/pages/v5.0/zh-cn/application-dev/arkts-utils/source-obfuscation.md)
- If you want the smbj library not to be obfuscated during code obfuscation, you need to add corresponding exclusion rules in the obfuscation rule configuration file obfuscation-rules.txt：
```
-keep
./oh_modules/@ohos/smbj
```

## Constraints

This project has been verified in the following versions:

- DevEco Studio: 4.1 Canary (4.1.3.317)

- OpenHarmony SDK: API 11 (4.1.0.36)

## Directory Structure
````
|---- smbj
    |---- entry
    |     |---- pages       # Sample code      
    |---- library              # Library
    |     |---- api         # Available APIs
    |     |---- crypto      # Encryption           
    |     |---- crypto      # Request message body
    |     |---- ntlm        # identity authentication
    |     |---- structures  # request/ response struct
    |     |---- tools       # socket processing
    |     |---- README.md  # Readme
    |     |---- README_zh.md  # Readme
````

## How to Contribute
If you find any problem when using the project, submit an [issue](https://gitcode.com/openharmony-tpc/openharmony_tpc_samples/issues) or a [PR](https://gitcode.com/openharmony-tpc/openharmony_tpc_samples/pulls).

## License
This project is licensed under [MIT License](https://gitcode.com/openharmony-tpc/openharmony_tpc_samples/blob/master/smbj/LICENSE).
