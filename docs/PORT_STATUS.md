# PokéBonk → Godot 移植状态

来源：`pokebonk-web`（离线抓取版，站点 build `mvpt1dlr` / 版本 `0.8.59`，逻辑包 `assets/main-C5MieX6g-mvpjh5lt.js`）
目标：`godot-pokebonk`（Godot 4.7）
移植工具链：`pokebonk-web/tools-re/`（可重跑，见文末）

## 验证

```bash
./scripts/verify.sh            # 导入编译 + 无头断言套件 + 六个场景真实渲染启动
```

当前结果：**465 项断言 0 失败**，`MainMenu / Pokedex / Lab / FusionMachine / SaveManager / Run` 全部零错误启动。
断言套件在 `test/smoke_test.gd`，其中公式部分不是自证：它比对 `data/pb/golden_values.json`，该文件由
`tools-re/golden_values.py` 用**独立的 Python 实现**按同样的逆向公式算出（双实现互验）。
无头模拟对局（`PbRun.simulate`）实测：约 83 秒阵亡、仍在第 1 阶段（Web 关卡无固定计时，守卫在 600 s 里程碑唤醒；生存曲线仍需对齐）。

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
python3 extract_ui_tokens.py                   # data/pb/ui_theme.json（CSS 变量/组件规则/keyframes/稀有度/危险计表）
```

## 1:1 复刻补齐（UI/交互/反馈，按差异清单编号）

以 `pokebonk-web` 为唯一权威参考，UI 全部走 `data/pb/ui_theme.json` 设计 token（`extract_ui_tokens.py`
从打包 CSS/JS 抽取的 `:root` 变量、`.hud-*/.card/.btn/.seg/.switch/.dx-*/.lab-*/.mm-*` 组件规则、
33 条 `@keyframes`、稀有度表 `nD`@1386869 / `Ke`@news54781、危险计 `dH/fH/pH`@2122027），
`src/ui/pb_theme.gd` 做 CSS 解析（var/color-mix/box-shadow/linear-gradient/animation），
`src/ui/pb_widgets.gd` 提供 StyleBoxFlat 表达不了的控件（渐变+条纹 GradRect、conic 冷却环、开关、XP 环）。

| 编号 | 已补齐 | 落点 |
|---|---|---|
| #1 | Run HUD 一比一重建：hud-top（ht-l 生态/阶段 pips/天气、ht-c 精灵球计时器+7 段危险计+金币钱包、ht-r 时钟）、hud-tl（xp 环勋章+名牌+属性+生命+多层 hpbar 含红残影/护盾/文字+pw-row）、hud-bl（融合 conic 环+击杀计数+kgoal 目标卡）、bossbar、banner、toasts | `src/ui/hud_layer.gd` |
| #2 | 升级三选一改为 `.card.offer` 卡片：稀有度/属性顶带渐变+条纹+徽章、[1][2][3] 键位、offerIn 错峰、hover 抬升、reroll/skip/banish 计数禁用、放逐两击确认、buildMini 招式行、结算卡片化 | `run_screen.gd` + `UI.card_offer` |
| #3 | 屏公共外壳：`.scr-head`（返回胶囊+kbd Esc+斜切条纹 `.scr-title`）、`.seg/.pill.on` 分段、`.switch`、`.field`、toasts 顶部堆叠、屏内入场动画 | 四屏 + `ui_kit.gd` |
| #4 | 主题 token 管线扩展 + 深色模式（`PbTheme.set_mode`，`App.set_theme_mode`，设置里深色开关） | `pb_theme.gd`/`app.gd` |
| #5 | 主菜单二级导航改 `.mm-item` 磁贴（`.mm-ic` 图标块+标题/副标题+分类色底边+hover） | `main_menu.gd` + `UI.mm_tile` |
| #6 | 研究所改 `.lab-card`（渐变顶带、等级/价格胶囊随余额 `.kind.price.ok/.no` 变色、tileIn 错峰） | `lab_screen.gd` |
| #7 | 反馈/音效：按钮 hover 音、卡片选择/拒绝音、阶段 banner、低血 pulse、危险计升档提示 | 各屏 + `audio_service.gd` |
| #8 | 玩法补齐：Revivir Máximo（`@848700` 死亡顺序：复活→60% HP+3s 无敌）、危险计（估计倍率，`TODO(reverse)`）、kgoal 首领倒计时/血条、pw-row 增益摘要 | `pb_actor/pb_run/hud_layer` |

### 无法 1:1 的近似（差异登记）

| Web 效果 | Godot 限制 | 采用的近似 | 后续逼近 |
|---|---|---|---|
| `.btn/.card .top` 垂直/135° 渐变 | StyleBoxFlat 无渐变 | `GradRect` 用 `draw_polygon` 逐顶点色插值沿 CSS 角度铺（首帧确定，不用 GradientTexture 异步） | 需要曲线渐变时上 shader |
| `.btn:after` `--stripes` 斜纹 | 无 background-image | 生成 20px 斜纹 tile（`PbTheme.stripes()` 参数）+ `texture_repeat` 叠加 | 已按 token 参数化，接近 |
| `box-shadow` 双层/`0 0 0 4px` 环 | Godot 单层 shadow | 主层→`shadow_*`，spread 环/`0 4px 0` 底边→border 折叠 | 需要精确投影再上 shadow shader |
| `.card:hover translateY(-4px) scale(1.05)` | Control 无内建 hover transform | `mouse_entered/exited` + Tween scale（pivot 居中）；容器内 position 由布局接管故只做 scale | — |
| `.scr-title/.banner h1/.modal h1` `skew(-8deg)` | Control 不能剪切 canvas transform | 底板 `rotation(-8deg)`+子节点反旋，保留倾斜观感 | 需要真斜切用 shader |
| `.ult-ring/.tl-ring` conic-gradient | 无 CSS conic | `draw_polygon`/`draw_arc` 扇形逼近，颜色取 `.ult.ready`/`.tl-ring` token | 锯齿明显改 shader |
| `backdrop-filter blur`（`.modal.sm-modal`） | 需环境采样 | 半透明径向遮罩 `.screen.dim` 近似，未做全屏 blur | BackBufferCopy+blur shader |
| 精灵球价 `.wl-ball`、商店/事件 Meowth、小地图 openMap、联机/协作/任务/排行 | 属未迁移的服务器玩法 | 结构位保留但默认隐藏（与 Web 无数据时一致），不静默造数 | 见上「无法从远端拉取的部分」 |

数据侧仅新增/重跑 `data/pb/ui_theme.json`（提取器产物）；`data/*.json` 与既有 `data/pb/*.json`
数值零改动；升级卡 `rarity` 为按幅度估计并标注，遵循本文「档位幅度为估计」的既有纪律。

## 参考源切换到 pokebonk-re：地图地形 1:1（本轮）

`pokebonk-web` 是**部分抓取**（83 个 asset 文件、`assets/env` 只有 5 个群系且缺 atlas.json、
无真鸣声/音乐/道具模型），而 `pokebonk-re` 是**完整离线镜像**（4.4k 文件、13 个 env 包、
1025 鸣声、7 首音乐、61 个真 .glb、zh/zht/ru 语言包）。所以地形/世界系统改以 re 为权威源，
`tools/extract_world.py` + `tools/terrain_reference.mjs` 都从它读取。

### 1) 世界数据表（`tools/extract_world.py` → `data/pb/world_*.json`）

| 表 | 内容 | 出处（bundle `main-CPuTGAQ--mvlr7rzv.js`） |
|---|---|---|
| `world_biomes.json` | 6 群系：size/relief/water/sky/fogNear-Far/light/sun/hemiGround/ground[4]/path/cliff[3]/tex/sanctuary/music/**zones**（每区 sunDir/sunH/tint/clouds/cover/glow/stars/motes）+ 中/繁/英译名 | news chunk 偏移 0（`var a=[{id:\`forest\`…`），译名来自 `zh-*/zht-*/en-*.js` 语言包 |
| `world_props.json` | 11 个包的 trees/big/small/landmarks（name/scale/sway/collider/shadow，`model:` 覆盖为真 .glb 名）+ 每包 `atlas.json` 精灵矩形 | 182615（`au={forest:…}`，含 `ou`/`su` 构造器） |
| `world_palettes.json` | 悬崖/地面 toon 调色板（a/b/light/dark/ink/mossA/mossB/moss/band/block/shore/ground）+ `_d()` 地面细节映射 | 205316–206830 |
| `world_fx.json` | 天气 look 表（fog/storm/eclipse/meowth 的 top/bottom/fog/near/far/light/sun/clouds/cover/eclipse/vignette/tint + 刷怪池）与危险地形（mud/bramble/quicksand/fire + 群系映射） | 1017153（`cb`）、1311745（`bw`/`xw`） |
| `world_constants.json` | Qu=1.12 网格、$u=4.6 阶地、Iu=13.5 像素网格、td/nd/rd/id/ad/od、地标半径、RNG/simplex 说明 | 214307、205317、131470、181841 |

### 2) 地形生成器 1:1（`src/core/`）

* `pb_js_rng.gd`＝`Ol`（mulberry32，逐位一致，seed 0 的回退值也一致）
* `pb_simplex.gd`＝`iu`（2D simplex：shuffle 建 perm、F2/G2、8 梯度、`fbm` 归一化）
* `pb_terrain.gd`＝`cd` 的开放世界路径：随机游走山谷 → massif 台地 → 阶地量化 → 池塘选址/挖掘
  → 高度格 → 3×3 平滑 → `connect_plateaus` BFS + `carve_ramp` → 水位/熔岩/冰 → 地标（grove/fairy/arch/
  hollow/meadow/boulders/pond）→ 植被散布（`placeEnv` 的拒绝采样、flip、collider）→ `shadeTex` 阴影遮罩
  → `cliffAttribs` 崖顶/崖底属性
* `pb_world_view.gd` + `pb_terrain/pb_props/pb_water.gdshader`：把上面全部数据画出来——
  13.5 px/m 像素网格的 toon 地面（草/沙/雪/滩纹理化绘制、黏土块岩壁 + 苔藓 + 墨线 + bayer 抖动、
  小径遮罩、水线沙滩、烘焙草影、雾）、atlas 圆柱公告板植被（风摆量化到整像素、遮挡玩家的抖动淡出、
  椭圆假阴影）、水/冰/熔岩（涟漪/裂纹/闪光）、群系天空渐变与光照。
* Run 场景改为按 **run 自己的 seed+biome** 生成世界，玩家/敌人/经验球贴地面高度，
  移动受 `hit_prop` 碰撞体阻挡（斜向撞墙时沿未阻挡轴滑动）。

### 3) 平价验证（不是自证）

`tools/terrain_reference.mjs` 把 bundle 里的**真实地形类**切出来在 Node 里跑（用 Proxy 桩掉
three.js 依赖），`tools/build_terrain_golden.py` 生成 `data/pb/terrain_golden.json`
（6 群系 × seed 0/2026/1987654321：17×17 高度采样、massifs/ponds/landmarks、colliders、
前 10 + 后 10 个 props 的 name/x/y/z/flip/s、probes 计数、ramps 与 lattice 校验和）。
`tools/probe_terrain.gd` 全量比对，`SmokeTest` 里常驻 graveyard/2026 的逐值比对。

**结果：18 个世界里 15 个逐值一致**（desert/coast/glacier/graveyard/volcano 全部 0 偏差，
props 顺序/坐标/flip 也一致）。只有 forest（唯一有 relief 的群系）有偏差：
massifs/ponds/landmarks/ramps 与 `connect_plateaus` 的总削方量完全一致，但高度格校验和差 ~0.001 m/格，
局部采样最大 ~0.9 m，props 数差 <2%。原因定位在浮点差异被阶地量化放大（`Math.hypot` 与
`sqrt(x²+z²)`、libm 的 sin/cos 末位差异），不是逻辑差异——`latticePre` 的差值与 `lattice` 完全相同，
说明差异发生在 `connect_plateaus` 之前。要抹平需要逐位复刻 JS 的 double 运算路径（或把生成搬到
GDExtension/C++），当前按"结构一致 + 记录偏差"处理，未静默放过。

### 4) 资源缺口关闭（re 直接搬）

`assets/env/` 12 包（atlas.json + atlas/ground/cliff/path）+ `env/common/`（atlas + hazards）；
`assets/cries/` 1025 真鸣声（25/808/809 上游是 .ogg 命名的 MP3，用 ffmpeg 转成 .wav）；
`assets/music/` 7 首（menu/boss/ingame1-4/halloween-menu）；`assets/models/` 61 个真 .glb
（web 仓库里那 17 个坏文件由它们替换，全部通过 glTF 结构校验）；`assets/pmd`/`portraits` 151→971、
`items` 63→158、`icons` 新增 1025、`ui/` 头像/框/军衔/属性图标。
`data/pb/missing_remote_assets.json` 已逐条改写状态。

### 5) 已知未完成（诚实记录）

| 项 | 状态 |
|---|---|
| 圣所/塔竞技场布局（`generateArena`/`generateTower`/`placeArenaEnv` + `QS/oC/gC/TC` 表） | 未移植：布局表依赖 `qS`/`ou` 等构造器，需要扩 `terrain_reference.mjs`；Run 仍是开放世界 |
| `Au`/`ju` 程序化贴图（tSand 等） | 未移植：先用群系 `path.png` 顶替 shore/path，视觉差在水线带 |
| 天气/区域的 `look` 混合、motes（落叶/萤火/雪）、云、暗角、危险地形（泥潭/火焰…） | 数据已入表（`world_fx.json`），渲染只接了群系自身 look，未接区域/天气切换与粒子 |
| forest 的浮点级平价 | 见上，`TODO(reverse)` |
| 生成耗时 | forest 约 6.7 s、其余 1.8–3 s（GDScript 单线程），后续可后台预生成或下沉到 GDExtension |

## 界面 1:1 第一轮：主菜单按 re 实机重建

参考源改为**跑起来的 re 镜像**（`node server.mjs` → 127.0.0.1:8080，v0.8.34），逐屏截图 +
`getComputedStyle` 取真实值，而不是读压缩 CSS 猜。取到的关键事实：
`--paper:#fff`、`--ink:#2a2440`、`--radius:22px`、`--stripes: repeating-linear-gradient(-45deg,#ffffff24 0 10px,#fff0 10px 20px)`、
`--font-title:"M PLUS Rounded 1c"`、body 字体带 CJK 回退、`.btn` 是 `linear-gradient(180deg,#ff787c,#ff5a5f 60%,#e0303e)`
+ `0 4px 0` 硬底边 + hover `scale(1.02) translateY(-2)`、`.seg` 底槽 `#f3f1fa` + inset 阴影 + `skewX(3°)`。

`src/ui/main_menu.gd` 按实机结构重排（不再是三栏仪表盘）：

| 区域 | 对齐点 |
|---|---|
| 左上浮动 pill | 语言（点击循环 9 语言）+ 全屏 |
| 右上 `.trainer` | 头像（`assets/portraits/<dex>.png`）+ 名字 + `N 场对局 · M 个家族已捕获` + 星尘/图鉴胶囊 + 存入账号/退出 |
| wordmark | `PokéBonk` 58px 标题字体 + `BETA v0.8.34` 胶囊 |
| `.mm-item.play` | 整宽红色渐变 + 斜纹（GradRect，StyleBoxFlat 表达不了渐变）、图标块、标题/副标题、右侧当前伙伴 PMD |
| `.mm-item` ×4 | 生存 / 合作 / 活动 / 委托 两列 |
| `.mm-item.tile` ×5 | 竖排小磁贴：图鉴 151/151、研究所、成就 0/228、排行、氏族 |
| `.mm-item.mini` | 设置 / 反馈 / Discord / 开发者 |
| 右侧赛季卡 | 橙色斜纹渐变头 + 分段（击败/生存/竞速/氏族）+ 全球下拉 + 空状态 + `你的赛季` + 奖励阶梯 + 按钮 |
| 页脚 | 非官方声明 + 移植来源 build/版本 |

设置与"当前伙伴派生值/招式"移入 `Ajustes` 弹窗（Web 也把它们放在设置屏，菜单本体保持与参考一致）。
未迁移的入口（生存/合作/活动/委托/成就/排行/氏族/反馈）逐个 toast 说明原因，不做假按钮。

顺带修的通用 bug：`UI.mm_tile` 把内容行锚到按钮矩形并设 `SIZE_EXPAND_FILL` —— Button 不是
Container，之前磁贴在网格里会塌成最小宽度导致文字互相压叠（这条影响所有用 mm_tile 的屏）。

**验证**：`./scripts/verify.sh` → 506 项 0 失败，六屏零错误启动；`./scripts/shot.sh MainMenu` 与
`/tmp/web-04-menu.png`（re 实机）逐区对照。

## 语言：暂时只做中文（默认 zh，去掉语言切换）

* `App.DEFAULT_LOCALE = "zh"`，`_detect_locale()` 直接返回 zh（保留函数，日后要恢复切换只需把检测循环加回来）。
* 主菜单去掉语言 pill（只留全屏 pill），设置弹窗去掉「界面语言」分段；`_cycle_locale` / `_set_locale` 一并删除。
* 取名默认走 zh：`PbData.localized_name(kind, id, locale = "zh")`、`biome_label(id)` 与新增的 `biome_text(id, key)`
  按 `locale → zh → zht → es` 回退，所以表里的群系名/描述/区域名/危险地形名都出中文。
* 实机文案对齐：HUD 名牌改用图鉴中文名（妙蛙种子），`UI.type_chip` 用 zh 属性表（草/毒），
  `_biome_name` 用真表的区域名（青翠森林 / 紫苑塔 …），原来的短名表退化为兜底。
* 新增 SmokeTest「language: zh-only」段：locale 钉死、TranslationServer 为 zh、区域/种族名出中文、
  主菜单里不再有 LangPill。**515 项断言 0 失败**，六屏零错误启动。
