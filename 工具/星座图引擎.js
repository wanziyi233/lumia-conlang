/* Selagrafi 星座图引擎
 *
 * 输入：罗马字转写的 Lumia 句子（ASCII），如 "komo li mako, mi li miko."
 * 输出：星座体排布的 SVG 字符串。
 *
 * 数据来自 工具/星座数据.js（由 数据/生成星座图.ps1 从 数据/lumia.json 生成）。
 * 排布规则见 文字/星座体规范.md，参数取自 script.constellation。
 *
 * 用法（浏览器与 Node 通用）：
 *   Selagrafi.render("sela li lumia.", { labels: true })
 */
(function (root) {
  "use strict";

  var D = root.LUMIA;
  if (!D) throw new Error("缺少 工具/星座数据.js —— 请先运行 数据/生成星座图.ps1");

  var C = D.constellation;
  var G = D.glyphs;
  var BOX_WORD = G.box.word, BOX_SYL = G.box.syllable, BOX_DIGIT = G.box.digit;

  /* ---------- 小工具 ---------- */

  // 由句子内容派生的确定性伪随机：同一句话永远排出同一个图
  function makeRng(seedStr) {
    var h = 2166136261;
    for (var i = 0; i < seedStr.length; i++) { h ^= seedStr.charCodeAt(i); h = (h * 16777619) >>> 0; }
    return function () {
      h ^= h << 13; h >>>= 0; h ^= h >> 17; h ^= h << 5; h >>>= 0;
      return h / 4294967296;
    };
  }
  function r2(n) { return Math.round(n * 100) / 100; }
  function hypot(x, y) { return Math.sqrt(x * x + y * y); }

  // 点到线段的距离（用于卫星净空检查）
  function distToSeg(px, py, ax, ay, bx, by) {
    var dx = bx - ax, dy = by - ay, L2 = dx * dx + dy * dy;
    var t = L2 > 0 ? ((px - ax) * dx + (py - ay) * dy) / L2 : 0;
    t = Math.max(0, Math.min(1, t));
    return hypot(px - (ax + t * dx), py - (ay + t * dy));
  }

  /* ---------- 词法 / 句法 ---------- */

  function splitSentences(text) {
    return text.split(/[.!?;。！？；\n]+/)
      .map(function (s) { return s.trim(); })
      .filter(function (s) { return s.length > 0; });
  }

  // 切词，同时记住逗号出现在第几个词之后（用于在句轨上嵌「节点星」，见规范 §五）。
  function tokenize(sentence) {
    var words = [], commaAfter = {};
    var re = /([A-Za-z]+)|([,，、;；])/g, m;
    while ((m = re.exec(sentence)) !== null) {
      if (m[1]) words.push(m[1]);
      else if (m[2]) commaAfter[words.length] = true;
    }
    return { words: words, commaAfter: commaAfter };
  }

  function info(w) {
    var lower = w.toLowerCase();
    // 专名必须**先**查：词典词全是小写，若先查 D.words，
    // "Vega" 会命中核心词 vega（去/移动）而被当成普通词，专名标记就永远设不上。
    var p = D.properNames[lower];
    if (p) return { w: w, lower: lower, known: true, proper: true, zh: p.zh };
    var e = D.words[lower];
    if (e) return { w: w, lower: lower, known: true, cat: e.cat, pos: e.pos, zh: e.zh };
    return { w: w, lower: lower, known: false };
  }

  var FRAME_WORDS = { pela: 1, meta: 1, tele: 1, vaka: 1, oba: 1, sela: 1 };
  var COMPANION_POS = { "助": 1, "介": 1, "连": 1, "疑": 1 };

  // 主星 / 伴星判定（对照三张手绘示例图的 19 个节点验证：
  // 18 个直接吻合，唯一例外 pela —— 它是时态框架词，故有下面的例外规则）
  function isCompanion(tok, next) {
    if (tok.proper) return false;
    if (tok.cat === "num") return false;
    if (FRAME_WORDS[tok.lower] && next && next.lower === "la") return false;
    return !!COMPANION_POS[tok.pos];
  }

  /* ---------- 排布 ---------- */

  var MAIN = C.cell.main, COMP = C.cell.companion;
  var HALO_MAIN = C.halo.main, HALO_COMP = C.halo.companion;
  var NUM_STANDALONE = C.cell.numeral, NUM_ATTACHED = C.cell.numeralAttached;
  var SYL = C.cell.syllable;

  function analyze(sentence) {
    var tk = tokenize(sentence);
    var toks = tk.words.map(info);
    var nodes = [], pend = [], skipped = [], before = [];

    for (var i = 0; i < toks.length; i++) {
      var t = toks[i], next = toks[i + 1];
      before[i] = nodes.length;

      // 数词修饰名词 -> 卫星，挂在后面那个名词上
      if (t.known && t.cat === "num" && next && next.known && !next.proper && next.cat !== "func") {
        pend.push({ kind: "satellite", tok: t });
        continue;
      }

      // na + 专名 -> 音节串。
      // 注意判定**不能只看 properNames**：那里只收八大行星，而 Vega / Luna / Lena
      // 这类专名并不在表内，且又与小写核心词同形（vega 去/移动、luna 月亮）——
      // 只看词典就会把 "na Vega" 画成核心词的字形。故：na 后面首字母大写、
      // 或词典外可拼的词，一律当专名。
      if (t.known && t.lower === "na" && next) {
        var properish = next.proper || /^[A-Z]/.test(next.w) || !next.known;
        var syls = next.proper ? splitSyllables(next.lower) : syllabifyAlien(next.lower);
        if (properish && syls) {
          nodes.push({ tok: t, cell: COMP, halo: HALO_COMP, companion: true, attach: pend });
          pend = [];
          nodes.push({ tok: next, cell: SYL, halo: SYL / 2 + 1, chain: syls });
          i++;
          continue;
        }
      }

      if (t.known && t.cat === "num") {
        nodes.push({ tok: t, cell: NUM_STANDALONE, halo: NUM_STANDALONE / 2 + 1, attach: pend });
        pend = [];
        continue;
      }

      // 词典里没有的词：能按 Lumia 音节规律拼出来就当音节串画，否则放弃这个节点
      if (!t.known) {
        var alien2 = syllabifyAlien(t.lower);
        if (alien2) {
          nodes.push({ tok: t, cell: SYL, halo: SYL / 2 + 1, chain: alien2, attach: pend });
          pend = [];
        } else {
          skipped.push(t.w);
        }
        continue;
      }

      var comp = isCompanion(t, next);
      nodes.push({ tok: t, cell: comp ? COMP : MAIN, halo: comp ? HALO_COMP : HALO_MAIN,
                    companion: comp, attach: pend });
      pend = [];
    }
    if (pend.length && nodes.length) nodes[nodes.length - 1].attach = (nodes[nodes.length - 1].attach || []).concat(pend);

    // 逗号 -> 句轨上的「节点星」（规范 §五）：r=3.5、#9fb4c8、不构成词，句轨从两侧接入。
    // 位置在「前 k 个词之后」，即第 k 个词的节点之前。
    var juncAt = [];
    for (var ck in tk.commaAfter) {
      var k = parseInt(ck, 10);
      if (k > 0) juncAt.push(k < toks.length ? before[k] : nodes.length);
    }
    juncAt.sort(function (a, b) { return b - a; }).forEach(function (pos) {
      nodes.splice(pos, 0, { junction: true, tok: null, cell: 8, halo: 4 });
    });

    // 闭合与否按**整句词数**判定，不能只数词典里有的词——
    // 否则「komo li mako kaka kiki koko」会被算成 3 个词而错误地闭合。
    var wordCount = toks.length;
    return {
      sentence: sentence, nodes: nodes, skipped: skipped,
      unknown: toks.filter(function (x) { return !x.known; }).map(function (x) { return x.w; }),
      wordCount: wordCount,
      closed: wordCount > 0 && wordCount <= C.closure.maxWords
    };
  }

  var CONS = D.consonants;
  var VOW = "aeiou";

  function splitSyllables(word) {
    var out = [], i = 0;
    while (i < word.length) {
      var start = i;
      if (CONS.indexOf(word[i]) >= 0) i++;
      if (i < word.length && VOW.indexOf(word[i]) >= 0) i++;
      if (i < word.length && word[i] === "n") i++;          // 音节尾 n
      if (i === start) i++;
      out.push(word.slice(start, i));
    }
    return out.length ? out : [word];
  }

  // 把词典里没有的词按 Lumia 音节规律切成 (C)V 或 (C)Vn。
  // 切不干净（辅音丛、没有元音等）或超过 4 个音节的放弃。
  function syllabifyAlien(word) {
    if (!/^[a-z]+$/.test(word)) return null;
    var out = [], i = 0;
    while (i < word.length) {
      var start = i;
      if (CONS.indexOf(word[i]) >= 0) i++;
      if (i >= word.length || VOW.indexOf(word[i]) < 0) return null;   // 必须有元音
      i++;
      if (i < word.length && word[i] === "n") {
        // n 后面不接元音时才算音节尾；接元音则是下一节的声母
        if (i + 1 >= word.length || VOW.indexOf(word[i + 1]) < 0) i++;
      }
      out.push(word.slice(start, i));
    }
    if (!out.length || out.length > 4) return null;
    return out;
  }

  /* ---- 图形评分：交叉 / 重叠 / 比例 / 内角 ---- */

  function segIntersect(p1, p2, p3, p4) {
    function cr(o, a, b) { return (a.x - o.x) * (b.y - o.y) - (a.y - o.y) * (b.x - o.x); }
    var d1 = cr(p3, p4, p1), d2 = cr(p3, p4, p2), d3 = cr(p1, p2, p3), d4 = cr(p1, p2, p4);
    return ((d1 > 0) !== (d2 > 0)) && ((d3 > 0) !== (d4 > 0));
  }

  // 阅读方向：起点应当在终点的左侧，读起来才顺。
  // 镜像不改变自交、间距、内角、长宽比，所以直接翻过来即可，评分不受影响。
  function mirrorToRead(pts) {
    var n = pts.length;
    if (n >= 2 && pts[n - 1].x < pts[0].x) {
      for (var i = 0; i < n; i++) pts[i].x = -pts[i].x;
    }
    return pts;
  }

  function scoreFigure(an, pts, closed) {
    var n = pts.length, score = 100, i, j;
    var segs = [];
    for (i = 0; i + 1 < n; i++) segs.push([pts[i], pts[i + 1]]);
    if (closed && n >= 3) segs.push([pts[n - 1], pts[0]]);

    for (i = 0; i < segs.length; i++) {
      for (j = i + 1; j < segs.length; j++) {
        if (j === i + 1) continue;
        if (closed && i === 0 && j === segs.length - 1) continue;
        if (segIntersect(segs[i][0], segs[i][1], segs[j][0], segs[j][1])) score -= 60;
      }
    }
    for (i = 0; i < n; i++) {
      for (j = i + 1; j < n; j++) {
        if (j === i + 1) continue;
        if (closed && i === 0 && j === n - 1) continue;
        var d = hypot(pts[i].x - pts[j].x, pts[i].y - pts[j].y);
        var need = an.nodes[i].halo + an.nodes[j].halo + 8;
        if (d < need) score -= 22;
      }
    }

    var xs = pts.map(function (p) { return p.x; }), ys = pts.map(function (p) { return p.y; });
    var mnx = Math.min.apply(null, xs), mxx = Math.max.apply(null, xs);
    var w = mxx - mnx, h = Math.max.apply(null, ys) - Math.min.apply(null, ys);
    var ar = Math.max(w, h) / Math.max(1, Math.min(w, h));
    if (ar > 2.4) score -= (ar - 2.4) * 16;

    // 起点越靠左加分（镜像已保证起点在终点左侧，这里再让它尽量落在最左端）
    if (w > 1) score += (1 - (pts[0].x - mnx) / w) * 14;

    if (n >= 3) {
      for (i = 0; i < n; i++) {
        if (!closed && (i === 0 || i === n - 1)) continue;
        var a = pts[(i - 1 + n) % n], b = pts[i], c = pts[(i + 1) % n];
        var v1x = a.x - b.x, v1y = a.y - b.y, v2x = c.x - b.x, v2y = c.y - b.y;
        var m = hypot(v1x, v1y) * hypot(v2x, v2y);
        if (m < 1) continue;
        var ang = Math.acos(Math.max(-1, Math.min(1, (v1x * v2x + v1y * v2y) / m))) * 180 / Math.PI;
        if (ang < C.interiorAngleTarget[0] || ang > C.interiorAngleTarget[1]) score -= 10;
      }
    }
    return score;
  }

  // 长句分簇（规范 §六）：单句超过 thresholdWords 词时，句轨拉得过长会失去星座感，
  // 于是切成若干子簇（每簇 4~6 词）。子簇之间**不连线**，靠 40px 留白区分；
  // 句间留白是 60px 且有弧轨，两者因此可以分辨。
  // 这里刻意做得克制：只在超阈值时启用，簇内排布算法完全不变。
  function clusterSize() { return 5; }
  function clusterBreaks(an) {
    var b = {};
    if (an.nodes.length > C.clustering.thresholdWords) {
      for (var s = clusterSize(); s < an.nodes.length; s += clusterSize()) b[s - 1] = true;
    }
    return b;
  }

  // 句轨节点坐标。多次采样取分最高者：
  // 保证不自交、不相邻节点不重叠、整体不过分扁长、内角落在目标区间。
  function placeNodes(an, rng) {
    var n = an.nodes.length;
    if (n === 0) return [];
    if (n === 1) return [{ x: 0, y: 0 }];

    // 超长句：先切子簇，各簇独立排布，再按 clusterGap 纵向叠起来。
    if (n > C.clustering.thresholdWords) {
      var step = clusterSize(), acc = [], cursor = 0;
      for (var s0 = 0; s0 < n; s0 += step) {
        var chunk = an.nodes.slice(s0, s0 + step);
        var sub = placeNodes({ nodes: chunk, closed: false }, rng);   // 每簇都短，不会再触发分簇
        var lo = Infinity, hi = -Infinity;
        sub.forEach(function (p) { if (p.y < lo) lo = p.y; if (p.y > hi) hi = p.y; });
        sub.forEach(function (p) { p.y += cursor - lo; acc.push(p); });
        cursor += (hi - lo) + C.clustering.clusterGap;
      }
      return acc;
    }

    if (an.closed && n >= 3) {
      var best = null;
      for (var t = 0; t < 30; t++) {
        var R = 120 + rng() * 26, a0 = rng() * Math.PI * 2, cand = [];
        var jit = (n === 3) ? 0.30 : 0.20;
        for (var k = 0; k < n; k++) {
          var a = a0 + (Math.PI * 2 * k) / n + (rng() - 0.5) * jit;
          var rr = R * (0.88 + rng() * 0.26);
          cand.push({ x: Math.cos(a) * rr, y: Math.sin(a) * rr });
        }
        var sc = scoreFigure(an, mirrorToRead(cand), true);
        if (!best || sc > best.sc) best = { pts: cand, sc: sc };
      }
      return best.pts;
    }

    // 长句：折线。多数节点处换向、左右交替，**但转角幅度每次随机**——
    // 幅度固定会让方向只在两个值间弹跳，把图形压成一条带子；幅度变化方向才会漂移、图形才铺得开。
    // 另留少数节点不换向，构成「臂」。
    var best2 = null;
    for (var t2 = 0; t2 < 120; t2++) {
      var dir = rng() * Math.PI * 2, x = 0, y = 0, flip = rng() < 0.5 ? 1 : -1;
      var cand2 = [{ x: 0, y: 0 }];
      for (var j2 = 1; j2 < n; j2++) {
        if (rng() < 0.84) {
          var mag = (88 + rng() * 48) * Math.PI / 180;      // 88~136° -> 内角 44~92°
          dir += flip * mag;
          if (rng() < 0.78) flip = -flip;
        }
        var gap = (an.nodes[j2 - 1].halo + an.nodes[j2].halo) * 1.55 + 46 + rng() * 52;
        x += Math.cos(dir) * gap; y += Math.sin(dir) * gap;
        cand2.push({ x: x, y: y });
      }
      var s2 = scoreFigure(an, mirrorToRead(cand2), false);
      if (!best2 || s2 > best2.sc) best2 = { pts: cand2, sc: s2 };
    }
    return best2.pts;
  }

  function placeAttachments(an, pts, rng) {
    var out = [], n = pts.length;
    for (var i = 0; i < n; i++) {
      var node = an.nodes[i], p = pts[i];
      var ref = null;
      if (i > 0) ref = { x: p.x - pts[i - 1].x, y: p.y - pts[i - 1].y };
      else if (i < n - 1) ref = { x: pts[i + 1].x - p.x, y: pts[i + 1].y - p.y };
      var base = ref ? Math.atan2(ref.y, ref.x) : 0;

      (node.attach || []).forEach(function (a) {
        var dist = node.cell / 2 + NUM_ATTACHED / 2 + 30;
        var satHalo = NUM_ATTACHED / 2 + 1;
        // 规范 §三「唯一硬约束」：卫星到句轨的最近距离 ≥ 卫星光晕半径 + clearance（6px），
        // 即卫星**不得压在句轨上**。从基准方向向两侧扫角度，取第一个满足净空的位置。
        var need = satHalo + C.attachments.numeral.clearance;
        var want = base + (rng() < 0.5 ? 1 : -1) * (((30 + rng() * 30) * Math.PI) / 180);
        var pick = null;
        for (var k = 0; k < 28 && !pick; k++) {
          var sideK = (k % 2 === 0) ? 1 : -1;
          var angK = want + sideK * Math.floor(k / 2) * (10 * Math.PI / 180);
          var sx = p.x + Math.cos(angK) * dist, sy = p.y + Math.sin(angK) * dist;
          var ok = true;
          // 只检查相邻的两段句轨（卫星挂在哪个节点上，就与那两段比）
          if (i > 0) ok = ok && distToSeg(sx, sy, pts[i - 1].x, pts[i - 1].y, p.x, p.y) >= need;
          if (ok && i < n - 1) ok = ok && distToSeg(sx, sy, p.x, p.y, pts[i + 1].x, pts[i + 1].y) >= need;
          if (ok) pick = { x: sx, y: sy };
        }
        if (!pick) {   // 实在找不到，就垂直朝外，并把距离拉大
          var far = dist + 26;
          pick = { x: p.x + Math.cos(base + Math.PI / 2) * far, y: p.y + Math.sin(base + Math.PI / 2) * far };
        }
        out.push({
          kind: "satellite", tok: a.tok, cell: NUM_ATTACHED, box: BOX_DIGIT,
          x: pick.x, y: pick.y,
          // from 必须是**副本**：若直接存节点对象引用，归一化时 pts 与 atts 会各平移一次，
          // 该节点就被平移两遍，整张图随即错位。
          from: { x: p.x, y: p.y }, fromHalo: node.halo, halo: satHalo
        });
      });

      if (node.chain) {
        var perp = base + Math.PI / 2;
        if ((i > 0 && pts[i - 1].y > p.y) || (i === 0 && rng() < 0.5)) perp += Math.PI;
        var px = p.x, py = p.y, prevHalo = node.halo;
        for (var s = 1; s < node.chain.length; s++) {
          var fx = px, fy = py, fh = prevHalo;
          px += Math.cos(perp) * C.attachments.syllabary.chainGap;
          py += Math.sin(perp) * C.attachments.syllabary.chainGap;
          out.push({
            kind: "chain", syl: node.chain[s], cell: SYL, box: BOX_SYL, x: px, y: py,
            from: { x: fx, y: fy }, fromHalo: fh, halo: SYL / 2 + 1
          });
          prevHalo = SYL / 2 + 1;
        }
      }
    }
    return out;
  }

  /* ---------- 画 ---------- */

  function glyphOf(tok) {
    // 专名里只有 Satuna 破例有专属星符，必须优先用它；
    // 其余专名一律走音节串，**绝不**回退到同形的核心词（Vega 不能画成 vega 去/移动）。
    if (G.word[tok.w]) return G.word[tok.w];
    if (tok.proper) return null;
    return G.word[tok.lower] || null;
  }

  // 字形画在 120（词符/音节）或 100（数字符）的方格内，中心在 (box/2, box/2)。
  // 因此必须先把方格中心对到节点坐标上再缩放 —— 少这一步字就会整体偏移。
  function glyphGroup(frag, x, y, cell, box, opacity) {
    var s = cell / box, off = box / 2 * s;
    return '<g transform="translate(' + r2(x - off) + ',' + r2(y - off) + ') scale(' + r2(s) + ')"' +
           (opacity != null ? ' opacity="' + opacity + '"' : '') + ">" + frag + "</g>";
  }

  // 数词的值可能不止一位：deka=10 / sento=100 / kilo=1000 没有独立数字符，
  // 按 numerals.numeralGlyphs 的「位值横排」写成 d1 d0 / d1 d0 d0 / d1 d0 d0 d0。
  function digitFragRow(value) {
    var s = String(value || "");
    if (!/^[0-9]+$/.test(s)) return null;
    var out = [];
    for (var i = 0; i < s.length; i++) {
      var f = G.digit[s[i]];
      if (!f) return null;
      out.push(f);
    }
    return out;
  }

  function trackSeg(a, b, ha, hb) {
    var dx = b.x - a.x, dy = b.y - a.y, L = hypot(dx, dy);
    if (L < 1) return "";
    var ux = dx / L, uy = dy / L;
    return "M" + r2(a.x + ux * ha) + " " + r2(a.y + uy * ha) +
           " L" + r2(b.x - ux * hb) + " " + r2(b.y - uy * hb);
  }

  function esc(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;"); }

  function syllableFrag(syl) {
    if (!syl) return null;
    var v = null;
    for (var i = 0; i < syl.length; i++) if ("aeiou".indexOf(syl[i]) >= 0) { v = syl[i]; break; }
    var va = v && G.syllabary.vowelAnchor[v];
    var ci = D.consonants.indexOf(syl[0]);
    var frag = "";
    if (ci >= 0) frag = G.syllabary.bases["c" + ci] || "";
    // 纯元音音节：音节表只有 16 辅音 × 5 元音，没有对应基形。
    // 不去发明新形状，退化为**只画元音定位圈**（.v 已在数据库里定义）。
    // u 是无标记元音（vowelAnchor.u = null），连圈也没有，只能返回 null。
    if (va) frag += '<circle class="v" cx="' + va[0] + '" cy="' + va[1] + '" r="' + G.syllabary.vowelRingRadius + '"/>';
    if (/n$/.test(syl) && G.syllabary.coda) frag += G.syllabary.coda;   // -n 尾
    return frag || null;
  }

  function numeralValue(w) {
    for (var i = 0; i < D.digits.length; i++) if (D.digits[i].w === w) return D.digits[i].value;
    for (var j = 0; j < D.powers.length; j++) if (D.powers[j].w === w) return D.powers[j].value;
    return 0;
  }

  /* ---------- 主入口 ---------- */

  function render(input, opts) {
    opts = opts || {};
    var sentences = splitSentences(input);
    if (!sentences.length) return { svg: "", warnings: ["没有可解析的句子"] };

    var warnings = [], figures = [];

    sentences.forEach(function (s, si) {
      var an = analyze(s);
      var alien = an.unknown.filter(function (w) { return an.skipped.indexOf(w) < 0; });
      if (alien.length) warnings.push("第 " + (si + 1) + " 句用音节符拼写了词典外的词：" + alien.join(", "));
      if (an.skipped.length) warnings.push("第 " + (si + 1) + " 句放弃了 " + an.skipped.join(", ") +
        "（不符合 Lumia 音节规律，或超过 4 个音节）");
      // 音节表是 16 辅音 × 5 元音，**没有纯元音音节**。能退化成只画元音圈的已退化，
      // 剩下的（元音为 u —— 无标记，连圈都没有）确实画不出，如实提示。
      var cantDraw = [];
      an.nodes.forEach(function (nd) {
        if (nd.chain) nd.chain.forEach(function (sy) { if (!syllableFrag(sy)) cantDraw.push(sy); });
      });
      if (cantDraw.length) warnings.push("第 " + (si + 1) + " 句的 " + cantDraw.join(", ") +
        " 画不出符号：音节表没有纯元音音节，而 u 是无标记元音（连元音圈也没有）");
      var rng = makeRng(s + "#" + si);
      var pts = placeNodes(an, rng);
      var atts = placeAttachments(an, pts, rng);
      figures.push({ an: an, pts: pts, atts: atts, breaks: clusterBreaks(an) });
    });

    var all = [];
    // 多句：各句先各自排布，再按句间留白纵向排开 —— 否则所有句子都会从原点起算、叠在一起。
    var cursorY = 0, sentGap = C.clustering.sentenceGap;
    figures.forEach(function (f) {
      var pts = f.pts.slice();
      f.atts.forEach(function (a) { pts.push(a); pts.push(a.from); });
      if (!pts.length) return;
      var mnx = Infinity, mxx = -Infinity, mny = Infinity, mxy = -Infinity;
      pts.forEach(function (p) {
        if (p.x < mnx) mnx = p.x; if (p.x > mxx) mxx = p.x;
        if (p.y < mny) mny = p.y; if (p.y > mxy) mxy = p.y;
      });
      var dx = -mnx, dy = cursorY - mny;
      f.pts.forEach(function (p) { p.x += dx; p.y += dy; });
      f.atts.forEach(function (a) { a.x += dx; a.y += dy; a.from.x += dx; a.from.y += dy; });
      cursorY += (mxy - mny) + sentGap;
    });

    // 竖排（规范 §七）：整体顺时针旋转 90° —— 句内 左→右 变 上→下，句间 上→下 变 右→左，
    // 入点/出点 左入右出 变 上入下出，其余规则全不变。
    // **只旋转版式坐标，不旋转字形与文字**：星符有固定朝向，转 90° 会变成另一个字
    //（例：li 的短横转成短竖就是 e），所以字形一律保持正立。
    var V = !!opts.vertical;
    if (V) {
      figures.forEach(function (f) {
        var rot = function (p) { var nx = -p.y, ny = p.x; p.x = nx; p.y = ny; };
        f.pts.forEach(rot);
        f.atts.forEach(function (a) { rot(a); rot(a.from); });
      });
    }

    figures.forEach(function (f) {
      f.pts.forEach(function (p) { all.push(p); });
      f.atts.forEach(function (a) { all.push(a); });
    });
    if (!all.length) return { svg: "", warnings: warnings.concat(["没有可画的节点"]) };

    var minX = Math.min.apply(null, all.map(function (p) { return p.x; }));
    var maxX = Math.max.apply(null, all.map(function (p) { return p.x; }));
    var minY = Math.min.apply(null, all.map(function (p) { return p.y; }));
    var maxY = Math.max.apply(null, all.map(function (p) { return p.y; }));

    var pad = opts.pad != null ? opts.pad : 70;
    var head = opts.title ? 66 : 26;
    var W = maxX - minX + pad * 2, H = maxY - minY + pad * 2 + head;
    var ox = pad - minX, oy = pad + head - minY;

    var body = ['<rect width="' + r2(W) + '" height="' + r2(H) + '" fill="#0a0e1a"/>'];
    var arcPaths = [], figEnds = [];

    figures.forEach(function (f) {
      var pts = f.pts.map(function (p) { return { x: p.x + ox, y: p.y + oy }; });
      var atts = f.atts.map(function (a) {
        return { kind: a.kind, tok: a.tok, syl: a.syl, cell: a.cell, box: a.box, halo: a.halo,
                 fromHalo: a.fromHalo, x: a.x + ox, y: a.y + oy,
                 from: { x: a.from.x + ox, y: a.from.y + oy } };
      });

      // 阅读方向兜底：横排时起点在终点左侧、竖排时起点在终点上方。
      // 在最终坐标上再镜像一次，保证无论前面的排布怎么走，读起来都顺着。
      var lastI = pts.length - 1;
      var reversed = lastI > 0 && (V ? (pts[lastI].y < pts[0].y) : (pts[lastI].x < pts[0].x));
      if (reversed) {
        if (V) {
          var py2 = pts.map(function (p) { return p.y; });
          var axisY = (Math.min.apply(null, py2) + Math.max.apply(null, py2)) / 2;
          var flipY = function (p) { p.y = 2 * axisY - p.y; };
          pts.forEach(flipY);
          atts.forEach(function (a) { flipY(a); flipY(a.from); });
        } else {
          var px2 = pts.map(function (p) { return p.x; });
          var axisX = (Math.min.apply(null, px2) + Math.max.apply(null, px2)) / 2;
          var flipX = function (p) { p.x = 2 * axisX - p.x; };
          pts.forEach(flipX);
          atts.forEach(function (a) { flipX(a); flipX(a.from); });
        }
      }
      var an = f.an;

      if (pts.length) {
        figEnds.push({ first: pts[0], last: pts[pts.length - 1],
                       firstHalo: an.nodes[0].halo, lastHalo: an.nodes[an.nodes.length - 1].halo });
      }

      // 卫星 / 音节串的连线（比句轨更细更淡，两端停在光晕边缘）
      atts.forEach(function (a) {
        var L = hypot(a.x - a.from.x, a.y - a.from.y);
        if (L < 1) return;
        var ux = (a.x - a.from.x) / L, uy = (a.y - a.from.y) / L;
        body.push('<path class="bond" d="M' + r2(a.from.x + ux * a.fromHalo) + " " + r2(a.from.y + uy * a.fromHalo) +
                  " L" + r2(a.x - ux * a.halo) + " " + r2(a.y - uy * a.halo) + '"/>');
      });

      for (var i = 0; i + 1 < pts.length; i++) {
        if (f.breaks[i]) continue;                 // 子簇之间不连线
        var d = trackSeg(pts[i], pts[i + 1], an.nodes[i].halo, an.nodes[i + 1].halo);
        if (d) body.push('<path class="track" d="' + d + '"/>');
      }
      if (an.closed && pts.length >= 3) {
        var last = pts.length - 1;
        var dc = trackSeg(pts[last], pts[0], an.nodes[last].halo, an.nodes[0].halo);
        if (dc) body.push('<path class="close" d="' + dc + '"/>');
      }

      // 逗号处的节点星（规范 §五）：嵌在句轨上，小点，不构成词 —— 与「落星」（悬在轨外）区分
      an.nodes.forEach(function (nd, i) {
        if (nd.junction) {
          body.push('<circle class="node" cx="' + r2(pts[i].x) + '" cy="' + r2(pts[i].y) + '" r="3.5"/>');
        } else {
          body.push('<circle class="halo" cx="' + r2(pts[i].x) + '" cy="' + r2(pts[i].y) + '" r="' + r2(nd.halo) + '"/>');
        }
      });
      atts.forEach(function (a) {
        body.push('<circle class="halo" cx="' + r2(a.x) + '" cy="' + r2(a.y) + '" r="' + r2(a.halo) + '"/>');
      });

      an.nodes.forEach(function (nd, i) {
        if (nd.junction) return;                       // 节点星没有字形
        var frag = nd.chain ? syllableFrag(nd.chain[0]) : glyphOf(nd.tok);
        if (frag) body.push(glyphGroup(frag, pts[i].x, pts[i].y, nd.cell,
                                       nd.chain ? BOX_SYL : BOX_WORD,
                                       nd.companion ? C.nodeScale.companionOpacity : null));
      });
      atts.forEach(function (a) {
        if (a.kind === "satellite") {
          var row = digitFragRow(numeralValue(a.tok.w));
          if (!row) return;
          if (row.length === 1) { body.push(glyphGroup(row[0], a.x, a.y, a.cell, a.box)); return; }
          var cellD = a.cell * 0.62, step = cellD * 1.02;
          var x0 = a.x - step * (row.length - 1) / 2;
          for (var k = 0; k < row.length; k++) body.push(glyphGroup(row[k], x0 + step * k, a.y, cellD, a.box));
        } else {
          var frag2 = syllableFrag(a.syl);
          if (frag2) body.push(glyphGroup(frag2, a.x, a.y, a.cell, a.box));
        }
      });

      if (pts.length) {
        var lp = pts[pts.length - 1];
        body.push('<circle class="fall" cx="' + r2(lp.x + 42) + '" cy="' + r2(lp.y + 42) + '" r="2.5"/>');
      }

      if (opts.labels) {
        an.nodes.forEach(function (nd, i) {
          if (nd.junction) return;
          body.push('<text class="lb" x="' + r2(pts[i].x) + '" y="' + r2(pts[i].y + nd.halo + 15) + '">' +
                    esc(nd.tok.w) + "</text>");
        });
      }
    });

    // 句间弧轨（规范 interSentence）：上一句的末节点 → 下一句的首节点，虚线弧。
    // 画在图形之前，作为背景，与手绘示例一致。
    for (var q = 0; q + 1 < figEnds.length; q++) {
      var A = figEnds[q].last, B = figEnds[q + 1].first;
      var ddx = B.x - A.x, ddy = B.y - A.y, dL = hypot(ddx, ddy);
      if (dL < 1) continue;
      var ux2 = ddx / dL, uy2 = ddy / dL;
      var ax1 = A.x + ux2 * (figEnds[q].lastHalo + 8), ay1 = A.y + uy2 * (figEnds[q].lastHalo + 8);
      var ax2 = B.x - ux2 * (figEnds[q + 1].firstHalo + 8), ay2 = B.y - uy2 * (figEnds[q + 1].firstHalo + 8);
      var perpX = -uy2, perpY = ux2, bow = Math.max(40, dL * 0.22);
      arcPaths.push('<path class="arc" d="M' + r2(ax1) + " " + r2(ay1) +
        " C" + r2(ax1 + ux2 * dL * 0.3 + perpX * bow) + " " + r2(ay1 + uy2 * dL * 0.3 + perpY * bow) +
        "," + r2(ax2 - ux2 * dL * 0.3 + perpX * bow) + " " + r2(ay2 - uy2 * dL * 0.3 + perpY * bow) +
        "," + r2(ax2) + " " + r2(ay2) + '"/>');
    }

    if (opts.title) body.push('<text class="ttl" x="26" y="34">' + esc(opts.title) + "</text>");

    var svg = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + r2(W) + " " + r2(H) +
      '" width="' + r2(W) + '" height="' + r2(H) + '">' +
      "<style>" + G.css + D.extraCss + "</style>" +
      body[0] + arcPaths.join("") + body.slice(1).join("") + "</svg>";

    return { svg: svg, warnings: warnings };
  }

  root.Selagrafi = { render: render, analyze: analyze, splitSentences: splitSentences, splitSyllables: splitSyllables };
})(typeof globalThis !== "undefined" ? globalThis : this);
