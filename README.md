# Lumia（露米亚）

**Lumia** — a minimal constructed language (conlang) for astronomy & science fiction.
**Lumia** —— 一门面向天文科幻社团的极简人造语言。

作者 / 维护者：**wanziyi233** · Maintainer: [@wanziyi233](https://github.com/wanziyi233)

[![License: CC BY-SA 4.0](https://img.shields.io/badge/License-CC%20BY--SA%204.0-lightgrey.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-v0.7.0-blue.svg)](数据/lumia.json)
[![Validate](https://github.com/wanziyi233/lumia-conlang/actions/workflows/validate.yml/badge.svg)](.github/workflows/validate.yml)

> **komo li mako, mi li miko.**
> 宇宙很大，我很小。 · The universe is big, I am small.

---

## 这是什么 · What is Lumia?

Lumia 是一门道本语（Toki Pona）式的**极简、模糊、娱乐向**人造语言，专为天文科幻社团设计。
Lumia is a Toki-Pona-style minimal, deliberately-vague, recreational conlang designed for astronomy and sci-fi clubs.

它刻意「偏科」：能相当清晰地指认恒星、行星、土星、宇宙、轨道、脉冲，却几乎无法直接描述厨房或足球。
It is deliberately "unbalanced": it names stars, planets, Saturn, the universe, orbits and pulsars clearly, yet can hardly describe a kitchen or a football.

- 语言名 / Name：**Lumia**（/ˈlu.mi.ɑ/，露米亚），本义就是「光」/ *light*。
- 核心词汇 / Core words：**97 个**（极简）。
- 文字 / Script：**Selagrafi（星文 · 星轨体）**，表意 + 表音混合。

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

- 打开 `词典.html` 可检索全部 97 词。
- 从 `音系/`、`词典/`、`语法/`、`数字/`、`文字/` 快速了解全貌。
- 示例句 / Example：

| Lumia | 中文 / English |
| --- | --- |
| `sela li lumia.` | 星星是亮的。 / The star is bright. |
| `paneta ni li oba e sola.` | 那颗行星绕太阳运行。 / That planet orbits the sun. |
| `Satuna li paneta ku oba.` | 土星是一颗带环的行星。 / Saturn is a ringed planet. |
| `meta la mi vega wo komo.` | 未来我赴宇宙。 / In the future I go to the cosmos. |

## 工具 · Tooling

需要 PowerShell（Windows 自带；macOS/Linux 装 [PowerShell](https://github.com/PowerShell/PowerShell)）。

```bash
# 一致性体检（18 项检查）
pwsh -File 数据/校验.ps1

# 改完 数据/lumia.json 后，刷新可检索词典
pwsh -File 数据/生成词典.ps1
```

> **数据是唯一权威源**：所有词条/音系/语法/字形改动请先改 `数据/lumia.json`，再同步 Markdown 文档，并运行校验确保全 PASS。

## 贡献 · Contributing

欢迎提 Issue / PR！请先阅读 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证 · License

- **文档、图表与星文字形**：以 [CC BY-SA 4.0](LICENSE) 授权（署名-相同方式共享）。
- **语言本身**（语法、词汇、发音规则）：语言通常不受版权保护，可自由使用，但请注明来源（遵循 CC BY-SA 的署名习惯）。
- *Documentation, charts and the Selagrafi script*: licensed under [CC BY-SA 4.0](LICENSE).
- *The language itself* (grammar, vocabulary, phonology): languages are generally not copyrightable; feel free to use it, with attribution appreciated.

---

*This project is a work-in-progress development version (v0.7.0). 本项目为开发版，仍会持续改动。*
