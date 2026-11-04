# PokéBonk Web 构建版本权威性核对（阶段 6d 前置校验）

- 核对日期：2026-11-04
- 核对对象：`/Users/tobycroft/Documents/GitHub/pokebonk-web`
- 性质：只读校验。未修改任何 Godot 代码 / 数据 / 场景。
- 目标：确认当前部署/权威构建，并核对三组 `assets/main-*` 中此前已移植真值是否变化。

---

## 1. 结论

**权威构建 = `mvpjh5lt` 组，实际游戏逻辑在 `assets/main-C5MieX6g-mvpjh5lt.js`。**

- `mvn4tolm`（`main-BRoWoo2--mvn4tolm.js`）与 `mvlr7rzv`（`main-CPuTGAQ--mvlr7rzv.js`）**都真实存在**，但都不是入口引用的构建；`mvlr7rzv` 组还缺失全部配套 CSS，无法独立启动。
- 最近会话「另一个不存在」的说法不成立；`main-CPuTGAQ--mvlr7rzv.js` 确实存在，只是不是权威版本。
- `version.json`（`mvpt1dlr` / `0.8.59`）与 `api-core.js` 内写的 `mvlr7rzv` / `0.8.34` **都不指向现存 asset 构建**，属于过期/外来元数据，**不是**资源版本判据。

---

## 2. 证据链

| 证据 | 位置 | 内容 |
|---|---|---|
| 入口构建标记 | [index.html:10](file:///Users/tobycroft/Documents/GitHub/pokebonk-web/index.html#L10) | `<meta name="pokebonk-build" content="mvpjh5lt">` |
| 入口脚本 | [index.html:158](file:///Users/tobycroft/Documents/GitHub/pokebonk-web/index.html#L158) | `<script type="module" ... src="./assets/main-B5SeHpLD-mvpjh5lt.js">` |
| 入口分发块 | [main-B5SeHpLD-mvpjh5lt.js:1](file:///Users/tobycroft/Documents/GitHub/pokebonk-web/assets/main-B5SeHpLD-mvpjh5lt.js#L1) | `__vite__mapDeps` 列表第 7 项 = `./main-C5MieX6g-mvpjh5lt.js`，另有 `news-BJhqkt7g`、`main-oZVl1tJD` CSS |
| 实际加载 | [main-B5SeHpLD-mvpjh5lt.js:2](file:///Users/tobycroft/Documents/GitHub/pokebonk-web/assets/main-B5SeHpLD-mvpjh5lt.js#L2) | 末尾 `import("./main-C5MieX6g-mvpjh5lt.js")` |
| 静态版本文件 | [version.json:1](file:///Users/tobycroft/Documents/GitHub/pokebonk-web/version.json#L1) | `{"build":"mvpt1dlr","version":"0.8.59"}`；`assets/` 下无任何后缀为 `mvpt1dlr` 的产物 |
| 离线 API 元数据 | [api-core.js:18-19](file:///Users/tobycroft/Documents/GitHub/pokebonk-web/api-core.js#L18-L19) | `BUILD = 'mvlr7rzv'`、`VERSION = '0.8.34'`；且 `/version.json` 被离线层接管后返回这两个值 |
| 离线层无资源清单 | [offline-fetch.js:22-36](file:///Users/tobycroft/Documents/GitHub/pokebonk-web/offline-fetch.js#L22-L36) | 只拦截 API 路径，不登记 assets；`manifest.webmanifest` 也无 js/css 引用 |
| 三组同时入库 | git `79ff342` | 三个 `main-*` 组、`api-core.js` 均在该 deploy 提交中加入 |
| 入口从未切换 | git `79ff342` / `fb029df` / `089e7a6` / `20c71f4` | `index.html` 始终引用 `main-B5SeHpLD-mvpjh5lt.js`，`content="mvpjh5lt"` 未变 |

**新旧判定（i18n 键集包含关系）**

- `en` 键数：`mvpjh5lt` 6977 > `mvn4tolm` 6521 > `mvlr7rzv` 6186。
- 严格包含：`mvlr7rzv ⊆ mvn4tolm ⊆ mvpjh5lt`（旧 → 新，逐级只增不减）。
- `ko` 同向：6947 / 6491 / 6156。

> 结论：`mvpjh5lt` 是最新且被入口引用的构建；另两组是随包残留的旧构建。抽样数据虽然一致，但三组 main bundle 的非抽样字符串集合**不构成包含关系**（15852 / 15104 / 14148 条），说明代码/文案区确有漂移，不能仅凭抽样认定三组可互换。

**样式配对完整性**

`mvlr7rzv` 启动块 [main-CwXNXC4E-mvlr7rzv.js:1](file:///Users/tobycroft/Documents/GitHub/pokebonk-web/assets/main-CwXNXC4E-mvlr7rzv.js#L1) 声明的以下文件在 `assets/` 中**不存在**：

- `700-COTNmmyX-mvlr7rzv.css`、`800-2YtJEs9e-mvlr7rzv.css`、`900-BEaisG8F-mvlr7rzv.css`
- `cyrillic-600-DsPZbYsm-mvlr7rzv.css` 等 4 个 cyrillic 子集
- `news-CdnYkD8q-mvlr7rzv.css`、`main-BnZCGLop-mvlr7rzv.css`

`mvn4tolm` 组 CSS 完整；`mvpjh5lt` 组 CSS 完整。

---

## 3. 构建组对照

| 后缀 | 入口分发块 | 实际逻辑块 | news | 样式 | 入口引用 | 状态 |
|---|---|---|---|---|---|---|
| `mvpjh5lt` | `main-B5SeHpLD` | `main-C5MieX6g`（2,289,292 B） | `news-BJhqkt7g` | 完整（`main-oZVl1tJD`） | 是 | **权威** |
| `mvn4tolm` | `main-5ek7RZPI` | `main-BRoWoo2-`（2,201,341 B） | `news-C59DVoWe` | 完整（`main-CGZDnVL6`） | 否 | 旧构建残留 |
| `mvlr7rzv` | `main-CwXNXC4E` | `main-CPuTGAQ-`（2,093,711 B） | `news-CbTCXK8Y` | **7 个文件缺失** | 否 | 旧构建残留，不可独立启动 |

> 根 `data/*.json` 只有一份（三组共用）；`assets/data/*.json` 全是 0 字节占位文件，不是数据源。

---

## 4. 抽样比对结果

比对方式：用同一锚点在各 bundle 中提取平衡括号字面量 / 函数体；`M` 表按 key 逐项比对，`KS` 归一化标识符后比对。

| 项目 | 权威构建位置（`main-C5MieX6g-mvpjh5lt.js`） | `mvpjh5lt` | `mvn4tolm` | `mvlr7rzv` | 结论 |
|---|---|---|---|---|---|
| 危险地形定义 `_D` | `@1392060`，锚点 `Zarzal venenoso` | 4 条：mud `cell0 slow .55`／bramble `cell1 slow .8 hurt .025 bite .05 poison`／quicksand `cell2 slow .5 pull 2.4`／fire `cell3 slow 1 hurt .03 bite .07 burn` | 同 | 同 | **一致**（字节级相同） |
| `byBiome` | `@1392796`，`vD` | `{forest:[mud,bramble],desert:[quicksand,fire],coast:[mud,quicksand],glacier:[mud,bramble]}` | 同 | 同 | **一致**（graveyard 无危险地形） |
| 融合攻击力覆盖 `Mw` | `@1276356` | 106 key；样例 `fu-1 1.13`、`fu-16 7`、`fu-95 11.83`、`fu-t-fire 1.32` | 106 key，逐项同 | 106 key，逐项同 | **一致**（key 集合与数值零差异） |
| 重复标记 `Pw` | `@1277895` | 22 项（`fu-23/29/35/39/79/106/107/111/122/125/127/129/131/132/143/144/146/151` + `fu-t-fire/electric/psychic` + `fu-missingno`） | 同 | 同 | **一致** |
| 冷却缩放 `Nw` | `@1277888` | `.85` | `AC=.85` | `sS=.85` | **一致** |
| 难度 tier 表 | news chunk（`Se`/`Xe`/`T`） | `hp[1,1.4,1.9] dmg[1,1.42,1.96] speed[1,1.08,1.16] amount[1,1.3,1.6] kills[1,1.25,1.5] level[1,1.5,1.8] cap[1,1.15,1.3] elite[0,.04,.08] strike[1,1.2,1.4] alphaCap1[.15,.25,.25]` 等 17 组 | 同 | 同 | **一致** |
| 关卡 HP 倍率 | news chunk | `[1,2,3.1,3.4]` | 同 | 同 | **一致** |
| HP / 伤害 / 经验乘区装配 | `run.diff=` | `enemyHp=hp[tier]`、`enemyDamage=dmg[tier]`、`xpMult=1+tier*.15`、`stardust=1+tier*.75` | 同 | 同 | **一致** |
| 经验曲线 `Cb` | `@834827` | `round(8 + L*5.5 + L**1.8)` | 同 | 同 | **一致** |
| 无尽经验曲线 | news chunk | `.7+.014t+.5(t/60)**1.75`（600 s 后 `600+.55(t-600)`） | 同 | 同 | **一致** |
| 金币掉落系数 | `drops()` | `.2`（`goldFrac += .2 * gold * i`；变量名 `Pv`/`Z_`/`Wg`） | 同 | 同 | **一致** |
| 稀有度权重 `GS` | `@1096826` | `[70/(1+a), 24*(1+.5a), 5(1+a)^2·s(3,10), .9(1+a)^3·s(8,18), .12(1+a)^4·s(14,26)]`，`a=max(0,luck+n)/100`，`o=level+luck/8+(stage-1)*12` | 同 | 同 | **一致** |
| 卡池构成 `KS` | `@1097230` | 2443 B；数字集 `{0,1,2,3,10,60,.35,.45,.5}`，字符串集 `m/newMove/upMove/upVit/newVit/v/mew/normal/status/random` | 2443 B，归一化后同 | 2439 B，归一化后同（差值仅来自压缩变量名长度） | **结构一致** |

**结论**：此前移植的上述真值在三组构建中**没有发生变化**；不存在「按新版本修正数值」的需求。

---

## 5. 需要修正 / 注意的移植清单（按影响排序）

| 排序 | 级别 | 项目 | 说明 |
|---|---|---|---|
| 1 | 高（仅影响文案覆盖面） | `.port/locale_en.out.json` = 6186 键，来自 `mvlr7rzv` | 权威 `mvpjh5lt` 的 `en` 是 **6977** 键。实际交付的 `data/i18n/ui/*.json` 已是 6977（`ko/ru/zht` 为 6947），**无需重导**；但 `.port` 中间产物与 `docs/parity/data-logic-parity.md` 里「English 6186」的口径来自旧构建，应改按 mvpjh5lt 计数。若该会话基于 `CPuTGAQ` 做过键映射，会漏 **791 键**（相对 `mvn4tolm` 漏 456 键）。 |
| 2 | 中 | 版本元数据三方不一致 | `api-core.js:18-19` = `mvlr7rzv` / `0.8.34`；`version.json` = `mvpt1dlr` / `0.8.59`；`index.html:10` = `mvpjh5lt`。且 `/version.json` 被 [offline-fetch.js:22](file:///Users/tobycroft/Documents/GitHub/pokebonk-web/offline-fetch.js#L22) 接管，实际返回 `api-core` 的值。任何存档兼容/版本校验逻辑不要依赖这些字段。 |
| 3 | 中 | `mvlr7rzv` 组不完整 | 缺 7 个 CSS/资源文件（见 §2），不能作为可运行参照；`mvn4tolm` 完整但未被引用。两者都只应作历史快照。 |
| 4 | 低 | `assets/data/*.json` 为 0 字节占位 | 真实数据只有根 `data/` 一份，三组共用；按 `assets/data/` 抽取会得到空表。 |
| 5 | 无 | 已移植的游戏数值 | 抽样范围内的危险地形、`Mw`/`Pw`/`Nw`、tier 表、HP/伤害/经验乘区、`Cb`、金币 `.2`、`GS`、`KS` 全部一致，**不需要修正**。 |

---

## 6. 复现要点

- 构建判据只看两处：`index.html:10` 的 `pokebonk-build` 与 `index.html:158` 的入口脚本；再从入口块的 `__vite__mapDeps` / 末尾 `import()` 得到实际逻辑块。
- 常量比对用「稳定锚点 + 平衡括号提取」：`Zarzal venenoso`（危险地形）、`"fu-1":1.13`（`Mw`）、`"fu-missingno"`（`Pw`）、`70/(1+a)`（`GS`）、`kind:\`newMove\`` 回溯 `function (e,t){`（`KS`）、`Math.round(8+e*5.5+e**1.8)`（`Cb`）、`goldFrac+=X*o.gold*i`（金币系数）。
- 向量名在各构建中会变（`Pw`→`jC`→`cS` 等），不要按变量名搜索，按字面量内容搜索。
