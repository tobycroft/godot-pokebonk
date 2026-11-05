# PokéBonk Godot ↔ Web：数据 / 规则 / 状态 / 文案 一致性审计

- 审计日期：2026-11-04
- 权威参考（真值）：`/Users/tobycroft/Documents/GitHub/pokebonk-web`
  - 数据：`data/*.json`、`data/i18n/*.json`
  - 逻辑 bundle：`assets/main-C5MieX6g-mvpjh5lt.js`（`index.html` 的入口 `main-B5SeHpLD…` 只做分发，实际逻辑在此块；下文 offset 均为该文件字符偏移）
  - 存档/离线 API：`api-core.js`、`save-manager.js`、`offline-fetch.js`
- 被审计对象：`/Users/tobycroft/godot/godot-pokebonk`
- 辅助参考：`/Users/tobycroft/Documents/GitHub/pokebonk-re`（仅用于补齐资源，不作为规则真值）
- 本报告只读产出；未修改任何 Godot 场景 / 脚本 / 资源 / 数据文件。

> 说明：bundle 为压缩产物，函数名不可读。本文以「offset + 关键字」定位，必要时给出原文片段，避免臆造。

---

## 0. 结论摘要（按影响程度）

| 级别 | 数量级 | 摘要 |
|---|---|---|
| 高 | 6 类 | ① 野怪/关卡/掉落/卡片/实验室等数值大量为“估计值”；② 伤害与受击管线缺少多个乘区与状态分支；③ 物品、商店、捕获、进化、天气事件、危险地形整块缺失；④ UI i18n 完全未接线（0/5225 键）；⑤ 图鉴/融合/实验室/存档界面完全不本地化；⑥ 捕获（captures）语义被改成“击杀即捕获” |
| 中 | 6 类 | ① 融合缺少“图鉴签名招式”占位报价；② 存档新增 research 自增、starter 不写 league 数组、league 数组导入会崩；③ 54 个物种缺图；④ 叫声/BGM 资源未接线；⑤ 图鉴详情用西语、HUD 用中文的混排；⑥ 106 条融合 `fused_def` 未与 Web 逐字段核对（待确认） |
| 低 | 4 类 | ① armor 阈值常量不一致；② 天气名被改写；③ 存档文件名/备份命名/令牌细节；④ 类型 i18n 多 1 键 |

**核心量化**

- 7 张主数据表与 Web **逐字节一致**（md5 相同）：abilities 314、items 151、moves 919、pokemon 1025、learnsets 1025、sprites 1025、types 18+18×18。
- 7 种语言 i18n 与 Web 逐字节一致，每语言 6 段共 3044 键（pokemon 1025 / flavor 151 / moves 919 / abilities 314 / types 19 / items 151）。
- Web 的 **UI 文案表**（bundle 内，已被 `tools` 抽到 `.port/locale_*.out.json`）：中文 5225 键、英文 6186 键；Godot **加载 0 键**。
- Godot `src/` 内唯一中文字面量 **272 条**，含重音字符的西语字面量 **21 条**（另有若干无重音西语短语，见 §5）。
- `data/i18n` 只能覆盖“名称”，Web 的 UI 句子（按钮/提示/确认框/空状态）未进入 Godot。
- 资源缺口：**54/1025** 物种无 `pmd` 与 `portraits` 图；`cries` 仅 1 个模板音；`assets/music` 的 7 首 OGG 全部未被播放。

---

## 1. 审计方法与可复现命令

1. 主数据表做 md5 与逐项键对比：
   ```bash
   md5 -q pokebonk-web/data/moves.json godot-pokebonk/data/moves.json
   ```
2. `.port/*.out.json`（从 bundle 抽取）与 `data/pb/*.json`（Godot 载入的派生表）做扁平化键值 diff。
3. i18n 键集：`data/i18n/<lang>.json` 与 `.port/locale_<lang>.out.json` 对比。
4. 规则：`src/core/pb_*.gd` 与 bundle offset 对照（本报告逐条给出 offset）。
5. 资源：`data/sprites.json` 的 id 与 `assets/pmd`、`assets/portraits` 实际文件做集合差。
6. 文案：正则统计 `src/**/*.gd` 的 CJK 与西语字面量，并统计 `App.t()` / `localized_name()` 调用点。

---

## 2. 数据表一致性

### 2.1 主数据表：完全一致

Web 与 Godot 的以下文件 md5 完全相同，不存在字段缺失、数值改写、条目增删、ID 错位：

| 表 | 条目数 | Web 路径 | Godot 路径 | 结论 |
|---|---|---|---|---|
| abilities | 314 | `data/abilities.json` | `data/abilities.json` | 逐字节一致 |
| items | 151 | `data/items.json` | `data/items.json` | 逐字节一致 |
| moves | 919 | `data/moves.json` | `data/moves.json` | 逐字节一致 |
| pokemon | 1025 | `data/pokemon.json` | `data/pokemon.json` | 逐字节一致 |
| learnsets | 1025 | `data/learnsets.json` | `data/learnsets.json` | 逐字节一致 |
| sprites | 1025 | `data/sprites.json` | `data/sprites.json` | 逐字节一致 |
| types | 18 names + 18 chart | `data/types.json` | `data/types.json` | 逐字节一致 |
| i18n（7 语） | 3044×7 | `data/i18n/*.json` | `data/i18n/*.json` | 逐字节一致 |

**结论**：`data/*.json` 层面 0 差异。问题不在原表，而在“用什么、怎么用、缺什么”。

### 2.2 派生表 `data/pb/*.json` 与抽取源 `.port/*.out.json`

| 文件 | 差异 |
|---|---|
| `constants.json` | 结构被重排（源 `.port/constants.out.json` 15 组 → 目标 141 个扁平键），语义保留；属于“可读性重排”，非数值改写 |
| `world_biomes.json` / `world_props.json` | 目标额外补充 `_offset_news`、`residents`、`summoners` 等字段；重叠键值一致；属“增补”不是“改写” |
| **`weather.json`** | ⚠ 把 Web **天气事件表**换成了**战斗加成表**，见 2.3 |
| `hazards` | `.port/hazards.out.json` 已抽取，但 `data/pb/` **没有对应条目**，代码也未使用（见 §3.6） |

### 2.3 天气：抽错表 + 文案改写（高）

- Web 真值（`.port/weather.out.json`，bundle 内事件表）：
  `fog / storm / eclipse / meowth`，字段含 `dur`（45/40/40/25）、`pool`（稀有物种池）、`look`（雾/光照/云量/日食/暗角）。
- Godot `data/pb/weather.json` 实际是**伤害加成表**（clear/rain/sun/sand/hail…），字段 `boost/nerf`，**没有 `dur`、`pool`、`look`**。
- 因此 Godot 运行时 `weather` 永远为 `"clear"`（仅 `src/core/pb_run.gd:48` 初始化，无任何赋值点），天气招式、天气事件、日食刷怪全部无效。
- 同一文件里 `fog.name` 被从 Web 的 `"Niebla espectral"` 改成 `"Niebla"`（bundle offset ≈ 744000 区域唯一出处，可确认 Web 真值）。
- 修复：新增 `data/pb/weather_events.json`（直接采用 `.port/weather.out.json`），恢复 `"Niebla espectral"`；在 run tick 中实现事件计时、`pool` 刷怪与 `look` 渲染。

### 2.4 i18n 覆盖结构（中）

- `data/i18n` 与 Web 一致，但只有 6 段“实体名称 + 151 条图鉴 flavor”。
- Web 的 UI 句子存放于 bundle 的语言模块（已被抽到 `.port/locale_*.out.json`）：
  - `zh` 5225 键、`en` 6186 键、`zht` 5225 键。
- 这些键 **不在仓库里**（`.gitignore:4` 忽略 `.port/`，`git ls-files .port` = 0），Godot 无法读取。
- `flavor` 仅 151 条，1025 物种中的 874 个在 Web 也回落 `pokemon.flavor`（西语）；Godot 图鉴同样只用 `species.flavor`（见 §5）。
- `types` i18n 19 键 vs `data/types.json` 18 个类型名（多 1 键），低影响。

---

## 3. 数值与规则对照

### 3.1 已核对一致（可放心）

| 规则 | Web 出处 | Godot 出处 | 结论 |
|---|---|---|---|
| 属性克制 18×18 | bundle offset ≈ 6232 | `src/core/pb_damage.gd:28` `effectiveness()` | 一致 |
| 受击克制夹取 0.5~1.6 | `incoming_effectiveness` | `pb_damage.gd:22-23,50` | 一致 |
| 基础六维换算（HP/攻/防/速/特攻/特防） | bundle ≈ 812367 | `pb_stats.gd:28` `stats_from_species()` | 一致 |
| 加成组（lab、饰品、性格） | bundle ≈ 813284 | `pb_stats.gd:73` `apply_mod_groups()` | 一致 |
| 护甲减伤 `1 - x/(x+45)`，上限 0.99999 | bundle ≈ 834827 | `pb_stats.gd:110` `armor_mitigation()` | 公式一致；阈值常量见 §3.7 |
| 招式实例（威力/冷却/数量/范围/状态/暴击） | bundle ≈ 1583829 | `pb_damage.gd:70-135` `move_instance()` | 一致（含 8%+4%/级双乘区、1.3×；STAB 在 strike 生效，见下行） |
| 类型→状态、招→原型、原型表 | bundle ≈ 791717 | `pb_moves.gd:125` `resolve()` | 一致 |
| 招式评分选优算法 | bundle ≈ 792596 | `pb_moves.gd:264` `best_move_for()` | 打分一致；**兜底不同**，见 §3.4 |
| 经验曲线 `round(8+5.5·L+L^1.8)` | `src/core/pb_xp.gd:9-15` | 同 | 一致 |
| 融合配方 106 条、排序、合并 | bundle ≈ 1278600 | `pb_fusion.gd:41-232` | 配方/排序/`kind` 一致；缺 roster 报价，见 §3.5 |
| 存档基础字段 | `api-core.js:56-110` | `save_service.gd:55-110` | 基础 profile 字段完全一致 |

### 3.2 被替换为“估计值”的数值（高）

以下数值在 Godot 代码中**明确标注 estimated / TODO**，无 Web 出处，属于规则重写而非复刻：

| 项目 | Godot 出处 | 现状 | 影响 |
|---|---|---|---|
| 关卡时长 | `pb_run.gd:15` `STAGE_TIME := 60.0` | 估计 | 整局节奏 |
| 关卡数 | `pb_run.gd:16` `STAGES := 5` | 固定 5 | 与 Web 关卡推进不一致 |
| 每秒最大刷新 | `pb_run.gd:17` `14.0` | 估计 | 刷怪密度 |
| 单只经验权重 | `pb_run.gd:18` `3.0` | 估计 | 升级速度 |
| 单只金币 | `pb_run.gd:19` `1.5` | 估计 | 经济系统 |
| 野怪 HP | `pb_enemies.gd:104` `(8 + BST·0.06)·(1+0.35·(stage-1))` | **替代公式**；代码注释承认 `ft()/an()` 未恢复 | 所有战斗数值不可比 |
| 野怪伤害 | `pb_enemies.gd:121` `6 + 2·stage` | 估计 | 难度曲线 |
| 野怪速度 | `pb_enemies.gd:122` 直接取玩家 stats.moveSpeed | 估计 | 追逐体验 |
| 精英/Alpha/Legendary/Boss HP 倍率 | `pb_enemies.gd:106-115` `2.5/3.5/6/12` | 估计 | 高难模式 |
| 野怪抽取权重 | `pb_enemies.gd:29` `TIER_WEIGHT` | 估计 | 稀有度 |
| 危险度/刷新曲线 | `pb_run.gd:114-167` | 估计（线性 0.55→1.0） | 难度 |
| 卡片掷取权重 | `pb_cards.gd:26-30,54-155` `3.0/1.4/2.4/1.2` | 估计 | 构筑强度 |
| 卡片数值池 | `pb_cards.gd:16-46` `STAT_POOL/ARCH_STAT_AMOUNTS` | 估计 | 卡片强度 |
| 实验室加成值 | `save_service.gd:346-362` `lab_deltas()` | 估计（注释“amounts estimated”） | 元进度收益 |
| 成长指数 | `pb_actor.gd:16` `GROWTH_PER_LEVEL := 1.0` | 估计 | 六维随等级增长 |
| 状态时长/DPS | `pb_status.gd:19-45` `VERIFIED/DEFAULTS` | 部分估计 | 状态强度 |
| 无尽模式经验 | `pb_xp.gd:17-23` `1.16^L` | 估计 | Endless 曲线 |

修复建议：把这批常量整体迁到 `data/pb/run_tuning.json`，并在字段上标注 `source_offset`；能反编译出 Web 常量的逐项替换，不能恢复的保留 `estimate` 字段并在启动日志打印，避免“看似 1:1”。

### 3.3 伤害 / 受击管线缺口（高）

Web `strike`（offset 746724）与 `hurt`（offset 846019）包含多个 Godot 未实现的乘区/分支：

| 缺失项 | Web 语义 | Godot 现状 |
|---|---|---|
| `player.bonusDamageMult()` | 全局增伤 | 未乘（`pb_damage.gd:164-253`） |
| `ability.hitMul` | 能力增伤 | 未实现（仅 pickup/beacon/venom 特判） |
| `critAdd` | 暴击率加成 | 未实现 |
| `items.stick` + `noReact` | 道具暴击与“无反应”招式屏蔽 | 仅 stick，且未判 noReact |
| `endless.siegeMult` | 无尽模式乘区 | 未实现 |
| Boss 机制/套件 `hitMul` | Boss 专属倍率 | 仅 exhaust |
| Alpha `12290` 旗标 | 精英判定掩码 | 仅 `elite or boss`，漏 12290 组合 |
| 冻结碎裂（冰系治疗抵消） | 冻结状态交互 | 只有 1.2×，无碎裂 |
| `venom-sting` 附带中毒 | 能力附加状态 | 未实现 |
| `effect-spore / compound-eyes / carnivore` | 状态/命中/吸血分支 | 未实现 |
| `awakening` 解除睡眠 | 能力交互 | 未实现 |
| 玩家 `hurtMod`、最小伤害、最大伤害、`Qp` | 受击乘区与下限 | 未实现（`incoming_to_player()` 仅护甲+魔法护盾+克制夹取） |
| `overheal` 吸收、`shield` 吸收、`thorns`、`contact`、`headache`、`onHurt` | 玩家受击链 | 未实现（`pb_actor.gd:229` `damage()` 直接扣 HP） |

**影响**：同一招式/同一受击，Godot 与 Web 结果可能在数十个百分点到整倍之间。

修复建议：按 Web 顺序在 `strike()` 中补齐乘区；`PbActor.damage()` 改为调用统一的 `incoming_to_player()`，并实现 overheal→shield→thorns 的扣减顺序；每个分支加开关（`feature_flags.json`），便于逐项回归。

### 3.4 招式分配兜底（中）

Web `xy`（offset 792596）末尾兜底：
```
若无候选 → 遍历所有招式中“非 weather/buff 且 type === species.types[0]”者，返回该招；
否则返回 33。
```
Godot `pb_moves.gd:264-302` 无兜底，直接返回 `""`；`pb_actor.gd:184` 自动装配因此可能一个招式都不给。

修复：在 `best_move_for()` 末尾追加同样兜底，返回 33（以及类型招）。

### 3.5 融合（中）

- Web `Gw` 有一个“图鉴签名（roster）”占位报价：`{a:-1,b:-1,ready:false,kind:'signature'}`，文案区分“可学习 / 已在队内 / 已流放”。
- Godot `pb_fusion.gd:155-192` `offers()` 不生成该占位，`ready` 与排序虽一致，但缺“未拥有但可提示”的入口。
- `pb_fusion.gd:111` `fused_def()` 依据原型表构造；Web `Rw()` 以配方 key 派生，`status/type/class` 等字段尚未逐字段核对（**待确认**）。
- 修复：补 roster 报价；对 106 条配方写脚本逐条对比 `fused_def` 与 Web `Rw` 输出。

### 3.6 整块缺失的玩法系统（高）

| 系统 | Web 证据 | Godot 现状 |
|---|---|---|
| 物品获取/装备 | bundle 含 `items` 掉落、装备栏；`data/items.json` 151 条 | `pb_actor.gd:246` 定义 `give_item()`，全仓无调用点；`pb_run` 不掉物品、无商店 |
| 商店 | bundle `Tienda` 出现 | 无 |
| 宝可梦球捕获 | bundle `Poké Ball` | 无；`captures` 被改为“击杀即记录”（`pb_run.gd:367-370`） |
| 进化 | bundle `Evolución` | 无（`pb_data_registry.gd:125-135` 仅数据查询） |
| 维生素/糖果 | bundle `Vitamina` | 无 |
| 随机天气事件 | `.port/weather.out.json` 4 事件 | 无（见 §2.3） |
| 危险地形 | `.port/hazards.out.json` 4 类 + `byBiome` | 表未入库、代码未实现 |
| 研究计数 | profile 有 `research:{}`（`api-core.js:69`），由游戏侧累加 | Godot 在 `apply_run_result()` 内自增（Web api-core 无）；写入归属**待确认**（见 §4.1） |

修复优先级：捕获语义（直接导致图鉴进度错误）> 物品/商店（构筑闭环）> 天气/地形（关卡差异）> 进化/研究。

### 3.7 低影响数值差异

- `pb_stats.gd:110-116` 护甲分支阈值用 `1.0e17`；Web 为 `0xe8d4a51000`（= 999,999,999,999）。仅极端值可感知。
- `pb_moves.gd:206-230` 招式描述中用硬编码西语拼接（Web 用 i18n `{n}` 插值）。
- `pb_damage.gd:18-19` STAB/适应力常量与 Web 一致，无需改。

---

## 4. 状态与禁用条件

| 位置 | Web 判定 | Godot 实现 | 结论 |
|---|---|---|---|
| 升级三选一：reroll | 金币不足则禁用 | `pb_run.gd:447` + `run_screen.gd:659` | 一致 |
| skip | 始终可用 | `pb_run.gd:455` | 一致 |
| banish | 需要流放次数 | `pb_run.gd:465` + `run_screen.gd:677` | 一致（0 次时禁用） |
| 实验室购买 | 星尘 ≥ 10×(rank+1)，且未满级 | `save_service.gd:327-344`，`lab_screen.gd` | 一致（含“已满级”态） |
| 实验室货币文案 | 本地化“Polvo Estelar” | 硬编码混排“星尘 / Polvo estelar”“邦币 / Bonk” | 文案不一致（§5） |
| 融合按钮 | 需两招均 8 级、非 weather/buff/fusion | `pb_fusion.gd:69-74` | 一致 |
| 融合“无可融合”提示 | 有 roster 占位 | 无 | 缺反馈（§3.5） |
| 存档导入 | 校验 JSON + 版本 | `save_service.gd` `normalize()` | 多一层“未知键保留”，方向正确 |
| 图鉴未捕获态 | 灰显 + 未发现 silueta | `pokedex_screen.gd:102` `_tile(captured)` | 有；但 captured 语义错误（§3.6） |

### 4.1 存档互操作的状态缺陷（中）

1. `api-core.js:330-345` starter 选择后：
   ```js
   if (!Array.isArray(store.league)) store.league = [];
   store.league.push(id)
   ```
   Godot `save_service.gd:417-427` **没有写 league**。结果：新手关后 Web 存档 `league=[id]`，Godot 仍为 `league=1`。
2. `save_service.gd:240-241` 对 `league` 做 `int(store.get("league",1))`；若导入 Web 存档（`league` 为数组），`int(Array)` 在 GDScript 会报错/归零，**导入后升级计数可能被清零**。
3. `save_service.gd:260-318` `apply_run_result()` 额外写 `research[species] += 1`；Web `api-core.js:234-267` 没有该字段。会造成存档分叉。
4. `save-manager.js` 导出文件名走正则清洗；Godot 用空格→`-`，特殊字符未清洗。
5. 备份文件名 Godot 追加 `-%03d` 序号，列表里会显示为时间戳后缀；Web 无后缀。

修复：starter 写 `league` 数组；`normalize()` 把 `league` 统一为数组（或统一为计数）并在 `apply_actions` 读 `league` 时做类型分支；删除 `research` 自增或确认 Web 后续确实有该字段（**待确认**）；对齐导出文件名正则。

---

## 5. 提示文案与 i18n 缺口

### 5.1 结论

- Godot **没有任何翻译资源**：`project.godot` 无 `internationalization/locale/*`，源码无 `add_translation()`/`Translation`/`tr()` 调用。
- `App._detect_locale()` 直接 `return "zh"`（`src/autoload/app.gd:16,93-94`），语言选择器被注释掉。
- `App.t()`（`app.gd:97`）只查 `data/i18n` 的 6 段实体名称；**没有任何 UI 句子表**。
- 结果：界面主文案是**硬编码中文**，实体名/类型名/招式名是**西语**，少量 screens 标题是**中西混排**。

### 5.2 量化

| 指标 | 数值 |
|---|---|
| Web UI 语言键（zh） | 5225 |
| Godot 已接线 UI 键 | 0 |
| `src/**/*.gd` 唯一中文字面量 | 272 |
| 含重音西语字面量 | 21（另有 `pb_moves.describe`、`pb_cards._label`、`pb_run` 的无重音西语句） |
| `App.t()` 调用点 | 6 |
| `localized_name()` 调用点 | 2 |
| 完全未调用本地化的界面 | Pokedex、Fusion、Lab、Save（4 屏，`App.t()` 调用数 = 0） |

### 5.3 典型证据

- `src/ui/pokedex_screen.gd:134-208` 详情页使用 `species.get("name")`、`species.get("flavor")`（西语），0 次 `App.t`。
- `src/ui/lab_screen.gd` 使用“研究所 / 升级 / %s 已满级 / 星尘不足”等硬编码中文，并直接拼“星尘 / Polvo estelar”混排。
- `src/ui/save_screen.gd` 使用“账号 / 存档 / 备份 / 导出 / 导入”等硬编码中文。
- `src/ui/run_screen.gd:603-613` 稀有度标签 `_rar_name()` 硬编码中文；卡片标签 `pb_cards.gd:226` 返回西语（如 “Daño”“PS máx.”）。
- `src/core/pb_run.gd:189` 复活提示硬编码中文，Web 走 `c()` 本地化。
- `power‑up / fusions / weather` 的 HUD 文本中西混排（`hud_layer.gd`）。

### 5.4 修复建议（具体）

1. 把 `.port/locale_zh/zht/en.out.json` 提升为受版本控制数据：`data/i18n/ui/<lang>.json`（扁平 `key → 文案`）。**注意 Web 的 key 是西班牙语原文**（`c("Daño")`），zh 表按原文映射；因此 Godot 现有的西语字面量可以直接作为 key 复用，无需重新命名。
2. 在 `App` 中实现 `ui(key, vars)`：查找 UI 表 → 插值 → 回退 `data/i18n`；再逐步替换 272 条中文字面量。
3. 为 Pokedex/Fusion/Lab/Save 接入 `App.t("pokemon"|"moves"|"items"|"abilities", id)`；图鉴详情页 `flavor` 优先 `i18n.flavor[id]`，151 之外再回落西语。
4. 统一 `type_label()` 走 i18n（当前 `pb_data_registry.gd:180` 用西语 `types.names`）。
5. 建立 lint：禁止 `src/ui/**` 出现 CJK 字面量（除测试），CI 统计硬编码数从 272 降到 0。

---

## 6. 资源引用

| 项 | 结论 | 证据 | 修复 |
|---|---|---|---|
| PMD/立绘 | **54/1025 物种**同时缺 `assets/pmd/<id>.png` 与 `assets/portraits/<id>.png`；Godot 回退为纯色方块（`pb_visuals.gd:69-76,35-46`） | `data/sprites.json` 的 `fallback` 指向 `front/<id>.png`，Godot 从不读该字段；`pokebonk-re/public/assets/front` 恰有这 54 张 | 复制 `re/public/assets/front/*.png` 到 `assets/portraits/`，并让 `front_texture()` 先试 `portraits` → `front` → 色块 |
| 叫声 | 只有 `cry_template.wav`；Web 按物种播放 `.ogg` | `audio_service.gd:73-88` 无论 species 都播模板 | 引入按 id 的 `cries/<id>.ogg` 映射；缺文件回退模板并记日志 |
| BGM | `assets/music` 有 7 首 OGG（`menu/boss/ingame1-4/halloween-menu`），但 `play_music()` 仅映射 `menu`→`assets/audio/music/menu_theme.wav`，其余全部 `_`；两套目录并存 | `audio_service.gd:43-66` | 按场景/阶段映射 `ingame*`、`boss`、`halloween-menu`；统一到单一音频目录 |
| 物品图标 | 158 PNG（items 151 + 7 额外） | `assets/items/` | 无需改，注意 7 个额外图标映射 |
| 类型/UI 图标 | `assets/icons` 1025 张 PNG（含 `.import` 共 2050 文件） | — | 无需改 |
| 名称映射 | `sprites.json` 与 Web 一致；Godot 用 `pmd` 目录，Web 用 `sprites.json` 的帧表 | `pb_visuals.gd:47-68` | 保留；仅补本节所述缺图 |

> 只记录，不重做资源。54 个缺失 id 可由 `python` 对比 `data/sprites.json` 与 `assets/portraits` 实时生成，避免硬编码列表。

---

## 7. 存档与状态管理

| 维度 | Web | Godot | 结论 |
|---|---|---|---|
| 存储 | localStorage `pb.offline.profile` + 备份 | 同名 key + 文件备份 5 份 | 对齐 |
| 默认 profile | `api-core.js:56-110` | `save_service.gd:55-110` | 字段一致 |
| 周期 | 7 日，起止 ISO | 同 | 一致 |
| 规范化 | `normalize` 合并默认 | `normalize()` 保留未知键 | 方向一致 |
| 运行结算 | `api-core.js:234-267` | `save_service.gd:260-318` | **多写 research**（§4.1） |
| 新手选择 | 写 `league` 数组 | 不写 | **缺**（§4.1） |
| 导入 Web 存档 | `league` 可为数组 | `int(Array)` 风险 | **不兼容**（§4.1） |
| 导出 | 正则清洗文件名 | 仅空格替换 | 低 |
| 备份 | 时间戳 | 时间戳 + 序号 | 低 |
| 令牌/构建号 | `mvlr7rzv/0.8.34` | `port_meta` 固定值 | 低，仅展示 |

> 内存状态机（run state）字段对照：`pb_run.gd:22-70` 覆盖 `stage/time/gold/xp/orbs/offers/weather/diff`；Web run 还维护 `items`、`quests`、`squad/party`、`siege`、`npc`、`shop`。Godot 的 `items` 仅有容器无内容，属结构缺失而非字段错位。

---

## 8. 启动与初始化顺序

### 8.1 Godot

`project.godot:19-24`：

```
PbData → Save → Audio → App（主场景 res://scenes/MainMenu.tscn）
```

- `PbData._ready()` 只建立索引/清缓存（`pb_data_registry.gd:22`），JSON 按需懒加载。
- `Save._ready()` 立即 `load_profile()`（`save_service.gd:24`）。
- `App._ready()` 固定 `zh`、应用主题/背景（`app.gd:30-60`），不注册任何翻译。
- `Audio._ready()` 预建模板音（`audio_service.gd:23`）。

### 8.2 Web

`index.html` → `offline-fetch.js` 安装离线 `fetch`/`localStorage` 适配层 → `api-core.js` 提供存档 API → 语言包在运行时按 `locale` 选择 → 启动游戏循环。数据走 `fetch` 并发加载。

### 8.3 顺序差异导致的行为

1. **语言在启动即固定**：Web 可运行中切换语言并即时重绘；Godot 若未来要切换，需要重建所有硬编码文案（因为没有 key）。
2. **数据加载时机**：Web 是异步并发，缺表会显式报错；Godot 懒加载 + `push_error` 后继续（`pb_data_registry.gd:258-264`），可能带着空表跑。
3. **存档先于主题**：Godot 主题在 `App._ready()` 读 `Save.store`；由于 autoload 顺序正确，目前无竞态；但若以后把 `App` 调到 `Save` 前会读到空 profile，建议在 `App._ready()` 里 `await get_tree().process_frame` 或显式依赖检查。
4. **天气初始化**：`pb_run.gd:48` 固定 `clear`，之后无赋值点 → 见 §2.3。

---

## 9. 修复清单（按优先级 / 可执行）

### P0（高，先做）

1. **补受击链**：`PbActor.damage()` → `incoming_to_player()`，实现 overheal→shield→thorns→contact 顺序；补齐 `strike()` 的能力/道具/无尽/Boss 乘区。文件：`src/core/pb_damage.gd:164-271`、`src/core/pb_actor.gd:229`。
2. **捕获语义**：把 `pb_run.gd:367-370` 的“击杀即 captures”改为独立的“宝可梦球捕获”事件；图鉴 `captured` 只读真实捕获。文件：`pb_run.gd`、`pokedex_screen.gd:102`。
3. **天气事件 + 危险地形**：新增 `data/pb/weather_events.json`（源自 `.port/weather.out.json`）、`data/pb/hazards.json`（源自 `.port/hazards.out.json`）；在 `pb_run.tick` 实现事件/地形效果与 `pool` 刷怪。
4. **UI i18n 接线**：导入 `.port/locale_*.out.json` → `data/i18n/ui/*.json`；实现 `App.ui(key, vars)`；替换 272 条硬编码中文。文件：`app.gd:97`、`ui/*.gd`。
5. **数值反编译**：把 `pb_run/pb_enemies/pb_cards/pb_status/save_service:lab_deltas/pb_actor:GROWTH` 的估计值集中到 `data/pb/run_tuning.json`，逐项对照 Web 常量或标记 `unrecovered`。

### P1（中）

6. 融合 roster 占位报价 + `fused_def` 106 条逐条核对（`pb_fusion.gd:111-192`）。
7. 存档：starter 写 league 数组；`league` 类型兼容；删除/确认 `research`（`save_service.gd:240,260-318,417-427`）。
8. 资源：补 54 张立绘；`front_texture()` 读 `fallback`；按 id 接入叫声；`play_music` 映射 ingame/boss。
9. 图鉴/融合/实验室/存档四屏接入 `App.t`；`type_label()` 走 i18n。
10. 物品获取闭环：掉落/商店/装备（或明确删除 `give_item()` 与 `items` 容器，避免“看似有系统”）。

### P2（低）

11. `armor_mitigation` 阈值对齐 `0xe8d4a51000`。
12. 恢复 `weather.fog.name = "Niebla espectral"`。
13. 导出文件名正则、备份命名、令牌/build 展示。
14. `types` i18n 多出的 1 个键确认用途。

---

## 10. 待确认（未臆造）

以下无法从 bundle 静态恢复，需运行时抓取或对 Web 做黑盒测量：

- 野怪 `ft()/an()` 的真实 HP/伤害表与成长曲线。
- 关卡时长（`STAGE_TIME`）与关卡总数（`STAGES`）的 Web 真值。
- 卡片池的真实权重与数值区间。
- 实验室各条目的真实加成量。
- 异常状态完整时长/DPS 表（Godot `VERIFIED` 只覆盖一部分）。
- 无尽模式经验曲线与 `siegeMult` 具体值。
- `fused_def()` 与 Web `Rw()` 在 106 条配方上的字段级一致性。
- 存档 `research` 字段是否为 Web 的后续版本字段。

---

## 附录 A：本报告涉及的主要文件

- Godot 规则：`src/core/pb_damage.gd`、`pb_stats.gd`、`pb_moves.gd`、`pb_status.gd`、`pb_xp.gd`、`pb_actor.gd`、`pb_enemies.gd`、`pb_cards.gd`、`pb_fusion.gd`、`pb_weather.gd`、`pb_run.gd`
- Godot 状态/界面：`src/autoload/app.gd`、`save_service.gd`、`audio_service.gd`、`src/ui/*.gd`
- Godot 数据：`data/*.json`、`data/i18n/*.json`、`data/pb/*.json`、`.port/*.out.json`（仅本机、被 gitignore）
- Web 真值：`data/*.json`、`api-core.js`、`save-manager.js`、`assets/main-C5MieX6g-mvpjh5lt.js`

## 附录 B：建议加入 CI 的自动检查

1. `data/*.json` 与 Web 做 md5 对比（防止再次漂移）。
2. `data/pb/*.json` 与 `.port/*.out.json` 的重叠键值 diff（当前发现 weather 抽错表）。
3. `src/ui/**/*.gd` 禁止 CJK 字面量（白名单除外）。
4. `sprites.json` × `assets/portraits` 集合差必须为 0。
5. `pb_run` 中所有 `estimated` 注释数量上限（防扩张）。
