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
$dictHtml   = Join-Path (Join-Path $root "$([char]0x5DE5)$([char]0x5177)") ($CD + '.html')

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
$SYL = "$([char]0x97F3)$([char]0x8282)$([char]0x56FE)"                                      # 音节图
$syPath = Join-Path $wdir ($SYL + '.svg')
$cv = $j.phonology.consonants.Count
$vv = $j.phonology.vowels.Count
if (Test-Path $syPath) {
    $syText = [System.IO.File]::ReadAllText($syPath)
    $syBad = @()
    $nc = @([regex]::Matches($syText, '<use[^>]*href="#c\d+"')).Count
    $nb = @([regex]::Matches($syText, 'id="c\d+"') | ForEach-Object { $_.Value } | Sort-Object -Unique).Count
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
        $i = 0; $cx = 0.0; $cy = 0.0; $stX = 0.0; $stY = 0.0; $cmd = ''
        while ($i -lt $toks.Count) {
            if ($toks[$i] -match '^[A-Za-z]$') {
                $cmd = $toks[$i]; $i++
                if ($cmd -match '^[Zz]$') { $cx = $stX; $cy = $stY; continue }
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
                $stX = $cx; $stY = $cy
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

# 29. script.glyphs is the single source of truth for glyph GEOMETRY. Every fragment
#     stored there must appear VERBATIM in the SVG asset that draws it, and the assets
#     must not carry glyph bodies the database has never heard of. Without this the same
#     path silently drifts between copies -- which is how 星座示例.svg ended up with a
#     different radius for mi than every other file (found in the 0.14.0 audit).
$FT  = "$([char]0x7B26)$([char]0x8868)"                                                    # 符表
$DGT = "$([char]0x6570)$([char]0x5B57)$([char]0x7B26)$([char]0x8868)"                      # 数字符表
$gl = $j.script.glyphs
$glPairs = @()
foreach ($w in @($lex | Where-Object { $_.cat -eq 'astro' } | ForEach-Object { $_.w })) { $glPairs += @{ prop = 'word';  key = $w; file = $TH;  id = ('g_' + $w) } }
foreach ($w in @($lex | Where-Object { $_.cat -eq 'func'  } | ForEach-Object { $_.w })) { $glPairs += @{ prop = 'word';  key = $w; file = $FU;  id = ('f_' + $w) } }
foreach ($w in @($lex | Where-Object { $_.cat -eq 'base'  } | ForEach-Object { $_.w })) { $glPairs += @{ prop = 'word';  key = $w; file = $BA;  id = ('b_' + $w) } }
$glPairs += @{ prop = 'word';  key = 'Satuna'; file = $FT;  id = 'g_satuna' }
foreach ($d in @($gl.digit.PSObject.Properties.Name))                                   { $glPairs += @{ prop = 'digit'; key = $d; file = $DGT; id = ('d' + $d) } }
foreach ($b in @($gl.syllabary.bases.PSObject.Properties.Name))                         { $glPairs += @{ prop = 'bases'; key = $b; file = $SYL; id = $b } }
$glPairs += @{ prop = 'coda'; key = 'coda'; file = $SYL; id = 'coda' }
foreach ($pr in @($j.script.primitives))                                                 { $glPairs += @{ prop = 'prim'; key = [string]$pr.lumia; file = $FT; id = ('prim_' + $pr.lumia) } }

$glBad = @(); $glN = 0
foreach ($p in $glPairs) {
    $dbVal = $null
    if ($p.prop -eq 'bases') { $dbVal = $gl.syllabary.bases.PSObject.Properties[$p.key].Value }
    elseif ($p.prop -eq 'coda') { $dbVal = $gl.syllabary.coda }
    elseif ($p.prop -eq 'prim') {
        $pr = @($j.script.primitives | Where-Object { [string]$_.lumia -eq $p.key }) | Select-Object -First 1
        if ($pr) { $dbVal = $pr.glyph }
    }
    else {
        $store = $gl.PSObject.Properties[$p.prop].Value
        $prop = $store.PSObject.Properties[$p.key]
        if ($prop) { $dbVal = $prop.Value }
    }
    if ($null -eq $dbVal) { $glBad += ('database missing ' + $p.prop + '/' + $p.key); continue }
    $asset = Join-Path $wdir ($p.file + '.svg')
    if (-not (Test-Path $asset)) { $glBad += ('asset missing ' + $p.file); continue }
    $c = [System.IO.File]::ReadAllText($asset)
    $m = [regex]::Match($c, '<g id="' + [regex]::Escape($p.id) + '">(.*?)</g>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if (-not $m.Success) { $glBad += ('asset missing #' + $p.id); continue }
    if ($m.Groups[1].Value.Trim() -ne $dbVal) { $glBad += ('drift in ' + $p.id) }
    $glN++
    # 语域总览.svg 自带一整套字形副本（g_*/f_*/b_*/d*）。它也必须是同一份几何——
    # 0.15.0 修 d0 时就漏了它，直到下一次审计才发现。
    if (($p.file -eq $TH) -or ($p.file -eq $FU) -or ($p.file -eq $BA) -or ($p.file -eq $DGT)) {
        $ovPath = Join-Path $wdir ($OVN + '.svg')
        if (Test-Path $ovPath) {
            $ovc = [System.IO.File]::ReadAllText($ovPath)
            $ovm = [regex]::Match($ovc, '<g id="' + [regex]::Escape($p.id) + '">(.*?)</g>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
            if ($ovm.Success -and ($ovm.Groups[1].Value.Trim() -ne $dbVal)) { $glBad += ('drift in ' + $OVN + '.svg #' + $p.id) }
        }
    }
}
#     baseOrder must agree with the declared consonant inventory -- c0..c15 map onto it
#     positionally, and that mapping was previously only implicit.
$bo = @($gl.syllabary.baseOrder)
$co = @($j.phonology.consonants)
if ($bo.Count -ne $co.Count -or (Compare-Object $bo $co)) { $glBad += 'baseOrder != phonology.consonants' }
#     The css block is part of the same contract: the classes the database declares must be
#     byte-identical to the ones the assets use, otherwise a glyph drawn from the database
#     looks subtly different from the same glyph printed in the chart.
function GetCssRule($file, $cls) {
    $p = Join-Path $wdir $file
    if (-not (Test-Path $p)) { return $null }
    $c = [System.IO.File]::ReadAllText($p)
    $m = [regex]::Match($c, '\.' + $cls + '\{[^}]*\}')
    if ($m.Success) { return $m.Value }
    return $null
}
$dbS = ([regex]::Match($gl.css, '\.s\{[^}]*\}')).Value
$dbD = ([regex]::Match($gl.css, '\.d\{[^}]*\}')).Value
$dbV = ([regex]::Match($gl.css, '\.v\{[^}]*\}')).Value
$cssChecks = @(
    @{ f = ($TH + '.svg');  cls = 's'; want = $dbS },
    @{ f = ($FU + '.svg');  cls = 's'; want = $dbS },
    @{ f = ($BA + '.svg');  cls = 's'; want = $dbS },
    @{ f = ($DGT + '.svg'); cls = 's'; want = $dbS },
    @{ f = ($SYL + '.svg'); cls = 's'; want = $dbS },
    @{ f = ($TH + '.svg');  cls = 'd'; want = $dbD },
    @{ f = ($DGT + '.svg'); cls = 'd'; want = $dbD },
    @{ f = ($SYL + '.svg'); cls = 'v'; want = $dbV }
)
foreach ($cc in $cssChecks) {
    $got = GetCssRule $cc.f $cc.cls
    if ($null -eq $got) { $glBad += ('css .' + $cc.cls + ' missing in ' + $cc.f) }
    elseif ($got -ne $cc.want) { $glBad += ('css .' + $cc.cls + ' differs in ' + $cc.f) }
}

#     Box containment: every fragment must stay inside its declared canvas. Arc extrema MUST
#     be derived from the SVG endpoint -> centre parameterisation (spec F.6.5), never from the
#     literal coordinate numbers. That is exactly how vaka's ring poked ~8.7 units above its own
#     120 box while still looking perfectly plausible in the large charts.
function GetFragExtent($frag) {
    $xs = @(); $ys = @()
    $TWO = [Math]::PI * 2
    $add = { param($x, $y) $script:exs += $x; $script:eys += $y }
    foreach ($m in [regex]::Matches($frag, '<circle[^>]*cx="(-?[\d.]+)"[^>]*cy="(-?[\d.]+)"[^>]*r="([\d.]+)"')) {
        $x = [double]$m.Groups[1].Value; $y = [double]$m.Groups[2].Value; $p = [double]$m.Groups[3].Value + 2
        $xs += ($x - $p); $xs += ($x + $p); $ys += ($y - $p); $ys += ($y + $p)
    }
    foreach ($m in [regex]::Matches($frag, '<ellipse[^>]*cx="(-?[\d.]+)"[^>]*cy="(-?[\d.]+)"[^>]*rx="([\d.]+)"[^>]*ry="([\d.]+)"')) {
        $x = [double]$m.Groups[1].Value; $y = [double]$m.Groups[2].Value
        $a = [double]$m.Groups[3].Value + 5; $b = [double]$m.Groups[4].Value + 5
        $xs += ($x - $a); $xs += ($x + $a); $ys += ($y - $b); $ys += ($y + $b)
    }
    foreach ($dm in [regex]::Matches($frag, 'd="([^"]+)"')) {
        $toks = @([regex]::Matches($dm.Groups[1].Value, '[MmLlHhVvCcSsQqTtAaZz]|-?\d*\.?\d+') | ForEach-Object { $_.Value })
        $i = 0; $cx = 0.0; $cy = 0.0; $sx = 0.0; $sy = 0.0; $cmd = ''
        $ar = @{ M = 2; L = 2; H = 1; V = 1; C = 6; S = 4; Q = 4; T = 2; A = 7 }
        while ($i -lt $toks.Count) {
            if ($toks[$i] -match '^[A-Za-z]$') {
                $cmd = $toks[$i]; $i++
                if ($cmd -match '^[Zz]$') { $cx = $sx; $cy = $sy; continue }
            }
            if (-not $cmd) { $i++; continue }
            $up = $cmd.ToUpper(); $rel = ($cmd -ceq $cmd.ToLower())
            if (-not $ar.ContainsKey($up)) { $i++; continue }
            $n = $ar[$up]
            if (($i + $n) -gt $toks.Count) { break }
            if ($up -eq 'A') {
                $r0 = [double]$toks[$i]
                $fa = [int][double]$toks[$i + 3]; $fs = [int][double]$toks[$i + 4]
                $x = [double]$toks[$i + 5]; $y = [double]$toks[$i + 6]
                if ($rel) { $x += $cx; $y += $cy }
                $dd = [Math]::Sqrt((($x - $cx) * ($x - $cx)) + (($y - $cy) * ($y - $cy)))
                if ($dd -gt 0.0001) {
                    $r = $r0; if ($r -lt ($dd / 2)) { $r = $dd / 2 }
                    $h = [Math]::Sqrt([Math]::Max(0, ($r * $r) - (($dd / 2) * ($dd / 2))))
                    $x1p = ($cx - $x) / 2; $y1p = ($cy - $y) / 2
                    $f = 0.0; if (($dd / 2) -gt 0.0001) { $f = $h / ($dd / 2) }
                    $ox = $f * $y1p; $oy = $f * (-$x1p)
                    if ($fa -eq $fs) { $ox = -$ox; $oy = -$oy }
                    $ocx = $ox + (($cx + $x) / 2); $ocy = $oy + (($cy + $y) / 2)
                    $a1 = [Math]::Atan2($cy - $ocy, $cx - $ocx)
                    $dth = ([Math]::Atan2($y - $ocy, $x - $ocx) - $a1) % $TWO
                    if ($dth -lt 0) { $dth += $TWO }
                    if (($fs -eq 0) -and ($dth -gt 0)) { $dth -= $TWO }
                    if (($fs -eq 1) -and ($dth -lt 0)) { $dth += $TWO }
                    $qt = @(0.0, 1.5707963267948966, 3.1415926535897931, 4.7123889803846898)
                    foreach ($q in $qt) {
                        $t = ($q - $a1) % $TWO
                        if ($t -lt 0) { $t += $TWO }
                        $inside = $false
                        if ($dth -ge 0) { if ($t -le ($dth + 0.000001)) { $inside = $true } }
                        else { if (($TWO - $t) -le ((-$dth) + 0.000001)) { $inside = $true } }
                        if ($inside) {
                            $xs += ($ocx + $r * [Math]::Cos($q)); $ys += ($ocy + $r * [Math]::Sin($q))
                        }
                    }
                }
                $xs += $cx; $xs += $x; $ys += $cy; $ys += $y
                $cx = $x; $cy = $y
            }
            elseif ($up -eq 'H') {
                $x = [double]$toks[$i]; if ($rel) { $cx += $x } else { $cx = $x }
                $xs += $cx; $ys += $cy
            }
            elseif ($up -eq 'V') {
                $y = [double]$toks[$i]; if ($rel) { $cy += $y } else { $cy = $y }
                $xs += $cx; $ys += $cy
            }
            elseif ($up -eq 'M') {
                $x = [double]$toks[$i]; $y = [double]$toks[$i + 1]
                if ($rel) { $cx += $x; $cy += $y } else { $cx = $x; $cy = $y }
                $sx = $cx; $sy = $cy
                $xs += $cx; $ys += $cy
            }
            else {
                for ($k = 0; $k -lt $n; $k += 2) {
                    $x = [double]$toks[$i + $k]; $y = [double]$toks[$i + $k + 1]
                    if ($rel) { $xs += ($cx + $x); $ys += ($cy + $y) } else { $xs += $x; $ys += $y }
                }
                $x = [double]$toks[$i + $n - 2]; $y = [double]$toks[$i + $n - 1]
                if ($rel) { $cx += $x; $cy += $y } else { $cx = $x; $cy = $y }
            }
            $i += $n
        }
    }
    if ($xs.Count -eq 0) { return @{ minx = 0; miny = 0; maxx = 0; maxy = 0 } }
    return @{
        minx = ($xs | Measure-Object -Minimum).Minimum
        miny = ($ys | Measure-Object -Minimum).Minimum
        maxx = ($xs | Measure-Object -Maximum).Maximum
        maxy = ($ys | Measure-Object -Maximum).Maximum
    }
}
$boxChecks = @(
    @{ g = $gl.word; b = [double]$gl.box.word },
    @{ g = $gl.digit; b = [double]$gl.box.digit },
    @{ g = $gl.syllabary.bases; b = [double]$gl.box.syllable }
)
foreach ($bc in $boxChecks) {
    foreach ($k in @($bc.g.PSObject.Properties.Name)) {
        $e = GetFragExtent $bc.g.PSObject.Properties[$k].Value
        if (($e.minx -lt -0.5) -or ($e.miny -lt -0.5) -or ($e.maxx -gt ($bc.b + 0.5)) -or ($e.maxy -gt ($bc.b + 0.5))) {
            $glBad += ($k + ' escapes box ' + $bc.b + ' [' + [Math]::Round($e.minx, 1) + ',' + [Math]::Round($e.miny, 1) + ' .. ' + [Math]::Round($e.maxx, 1) + ',' + [Math]::Round($e.maxy, 1) + ']')
        }
    }
}
# 笔形基元也有画布（box.primitive），同样不能越界
foreach ($pr in @($j.script.primitives)) {
    if (-not $pr.glyph) { continue }
    $e = GetFragExtent $pr.glyph
    $pb = [double]$gl.box.primitive
    if (($e.minx -lt -0.5) -or ($e.miny -lt -0.5) -or ($e.maxx -gt ($pb + 0.5)) -or ($e.maxy -gt ($pb + 0.5))) {
        $glBad += ('primitive ' + $pr.lumia + ' escapes box ' + $pb)
    }
}
# 音节图每行的辅音标签必须与 baseOrder 同序——否则换两行也不会被发现
if (Test-Path (Join-Path $wdir ($SYL + '.svg'))) {
    $syt = [System.IO.File]::ReadAllText((Join-Path $wdir ($SYL + '.svg')))
    $labs = @([regex]::Matches($syt, '<text[^>]*class="l"[^>]*>([a-z])\s') | ForEach-Object { $_.Groups[1].Value })
    if ($labs.Count -ne $bo.Count) { $glBad += ('syllabary rows ' + $labs.Count + ' != baseOrder ' + $bo.Count) }
    elseif ((Compare-Object $labs $bo)) { $glBad += 'syllabary row labels != baseOrder' }
}
# 每个借词都必须带来源（词典.md 里有，数据库里也必须有）
$JIE = [string][char]0x501F                                                              # 借
foreach ($e2 in @($lex | Where-Object { $_.ety -eq $JIE })) {
    if (-not $e2.src) { $glBad += ('borrowed word without src: ' + $e2.w) }
}
# 星座体样式必须来自数据库，否则「单发 lumia.json 就能画出全部图形」不成立
if (-not $j.script.constellation.css) { $glBad += 'constellation.css missing' }
# lexicon[].posAll 必须与 词典.md 的词类栏一致（该栏形如 `名·太阳；形·唯一的；数·一`），
# 否则「词性」在数据库与人类可读词典之间就会悄悄分叉。
$POSTAGS = '[\u4EE3\u52A9\u8FDE\u4ECB\u540D\u52A8\u5F62\u6570\u7591\u53F9]'
$DIC = $dictMd
if (Test-Path $DIC) {
    $dicTags = @{}
    foreach ($dl in [System.IO.File]::ReadAllLines($DIC)) {
        $dm = [regex]::Match($dl, '^\|\s*\d+\s*\|\s*(\S+)\s*\|[^|]*\|\s*([^|]+?)\s*\|')
        if (-not $dm.Success) { continue }
        # 词类栏形如 `形/名·双、对、成双；数·二`：按 ；分段，取每段 `·` 之前的部分，再按 / 拆开
        $tags = @()
        foreach ($seg in @($dm.Groups[2].Value -split [string][char]0xFF1B)) {
            $head = @($seg -split [string][char]0x00B7)[0]
            foreach ($t in @($head -split '/')) {
                $tt = $t.Trim()
                if ($tt -match ('^' + $POSTAGS + '$')) { $tags += $tt }
            }
        }
        if ($tags.Count) { $dicTags[$dm.Groups[1].Value] = $tags }
    }
    foreach ($e3 in $lex) {
        $want = @($dicTags[[string]$e3.w])
        if (-not $want.Count) { continue }
        $have = if ($e3.posAll) { @([string]$e3.posAll -split '/') } else { @([string]$e3.pos) }
        if (($want -join '/') -ne ($have -join '/')) {
            $glBad += ('pos mismatch for ' + $e3.w + ': dict=' + ($want -join '/') + ' db=' + ($have -join '/'))
        }
    }
}

$glExpectWord  = @($glPairs | Where-Object { $_.prop -eq 'word'  } | ForEach-Object { $_.key })
$glExpectDigit = @($glPairs | Where-Object { $_.prop -eq 'digit' } | ForEach-Object { $_.key })
$glExpectBase  = @($glPairs | Where-Object { $_.prop -eq 'bases' } | ForEach-Object { $_.key })
foreach ($x in @($gl.word.PSObject.Properties.Name           | Where-Object { $glExpectWord  -notcontains $_ })) { $glBad += ('database has unknown word glyph '  + $x) }
foreach ($x in @($gl.digit.PSObject.Properties.Name          | Where-Object { $glExpectDigit -notcontains $_ })) { $glBad += ('database has unknown digit glyph ' + $x) }
foreach ($x in @($gl.syllabary.bases.PSObject.Properties.Name | Where-Object { $glExpectBase  -notcontains $_ })) { $glBad += ('database has unknown syllable base ' + $x) }
if ($glN -ne $glPairs.Count) { $glBad += ('checked ' + $glN + ' of ' + $glPairs.Count + ' glyphs') }
if ($glBad.Count -eq 0) { OK ("database glyph geometry and styles match the SVG assets (" + $glN + " glyphs)") }
else { BAD ("glyph geometry drift: " + (($glBad | Sort-Object -Unique) -join '; ')) }

# 30. the constellation tool ships a GENERATED data file. It must stay in step with the
#     database, or the page silently draws yesterday's glyphs.
$GJ2 = "$([char]0x5DE5)$([char]0x5177)"                                                    # 工具
$JQ2 = "$([char]0x661F)$([char]0x5EA7)$([char]0x6570)$([char]0x636E)"                      # 星座数据
$toolData = Join-Path (Join-Path $root $GJ2) ($JQ2 + '.js')
if (Test-Path $toolData) {
    try {
        $td = [System.IO.File]::ReadAllText($toolData)
        $tm = [regex]::Match($td, 'globalThis\.LUMIA\s*=\s*(\{.*\});', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if (-not $tm.Success) { BAD "constellation tool data is not a LUMIA payload" }
        else {
            $tl = $tm.Groups[1].Value | ConvertFrom-Json
            $tBad = @()
            if ($tl.version -ne $j.meta.version) { $tBad += ('version ' + $tl.version + ' != ' + $j.meta.version) }
            $tn = @($tl.words.PSObject.Properties).Count
            if ($tn -ne $lex.Count) { $tBad += ('words ' + $tn + ' != ' + $lex.Count) }
            $tg = @($tl.glyphs.word.PSObject.Properties).Count
            $dg = @($gl.word.PSObject.Properties).Count
            if ($tg -ne $dg) { $tBad += ('glyphs.word ' + $tg + ' != ' + $dg) }
            $tdig = @($tl.glyphs.digit.PSObject.Properties).Count
            if ($tdig -ne @($gl.digit.PSObject.Properties).Count) { $tBad += ('glyphs.digit ' + $tdig) }
            if ($tBad.Count -eq 0) { OK ("constellation tool data matches the database (" + $tn + " words, " + $tg + " glyphs)") }
            else { BAD ("constellation tool data stale: " + ($tBad -join '; ')) }
        }
    } catch { BAD ("constellation tool data check error: " + $_.Exception.Message) }
} else { BAD "constellation tool data missing" }

# 31. script.track: the auxiliary line-script layout must be complete and positive,
#     otherwise renderTrack() collapses a line or leaves no room for the labels.
$trk = $j.script.track
if ($trk) {
    $needTrk = @('name','spec','rule','cell','gap','lineHeight','maxWidth','margin','css')
    $goneTrk = @($needTrk | Where-Object { -not $trk.PSObject.Properties[$_] })
    $numBad = @()
    foreach ($k in @('cell','gap','lineHeight','maxWidth','margin')) {
        $v = 0
        try { $v = [double]$trk.$k } catch { $v = 0 }
        if ($v -le 0) { $numBad += $k }
    }
    if (([double]$trk.lineHeight) -lt ([double]$trk.cell)) { $numBad += 'lineHeight<cell' }
    if ($goneTrk.Count -eq 0 -and $numBad.Count -eq 0) {
        OK ("script.track complete (cell " + $trk.cell + ", gap " + $trk.gap + ", lineHeight " + $trk.lineHeight + ")")
    } else {
        $trkBad = @()
        if ($goneTrk.Count) { $trkBad += ('missing ' + ($goneTrk -join ',')) }
        if ($numBad.Count)  { $trkBad += ('bad ' + ($numBad -join ',')) }
        BAD ("script.track invalid: " + ($trkBad -join '; '))
    }
} else { BAD "script.track missing" }

# 32. the track layout and its styles must survive the JSON -> JS payload trip
#     (same bug class that once silently emptied constellation.css), and the
#     classes renderTrack() emits must actually be defined.
if (Test-Path $toolData) {
    try {
        $td2 = [System.IO.File]::ReadAllText($toolData)
        $tm2 = [regex]::Match($td2, 'globalThis\.LUMIA\s*=\s*(\{.*\});', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if (-not $tm2.Success) { BAD "track data is not a LUMIA payload" }
        else {
            $tl2 = $tm2.Groups[1].Value | ConvertFrom-Json
            $t2 = @()
            if (-not $tl2.track) { $t2 += 'track missing' }
            else {
                foreach ($k in @('cell','gap','lineHeight','maxWidth','margin')) {
                    if ([string]$tl2.track.$k -ne [string]$trk.$k) { $t2 += ($k + '=' + $tl2.track.$k) }
                }
                if ([string]$tl2.track.css -ne [string]$trk.css) { $t2 += 'css differs' }
            }
            foreach ($cls in @('.strut','.joint')) {
                if ([string]$trk.css -notmatch [regex]::Escape($cls)) { $t2 += ($cls + ' undefined') }
            }
            if ($t2.Count -eq 0) { OK "track layout and .strut/.joint styles match the database" }
            else { BAD ("track data mismatch: " + ($t2 -join '; ')) }
        }
    } catch { BAD ("track data check error: " + $_.Exception.Message) }
} else { BAD "track data check skipped: tool data missing" }

# 33. every CSS class the engine emits must actually be defined in the database
#     stylesheets. The comma node-star emits class="node", yet constellation.css
#     never defined .node -- so the browser fell back to the SVG default fill
#     (black on the near-black #0a0e1a background) and the star was invisible.
#     The geometry checks compare paths, not stylesheets, so nothing noticed.
#     Same silent-failure family as the emptied constellation.css payload.
#     NOTE: paths are emitted through drawable("track", d), so scanning only for
#     class="..." would silently stop covering bond/track/close/strut the moment
#     that refactor landed -- a check that quietly stops checking is worse than
#     no check. Both spellings are scanned.
$YQ = "$([char]0x661F)$([char]0x5EA7)$([char]0x56FE)$([char]0x5F15)$([char]0x64CE)"          # engine
$engPath = Join-Path (Join-Path $root $GJ2) ($YQ + '.js')
if (Test-Path $engPath) {
    try {
        $engSrc = [System.IO.File]::ReadAllText($engPath)
        $allCss = [string]$gl.css + [string]$const.css + [string]$trk.css
        $names = @()
        $clsRe = 'class="([A-Za-z][A-Za-z0-9_-]*)"|drawable\("([A-Za-z][A-Za-z0-9_-]*)"'
        foreach ($m in [regex]::Matches($engSrc, $clsRe)) {
            $nm = $m.Groups[1].Value
            if (-not $nm) { $nm = $m.Groups[2].Value }
            if ($names -notcontains $nm) { $names += $nm }
        }
        $miss = @()
        foreach ($n in $names) {
            if ($allCss -notmatch ('\.' + [regex]::Escape($n) + '\s*[\{,]')) { $miss += ('.' + $n) }
        }
        if ($names.Count -eq 0) { BAD "engine source scan found no CSS classes" }
        elseif ($miss.Count -eq 0) { OK ("every engine CSS class is defined in the database (" + ($names -join ', ') + ")") }
        else { BAD ("engine CSS classes undefined in the database: " + ($miss -join ', ')) }
    } catch { BAD ("engine stylesheet check error: " + $_.Exception.Message) }
} else { BAD "engine stylesheet check skipped: engine source missing" }

# 34. animation parameters must agree with the stylesheets they animate.
#     arcFlow.shift is the dash period: if it drifts from the sum of .arc's
#     stroke-dasharray, the dashed arc visibly jumps once per loop.
#     nodeBreath.from is the resting opacity: if it drifts from .halo's opacity,
#     turning animation on makes every halo jump at t=0.
#     Both are the same silent-mismatch family as check 33 (the missing .node).
$animCfg = $const.animation
if (-not $animCfg) { BAD "script.constellation.animation missing" }
else {
    try {
        $badA = @()
        foreach ($k in @('spec','rule','arcFlow','nodeBreath','trackDraw','drift')) {
            if (-not $animCfg.PSObject.Properties[$k]) { $badA += ('missing ' + $k) }
        }
        if ($badA.Count -eq 0) {
            $cssA = [string]$const.css
            $arcM = [regex]::Match($cssA, '\.arc\{[^}]*stroke-dasharray:\s*([0-9][0-9. ]*)')
            $haloM = [regex]::Match($cssA, '\.halo\{[^}]*opacity:\s*([0-9.]+)')
            if (-not $arcM.Success) { $badA += '.arc has no stroke-dasharray' }
            if (-not $haloM.Success) { $badA += '.halo has no opacity' }
            if ($arcM.Success) {
                $sum = 0.0
                $parts = $arcM.Groups[1].Value.Trim() -split '\s+'
                foreach ($pv in $parts) { $sum += [double]$pv }
                $shift = [double]$animCfg.arcFlow.shift
                if (($shift - $sum) -gt 0.0001 -or ($sum - $shift) -gt 0.0001) {
                    $badA += ('arcFlow.shift ' + $shift + ' <> .arc dasharray sum ' + $sum)
                }
            }
            if ($haloM.Success) {
                $of = [double]$haloM.Groups[1].Value
                $nf = [double]$animCfg.nodeBreath.from
                if (($nf - $of) -gt 0.0001 -or ($of - $nf) -gt 0.0001) {
                    $badA += ('nodeBreath.from ' + $nf + ' <> .halo opacity ' + $of)
                }
            }
            foreach ($pk in @('arcFlow','nodeBreath','trackDraw')) {
                if ([double]$animCfg.$pk.dur -le 0) { $badA += ($pk + '.dur must be positive') }
            }
            $sp = [double]$animCfg.trackDraw.span
            $wd = [double]$animCfg.trackDraw.width
            if ($sp -le 0 -or $sp -gt 1) { $badA += 'trackDraw.span must be in (0,1]' }
            if ($wd -le 0 -or $wd -gt 1) { $badA += 'trackDraw.width must be in (0,1]' }
            if (($sp + $wd) -gt 1) { $badA += 'trackDraw span+width exceeds 1, last segment never finishes' }
            # The one-shot growth is a CSS animation, so the @keyframes it names must
            # really exist in the stylesheet. A name that resolves to nothing means
            # the browser silently draws the finished path -- "animation on, no growth".
            $kf = [string]$animCfg.trackDraw.keyframes
            if (-not $kf) { $badA += 'trackDraw.keyframes must name a @keyframes rule' }
            elseif ($cssA -notmatch ('@keyframes\s+' + [regex]::Escape($kf) + '\s*\{')) {
                $badA += ('trackDraw.keyframes "' + $kf + '" has no @keyframes in constellation.css')
            }
            foreach ($dk in @('dur','amp','squash','phaseStep','keys')) {
                if (-not $animCfg.drift.PSObject.Properties[$dk]) { $badA += ('drift.' + $dk + ' missing') }
            }
            if ($animCfg.drift.PSObject.Properties['dur'] -and [double]$animCfg.drift.dur -le 0) {
                $badA += 'drift.dur must be positive' }
            if ($animCfg.drift.PSObject.Properties['amp'] -and [double]$animCfg.drift.amp -le 0) {
                $badA += 'drift.amp must be positive' }
            if ($animCfg.drift.PSObject.Properties['keys'] -and [double]$animCfg.drift.keys -lt 2) {
                $badA += 'drift.keys must be at least 2' }
        }
        if ($badA.Count -eq 0) {
            OK ("animation parameters agree with the stylesheets (arc period " + $animCfg.arcFlow.shift +
                ", halo opacity " + $animCfg.nodeBreath.from + ", dur " + $animCfg.trackDraw.dur + "s)")
        } else { BAD ("animation parameter mismatch: " + ($badA -join '; ')) }
    } catch { BAD ("animation parameter check error: " + $_.Exception.Message) }
}

# 35. the generated data file must carry the same animation block as the database.
#     The engine reads these numbers at runtime from the payload, so if the
#     generator ever drops them animation silently degrades to static output.
if (Test-Path $toolData) {
    try {
        $tdA = [System.IO.File]::ReadAllText($toolData)
        $tmA = [regex]::Match($tdA, 'globalThis\.LUMIA\s*=\s*(\{.*\});', [System.Text.RegularExpressions.RegexOptions]::Singleline)
        if (-not $tmA.Success) { BAD "animation data is not a LUMIA payload" }
        else {
            $tlA = $tmA.Groups[1].Value | ConvertFrom-Json
            $badB = @()
            $da = $tlA.constellation.animation
            if (-not $da) { $badB += 'animation absent from generated data' }
            elseif (-not $animCfg) { }
            else {
                foreach ($pk in @('arcFlow','nodeBreath','trackDraw','drift')) {
                    foreach ($k in @('dur')) {
                        if ([string]$da.$pk.$k -ne [string]$animCfg.$pk.$k) { $badB += ($pk + '.' + $k + '=' + $da.$pk.$k) }
                    }
                }
                foreach ($pair in @(@('arcFlow','shift'), @('nodeBreath','from'), @('nodeBreath','to'),
                                    @('nodeBreath','stagger'), @('trackDraw','span'), @('trackDraw','width'),
                                    @('trackDraw','keyframes'), @('drift','amp'), @('drift','squash'),
                                    @('drift','phaseStep'), @('drift','keys'))) {
                    if ([string]$da.$($pair[0]).$($pair[1]) -ne [string]$animCfg.$($pair[0]).$($pair[1])) {
                        $badB += ($pair[0] + '.' + $pair[1] + '=' + $da.$($pair[0]).$($pair[1]))
                    }
                }
            }
            if ($badB.Count -eq 0) { OK "generated data carries the same animation parameters as the database" }
            else { BAD ("animation data mismatch: " + ($badB -join '; ')) }
        }
    } catch { BAD ("animation data check error: " + $_.Exception.Message) }
}

# 36. backtrackLimit must be a positive number AND actually read by the engine.
#     The value and its spec sentence sat in the database for a long time and
#     were already compared by item 16, yet the engine never read it: the rule
#     "a sentence runs left to right, allowing a short backtrack of at most
#     120px" was documented and validated but not implemented. A parameter that
#     is checked for existence but never consumed is dead data, and dead data
#     looks identical to working data from the outside. This item pins the link.
$btl = $const.backtrackLimit
if ($null -eq $btl) { BAD "script.constellation.backtrackLimit missing" }
else {
    $btlNum = 0.0
    $btlParsed = $false
    try { $btlNum = [double]$btl; $btlParsed = $true } catch { $btlParsed = $false }
    if (-not $btlParsed) { BAD ("backtrackLimit is not a number: " + $btl) }
    elseif ($btlNum -le 0) { BAD ("backtrackLimit must be positive, got " + $btl) }
    elseif (-not (Test-Path $engPath)) { BAD "backtrackLimit check skipped: engine source missing" }
    else {
        try {
            $backSrc = [System.IO.File]::ReadAllText($engPath)
            if ($backSrc -match 'C\.backtrackLimit') {
                OK ("backtrackLimit is positive (" + $btl + ") and read by the engine")
            } else {
                BAD "backtrackLimit is never read by the engine (dead data)"
            }
        } catch { BAD ("backtrackLimit check error: " + $_.Exception.Message) }
    }
}

# 37. animation parameters must actually be consumed by the engine.
#     Same dead-data family as item 36. The drift block, and the @keyframes name
#     that the one-shot growth animation resolves against, only mean anything if
#     the engine really reads them. A parameter that is merely carried along in
#     the payload looks exactly like a working one from the outside.
if ($animCfg -and (Test-Path $engPath)) {
    try {
        $animSrc = [System.IO.File]::ReadAllText($engPath)
        $badC = @()
        foreach ($needle in @('AN.drift', 'driftAt(', 'driftAnim(', 'arcDAt(', 'td.keyframes')) {
            if ($animSrc -notmatch [regex]::Escape($needle)) {
                $badC += ($needle + ' never appears in the engine')
            }
        }
        if ($badC.Count -eq 0) {
            OK "drift and the CSS keyframes name are actually used by the engine"
        } else { BAD ("animation parameters are dead data: " + ($badC -join '; ')) }
    } catch { BAD ("animation usage check error: " + $_.Exception.Message) }
}

Write-Output ""
Write-Output ("== RESULT: PASS " + $script:pass + " / FAIL " + $script:fail + " ==")
if ($script:fail -gt 0) { exit 1 } else { exit 0 }
