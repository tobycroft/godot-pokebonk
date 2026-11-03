# PokéBonk → Godot 移植状态

来源：`pokebonk-web`（离线抓取版，站点 build `mvpt1dlr` / 版本 `0.8.59`，逻辑包 `assets/main-C5MieX6g-mvpjh5lt.js`）
目标：`godot-pokebonk`（Godot 4.7）
移植工具链：`pokebonk-web/tools-re/`（可重跑，见文末）

## 验证

```bash
./scripts/verify.sh            # 导入编译 + 无头断言套件 + 六个场景真实渲染启动
```

当前结果：**437 项断言 0 失败**，`MainMenu / Pokedex / Lab / FusionMachine / SaveManager / Run` 全部零错误启动。
断言套件在 `test/smoke_test.gd`，其中公式部分不是自证：它比对 `data/pb/golden_values.json`，该文件由
`tools-re/golden_values.py` 用**独立的 Python 实现**按同样的逆向公式算出（双实现互验）。
无头模拟对局（`PbRun.simulate`）实测：150 秒内 170 次击杀、等级 18、进入第 2 阶段。

操作：`WASD/方向键`移动 · `F`融合 · `P`暂停 · `1-3`选卡 · `Esc`结束本局/返回。

## 已迁移

### 数据（1:1 复制）
`types`(18+18×18 表)、`pokemon`(1025)、`moves`(919)、`abilities`(314)、`learnsets`(1025)、
`sprites`(1025 PMD 图集元数据)、`items`(151)、`i18n`(7 语言) → `res://data/`

### 资源
`pmd`151 · `portraits`151 · `items`63 · `ui/icons`+`ui/ranks`21 · `env`5 生物群系 ×4 贴图 ·
`models`17 glb · `music` · PWA `icons` → `res://assets/`、`res://icons/`
（406 张 PNG + 全部 JSON + 音频经 `tools-re/repair_glb.py` 逐个校验，结构完好的记录在
`data/pb/asset_repair_report.json`）

### 逆向出来的数值表与公式（`data/pb/` + 偏移坐标写在 `constants.json`）
| 系统 | bundle 偏移 | 移植位置 |
|---|---|---|
| 属性克制重映射（2×→1.35、免疫→0.5、0.5×→0.8、钳制 [0.4,1.8]） | 6232 | `PbDamage.effectiveness` |
| 能力值派生 `Qy`（BST 占比驱动 HP/护甲/闪避/移速/物特倍率/成长） | 812367 | `PbStats.stats_from_species` |
| 卡牌加成叠加 `$y()` + 钳制 `tb()`（mul≥1 合并、护甲/闪避/幸运上限） | 813284 | `PbStats.apply_mod_groups/finalize` |
| 护甲减伤 `armor/(armor+45)` | 813284 | `PbStats.armor_mitigation` |
| 伤害管线 `strike`（thick-club/STAB/属性加成/天气/超级有效/精英/binding-band/full-heal/scope/暴击+极暴/stick/诅咒/护幕/冰冻/睡眠/护盾） | 746724 | `PbDamage.strike` |
| 受击管线（克制钳制 .5–1.6、护甲、magic-guard、multiscale） | 846019 | `PbDamage.incoming_to_player` |
| 经验曲线 `Cb=round(8+L*5.5+L^1.8)` | 834827 | `PbXp` |
| 招式实例 `yA`（威力 1.3×、每级 +4%、STAB 1.25/1.5625、冷却下限、范围/穿透/弹跳、dps 估算 `bA`） | 1583829 | `PbDamage.move_instance/expected_use` |
| 招式→原型解析 `_y`（427 条覆盖表 + 13 条名称正则 + 属性默认对） | 789750 | `PbMoves.archetype_for` |
| 实时招式定义 `vy`（威力→伤害/冷却系数、状态与概率、吸取、会心、天气、增益） | 791717 | `PbMoves.resolve` |
| 自动招牌招式评分 `xy` / 进化链可学 `by` | 792596 | `PbMoves.best_move_for/learnable_moves` |
| 融合配方查询 `Uw`（签名→反应→同属性→故障）+ `JC` 融合招式 + `Gw/Kw` 执行 | 1113565, 1278535+ | `PbFusion` |
| 融合范围钳制 `My`、冷却下限 `ky/Ay`、极暴系数 `Iv` | 795862 | `PbDamage` 常量 |
| 26 个招式原型、类型→状态表、天气表（7 种，boost/nerf 1.3/0.75） | 773555, 745150, news chunk | `archetypes/type_status/weather.json` |
| 106 条融合：79 签名 + 18 同属性 + 8 反应 + 1 MissingNo.（含 power 覆盖与 cd×0.85 归一化） | 1278535 | `fusion_catalog.json` / `fusion_extras.json` |
| 18 张属性卡、5 个 TM 增益、经验/金币常量 | 541981, 338079 | `type_cards.json` / `tm_powerups.json` |
| 存档 profile（56 字段）、22 项研究所、行动类型、对局结算与星尘/邦币公式、实验室花费 `10*(rank+1)`、满解锁初始档 | `api-core.js` | `Save`（`handle()` 保留同名路由） |
| 导出/导入（容忍粘贴杂质）、5 份自动备份、恢复、summary | `save-manager.js` | `Save` |
| PMD 帧表布局（`y + facing*fh`、`b*fw`、d 为毫秒）、fallback 链 | 133475, 1386118 | `PbPmd` / `PbVisuals` |
| 相机（pitch .45 / dist 9）、horde 导演（credits/weight 上限、MAX_SPAWNS_PER_SEC） | 1506673, 346928 | `run_screen.gd` / `PbRun` |

### 场景
`MainMenu`（档案摘要、初始选择、设置：音乐/音效/瞄准模式/语言 → `PUT /profile/prefs`）、
`Pokedex`（世代过滤、种族值、实时派生值、可学招式解析）、`Lab`（22 项、走 `/lab/<id>/buy`）、
`FusionMachine`（106 条配方、`Gw` 同款就绪判定、用 `yA` 实时预览融合招式）、
`SaveManager`（导出/导入/备份/恢复/重置）、`Run`（3D 竞技场 + HUD + 升级三选一 + 重掷/跳过/禁用 + 融合 + 结算）。

## 无法从远端拉取的部分（已生成或占位，均有记录）

远程探测：`pokebonk.com` **TLS 握手被重置**（不可达）；`github.com/juzi123451/pokebonk-web` 可达，
但其 561 个文件的清单里根本没有这些资源，`assets/data/*.json` 在仓库中即为 0 字节（真实数据在仓库根的 `data/`，已复制）。

登记文件：`data/pb/missing_remote_assets.json`（逐条写明缺口、当前替代方案、TODO）、
`data/pb/asset_repair_report.json`（逐文件原始字节/状态）。

| 缺口 | 处理 |
|---|---|
| 151 个宝可梦 `.glb` 模型 | `PbVisuals.avatar` 三级回退：真模（放进 `assets/models/<key>.glb` 即生效）→ PMD billboard → 按 `color/height` 上色的方块 |
| 151 个 `.ogg` 鸣声 | 生成 `assets/audio/cries/cry_template.wav`，`AudioService.play_cry()` 按图鉴号确定性变调 |
| 关卡/Boss 音乐 | 生成 `assets/audio/music/menu_theme.wav` 循环；保留了唯一的真 `halloween-menu.ogg` |
| 17 个仓库自带 `.glb` 道具 | **仓库里就是坏的**（git 树干净＝远端同字节）：17 个都无法按声明长度修复 → 生成合法占位立方体；原始字节存于 `assets/models/_corrupted/*.bak` |
| `env/<biome>/atlas.json` | 无需替代：Godot 直接用 `ground/cliff/path/atlas.png`，Web 的 UV 区域描述符在 Godot 侧没有对应职责 |
| 网页字体 `.woff2` | Godot 不加载 WOFF2，使用内置字体；如需还原需先转 `.ttf/.otf` |
| 每招式 `cast/sfx` 的 JS 闭包（VFX/音效） | 无法转成数据：`fusion_recipes/fusion_catalog` 中保留 `{"__fn":true}` 标记；改由 26 个原型驱动通用表现 |
| 能力（ability）逐条 `dmgTaken/hitMul/cast` 闭包 | 仅移植可确证的数值分支（magic-guard 0.7、multiscale 0.5、adaptability 1.5625、beacon/venom-sting/… 条件），其余 `TODO(port)` |
| 敌人 HP/伤害表（`ft()`/`an()` 闭包） | 用 `8 + BST*0.06` × 已证实的阶段系数 `(1+(stage-1)*0.35)` 的标定替代，源码内标 `TODO(reverse)` |
| 状态持续时间/DoT 强度 | `PbStatus.DEFAULTS` 明示 `verified: false` 的估计值，已证实的受击倍名单独放 `PbStatus.VERIFIED` |
| 升级卡牌档位数值 | 结构（`{label, mods}`、每原型可升级项、属性卡数值）为真；档位幅度为估计并逐条打 `estimated: true` |
| 成长索引 `Qy` 的入参映射、无尽模式经验曲线 `Pn`、`labStats()` 每项幅度、模式塔/联机/协作/排行/邮件等服务器系统 | 明确标注为估计或不迁移（`PbXp.need_for_mode`、`Save.lab_deltas` 注释），非静默 |

## 重跑移植工具链

```bash
cd ../pokebonk-web/tools-re
python3 kw.py <bundle> <关键词>              # 在压缩包中定位实现点
python3 extract_literal.py <bundle> name=锚点  # 括号配平导出 JS 字面量
python3 jslit_to_json.py in.js.txt out.json   # JS 字面量 → JSON（函数体记为 {"__fn":true}）
python3 dump_tables.py && python3 dump_enclosing.py
python3 build_pb_data.py                      # data/pb/*.json（含常量+偏移出处）
python3 build_fusion_catalog.py               # 79 条签名融合（含 cd×0.85/power 归一化）
python3 build_fusion_extras.py                # 18 同属性 + 8 反应 + 1 MissingNo.
python3 golden_values.py                      # 公式平价用的期望值
python3 make_placeholders.py                  # 占位音频 + 缺口登记
python3 repair_glb.py                         # 资源体检 + glb 修复/占位 + 保留原始字节
```
