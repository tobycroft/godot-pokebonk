# Godot ↔ re：点击「开始」后的行为差异分析与 1:1 复刻计划

> 参考源：`pokebonk-re`（上游 Web 客户端 `build mvilprw2` 的逐字节镜像）+ `godot-pokebonk`（Godot 4.7 移植）。
> 所有结论锚定到具体文件与 bundle 偏移；本计划聚焦「点击开始后的显示」与「输入映射」。

---

## 0. 参考源定位

`pokebonk-re` 不是重新实现，而是上游 Web 客户端的镜像，玩法逻辑全在
`public/assets/main-D5OUVqGK-mvilprw2.js`（压缩包）。`godot-pokebonk` 是同一游戏的 Godot 移植，
`docs/PORT_STATUS.md` 已把**世界/地形**对齐到 re 实机，但 **Run（点击开始）表现层仍有缺口**。

---

## 1. 点击「开始」后的行为差异分析

### 1.1 流程差异

| 环节 | re（Web） | Godot（当前） | 影响显示 |
|---|---|---|---|
| 入口 | 主菜单 `Play` → **Liga / 地区选择屏** → 选伙伴 → 开始对局 | 磁贴「开始对局」**直接 `App.goto("run")`** | 否（流程取舍，阶段 3）|
| 默认 biome | 地区屏决定 | 硬编码 `lastBiome ?? "forest"` | 是（forest 地形生成阻塞，见 1.3）|
| 角色/怪物渲染 | 见 1.2 | 见 1.2 | **是（核心问题）** |
| 输入 | 见 §4 | 见 §4 | 是 |

### 1.2 资源加载 / 显示差异（"开始后无法正常显示"根因）

re bundle 定位结果：

- **re 的 PMD 精灵是 3D 公告板**（与 Godot 思路一致）：`this.mesh = new hr(o, this.material, r); this.mesh.frustumCulled = !1; this.mesh.renderOrder = 1`（`main-D5OUVqGK-mvilprw2.js:5636-5638`）。
- **re 的回退链**（行 58697-58701）：
  ```js
  i = O.sprites[e];
  Ks(i?.anims ? Ft(`pmd/${e}.png`)
             : Ft(i?.fallback ?? `front/${e}.png`), …)   // 无 anims → front/ 静态图
  ```
- **re 也尝试 `models/${e}.glb`**（行 7860/7875）——对宝可梦在上游同样是 404，re 与 Godot 都回退到 PMD。

对照 Godot（`src/core/pb_visuals.gd` 的 `avatar()`）：

1. `res://assets/models/<key>.glb` —— 实测 `assets/models/` 里**只有世界道具/首领**（altar/ball/boss/chest/nest … 61 个 `.glb`），**没有任何 `<species_key>.glb`**。此步对宝可梦恒为死路（与 re 一致，但注释误导）。
2. `PbVisuals.sheet()` → `res://assets/pmd/%d.png`，**无 `front/` 回退**。
3. 都没有 → 用 `color/height` 着色的方块。

具体偏差：

| # | 偏差 | 证据 | 表现 |
|---|---|---|---|
| **D1** | **Godot 怪物没有回退链** | `run_screen.gd` 的 `_enemy_nodes` 是裸 QuadMesh + StandardMaterial3D，仅贴 `pmd/<id>.png` | 缺 PMD 表/alpha 异常时敌人是**无贴图白块**；re 永远不出现白块 |
| **D2** | **Godot 缺 `front/` 静态回退** | re 行 58700 用 `front/${e}.png`；Godot `assets/` 下无 `front`，只有 `assets/portraits/`（151→971 静态正面图）| 无 anims 物种直接掉到色块；re 显示真实静态精灵 |
| **D3** | **玩家/敌人动画写死 idle** | `run_screen.gd` `anim := "walk" if absf(player.x - px) > 0.0 else "idle"`，而 `px == player.x` | 玩家走路不播动画 |

### 1.3 时序差异

`Run.tscn` 的 `_ready`：`_build_world → _build_hud → _start_run → _build_terrain`。
`PbTerrain.create` 对 forest 约 **6.7s**（GDScript 单线程），且在 `_start_run` 之后**同步阻塞**。
结果：点「开始」后画面空场数秒才出地形，易被误判为"无法正常显示"。

---

## 2. 需要对齐的功能点清单

**P0（显示，本次重点）**
- [ ] F1 `PbVisuals` 回退链对齐 re：`glb → pmd动画 → front静态图 → 色块`（新增 `front/`，即 `portraits/` 兜底）
- [ ] F2 敌人渲染复用与玩家**同一套** `avatar` 回退（消灭白块 D1）
- [ ] F3 修复玩家 walk/idle 判定（D3）
- [ ] F4 PMD 贴图 alpha/过滤正确（`.import` 透明 + 最近邻），截图核对
- [ ] F5 地形生成改为异步/延迟，避免「开始」后空场

**P1（输入，见 §4）**
- [ ] 对齐 re 热键：reroll=`F`、skip=`X`、banish=`B`、card=`1-3`、pause=`P`
- [ ] 确认并接入 re 的 `fusion/ult` 键（Godot 当前 `F=融合` 与 re `F=reroll` **冲突**）
- [ ] 接入 re 的 `aim`/`lock`（瞄准模式运行时切换）、`autoult`(`Y`)、`Space`(jump/dash)

**P2（流程，可选，较大）**
- [ ] Liga / 地区选择屏（re 在「开始」前有地区与伙伴选择；Godot 直进 forest）
- [ ] 结算屏 `Esc` 行为对齐 re 的 `back`

**已对齐（无需动）**
- 相机 rig：`pitch .45 / dist 9` ✓
- 刷怪导演 `credits/weight/MAX_SPAWNS_PER_SEC` ✓
- 类型克制、伤害管线、经验曲线、融合、复活、危险计（已按 golden 校验）✓

---

## 3. 角色与怪物资源加载与显示逻辑（重点）

### 3.1 目标逻辑（对齐 re 行 5638 / 58697-58701）

统一 `PbVisuals.avatar(species_id)` 出口，**玩家与敌人共用**：

```
1. res://assets/models/<key>.glb        // 真实模型（对宝可梦恒死路，re 同样 404，保留）
2. res://assets/pmd/<id>.png            // 有 anims → PMD 动画公告板（Nearest + Alpha）
3. res://assets/portraits/<id>.png      // 新增：= re 的 front/，静态非动画公告板
4. tinted BoxMesh                      // 仅当连静态图都缺失时的最后兜底
```

### 3.2 具体改动点

**(a) `pb_visuals.gd` 新增静态图回退（F1/F2）**
```gdscript
const FRONT_PATH := "res://assets/portraits/%d.png"
static func front_texture(species_id: int) -> Texture2D:
    var p := FRONT_PATH % species_id
    return load(p) if ResourceLoader.exists(p) else null
```
在 `avatar()` 第 2 步之后插入第 3 步：若 PMD 帧为 null 但 `front_texture` 非空 → 用正面图做静态公告板（不播动画）。

**(b) `run_screen.gd` 敌人渲染改写（消灭 D1）**
- 删除 `_build_world` 里手工造的 64 个裸 `MeshInstance3D`。
- 改为：敌人用轻量 Pool，每帧通过 `PbVisuals.avatar(species)` 取节点（或缓存每物种 billboard 材质）来贴图；缺失 PMD 时自动走 `front/`（静态）或色块，**绝不出现无贴图白块**。
- 保留"贴地高度 + scale + 按血量染色"逻辑，但染色只改 `albedo_color`，不覆盖已存在的 `albedo_texture`。

**(c) 修复玩家动画（D3）**
引入 `_last_px/_last_pz`，每帧：
```gdscript
var moved := absf(px - _last_px) > 1e-4 or absf(pz - _last_pz) > 1e-4
var anim := "walk" if moved else "idle"
_last_px = px; _last_pz = pz
```

**(d) 贴图 alpha/过滤（F4）**
确认 `assets/pmd/*.png.import` 启用透明、Nearest 过滤、视需要 Premult Alpha；与 UI 侧 `PmdSprite`（Nearest）一致。

**(e) 地形时序（F5）**
`_build_terrain()` 用 `call_deferred` 或后台线程，生成期间显示 loading 遮罩；`_render` 在地形未就绪时只画玩家+敌人（贴地高度回退 0）。

---

## 4. 输入事件与操作行为映射规则

re 真实键位（bundle `hi` 表 + `bi`，`main-D5OUVqGK-mvilprw2.js:443-461,478`）：

| 动作 | re 键 | Godot 当前 | 对齐决策 |
|---|---|---|---|
| 上/下/左/右 | `W/S/A/D` | `WASD` + 方向键 ✓ | 保留（额外支持方向键，兼容）|
| 暂停 | `P` | `P` ✓ | 保留 |
| 选卡 | `Digit1-4`(+`NumpadEnter`/`Enter`) | `1-3`(+`KP_1-3`) | 保留 1-3，补 `4`/`KP_4` |
| 融合/终极 | **`R`** (`ult`) | `F`=融合 ⚠️ | **改：融合→R（对齐 re）；F 让位给 reroll** |
| **刷新卡** | **`F`** (`reroll`) | `F`=融合 | **改：F→reroll（对齐 re）** |
| 跳过卡 | `X` (`skip`) | 无 | **新增 `X`→skip** |
| 放逐卡 | `Z` (`banish`) | 无 | **新增 `Z`→banish** |
| 瞄准模式 | `Q` (`aim`) | 仅设置里 `aimMode` | **新增 `Q`→运行时切换 auto/manual** |
| 锁定目标 | `Mouse2` (`lock`) | 无 | 鼠标右键，竞技场可选（暂未接入）|
| 自动终极 | `Y` (`autoult`) | 无 | 可选：对齐 `Y`（暂无 auto-ult 机制）|
| 跳跃/冲刺 | `Space`(`jump`)/`ShiftLeft`(`dash`) | 无 | 俯视竞技场可忽略，记录 |
| 交互/自动跑/地图 | `E`/`T`/`M` | 无 | web 专属（co-op/地图屏），竞技场暂未接入 |
| 返回/离开 | `Escape`→`back` | `Esc`=暂停/结算 | 对齐：对局中 `Esc` 优先暂停；结算屏 `Esc` 回菜单 ✓ |

> 注：re 默认键位取自 bundle `hi` 表（行 443‑461）。早期草稿曾误记 `banish=KeyB`、
> `fusion` 键未定位；已据 `hi` 校正为 **banish=Z、fusion/ult=R**。

**映射总纲**：移动 WASD∪方向键八向；模态态 `1-3` 选卡、`F` 刷新、`X` 跳过、`B` 放逐；非模态 `P`/`Esc` 暂停、`Y` 自动终极；融合待 re `ult` 键确认后绑定；`aim`/`lock` 运行时切换 `run.aimMode`。

---

## 5. 分阶段实施与验证

### 阶段 0 — 锁定 re 真机基线
- 起 re：`cd pokebonk-re && node server.mjs` → `127.0.0.1:8080`，实机点「开始对局」。
- 取证：Run 屏截图 `/tmp/re-run.png`；`getComputedStyle` 取 HUD 真实值；打印 re 实际键位（含被截断的 `ult`/`aim`/`lock`）。
- 验证：得到 re「开始后」视觉基线 + 键位表。

### 阶段 1 — 显示层对齐（F1–F5，本次重点）
1. `pb_visuals.gd`：加 `front_texture` + 第 3 步回退；`avatar()` 玩家/敌人共用。
2. `run_screen.gd`：敌人改用 `avatar` 回退（删裸 QuadMesh）；修玩家 walk/idle（D3）；`_build_terrain` 延迟+loading。
3. 校 `assets/pmd/*.png.import` 透明/Nearest。
- **验证 A（无头）**：扩展 `test/smoke_test.gd`：
  - `PbVisuals.avatar(id)` 对"有 glb / 有 pmd / 只有 front / 全无"四类返回正确 `avatar_kind`。
  - 敌人池每帧 `albedo_texture != null`（再不会白块）。
  - 玩家位移 > 阈值返回 `walk` 帧。
- **验证 B（视觉）**：`./scripts/shot.sh Run` 出 `godot-run.png`，与 `re-run.png` 逐区对照。重点：玩家是否显示、敌人是否显示且非白块、地形是否短时间出现。
- **验证 C（时序）**：forest 开局到首帧可交互 < 1s（地形异步）。

### 阶段 2 — 输入对齐（P1）
- 改 `_unhandled_input`：`F`→reroll、`X`→skip、`B`→banish、补 `4`/`KP_4`；确认 re fusion(`ult`) 键后绑定；接入 `aim`/`lock` 运行时切换。
- **验证**：无头单测模拟 `_unhandled_input` 事件 → 断言 reroll/skip/banish 正确、`aimMode` 翻转；实机逐项点一遍。

### 阶段 3 — 流程对齐（P2，可选/较大）
- 新增 Liga/地区选择屏（对齐「开始前」地区+伙伴选择），或至少在 `run_screen` 暴露 biome/伙伴选择入口。
- `Esc` 结算屏行为对齐 re 的 `back`。
- **验证**：截图对照 re 地区屏；`App.goto("run", {biome, species})` 路径断言。

### 阶段 4 — 全量 1:1 收口
- 跑 `./scripts/verify.sh`（当前 515+ 项 0 失败）→ 目标全屏零错误 + 显示/输入新断言全绿。
- 六屏（含 Run）实机截图与 re 逐区对照。
- **最终确认**：`git status` 干净、`git push` 已含全部改动、远程与本地一致。

---

## 6. 结论与优先序

1. "开始后无法正常显示"最可能根因：`pb_visuals.gd` 回退链缺口（**无 `front/` 静态兜底**）+ `run_screen.gd` **敌人裸 QuadMesh 无回退（白块 D1）** + **玩家动画写死 idle（D3）** + **forest 地形 6.7s 阻塞空场**。
2. 概念上 Godot 与 re 已对齐（"glb→PMD 公告板"），差异是 Godot 少一级 `front/` 回退、且敌人没复用回退链。
3. 输入侧存在明确冲突：`F` 在 Godot=融合、re=reroll；re 的 `X`/`B`/`ult`/`aim`/`lock` 在 Godot 缺失。
4. 下一步：先跑阶段 0 对照，确认 D1/D2/D3 中哪个导致实际"无法显示"，再动手改。
