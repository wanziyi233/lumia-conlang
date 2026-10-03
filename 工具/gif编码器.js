/* Lumia GIF 编码器
 *
 * 为什么要自己写：导出「会动的图」要能在任何地方分享——聊天软件、文档、投影。
 * 动画 SVG 只有在浏览器里打开才会动，所以必须落到 GIF。而 GIF 要自带调色板与
 * LZW 压缩，浏览器不提供任何现成入口（canvas 只能出 PNG/JPEG/WebP），
 * 所以这里自带一个最小实现，不依赖任何库。
 *
 * 调色板不用通用量化算法，而是**按本项目的配色现算**：画面里所有像素都是
 * 「底色 + alpha×(墨色 − 底色)」——抗锯齿和 opacity 都是这个形状，
 * 于是「底色 → 每个墨色」各取若干级渐变，就正好铺满真实用到的颜色，
 * 既没有量化误差，也不需要中位切分之类的重活。色阶取自 script.constellation.export。
 *
 * 用法（浏览器与 Node 通用）：
 *   var pal = LumiaGif.paletteFromCss(cssText, 12);
 *   var bytes = LumiaGif.encode(framesRGBA, w, h, { palette: pal, delayCs: 10 });
 */
(function (root) {
  "use strict";

  function parseHex(h) {
    h = h.replace("#", "");
    if (h.length === 3) h = h.charAt(0) + h.charAt(0) + h.charAt(1) + h.charAt(1) + h.charAt(2) + h.charAt(2);
    return [parseInt(h.slice(0, 2), 16), parseInt(h.slice(2, 4), 16), parseInt(h.slice(4, 6), 16)];
  }

  // 没有给调色板时的兜底：3-3-2 均匀量化，256 色。质量一般，但绝不会出错。
  function defaultPalette() {
    var p = [];
    for (var r = 0; r < 8; r++) {
      for (var g = 0; g < 8; g++) {
        for (var b = 0; b < 4; b++) p.push([r * 36, g * 36, b * 85]);
      }
    }
    return p;
  }

  /* 从 SVG 的 <style> 文本里现算调色板。
   * 底色取 .bg 规则的 fill；其余每个颜色各铺一条「底色→该色」的渐变。
   * levels 是每条渐变的级数：级数越多过渡越细，但调色板最多 256 格。 */
  function paletteFromCss(css, levels) {
    css = String(css || "");
    levels = levels > 0 ? levels : 12;
    var mb = /\.bg\s*\{[^}]*?fill\s*:\s*(#[0-9a-fA-F]{3,6})/.exec(css);
    var bg = mb ? parseHex(mb[1]) : [0, 0, 0];
    var inks = [], re = /#[0-9a-fA-F]{3,6}/g, m;
    while ((m = re.exec(css))) {
      var c = parseHex(m[0]);
      if (c[0] === bg[0] && c[1] === bg[1] && c[2] === bg[2]) continue;
      var dup = false;
      for (var i = 0; i < inks.length; i++) {
        if (inks[i][0] === c[0] && inks[i][1] === c[1] && inks[i][2] === c[2]) { dup = true; break; }
      }
      if (!dup) inks.push(c);
    }
    var pal = [bg.slice()];
    inks.forEach(function (ink) {
      for (var j = 1; j <= levels; j++) {
        var f = j / levels;
        pal.push([Math.round(bg[0] + (ink[0] - bg[0]) * f),
                  Math.round(bg[1] + (ink[1] - bg[1]) * f),
                  Math.round(bg[2] + (ink[2] - bg[2]) * f)]);
      }
    });
    var seen = {}, uniq = [];
    pal.forEach(function (c) { var k = c.join(","); if (!seen[k]) { seen[k] = 1; uniq.push(c); } });
    return uniq.slice(0, 256);
  }

  /* GIF 的 LZW：先发 clear，再发编号；字典满 4096 时发 clear 重来。
   * codeSize 是「当前码宽」，字典每长到 2^codeSize 就加一位——解码端按同一规则加宽，
   * 两边必须完全同步，差一位整幅图就花掉。 */
  function lzw(indices, minCodeSize) {
    var clear = 1 << minCodeSize, eoi = clear + 1;
    var codeSize = minCodeSize + 1, next = eoi + 1;
    var dict = new Map(), out = [], cur = 0, bits = 0;
    function emit(code) {
      cur |= code << bits; bits += codeSize;
      while (bits >= 8) { out.push(cur & 255); cur >>= 8; bits -= 8; }
    }
    emit(clear);
    var prefix = indices[0];
    for (var i = 1; i < indices.length; i++) {
      var k = indices[i], key = prefix * 4096 + k, got = dict.get(key);
      if (got !== undefined) { prefix = got; continue; }
      emit(prefix);
      if (next < 4096) {
        dict.set(key, next);
        if (next === (1 << codeSize) && codeSize < 12) codeSize++;
        next++;
      } else {
        emit(clear);
        dict = new Map(); next = eoi + 1; codeSize = minCodeSize + 1;
      }
      prefix = k;
    }
    emit(prefix); emit(eoi);
    if (bits > 0) out.push(cur & 255);
    return out;
  }

  // GIF 的数据一律切成 ≤255 字节的子块，每块前面一个长度字节，最后以 0 收尾。
  function subBlocks(out, data) {
    for (var i = 0; i < data.length; i += 255) {
      var n = Math.min(255, data.length - i);
      out.push(n);
      for (var j = 0; j < n; j++) out.push(data[i + j]);
    }
    out.push(0);
  }

  /* frames：每帧一个 w*h*4 的 RGBA 数组（正好是 canvas.getImageData().data）。
   * 返回 Uint8Array，可直接包成 Blob 下载。 */
  function encode(frames, w, h, opts) {
    opts = opts || {};
    if (!frames || !frames.length) throw new Error("GIF: 没有帧");
    var pal = opts.palette && opts.palette.length ? opts.palette : defaultPalette();
    if (pal.length > 256) pal = pal.slice(0, 256);
    var bits = 1;
    while ((1 << bits) < pal.length) bits++;
    if (bits < 2) bits = 2;
    var size = 1 << bits;

    // 颜色 → 调色板下标的查找表：把 RGB 各留 5 位当键，最多 32768 项。
    // 一帧几十万像素逐格比色太慢，缓存之后每格只算一次。
    var cache = new Int16Array(32768);
    for (var c = 0; c < cache.length; c++) cache[c] = -1;
    function nearest(r, g, b) {
      var key = ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3), v = cache[key];
      if (v >= 0) return v;
      var best = 0, bd = Infinity;
      for (var i = 0; i < pal.length; i++) {
        var dr = r - pal[i][0], dg = g - pal[i][1], db = b - pal[i][2];
        var d = dr * dr + dg * dg + db * db;
        if (d < bd) { bd = d; best = i; if (!d) break; }
      }
      cache[key] = best;
      return best;
    }

    var out = [];
    function str(s) { for (var i = 0; i < s.length; i++) out.push(s.charCodeAt(i) & 255); }
    function u16(v) { out.push(v & 255, (v >> 8) & 255); }

    str("GIF89a");
    u16(w); u16(h);
    out.push(0xF0 | (bits - 1));   // 有全局色表、8 位色分辨率、色表 2^bits 项
    out.push(0);                   // 背景色下标（0 = 底色，正好在调色板首位）
    out.push(0);                   // 像素宽高比：不指定
    for (var i = 0; i < size; i++) {
      var col = pal[i] || [0, 0, 0];
      out.push(col[0], col[1], col[2]);
    }
    out.push(0x21, 0xFF, 0x0B);    // 应用扩展：无限循环
    str("NETSCAPE2.0");
    out.push(0x03, 0x01);
    u16(opts.loop == null ? 0 : opts.loop);
    out.push(0);

    var delay = opts.delayCs > 0 ? Math.round(opts.delayCs) : 10;
    var minCodeSize = bits < 2 ? 2 : bits;
    var idx = new Uint8Array(w * h);
    for (var f = 0; f < frames.length; f++) {
      var rgba = frames[f];
      for (var p = 0, q = 0; q < idx.length; p += 4, q++) {
        idx[q] = nearest(rgba[p], rgba[p + 1], rgba[p + 2]);
      }
      out.push(0x21, 0xF9, 0x04, 0x04);   // 图形控制扩展：处置方式 1（保留上一帧），不透明
      u16(delay);
      out.push(0, 0);
      out.push(0x2C);                     // 图像描述符：整幅、无局部色表
      u16(0); u16(0); u16(w); u16(h);
      out.push(0x00);
      out.push(minCodeSize);
      subBlocks(out, lzw(idx, minCodeSize));
    }
    out.push(0x3B);                       // 结束
    return new Uint8Array(out);
  }

  root.LumiaGif = { encode: encode, lzw: lzw, paletteFromCss: paletteFromCss, defaultPalette: defaultPalette };
})(typeof globalThis !== "undefined" ? globalThis : this);
