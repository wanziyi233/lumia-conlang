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

  // 切句。除文本外还**保留句末标点** —— `?` 与 `!` 在星座体里有形制含义
  //（见 文字/星座体规范.md §五：问号可闭合成环、叹号整座放大），丢掉它们就没法实现。
  function splitSentencesEx(text) {
    var out = [], cur = "";
    for (var i = 0; i < text.length; i++) {
      var ch = text.charAt(i);
      if (".!?。！？".indexOf(ch) >= 0) {
        var t = cur.trim();
        if (t) out.push({ text: t, mark: ch });
        cur = "";
      } else if (";；\n".indexOf(ch) >= 0) {
        var t2 = cur.trim();
        if (t2) out.push({ text: t2, mark: "" });
        cur = "";
      } else {
        cur += ch;
      }
    }
    var last = cur.trim();
    if (last) out.push({ text: last, mark: "" });
    return out;
  }

  function splitSentences(text) {
    return splitSentencesEx(text).map(function (s) { return s.text; });
  }

  function isComma(ch) { return ch === "," || ch === "\uFF0C" || ch === "\u3001" || ch === ";" || ch === "\uFF1B"; }

  // 切词，同时记住逗号出现在第几个词之后（用于在句轨上嵌「节点星」，见规范 §五）。
  //
  // 旧实现的正则只认 `[A-Za-z]+` 与逗号，于是任何别的字符都**一声不响地消失**：
  // 实测 `2025 li lumia.` 画出来只剩两个节点、零警告；最糟的是 `lumia123 li luna.`
  // 里的 `lumia123` 被悄悄当成 `lumia` 画了出去 —— 用户看到的是一个他没写的词。
  // 现在：任何既不是字母、也不是逗号的片段都如实收进 dropped；且字母与杂字
  // **紧贴**时（`lumia123`）整体放弃，因为那多半不是用户想写的词，画出去比不画更糟。
  // 句末标点（`.!?。！？`）不在扫描范围内 —— 它们是分隔符，由 splitSentencesEx 处理，
  // 出现在这里只说明调用方直接传了原始文本（如生成器页直接调 analyze），一律忽略。
  function tokenize(sentence) {
    var words = [], commaAfter = {}, dropped = [], prev = null;
    var re = /[A-Za-z]+|[\uFF0C,\u3001;\uFF1B]|[^\sA-Za-z\uFF0C,\u3001;\uFF1B.!?\u3002\uFF01\uFF1F]+/g, m;
    while ((m = re.exec(sentence)) !== null) {
      var t = m[0], start = m.index, end = start + t.length;
      var kind = /^[A-Za-z]+$/.test(t) ? "w" : (isComma(t.charAt(0)) ? "c" : "x");
      if (prev && prev.end === start && kind !== "c" && prev.kind !== "c" &&
          (kind === "x" || prev.kind === "x")) {
        var merged = prev.text + t;
        if (kind === "x") { words.pop(); dropped.push(merged); }
        else { dropped[dropped.length - 1] = merged; }
        prev = { kind: "x", end: end, text: merged };
        continue;
      }
      if (kind === "w") words.push(t);
      else if (kind === "c") commaAfter[words.length] = true;
      else dropped.push(t);
      prev = { kind: kind, end: end, text: t };
    }
    return { words: words, commaAfter: commaAfter, dropped: dropped };
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
      sentence: sentence, nodes: nodes, skipped: skipped, dropped: tk.dropped,
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

  // 规范 §七「句内走向：整体自左向右；允许节点小幅回折，上限 120px」。
  // 「回折」= 后一个节点比前一个更靠左。这里返回**最严重的单步回折量**（px）。
  // 注意：必须在 mirrorToRead 之后量，否则「左右」还没有定下来。
  function backtrackExcess(pts) {
    var worst = 0;
    for (var i = 1; i < pts.length; i++) {
      var back = pts[i - 1].x - pts[i].x;
      if (back > worst) worst = back;
    }
    return worst;
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

    // 回折上限（规范 §七）。闭合图形是一圈环，没有「自左向右」可言，故不适用。
    // 超过上限按超出量成比例重罚，让 120 次采样优先挑守规矩的版式；
    // 若一个都没有（节点太少或太挤），仍取最接近的——评分是择优，不是硬失败。
    if (!closed) {
      var back = backtrackExcess(pts);
      if (back > C.backtrackLimit) score -= (back - C.backtrackLimit) * 3;
    }

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
    var best2 = null, best2ok = null;
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
      // 先镜像再评分——「自左向右」只有镜像之后才成立，回折量也只有这时才有意义。
      var s2 = scoreFigure(an, mirrorToRead(cand2), false);
      if (!best2 || s2 > best2.sc) best2 = { pts: cand2, sc: s2 };
      // 回折上限是**硬偏好**而非加权：只要有一版守规矩的，就一定选它。
      // 加权压不住——回折 165px 的图形可能因为自交/重叠扣分更少而胜出（实测 45 句里漏 5 句）。
      if (backtrackExcess(cand2) <= C.backtrackLimit && (!best2ok || s2 > best2ok.sc)) {
        best2ok = { pts: cand2, sc: s2 };
      }
    }
    // 一版合规矩的都没有（节点太少或太挤）时，退回分数最高的那版，不硬失败。
    return (best2ok || best2).pts;
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
    // 首字母大写 ⇒ 专名。词典词全是小写，所以这里必须在小写回退**之前**拦下，
    // 否则 Vega / Luna 这类与小写核心词同形的专名会被画成那个核心词。
    if (/^[A-Z]/.test(tok.w)) return null;
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

  /* ---------- 动画（SMIL）----------
   * 数据库 script.constellation.animation 只存**参数**，这里按参数生成 <animate> 元素。
   * opts.animate 关闭时 AN 为 null，**一个动画元素都不输出**，产出与加动画之前逐字节相同
   * （有回归测试守着这一点——「有时更喜欢静止的」必须是真的静止，不是「看起来静止」）。
   */
  var AN = null;          // 本次渲染的动画参数；null = 静止模式
  var drawList = null;    // 本次渲染里要「逐段生长」的路径，见 drawable()
  var haloIdx = 0;        // 光晕序号，用来把呼吸相位错开

  function animArc() {
    if (!AN) return "";
    return '<animate attributeName="stroke-dashoffset" from="0" to="-' + AN.arcFlow.shift +
           '" dur="' + AN.arcFlow.dur + 's" repeatCount="indefinite"/>';
  }

  function animBreath(i) {
    if (!AN) return "";
    var b = AN.nodeBreath;
    return '<animate attributeName="opacity" values="' + b.from + ";" + b.to + ";" + b.from +
           '" dur="' + b.dur + 's" begin="-' + r2(i * b.stagger) + 's" repeatCount="indefinite"/>';
  }

  // ---------- 缓慢漂移（星空流动性）----------
  // 第 i 个句子块沿一条闭合椭圆轨迹移动：横向幅度 amp、纵向幅度 amp*squash，
  // 相位按句子序号递增 phaseStep 弧度。因为各句相位不同，它们**相对彼此**也在缓缓错位——
  // 这正是「星空在流动」与「一张静止的图」的区别。
  //
  // 关键约束：句间弧轨连的是两个句子块，句块一走弧轨就得跟着走，
  // 否则弧的一端会从光晕上脱开。所以弧轨的 d 也必须按同一组相位逐帧重算，
  // 而不是只让句块自己漂。两边的相位必须来自同一个 driftAt()，绝不能各算各的。
  function driftAt(i, u) {
    var dr = AN && AN.drift;
    if (!dr) return { x: 0, y: 0 };
    var th = 2 * Math.PI * u + i * dr.phaseStep;
    return { x: dr.amp * Math.cos(th), y: dr.amp * dr.squash * Math.sin(th) };
  }

  // 把 u = 0,1/keys,…,1 的偏移采样成一条 keyTimes（首 0 末 1，可无缝循环）。
  function driftSamples(i) {
    var dr = AN.drift, vals = [], ts = [];
    for (var s = 0; s <= dr.keys; s++) {
      var u = s / dr.keys, o = driftAt(i, u);
      vals.push(r2(o.x) + " " + r2(o.y));
      ts.push(r2(u));
    }
    return { values: vals.join(";"), keyTimes: ts.join(";") };
  }

  function driftAnim(i) {
    if (!AN || !AN.drift) return "";
    var sp = driftSamples(i), dr = AN.drift;
    return '<animateTransform attributeName="transform" type="translate" values="' + sp.values +
           '" keyTimes="' + sp.keyTimes + '" dur="' + dr.dur + 's" repeatCount="indefinite"/>';
  }

  // 弧轨的几何：两端各停在光晕外 8px，控制点沿法线偏 bow。
  // 抽成函数是因为漂移时每一帧都要用**移动后的**端点重算一遍。
  function arcDAt(A, B, hA, hB, oA, oB) {
    var ax = A.x + oA.x, ay = A.y + oA.y, bx = B.x + oB.x, by = B.y + oB.y;
    var ddx = bx - ax, ddy = by - ay, dL = hypot(ddx, ddy);
    if (dL < 1) return null;
    var ux = ddx / dL, uy = ddy / dL;
    var x1 = ax + ux * (hA + 8), y1 = ay + uy * (hA + 8);
    var x2 = bx - ux * (hB + 8), y2 = by - uy * (hB + 8);
    var px = -uy, py = ux, bow = Math.max(40, dL * 0.22);
    return "M" + r2(x1) + " " + r2(y1) +
      " C" + r2(x1 + ux * dL * 0.3 + px * bow) + " " + r2(y1 + uy * dL * 0.3 + py * bow) +
      "," + r2(x2 - ux * dL * 0.3 + px * bow) + " " + r2(y2 - uy * dL * 0.3 + py * bow) +
      "," + r2(x2) + " " + r2(y2);
  }

  // 「逐段生长」的路径先登记、后组装：每段的起止时刻取决于**总段数**，
  // 而总段数要等整个图形走完才知道，所以先放占位符，最后统一替换。
  function drawable(cls, d) {
    if (!AN) return '<path class="' + cls + '" d="' + d + '"/>';
    drawList.push({ cls: cls, d: d });
    return "\u0001" + (drawList.length - 1) + "\u0001";
  }

  // 估算路径长度。引擎目前只产出两种路径：线段（M…L…）与三次贝塞尔（M…C…）。
  function approxLen(d) {
    var n = (d.match(/-?[0-9.]+/g) || []).map(Number);
    if (d.indexOf("C") >= 0 && n.length >= 8) {
      var p0x = n[0], p0y = n[1], p1x = n[2], p1y = n[3],
          p2x = n[4], p2y = n[5], p3x = n[6], p3y = n[7];
      var L = 0, px = p0x, py = p0y;
      for (var i = 1; i <= 16; i++) {
        var t = i / 16, m = 1 - t;
        var x = m * m * m * p0x + 3 * m * m * t * p1x + 3 * m * t * t * p2x + t * t * t * p3x;
        var y = m * m * m * p0y + 3 * m * m * t * p1y + 3 * m * t * t * p2y + t * t * t * p3y;
        L += hypot(x - px, y - py); px = x; py = y;
      }
      return L;
    }
    if (n.length >= 4) return hypot(n[2] - n[0], n[3] - n[1]);
    return 0;
  }

  // 生长动画。要点：
  //  · **不要**用 pathLength="1" 做归一化再配 stroke-dasharray="1"——
  //    librsvg（以及不少转换器）不认 pathLength，却照常执行 dasharray，
  //    于是整条轨道被画成 1 用户单位的短虚线，看上去是断的（实测墨迹少了约 27%）。
  //    改用**真实长度**当 dasharray，并把它作为静态属性写上去：不认识这套动画的渲染器
  //    看到的是 dashoffset 缺省 0，也就是完整图形，不会是空图。
  //  · 用 **CSS 动画**而不是 SMIL。两次「勾了动画却看不到生长」的教训：
  //    ① SMIL 的 keyTimes 首项必须 0、**末项必须 1**，写成 "0;k0;k1" 会被判非法而整条失效；
  //    ② 更根本的是，一次性 SMIL 动画的 begin 缺省指向**文档时间轴的第 0 秒**，
  //       而图形是页面加载完之后才插进 DOM 的——那一刻早已过去，动画一出现就已播完冻结。
  //    CSS 动画在元素插入文档时自动起跑，不依赖任何时间基准，把这两个坑一起绕开。
  //    循环类的动画（弧轨流动、光晕呼吸）仍用 SMIL：它们的 repeatCount 是 indefinite，
  //    本来就不受 begin 时刻影响，而且 librsvg 之类静态渲染器会直接忽略它们。
  //    每段用自己的 --lumia-len 传长度，@keyframes 命名在 script.constellation.css 里。
  function finalizeDraw(svg) {
    if (!AN || !drawList.length) return svg;
    var n = drawList.length, td = AN.trackDraw;
    return svg.replace(/\u0001(\d+)\u0001/g, function (_, k) {
      var it = drawList[+k];
      // 略放大，宁长勿短——短了会在末端留一截永远画不到。
      var L = r2(approxLen(it.d) * 1.05 + 2);
      var k0 = n > 1 ? (+k / n) * td.span : 0;
      // 单段自身生长的时长是 width*dur，起点错开 k0*dur；
      // both = 延迟期间先停在「未画出」，跑完保持「已画出」。
      return '<path class="' + it.cls + '" d="' + it.d + '" stroke-dasharray="' + L +
             '" style="--lumia-len:' + L + ';animation:' + td.keyframes + " " +
             r2(td.width * td.dur) + "s linear " + r2(k0 * td.dur) + 's both"/>';
    });
  }

  // 光晕呼吸：动画时把 <animate> 作为子元素塞进去，自闭合标签要展开成开闭对。
  function haloCircle(x, y, r) {
    var head = '<circle class="halo" cx="' + r2(x) + '" cy="' + r2(y) + '" r="' + r2(r) + '"';
    return AN ? head + ">" + animBreath(haloIdx++) + "</circle>" : head + "/>";
  }

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
    var sentences = splitSentencesEx(input);
    if (!sentences.length) return { svg: "", warnings: ["没有可解析的句子"] };

    var warnings = [], figures = [];
    AN = opts.animate ? (C.animation || null) : null;
    drawList = []; haloIdx = 0;

    sentences.forEach(function (se, si) {
      var s = se.text;
      var an = analyze(s);
      var alien = an.unknown.filter(function (w) { return an.skipped.indexOf(w) < 0; });
      if (an.dropped.length) warnings.push("第 " + (si + 1) + " 句忽略了无法解析的字符 " +
        an.dropped.join("\u3001") + "\uFF1ALumia \u53EA\u7528 a\u2013z \u62FC\u5199\uFF0C\u6570\u5B57\u5199\u6210\u6570\u8BCD" +
        "\uFF082025 = dua kilo dua deka penta\uFF09\uFF0C\u6807\u70B9\u7528 . , ? !");
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
      var breaks = clusterBreaks(an);
      // 问号（规范 §五）：星座首尾**可**闭合成环，强调「未定」——
      // 于是把「只闭合短句」放宽到问句。但过长句子会先被分簇，
      // 闭合轨会横跨子簇、连出错误的线，故有分簇时仍不闭合。
      if (se.mark === "?" && !Object.keys(breaks).length) an.closed = true;
      an.mark = se.mark;
      // 叹号 / 祈愿（规范 §五）：`o` 起首的整座星座半径放大 1.15 倍（见下方 BOOST）。
      var boost = se.mark === "!" || /^\s*o\b/i.test(s);
      figures.push({ an: an, pts: pts, atts: atts, breaks: breaks, boost: boost });
    });

    // 叹号 / 祈愿（规范 §五）：`o` 起首的整座星座**半径**放大 1.15 倍。只放大版式半径
    //（节点与附件的坐标），字形与光晕仍按数据库的 cell —— 那些尺寸是「可读性」参数，
    // 跟着缩放会破坏 cell 的语义（cell 是星座体布局的格，不是 SVG 画布尺寸）。
    var BOOST = 1.15;
    figures.forEach(function (f) {
      if (!f.boost || !f.pts.length) return;
      var cx = 0, cy = 0;
      f.pts.forEach(function (p) { cx += p.x; cy += p.y; });
      cx /= f.pts.length; cy /= f.pts.length;
      var k = function (p) { p.x = cx + (p.x - cx) * BOOST; p.y = cy + (p.y - cy) * BOOST; };
      f.pts.forEach(k);
      f.atts.forEach(function (a) { k(a); k(a.from); });
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
    var arcPaths = [], figEnds = [], layout = [];

    figures.forEach(function (f, fi) {
      var segStart = body.length;
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

      // 悬停交互需要「哪个词落在哪个坐标」。这里把**最终坐标**一并返回，
      // 页面就不必去解析 SVG 文档或依赖元素出现的顺序——
      // 那种耦合在以后改版式（加一种附件、调整绘制次序）时会悄悄失效，而且不报错。
      if (pts.length) {
        an.nodes.forEach(function (nd, ni) {
          if (nd.junction) return;
          layout.push({ w: nd.tok.w, zh: nd.tok.zh, x: pts[ni].x, y: pts[ni].y, r: nd.halo });
        });
        atts.forEach(function (a) {
          // 卫星附件有 tok；音节串附件只有 syl，没有词形可言——不要假设 tok 一定存在。
          layout.push({ w: a.tok ? a.tok.w : (a.syl || ""), zh: a.tok ? a.tok.zh : "",
                        x: a.x, y: a.y, r: a.halo, sat: true });
        });
      }

      if (pts.length) {
        figEnds.push({ first: pts[0], last: pts[pts.length - 1],
                       firstHalo: an.nodes[0].halo, lastHalo: an.nodes[an.nodes.length - 1].halo });
      }

      // 卫星 / 音节串的连线（比句轨更细更淡，两端停在光晕边缘）
      atts.forEach(function (a) {
        var L = hypot(a.x - a.from.x, a.y - a.from.y);
        if (L < 1) return;
        var ux = (a.x - a.from.x) / L, uy = (a.y - a.from.y) / L;
        body.push(drawable("bond", "M" + r2(a.from.x + ux * a.fromHalo) + " " + r2(a.from.y + uy * a.fromHalo) +
                  " L" + r2(a.x - ux * a.halo) + " " + r2(a.y - uy * a.halo)));
      });

      for (var i = 0; i + 1 < pts.length; i++) {
        if (f.breaks[i]) continue;                 // 子簇之间不连线
        var d = trackSeg(pts[i], pts[i + 1], an.nodes[i].halo, an.nodes[i + 1].halo);
        if (d) body.push(drawable("track", d));
      }
      if (an.closed && pts.length >= 3) {
        var last = pts.length - 1;
        var dc = trackSeg(pts[last], pts[0], an.nodes[last].halo, an.nodes[0].halo);
        if (dc) body.push(drawable("close", dc));
      }

      // 逗号处的节点星（规范 §五）：嵌在句轨上，小点，不构成词 —— 与「落星」（悬在轨外）区分
      an.nodes.forEach(function (nd, i) {
        if (nd.junction) {
          body.push('<circle class="node" cx="' + r2(pts[i].x) + '" cy="' + r2(pts[i].y) + '" r="3.5"/>');
        } else {
          body.push(haloCircle(pts[i].x, pts[i].y, nd.halo));
        }
      });
      atts.forEach(function (a) {
        body.push(haloCircle(a.x, a.y, a.halo));
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

      // 漂移：把这一句产生的全部元素包进一个 <g>，整组平移。
      // AN 关掉时**不包**——静态输出的逐字节不变是硬约束。
      // 注意 layout 里留下的是**未漂移**的坐标：漂移幅度只有十几像素，
      // 远小于悬停判定半径 max(r+12, 18)，所以不必让它跟着每一帧动。
      if (AN && AN.drift) {
        var seg = body.splice(segStart);
        body.push("<g>" + driftAnim(fi) + seg.join("") + "</g>");
      }
    });

    // 句间弧轨（规范 interSentence）：上一句的末节点 → 下一句的首节点，虚线弧。
    // 画在图形之前，作为背景，与手绘示例一致。
    for (var q = 0; q + 1 < figEnds.length; q++) {
      var A = figEnds[q].last, B = figEnds[q + 1].first;
      var hA = figEnds[q].lastHalo, hB = figEnds[q + 1].firstHalo;
      var nought = { x: 0, y: 0 };
      var arcD = arcDAt(A, B, hA, hB, nought, nought);
      if (!arcD) continue;
      if (!AN) { arcPaths.push('<path class="arc" d="' + arcD + '"/>'); continue; }

      var kids = animArc();
      if (AN.drift) {
        // 弧轨两端跟着句子块漂：这里按与 driftAnim() **完全相同**的相位逐帧重算 d。
        // 两边若各算各的，弧的一端就会从光晕上脱开。
        var drf = AN.drift, dvals = [], dts = [];
        for (var ki = 0; ki <= drf.keys; ki++) {
          var uu = ki / drf.keys;
          dvals.push(arcDAt(A, B, hA, hB, driftAt(q, uu), driftAt(q + 1, uu)) || arcD);
          dts.push(r2(uu));
        }
        arcD = dvals[0];                       // 静态值取 u=0 那一帧，动画从它接着走，不会跳
        kids = '<animate attributeName="d" values="' + dvals.join(";") + '" keyTimes="' + dts.join(";") +
               '" dur="' + drf.dur + 's" repeatCount="indefinite"/>' + kids;
      }
      arcPaths.push('<path class="arc" d="' + arcD + '">' + kids + "</path>");
    }

    if (opts.title) body.push('<text class="ttl" x="26" y="34">' + esc(opts.title) + "</text>");

    var svg = finalizeDraw('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + r2(W) + " " + r2(H) +
      '" width="' + r2(W) + '" height="' + r2(H) + '">' +
      "<style>" + G.css + D.extraCss + "</style>" +
      body[0] + arcPaths.join("") + body.slice(1).join("") + "</svg>");

    return { svg: svg, warnings: warnings, layout: layout };
  }

  /* ---------- 星轨体（辅助书写规范）---------- */

  // 与星座体**共用同一套星符**、同一套附件规则，区别只在排布：
  // 星座体把一句话摆成一个星座；星轨体把同一串星符横排连成一条轨道——
  // 每符一笔成字、有固定起笔点（左）与收笔点（右），前字收笔接后字起笔。
  // 参数取自 script.track，样式类 .strut/.joint 同样定义在数据库里。

  var TRACK_CHAIN_STEP = 0.72;   // 格内并排的步长（相对格宽）

  function trackFrags(tok) {
    var g = glyphOf(tok);
    if (g) return { frag: [g], box: BOX_WORD, kind: "星符" };
    // 数词：一位数是一个数字符，多位数按位值横排（同数字符表的写法）
    var nv = -1;
    for (var i = 0; i < D.digits.length; i++) if (D.digits[i].w === tok.lower) nv = D.digits[i].value;
    for (var j = 0; j < D.powers.length; j++) if (D.powers[j].w === tok.lower) nv = D.powers[j].value;
    if (nv >= 0) {
      var row = digitFragRow(nv);
      if (row) return { frag: row, box: BOX_DIGIT, kind: "数字符" };
    }
    // 专名与词典外的词：音节串
    var syls = tok.proper ? splitSyllables(tok.lower) : syllabifyAlien(tok.lower);
    if (syls) {
      var fs = [];
      for (var k = 0; k < syls.length; k++) {
        var f = syllableFrag(syls[k]);
        if (f) fs.push(f);
      }
      if (fs.length) return { frag: fs, box: BOX_SYL, kind: "音节串" };
    }
    return null;
  }

  function renderTrack(input, opts) {
    opts = opts || {};
    var sentences = splitSentencesEx(input);
    if (!sentences.length) return { svg: "", warnings: ["没有可解析的句子"] };

    AN = opts.animate ? (C.animation || null) : null;
    drawList = []; haloIdx = 0;

    var T = D.track || {};
    var CELL = T.cell || 56;
    var GAP = T.gap != null ? T.gap : 34;
    var LH = T.lineHeight || Math.round(CELL * 1.86);
    var MAXW = T.maxWidth || 1180;
    var M = T.margin || 44;
    var STEP = CELL * TRACK_CHAIN_STEP;
    var warnings = [];

    // 逐句建格，句间强制换行；行内超宽再折行（先左后右、先上后下）
    var lines = [], cur = [], curW = 0, parts = [];
    function flush() { if (cur.length) { lines.push(cur); cur = []; curW = 0; } }

    for (var s = 0; s < sentences.length; s++) {
      var tk = tokenize(sentences[s].text);
      var toks = tk.words.map(info);
      var cells = [], ps = [];
      // 与星座体同一条规矩：不认识的字符如实报告，不静默吞掉（见 tokenize 注释）。
      if (tk.dropped.length) warnings.push("第 " + (s + 1) + " 句忽略了无法解析的字符 " +
        tk.dropped.join("\u3001") + "\uFF1ALumia \u53EA\u7528 a\u2013z \u62FC\u5199\uFF0C\u6570\u5B57\u5199\u6210\u6570\u8BCD" +
        "\uFF082025 = dua kilo dua deka penta\uFF09\uFF0C\u6807\u70B9\u7528 . , ? !");
      for (var i = 0; i < toks.length; i++) {
        var c = trackFrags(toks[i]);
        if (c) {
          var n = c.frag.length;
          cells.push({ frag: c.frag, box: c.box, n: n,
            w: CELL * (1 + (n - 1) * TRACK_CHAIN_STEP), label: toks[i].w, zh: toks[i].zh });
          ps.push({ w: toks[i].w, zh: toks[i].zh, kind: c.kind });
        } else {
          warnings.push("第 " + (s + 1) + " 句放弃了 " + toks[i].w + "（没有星符，也拼不出音节）");
          ps.push({ w: toks[i].w, kind: "放弃" });
        }
        // 逗号 -> 轨道上的节点星（与星座体的节点星同义）
        if (tk.commaAfter[i + 1]) cells.push({ joint: true, w: Math.round(CELL * 0.4) });
      }
      if (!cells.length) continue;
      flush();                                   // 句间换行
      for (var k = 0; k < cells.length; k++) {
        var need = cells[k].w + (cur.length ? GAP : 0);
        if (cur.length && curW + need > MAXW) flush();
        curW += cells[k].w + (cur.length ? GAP : 0);
        cur.push(cells[k]);
      }
      flush();
      parts.push({ sentence: sentences[s].text, words: ps });
    }
    if (!lines.length) return { svg: "", warnings: warnings.concat(["没有可画的节点"]) };

    var contentW = 0;
    for (var li = 0; li < lines.length; li++) {
      var lw = 0;
      for (var m2 = 0; m2 < lines[li].length; m2++) lw += lines[li][m2].w + (m2 ? GAP : 0);
      if (lw > contentW) contentW = lw;
    }
    var top = opts.title ? 64 : M;
    var W = contentW + M * 2;
    var H = top + (lines.length - 1) * LH + CELL + M * 1.5;

    var body = ['<rect width="' + r2(W) + '" height="' + r2(H) + '" fill="#0a0e1a"/>'];
    var layout = [];
    if (opts.title) body.push('<text class="ttl" x="' + M + '" y="34">' + esc(opts.title) + "</text>");

    for (var q = 0; q < lines.length; q++) {
      var y = top + q * LH + CELL / 2, x = M, ln = lines[q];
      for (var p = 0; p < ln.length; p++) {
        var cc = ln[p];
        if (cc.joint) {
          body.push('<circle class="joint" cx="' + r2(x + cc.w / 2) + '" cy="' + r2(y) + '" r="3.5"/>');
          layout.push({ w: "\uFF0C", zh: "", x: x + cc.w / 2, y: y, r: cc.w / 2 });
        } else {
          for (var f2 = 0; f2 < cc.n; f2++) {
            body.push(glyphGroup(cc.frag[f2], x + CELL / 2 + f2 * STEP, y, CELL, cc.box, null));
          }
          layout.push({ w: cc.label, zh: cc.zh, x: x + cc.w / 2, y: y, r: cc.w / 2 });
          if (opts.labels) {
            body.push('<text class="lb" x="' + r2(x + cc.w / 2) + '" y="' + r2(y + CELL / 2 + 20) + '">' + esc(cc.label) + "</text>");
          }
        }
        var ex = x + cc.w;
        if (p < ln.length - 1) {
          body.push(drawable("strut", "M" + r2(ex) + " " + r2(y) + " L" + r2(ex + GAP) + " " + r2(y)));
        }
        x = ex + GAP;
      }
    }

    var svg = finalizeDraw('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ' + r2(W) + " " + r2(H) +
      '" width="' + r2(W) + '" height="' + r2(H) + '">' +
      "<style>" + G.css + D.extraCss + (T.css || "") + "</style>" +
      body.join("") + "</svg>");

    return { svg: svg, warnings: warnings, parts: parts, layout: layout };
  }

  root.Selagrafi = { render: render, renderTrack: renderTrack, analyze: analyze, splitSentences: splitSentences, splitSyllables: splitSyllables };
})(typeof globalThis !== "undefined" ? globalThis : this);
