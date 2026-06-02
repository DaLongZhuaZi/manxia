$base = "F:\DevEcoStudioProject\manxia\entry\src\main\ets\"
$files = Get-ChildItem -Path $base -Recurse -Filter "*.ets"
$count = 0

foreach ($file in $files) {
    if ($file.Name -eq "SafeUtils.ets") { continue }
    
    $lines = Get-Content $file.FullName -Encoding UTF8
    $modified = $false
    $newLines = @()
    
    foreach ($line in $lines) {
        $newLine = $line
        
        if ($newLine -match 'JSON\.parse\(') {
            $idx = $newLine.IndexOf('JSON.parse')
            if ($idx -lt 0) {
                # This handles case where match was found but indexof didn't, usually due to casing, but JSON.parse is exact
            } else {
                $postParse = $newLine.Substring($idx)
                
                if ($postParse -match 'as\s+.*?(?:\[\]|Array<)') {
                    $newLine = $newLine -replace 'JSON\.parse\(', 'SafeUtils.parseArr('
                } elseif ($postParse -match 'as\s+.*?(?:Record<|ESObject|Object|Map<|Set<)') {
                    $newLine = $newLine -replace 'JSON\.parse\(', 'SafeUtils.parseObj('
                } elseif ($postParse -match 'as\s+string(?!\[|>)') {
                    $newLine = $newLine -replace 'JSON\.parse\(', 'SafeUtils.parseStr('
                } elseif ($postParse -match 'as\s+number') {
                    $newLine = $newLine -replace 'JSON\.parse\(', 'SafeUtils.parseNum('
                } elseif ($postParse -match 'as\s+boolean') {
                    $newLine = $newLine -replace 'JSON\.parse\(', 'SafeUtils.parseBool('
                } elseif ($postParse -match 'as\s+[A-Z]') {
                    $newLine = $newLine -replace 'JSON\.parse\(', 'SafeUtils.parseObj('
                } elseif ($postParse -match 'as\s+T') {
                    $newLine = $newLine -replace 'JSON\.parse\(', 'SafeUtils.parseObj('
                } else {
                    $newLine = $newLine -replace 'JSON\.parse\(', 'SafeUtils.parseOptional('
                }
            }
        }
        
        if ($newLine -cne $line) {
            $modified = $true
        }
        $newLines += $newLine
    }
    
    if ($modified) {
        $count++
        $content = $newLines -join "`r`n"
        
        if ($content -notmatch "import \{ SafeUtils \}") {
            $relativePath = $file.FullName.Substring($base.Length)
            $slashCount = ($relativePath -split "\\").Count - 1
            if ($slashCount -eq 0) {
                $importPath = "./Utils/SafeUtils"
            } else {
                $up = "../" * $slashCount
                $importPath = "${up}Utils/SafeUtils"
            }
            $importStr = "import { SafeUtils } from '$importPath';`r`n"
            $content = $importStr + $content
        }
        
        $content | Set-Content $file.FullName -Encoding UTF8 -NoNewline
    }
}
Write-Host "Processed $count files."
