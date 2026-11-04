# PokéBonk Godot ↔ Web 视觉与交互对齐审计

> 审计对象：`/Users/tobycroft/godot/godot-pokebonk`（Godot 移植版）
> 权威基线：`/Users/tobycroft/Documents/GitHub/pokebonk-web`（Web 原版，Vite build）
> 审计日期：2026-11-04
> 本阶段只读：未修改 Godot 任何场景 / 脚本 / 资源 / 数据；本文件是唯一新增产物。

## 0. 方法与证据边界

- 设计 token 与组件真值来自 Web 构建产物：
  - `pokebonk-web/assets/main-oZVl1tJD-mvpjh5lt.css`（`ui_theme.json` 的 `_source` 同为此文件）
  - DOM 层级与组件组合来自 `pokebonk-web/assets/main-C5MieX6g-mvpjh5lt.js`（主菜单、图鉴、研究所、HUD 的实际建树代码）
- Godot 侧为静态代码审计：`src/ui/*.gd`、`src/autoload/app.gd`、`scenes/*.tscn`、`data/pb/ui_theme.json`。
- Web CSS 是压缩单行文件，因此“Web 出处”用 **文件 + 选择器** 定位；Godot 出处用 **文件:行号 + 节点/函数**。
- 未做逐帧截图对比。涉及 `clamp()` 响应式换算、运行时遮挡/滚动、浏览器合成效果（blur/backdrop-filter）的条目标 **待确认**，并给出验证方法。
- Web UI 使用西语，Godot 为中文；本地化文本差异不计入本报告，但“品牌名被改写”“新增移植说明/最近对局”等 **非本地化内容** 计入差异。

严重度定义：

| 级别 | 判定标准 |
| --- | --- |
| 高 | 首屏或主流程肉眼即见；影响可读性、可操作性、状态反馈或整体明暗关系 |
| 中 | 并排对比明显；影响局部质感、信息密度或交互一致性 |
| 低 | token 级偏差、边角动效或特定窗口尺寸才出现 |

---

## 1. Web 设计 token 真值表

### 1.1 颜色 token（`:root` / `[data-theme=dark]`）

| Token | Light | Dark | Godot 读取方式 |
| --- | --- | --- | --- |
| `--ink` | `#2a2440` | `#e7eaf6` | `PbTheme.ink()` |
| `--ink-2` | `#5a5478` | `#aeb6cc` | `PbTheme.v("--ink-2")` |
| `--ink-3` | `#4a4466` | `#c3c9dc` | 直接 `v()` |
| `--muted` | `#7a7494` | `#8d97b3` | `PbTheme.ink_muted()` |
| `--paper` | `#fff` | `#222839` | `PbTheme.paper(0)` |
| `--paper-2` | `#f3f1fa` | `#1a1f2e` | `PbTheme.paper(1)` |
| `--paper-3` | `#e6e2f2` | `#2e3650` | `PbTheme.paper(2)` |
| `--line` | `#e4e0f0` | `#333c56` | `v("--line")` |
| `--red` / `--red-d` | `#ff5a5f` / `#e0303e` | 同 | `accent_color("red")` |
| `--orange` | `#ff9a3a` | 同 | `accent_color("orange")` |
| `--yellow` | `#fc3` | 同 | `accent_color("yellow")` |
| `--blue` | `#3a8cff` | 同 | `accent_color("blue")` |
| `--green` | `#36c96a` | 同 | `accent_color("green")` |
| `--purple` | `#8a5cff` | 同 | `accent_color("purple")` |
| `--w92` | `#ffffffeb` | `#22283aeb` | `v("--w92")` |
| `--w96` | `#fffffff5` | `#22283af5` | `v("--w96")` |
| `--w97` | `#fffffff7` | `#22283af7` | `v("--w97")` |
| 页面底色 | `#1a1630`（`html,body`） | 同 | **Godot 无对应 token** |

关键结论：

- **Web 的页面底色是深色 `#1a1630`，即使在 light theme 也如此**；白色卡片浮在深底上。Godot 的 `PbBackdrop` 却以浅色纸张为底（见 H-01），这是整体观感最大偏差。
- 主题有 light/dark 两套完整 token，但 Godot 存在若干“写死 light 色”的节点，在 dark theme 下会破功（见 H-18）。

### 1.2 字体、字阶与行高

| Web 角色 | 选择器 | 字号 / 字重 / 字体 | Godot 对应 |
| --- | --- | --- | --- |
| 页面正文 | `html,body` | 16px / **700** / `Nunito` | Theme `Label` **15px / Nunito-800**（`pb_theme.gd:772-774`） |
| 按钮 | `button` + `.btn` | 17px / 800 / `M PLUS Rounded 1c` | `pb_theme.gd:775-777` 17px / 800 ✓ |
| 小按钮 | `.btn.small` | 13px / 800 / title | `UI.small_button` 13px ✓ |
| 大按钮 | `.btn.big` | 22px / 800 / title | 未见使用 |
| 主菜单 wordmark | `.mm-left .logo.hero .logo-word` | `clamp(72px,9.5vw,156px)` / 900，line-height .92；紧凑 `clamp(48px,9vh,70px)`（已更正） | `main_menu.gd:147` 按 vh 缩放（紧凑 48–70） |
| 页面标题 | `.scr-title` | 28px / 900 | `UI.screen_head` ✓ |
| 弹窗标题 | `.modal h1` | 40px / 900，padding 6px 34px，radius 16 | `UI.modal_title` 40px ✓ |
| Banner | `.banner h1` | `clamp(28px,4.2vw,54px)` / 900，padding 8px 40px | 固定 40px（`ui_kit.gd:458`） |
| 主菜单 tile 主标题 | `.mm-tx b` | 19px / 900 / title，line-height 1.15 | `UI.mm_tile` 19px / 900 ✓ |
| 主菜单 tile 副标题 | `.mm-tx small` | 12px / 800 / `Nunito` | `UI.mm_tile` 12px / body-800 ✓ |
| 卡片标题 | `.card h3` | 21px / 900 / title | `card_offer` 约 20-21px |
| 卡片副标题 | `.card .sub` | 13px / 800 | 约 13px |
| 卡片快捷键 | `.card .key` | 12px / 900 / title，padding 1px 8px，radius 8，白字 `--slate` 底 | `UI.card_offer` 1–4 键标（`run_screen.gd` 传入序号），H-16 已补齐 |
| 研究所名称 | `.lab-bd h3` | 18px / 900 / title | 15px / title（`lab_screen.gd:80`） |
| 研究所描述 | `.lab-bd p` | 13px / 700 | **缺失** |
| 研究所购买 | `.lab-buy` | 17px / 900 / title，padding 9，radius 999 | 17px / 800（`UI.button`） |
| 图鉴格号 | `.dx-tile small` | 10px / 900 | 10px / 900 ✓（但未补零） |
| 页脚法务 | `.mm-legal` | 10.5px / 700，max-width 980 | 11px / muted（`main_menu.gd:374`） |

### 1.3 圆角、阴影、边框、透明度

| Token / 组件 | Web 真值 | 备注 |
| --- | --- | --- |
| `--radius` | 22px | 卡片基准圆角 |
| `--shadow` | `0 10px 28px #1a124638, 0 2px 6px #1a12461f` | **双层** |
| `--shadow-sm` | `0 4px 12px #1a12462e` | 轻量层 |
| `.btn` 立体边 | `box-shadow: 0 4px 0 var(--cd), var(--shadow-sm)` | 4px 实边 + 软影 |
| `.card` | `background:var(--paper); border-radius:22px; box-shadow:var(--shadow)` | 无内边距 |
| `.card:hover` | `translateY(-4px) scale(1.05)` + 4px `--rc` 外环 + 抬升阴影 | 选择态靠外环 |
| `.mm-item` | `radius 18`；`transform: skew(-6deg)`；`box-shadow: 0 4px 0 #1a124633, var(--shadow-sm)`；左 7px 强调条（`::before`） | 斜面是主菜单的视觉签名 |
| `.mm-item.play` | `inset 0 0 0 4px #ffffffe6` + `0 6px #a81c2c` + `0 14px 30px #e0303e66` | 内白环 + 红色实边 + 红光 |
| `.mm-item.tile` | 纵向 flex；无固定高；底部 5px 强调条 | `--n` 控制标题字号 |
| `.mm-item.mini` | `radius 999`；`padding 5 18 5 5`；`mmPop` | 胶囊，不是普通卡片 |
| `.lab-card` | `radius 20`；`--shadow-sm`；hover 抬升 + **3px** 外环（已更正） | 顶栏 70px |
| `.lab-ic` | 54×54 白圆，`translateY(18px)`，`0 3px #00000026` | 压在色带上 |
| `.lab-lv` | 右上绝对定位胶囊，`--w92`，12px/900 | 等级/进度 |
| `.lab-buy` | 默认灰 `#b8b2cc`；可买绿渐变；满级黄渐变 | 语义化三态 |
| `.dx-tile` | `radius 16`；radial 类型色渐变；`inset 0 -3px #00000014` | 选中 `.on`：纸 3px + 黄 6px 环 + scale 1.08 |
| `.field` | `border:2px solid var(--line)`；`radius 999`；padding 12 18；bg `--paper-2` | 聚焦边框变蓝 |
| `.switch` | 58×32；off `#d4cfe6`；on `var(--c,--green)`；inset 阴影 | 24px 白色滑块 |
| `.hud-top` | `width:max-content`；**3 列**网格 `1fr auto 1fr`（已更正，不是 4 列）；radius 20；`--w96`；`--shadow`；padding 10 18 8 | 中央列在网格内 |
| `.tl-medal` | 108×108；conic 蓝→青进度环；外 3px 纸环 + `--shadow-sm` | `--p` 为百分比 |
| `.tl-plate` | `min-width:240`；margin `12 0 0 -34`；padding `8 26 9 46` | 与徽章重叠 34px |
| `.tl-lvl` | 底部 `-12px` 居中；`skew(-12deg)`；外 3px 纸环；上下双段渐变 | 旋转徽标 |
| `.bar` / `.hpbar` | 圆角 999；`--shadow` 内嵌；hpbar 高 14 | 盾/滞后层有 z-index |
| `.timer` | 30px/900；padding 3 24 4 46；radius 999；外 4px 纸环 | final 有脉冲 |
| `.minimap` | 212×212；外 4px 纸环 + 3px 红环 | `--mm` 可缩放 |
| `.bb-body` | radius 16；`border-bottom:4px solid var(--c)`；padding 6 16 8 30 | Boss 颜色下边 |
| `.kg-head` | `var(--stripes)` + 双段渐变；白色文字 + 文本阴影 | 标签是白底 `--kc` 字 |
| `.banner h1` / `.modal h1` | `display:inline-block`（贴合文字）+ skew(-8deg) | 不是通栏色带 |

### 1.4 布局与栅格

| Web | 真值 | Godot 现状 |
| --- | --- | --- |
| 页面边距 | `.screen` `padding:18px 24px 20px`；`.mm` gutter `clamp(22px,5vw,84px)` | `UI.content` 统一传 18/22（`ui_kit.gd:214`，`main_menu.gd:38`） |
| 主菜单左列 | `width:min(520px, 100vw - 2*gutter)`；绝对定位 `top:52%` + `translateY(-50%)` | 固定 `620px`（`main_menu.gd:163`），流式堆叠 |
| 主菜单右列 | `.mm-season` `width:clamp(340px,26vw,400px)`，`max-height:min(640px,100dvh-170px)` | 固定 `320px`（`main_menu.gd:278`），无高度上限 |
| 主菜单模式区 | `.mm-modes`：Play + `.mm-pair`（两个模式，纵向成对），高 `clamp(100px,14vh,124px)` | 2×2 网格 + 4 个独立模式 tile（`main_menu.gd:181-187`） |
| 今日区 | `.mm-today` `min-height:72px`（每日 + 委托两项） | **缺失** |
| 次级入口 | `.mm-tiles`：5 个纵向 tile（氏族/图鉴/研究所/成就/排行） | 5 个纵向 tile ✓ 数量，但尺寸/字号不同 |
| 迷你入口 | `.mm-small`：4 个 `.mm-item.mini` 胶囊 | 普通 `.mm-item` 66px 卡片（`main_menu.gd:200-205`） |
| 页脚 | `.mm-foot` 绝对 `bottom:10px`，白色 12px/800 + 文本阴影 | 内容流末尾，11px muted（`main_menu.gd:50,374`） |
| 图鉴格 | `.dx-grid` `repeat(auto-fill,minmax(84px,1fr))`，gap 8，padding 6 4 | 固定 5 列（`pokedex_screen.gd:51`） |
| 研究所格 | `.lab-grid` `repeat(auto-fill,minmax(230px,1fr))`，gap 12 | 固定 3 列（`lab_screen.gd:28`） |
| 屏幕切换 | `.screen` `animation:fadeIn .25s`；HUD 有 `.fade` 0.45s | `App.goto` 直接 `change_scene_to_file`（`app.gd:101-107`） |

### 1.5 动效 token

| 场景 | Web | Godot |
| --- | --- | --- |
| 主菜单入场 | `mmIn .5s cubic-bezier(.2,1.3,.4,1)`，逐项 `--d` 80ms 递增 | **无** |
| 主菜单迷你 tile | `mmPop` | **无** |
| 卡片入场 | `cardIn .35s ease-out` | `anim_in_simple` 0.3s EASE_OUT |
| Offer 入场 | `offerIn .3s cubic-bezier(.2,1.5,.4,1)` 50ms 递增 | 0.3s EASE_OUT + 60ms 递增 |
| 图鉴格入场 | `tileIn .3s`，最大 60 项，8ms 递增 | **无** |
| 研究所卡片 | `tileIn .35s` + `--d` | 0.3s EASE_OUT |
| 悬浮 | `.card/.lab-card` 140ms `cubic-bezier(.3,1.6,.5,1)`，抬升 4px | 仅 scale，无位移 |
| 按钮悬浮 | `translateY(-2px) scale(1.02)` + brightness 1.06 | 仅换 StyleBox |
| 弹窗遮罩 | `fadeIn .2s` | **无**（立即显示/销毁） |
| Banner | 停留 3.2s（long 5.2s），末 30% 淡出 | 3.2s，末 30% 淡出 ✓ |
| Toast | 停留约 3s，popIn | 3s + 0.18s 淡出 ✓ |
| Boss 条入场 | `bbIn .45s cubic-bezier(.2,1.3,.4,1)` | **无** |
| 低血量/受击 | `.lowhp` 0.8s alternate 脉冲；`.flash` 0.3s | **无** |
| 伤害飘字 | `.floater` 上浮 1s `cubic-bezier(.2,.8,.3,1)` | **无** |

---

## 2. 组件状态真值（摘要）

| 组件 | Default | Hover | Pressed / Active | Selected / Focus | Disabled |
| --- | --- | --- | --- | --- | --- |
| `.btn` | 三段渐变 + 4px 实边 | brightness 1.06，上移 2px，scale 1.02 | 下移 2px，实边 1px | 浏览器键盘焦点（默认 outline） | `grayscale(1) opacity(.7)`，无位移 |
| `.card` | 纸底 + 双层影 | 上浮 4px + scale 1.05 + 4px `--rc` 环 | — | `.picked` 外环 | `.dim` 降透明 |
| `.mm-item` | skew(-6deg) + 左 7px 色条 | 由 JS 加 `.focus`：上移 4px + scale 1.03 | — | `.focus` | — |
| `.mm-item.play` | 红渐变 + 内白 4px 环 + 6px 实边 + 红光 | 同上 | — | — | — |
| `.lab-card` | 纸底 + sm 影 | 上浮 4px + 3px 环 | — | `.max` 黄边/满级 | — |
| `.dx-tile` | 类型色 radial | 上移 3px + scale 1.05 | — | `.on` 1.08 + 3px 纸环 + 6px 黄环 | `.unk` 灰化 |
| `.field` | 2px 全边框 | — | — | 边框 `--blue`，bg 纸底 | — |
| `.switch` | 58×32 灰紫 | — | 滑块位移 | on 绿色 + inset | — |
| `.pill`（tab） | 13px / **900** | — | — | `.on` 白底 + 2px 实边 + 阴影 | — |
| `.chip` / `.tag` | 12px / **800** 标题字体 | — | — | — | — |

Godot 侧对应的主要偏差见第 3 节 H-18 / M-01 / M-02 / M-03 / M-07 / M-09。

---

## 3. 差异清单（按影响排序）

### 3.1 高影响

#### H-01 页面底色/背景方向整体错误

- **Web 出处**：`assets/main-oZVl1tJD-mvpjh5lt.css` → `html,body`（`background:#1a1630`）；`.mm:before` 深色径向罩层。
- **Godot 位置**：`src/ui/pb_backdrop.gd:1-80`；`src/ui/ui_kit.gd:204-211`（每个 `UI.screen()` 都加 `PbBackdrop`）。
- **差异**：Web 是深色页面 + 浮起的白卡；Godot 铺浅纸渐变、彩色光斑和白色条纹。所有白色卡片失去对比，整体从“深色街机”变成“浅色纸面”。
- **影响**：高。首屏第一眼即可见，并影响全部非对局页面。
- **修复**：
  1. 把 `PbBackdrop` 根色改为 `#1a1630`，上层叠 `radial-gradient(...#00000066...)` 深色罩层；删除浅纸团/彩斑/白条纹，或仅保留 Web `.mm:before` 的深色径向暗角。
  2. 卡片阴影仍使用 `--shadow`；如需暗底可读性，用 Web 的 `--w96` 半透明卡片，不要改底色。
  3. 若确需浅色主题，应作为独立主题分支；默认必须与 Web 的 `html,body` 一致。

#### H-02 品牌被改写为 "DigiAssault"，wordmark 缺失

- **Web 出处**：`main-C5MieX6g-mvpjh5lt.js` 品牌字符串 `PokéBonk`（27 处）；CSS `.mm-left .logo.hero`（浮动 3.4s）、`.logo-word`（描边 4px、投影 0 7px、`clamp(48px,min(6vw,10vh),88px)`/900，-3°）、`.logo-ball`（wobble）。
- **Godot 位置**：`src/ui/main_menu.gd:168`（`UI.title("DigiAssault", 58)`）；`main_menu.gd:172`（新增“Godot 移植版…”）；`main_menu.gd:377`（法务文案品牌）。
- **差异**：
  - 文案：`DigiAssault` ↔ `PokéBonk`；
  - 尺寸：58px ↔ 1280×720 时 `min(6vw=76.8,10vh=72)=72px`；
  - 无 4px 深蓝描边、7px 投影、-3° 倾斜、精灵球、3.4s 浮动；
  - 多出一行“Godot 移植版 · 完全离线…”不属于 Web 信息架构。
- **影响**：高。品牌识别 + 首屏主视觉。
- **修复**：
  1. 全量恢复 `PokéBonk`（标题/法务/窗口标题）；移植说明移到“关于”弹窗，不占首屏。
  2. 新建 `BrandLogo` 控件：`HBox[Label("Poké") 900 72px + HBox[Label("Bonk") + 42px 精灵球]]`；`theme_override_colors/font_outline_size=4`、`font_outline_color=#2a2a7a`，`font_shadow_color` + `shadow_offset_y=7`，`rotation=-3°`；用 Tween 做 `position.y ±3px`、3.4s 循环。
  3. 版本胶囊改为 `.logo-ver` / `.mm-badge` 的白底小胶囊，不再拼在纯文本后。

#### H-03 主菜单整体布局与 Web 的绝对定位模型不一致，720p 下会溢出

- **Web 出处**：`.mm-left`（`position:absolute; left:var(--mm-gutter); width:min(520px,100vw-2*gutter); top:52%; translateY(-50%); gap:18`）；`.mm-season`（`width:clamp(340px,26vw,400px); max-height:min(640px,100dvh-170px); overflow:hidden`）；`.mm-foot`（`position:absolute; bottom:10px`）；`.mm-top`（固定在顶部）。
- **Godot 位置**：`main_menu.gd:38`（`UI.content(root, 22)`，无滚动）；`:163`（左列 `620px`）；`:278`（赛季 `320px`）；`:50`（页脚在内容流末尾）；`:207-210`（额外“最近对局”）。
- **差异**：
  - 左右列宽度/边距：`620/320/22` ↔ `520/340-400/22-84`；
  - Web 两列是**垂直居中**、页脚绝对贴底；Godot 是自上而下的 VBox，页脚被内容推走；
  - Godot 没有 `ScrollContainer`，估算内容高度已超过 720p（顶部 56 + Logo 72 + 模式 108 + 2×66 + 五格 92 + 迷你 66 + 分隔线/最近对局 + 页脚 ≈ 790+）。
- **影响**：高。1280×720 及更矮窗口会裁切/溢出；1920 宽度下左右比例明显不同。
- **修复**：
  1. 改为主菜单专用 `Control` 布局：`TopBar` 锚定顶部；`LeftColumn` 设 `anchor_left=0, anchor_top=0.52, anchor_bottom=0.52, offset_left=gutter, offset_right=gutter+520, grow_vertical=BOTH`（或 `custom_minimum_size.x=520` 且垂直居中）；`SeasonColumn` 右侧 `clamp(340,26vw,400)`（用 `_on_resized` 计算）。
  2. 页脚改为 `anchor_bottom=1, offset_bottom=-10`，白色 12px/800 + 文字阴影。
  3. 删除“最近对局”或移到调试视图；主菜单不得依赖滚动。
  4. `gutter` 实现为 `clamp(22, 0.05*viewport_w, 84)`，提供 `PbTheme.gutter()`。

#### H-04 主菜单 tile 结构/斜面/强调条/模式行整体不符

- **Web 出处**：
  - `.mm-modes` 高 `clamp(100px,14vh,124px)`，内含 Play + `.mm-pair`（`flex:0 0 172px`，纵向两项）。
  - `.mm-item`：`border-radius:18px; transform:skew(-6deg); padding:10 14 10 12; box-shadow:0 4px 0 #1a124633,var(--shadow-sm)`；`::before` 7px 左色条。
  - `.mm-item.tile`：`flex-direction:column; border-bottom 5px 色条`；标题字号由 `--n` 计算。
  - `.mm-item.mini`：`radius:999px; padding:5 18 5 5; mmPop`。
  - `.mm-today`：`min-height:72px`，承载“每日”和“委托”。
  - DOM：`mm-nav = [mm-modes(play,pair), mm-today, mm-tiles(5), mm-small(4)]`。
- **Godot 位置**：`ui_kit.gd:580-630`（`mm_tile`：横排、66/84 高、无斜面/色条、无入场动画）；`main_menu.gd:181-187`（2×2 模式网格，4 项）；`:189-198`（5 个纵向 tile）；`:200-205`（迷你行仍是普通 tile）；`:207-210`（额外区）。
- **差异**：
  - 结构：4 个模式排成 2×2 ↔ Play + 纵向 `.mm-pair`；缺 `.mm-today` 整行；
  - 视觉签名：全部 tile 少了 `skew(-6deg)` 与左/底部色条；竖排 tile 被做成横排；
  - 迷你行：66px 卡片 ↔ 44-58px 胶囊；
  - 入场：无 `mmIn/mmPop` 级联。
- **影响**：高。主菜单所有入口的形态、密度、节奏都不同。
- **修复**：
  1. 按 Web DOM 重建：`HBox[PlayTile(expand), VBox[EndlessTile, CoopTile](172px)]` → `HBox[Daily, Tasks]` → `HBox` 5 个 typed tile → `HBox` 4 个 mini。
  2. `UI.mm_tile` 拆成 `mm_tile_row / mm_tile_vertical / mm_mini` 三种；统一在容器上 `skew = deg_to_rad(-6)`，子节点 `skew = deg_to_rad(6)` 反向修正；色条用独立 `ColorRect`（7px 左 / 5px 底），`mouse_filter=IGNORE`。
  3. 纵向 tile 用 `VBoxContainer`，标题字号按 `min(14.5, width/(n*0.66))` 近似；迷你胶囊 `radius 999`、横向、`padding 5/18/5/5`。
  4. 入场用 `Tween`：`modulate.a 0→1`、`position.y +12→0`、`scale .96→1`，0.5s `TRANS_BACK`，索引 ×0.08s。

#### H-05 Play tile 的视觉层次缺失（内白环/红实边/红光/图标尺寸）

- **Web 出处**：`.mm-item.play` `box-shadow: inset 0 0 0 4px #ffffffe6, 0 6px #a81c2c, 0 14px 30px #e0303e66`；背景 `linear-gradient(180deg,#ff7a7e,var(--red) 58%,var(--red-d))`；`.mm-item.play .mm-ic` 70×70 白圆 + 内图 52×52 + `inset 0 -4px` + 红色投影（已更正：内图是 52，不是撑满 70）。
- **Godot 位置**：`main_menu.gd:232-247`（`GradRect` + 自绘；渐变 `#ff8f94,#ff5a5f 60%,#e0303e`，图标 70×70 / 内图 52×52，已按 70/52 实现）。
- **差异**：首段色偏亮（`#ff8f94` ↔ `#ff7a7e`）；无内白环、无 6px 红实边、无 14px 红光；图标尺寸 70/52 已对齐。
- **影响**：高。主菜单 CTA 的“可按下的塑料键”质感消失。
- **修复**：
  1. 渐变改回 `#ff7a7e → var(--red) 58% → var(--red-d)`（用 `PbTheme.gradient("linear-gradient(...var(--red)...)")` 或 token 拼字符串）。
  2. 在 tile 上叠加 `Panel`：`StyleBoxFlat` bg 透明、`border_width=4`、`border_color=#ffffffe6`、`corner_radius=22`；外层再加 `StyleBoxFlat` 底边 6px `#a81c2c` + shadow 0 14 30 `#e0303e66`（或两个 `ColorRect` 层）。
  3. 图标容器 70×70，圆角 50%，`inset 0 -4` 通过 `shadow_size=4, shadow_offset=(0,4), shadow_color=#00000014` 和红投影近似。

#### H-06 研究所：栅格/分组/信息密度整体降级

- **Web 出处**：`.lab-grid` `repeat(auto-fill,minmax(230px,1fr))`；`.lab-card` + `.lab-top`（70px，`var(--stripes)`+双段渐变）；`.lab-ic`（54px 白圆，`translateY(18px)`，`0 3px #00000026`）；`.lab-lv`（右上胶囊）；`.lab-bd`（padding 24 14 10，gap 4，居中）；`.lab-bd h3` 18px/900；`.lab-bd p` 13px/700。JS 另有 `.grp-head` 分组标题与进度 pips。
- **Godot 位置**：`lab_screen.gd:28`（固定 `UI.grid(3,10)`）；`:64`（色带仅 40px）；`:80`（名称 15px，含 ID）；`:86`（等级胶囊在正文中部）；`:94-95`（购买按钮 34px 紫色 `UI.button`）；无描述/图标/分组/pips。
- **差异**：3 列 ↔ 5 列（1280 宽时）；顶栏 40 ↔ 70；无 54px 图标圆盘、无右上等级、无 13px 描述、无分组标题、无进度 pips；信息密度显著降低。
- **影响**：高。研究所是主要养成界面，布局和卡片识别方式都不同。
- **修复**：
  1. 用 `HFlowContainer`（`custom_minimum_size.x=230`，`size_flags_horizontal=EXPAND_FILL`）替代固定 3 列；窗口变化自动换行。
  2. 按 Web 重建卡片：`VBox[TopBand70(GradRect+stripes, 54px IconDisc 压边), Body(padding 24/14/10 = name18 + desc13 + pips), BuyButton]`；`lab-lv` 绝对定位右上 `anchor_right=1, offset_right=-10, offset_top=8`。
  3. 分组：从 `lab_table` 读取 group 字段，插入 `.grp-head` 段落（SVG 标题 + 说明）后再放该组 `HFlowContainer`。
  4. 若数据缺 group/desc，先在数据层补齐；不得用自创文案填充。

#### H-07 研究所购买按钮的状态与信息错误

- **Web 出处**：`.lab-buy`（默认灰 `#b8b2cc`、`0 3px #8a84a4`、17px/900、`padding 9`、`margin 4 12 12`）；`.lab-buy.can`（绿色渐变 + `0 4px #157a3a`）；`.lab-buy.max`（黄渐变 + ink 字 + `0 3px #b07a00`）；按钮内显示价格/星尘图标。
- **Godot 位置**：`lab_screen.gd:94-95`（`UI.button("升级", ..., "purple")`，高 34）；`:90` 左右另置 `UI.chip` 显示价格。
- **差异**：颜色语义完全错（紫 ↔ 灰/绿/黄）；按钮无价格；高度 34 ↔ 约 41；无 `margin 4 12 12`；禁用态是 `.btn` 的半透明黄，而不是灰底紫字。
- **影响**：高。“买不起/可买/满级”三种状态无法一眼区分。
- **修复**：
  1. 新建 `LabBuyButton` 用 `.lab-buy` StyleBox 三态：默认 `#b8b2cc` + 底边 3；`can` 绿渐变 + 底边 4；`max` 黄渐变 + ink 字；禁用时 `disabled=true`，`mouse_default_cursor_shape=FORBIDDEN`。
  2. 文案改为 `[星尘图标] N · 升级`；去掉独立价格 chip。
  3. 高度用 `padding 9` 自然高度，`margin` 由容器 `MarginContainer` 设 `4/12/12`。
  4. 满级卡片加 `.max` 的黄色外环/角标。

#### H-08 图鉴：5 列硬栅格 + 缺失 cap/on/unk/shininess 状态

- **Web 出处**：`.dx-grid`（`repeat(auto-fill,minmax(84px,1fr)); gap:8; padding:6 4`）；`.dx-tile`（`aspect-ratio:1; radius:16; radial 类型色; inset 0 -3; animation:tileIn`）；`.dx-tile:hover`（`translateY(-3) scale(1.05)`）；`.dx-tile.on`（3px 纸环 + 6px 黄环 + 1.08）；DOM 中 `.cap` 球标、`.unk`、`shiny-mark`、`.dx-classic`、三位补零编号、`.dx-count`、`.dx-empty`。
- **Godot 位置**：`pokedex_screen.gd:51`（`UI.grid(5,6)`）；`:106`（每格 84×84）；`:109-111`（仅 normal/unk 两个 StyleBox，hover/pressed 复用 normal）；编号 `#%d`。
- **差异**：固定 5 列在左栏 430px 下会横向溢出（5×84+4×6=444）；hover 无反馈；选中无 `.on` 环；已捕获无球标/`.cap`；闪光无标记；编号 `#1` ↔ `001`；无计数、无空态。
- **影响**：高。网格溢出 + 图鉴核心状态不可见。
- **修复**：
  1. 换成 `HFlowContainer` 或按宽度动态 `columns = floor((w+8)/(84+8))`，禁止横向滚动。
  2. 每个 tile 用 `Button` + 三套 StyleBox（normal/hover/on）；hover 用 Tween `translateY(-3) + scale 1.05`；`.on` 用两层外环（3px paper + 6px yellow）。
  3. 增加 `cap` 球标（右下 18px）、`shiny-mark`（右上星）、三位补零编号；空列表插入 `.dx-empty`（精灵球 + 文案）。
  4. 顶部加 `.dx-count`（"N 只宝可梦"）。

#### H-09 图鉴详情缺少展示卡 / 筛选 / 闪光切换，信息密度与原版不同

- **Web 出处**：DOM `DB()`：`.dx-show`（230px 展示区，未知时 silhouette + 双色剪影）、`.dx-shiny` 切换、`.dx-count`、seen/caught/shiny/type 四类筛选、`.dx-entry`（未捕获说明）、`.dx-info`（`gap:12; padding:16 18; popIn .35s 50ms`）。
- **Godot 位置**：`pokedex_screen.gd` 右侧 `UI.panel()`（16px 内边距、10px 间距），无展示卡/闪光切换/捕获状态；筛选只有 Gen 页签 + 搜索（`:39`）；`:179`、`:205` 新增“对局数值/自动招牌招式”并非 Web 内容。
- **差异**：缺失主视觉展示区与状态筛选；右侧信息被移植公式/招牌招式占据；`.dx-info` 无入场动画。
- **影响**：高（图鉴是核心浏览界面，信息结构变化明显）。
- **修复**：
  1. 增加 `DXShow` 卡（顶部 230px，`PmdSprite` 大图 + 剪影模式 + 闪光按钮）；右侧改为 `VBox[Show, Types, Stats, MovesTable]`，`padding 16/18`、`gap 12`，入场 `popIn .35s` 延迟 50ms。
  2. 筛选条按 Web 做 `all/seen/caught/shiny` + 类型下拉 + 搜索；保留 Gen 页签可作为附加，但不能替代状态筛选。
  3. 移植公式/招牌招式移到调试或折叠“更多资料”，不占主信息流。

#### H-10 HUD 顶部中央列被移出网格，计时器会压住左侧信息

- **Web 出处**：`.hud-top`（`display:grid; grid-template-columns:1fr auto 1fr; width:max-content; width` 由中央列决定）；`.ht-c`（`z-index:1; margin:-4px 0 -80px`，仍在 grid 中央列内）；`.ht-l` / `.ht-r`。
- **Godot 位置**：`hud_layer.gd:53-120`（`HBox` 仅 HtL/HtR，宽 560）；`:86` 另建 `HtC`，作为顶部面板的兄弟节点。
- **差异**：中央列不参与面板宽度计算；`HtC` 独立锚定后，计时器/危险条/金币会在 `HtL` 右缘与 `HtR` 左缘之间重叠；Web 是由 grid 分配空间。
- **影响**：高。对局中计时器与生物群系/区域文本互相遮挡。
- **修复**：
  1. 把顶部容器改为 `GridContainer(columns=3)` 或 `HBox[Left(expand), Center(auto), Right(expand)]`；`HtC` 放第 2 列。
  2. 去掉 `HtC` 的独立 `set_anchors_and_offsets_preset(CENTER_TOP)`；改由容器布局，`margin_top=-4`、`margin_bottom=-80` 用 `MarginContainer` 近似。
  3. 保留 `width:max-content` 语义：容器 `size_flags_horizontal=SHRINK_CENTER`，`custom_minimum_size.x` 仅作下限。

#### H-11 血条：滞后层被填充层盖住；圆角/渐变/底色全部丢失

- **Web 出处**：`.bar`（圆角 999、内嵌阴影）；`.hpbar{height:14}`；DOM 顺序 `i, s, b, u, em`，`.hpbar>u{z-index:1}`（滞后层在填充层之上）；`.hpbar>i` 为绿色渐变。
- **Godot 位置**：`hud_layer.gd:274-310`（先加 track/lag，再加 fill，全部 `ColorRect`）；track `#2e2848`（`:282`）。
- **差异**：
  - **滞后层先绘制、填充层后绘制 → 红/白滞后条完全不可见**；
  - track 色 `#2e2848` ↔ Web `.bar` 背景（深色轨道）；
  - 三个矩形都没有 999 圆角；
  - fill 纯色 ↔ Web 渐变；
  - 无 inset 阴影。
- **影响**：高。掉血反馈与可读性错误。
- **修复**：
  1. 绘制顺序改为 `track → fill → lag → shield → text`，并将 lag/shield `z_index` 提高到 fill 之上（或直接将 lag 作为最后一段）。
  2. 用圆角 `Panel` + `StyleBoxFlat(corner_radius=7)` 分别做 track/fill/lag；或 `_draw` 里 `draw_rect(..., filled, width)` + 自定义圆角。
  3. 填充用 `GradientTexture2D`（`#7af0a0→#2ac860`）或 `GradRect` 裁切；track 改 `#3a3456`。
  4. 低/中血量时按 Web 的 `hpbar.mid/low` 改色，而不是仅换 base。

#### H-12 HUD 徽章/小地图尺寸与进度环颜色偏差

- **Web 出处**：`.tl-medal` 108×108；`.tl-ring` `conic-gradient(#3a8cff,#5ad8ff var(--p),var(--line))` + 3px 纸环 + sm 影；`.minimap` 212×212 + 4px 纸环 + 3px 红环；`.tl-plate` `-34px` 重叠；`.tl-lvl` 底部 `-12px`、`skew(-12deg)`、3px 纸环。
- **Godot 位置**：`hud_layer.gd:211`（左组 320×108）；`:240-241`（plate 260×84，位置 74/12）；`pb_widgets.gd` `XpRing` 绘制 84px、紫色弧 5px、纸环 2px；`hud_layer.gd:834`（小地图 150）。
- **差异**：徽章 84 ↔ 108；进度环紫 ↔ 蓝→青 conic；环宽 5/2 ↔ 3/3；小地图 150 ↔ 212（面积 50%）；等级徽标未居中、未旋转、外环缺失。
- **影响**：高。HUD 最主要的三处圆形仪表都偏小且颜色错误。
- **修复**：
  1. `XpRing` 尺寸改 108；用 `draw_arc` 两段（蓝 `#3a8cff` → 青 `#5ad8ff`）或在 `_draw` 中做角度插值；外纸环 3px + `StyleBoxFlat` 阴影。
  2. `TlLvl` 用绝对定位 `anchor_left=.5, anchor_bottom=1, offset_bottom=12` + `rotation`/`skew=-12°` + 3px 纸环；不要固定 `position 44/70`。
  3. 小地图 212，红环用两个 `draw_circle` 环带（纸 4px、红 3px），并支持 `--mm` 缩放。
  4. `plate` 的 260×84 保留，但随 108 徽章重新算重叠。

#### H-13 Banner 与 Modal 标题被拉成通栏色带（Web 为贴合文字的胶囊）

- **Web 出处**：`.banner h1` / `.modal h1`：`display:inline-block`、`padding 8 40 / 6 34`、`border-radius 16`、`skew(-8deg)`；`.banner h1` 字号 `clamp(28px,4.2vw,54px)`。
- **Godot 位置**：`ui_kit.gd:458-505`（`banner` 的 plate 是 VBox 子项，`custom_minimum_size=(0,64)`）；`ui_kit.gd:795-814`（`modal_title` 的 Control 无 `SHRINK_CENTER`，默认填满）；固定 40px。
- **差异**：`VBoxContainer` 默认横向 FILL，plate 被拉满全屏/弹窗宽度；Web 的红色色带只包住文字。Banner 字号 40 ↔ 1280 宽时 `4.2vw=53.8`。
- **影响**：高。Banner/弹窗标题是全屏最醒目的红色块，宽度和比例差异极大。
- **修复**：
  1. `plate.size_flags_horizontal = Control.SIZE_SHRINK_CENTER`（banner 与 modal_title 都加）。
  2. 字号用 `min(54, max(28, viewport_w*0.042))`；在 `resized` 信号里更新；或实现 `PbTheme.clamp_px()`。
  3. 取消整块 `rotation=-8°`，改为 `skew=-8°`（Control 支持 `skew`）；如果 skew 不可用，至少只对文字做旋转、色带保持水平。
  4. modal 标题高度改为内容 padding 驱动（`6px 34px` + 40px 文本 ≈ 52），不要固定 60。

#### H-14 讨伐目标头部的标签变成“紫底紫字”，不可读

- **Web 出处**：`.kg-head`（`color:#fff`；`background:var(--stripes),linear-gradient(100deg,var(--kc),color-mix(...))`；`text-shadow:0 1 #0003`）；`.kg-head span`（白底、`color:var(--kc)`、10px/900、15px 高、radius 99）。
- **Godot 位置**：`hud_layer.gd:390-450`：`head_style.bg_color = rarity_color(3)`（`:396`），`gtag` 文字颜色也是 `rarity_color(3)`（`:404`），进度条/数值也用同一紫色（`:418/:442/:450`）。
- **差异**：头部没有径向/斜向渐变与条纹；标签没有白底，紫字直接落在紫底上，对比度接近 1:1。
- **影响**：高。目标名/标签在对局中不可读。
- **修复**：
  1. 用 `GradRect`（`--kc` 双段 + stripes）铺 `.kg-head`；文字 `Color.WHITE` + `shadow_offset_y=1`。
  2. `gtag` 改为 `PanelContainer`：StyleBoxFlat `bg=paper`、`corner_radius=99`、`content_margin=0/6`，Label 用 `--kc`。
  3. `gleft_val/gbar_fill` 保留 `--kc`，但头部背景必须比文字深/浅分离。

#### H-15 Boss 血条：标签背景回退成纸色、底边丢失、填充写死颜色

- **Web 出处**：`.bb-body`（`background:var(--w96)`；`border-bottom:4px solid var(--c)`；radius 16；padding 6 16 8 30）；`.bb-tag`（`background:var(--c)`；白字）；`.bb-bar`（`background:#2e2848; radius 999; height 15; inset 0 2 3`）。
- **Godot 位置**：`hud_layer.gd:486-545`：`bb_fill.color = #ff4a6e`（`:522`）；`bg_s.bg_color = #2e2848`（`:533`）；`tag` 使用 `stylebox(".bb-tag")` 但未传 `--c`。
- **差异**：
  - `var(--c)` 在 `stylebox()` 中解析不到 → 回退到 `paper()`；标签变成纸底白字（不可读）；
  - `.bb-body` 的 `border-bottom` 未被 `stylebox()` 解析（它只处理 `border`/`shadow`），因此 Boss 色下边完全缺失；
  - fill 固定 `#ff4a6e`，不同 Boss 的 `--c` 不生效；
  - 无 `bbIn` 入场。
- **影响**：高（Boss 出现时最醒目的 UI 条）。
- **修复**：
  1. `stylebox(".bb-tag", {"--c": boss_color})`；或直接建 StyleBoxFlat `bg_color=boss_color, corner_radius=99, content_margin=(1,9)`。
  2. 在 `.bb-body` 的 StyleBoxFlat 上显式 `border_width_bottom=4; border_color=boss_color`，并把左右/上边框设 0。
  3. fill 颜色用 `boss_color`，叠加 `GradientTexture2D`；
  4. 入场 Tween：`scale.y 0.6→1` + `modulate.a 0→1`，0.45s `TRANS_BACK`。

#### H-16 快捷键提示与实际绑定不一致；选卡卡片的 1-4 键标缺失

- **Web 出处**：`.card .key`（12px/900、padding 1 8、radius 8）；`.ult kbd` 键帽；Web keymap 使用 `KeyR`（融合同源）。
- **Godot 位置**：`main_menu.gd:48`（“F 融合”）；`hud_layer.gd` `ult kbd` 文案 "F"；`run_screen.gd:319-343`（`KEY_R` 触发融合、`KEY_F` 触发 reroll）；`run_screen.gd` 构造 offer 时 `key=""`。
- **差异**：界面显示 F 融合，实际按 F 是 reroll、R 才是融合；选卡卡片没有 1/2/3/4 键标（Web 有 `.key` 徽标）。
- **影响**：高。按提示操作会得到相反结果，选卡热键不可发现。
- **修复**：
  1. 统一为 Web keymap：HUD keycap / 菜单操作提示改为 `R 融合`，或若决定保留 F，则把融合绑定改回 F，二者必须一致。
  2. offer 数据传入 `"key": str(index+1)`；`.card .key` 用 StyleBoxFlat（12/900、brown/ink、radius 8）+ 键帽底色。
  3. HUD `.ult kbd` 与菜单提示从同一个常量读取（如 `InputMap.action_get_events("fusion")`），避免再次漂移。

#### H-17 对局反馈层缺失：伤害飘字 / 低血量 / 受击闪屏

- **Web 出处**：`.floater`（伤害飘字上浮 1s）；`.lowhp`（`inset 0 0 160px 50px #ff142866`，0.8s pulse alternate）；`.flash`（`inset 0 0 120px 30px #ff283c8c`，0.3s opacity）；`.evpill/.milepill`（事件/里程碑 pill）；`.prompt`（底部 24% 交互提示）。
- **Godot 位置**：`hud_layer.gd` 无对应节点；`run_screen.gd:414-422` 只有相机 trauma + `Audio.sfx("hit")`；全项目无 `Label3D`/floater 实现；无 `.flash`/`.lowhp`；无 `.evpill/.milepill/.prompt`。
- **差异**：受击只有镜头震动，没有屏幕红闪、低血脉冲、飘字；Boss/事件/里程碑提示缺失；交互提示缺失。
- **影响**：高。战斗可读性和打击反馈显著弱于原版。
- **修复**：
  1. 新增 `DamageFloater`（`Label` + `Tween`：`position.y -40`、`scale 1→1.15→1`、`modulate.a 1→0`，1s `TRANS_CUBIC`；伤害数字用 26px/900 + 5px ink 描边），由伤害事件 spawn。
  2. HUD 根节点加 `LowHPOverlay`（`ColorRect` + Shader 或 4 边渐变 `TextureRect`），`hp<25%` 时 Tween `modulate.a` 0.6↔1，0.8s 循环。
  3. `FlashOverlay` 收到伤害/复活时 `modulate.a 0→0.45→0`，0.3s。
  4. `EvPill/MilestonePill/Prompt` 按 CSS 位置和 0.4s `TRANS_BACK` 入场；内容由 run events 驱动。

#### H-18 暗色主题存在写死浅色面：HUD 纸板与默认 Panel 永远是浅紫

- **Web 出处**：`--paper/-2/-3`、`--w92..97` 在 dark theme 全部切换为 `#22283a` 系；`.tl-plate` 等只使用 token，不写死。
- **Godot 位置**：`hud_layer.gd:240-244`（`tl_plate` StyleBox `bg_color = Color("#fffffff7")`，注释“HUD 纸板恒定白色”）；`pb_theme.gd:754`（`Panel` 的 card_style 强制 `Color("#f3f1fa")`）。
- **差异**：暗色主题下，左上信息板仍为白色；所有未显式覆写的 `Panel` 仍为浅紫 `#f3f1fa`，与深色卡片并置。
- **影响**：高（暗色主题核心可读性/一致性）。
- **修复**：
  1. `tl_plate` 改 `PbTheme.css_color(PbTheme.v("--w97"))`，不要写死。
  2. `Panel` 默认样式改 `card_style()` 无 override（即 `paper()`，随主题切换）；若某些面板必须浅色，使用独立类 `PanelLight`。
  3. 全项目检索 `Color("#fff...")`、`#fffffff7`、`#f3f1fa`，统一替换为 `paper()/w()`。

### 3.2 中影响

#### M-01 全局正文字号/字重偏离（15px/800 ↔ 16px/700）

- **Web**：`html,body` 16px/700；`.mm-legal` 10.5/700；`.lab-bd p` 13/700。
- **Godot**：`pb_theme.gd:772-774` Label 15px + `font("body")` = Nunito-800；`UI.dim` 13px/800。
- **差异**：所有普通文本偏小 1px、偏粗 100 级；在白色卡片上尤其明显。
- **影响**：中（全局纹理感）。
- **修复**：Theme Label 改 16px；`font("body")` 改为 Nunito-700（新增 `FONT_BODY_REGULAR=700`，`font("body")` 指 700，另设 `font("body_bold")` 供需要 800 的场景）；检查 `UI.label` 默认值与 HUD 11/12px 覆盖。

#### M-02 按钮没有 hover/active 位移与按压缩进，立体边尺寸也不对

- **Web**：`translateY(-2)/scale 1.02`、`brightness 1.06`；active `translateY(2)` + 实边 1px；实边 4px；`--shadow-sm 0 4 12`。
- **Godot**：`pb_theme.gd:820-846` 仅换 StyleBox；`border_width_bottom=6`；`shadow_offset=8, shadow_size=8`；disabled 用 alpha .45 且无 `grayscale`。
- **差异**：点击“软”，没有上浮/下压；6px 边比 4px 粗；阴影偏移 8 与 CSS 4 不一致；禁用态比 Web 更淡且偏黄。
- **影响**：中（全站按钮手感）。
- **修复**：`paint()` 里连接 `mouse_entered/exited/button_down/up`，用 Tween 改 `position`/`scale`（0.16s `TRANS_BACK`）；StyleBox 用 `border_width_bottom=4`、`shadow_offset=(0,4)`、`shadow_size=12`；disabled 用 `modulate` 灰度近似（`Color(0.65,0.65,0.65,0.7)` 的 `self_modulate`）并设 `mouse_default_cursor_shape=FORBIDDEN`。

#### M-03 卡片 hover 只放大，没有 4px 外环/上浮；card_offer 键帽缺失

- **Web**：`.card:hover` `translateY(-4) scale(1.05)` + `0 0 0 4px var(--rc)`；`.card .key`。
- **Godot**：`ui_kit.gd:638-690` hover 仅 `scale 1.05`；normal/hover 共用 `.card` StyleBox；`run_screen` 未传 key。
- **影响**：中。选卡缺少“聚焦卡片”的强提示，热键不可见。
- **修复**：hover 加 `position.y -4` + `StyleBoxFlat border 4px rc`（或在按钮 overlay 上套 4px 外环 `Panel`）；`key` 传入 1-4 并绘制右上角 `.key` 胶囊（12/900、radius 8）。

#### M-04 屏幕内边距与切换动画不统一

- **Web**：`.screen` `padding:18px 24px 20px` + `fadeIn .25s`；`.scr-head` `slideDown`；HUD `.fade .45s`。
- **Godot**：`ui_kit.gd:214-223` 统一 18/22；`app.gd:101-107` 直接 `change_scene_to_file`；`screen_head` 无动画。
- **影响**：中。左右留白比 Web 少 6px，切屏“瞬切”显得生硬。
- **修复**：`UI.content` 接受 `{top,right,bottom,left}` 或固定 `18/24/20`；主菜单用 gutter 而非 22；`App.goto` 用 `FadeRect` overlay 做 0.25s 淡出/淡入；`screen_head` 入场 `position.y -12→0` + fade。

#### M-05 图鉴/研究所/HUD 所有 `ColorRect` 填充的圆角丢失

- **Web**：`.dx-bar`、`.bar`、`.kg-bar`、`.bb-bar` 都是 `radius 999`，填充继承圆角。
- **Godot**：`pokedex_screen.gd:225/272`、`hud_layer.gd:450` 等直接 `ColorRect` 直角填充；外框是圆角 Panel，形成“圆槽方芯”。
- **影响**：中。所有进度/属性条边缘出现方角。
- **修复**：统一封装 `UI.fill_bar(track, fill)`，用 `Panel` + StyleBoxFlat `corner_radius=999` 做填充；或 `TextureProgressBar` + 圆角 mask。禁止再直接 `ColorRect` 叠在圆角槽上。

#### M-06 研究所卡片缺少 hover 抬升/外环与满级视觉

- **Web**：`.lab-card:hover` 上浮 4 + 3px 环；`.lab-card.max` 状态色边；`.lab-tile` 入场 0.35s。
- **Godot**：`lab_screen.gd:64-105` 是 `PanelContainer`，无鼠标信号；`UI.anim_in_simple` 仅 0.3s 淡入缩放。
- **影响**：中。卡片没有“可购买”的悬浮反馈，满级与普通卡无结构差异。
- **修复**：给卡片加透明 `Button` overlay 或 `gui_input`；hover Tween 上浮 4 + scale 1.02 + StyleBox 3px 环；满级加 `max` 黄边和“MAX”角标。

#### M-07 Switch 的关闭态在暗色主题仍为浅紫；滑块细节缺失

- **Web**：`.switch` off `#d4cfe6`（light）/`--line`（dark 同源）；on `var(--green)`；inset 阴影。
- **Godot**：`pb_theme.gd:1033-1054` 关闭态写死 `#d4cfe6`；`SwitchToggle` 58×32、24px 滑块。
- **影响**：中。暗色设置页出现发亮的浅紫开关。
- **修复**：off 用 `v("--line")`；track 加 inset 近似（`StyleBoxFlat` 无内阴影时用 1px 上边框+深色 6% 叠层）；滑块 24px 圆角 12，随 on/off 0.18s `TRANS_BACK` 位移。

#### M-08 滑条滑块是普通圆点，不是 Web 的精灵球；轨道样式也简化

- **Web**：`.st-range` 12px 高、双色轨道（已填充 `--c` / 未填充 `--line`）；thumb 是 28px 精灵球（红白分半、墨色边）。
- **Godot**：`pb_theme.gd:917-927` `slider_knob()` 单色圆形；`HSlider` 使用背景/填充两段 StyleBox。
- **影响**：中（设置面板）。
- **修复**：自绘 `PokeballSlider extends HSlider`：`_draw` 轨道圆角 + 精灵球 thumb（两个半圆 + 中带 + 描边）；或 `TextureRect` grabber 用 `pokeball` 资源，`custom_minimum_size 28`。

#### M-09 `pill`/`seg` 选中项字重与内阴影偏差

- **Web**：`.pill` 13px/**900**；`.seg` `inset 0 1px 3px #1a124614`；`.pill.on` `0 2px 0` + sm。
- **Godot**：`pb_theme.gd` `pill_seg_style` 用 `font("title_bold")` 800；`.seg` 的内阴影被 `stylebox()` 解释成 1px 下边框。
- **影响**：中（分段控件/筛选页签）。
- **修复**：`Segment` 用 `font("title")` 900；内阴影改为在轨道 StyleBox 上叠 1px 深色上边框 + 3% 黑色 bg 混合，或直接忽略（不要错误变成边线）。

#### M-10 弹窗无淡入、无焦点锁定，关闭语义不完整

- **Web**：`.modal` `fadeIn .2s`，遮罩径向渐变；标题贴合；`.modal h1` 斜切。
- **Godot**：`ui_kit.gd:818-831` 立即加入/移除；所有按钮 `FOCUS_NONE`（`ui_kit.gd:743`、`mm_tile:584`）；无遮罩点击关闭、无 Esc 统一处理（各屏自写）。
- **影响**：中。弹窗出现生硬；键盘用户无法聚焦；点击遮罩行为不一致。
- **修复**：`modal_shell` 加入 0.2s 淡入/0.15s 淡出 Tween；提供 `close_on_scrim` 参数（选择类弹窗保持 `false`，设置类 `true`）；`grab_focus` 到主按钮并 `focus_mode=ALL`（Web 有键盘焦点）；Esc 统一由 `modal_shell` 处理。

#### M-11 Toast 宽度固定 400px，Web 为内容自适应；未支持 HUD 缩放

- **Web**：`.toasts` 居中堆叠，toast 宽度由内容决定；`transform:scale(var(--hs,1))`。
- **Godot**：`ui_kit.gd:273-305` 固定 400px；无 `--hs`。
- **影响**：中。短提示留白过多，长提示换行。
- **修复**：`custom_minimum_size.x=0`，`size_flags_horizontal=SHRINK_CENTER`，最大宽度 `min(400, viewport*0.45)`；加 `hud_scale` 设置并按 `--hs` 对 HUD 根节点整体缩放。

#### M-12 HUD 文本字号/阴影与计时器终局脉冲缺失

- **Web**：`.hpbar>b` 11px/800 + 文本阴影；`.timer.final` 脉冲；`.kg-name` 14/900；`--hs`。
- **Godot**：`hud_layer.gd` 血条文字 9px、无 text-shadow；`timer_style(final)` 只换底色；无脉冲 Tween。
- **影响**：中。血条数字偏小，终局倒计时没有紧迫感。
- **修复**：血条文字 11px/800 + `shadow_offset_y=1, shadow_color=#00000066`；`final` 时 Tween `scale 1↔1.06`/`modulate` 0.5s alternate，并在最后一秒改红色闪烁。

#### M-13 `stylebox()` 对渐变/`border-bottom`/伪元素的静默降级

- **Web**：`.dx-tile` radial、`.lab-top` 双段+stripes、`.kg-head` 双段+stripes、`.bb-body` border-bottom、`.mm-item:before` 色条。
- **Godot**：`pb_theme.gd:stylebox()` 对非纯色背景回退 `paper()`；只解析 `border`，不解析 `border-bottom`；伪元素完全不支持。结果：图鉴 tiles/研究所顶栏/目标头/Boss 下边/主菜单色条被“压平”。
- **影响**：中（横跨多个场景的共性根因）。
- **修复**：`stylebox()` 遇到 `linear-gradient/radial-gradient/conic-gradient` 时输出 warning 并返回空/显式失败，迫使调用方用 `GradRect`；新增 `border_bottom_width/color` 解析；伪元素以显式节点实现（见 H-04）。
- **影响面**：这是主题层最值得先修的架构问题，修完后 H-04/H-06/H-14 的修复成本大幅下降。

#### M-14 主菜单页脚位置/对比度与原版不符

- **Web**：`.mm-foot` 绝对 `bottom:10px`，12px/800 白色 + `text-shadow:0 1px 3px #000c`。
- **Godot**：`main_menu.gd:50,374-381` 在内容流末尾，11px `ink_muted`。
- **影响**：中。在深色背景上灰字可读性差；页脚不在视口底部。
- **修复**：从 `column` 移出，锚定 `bottom=10`；颜色白 12px/800 + 文字阴影；`.mm-legal` 最大宽度 980、居中。

#### M-15 移植专属内容占据主信息流（最近对局、图鉴公式、开局招式说明）

- **Web**：主菜单无“最近对局”；图鉴无“移植公式/自动招牌招式”；研究所无“Godot 移植版”说明。
- **Godot**：`main_menu.gd:207-210`、`pokedex_screen.gd:179,205`、`main_menu.gd:172`。
- **影响**：中。首屏/核心页被非原版内容挤占，导致高度溢出和信息层级变化。
- **修复**：移除或收进“调试/关于”折叠区，默认不渲染；保留数据但不出现在主信息流。

### 3.3 低影响

| ID | 差异 | Web 出处 | Godot 位置 | 修复 |
| --- | --- | --- | --- | --- |
| L-01 | 卡片阴影单层（14/8）↔ 双层 28/10+2/6 | `--shadow` | `pb_theme.gd:801-814` | `StyleBoxFlat` 只能一层；用两层 Panel/TextureRect 叠加，或接受近似并记录 |
| L-02 | chip 底部 2px 边 ↔ `inset 0 -2` 阴影 | `.chip` | `pb_theme.gd:chip_style` | 用 1px 底边 + 深色 6% 叠层近似 |
| L-03 | 无 `prefers-reduced-motion` 降级 | `@media (prefers-reduced-motion)` 全局 `animation:none` | 全项目 Tween | 设置项“减少动态效果”，关闭入场/漂浮/脉冲 |
| L-04 | 无 Web 启动 loading（渐变 + 64px 旋转精灵球） | `.loading` | 未实现 | 启动场景加 0.8s 最小展示，避免闪屏 |
| L-05 | Toast 无堆叠上限/自动收缩 | `.toasts` | `ui_kit.gd:273` | 最多 4 条，超出移除最旧 |
| L-06 | Banner/modal 用 rotation 代替 skew | `skew(-8deg)` | `ui_kit.gd:813` | Control 支持 `skew` 时改 `skew=deg_to_rad(-8)` |
| L-07 | `--hs` HUD 缩放未实现 | `.under/.toasts` `scale(var(--hs))` | HUD 根节点 | 设置项 0.85–1.15，作用于 HUD CanvasLayer |
| L-08 | `.dx-tile` 编号未补零 | `padStart(3,'0')` | `pokedex_screen.gd` | `"%03d" % id` |
| L-09 | 版本/BETA 胶囊样式简化 | `.logo-ver/.mm-badge` | `main_menu.gd:168-172` | 白底胶囊 10px/900，置于 wordmark 右上 |
| L-10 | 图鉴类型筛选/精灵球计数缺失 | `.dx-count`/`.dx-ball` | `pokedex_screen.gd` | 加计数文本与球标（随 H-08 一起） |

---

## 4. 场景级结论

### 4.1 主菜单

Web 的真实信息架构（JS 建树）：

```text
.mm
├─ .mm-top  (语言 / 全屏 / KR / VB / Trainer 胶囊)
├─ .mm-left (top:52%, width:min(520,...), gutter clamp(22,5vw,84))
│  ├─ .logo.hero (float 3.4s + logo-word 72px 描边 + 球)
│  └─ .mm-nav
│     ├─ .mm-modes (Play + .mm-pair[Endless, Coop], 100-124 高)
│     ├─ .mm-today (每日 + 委托, min 72)
│     ├─ .mm-tiles (5 个纵向 tile)
│     └─ .mm-small (4 个 mini 胶囊)
├─ .mm-season (right, clamp(340,26vw,400), max-height min(640,100dvh-170))
└─ .mm-foot (absolute bottom 10)
```

Godot 现状与本报告 H-01..H-05、M-01、M-14、M-15 对应。主菜单是差距最集中的场景，建议作为第一优先批次。

### 4.2 图鉴

Web：筛选条（全部/见过/捕获/闪光/类型/搜索）→ 自适应 84px 网格（`.dx-count`、`.cap`、`.unk`、`.on`、闪光/经典标记、`.dx-empty`）→ 右侧 `.dx-show` + `.dx-info`（展示、类型、属性、招式表）。
Godot：Gen 页签 + 搜索 → 固定 5 列 → 右栏肖像 + 类型 + 属性条 + 12 条招式 + 移植公式。对应 H-08/H-09、M-05、L-08/L-10。

### 4.3 研究所

Web：滚动分组（`.grp-head`）→ 自适应 230px 卡片（70px 顶栏 + 54px 图标 + 右上等级 + 名称 18 + 描述 13 + pips + 三态购买按钮）。
Godot：单列表 → 固定 3 列 → 40px 顶栏、无图标/描述/等级角标/分组、紫色“升级”按钮。对应 H-06/H-07、M-06。

### 4.4 对局 HUD

Web 层级：

```text
.hud
├─ .hud-top (grid 1fr auto 1fr: fragment/zone/weather | timer/danger/gold | clock)
├─ .hud-tl (108 medal + 260 plate + lives/evolution)
├─ .under (hpbar 14 + pw-row)
├─ .hud-tr (212 minimap, leftpill, counters, 226 kgoal, evpill, milepill, ...)
├─ .hud-bl (slots + 74 ult ring + kbd)
├─ .hud-br (items)
├─ .lowhp / .flash / .fade / .prompt / .streak
└─ .toasts
```

Godot 缺失/偏差集中在 H-10..H-12、H-14..H-17、M-05、M-12。对局 HUD 是第二大优先批次。

### 4.5 局内弹窗、选卡、结算

- 标题：通栏红条（H-13）→ 应贴合文字。
- 选卡：无 1-4 键标（H-16）；hover 无外环（M-03）。
- 入场：无 `.modal fadeIn .2s`（M-10）。
- 结算：使用 `.card.mini` 178px；Godot 约 200px（低）。结算卡片信息分组与 Web 的 `.card` 结构一致，但缺 `.key`/`.picked` 状态。
- 建议：先修 H-13/H-16/M-03/M-10，再补结算数值细节。

### 4.6 融合 / 存档（移植扩展）

- Web 主流程没有独立融合页面（融合是局内按键/弹窗逻辑）；`save_screen` 是移植新增的存档管理页。两者属于“移植扩展”，不纳入 1:1 视觉必达项，但需要：
  - 若有独立页面，必须沿用 `.screen` 边距/标题/卡片 token，不要自创布局；
  - 存档页的 `LineEdit.new()` 未走 `UI.field`，会得到 `line_style` 只有下边框的输入框（`pb_theme.gd:863-868`），应改用 `UI.field` 或 `.field` 全边框样式。
- 建议在关于页标注“移植扩展”，避免被误认为原版内容。

---

## 5. 主题机制覆盖与收敛方案

### 5.1 当前覆盖面

| 能力 | 状态 | 说明 |
| --- | --- | --- |
| 颜色 token（light/dark） | 覆盖良好 | `ui_theme.json` 直接解析 `:root`，`PbTheme` 有 `ink/paper/accent/css_color` |
| 圆角 | 覆盖良好 | `radius()` 读 `--radius`，多数 StyleBox 走 token |
| 字体族 | 覆盖良好 | M PLUS Rounded 900/800 + Nunito 700/800 已内置 |
| 字号 | **部分硬编码** | Theme 15/16/17；各屏 10–58px 直接写字面量；无字阶 token |
| 阴影 | **仅近似** | `card_style` 写死 14/8；`--shadow` 双层无法在单个 StyleBoxFlat 表达 |
| 渐变 | **降级** | `stylebox()` 只取纯色/回退；radial/多段 conic 变成纸色 |
| 伪元素/色条 | **不支持** | `.mm-item:before`、`.lab-top:after` 未表达 |
| 动效 | **未 token 化** | `anim_in` 固定 0.3s EASE_OUT；无 reduced motion |
| 响应式 | **未实现** | Web 的 `clamp()`/`vw`/`vh` 在 Godot 中多为固定 px |
| 暗色 | **部分破功** | 写死浅色（H-18） |

### 5.2 硬编码清单（按文件）

| 文件 | 代表位置 | 问题 |
| --- | --- | --- |
| `src/ui/main_menu.gd` | `:235` `#ff8f94/#ff5a5f/#e0303e`；`:246` `#ff5a5f`；`:329` `#ffb04a/#ff8a2f`；`:377` 品牌 | 颜色/品牌未走 token，且首段色偏离 |
| `src/ui/hud_layer.gd` | `:259 #b5841a`；`:282 #2e2848`；`:522 #ff4a6e`；`:533 #2e2848`；`:834 150`；`:211/240` 尺寸 | HUD 专属尺寸/颜色应进 `PbTheme` 的 HUD token |
| `src/ui/ui_kit.gd` | `:489` 副标题底色；`:798` 固定 60/44；`:813` rotation | banner/modal 尺寸和斜切未 token 化 |
| `src/ui/pokedex_screen.gd` | `:179/:205` 移植内容；`:240` 自定义阈值色 | 非原版信息/颜色逻辑 |
| `src/ui/lab_screen.gd` | `:105` 自创分类色 | Web 无该分类色，属于自创样式 |
| `src/ui/pb_theme.gd` | `:754 Color("#f3f1fa")`；`:806-808` 阴影；`:827/845` 边宽；`:873` 轨道混合 | 主题层自身也写死浅色/近似值 |

`pb_theme.gd` 中约 38 处色值字面量，`hud_layer.gd` 约 27 处，建议用“硬编码清单 + 逐项替换”作为独立重构任务，不夹在功能修改中。

### 5.3 收敛建议（按落地顺序）

1. **补 token 维度**：新增
   - `--page-bg: #1a1630`（或 `PbTheme.page_bg()`）；
   - `--hud-medal:108px`、`--hud-minimap:212px`、`--hud-ult:74px`；
   - `--motion-fast:.16s`、`--motion-base:.25s`、`--motion-pop:.5s` + 曲线常量；
   - `--font-size-*`（10/12/13/15/16/17/19/21/28/40/54）。
2. **禁止静默降级**：`stylebox()` 对 gradient/border-bottom/伪元素输出警告并返回明确空值；调用方必须改用 `GradRect` 或显式节点。
3. **统一 widget**：
   - `UI.grad_button`（渐变 + 4px 实边 + hover/active Tween）；
   - `UI.rounded_bar`（track/fill/lag/shield 分层 + 999 圆角）；
   - `UI.hover_card`（抬升 + 外环）；
   - `UI.skew_tile`（skew + 反向 skew 子节点 + 色条）。
4. **布局 token 化**：实现 `PbTheme.clamp_px(min, vw_ratio, max)` 与 `gutter()`，在 `resized` 信号重算主菜单/弹窗标题/图鉴列数。
5. **暗色回归**：CI 或启动开关跑一遍 `theme=dark` 截图，重点检查 `Panel`、`tl_plate`、`switch`、`lab-buy`、`kgoal`。

---

## 6. 建议优先落地的前 5 项

1. **H-01 背景与整体明暗关系**：一项修复即可让全站观感回到 Web 的深底白卡基线，收益最大。
2. **H-02 + H-03 + H-04 + H-05 主菜单重做**：首屏是玩家第一印象；品牌、列宽、模式行、斜面/色条、Play 层次需一次成组修。
3. **H-10 + H-11 + H-12 HUD 官方布局/血条/仪表**：对局中持续可见，且 H-11 的滞后层被遮挡属于功能性视觉缺陷。
4. **H-06 + H-07 研究所卡片与购买三态**：主养成界面，当前信息密度和购买状态语义都不足。
5. **H-16 + H-17 + M-02 交互反馈闭环**：键位提示一致性、选卡键标、hover/press、伤害飘字/低血/闪屏，直接决定“像不像原版”。

---

## 7. 待确认项

以下未做运行时验证，需在实现前用 Web 实机或截图复核：

1. `clamp()` 在 1280×720 / 1440×900 / 1920×1080 下的实际列宽与高度（H-03）。
2. Web `.modal` 是否允许点击遮罩关闭、是否锁定焦点（M-10）；本文只确认了无动画与全宽标题。
3. `.floater` 是否对玩家伤害、敌人伤害、治疗分别使用不同字号/颜色；Godot 添加时需按事件类型确认（H-17）。
4. `.lowhp` 的触发阈值（推断 25%）与是否叠 `.flash`（H-17）。
5. Boss 条 `--c` 的取色来源（Boss 配置还是元素类型）；`#ff4a6e` 是否为某个 Boss 的固定色（H-15）。
6. Web 的 `KeyR` 是否在所有输入上下文都等同“融合”；HUD keycap 文案应以运行时 InputMap 为准（H-16）。
7. `.dx-show` 的闪光切换是否持久化到存档；Godot 实现前需确认（H-09）。
8. 研究所 `group/desc/pips` 数据是否已在 `lab_table` 中；若缺，先补数据再谈像素级复刻（H-06）。
