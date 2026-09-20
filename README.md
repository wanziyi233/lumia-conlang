# Lumia（露米亚）

**Lumia** — a minimal constructed language (conlang) for astronomy & science fiction.
**Lumia** —— 一门面向天文科幻社团的极简人造语言。

作者 / 维护者：**wanziyi233** · Maintainer: [@wanziyi233](https://github.com/wanziyi233)

[![License: CC BY-SA 4.0](https://img.shields.io/badge/License-CC%20BY--SA%204.0-lightgrey.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-v0.8.0-blue.svg)](数据/lumia.json)
[![Validate](https://github.com/wanziyi233/lumia-conlang/actions/workflows/validate.yml/badge.svg)](.github/workflows/validate.yml)

> **komo li mako, mi li miko.**
> 宇宙很大，我很小。 · The universe is big, I am small.

---

## 📖 在线阅读 · Read Online

**🌐 网站在线版（推荐）→ <https://wanziyi233.github.io/lumia-conlang/>**

| 内容 | 在线查看 | 源文件 |
| --- | --- | --- |
| 🔍 **可检索词典**（97 词） | [打开词典](https://wanziyi233.github.io/lumia-conlang/词典.html) | `词典.html` |
| ⭐ **星符总表**（文字系统） | [查看星符](https://wanziyi233.github.io/lumia-conlang/文字/符表.svg) | `文字/符表.svg` |
| 📝 实用语速查 | [阅读](https://wanziyi233.github.io/lumia-conlang/实用语.html) | `实用语.md` |
| 🔊 音系（发音规则） | [阅读](https://wanziyi233.github.io/lumia-conlang/音系/音系.html) | `音系/音系.md` |
| 🧩 语法 | [阅读](https://wanziyi233.github.io/lumia-conlang/语法/语法.html) | `语法/语法.md` |
| 📚 词典全表 | [阅读](https://wanziyi233.github.io/lumia-conlang/词典/词典.html) | `词典/词典.md` |
| 🔢 数字 | [阅读](https://wanziyi233.github.io/lumia-conlang/数字/数字.html) | `数字/数字.md` |
| ✍️ 文字设计说明 | [阅读](https://wanziyi233.github.io/lumia-conlang/文字/文字.html) | `文字/文字.md` |
| 🌌 **星座体**（艺术排布） | [规范](https://wanziyi233.github.io/lumia-conlang/文字/星座体规范.html) · [示例](https://wanziyi233.github.io/lumia-conlang/文字/星座体示例.svg) | `文字/星座体规范.md` |

> **关于图片**：GitHub 的仓库文件预览有时无法显示 SVG（在本机装了网络加速工具时尤其常见）。
> **本站点（github.io）不受此影响**，所有星符图表均正常显示。

---

## 这是什么 · What is Lumia?

Lumia 是一门道本语（Toki Pona）式的**极简、模糊、娱乐向**人造语言，专为天文科幻社团设计。
Lumia is a Toki-Pona-style minimal, deliberately-vague, recreational conlang designed for astronomy and sci-fi clubs.

它刻意「偏科」：能相当清晰地指认恒星、行星、土星、宇宙、轨道、脉冲，却几乎无法直接描述厨房或足球。
It is deliberately "unbalanced": it names stars, planets, Saturn, the universe, orbits and pulsars clearly, yet can hardly describe a kitchen or a football.

- 语言名 / Name：**Lumia**（/ˈlu.mi.ɑ/，露米亚），本义就是「光」/ *light*。
- 核心词汇 / Core words：**97 个**（极简）。
- 文字 / Script：**Selagrafi（星文）**——星轨体一笔连写 + 星座体艺术排布，表意 + 表音混合。

## 特性 · Features

| 维度 / Aspect | 设计 / Design |
| --- | --- |
| 音系 / Phonology | 英式口音 + 五元音 a e i o u；音节 `(C)V(n)`；16 辅音 |
| 语法 / Grammar | 道本语框架 + 天体隐喻时态（过去/现在/未来/假设/总是） |
| 数字 / Numerals | 十进制、一词双义（0=`vaka`、1=`sola`） |
| 文字 / Script | 表意（星符）+ 表音（80 音节符）+ 数字符 |
| 数据 / Data | 单一 JSON 数据库 + 一致性校验脚本 |

## 目录结构 · Repository Structure

```
人造语尝试/
├── LICENSE               CC BY-SA 4.0 许可证
├── README.md             本文件（总览）
├── 词典.html             可检索词典（由 数据/生成词典.ps1 生成）
├── 实用语.md             基础用语速查
├── 音系/                 发音与音系规则
├── 词典/                 97 个核心词全表
├── 语法/                 语法规则
├── 数字/                 十进制数词
├── 文字/                 星文字形设计 + 各类 SVG 图表
├── 数据/
│   ├── lumia.json        全系统单一数据库（权威数据源）
│   ├── 校验.ps1          一致性校验脚本
│   ├── 生成词典.ps1      词典生成脚本
│   └── dict-template.html 词典 HTML 模板
└── .github/workflows/    CI：每次提交自动运行校验
```

## 快速开始 · Quick Start

- 想查词？打开 **[在线词典](https://wanziyi233.github.io/lumia-conlang/词典.html)**（可检索全部 97 词）。
- 想系统了解？按这个顺序读：**[实用语速查](https://wanziyi233.github.io/lumia-conlang/实用语.html)** → **[音系](https://wanziyi233.github.io/lumia-conlang/音系/音系.html)** → **[语法](https://wanziyi233.github.io/lumia-conlang/语法/语法.html)** → **[文字](https://wanziyi233.github.io/lumia-conlang/文字/文字.html)**。
- 想看星符？直接开 **[星符总表](https://wanziyi233.github.io/lumia-conlang/文字/符表.svg)**。
- 示例句 / Example：

| Lumia | 中文 / English |
| --- | --- |
| `sela li lumia.` | 星星是亮的。 / The star is bright. |
| `paneta ni li oba e sola.` | 那颗行星绕太阳运行。 / That planet orbits the sun. |
| `Satuna li paneta ku oba.` | 土星是一颗带环的行星。 / Saturn is a ringed planet. |
| `meta la mi vega wo komo.` | 未来我赴宇宙。 / In the future I go to the cosmos. |

## 工具 · Tooling

需要 PowerShell。**注意命令名不一样**：Windows 自带的是 Windows PowerShell 5.1，命令为 `powershell`；`pwsh` 是 PowerShell 7+ 的命令，Windows 默认**没有**安装（macOS/Linux 需自行安装 [PowerShell](https://github.com/PowerShell/PowerShell)）。

```bash
# 一致性体检（18 项检查）
powershell -File 数据/校验.ps1

# 改完 数据/lumia.json 后，刷新可检索词典
powershell -File 数据/生成词典.ps1
```

> macOS / Linux 用户请把上面的 `powershell` 换成 `pwsh`。

> **数据是唯一权威源**：所有词条/音系/语法/字形改动请先改 `数据/lumia.json`，再同步 Markdown 文档，并运行校验确保全 PASS。

## 贡献 · Contributing

欢迎提 Issue / PR！请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证 · License

- **文档、图表与星文字形**：以 [CC BY-SA 4.0](LICENSE) 授权（署名-相同方式共享）。
- **语言本身**（语法、词汇、发音规则）：语言通常不受版权保护，可自由使用，但请注明来源（遵循 CC BY-SA 的署名习惯）。
- *Documentation, charts and the Selagrafi script*: licensed under [CC BY-SA 4.0](LICENSE).
- *The language itself* (grammar, vocabulary, phonology): languages are generally not copyrightable; feel free to use it, with attribution appreciated.

---

*This project is a work-in-progress development version (v0.8.0). 本项目为开发版，仍会持续改动。*
