@ECHO OFF
SETLOCAL

PUSHD "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0build_libdatachannel_ohos.ps1" %*
SET EXIT_CODE=%ERRORLEVEL%
POPD

EXIT /B %EXIT_CODE%
