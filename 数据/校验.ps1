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
$pnWords = @($j.properNames | ForEach-Object { $_.w })
$orphans = @($recipes | Where-Object { ($words -notcontains $_) -and ($pnWords -notcontains $_) })
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
$longHits = @(); $greetHits = @(); $panHits = @(); $numHits = @()
foreach ($f in $scan) {
    $c = [System.IO.File]::ReadAllText($f.FullName)
    if ($c.Contains([string][char]0x02D0)) { $longHits += $f.Name }
    if ($c.Contains('o mi tu!')) { $greetHits += $f.Name }
    if ($c.Contains('paneta ta')) { $panHits += $f.Name }
    if ($c.Contains('e luna dua')) { $numHits += $f.Name }
}
if ($longHits.Count -eq 0) { OK "no length mark in whole repo" } else { BAD ("length mark still in: " + ($longHits -join ', ')) }
if ($greetHits.Count -eq 0) { OK "no legacy greeting o mi tu!" } else { BAD ("legacy greeting still in: " + ($greetHits -join ', ')) }
if ($panHits.Count -eq 0) { OK "no legacy paneta ta" } else { BAD ("legacy paneta ta still in: " + ($panHits -join ', ')) }
if ($numHits.Count -eq 0) { OK "no legacy postposed numeral (luna dua)" } else { BAD ("postposed numeral still in: " + ($numHits -join ', ')) }

# 13. dictionary html freshness (WARN only: dict.html is a derived artifact)
if (Test-Path $dictHtml) {
    if ((Get-Item $dictHtml).LastWriteTime -ge (Get-Item $jsonPath).LastWriteTime) { OK "dict.html not older than lumia.json" }
    else { Write-Output "  [WARN] dict.html older than lumia.json; run data/gen-dict.ps1" }
} else { Write-Output "  [WARN] dict.html missing; run data/gen-dict.ps1" }

# 14. constellation section completeness
$const = $j.script.constellation
if ($null -eq $const) {
    BAD "script.constellation missing"
} else {
    $needConst = @('name','spec','example','unit','nodeScale','halo','closure','interiorAngleTarget','backtrackLimit','spatialAllocation','interSentence')
    $haveConst = @($const.PSObject.Properties.Name)
    $goneConst = @($needConst | Where-Object { $haveConst -notcontains $_ })
    if ($goneConst.Count -eq 0) { OK ("constellation has all " + $needConst.Count + " keys") }
    else { BAD ("constellation missing keys: " + ($goneConst -join ', ')) }
}

# 15. constellation referenced files exist
$constSpecPath = $null
try {
    $sep = [IO.Path]::DirectorySeparatorChar
    $constSpecPath = Join-Path $root ($const.spec -replace '/', $sep)
    $constExPath   = Join-Path $root ($const.example -replace '/', $sep)
    $missRef = @()
    if (-not (Test-Path $constSpecPath)) { $missRef += $const.spec }
    if (-not (Test-Path $constExPath))   { $missRef += $const.example }
    if ($missRef.Count -eq 0) { OK "constellation spec/example files exist" }
    else { BAD ("constellation references missing: " + ($missRef -join ', ')) }
} catch { BAD ("constellation file check error: " + $_.Exception.Message) }

# 16. constellation params agree with the spec document
#     Chinese anchors are written as \uXXXX escapes so this file stays pure ASCII.
if ($constSpecPath -and (Test-Path $constSpecPath)) {
    try {
        $specText = [System.IO.File]::ReadAllText($constSpecPath)
        $MS = '\u4E3B\u661F'   # main star
        $CS = '\u4F34\u661F'   # companion star
        $anchors = @(
            @{ n = 'nodeScale.main';      p = $MS + '\*{0,2}\s*\|\s*[^\r\n|]*\|\s*' + [regex]::Escape([string]$const.nodeScale.main) },
            @{ n = 'nodeScale.companion'; p = $CS + '\*{0,2}\s*\|\s*[^\r\n|]*\|\s*' + [regex]::Escape([string]$const.nodeScale.companion) },
            @{ n = 'halo.main';           p = $MS + '\s*\|\s*\*{0,2}' + [string]$const.halo.main + '\*{0,2}\s*\|' },
            @{ n = 'halo.companion';      p = $CS + '\s*\|\s*\*{0,2}' + [string]$const.halo.companion + '\*{0,2}\s*\|' },
            @{ n = 'closure.maxWords';    p = '\u2264\s*' + [string]$const.closure.maxWords + '\s*\u8BCD' },
            @{ n = 'interiorAngleTarget'; p = [string]($const.interiorAngleTarget[0]) + '[\u2013-]' + [string]($const.interiorAngleTarget[1]) },
            @{ n = 'backtrackLimit';      p = [string]$const.backtrackLimit + 'px' },
            @{ n = 'cell.main';           p = $MS + '\s*\|\s*' + [string]$const.cell.main + '\s*\|' },
            @{ n = 'cell.companion';      p = $CS + '\s*\|\s*' + [string]$const.cell.companion + '\s*\|' },
            @{ n = 'cell.numeral';        p = '\u5B9E\u4E49\*{0,2}\s*\|\s*[^\r\n|]*\|\s*[^\r\n|]*\|\s*\*{0,2}' + [string]$const.cell.numeral },
            @{ n = 'cell.numeralAttached'; p = '\u6570\u503C\*{0,2}\s*\|\s*[^\r\n|]*\|\s*[^\r\n|]*\|\s*\*{0,2}' + [string]$const.cell.numeralAttached },
            @{ n = 'cell.syllable';       p = '\u6BCF\u8282\s*cell\s*\*{0,2}' + [string]$const.cell.syllable },
            @{ n = 'syllabary.chainGap';  p = [string]$const.attachments.syllabary.chainGap + 'px' },
            @{ n = 'numeral.bond.opacity'; p = '\u4E0D\u900F\u660E\u5EA6\s*\*{0,2}' + [regex]::Escape([string]$const.attachments.numeral.bond.opacity) },
            @{ n = 'clustering.thresholdWords'; p = '\u8D85\u8FC7\s*\*{0,2}' + [string]$const.clustering.thresholdWords + '\*{0,2}\s*\u8BCD' },
            @{ n = 'clustering.clusterGap'; p = '\u5B50\u7C07\*{0,2}\u95F4\u8DDD\s*' + [string]$const.clustering.clusterGap + 'px' },
            @{ n = 'clustering.sentenceGap'; p = '\u53E5\u95F4\u7559\u767D\s*\u2265\s*\*{0,2}' + [string]$const.clustering.sentenceGap + 'px' },
            @{ n = 'numeral.branch.angle'; p = [string]$const.attachments.numeral.branch.angleMin + '[\u2013-]' + [string]$const.attachments.numeral.branch.angleMax + '\u00B0' }
        )
        $drift = @($anchors | Where-Object { $specText -notmatch $_.p })
        if ($drift.Count -eq 0) { OK ("constellation params match spec (" + $anchors.Count + " anchors)") }
        else { BAD ("constellation vs spec drift: " + (($drift | ForEach-Object { $_.n }) -join ', ')) }
    } catch { BAD ("constellation/spec compare error: " + $_.Exception.Message) }
} else { BAD "cannot compare constellation params: spec file unavailable" }

# 17. SVG sanity:
#     (a) every <use href="#id"> resolves in-file;
#     (b) no transform carries a thousands separator (PowerShell's {0:N1} writes
#         "translate(1,020.8,1,025.9)" -- invalid, and nodes collapse to origin);
#     (c) every <animate> that drives a geometry/paint attribute sits INSIDE a shape
#         element. A sibling <animate> has no target and fails silently: the stroke
#         stays hidden forever while everything else animates.
$svgFiles = @(Get-ChildItem -Path $root -Recurse -File -Filter *.svg)
$dangling = @(); $badTf = @(); $badSmil = @()
$shapeTags = @('path', 'circle', 'ellipse', 'rect', 'line', 'polyline', 'polygon')
$shapeAttrs = @('stroke-dashoffset', 'stroke-dasharray', 'd', 'points', 'cx', 'cy', 'r', 'rx', 'ry', 'x1', 'y1', 'x2', 'y2')
foreach ($f in $svgFiles) {
    $c = [System.IO.File]::ReadAllText($f.FullName)
    $ids  = @([regex]::Matches($c, 'id="([^"]+)"')     | ForEach-Object { $_.Groups[1].Value })
    $uses = @([regex]::Matches($c, 'href="#([^"]+)"')  | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    foreach ($u in $uses) {
        if ($ids -notcontains $u) { $dangling += ($f.Name + ' -> #' + $u) }
    }
    $bt = @([regex]::Matches($c, 'translate\([^)]*,[^)]*,'))
    if ($bt.Count -gt 0) { $badTf += ($f.Name + ' x' + $bt.Count) }
    if ($c -match '<animate') {
        try {
            $dx = New-Object System.Xml.XmlDocument
            $dx.LoadXml($c)
            foreach ($an in $dx.SelectNodes('//*[local-name()="animate" or local-name()="animateTransform"]')) {
                if ($an.GetAttribute('href') -or $an.GetAttribute('xlink:href')) { continue }
                $at = $an.GetAttribute('attributeName')
                $pn = $an.ParentNode.LocalName
                if (($shapeAttrs -contains $at) -and ($shapeTags -notcontains $pn)) {
                    $badSmil += ($f.Name + ': animate@' + $at + ' sibling of <' + $pn + '>')
                }
            }
        } catch { $badSmil += ($f.Name + ': SMIL parse error') }
    }
}
$svgIssues = @()
if ($dangling.Count -gt 0) { $svgIssues += ('dangling refs: ' + ($dangling -join '; ')) }
if ($badTf.Count -gt 0)    { $svgIssues += ('thousands separator in transform: ' + ($badTf -join '; ')) }
if ($badSmil.Count -gt 0)  { $svgIssues += ('untargeted SMIL: ' + ($badSmil -join '; ')) }
if ($svgIssues.Count -eq 0) { OK ("all SVG refs, transforms and SMIL targets well-formed (" + $svgFiles.Count + " files)") }
else { BAD ("SVG issues: " + ($svgIssues -join ' | ')) }

# 18. register overview chart declares the same cat counts as the lexicon
#     The chart is a generated artifact; its header comment records the counts it drew.
$WZD = "$([char]0x6587)$([char]0x5B57)"                                    # 文字
$OVN = "$([char]0x8BED)$([char]0x57DF)$([char]0x603B)$([char]0x89C8)"      # 语域总览
$ovPath = Join-Path (Join-Path $root $WZD) ($OVN + '.svg')
if (Test-Path $ovPath) {
    try {
        $ov = [System.IO.File]::ReadAllText($ovPath)
        $m = [regex]::Match($ov, 'counts:\s*astro=(\d+)\s+base=(\d+)\s+func=(\d+)\s+num=(\d+)')
        $ovBad = @()
        if (-not $m.Success) { $ovBad += 'counts comment missing' }
        else {
            $cats = @('astro', 'base', 'func', 'num')
            for ($ix = 0; $ix -lt 4; $ix++) {
                $declared = [int]$m.Groups[$ix + 1].Value
                $actual = @($lex | Where-Object { $_.cat -eq $cats[$ix] }).Count
                if ($declared -ne $actual) { $ovBad += ($cats[$ix] + " declared " + $declared + " but lexicon has " + $actual) }
            }
        }
        if ($ovBad.Count -eq 0) { OK "register overview chart matches lexicon counts" }
        else { BAD ("register overview chart stale: " + ($ovBad -join '; ')) }
    } catch { BAD ("register overview check error: " + $_.Exception.Message) }
} else { OK "register overview chart absent (skipped)" }

# 19. the three word glyph tables must cover the lexicon EXACTLY in both directions.
#     astro -> g_<w>, func -> f_<w>, base -> b_<w>. cat=num words carry no 星符 by design
#     (they are written with 星数), so they are excluded here -- see 20 for the digits.
$wdir = Join-Path $root "$([char]0x6587)$([char]0x5B57)"                                  # 文字
$TH = "$([char]0x5929)$([char]0x6587)$([char]0x8BCD)$([char]0x7B26)$([char]0x8868)"        # 天文词符表
$FU = "$([char]0x529F)$([char]0x80FD)$([char]0x8BCD)$([char]0x7B26)$([char]0x8868)"        # 功能词符表
$BA = "$([char]0x57FA)$([char]0x7840)$([char]0x8BCD)$([char]0x7B26)$([char]0x8868)"        # 基础词符表
$tblPath = @{ astro = (Join-Path $wdir ($TH + '.svg')); func = (Join-Path $wdir ($FU + '.svg')); base = (Join-Path $wdir ($BA + '.svg')) }
$tblPre  = @{ astro = 'g_'; func = 'f_'; base = 'b_' }
$coverBad = @(); $coverN = 0
foreach ($c in @('astro', 'func', 'base')) {
    if (-not (Test-Path $tblPath[$c])) { $coverBad += ($c + ' table missing'); continue }
    $txt  = [System.IO.File]::ReadAllText($tblPath[$c])
    $have = @([regex]::Matches($txt, 'id="([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    $want = @($lex | Where-Object { $_.cat -eq $c } | ForEach-Object { $tblPre[$c] + $_.w })
    $coverN += $want.Count
    $miss  = @($want | Where-Object { $have -notcontains $_ })
    $extra = @($have | Where-Object { $want -notcontains $_ })
    if ($miss.Count  -gt 0) { $coverBad += ($c + ' missing glyph: ' + ($miss -join ', ')) }
    if ($extra.Count -gt 0) { $coverBad += ($c + ' extra glyph: '  + ($extra -join ', ')) }
}
if ($coverBad.Count -eq 0) { OK ("glyph tables cover all " + $coverN + " non-numeral words exactly") }
else { BAD ("glyph table coverage: " + ($coverBad -join '; ')) }

# 20. the syllabary chart must draw exactly 16 consonants x 5 vowels = 80 cells,
#     using one base shape per consonant.
$SY = "$([char]0x97F3)$([char]0x8282)$([char]0x56FE)"                                      # 音节图
$syPath = Join-Path $wdir ($SY + '.svg')
$cv = $j.phonology.consonants.Count
$vv = $j.phonology.vowels.Count
if (Test-Path $syPath) {
    $sy = [System.IO.File]::ReadAllText($syPath)
    $syBad = @()
    $nc = @([regex]::Matches($sy, '<use\b')).Count
    $nb = @([regex]::Matches($sy, 'id="c\d+"') | ForEach-Object { $_.Value } | Sort-Object -Unique).Count
    if ($nc -ne ($cv * $vv)) { $syBad += ('cells ' + $nc + ' != ' + ($cv * $vv)) }
    if ($nb -ne $cv)         { $syBad += ('base shapes ' + $nb + ' != ' + $cv) }
    if ($syBad.Count -eq 0) { OK ("syllabary chart draws " + $cv + 'x' + $vv + ' = ' + ($cv * $vv) + " cells") }
    else { BAD ("syllabary chart: " + ($syBad -join '; ')) }
} else { BAD "syllabary chart missing" }

# 21. every Lumia token used in examples / phrases / weekdays must resolve to a
#     lexicon word or a registered proper name. A typo here renders as fluent-looking
#     nonsense and nothing else would catch it.
$known = @($words) + @($pnWords)
$unres = @()
$corpus = @()
foreach ($e in @($j.grammar.examples)) { $corpus += @{ s = $e.lumia; where = 'grammar.examples' } }
foreach ($e in @($j.phrases))          { $corpus += @{ s = $e.lumia; where = 'phrases' } }
foreach ($e in @($j.numerals.examples.PSObject.Properties)) { $corpus += @{ s = [string]$e.Value; where = 'numerals.examples' } }
foreach ($e in @($j.time.weekdays))    { $corpus += @{ s = $e.lumia; where = 'time.weekdays' } }
foreach ($e in $corpus) {
    $toks = @([regex]::Matches($e.s, '[A-Za-z]+') | ForEach-Object { $_.Value })
    $bad  = @($toks | Where-Object { $known -notcontains $_ })
    if ($bad.Count -gt 0) { $unres += ($e.where + ': ' + $e.s + ' -> ' + ($bad -join ', ')) }
}
if ($unres.Count -eq 0) { OK ("every word in examples/phrases/weekdays resolves (" + $corpus.Count + " strings)") }
else { BAD ("undefined words used: " + ($unres -join '; ')) }

# 22. numerals.examples must actually compute to their keys under the stated
#     composition rule. Two shapes occur: place value (X deka Y = X*10 + Y, biggest
#     place first) and power coefficient (deka kilo = 10 * 1000, where the smaller
#     power multiplies the bigger one). A power word that is followed by an equal or
#     bigger power acts as that coefficient; otherwise it is a place of its own.
$numVal = @{}
foreach ($d in $j.numerals.digits) { $numVal[[string]$d.w] = [int]$d.value }
foreach ($p in $j.numerals.powers) { $numVal[[string]$p.w] = [int]$p.value }
$powSet = @($j.numerals.powers | ForEach-Object { [string]$_.w })
$numBad = @(); $numN = 0
foreach ($prop in $j.numerals.examples.PSObject.Properties) {
    $numN++
    $want = [int]$prop.Name
    $toks = @([regex]::Matches([string]$prop.Value, '[A-Za-z]+') | ForEach-Object { $_.Value })
    $acc = 0; $pend = 0; $undef = $null
    for ($i = 0; $i -lt $toks.Count; $i++) {
        $t = $toks[$i]
        if (-not $numVal.ContainsKey($t)) { $undef = $t; break }
        $v = $numVal[$t]
        if ($powSet -contains $t) {
            $laterBig = $false
            for ($k = $i + 1; $k -lt $toks.Count; $k++) {
                $tk = $toks[$k]
                if (($powSet -contains $tk) -and ($numVal[$tk] -ge $v)) { $laterBig = $true; break }
            }
            if ($pend -eq 0) { $pend = 1 }
            if ($laterBig) { $pend = $pend * $v }
            else { $acc += $pend * $v; $pend = 0 }
        } else { $pend += $v }
    }
    if ($undef) { $numBad += ($prop.Name + ' uses undefined ' + $undef) }
    else {
        $acc += $pend
        if ($acc -ne $want) { $numBad += ($prop.Name + ' = ' + $prop.Value + ' computes to ' + $acc) }
    }
}
if ($numBad.Count -eq 0) { OK ("all " + $numN + " numeral examples compute correctly") }
else { BAD ("numeral arithmetic: " + ($numBad -join '; ')) }

# 23. README.md must carry the same version as the database (badge + footer).
try {
    $rd = [System.IO.File]::ReadAllText((Join-Path $root 'README.md'))
    $hits = @([regex]::Matches($rd, '([0-9]+\.[0-9]+\.[0-9]+)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $stale = @($hits | Where-Object { $_ -ne $j.meta.version })
    if ($stale.Count -eq 0 -and $hits.Count -gt 0) { OK ("README.md version matches " + $j.meta.version) }
    else { BAD ("README.md version drift: " + ($stale -join ', ') + " != " + $j.meta.version) }
} catch { BAD ("README.md version check error: " + $_.Exception.Message) }

# 24. every relative markdown link must resolve on disk.
$linkBad = @()
foreach ($f in @(Get-ChildItem -Path $root -Recurse -File -Filter *.md)) {
    $dir = Split-Path $f.FullName -Parent
    $c = [System.IO.File]::ReadAllText($f.FullName)
    foreach ($m in [regex]::Matches($c, '\]\(([^)#:]+?)\)')) {
        $t = $m.Groups[1].Value.Trim()
        if ($t -eq '' -or $t -match '^https?://') { continue }
        $p = Join-Path $dir ($t -replace '/', [IO.Path]::DirectorySeparatorChar)
        if (-not (Test-Path $p)) { $linkBad += ($f.Name + ' -> ' + $t) }
    }
}
if ($linkBad.Count -eq 0) { OK "all relative markdown links resolve" }
else { BAD ("broken relative links: " + (($linkBad | Sort-Object -Unique) -join '; ')) }

# 25. every tense/metaphor frame declared in the database must be documented in 语法.md.
$YF = "$([char]0x8BED)$([char]0x6CD5)"                                                      # 语法
$NONE = "$([char]0xFF08)$([char]0x65E0)$([char]0xFF09)"                                     # （无）
$gPath = Join-Path (Join-Path $root $YF) ($YF + '.md')
if (Test-Path $gPath) {
    $gt = [System.IO.File]::ReadAllText($gPath)
    $ung = @($j.grammar.tamMetaphor | Where-Object { $_.frame -ne $NONE } | Where-Object { $gt -notmatch [regex]::Escape($_.frame) } | ForEach-Object { $_.frame })
    if ($ung.Count -eq 0) { OK ("all tense/metaphor frames are documented in " + $YF + ".md") }
    else { BAD ("frames missing from " + $YF + ".md: " + ($ung -join ', ')) }
} else { BAD "grammar document missing" }

# 26. constellation examples: every sentence short enough to require closure MUST
#     actually carry a 闭合轨 (.close). An example that ignores the closure rule
#     teaches the wrong shape, and nothing else in the pipeline would notice.
#     Only files defining .halo count as real layouts (星座示例.svg is a prototype).
$maxW = [int]$j.script.constellation.closure.maxWords
$cloBad = @(); $cloN = 0
foreach ($f in @(Get-ChildItem -Path $wdir -File -Filter *.svg)) {
    $c = [System.IO.File]::ReadAllText($f.FullName)
    if ($c -notmatch 'class="halo"') { continue }
    $nClose = @([regex]::Matches($c, 'class="close"')).Count
    $short = 0
    foreach ($m in [regex]::Matches($c, '<text[^>]*class="cap"[^>]*>([^<]*)</text>')) {
        $n = @([regex]::Matches($m.Groups[1].Value, '[A-Za-z]+')).Count
        if ($n -gt 0 -and $n -le $maxW) { $short++ }
    }
    if ($short -eq 0) { continue }
    $cloN += $short
    if ($nClose -lt $short) { $cloBad += ($f.Name + ': ' + $short + ' short sentence(s), ' + $nClose + ' close path(s)') }
    elseif ($c -notmatch '\.close\{') { $cloBad += ($f.Name + ': .close used but never defined') }
}
if ($cloBad.Count -eq 0) { OK ("all " + $cloN + " short constellation sentences are closed") }
else { BAD ("missing closure track: " + ($cloBad -join '; ')) }

# 27. this validator's own executable code must stay pure ASCII, so it runs under any
#     console code page. Chinese may appear only in full-line comments; literal Chinese
#     strings are built with [char]0xNNNN. A stray literal renders as mojibake in the
#     report and can break parsing on a non-UTF8 host.
$selfPath = $PSCommandPath
if (-not $selfPath) { $selfPath = $MyInvocation.MyCommand.Path }
if ($selfPath -and (Test-Path $selfPath)) {
    $selfBad = @(); $ln = 0
    foreach ($line in [System.IO.File]::ReadAllLines($selfPath)) {
        $ln++
        $code = $line
        $h = $code.IndexOf('#')
        if ($h -ge 0) { $code = $code.Substring(0, $h) }
        if ($code -match '[^\x00-\x7F]') { $selfBad += ('line ' + $ln) }
    }
    if ($selfBad.Count -eq 0) { OK "validator executable code is pure ASCII" }
    else { BAD ("non-ASCII outside comments in the validator: " + ($selfBad -join ', ')) }
} else { OK "validator self-path unavailable (skipped)" }

# 28. no SVG arc may declare a radius smaller than half its chord. Per SVG 1.1 F.6.6 the
#     renderer then silently SCALES THE RADIUS UP, so two arcs that were written to differ
#     collapse onto each other -- the shape loses area while still looking plausible.
#     That is exactly how the luna glyph degenerated into a zero-area curve.
$selfArc = @(); $arcN = 0
$arity = @{ M = 2; L = 2; H = 1; V = 1; C = 6; S = 4; Q = 4; T = 2; A = 7 }
foreach ($f in $svgFiles) {
    $c = [System.IO.File]::ReadAllText($f.FullName)
    foreach ($dm in [regex]::Matches($c, '\sd="([^"]+)"')) {
        $toks = @([regex]::Matches($dm.Groups[1].Value, '[MmLlHhVvCcSsQqTtAaZz]|-?\d*\.?\d+') | ForEach-Object { $_.Value })
        $i = 0; $cx = 0.0; $cy = 0.0; $sx = 0.0; $sy = 0.0; $cmd = ''
        while ($i -lt $toks.Count) {
            if ($toks[$i] -match '^[A-Za-z]$') {
                $cmd = $toks[$i]; $i++
                if ($cmd -match '^[Zz]$') { $cx = $sx; $cy = $sy; continue }
            }
            if (-not $cmd) { $i++; continue }
            $up = $cmd.ToUpper(); $rel = ($cmd -ceq $cmd.ToLower())
            if (-not $arity.ContainsKey($up)) { $i++; continue }
            $n = $arity[$up]
            if (($i + $n) -gt $toks.Count) { break }
            if ($up -eq 'A') {
                $rx = [double]$toks[$i]; $x = [double]$toks[$i + 5]; $y = [double]$toks[$i + 6]
                $ex = $x; $ey = $y
                if ($rel) { $ex = $cx + $x; $ey = $cy + $y }
                $half = ([math]::Sqrt((($ex - $cx) * ($ex - $cx)) + (($ey - $cy) * ($ey - $cy)))) / 2
                $arcN++
                if ($half -gt ($rx + 0.01)) { $selfArc += ($f.Name + ' r=' + $rx + ' < half-chord ' + [math]::Round($half, 1)) }
                $cx = $ex; $cy = $ey
            }
            elseif ($up -eq 'H') {
                $x = [double]$toks[$i]
                if ($rel) { $cx = $cx + $x } else { $cx = $x }
            }
            elseif ($up -eq 'V') {
                $y = [double]$toks[$i]
                if ($rel) { $cy = $cy + $y } else { $cy = $y }
            }
            elseif ($up -eq 'M') {
                $x = [double]$toks[$i]; $y = [double]$toks[$i + 1]
                if ($rel) { $cx = $cx + $x; $cy = $cy + $y } else { $cx = $x; $cy = $y }
                $sx = $cx; $sy = $cy
            }
            else {
                $x = [double]$toks[$i + $n - 2]; $y = [double]$toks[$i + $n - 1]
                if ($rel) { $cx = $cx + $x; $cy = $cy + $y } else { $cx = $x; $cy = $y }
            }
            $i += $n
        }
    }
}
if ($selfArc.Count -eq 0) { OK ("no SVG arc needs silent radius scaling (" + $arcN + " arcs)") }
else { BAD ("degenerate arc (radius would be auto-scaled): " + (($selfArc | Sort-Object -Unique) -join '; ')) }

Write-Output ""
Write-Output ("== RESULT: PASS " + $script:pass + " / FAIL " + $script:fail + " ==")
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
