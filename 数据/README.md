# 数据文件夹说明

本目录存放 Lumia 的**机器可读数据库**，供存档与 AI 快速重读记忆，防止设计信息遗漏。

## 文件

| 文件 | 内容 |
| --- | --- |
| `lumia.json` | **单一总数据库**：音系 + 97 词词典 + 数字 + 语法 + 文字（**含全部字形几何**）+ 专名 + 常用语 + 时间表达，一文件掌握全系统 |

## JSON 结构（顶层键）

| 键 | 含义 |
| --- | --- |
| `meta` | 语言名、版本、设计决策清单、核心词数 |
| `phonology` | 元音/辅音/音节/重音/借词适配 |
| `lexicon` | 97 个核心词数组（`w`=词形，`ipa`，`cat`=func/astro/num/base，`pos`，`zh`，`en`，`ety`=自/借） |
| `numerals` | 十进制数词（一词双义）与组数示例 |
| `grammar` | 语序、功能词、代词、天体隐喻时态、例句 |
| `script` | Selagrafi 星文：原则、基元、字形配方、**字形几何 `glyphs`**、音节符、方向、**星座体参数** |
| `properNames` | **八大行星**专名（日月不入表，直接借用 `sola`/`luna` 的大写形式）。`Vega`、人名等其他专名按音系规则临时适配，不登记 |
| `phrases` | 常用语与句模板（`lumia` + `zh`） |
| `time` | 时间表达：一小时（`aka`）与七曜星期（`sema na X`） |

## 使用约定

- **lexicon 的 `cat` 取值**：`func` 功能词 · `astro` 天文科幻借词 · `num` 数词 · `base` 基础自创词。
- 此 JSON 是权威数据源；`词典.md`、`数字.md` 等 Markdown 是人类可读版本，二者应保持同步。
- 版本号随设计变更递增（当前 `0.15.0`）。

## 自包含：字形几何

`script.glyphs` 存放**全部字形的几何**（87 个词符 + 10 个数字符 + 16 个音节基形），
每条都是可直接嵌入 SVG 的片段。所以**单发这一个文件，对方就能画出全部字形**——

```xml
<svg viewBox="0 0 120 120" xmlns="http://www.w3.org/2000/svg">
  <style><!-- 这里放 script.glyphs.css --></style>
  <g><!-- 这里放 script.glyphs.word.lumia --></g>
</svg>
```

- 词符：`box.word` = 120；数字符：`box.digit` = 100
- 音节符：取 `syllabary.bases` 里对应的基形，再按 `syllabary.vowelAnchor` 放一个半径
  `syllabary.vowelRingRadius` 的空心圆（`u` 的锚点是 `null`，即不标点）
- 完整示例见 `script.glyphs.usage`

校验第 29 项会**逐字比对**数据库与 SVG 资产，任一侧改动而另一侧没跟上都会 FAIL。
