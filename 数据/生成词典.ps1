# Generate the searchable dictionary (dict.html) from data/lumia.json.
# Single source of truth: lumia.json. Run from repo root: powershell -File 数据/生成词典.ps1
$ErrorActionPreference = 'Stop'
$SJ = "$([char]0x6570)$([char]0x636E)"   # data folder (shu ju)
$CD = "$([char]0x8BCD)$([char]0x5178)"   # dictionary (ci dian)
$root = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
$jsonPath = Join-Path (Join-Path $root $SJ) 'lumia.json'
$tplPath  = Join-Path (Join-Path $root $SJ) 'dict-template.html'
$outPath  = Join-Path $root ($CD + '.html')

$j = [System.IO.File]::ReadAllText($jsonPath) | ConvertFrom-Json
$compact = $j | ConvertTo-Json -Depth 20 -Compress
$tpl = [System.IO.File]::ReadAllText($tplPath)
$html = $tpl.Replace('__DATA__', $compact)
[System.IO.File]::WriteAllText($outPath, $html, (New-Object System.Text.UTF8Encoding $false))
Write-Output ("OK: generated " + ($CD + '.html') + " with " + $j.lexicon.Count + " words")
