# 星座图工具 —— 数据生成器
# 从 数据/lumia.json 生成 工具/星座数据.js，供 工具/星座图生成器.html 使用。
# 运行： powershell -File 数据/生成星座图.ps1
#
# 遵循本项目「数据是唯一权威源」原则：字形几何与排布参数全部来自 lumia.json，
# 工具页只是消费者。改完 lumia.json 后重跑本脚本即可。
#
# 本文件可执行代码保持纯 ASCII（中文一律用 Unicode 码点拼出），
# 详见 CONTRIBUTING.md「编码注意」。
$ErrorActionPreference = 'Stop'

$SJ   = "$([char]0x6570)$([char]0x636E)"                                        # 数据
$WZ   = "$([char]0x6587)$([char]0x5B57)"                                        # 文字
$GJ   = "$([char]0x5DE5)$([char]0x5177)"                                        # 工具
$JQTB = "$([char]0x661F)$([char]0x5EA7)$([char]0x6570)$([char]0x636E)"          # 星座数据

$root = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
$jsonPath = Join-Path (Join-Path $root $SJ) 'lumia.json'
$outDir   = Join-Path $root $GJ
$outPath  = Join-Path $outDir ($JQTB + '.js')

if (-not (Test-Path $jsonPath)) { Write-Error "cannot find lumia.json"; exit 1 }
if (-not (Test-Path $outDir))   { New-Item -ItemType Directory -Path $outDir | Out-Null }

$j = [System.IO.File]::ReadAllText($jsonPath) | ConvertFrom-Json

# 词表：小写词形 -> {cat, pos, zh}
$words = [ordered]@{}
foreach ($e in $j.lexicon) { $words[[string]$e.w] = [ordered]@{ cat = $e.cat; pos = $e.pos; zh = $e.zh } }

# 专名：小写 -> {w, zh}
$pn = [ordered]@{}
foreach ($p in $j.properNames) { $pn[([string]$p.w).ToLower()] = [ordered]@{ w = $p.w; zh = $p.zh } }

# 星座体渲染需要的样式类（字形自带的 .s/.d/.v 在 glyphs.css 里）。
# 全部来自数据库的 script.constellation.css —— 不在此处硬编码，
# 否则「单发 lumia.json 就能画出全部图形」这句话对星座体就不成立了。
# 注意：**不要**先把该表达式赋给一个中间变量再放进 payload ——
# Windows PowerShell 5.1 下 `$x = [string]$j.script.constellation.css` 会得到空串
#（同一表达式直接内联却正常），原因未查明，故一律内联。

$payload = [ordered]@{
    version       = $j.meta.version
    words         = $words
    properNames   = $pn
    constellation = $j.script.constellation
    track         = $j.script.track
    glyphs        = $j.script.glyphs
    digits        = $j.numerals.digits
    powers        = $j.numerals.powers
    consonants    = $j.phonology.consonants
    extraCss      = [string]$j.script.constellation.css
}

$json = $payload | ConvertTo-Json -Depth 100 -Compress
$text = '/* ' + 'generated from ' + $SJ + '/lumia.json by ' + $SJ + '/gen-constellation.ps1 -- do not edit by hand */' + "`n" +
        'globalThis.LUMIA = ' + $json + ';' + "`n"

[System.IO.File]::WriteAllText($outPath, $text, (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("OK: generated " + $JQTB + ".js from lumia.json v" + $j.meta.version + " (" + $words.Count + " words, " + @($j.script.glyphs.word.PSObject.Properties).Count + " glyphs)")
