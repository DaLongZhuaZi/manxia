Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = [System.IO.Compression.ZipFile]::OpenRead("f:\DevEcoStudioProject\manxia\entry\build\default\outputs\default\entry-default-unsigned.hap")

Write-Host "=== C/C++ Libs (.so) ==="
$c_libs = $zip.Entries | Where-Object { $_.FullName -like "libs/*.so" }
$c_libs_sum = ($c_libs | Measure-Object -Property Length -Sum).Sum
Write-Host "Total Size: $c_libs_sum bytes"
$c_libs | Select-Object FullName, Length | Format-Table -AutoSize

Write-Host "=== ArkTS / JS Bytecode (.abc) ==="
$abc_files = $zip.Entries | Where-Object { $_.FullName -like "*.abc" }
$abc_sum = ($abc_files | Measure-Object -Property Length -Sum).Sum
Write-Host "Total Size: $abc_sum bytes"
$abc_files | Select-Object FullName, Length | Format-Table -AutoSize

Write-Host "=== HTML files in rawfile ==="
$html_files = $zip.Entries | Where-Object { $_.FullName -like "resources/rawfile/*.html" }
$html_sum = ($html_files | Measure-Object -Property Length -Sum).Sum
Write-Host "Total Size: $html_sum bytes"
$html_files | Select-Object FullName, Length | Format-Table -AutoSize

Write-Host "=== JS files in rawfile ==="
$js_files = $zip.Entries | Where-Object { $_.FullName -like "resources/rawfile/*.js" }
$js_sum = ($js_files | Measure-Object -Property Length -Sum).Sum
Write-Host "Total Size: $js_sum bytes"
$js_files | Select-Object FullName, Length | Format-Table -AutoSize

$zip.Dispose()
