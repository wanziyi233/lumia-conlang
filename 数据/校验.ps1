# Lumia consistency validator.
# Run from repo root: powershell -File 数据/校验.ps1
# Exit code: 0 = all pass, 1 = some fail.
$ErrorActionPreference = 'Stop'
$script:pass = 0
$script:fail = 0
function OK($name)  { $script:pass++; Write-Output ("  [PASS] " + $name) }
function BAD($name) { $script:fail++; Write-Output ("  [FAIL] " + $name) }

$SJ = "$([char]0x6570)$([char]0x636E)"   # data
$CD = "$([char]0x8BCD)$([char]0x5178)"   # dict
$root = if ($PSScriptRoot) { Split-Path -Parent $PSScriptRoot } else { (Get-Location).Path }
$jsonPath   = Join-Path (Join-Path $root $SJ) 'lumia.json'
$dictMd     = Join-Path (Join-Path $root $CD) ($CD + '.md')
$dataReadme = Join-Path (Join-Path $root $SJ) 'README.md'
$dictHtml   = Join-Path $root ($CD + '.html')

Write-Output "== Lumia consistency check =="
Write-Output ("root: " + $root)

# 1. JSON parse
$raw = $null
try {
    $raw = [System.IO.File]::ReadAllText($jsonPath)
    $j = $raw | ConvertFrom-Json
    OK "lumia.json parses"
} catch {
    BAD ("lumia.json parse error: " + $_.Exception.Message)
    Write-Output ("== RESULT: PASS " + $script:pass + " / FAIL " + $script:fail + " ==")
    exit 1
}

$lex   = @($j.lexicon)
$words = @($lex | ForEach-Object { $_.w })

# 2. core word count
if ($j.meta.coreWordCount -eq $lex.Count) { OK ("coreWordCount(" + $j.meta.coreWordCount + ") == lexicon(" + $lex.Count + ")") }
else { BAD ("coreWordCount(" + $j.meta.coreWordCount + ") != lexicon(" + $lex.Count + ")") }

# 3. ids continuous & unique
$uniq = @($lex | ForEach-Object { [int]$_.id } | Sort-Object -Unique)
$okIds = ($uniq.Count -eq $lex.Count)
if ($okIds) {
    for ($i = 0; $i -lt $lex.Count; $i++) { if ($uniq[$i] -ne ($i + 1)) { $okIds = $false; break } }
}
if ($okIds) { OK ("ids continuous 1.." + $lex.Count + " and unique") }
else { BAD "ids not continuous or not unique" }

# 4. words unique
$dupes = @($words | Group-Object | Where-Object { $_.Count -gt 1 })
if ($dupes.Count -eq 0) { OK "words unique" }
else { BAD ("duplicate words: " + (($dupes | ForEach-Object { $_.Name }) -join ', ')) }

# 5. categories valid
$validCats = @('func', 'astro', 'num', 'base')
$badCat = @($lex | Where-Object { $validCats -notcontains $_.cat })
if ($badCat.Count -eq 0) { OK "cat values valid" }
else { BAD ("bad cat: " + (($badCat | ForEach-Object { "$($_.w):$($_.cat)" }) -join ', ')) }

# 6. no long mark in lexicon IPA
$longIpa = @($lex | Where-Object { $_.ipa -match [string][char]0x02D0 })
if ($longIpa.Count -eq 0) { OK "lexicon IPA has no length mark" }
else { BAD ("length mark in IPA of: " + (($longIpa | ForEach-Object { $_.w }) -join ', ')) }

# 7. phonology basics
if ($j.phonology.vowels.Count -eq 5) { OK "vowels == 5" } else { BAD ("vowels != 5 (" + $j.phonology.vowels.Count + ")") }
if ($j.phonology.consonants.Count -eq 16) { OK "consonants == 16" } else { BAD ("consonants != 16 (" + $j.phonology.consonants.Count + ")") }

# 8. numerals structure
if (@($j.numerals.digits).Count -eq 10) { OK "digits 0-9 == 10" } else { BAD "digits 0-9 != 10" }
if (@($j.numerals.powers).Count -eq 3) { OK "powers 10/100/1000 == 3" } else { BAD "powers != 3" }

# 9. glyph recipes coverage
$contentWords = @($lex | Where-Object { $_.cat -ne 'num' } | ForEach-Object { $_.w })
$recipes = @($j.script.glyphRecipes | ForEach-Object { $_.w })
$missing = @($contentWords | Where-Object { $recipes -notcontains $_ })
if ($missing.Count -eq 0) { OK "every content word has a glyph recipe" }
else { BAD ("missing recipes: " + ($missing -join ', ')) }
$orphans = @($recipes | Where-Object { ($words -notcontains $_) -and ($_ -ne 'Satuna') })
if ($orphans.Count -eq 0) { OK "no orphan glyph recipes" }
else { BAD ("orphan recipes: " + ($orphans -join ', ')) }

# 10. dictionary.md word set alignment
try {
    $mdLines = Get-Content -Encoding UTF8 $dictMd
    $mdWords = @()
    foreach ($ln in $mdLines) {
        $m = [regex]::Match($ln, '^\|\s*\d+\s*\|\s*(\S+)\s*\|')
        if ($m.Success) { $mdWords += $m.Groups[1].Value }
    }
    $mdSet = @($mdWords | Sort-Object -Unique)
    $jsonSet = @($words | Sort-Object -Unique)
    $onlyMd = @($mdSet | Where-Object { $jsonSet -notcontains $_ })
    $onlyJson = @($jsonSet | Where-Object { $mdSet -notcontains $_ })
    if ($onlyMd.Count -eq 0 -and $onlyJson.Count -eq 0) { OK ("dict.md words match JSON exactly (" + $jsonSet.Count + " words)") }
    else {
        BAD "dict.md vs JSON word mismatch"
        if ($onlyJson.Count) { Write-Output ("    only in JSON: " + ($onlyJson -join ', ')) }
        if ($onlyMd.Count)  { Write-Output ("    only in dict.md: " + ($onlyMd -join ', ')) }
    }
} catch { BAD ("dict.md check error: " + $_.Exception.Message) }

# 11. version consistency
try {
    $dr = [System.IO.File]::ReadAllText($dataReadme)
    if ($dr -match [regex]::Escape($j.meta.version)) { OK ("data/README.md has version " + $j.meta.version) }
    else { BAD ("data/README.md missing version " + $j.meta.version) }
} catch { BAD "cannot read data/README.md" }

# 12. full-library scan
$scan = Get-ChildItem -Path $root -Recurse -File | Where-Object { $_.Extension -in '.md', '.json', '.svg', '.html' }
$longHits = @(); $greetHits = @(); $panHits = @()
foreach ($f in $scan) {
    $c = [System.IO.File]::ReadAllText($f.FullName)
    if ($c.Contains([string][char]0x02D0)) { $longHits += $f.Name }
    if ($c.Contains('o mi tu!')) { $greetHits += $f.Name }
    if ($c.Contains('paneta ta')) { $panHits += $f.Name }
}
if ($longHits.Count -eq 0) { OK "no length mark in whole repo" } else { BAD ("length mark still in: " + ($longHits -join ', ')) }
if ($greetHits.Count -eq 0) { OK "no legacy greeting o mi tu!" } else { BAD ("legacy greeting still in: " + ($greetHits -join ', ')) }
if ($panHits.Count -eq 0) { OK "no legacy paneta ta" } else { BAD ("legacy paneta ta still in: " + ($panHits -join ', ')) }

# 13. dictionary html freshness (WARN only: dict.html is a derived artifact)
if (Test-Path $dictHtml) {
    if ((Get-Item $dictHtml).LastWriteTime -ge (Get-Item $jsonPath).LastWriteTime) { OK "dict.html not older than lumia.json" }
    else { Write-Output "  [WARN] dict.html older than lumia.json; run data/gen-dict.ps1" }
} else { Write-Output "  [WARN] dict.html missing; run data/gen-dict.ps1" }

Write-Output ""
Write-Output ("== RESULT: PASS " + $script:pass + " / FAIL " + $script:fail + " ==")
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
