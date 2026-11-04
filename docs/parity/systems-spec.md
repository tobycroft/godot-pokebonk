# 剩余系统 Web 真值规格（商店 / 维生素 / 进化 / 天气事件 / 危险地形）

- 生成日期：2026-11-04
- 真值来源：`/Users/tobycroft/Documents/GitHub/pokebonk-web`
  - 主逻辑：`assets/main-C5MieX6g-mvpjh5lt.js`
  - 共享数据：`assets/news-BJhqkt7g-mvpjh5lt.js`
  - 元商店 API：`api-core.js`（本文不涉及，见 §1.1 说明）
- 输出对象：`/Users/tobycroft/godot/godot-pokebonk`
- 背景报告：[data-logic-parity.md](file:///Users/tobycroft/godot/godot-pokebonk/docs/parity/data-logic-parity.md)
- 本文只做只读提取；未改任何 Godot 代码 / 数据文件。

> **offset 记法**：全部为「UTF-8 解码后字符串」的 0-based 字符下标，用 Python `str.find()` 复现，不是字节偏移。
> **minified 符号**：`Zt`/`er` 是 news 模块内的局部名，在 main 里分别被 import 成 `Zt`/`er`；同名不同模块的局部名可能复用，定位时以「文件 + offset」为准。
> **`c()`**：bundle 的 i18n 取值函数；`c('西语原文')` 的字符串就是 i18n key（西语原文即 key）。

---

## 0. Godot 现状与本文件的关系

| 系统 | Godot 现有文件 | 已有内容 | 本文补什么 |
|---|---|---|---|
| 商店 | `src/core/pb_shop.gd` | `open` `_roll_stock` `price_for` `reroll_cost` `reroll` `buy` `can_hold` `shop_heat` `discount`，非无尽公式已对齐 | 无尽/塔分支、商人 NPC 计时、出售价 `oT`、UI 文案与 i18n |
| 维生素 | `src/core/pb_vitamins.gd`、`data/pb/vitamins.json` | `add` `mods_for` `preview` `_base_mod` `_roll_dice` `_dice_mods` 已按 `addVitamin/de/ue/pe` 移植 | 出卡权重差异、等级上限口径、展示格式、准确 offset |
| 进化 | `src/core/pb_data_registry.gd:141 evolutions_of`、`:146 evo_chain_root` | 只有数据辅助 | 全部运行逻辑：`runEvolution/planEvolution/tryEvolve/startEvolution/setSpecies` |
| 天气事件 | `src/core/pb_weather.gd`、`data/pb/weather.json` | 只做 `weather_damage` 伤害倍率 | 事件调度、`baseWeather` 回落、四事件效果、meowth 行为 |
| 危险地形 | `data/pb/hazards.json` | 与 `_D`/`vD` 完全一致 | 运行层：调度、生成、生命周期、玩家/敌人效果 |

---

## 1. 商店（Tienda de Meowth）

### 1.1 结论：这是「局内 Meowth NPC 商店」，不是元商店

- 元商店（星尘商店）走 `api-core.js` 的 `items/:key/buy|equip|off|sell`，`grep -c shop api-core.js` = **0**，与本节无关。
- 本节商店由 run 内的 `shop` 对象 + `interactables` 的 `meowth` NPC 驱动，入口 `openShop()` @**1547939**。
- 用户提到的 `dD=7500` `fD=2500` **不是商店刷新**，而是地图交互提示的显示/锁定计时：

```js
var dD=7500,fD=2500,pD=.4,mD={ball:{...},...}
```

| 常量 | 值 | 真实语义 | 出处 |
|---|---|---|---|
| `dD` | `7500` | 交互提示停留 **7.5 s** 后加淡出 class | main @1388836 |
| `fD` | `2500` | 提示展示后 **再锁 2.5 s** 才允许下一条提示 | main @1388836 |
| `pD` | `.4` | 场景扫描交互物的间隔 **0.4 s** | main @1388836 |
| 硬编码 `7900` | `7900` | 提示 7.9 s 后从 DOM 移除 | main @1391808 |

> 商店计时是另一组：`meowthT=210` / 重置 `300` / `meowthLeft=45`（§1.7）。

### 1.2 Web 出处

| 符号 | offset | 作用 |
|---|---|---|
| `openShop()` | main @1547939 | 打开商店、按 stage 选库存 |
| `nC(e)` | main @1103831 | 生成 4 件库存 |
| `XS(e,t=0)` | main @1101219 | 随机抽一件道具（稀有度 + 标签权重） |
| `GS(e,t=0,n=0,r)` | main @1096826 | 稀有度 0–4 抽样 |
| `rC` | main @1103970 | 基础价格 `rtRC [80,130,220,400,750]` |
| `iC` | main @1103994 | 热度倍率 `[1.15,1.25,1.4,1.6,2]` |
| `aC(e,t)` | main @1104019 | 当前售价 |
| `oC` | main @1104103 | gold-teeth 折扣 |
| `rT(e,t=tT)` | main @1284139 | 关卡/无尽价格缩放；`tT=2.2`、`nT=1.7` |
| `eT(e)` | main @1284038 | 宝箱基准价（`CHEST_BASE=18`） |
| `$w(e)` | main @1283854 | 宝箱价格增长曲线 |
| `oT(e,t)` | main @1284315 | 出售价（按稀有度） |
| `get shopHeat()` | main @1505936 | 连买热度 |
| `rerollCost()` | main @1548181 | 重掷价格 |
| `rerollShop()` | main @1548314 | 重掷库存 |
| `buyShopItem(e)` | main @1548502 | 购买校验与结算 |
| `showShop(e,t)` | main @2178449 | 商店 UI |
| `canHold(e)` | main @840446 | 持有上限校验 |
| `meowthArrives()` | main @1407519 | 商人到场 |
| `meowthLeaves()` | main @1407893 | 商人离场 |

### 1.3 库存生成（`nC` / `XS` / `GS`）

```js
function nC(e){
  let t=[];
  for(let n=0;n<16&&t.length<4;n++){
    let n=XS(e);
    n&&!t.some(e=>e.key===n)&&t.push({key:n,price:aC(e,n)})
  }
  return t
}
```

- 最多尝试 **16** 次，目标 **4** 件；按 `key` 去重。
- **注意**：库存行初始没有 `sold` 字段；购买时 `buyShopItem` 才写 `e.sold=!0`。读 `sold` 等价于 `false`。

`XS` 的池与权重（原样）：

```js
function XS(e,t=0){
  let n=e.player,
      r=wt.filter(t=>e.meta.itemInPool(t.key)&&!YS(e,t.key)&&(n.items.get(t.key)??0)<(t.max??10)),
      i=[0,1,2,3,4].map(t=>r.some(n=>n.rarity===t&&!e.banished.has(`i`+n.key)));
  if(t>=3&&!i.slice(t).some(Boolean))return null;
  let a=Math.max(t,GS(e,t,10,i)),
      o=r.filter(t=>t.rarity===a&&!e.banished.has(`i`+t.key));
  for(let t=a-1;!o.length&&t>=0;t--)
    o=r.filter(n=>n.rarity===t&&!e.banished.has(`i`+n.key));
  return o.length||(o=r),
    o.length?F.weighted(o,e=>e.tags?.some(e=>n.types.includes(e.slice(5)))?4:e.tags?.35:1)?.key??null:null
}
```

池过滤条件（三条）：
1. `meta.itemInPool(key)`：`Le(profile,key)`，即「未解锁的池外道具不给」；
2. `!YS(e,key)`：本局不可出现的道具（故事/事件道具）；
3. `items.get(key) < (def.max ?? 10)`：已满不再出。

权重规则：
- `tags` 中存在 `type:xxx` 且玩家拥有该属性 → **×4**
- 有 `tags` 但一个都不匹配 → **×0.35**
- 无 `tags` → **×1**

`GS` 稀有度抽样（原样）：

```js
function GS(e,t=0,n=0,r){
  let i=Math.max(0,e.player.stats.luck+n),a=i/100,
      o=e.player.level+i/8+(e.stage-1)*12,
      s=(e,t)=>Math.max(0,Math.min(1,(o-e)/(t-e))),
      c=[70/(1+a),24*(1+.5*a),5*(1+a)**2*s(3,10),.9*(1+a)**3*s(8,18),.12*(1+a)**4*s(14,26)]
        .map((e,n)=>e*(n>=t?1:1e-4)*(r&&!r[n]?0:1)),
      l=c.reduce((e,t)=>e+t,0);
  if(l<=1e-6)return t;
  let u=Math.random()*l;
  for(let e=0;e<5;e++)if(u-=c[e],u<=0)return e;
  return 0
}
```

即权重向量：

```text
[ 70/(1+a), 24*(1+.5a), 5*(1+a)^2*clamp((o-3)/7,0,1),
  .9*(1+a)^3*clamp((o-8)/10,0,1), .12*(1+a)^4*clamp((o-14)/12,0,1) ]
a = max(0, luck+n)/100
o = level + luck/8 + (stage-1)*12
```

- `minRarity` 以下的档位权重乘 `1e-4`（不是 0）。
- `r` 传的是「各稀有度是否有可选道具」的 5 元布尔数组；不可用档位直接乘 0。
- 商店调用 `XS(e)`，所以 `t=0`；`GS(e,0,10,i)` 的 `n=10` 是幸运加成。

### 1.4 价格

```js
var rC=[80,130,220,400,750],iC=[1.15,1.25,1.4,1.6,2];

function aC(e,t){return Math.round(rC[cr.get(t).rarity]*rT(e)*e.shopHeat*oC(e))}

var oC=e=>1-.08*Math.min(3,e.player.items.get(`gold-teeth`)??0)

var tT=2.2,nT=1.7;
function rT(e,t=tT){
  let n=e.endless;
  return n
    ? nT**+Math.max(0,Math.floor((e.time-210)/300))*n.curse.chest
    : t**(Math.min(4,Math.max(1,e.stage))-1)
}
```

| 量 | 公式 | 说明 |
|---|---|---|
| 售价 | `round(rC[rarity] * rT * shopHeat * oC)` | `rC[0..4] = 80/130/220/400/750` |
| 关卡缩放 | `2.2^(clamp(stage,1,4)-1)` | 普通：stage 1→1，2→2.2，3→4.84，4→10.648 |
| 无尽缩放 | `1.7^max(0, floor((time-210)/300)) * curse.chest` | 每 300 s 一档，从 210 s 起 |
| gold-teeth 折扣 | `1 - .08*min(3, copies)` | 最多 −24% |
| shopHeat | 见下 | 连买同一档稀有度会涨价 |

```js
get shopHeat(){
  if(this.endless)return 1;
  let e=1;
  for(let t of this.shopBuys.slice(2+Math.floor(this.chestsBought/3)))
    e*=iC[t]??1;
  return e
}
```

- `shopBuys` 是「每次成功购买 push 该道具 rarity」的数组。
- 前 `2 + floor(chestsBought/3)` 次购买不计入热度；之后每次购买把 `iC[rarity]` 连乘。
- 无尽模式热度恒为 **1**。

### 1.5 重掷

```js
rerollCost(){
  let e=.5*rC[0]*rT(this);
  return Math.round(e*(this.endless?1.6**(this.shop?.rerolls??0):1.5**this.shopRerolls)*oC(this))
}
rerollShop(){
  let e=this.rerollCost();
  return !this.shop||this.gold<e?!1:(
    this.gold-=e,this.econ.shop+=e,this.goldSpent+=e,
    this.shop.stock=nC(this),this.shop.rerolls++,this.shopRerolls++,!0
  )
}
```

- 基数 `.5*rC[0]` = **40**。
- 普通：`1.5^shopRerolls`；无尽：`1.6^(shop.rerolls)`。
- **重掷价不含 `shopHeat`**（对比售价 `aC` 含）。
- 每次重掷同时 `shop.rerolls++` 与 `shopRerolls++`。
- 重掷只重掷当前 `stock`，不重置 `sold` 外的其他状态；新库存 `sold` 全为 `undefined`。

### 1.6 库存键（`openShop`）与购买校验

```js
openShop(){
  this.state=`modal`;
  let e=this.endless?100+this.endless.shopVisit:this.tower?200+this.tower.floor:this.stage;
  (!this.shop||this.shop.stage!==e)&&(this.shop={stage:e,stock:nC(this),rerolls:0});
  this.ui.showShop(this,()=>this.resume())
}
```

| 模式 | 库存键 `shop.stage` |
|---|---|
| 普通 | `stage`（1..N） |
| 无尽 | `100 + endless.shopVisit`（每次 Meowth 到场 `shopVisit++`） |
| 塔 | `200 + tower.floor` |

- 同一 `shop.stage` 再次开门时**不重掷**，保留已购状态。

`canHold` 与 `buyShopItem` 原样：

```js
canHold(e){return(this.items.get(e)??0)<(cr.get(e)?.max??10)}

buyShopItem(e){
  return e.sold||this.gold<e.price||!this.player.canHold(e.key)?!1:(
    this.gold-=e.price,this.econ.shop+=e.price,this.goldSpent+=e.price,
    e.sold=!0,this.player.addItem(e.key),
    this.shopBuys.push(cr.get(e.key)?.rarity??0),!0
  )
}
```

校验顺序（短路）：`sold` → 金币不足 → 持有满。三项任一失败都不扣钱。

### 1.7 商人 NPC 计时

| 常量 | 值 | 语义 | 出处 |
|---|---|---|---|
| `meowthT` 初值 | `210` | 首次到场倒计时 210 s | main @1401011 |
| 重置值 | `300` | 到场后下一轮 300 s | main @1402315 |
| `meowthLeft` | `45` | 到场后停留 45 s | main @1407519 |
| 超梦重试 | `30` | 超梦事件激活时 30 s 后重试 | main @1407519 |

驱动（原样）：

```js
this.meowth
  ? (this.meowthLeft-=e)<=0 && t.state==='play' && this.meowthLeaves()
  : (this.meowthT-=e)<=0 && (this.meowthT=300, this.meowthArrives())
```

- 判定顺序：先判 `meowth` 是否存在；不存在才轮到 `meowthT`。
- `meowthArrives` 里 `shopVisit++`，随机点半径 **12–18**（`randomPoint(F,x,z,12,18)`）。
- 超梦激活时 `meowthT=30` 并直接 return（不生成 NPC、不递增 `shopVisit`）。
- 离场只移除 NPC，不关闭已打开的商店面板（面板由玩家自行关闭）。

### 1.8 出售价 `oT`（商店面板右侧）

```js
var iT=[.3,.45,.65,1,1.5],aT=.5;
function oT(e,t){
  let n=aT*rC[t]*rT(e);
  return Math.round(Math.max([10,18,30,50,90][t]*e.stage,Math.min(n,iT[t]*eT(e)))
}
```

- 下限 `[10,18,30,50,90][rarity] * stage`。
- 上限 `iT[rarity] * eT(e)`，`iT = [.3,.45,.65,1,1.5]`。
- `eT(e) = 18 * $w(chestsBought) * (endless.curse.chest ?? 1)`。
- `$w`（原样，注意 30/40/50 段都用 `e-30` 作基数）：

```js
function $w(e){
  let t=35*e;
  return e>10&&(t+=300*(e-10)),
    e>20&&(t+=550*(e-20)),
    e>30&&(t+=1200*(e-30)),
    e>40&&(t+=2400*(e-30)),
    e>50&&(t+=4500*(e-30)),
    (1.22**e+t/30)*1.12**Math.max(0,e-12)
}
```

- 出售交互：点一次进入 `armed`，3 s 内再点一次才真正 `removeItem` + `addGold`；`econ.sold++`。

### 1.9 商店 i18n key

| key（西语原文） | 场景 |
|---|---|
| `Meowth: «¿Tienes dinero, miau?»` | 商店标题 |
| `Renovar surtido · {n} ₽` | 重掷按钮 |
| `VENDIDO` | 已售 |
| `Tienes {n}/{max}` | 持有数 / 上限 |
| `«Ya lo tienes todo, miau. Aquí no me queda nada para ti.»` | 空库存 |
| `Si le compras mucho sin abrir Poké Balls, su próxima tienda saldrá más cara.` | 热度提示（无尽模式隐藏） |
| `Vender tus objetos:` | 出售区标题 |
| `Vender +{n}` | 出售按钮 |
| `¿Vender? Pulsa otra vez` | 二次确认 |
| `Salir` | 关闭 |
| `Ver mi equipo` | 队伍面板 |
| `¡Meowth ha venido con su tienda! Se irá en 45 s` | 到场 toast |
| `Meowth se ha marchado` | 离场 toast |
| `Elige uno` / `Ninguno (+{n} ₽)` | 宝箱替换弹窗（与商店同 UI） |

弹出提示表 `mD.shop`（main @1389312）：

| key | 文本 |
|---|---|
| `Tienda de Meowth` | 标题 |
| `Vende objetos por ₽. {key} cerca para hablar con él; se marcha pasado un rato.` | 说明 |

### 1.10 Godot 落点与差距

- 落点：`src/core/pb_shop.gd` 的 `open` / `price_for` / `reroll_cost` / `reroll` / `buy` / `can_hold` / `shop_heat` / `discount`。
- **已对齐**：`_roll_stock`（16 次 / 4 件 / 去重）、`aC` 售价、`rC`/`iC`/`oC`、`shopHeat` 的非无尽窗口、`canHold` 的 `max??10`。
- **需补**：
  1. `open` 的库存键改为 `endless ? 100+shopVisit : tower ? 200+floor : stage`；
  2. `_stage_scale` 增加无尽分支 `1.7^max(0,floor((time-210)/300))*curse.chest`；
  3. `reroll_cost` 增加无尽 `1.6^shop.rerolls`（且**不乘** `shop_heat`）；
  4. 新增出售价 `sell_price(state, rarity)` = `oT`，以及二次确认 UI；
  5. 商人计时 `210 → 300 / 45` 与 `shopVisit++`、`openShop` 面板；
  6. `can_hold` 目前用 `PbActor.item_power`（float）比较，语义等价于 `.items.get`（int），保留即可；
  7. `_roll_stock` 的 `sold:false` 与 Web 的「未写字段」语义等价，无需改。

---

## 2. 维生素

### 2.1 Web 出处

| 符号 | 文件 | offset | 作用 |
|---|---|---|---|
| 维生素表 `p` | news | @70075 | 26 条定义（`key/name/icon/stat/per/kind/desc/extra/note/dice`） |
| 定义索引 `le` | news | @73688 | `new Map(p.map(e=>[e.key,e]))` |
| `ue(e,t,n)` | news | @73720 | 单条 mod（`n=acc`） |
| `de(e,t)` | news | @73817 | 一个维生素条目的全部 mod |
| `pe(e,t)` | news | @74110 | `loaded-dice` 的随机 roll（`e`=卡值，`t`=picker） |
| `fe` | news | @74270 附近 | `1.5`（dice 倍率） |
| 稀有度倍率 `ie` | news | @54905 | `[1,1.2,1.45,1.75,2.1]` |
| 稀有度名 `ne` | news | @54781 | `Común/Poco común/Raro/Épico/Legendario` |
| 稀有度色 `re` | news | @54850 | `#c8d0dc/#5ad87a/#4aa8ff/#c070ff/#ffc83a` |
| `addVitamin(e,t)` | main | @839647 | 等级/acc/extra/rolls 记账 |
| `get vitCap()` | main | @840389 | `10 + (max-ether ? 2 : 0)` |
| `vitaminSlots` 默认 | main | @835099 | `3` |
| `canHold(e)` | main | @840446 | 道具上限 |
| `KS(e,t)` | main | @1097230 | 出卡候选与权重 |
| `GS(e,t,n,r)` | main | @1096826 | 稀有度抽样（同 §1.3） |
| `qS(e,t)` | main | @1099900 附近 | 卡片文案/预览数值 |

> main 里维生素定义 Map 被 import 成 `er`；新闻里的局部名是 `le`。同一个 `ue/de/pe` 在 main 中被 import 成别的短名（`addVitamin` 里 dice 分支调用的是 `Ln` = `pe`）。

### 2.2 26 条维生素真值表（原样抄写）

| key | name | stat | per | kind | 备注 |
|---|---|---|---|---|---|
| `protein` | Proteína | `physical` | `.1` | `mul` | Daño físico |
| `calcium` | Calcio | `special` | `.1` | `mul` | Daño especial |
| `iron` | Hierro | `armor` | `5` | `add` | Armadura |
| `zinc` | Zinc | `shieldMax` | `12` | `add` | Escudo regenerable |
| `carbos` | Carburante | `moveSpeed` | `.07` | `mul` | Velocidad de movimiento |
| `hp-up` | Más PS | `maxHp` | `18` | `add` | PS máximos |
| `pp-up` | Más PP | `projectiles` | `.5` | `add` | Proyectiles；`Se acumulan: cada +1 entero es un proyectil más (con rareza común, un proyectil cada 2 niveles).` |
| `ether` | Éter | `attackSpeed` | `.08` | `mul` | Velocidad de ataque |
| `dire-hit` | Directo X | `critChance` | `.05` | `add` | Probabilidad de crítico |
| `x-speed` | Velocidad X | `projSpeed` | `.12` | `mul` | Velocidad de proyectil |
| `x-defense` | Defensa X | `evasion` | `.035` | `add` | Evasión |
| `x-attack` | Ataque X | `statusChance` | `.15` | `mul` | Probabilidad de estados |
| `stardust` | Polvo Estelar | `area` | `.1` | `mul` | Área de efecto |
| `elixir` | Elixir | `duration` | `.1` | `mul` | Duración |
| `super-potion` | Superpoción | `regen` | `.7` | `add` | Regeneración de PS |
| `nugget` | Pepita | `gold` | `.15` | `mul` | Pokédólares |
| `exp-candy` | Caramelo Exp. | `xpGain` | `.1` | `mul` | Experiencia |
| `star-piece-v` | Trozo Estrella | `luck` | `10` | `add` | Suerte |
| `max-potion` | Máx. Poción | `lifesteal` | `.02` | `add` | Robo de vida |
| `escape-rope` | Cuerda Huida | `pickupRange` | `1.2` | `add` | Rango de recogida |
| `cursed` | Incienso Maldito | `difficulty` | `.12` | `mul` | `Más enemigos y más fuertes, pero +6% XP y +6% ₽ por nivel`；`extra:[{stat:'xpGain',mul:.06},{stat:'gold',mul:.06}]` |
| `sticky-barb` | Toxiestrella | `thorns` | `10` | `add` | `Las espinas golpean a todos los que te rodean, envenenan y también saltan cuando esquivas.` |
| `enigma-berry` | Baya Enigma | `overheal` | `.05` | `add` | `La curación que no te cabe se guarda como PS extra dorados (se van gastando poco a poco).` |
| `super-lure` | Supercebo | `eliteSpawn` | `.18` | `mul` | `Y +5% de daño a élites y jefes por nivel.`；`extra:[{stat:'eliteDamage',mul:.05}]` |
| `poke-radar` | Pokéradar | `powerup` | `.15` | `mul` | `Salen más power-ups (Imán, MT, bayas…) y duran más.` |
| `loaded-dice` | Dado Trucado | `luck` | `0` | `add` | `Una estadística al azar`；`dice:!0`；`Cada nivel tira el dado: sube la estadística de otra vitamina al azar, un 50% más que esa vitamina.` |

> 上表的 `per`/`kind`/`stat` 与 `data/pb/vitamins.json` 逐字段一致（已核对）。
> `loaded-dice` 的 `stat:'luck'` 与 `per:0` 只是占位；真正效果走 `dice` 分支。

### 2.3 条目结构与 `addVitamin`

运行时条目：

```js
{ level:<int>, acc:<number>, rolls?:<mod[]>, extra?:<number[]> }
```

`addVitamin`（原样）：

```js
addVitamin(e,t){
  let n=this.vitamins.get(e);
  if(this.run.vitTaken=!0,
     n?(n.level>=10&&(n.extra??=[]).push(t),n.level++,n.acc+=t)
      :this.vitamins.set(e,n={level:1,acc:t}),
     er.get(e)?.dice){
    let{mod:e,def:r}=Ln(t,e=>F.pick(e));
    (n.rolls??=[]).push(e);
    let i=e.add??e.mul-1,
        a=r.kind===`mul`||e.stat===`critChance`||e.stat===`evasion`||e.stat===`lifesteal`,
        o=this.run,s=this.pos;
    o.ui.toast(c(`Dado Trucado: {v} {stat}`,{
      v:a?`+${Math.round(i*100)}%`:`+${+i.toFixed(1)}`,
      stat:r.desc.toLowerCase()
    }),r.icon),
    o.vfx.burst(s.x,s.y+1.6,s.z,16777215,12,4,I.Star,.45,.5),
    o.vfx.ring(s.x,s.y+.1,s.z,2.4,16765498,.35,.3)
  }
  this.recompute()
}
```

要点：
- `level` **不封顶**，只按 `vitCap` 限制「能不能再出升级卡」。
- 到 10 级后继续拿卡，`level` 仍 +1，同时把卡值 `t` 追加进 `extra` 数组（历史值）。
- `acc` 永远是「所有卡值之和」，不因超过 10 级而停。
- `loaded-dice` 每次获得都独立 roll 一次，追加进 `rolls`；`rolls` 是 mod 对象数组，不是数值。

### 2.4 `ue` / `de` / `pe` 精确公式

```js
function ue(e,t,n){let r=e.per*n;return e.kind==='add'?{add:r}:{mul:1+r}}

function de(e,t){
  if(er.get(e)?.dice){
    let n={};
    for(let r of t.rolls??[]){
      let i=n[r.stat];
      if(i) i.add==null?i.mul=(i.mul??1)+(r.mul-1):i.add=(i.add??0)+r.add;
      else n[r.stat]=r.add==null?{stat:r.stat,mul:r.mul}:{stat:r.stat,add:r.add};
    }
    return Object.values(n)
  }
  return [
    ue(e,t.level,t.acc),
    ...(e.extra??[]).map(e=>({stat:e.stat,mul:1+e.mul*t.acc}))
  ]
}

var fe=1.5;
function pe(e,t){
  let n=t(p.filter(e=>!e.dice&&!e.extra&&e.stat!=='overheal'&&e.stat!=='powerup')),
      r=n.per*e*fe;
  return {def:n,mod:n.kind==='add'?{stat:n.stat,add:r}:{stat:n.stat,mul:1+r}}
}
```

| 符号 | 语义 |
|---|---|
| `ue(def, level, acc)` | 取 `def.per * acc`；`level` 参数**未使用**。`add` → `{add}`；`mul` → `{mul:1+r}` |
| `de(key, entry)` | 普通维生素：`ue` + 每个 `extra` 的 `{mul:1+extra.mul*acc}`；`loaded-dice`：只返回 `rolls` 按 `stat` 合并后的 mods（忽略 `acc`/`extra`） |
| `pe(value, picker)` | 从「非 dice、无 extra、stat 不是 overheal/powerup」的维生素里随机取一条，幅度 `per*value*1.5` |

`de` 的 dice 合并规则：
- 同 `stat` 且已有 `add` → `add` 累加；
- 否则 `mul` 累加 `(mul-1)`（即保留首次的基数 1）；
- `pe` 返回的 `def` 用于 toast 的 `r.desc.toLowerCase()`。

> 关键：`pe` 的倍率是 `per * 卡值 * 1.5`，**不是** `per * acc`。所以 `loaded-dice` 每级是「另一条维生素的单张卡值 ×1.5」，与那条维生素自己的等级无关。

### 2.5 稀有度档位与 `per` 的关系

```js
Ot = ie = [1, 1.2, 1.45, 1.75, 2.1]
```

- 卡值 `t = Ot[rarity]`，即普通 `1`、非凡 `1.2`、稀有 `1.45`、史诗 `1.75`、传说 `2.1`。
- `addVitamin` 把该卡值累加进 `acc`；`ue` 用 `acc`，所以同一维生素拿 N 张普通卡 = `N × per`。
- `per` 只决定「每 1 点卡值给多少」，稀有度决定「一张卡给多少卡值」。
- 不存在「稀有度改变 per」的独立表；差异**全部**由 `Ot` 承担。

### 2.6 等级上限口径

```js
get vitCap(){return 10+(this.items.has('max-ether')?2:0)}
```

| 口径 | 值 | 用途 |
|---|---|---|
| `vitCap` | `10`，持有 `max-ether` 时 `12` | 决定「还能不能再出升级卡」：`r.level < n.vitCap` |
| `addVitamin` 硬编码 | `level>=10` | 超过 10 级后卡值进 `extra` 桶 |
| `data/pb/vitamins.json` 的 `max` | 无 | 维生素不走 `canHold`，走 `vitCap` |
| `vitaminSlots` | `3`（`player_defaults.move_slots` 同源结构） | 同时拥有的维生素种类上限 |

**Web 的真实怪癖**：持有 `max-ether` 时 `vitCap=12`，所以 11、12 级仍出升级卡；但 `addVitamin` 在 `level>=10` 就把卡值塞进 `extra`，而 `de` 只对 `extra` 用 `mul:1+extra.mul*acc`（`extra` 是数字，没有 `.mul`）。结果：**11/12 级的卡值只在 `acc` 里生效，`extra` 桶是垃圾数据**。Godot `pb_vitamins.add` 已复刻这个行为，不要"修"。

### 2.7 出卡权重（`KS` 的维生素部分，原样）

```js
let s=n.vitamins.size<n.vitaminSlots,c=[];
for(let t of Zt){
  if(i.has('v'+t.key))continue;
  let r=n.vitamins.get(t.key);
  if(r){
    if(r.level<n.vitCap)
      for(let n=0;n<2;n++)
        a.push(()=>({kind:'upVit',vit:t.key,rarity:GS(e),key:'v'+t.key}))
  }else s&&(
    Math.random()<.45
      ? a.push(()=>({kind:'newVit',vit:t.key,rarity:GS(e),key:'v'+t.key}))
      : c.push(t.key)
  )
}
```

- 每种**已拥有且未满级**的维生素贡献 **2 个闭包**；每个闭包在**被调用时**才 `GS(e)` 抽稀有度。
- 每种**未拥有**的维生素：仅在还有空位（`vitamins.size < vitaminSlots`）时，**45%** 概率贡献 **1 个闭包**；失败进入 `c` 兜底池。
- 全部闭包 `F.shuffle` 后逐个调用，按 `key` 去重，取前 `t` 张（`t=3`，实验室 `choice4` 时 4 张）。
- 不足时先用 `newMove` 候选 `o` 补齐，再用 `c` 里的未拥有维生素以 `newVit` 补齐（此时也调 `GS(e)`）。
- 结论：**升级卡出现概率 ∝ 2×已拥有数量**；新维生素 ∝ `0.45×未拥有数量`。不是均匀分布。

### 2.8 展示格式（`qS`）

```js
case `newVit`:case `upVit`:{
  let e=er.get(t.vit),i=r.vitamins.get(t.vit),a=e.per*Ot[t.rarity],
      o=e.kind===`mul`||e.stat===`critChance`||e.stat===`evasion`||e.stat===`lifesteal`
        ? `+${+(a*100).toFixed(1)}%`:`+${+a.toFixed(2)}`,
      s=e.dice
        ? c(`Tira el dado: la estadística de una vitamina al azar, ×{n}`,{n:n(ye*Ot[t.rarity],2)})
        : `${o} ${e.desc.toLowerCase()}`,
      l=e.extra?.length
        ? [`${o} ${(Zy[e.stat]?.[0]??e.desc).toLowerCase()}`,
           ...e.extra.map(e=>`+${+(e.mul*Ot[t.rarity]*100).toFixed(1)}% ${(Zy[e.stat]?.[0]??String(e.stat)).toLowerCase()}`)]
        : e.note?[s,e.note]:[s];
  return{title:e.name,
    sub:i?c(`Nivel {a} → {b} (máx. {max})`,{a:i.level,b:i.level+1,max:r.vitCap}):c(`Nueva vitamina`),
    lines:l,icon:`item:`+e.icon}
}
```

- 预览数值 `a = per * Ot[rarity]`（**单张卡**，不是累计）。
- 百分比类：`mul`、`critChance`、`evasion`、`lifesteal`；其余用两位小数。
- `loaded-dice` 的文案是 `×1.5*Ot[rarity]`（保留 2 位）。
- 副标题：`i` 已存在 → `Nivel {a} → {b} (máx. {max})`（`max=vitCap`）；否则 `Nueva vitamina`。
- 有 `note` 时第二行追加 `note`。

### 2.9 维生素 i18n key

| key | 场景 |
|---|---|
| 上表 26 个 `name` | 卡名 |
| 上表 26 个 `desc` | 效果描述（会被 `.toLowerCase()`） |
| 上表 `note` 文本 | 追加说明 |
| `Nivel {a} → {b} (máx. {max})` | 升级卡副标题 |
| `Nueva vitamina` | 新卡副标题 |
| `Tira el dado: la estadística de una vitamina al azar, ×{n}` | loaded-dice 描述 |
| `Dado Trucado: {v} {stat}` | loaded-dice 获得 toast |
| `Proteína`/`Calcio`/... | 与 `name` 同 |

### 2.10 Godot 落点与差距

- 落点：`src/core/pb_vitamins.gd`（`add` / `mods_for` / `preview`）、`src/core/pb_cards.gd:105 roll_vitamin`。
- **已对齐**：`add` 的 `level>=10 → extra`、`acc+=t`、dice rolls；`mods_for` 的 `de` 合并；`_base_mod` 的 `ue`；`_roll_dice` 的 `pe`（1.5）；`cap_for` 的 `10 + max-ether?2`。
- **需注意/修正**：
  1. `pb_cards.roll_vitamin` 目前是「先选 key 再抽一次稀有度」，与 Web「每维生素 2 个独立闭包、选中时才 roll」的分布不同。若要严格对齐，应重写为闭包列表 + shuffle + 去重。
  2. `preview` 的 `level` 计算在超过 10 级时不进 `extra`（Web 会进），但展示只用到 `acc`，影响仅是「预览 mods」与真实一致，可保留。
  3. 注释 offset 过时：
     - `addVitamin` 实际 @**839647**（文件头写的 839470）
     - `vitCap` 实际 @**840389**（写的 841200）
     - `KS` 实际 @**1097230**（写的 1099962）
     - `GS` 实际 @**1096826**（写的 1096835）
  4. `data/pb/vitamins.json` 已含 26 条，字段与 news `p` 一致；无需重建。

---

## 3. 进化

### 3.1 Web 出处

| 符号 | offset | 作用 |
|---|---|---|
| `runEvolution(e,t)` | main @6543 | 数据层求下一步进化目标与等级 |
| `evolutionsOf(e)` | main @6493 | `this.evolutions.get(e) ?? []` |
| `planEvolution(e,t)` | main @1514341 | 结合 roster/evoLevels 的最终计划 |
| `evoReady()` | main @1541178 | 是否可以进化 |
| `tryEvolve()` | main @1541278 | 触发分支选择或演出 |
| `doLevelUp()` | main @1541606 | 升级入口（先进化，后出卡） |
| `startEvolution()` | main @1543295 | 3.6 s 演出 + 结算 |
| `setSpecies(e)` | main @837293 | 切物种 + 重算 + HP 规则 |
| `showBranch` | main @2190988 | 伊布分支选择 UI |
| `showEvolution` | main @2191571 | 进化中 HUD |
| `evolutionReveal` | main @2192719 | 进化后揭示卡 |

### 3.2 `runEvolution` / `evolutionsOf`（原样）

```js
evolutionsOf(e){return this.evolutions.get(e)??[]}

runEvolution(e,t){
  let n=this.evolutionsOf(e);
  if(!n.length)return null;
  let r=t??(n.length>1?n[Math.random()*n.length|0]:n[0]),
      i=this.get(e),
      a=r.evoLevel??(i.evoStage===0?20:34);
  return this.evolutionsOf(r.id).length
    ? {to:r,level:Math.max(16,Math.min(30,Math.round(8+a)))}   // 还有下一段
    : {to:r,level:Math.max(36,Math.min(50,Math.round(22+a*.6)))} // 最终段
}
```

| 情况 | 进化等级 `level` |
|---|---|
| `to` 还能再进化 | `clamp(round(8+a), 16, 30)` |
| `to` 是最终形态 | `clamp(round(22+a*.6), 36, 50)` |
| `a` 来源 | `r.evoLevel ?? (源物种.evoStage===0 ? 20 : 34)` |

- 多分支时若未指定 `t`，**随机**选一个（`n[Math.random()*n.length|0]`）。
- 源物种 `evoStage` 取的是**物种数据**的 `evoStage`（0 基），不是玩家等级。

### 3.3 `planEvolution`（原样）

```js
planEvolution(e,t){
  let n=this.player?.roster;
  if(n?.branch&&e===n.id)return{to:-1,level:n.evoLevel??36};
  let r=j.runEvolution(e);
  if(!r)return null;
  let i=n?.evoLevel&&e===n.id?n.evoLevel:r.level;
  if(n?.evoLevels){
    let k=0;
    for(let s=e;s!==n.id&&j.get(s).evoFrom!=null;s=j.get(s).evoFrom)k++;
    n.evoLevels[k]!=null&&(i=n.evoLevels[k])
  }
  return{to:r.to.id,level:Math.max(i,t)}
}
```

- 普通模式没有 `roster`，结果为 `{to:runEvolution(e).to.id, level:Math.max(runEvolution.level, t)}`。
- `roster.branch && e===roster.id` → `to=-1`（伊布分支选择），等级 `roster.evoLevel ?? 36`。
- `roster.evoLevels` 允许按链上位置 `k` 覆盖等级（roster/league 专用）。
- `t` 通常是 `player.level` 或 `player.level+3`（见 §3.5）。

### 3.4 触发时机与状态机

```js
evoReady(){let e=this.nextEvo;return!!e&&this.player.level>=e.level&&(e.to===-1||j.hasSprite(e.to))}

tryEvolve(){
  return this.evoReady()
    ? (this.nextEvo.to===-1&&this.player.roster?.branch
        ? (this.state='modal',this.ui.showBranch(this,...),!0)
        : (this.startEvolution(),!0))
    : !1
}

doLevelUp(){
  if(this.pendingLevels<=0||this.tryEvolve())return;
  ... // 出卡
}
```

| 步骤 | 条件 | 结果 |
|---|---|---|
| 1 | `nextEvo` 存在 | 继续 |
| 2 | `player.level >= nextEvo.level` | 继续 |
| 3 | `nextEvo.to === -1` | 分支选择：`state='modal'`，`showBranch` |
| 4 | 否则 | `startEvolution()` |
| 5 | `startEvolution` 返回后 | `doLevelUp` **提前 return**：本次升级**不出卡** |

- `nextEvo` 初始由开局/进化结算 `planEvolution` 产生。
- `pendingLevels` 是队列；一次升级若触发了进化，这一级就被进化消耗。
- `doLevelUp` 在 `pendingLevels>0` 时被主循环反复调用。

### 3.5 `startEvolution` 演出与结算（原样关键段）

```js
startEvolution(){
  let e=this.player.speciesId,t=this.nextEvo.to,n=this.player,r=3.6,
      i=da[j.get(t).types[0]],a=da[n.types[0]],o=Math.round(n.maxHp);
  this.state='evolving';
  this.sprites.get(t);
  this.audio.evolve(r);
  this.audio.duck(.2,4.8);
  this.cry(e);
  this.ui.showEvolution(e,t,r);
  let s=this.camYaw;
  this.setCine({follow:-2,dist:3.6,pitch:.22,orbit:.35});
  ...
  this.animate(r, o=>{ ... }, ()=>{
    n.speciesId=e;            // 先还原旧物种（演出里在闪烁切换）
    n.setSpecies(t);          // 真正切换
    n.flash=1;
    n.renderScale=1;
    n.iframes=Math.max(n.iframes,2.6);
    this.nextEvo=this.planEvolution(t,n.level+3);
    this.stats.evolutions++;
    this.firstEvoAt??=this.time;
    this.meta.count('evolutions',1);
    this.meta.unlockForm(t);
    ... // 闪光/环/粒子/震荡
    for(let e of this.enemies.within(r,a,c,18))
      this.enemies.flags[e]&R.Capture||(
        this.enemies.flags[e]&(R.Boss|12290)
          ? this.combat.hit(e,this.enemies.maxHp[e]*.05,{type:n.types[0],cls:'special',fixed:!0,silent:!0,noReact:!0})
          : this.combat.hit(e,80*n.level,{type:n.types[0],cls:'special',silent:!0,knock:8,noReact:!0}
      );
    this.cry(t);
    this.audio.evolveDone();
    this.ui.evolutionReveal(e,t,o,Math.round(n.maxHp),...);
    this.shake(.6);
    this.state='play';
    this.cine.want=0;
    this.yawBack=s;
    this.later(.45,()=>this.ui.endCinematic());
    this.evoHold=2.4;
  })
}
```

时间轴：

| 时间 | 事件 |
|---|---|
| 0 s | `state='evolving'`、`showEvolution(旧,新,3.6)`、`audio.evolve(3.6)`、`audio.duck(.2,4.8)`、`cry(旧)`、电影机位 `follow:-2, dist:3.6, pitch:.22, orbit:.35` |
| 0–0.9 s | `flash` 渐亮；旧属性色粒子；`renderScale=1+flash*.05` |
| 0.9–3.2 s | 新旧物种每 `floor(l*2)%2` 闪烁；光束、环、星粒子 |
| 3.15–3.6 s | `renderScale` 额外 `+0.35`，轻微抖动 `shake(.02)` |
| 3.6 s（完成） | `setSpecies`、`nextEvo=planEvolution(new, level+3)`、`stats.evolutions++`、`meta.count('evolutions',1)`、`meta.unlockForm`、范围 18 的冲击波、`evolutionReveal`、`shake(.6)`、`state='play'`、`evoHold=2.4` |

结算顺序（严格）：
1. `speciesId = 旧`
2. `setSpecies(新)`
3. `flash=1`, `renderScale=1`
4. `iframes = max(iframes, 2.6)`
5. `nextEvo = planEvolution(新, level+3)`
6. `stats.evolutions++`
7. `firstEvoAt ??= time`
8. `meta.count('evolutions', 1)`
9. `meta.unlockForm(新)`
10. `evolutionReveal(旧, 新, 旧maxHp, 新maxHp, ...)`

冲击波：
- 半径 **18**，跳过 `flags & R.Capture`（捕获态）。
- `flags & (R.Boss | 12290)` → `maxHp*0.05`，`fixed:!0, silent:!0, noReact:!0`。
- 其余 → `80 * player.level`，`silent:!0, knock:8, noReact:!0`。

### 3.6 `setSpecies` 与属性/招式继承（原样）

```js
setSpecies(e){
  let t=this.hp/this.maxHp;
  this.speciesId=e;
  this.data=j.get(e);
  this.types=this.data.types;
  this.evoStage++;
  this.recompute();
  this.hp=Math.min(this.maxHp,this.maxHp*Math.max(t,.5)+this.maxHp*.3)
}
```

| 项 | 规则 |
|---|---|
| 基础属性 | 换成新物种 `data`，`recompute()` 重算（含属性成长、lab、卡片/道具/维生素 mods） |
| 类型 | 直接替换为新物种 `types`（不保留旧类型，除非道具另有 typeBoost） |
| `evoStage` | 玩家对象的计数器 `++`（不是物种的 `evoStage`） |
| 招式 | **不继承、不新增、不遗忘**；`setSpecies` 内**没有** `addMove`。进化前学到的招式全部保留，新物种的可学招式不会自动获得 |
| HP 比例 | `t = hp/maxHp`（旧）；新 `hp = min(newMax, newMax*max(t,.5) + newMax*.3)` |
| 护盾/超量治疗 | 未在 `setSpecies` 里处理；`recompute()` 会按 `shieldMax` 重算上限，现有 shield/overheal 由 `recompute` 的通用逻辑保留 |

> HP 规则等价于：**进化后至少回到 80% 最大 HP**（`t>=.5` 时 `t*newMax + .3*newMax`；`t<.5` 时 `.5*newMax + .3*newMax = .8*newMax`）。

### 3.7 `stats` 与图鉴写入时机

| 写入点 | 内容 | 时机 |
|---|---|---|
| `this.stats.evolutions++` | 本局统计 | 3.6 s 演出**完成回调**内，`setSpecies` 之后 |
| `this.firstEvoAt ??= this.time` | 首次进化时间 | 同上 |
| `this.meta.count('evolutions',1)` | 账号级计数 | 同上 |
| `this.meta.unlockForm(t)` | 图鉴形态解锁（新物种 id） | 同上 |
| `this.nextEvo = planEvolution(t, level+3)` | 下一次进化计划 | 同上，在 `stats.evolutions++` 之前 |
| `ui.evolutionReveal(...)` | UI 揭示卡 | 同上，最后 |

- 进化**不会**在 `startEvolution` 开始时写 `stats`；中途被中断（理论上无）不会写。
- 图鉴解锁的是**目标物种 id**，不是形态 key。

### 3.8 进化 i18n key

| key | 场景 |
|---|---|
| `¿Eh? ¡{name} está evolucionando!` | 进化中 HUD，`name=旧物种` |
| `¡Enhorabuena! {name} ha evolucionado a` | 揭示卡，`name=旧物种` |
| `PS máx.` | 揭示卡里的 HP 对比标签 |
| `¡Eevee va a evolucionar!` | 分支选择标题（硬编码 Eevee） |
| `Elige en qué quieres que evolucione: cambiará su tipo y su poder` | 分支选择说明 |
| 新物种 `name` / `types` | 揭示卡与分支卡 |

### 3.9 Godot 落点与差距

- 数据层：`src/core/pb_data_registry.gd:141 evolutions_of(id)` 已等价 `evolutionsOf`；`:146 evo_chain_root` 已可替代 `evoFrom` 回溯。
- **需新增运行层**（建议 `src/core/pb_evo.gd`，纯 RefCounted）：
  - `run_evolution(species_id, forced_id := -1) -> Dictionary`：照抄 §3.2 的等级公式；
  - `plan_evolution(actor, level_arg) -> Dictionary`：普通模式忽略 roster，返回 `{to, level}`；
  - `ready(actor) -> bool`：`level >= next.level` 且 `to` 有 sprite；
  - `set_species(actor, new_id)`：照抄 §3.6（HP 公式、`recompute`、`evoStage`），**不学招式**；
  - `start_evolution(state)`：`state='evolving'`、3.6 s 计时、结算顺序照抄 §3.5。
- **触发钩子**：`src/core/pb_run.gd:559 open_offers` 开头，在 `PbCards.offer` 之前：
  ```gdscript
  if int(state["pendingLevels"]) > 0 and PbEvo.try_evolve(state):
      return   # 本次升级被进化消耗，不出卡
  ```
  进化完成回调里 `pendingLevels -= 1`；若仍 > 0 再 `open_offers`。
- `nextEvo` 需要新增到 run state（`{"to": int, "level": int}`），开局用 `plan_evolution(species, level)` 初始化。
- `stats.evolutions` 字段已存在（`pb_run.gd:60`），直接 `+= 1`。
- `PbActor` 目前无 `evoStage` 字段；按 §3.6 新增 `evo_stage`（或按需从物种 `evoStage` 推导）。
- 分支：`roster.branch` 属于 roster/league 模式，Godot 当前无该模式；普通模式只需处理 `to != -1`。

---

## 4. 天气事件调度

### 4.1 结论：事件与 `baseWeather` 是两套系统

- `baseWeather` 是**生物群系常驻天气**（`clear/rain/sand/sun/hail/fog/ash`），只影响伤害倍率与视觉。
- `fog/storm/eclipse/meowth` 是**限时地图事件**，有自己的 `kind/left/done` 状态，**不修改** `baseWeather`。
- 二者共用 `weather` 字段：`setWeather(kind, dur)` 会临时覆盖 `weather`，到期回落到 `baseWeather`。

### 4.2 Web 出处

| 符号 | offset | 作用 |
|---|---|---|
| `uS` 事件表 | main @1061261 | `fog/storm/eclipse/meowth` 的 name/sub/color/dur/pool/look |
| `dS=52` | main @1062373 | meowth 事件物种 id（Meowth） |
| `class fS` | main @1062329 | 事件控制器（`RD` 内的 `events` 字段） |
| `get blind()` | main @1062871 | `kind==='fog' && k>.5` |
| `get eliteBonus()` | main @1062889 | `kind==='eclipse' ? .12 : 0` |
| `get marker()` | main @1062907 | 事件 Meowth 的存活标记 |
| `startRandom()` | main @1062999 | 选事件、前置条件 |
| `start(e)` | main @1063313 | 进入事件 |
| `pool()` | main @1063720 | 事件刷怪池 |
| `end(e=!1)` | main @1063823 | 结束与回落 toast |
| `update(e)` | main @1064054 | 计时、`k` 渐变 |
| `updateSpawns(e)` | main @1064938 | 每 4 s 刷怪 |
| `fogFx` | main @1065573 | 雾粒子 |
| `stormFx` | main @1066155 | 雨/雷 |
| `bolt` | main @1067171 | 落雷伤害 |
| `eclipseFx` | main @1068070 | 闪光判定 |
| `spawnMeowth()` | main @1068668 | 事件 Meowth 生成 |
| `updateMeowth(e)` | main @1069149 | 掉币/逃离 |
| `onHit(e)` | main @1069585 | 被打掉币 |
| `onKilled(e)` | main @1069786 | 击杀奖励 |
| director `case 'event'` | main @887987 | 时间线触发与重试 |
| `setBaseWeather(e)` | main @1520977 | 常驻天气切换 |
| `setWeather(e,t)` | main @1521073 | 临时天气 |

### 4.3 `uS` 事件表（原样）

```js
uS={
  fog:{name:c('Niebla espectral'),
       sub:c('Una niebla helada lo cubre todo... y algo se mueve en ella'),
       color:'#9a7aff',dur:45,
       pool:[[92,41,96],[93,42,96],[94,93,97]],
       look:{top:3814480,bottom:6971528,fog:5919348,near:2,far:26,light:.62,
             sun:12101887,clouds:[.55,.52,.66],cover:.6,eclipse:0,vignette:.62,tint:[.74,.72,.9]}},
  storm:{name:c('Tormenta eléctrica'),
         sub:c('Caen rayos: aléjate de las marcas amarillas'),
         color:'#ffd23a',dur:40,
         pool:[[100,81,25],[101,82,125,26],[101,82,125,135]],
         look:{top:2765894,bottom:6978192,fog:5661306,near:22,far:110,light:.58,
               sun:13162751,clouds:[.36,.4,.48],cover:1,eclipse:0,vignette:.55,tint:[.62,.68,.82]}},
  eclipse:{name:c('Eclipse'),
           sub:c('La luz se apaga. Salen los Pokémon de la noche... y algún variocolor'),
           color:'#ff6a5a',dur:40,
           pool:[[41,92,96,35,43],[42,93,97,36,44],[42,94,97,36,45]],
           look:{top:1182244,bottom:5909050,fog:3809844,near:26,far:120,light:.42,
                 sun:16743002,clouds:[.32,.22,.34],cover:.3,eclipse:1,vignette:.65,tint:[.58,.4,.5]}},
  meowth:{name:c('Meowth dorado'),
          sub:c('Suelta monedas con cada golpe. ¡Atrápalo antes de que escape!'),
          color:'#ffc83a',dur:25}
}
```

| 事件 | dur | pool 结构 | 刷怪池索引 |
|---|---|---|---|
| `fog` | 45 | 3 档 × 3–5 个 id | `pool[min(2, stage-1)]` |
| `storm` | 40 | 3 档 × 3–5 个 id | 同上 |
| `eclipse` | 40 | 3 档 × 3–5 个 id | 同上 |
| `meowth` | 25 | 无 | 不刷怪，只生成 Meowth |

> 池按 `Ht(pool[idx]).filter(id => hasSprite(id))` 过滤缺图物种。

### 4.4 选择与前置条件（原样）

```js
startRandom(){
  let e=this.run;
  if(this.active||e.boss.alive||e.stageCleared||e.mapEvents.busy)return!1;
  let t=['fog','storm','eclipse','meowth'].filter(e=>!this.done.has(e));
  return!t.length&&e.endless&&(this.done.clear(),t=['fog','storm','eclipse','meowth']),
    !t.length||this.start(F.weighted(t,e=>e==='meowth'?.8:1))
}
```

| 条件 | 含义 |
|---|---|
| `active` | 已有事件进行中 → 不触发 |
| `boss.alive` | Boss 存活 → 不触发 |
| `stageCleared` | 本关已清 → 不触发 |
| `mapEvents.busy` | 地图事件（宝箱/祭坛等）占用 → 不触发 |
| `done` | 本次 run 已出现过的事件集合 |

- 普通模式：每个事件**只会出现一次**；4 个都用完后 `startRandom` 返回 `false`，后续 event beat 全部失败（重试到上限后不再排）。
- 无尽模式：4 个都用完后 `done.clear()` 并全部重新可用。
- 权重：`meowth` **0.8**，其余 **1**；用 `F.weighted` 归一化抽取。

### 4.5 `start` / `end` / `update`（原样）

```js
start(e){
  let t=this.run,n=uS[e];
  this.active&&this.end(!0);
  this.kind=e;
  this.left=n.dur;
  this.spawned=0;
  this.spawnT=2;
  this.boltT=3;
  this.shinyRolled=!1;
  this.done.add(e);
  for(let e of this.pool())t.sprites.get(e);
  return e==='meowth'&&!this.spawnMeowth()
    ? (this.kind=null,!1)
    : (t.ui.banner(c('¡{name}!',{name:n.name}),n.sub,n.color,
        e==='meowth'?{species:dS}:void 0),
       t.audio.alarm(),
       e==='storm'&&t.audio.boom(.6),
       !0)
}

end(e=!1){
  let t=this.run;
  if(!e&&this.kind){
    let e=this.kind==='fog'?c('La niebla se disipa')
      :this.kind==='storm'?c('La tormenta se aleja')
      :this.kind==='eclipse'?c('La luz vuelve'):'';
    e&&t.ui.toast(e,null)
  }
  this.kind=null,this.left=0
}

update(e){
  let t=this.run,n=this.kind,r=this.flash;
  this.kind
    ? (this.left-=e,
       this.kind==='meowth'
         ? (this.updateMeowth(e),this.k=Math.max(0,this.k-e/3))
         : (this.k=Math.min(1,this.k+e/3),
            this.updateSpawns(e),
            this.kind==='fog'?this.fogFx(e)
              :this.kind==='storm'?this.stormFx(e)
              :this.eclipseFx(e)),
       this.left<=0&&this.end())
    : this.k=Math.max(0,this.k-e/3),
  this.flash=Math.max(0,this.flash-e*5),
  (this.k!==n||this.flash>0||r>0)&&t.pushLook()
}
```

| 项 | 规则 |
|---|---|
| `end()` 无参 | **会**弹「结束」toast（自然到期） |
| `end(true)` | **不**弹 toast（被新事件顶替 / meowth 死亡 / 逃跑） |
| `k` 渐变 | 非 meowth：`k += dt/3`；meowth：`k -= dt/3`（事件期间不留视觉覆盖） |
| `flash` 衰减 | `flash -= dt*5` |

### 4.6 刷怪（`updateSpawns`）

```js
updateSpawns(e){
  let t=this.run,n=t.enemies,r=this.pool();
  if(!r.length||this.spawned>=30||this.left<6||(this.spawnT-=e,this.spawnT>0))return;
  this.spawnT=4;
  let i=t.player.pos,a=3+t.stage;
  for(let e=0;e<a;e++){
    let a=F.range(0,Math.PI*2),o=F.range(20,27),
        s=i.x+Math.cos(a)*o,c=i.z+Math.sin(a)*o;
    if(!t.terrain.inBounds(s,c,5))continue;
    let l=this.kind==='eclipse'&&e===0&&t.stageTime>90?R.Elite:0,
        u=n.spawn(F.pick(r),s,c,t.director.hpMult(),t.director.dmgMult(),l);
    u<0||(this.spawned++,
      this.kind==='fog'&&(n.flags[u]|=R.Flying,n.xp[u]*=2,t.vfx.add.spawn(...)))
  }
}
```

| 项 | 值 |
|---|---|
| 触发间隔 | `spawnT=4` s |
| 单次数量 | `3 + stage` |
| 半径 | `20–27`，`inBounds(..., 5)` |
| 总数上限 | `spawned < 30` |
| 剩余时间保护 | `left < 6` 停止刷 |
| eclipse 保底精英 | **每个 tick 的第一个** 且 `stageTime>90` → `R.Elite` |
| fog 产物 | `flags |= R.Flying`，`xp *= 2`，附加 Wisp 粒子 |

### 4.7 storm 落雷（`stormFx` / `bolt`）

```js
stormFx(e){
  let t=this.run,n=t.r.camera.position,r=t.player,i=t.enemies,a=t.biome.id!=='desert',
      o=Math.floor((a?90:18)*e*10*this.k+Math.random());
  ... // 雨滴/沙尘
  if(a&&(this.wetT-=e)<=0){
    this.wetT=.5;
    for(let e of i.within(r.pos.x,r.pos.z,25))i.wet[e]=Math.max(i.wet[e],2)
  }
  if(this.boltT-=e,this.boltT>0||this.k<.6)return;
  this.boltT=F.range(.9,1.6);
  let s,c,l;
  if(F.chance(.35)){
    let e=F.range(0,Math.PI*2),t=F.range(0,3);
    s=r.pos.x+Math.cos(e)*t,c=r.pos.z+Math.sin(e)*t,l=1.1
  }else{
    let e=i.within(r.pos.x,r.pos.z,26),t=e.length?F.pick(e):-1;
    t>=0?(s=i.x[t],c=i.z[t]):(s=r.pos.x+F.range(-18,18),c=r.pos.z+F.range(-18,18));
    l=.6
  }
  let u=t.terrain.surface(s,c);
  t.vfx.telegraph(s,u,c,3,16773754,l);
  t.later(l,()=>this.bolt(s,u,c,3))
}

bolt(e,t,n,r){
  let i=this.run,a=i.player,o=i.enemies;
  ... // 闪电/闪光/环/粒子
  this.flash=1;
  Math.hypot(a.pos.x-e,a.pos.z-n)<r&&a.pos.y-t<2.5&&
    a.hurt(16*i.director.dmgMult()*i.diff.enemyDamage,'electric',-1,NaN,NaN,!1,0,
      {kind:'event',species:0});
  for(let t of o.within(e,n,r+1.5)){
    let e=o.flags[t]&(R.Boss|R.Alpha|R.Totem|R.Summoner);
    i.combat.hit(t,o.maxHp[t]*(e?.04:.3),
      {type:'electric',cls:'special',fixed:!0,noReact:!0});
    o.isAlive(t)&&i.combat.applyStatus(t,'paralysis',0)
  }
}
```

| 项 | 值 |
|---|---|
| 雷击节奏 | 首个 `boltT=3`；之后 `range(.9,1.6)`；`k<.6` 时不落雷 |
| 雷击点 | 35% 玩家附近（半径 0–3）；否则 26 码内随机敌人；无敌人则玩家周围 ±18 |
| 预警圈 | **半径 3**，颜色 `16773754` |
| 预警延迟 `l` | 玩家目标 **1.1 s**；敌人目标 **0.6 s** |
| 玩家伤害 | `16 * dmgMult * enemyDamage`，`electric`，`fixed=false`（第 6 参数 `!1`） |
| 玩家命中 | `dist < 3` 且 `player.y - ground < 2.5` |
| 敌人伤害 | `maxHp*(Boss|Alpha|Totem|Summoner ? .04 : .3)`，`fixed:!0`，附加 `paralysis` |
| 敌人命中半径 | `r+1.5 = 4.5` |
| 潮湿 | 非沙漠：每 0.5 s 把 25 码内敌人 `wet = max(wet,2)` |
| 沙漠 | 不降雨、不潮湿，仅沙尘粒子；雷照常落 |

### 4.8 eclipse 闪光判定

```js
eclipseFx(e){
  let t=this.run,n=t.r.camera.position;
  ... // 星空粒子
  if(!this.shinyRolled&&this.left<uS.eclipse.dur-12){
    let e=t.capture.state;
    if(e==='roaming'||e==='weakened'||e==='throwing'||(this.shinyRolled=!0,t.endless))return;
    let n=this.pool();
    n.length&&F.chance(Math.min(.9,(me.eclipse+Math.min(me.zone,t.player.stats.luck/me.luckDiv))*t.meta.shinyRate()))
      &&t.capture.spawnShiny(n)
  }
}
```

- 判定窗口：事件剩余 `< dur-12`（即事件开始 **12 s 后**）只掷一次。
- 概率：`min(.9, (0.2 + min(0.08, luck/1000)) * meta.shinyRate())`
  - `me.eclipse=.2`、`me.zone=.08`、`me.luckDiv=1e3`（news `ot={zone:.08,eclipse:.2,luckDiv:1e3}`）。
- 无尽模式**不掷**闪光（`t.endless` 时直接 return）。
- 捕获状态 `roaming/weakened/throwing` 时**延迟**（不置 `shinyRolled`）。
- `eliteBonus` 字段：`get eliteBonus(){return this.kind==='eclipse'?.12:0}`（供其它系统读取，事件本身不直接加算）。

### 4.9 meowth 特殊行为

```js
spawnMeowth(){
  let e=this.run,t=e.player.pos;
  e.sprites.get(dS);
  for(let n=0;n<12;n++){
    let n=F.range(0,Math.PI*2),r=F.range(14,20),
        i=t.x+Math.cos(n)*r,a=t.z+Math.sin(n)*r;
    if(!e.terrain.inBounds(i,a,10))continue;
    let o=e.enemies.spawn(dS,i,a,e.director.hpMult(),1,R.Treasure);
    return o<0?!1:(this.meowth=o,this.meowthGen=e.enemies.gen[o],
      e.enemies.speed[o]=7.4,e.enemies.flags[o]&=~(R.Ranged|R.Charger),
      e.vfx.burst(...),e.cry(dS),!0)
  }
  return!1
}

updateMeowth(e){
  let t=this.run,n=t.enemies,r=this.meowth;
  this.coinCd-=e;
  this.marker
    ? (Math.random()<e*12&&t.vfx.trail(...),
       this.left<=0&&(t.vfx.burst(...),t.vfx.dust(...),n.kill(r),
                      this.meowth=-1,t.ui.toast(c('Meowth dorado se escapa con su botín'),null)))
    : this.end(!0)
}

onHit(e){
  if(e!==this.meowth||this.coinCd>0)return;
  let t=this.run,n=t.enemies;
  this.coinCd=.16;
  t.pickups.spawn('coin',n.x[e],n.y[e]+.5,n.z[e],Math.ceil((2+t.stage*2)*t.player.stats.gold));
  t.audio.coin()
}

onKilled(e){
  if(e!==this.meowth)return;
  let t=this.run,n=t.enemies,r=t.player.stats;
  for(let i=0;i<30;i++)
    t.pickups.spawn('coin',n.x[e],n.y[e],n.z[e],Math.ceil((4+t.stage*4)*r.gold));
  t.vfx.burst(...);
  t.ui.banner(c('¡Día de Pago!'),c('Meowth dorado suelta todas sus monedas'),'#ffc83a',{species:dS});
  t.audio.power();
  this.meowth=-1;
  this.end(!0)
}
```

| 项 | 规则 |
|---|---|
| 物种 | `dS = 52`（Meowth） |
| 生成 | 最多 12 次，半径 `14–20`，`inBounds(...,10)` |
| 属性 | `hp = hpMult()`，`dmg = 1`（原始值，不是 `dmgMult`），`flags = R.Treasure` |
| 移动 | `speed=7.4`，清除 `Ranged|Charger` |
| 存活 | 事件 `dur=25` s |
| 被击掉币 | 每 `0.16` s 最多一次；金币 `ceil((2+stage*2)*stats.gold)` |
| 击杀 | 30 枚金币，每枚 `ceil((4+stage*4)*stats.gold)`；banner `¡Día de Pago!`；`end(true)` |
| 超时逃离 | `n.kill(r)` + toast `Meowth dorado se escapa con su botín`；**不掉奖励** |
| `marker` | 由 `meowth` 索引 + `enemies.gen` 校验；无效则 `end(true)` |

- `this.marker` 定义（main @1062907，原样）：

```js
get marker(){
  let e=this.run.enemies,t=this.meowth;
  return t>=0&&e.gen[t]===this.meowthGen&&e.isAlive(t)?{x:e.x[t],z:e.z[t],i:t}:null
}
```
- 注意：`onKilled` 与 `updateMeowth` 的逃离都会调用 `end(!0)`，不会弹「结束」toast。

### 4.10 director 时间线中的事件

普通（`buildTimeline`，stage 1 与 stage≥2）：

```js
e.stage===1
  ? n.push({t:t.range(170,300),kind:'event'})
  : n.push({t:t.range(130,230),kind:'event'},{t:t.range(340,460),kind:'event'})
```

无尽（`beats`）：

```js
{kind:'event',next:t.range(170,230),every:[220,260]}
```

| 模式 | 首次 | 后续 |
|---|---|---|
| 普通 stage 1 | 1 个，`170–300 s` | 无 |
| 普通 stage ≥2 | 2 个，`130–230 s` / `340–460 s` | 无 |
| 无尽 | `170–230 s` | 每 `220–260 s` |

- tier 的 `early` 偏移**显式排除** `card` 与 `event`：`e.kind!=='card'&&e.kind!=='event'`，所以事件不受难度提前影响。

事件 beat 失败重试（原样）：

```js
case 'event':{
  let n=t.events.startRandom();
  !n&&t.endless
    ? this.retry(e,15)
    : !n&&!t.stageCleared&&t.stageTime+15<540
      && this.timeline.push({t:t.stageTime+15,kind:e});
  break
}
```

| 情况 | 处理 |
|---|---|
| 无尽且失败 | `retry(event,15)`：把该 beat 的 `next = min(next, time+15)` |
| 普通且失败 | 若未清关且 `stageTime+15 < 540`，在 `+15 s` 重排一次 |
| 普通且 `stageTime+15 >= 540` | 不再重试 |

> 普通模式 `done` 用完后（4 个事件都已出现），后续 event beat 会全部失败；stage 1 只有 1 个 beat，所以最多 1 次事件；stage≥2 有 2 个 beat，最多 2 个事件（4 事件池够用）。

### 4.11 `baseWeather` / `weather` / `weatherT`

```js
this.baseWeather=r||i?'clear':F.pick(this.biome.weather);
let o=sb(this.player.ability);
o.weather&&(this.baseWeather=o.weather);
this.weather=this.baseWeather;
this.applyWeatherLook();

setBaseWeather(e){this.baseWeather=e,this.weatherT<=0&&(this.weather=e,this.applyWeatherLook())}

setWeather(e,t){this.weather=e,this.weatherT=t,this.applyWeatherLook(),this.ui.toast(c('¡El clima cambia: {weather}!'))}

// 每帧
this.weatherT>0&&(this.weatherT-=e,
  this.weatherT<=0&&(this.weather=this.baseWeather,this.applyWeatherLook()))
```

| 字段 | 语义 |
|---|---|
| `baseWeather` | 常驻天气；开局按 `r||i ? 'clear' : F.pick(biome.weather)`；ability 可覆盖 |
| `weather` | 当前显示/生效天气 |
| `weatherT` | 临时天气剩余时间；`<=0` 时 `weather` 跟随 `baseWeather` |

生物群系基础天气（news `weather` 字段）：

| biome | `weather` |
|---|---|
| `forest` | `['clear','clear','rain']` |
| `desert` | `['clear','sand','sun']` |
| `coast` | `['clear','rain','clear']` |
| `glacier` | `['clear','hail','clear']` |
| `graveyard` | `['fog','clear','rain']` |
| `volcano` | `['ash','sun','clear']` |

- 事件结束**不调用** `setBaseWeather`，所以 `baseWeather` 始终不变；`weather` 只会因为 `weatherT` 归零或 `setWeather` 而变。
- `blind = kind==='fog' && k>.5`（雾事件过半后启用「致盲」标记）。
- `eliteBonus = kind==='eclipse' ? .12 : 0`。

### 4.12 天气事件 i18n key

| key | 场景 |
|---|---|
| `¡{name}!` | 事件开始 banner（`name` 来自 `uS`） |
| `Niebla espectral` / `Una niebla helada...` | fog |
| `Tormenta eléctrica` / `Caen rayos: aléjate de las marcas amarillas` | storm |
| `Eclipse` / `La luz se apaga. Salen los Pokémon de la noche...` | eclipse |
| `Meowth dorado` / `Suelta monedas con cada golpe. ¡Atrápalo antes de que escape!` | meowth |
| `La niebla se disipa` | fog 结束 |
| `La tormenta se aleja` | storm 结束 |
| `La luz vuelve` | eclipse 结束 |
| `¡Día de Pago!` / `Meowth dorado suelta todas sus monedas` | 击杀 Meowth |
| `Meowth dorado se escapa con su botín` | 超时逃离 |
| `¡El clima cambia: {weather}!` | `setWeather` 提示 |

### 4.13 Godot 落点与差距

- 数据：`data/pb/weather.json` 与 `uS` **逐字段一致**（含 `look/pool/dur`）。
- `src/core/pb_weather.gd` 只做 `weather_damage` 倍率；**无**事件调度。
- **需新增**（建议 `src/core/pb_weather_events.gd`，纯 RefCounted）：
  - `start_random(state)`：照抄 §4.4 的前置条件 + `done` + 0.8 权重；
  - `start(state, kind)` / `end(state, silent)`：照抄 §4.5；
  - `update(state, dt)`：`left/k/spawnT/boltT`；
  - `update_spawns`、`storm_fx`、`bolt`、`eclipse_fx`、`spawn_meowth`、`update_meowth`、`on_hit`、`on_killed`。
- **接入点**：
  1. `src/core/pb_run.gd:197 _tick_director` 增加 `event` beat（普通 stage1 `range(170,300)`，stage≥2 两个，无尽 `next=range(170,230), every=[220,260]`）；
  2. `pb_run.gd:145` 的 `weatherT` 回落逻辑已存在，保持；事件只操作 `weather`/`weatherT`，不动 `baseWeather`；
  3. `data/pb/weather.json` 的 `name/sub/color` 可直接用；`look` 字段若要接入渲染，转成 Godot 环境参数。
- **注意**：Godot 当前没有 `done` 集合、`mapEvents.busy`、`mewtwo.active`、`stageCleared` 语义；需在 `state` 里补 `weatherDone` 与对应的 gate。

---

## 5. 危险地形

### 5.1 Web 出处

| 符号 | offset | 作用 |
|---|---|---|
| `_D` 定义表 | main @1392060 | mud/bramble/quicksand/fire |
| `vD` 生物群系映射 | main @1392796 | `byBiome` |
| `yD=.5`、`bD=1.5` | main @1392906 / @1392912 | tick 重置值 / 淡出时长 |
| `TD()` | main @1394171 | 惰性加载 `hazards.png` 图集，成功后 `wD=true` |
| `var ED=class` | main @1394477 | 危险地形控制器 |
| `schedule(e)` | main @1394605 | 定时生成 |
| `flatSpot(e)` | main @1394843 | 找平坦圆 |
| `spawn(e,t,n,r,i)` | main @1395258 | 生成网格与状态 |
| `update(e)` | main @1396003 | 生命周期与效果 |
| `ambient(e,t)` | main @1397226 | 环境粒子 |
| `drop(e)` | main @1398148 | 释放 |
| `clear()` | main @1398269 | 迁移/重置 |
| `onMigrate()` | main @1407307 | 迁移时清空 |

### 5.2 `_D` 与 `vD`（原样）

```js
_D={
  mud:{cell:0,name:()=>c('Charca de barro'),
       say:()=>c('¡Terreno hostil! Una charca de barro frena a todo el que la pisa'),
       color:9067050,slow:.55,pull:0,hurt:0,bite:0},
  bramble:{cell:1,name:()=>c('Zarzal venenoso'),
           say:()=>c('¡Terreno hostil! Un zarzal venenoso pincha a todo el que lo cruza'),
           color:11553496,slow:.8,pull:0,hurt:.025,bite:.05,type:'poison',status:'poison'},
  quicksand:{cell:2,name:()=>c('Arenas movedizas'),
             say:()=>c('¡Terreno hostil! Unas arenas movedizas tragan a todo lo que se acerca'),
             color:14200928,slow:.5,pull:2.4,hurt:0,bite:0},
  fire:{cell:3,name:()=>c('Suelo en llamas'),
        say:()=>c('¡Terreno hostil! El suelo arde: no te quedes encima'),
        color:16738842,slow:1,pull:0,hurt:.03,bite:.07,type:'fire',status:'burn'}
},
vD={forest:['mud','bramble'],desert:['quicksand','fire'],coast:['mud','quicksand'],glacier:['mud','bramble']},
yD=.5,bD=1.5
```

| 字段 | 语义 |
|---|---|
| `cell` | 图集格子索引；`uCell = (cell%2, 1-floor(cell/2))` |
| `name` | 显示名（i18n key） |
| `say` | 生成时 toast |
| `color` | 环/粒子颜色（十进制 RGB） |
| `slow` | 玩家移动速度乘数（`1` = 不减速；实际用 `min` 叠加，越小越慢） |
| `pull` | 每秒向中心拉拽的距离（`0` = 无） |
| `hurt` | 玩家每次 tick 的 `maxHp` 比例伤害（`0` = 无） |
| `bite` | 敌人每次 tick 的 `maxHp` 比例伤害（`0` = 无） |
| `type` | 伤害/状态属性；缺省 `normal` |
| `status` | 命中时附加的状态（`poison`/`burn`） |

`byBiome`：`forest → mud/bramble`、`desert → quicksand/fire`、`coast → mud/quicksand`、`glacier → mud/bramble`；未列出的 biome 回退 `Object.keys(_D)`（全部四种）。

### 5.3 调度（`schedule` / `flatSpot` / `spawn`）

```js
schedule(e){
  let t=this.run;
  if((this.nextT-=e)>0||!wD||(
    this.nextT=F.range(45,70),
    this.list.length>=(t.stage>=3?3:2)||t.mewtwo.active
  ))return;
  let n=this.flatSpot(F.range(6,9));
  n&&this.spawn(F.pick(this.kinds()),n.x,n.z,n.r,F.range(40,55))
}

kinds(){return vD[this.run.biome.id]??Object.keys(_D)}
```

| 项 | 值 |
|---|---|
| 初值 `nextT` | `180` s |
| 重置间隔 | `range(45,70)` s |
| 同时存在上限 | `stage>=3 ? 3 : 2` |
| 生成半径 | `flatSpot(range(6,9))`，即目标半径 6–9，最小 4.5，最大受 `randomPoint(8,28)` 限制 |
| 存活时长 `life` | `range(40,55)` s |
| `mewtwo.active` | 不生成 |
| `!wD` | 图集未加载，持续重试（`nextT` 已 <=0，不做重置） |

`flatSpot`：

```js
flatSpot(e){
  let t=this.run.terrain,n=this.run.player.pos,r=null;
  for(let i=0;i<24;i++){
    let i=t.randomPoint(F,n.x,n.z,8,28),a=t.height(i.x,i.z),o=e;
    for(;o>=4.5;){
      let e=t.inBounds(i.x,i.z,o+2);
      for(let n=0;e&&n<12;n++){
        let r=n/12*Math.PI*2;
        for(let n of[.5,1])
          Math.abs(t.height(i.x+Math.cos(r)*o*n,i.z+Math.sin(r)*o*n)-a)>1.2&&(e=!1)
      }
      if(e)break;
      --o
    }
    if(o>=4.5&&(!r||o>r.r)&&(r={x:i.x,z:i.z,r:o}),r&&r.r>=e)break
  }
  return r
}
```

- 24 次随机点（玩家周围 8–28）。
- 半径从目标 `e` 逐 1 递减到 **4.5**。
- 每个半径检查 **12 个角度 × 2 个比例（.5, 1）**，高度差 > **1.2** 即失败。
- `inBounds(..., r+2)`。
- 取「最大可行半径」；一旦达到目标 `e` 立即停止。
- 找不到返回 `null`（本次不生成）。

`spawn`（为便于阅读，把 bundle 里的 Three.js minified 构造名 `vi`/`hi`/`qr` 写成可读等价名；语义不变）：

```js
spawn(e,t,n,r,i){
  let a=this.run,o=_D[e],s=a.terrain,
      c=new PlaneGeometry(r*2,r*2,18,18).rotateX(-Math.PI/2),
      l=c.attributes.position;
  for(let e=0;e<l.count;e++)l.setY(e,s.height(t+l.getX(e),n+l.getZ(e))+.07);
  c.computeBoundingSphere();
  ...
  this.list.push({kind:e,x:t,z:n,r,age:0,life:i,tick:.2,mesh:f,mat:d});
  a.ui.toast(o.say(),null)
}
```

- 网格 `PlaneGeometry(r*2, r*2, 18, 18)`，旋转成水平，顶点 Y 贴合地形 `+0.07`。
- `uCell = (cell%2, 1-floor(cell/2))`；`uRot=range(0,2π)`。
- 初始 `tick=0.2`（不是 `yD`）。
- 生成即 toast `o.say()`。

### 5.4 生命周期与视觉（`update`）

```js
update(e){
  let t=this.run,n=t.player,r=t.enemies;
  n.hazardSlow=1;
  for(let i=this.list.length-1;i>=0;i--){
    let a=this.list[i],o=_D[a.kind];
    a.age+=e;
    let s=2+a.life;
    if(a.age>=s+1.5){this.drop(i);continue}
    let c=a.age>=2&&a.age<s;
    a.mat.uniforms.uAlpha.value=
      a.age<2? .35+.15*Math.sin(a.age*12)
        : a.age<s?1
          : 1-(a.age-s)/bD;
    let l=t.terrain.height(a.x,a.z);
    if(a.age<2){
      Math.random()<e*3&&t.vfx.ring(a.x,l,a.z,a.r,o.color,.6,.95);
      continue
    }
    if(this.ambient(a,e),!c)continue;
    ...
  }
}
```

| 阶段 | 时长 | alpha | 行为 |
|---|---|---|---|
| 进场 | `age < 2` | `.35 + .15*sin(age*12)` | 闪烁；随机 `ring`；不生效 |
| 生效 | `2 <= age < life+2` | `1` | 玩家/敌人效果 |
| 淡出 | `life+2 <= age < life+3.5` | `1-(age-s)/1.5` | 线性淡出；不生效 |
| 移除 | `age >= life+3.5` | — | `drop` |

- `s = 2 + life`。
- 生效窗口变量 `c = age>=2 && age<s`。
- 淡出时长 `bD=1.5`。

### 5.5 玩家效果 vs 敌人效果（原样）

```js
let u=a.x-n.pos.x,d=a.z-n.pos.z,f=Math.hypot(u,d),
    p=f<a.r&&n.grounded;
if(p&&(n.hazardSlow=Math.min(n.hazardSlow,o.slow),
        o.pull&&f>.5)){
  let t=o.pull*e*(1-f/a.r*.5);
  n.pos.x+=u/f*t,n.pos.z+=d/f*t
}
a.tick-=e;
let m=a.tick<=0;
m&&(a.tick=yD);
m&&p&&o.hurt&&n.hurt(n.maxHp*o.hurt,o.type,-1,NaN,NaN,!0,0,{kind:'hazard',species:0});

for(let n of r.within(a.x,a.z,a.r,this.near))
  if(!(r.flags[n]&R.Flying)){
    r.hazSlow[n]=Math.min(r.hazSlow[n],o.slow*.9);
    if(o.pull){
      let t=a.x-r.x[n],i=a.z-r.z[n],s=Math.hypot(t,i);
      s>.5&&(r.x[n]+=t/s*o.pull*1.3*e,r.z[n]+=i/s*o.pull*1.3*e)
    }
    if(m&&o.bite){
      let e=r.flags[n]&(R.Boss|R.Alpha|R.Totem|R.Summoner);
      t.combat.hit(n,r.maxHp[n]*o.bite*(e?.1:1),
        {type:o.type??'normal',cls:'special',fixed:!0,noReact:!0,
         status:o.status,statusChance:.5,silent:!0})
    }
  }
```

| 项 | 玩家 | 敌人 |
|---|---|---|
| 命中半径 | `f < a.r`（精确圆内）且 `grounded` | `within(a.x,a.z,a.r)`（精确圆内） |
| 飞行免疫 | 玩家无 | `flags & R.Flying` 跳过 |
| 减速 | `hazardSlow = min(hazardSlow, slow)`，乘到移动速度 | `hazSlow = min(hazSlow, slow*.9)` |
| 拉拽 | `pull*dt*(1-f/r*.5)`，仅 `f>.5` | `pull*1.3*dt`，仅 `s>.5` |
| 伤害节奏 | `tick` 初始 `.2`，归零后重置为 `yD=.5` | 同一个 `m` 判定（与玩家共用 tick） |
| 伤害 | `maxHp*hurt`，`fixed:!0`，`kind:'hazard'` | `maxHp*bite*(Boss|Alpha|Totem|Summoner ? .1 : 1)`，`fixed:!0`，`noReact:!0, silent:!0` |
| 状态 | 无（`type` 只作伤害属性） | `statusChance:.5` 附加 `status` |
| 生效窗口 | `age>=2 && age<s`（`p` 判定外还有 `continue`） | 同左 |

- 玩家 `hurt` 第 6 参数 `!0` 即 `fixed=true`（固定伤害，不吃护甲/闪避）。
- 敌人伤害对 Boss/Alpha/Totem/Summoner 乘 **.1**（不是 .1 倍上限，是伤害系数）。
- `this.near` 只是 `within` 的输出缓存数组，**不是半径**；半径就是 `a.r`。
- `hazardSlow` 每帧先重置为 `1`，再由所有命中的 hazard 取 `min`；未命中则为 1。敌人的 `hazSlow` 是每敌槽位数组，在敌人移动结算时乘一次并重置（web 在 `354930` 处 `S*=hazSlow[h]; hazSlow[h]=1`）。

### 5.6 环境粒子（`ambient`）

```js
ambient(e,t){
  let n=this.run;
  if(Math.random()>t*(4+e.r))return;
  let r=F.range(0,Math.PI*2),i=Math.sqrt(Math.random())*e.r*.9,
      a=e.x+Math.cos(r)*i,o=e.z+Math.sin(r)*i,
      s=n.terrain.height(a,o);
  switch(e.kind){
    case`mud`:n.vfx.norm.spawn({x:a,y:s+.15,z:o,vy:.4,life:.7,size:.35,endSize:.6,color:6964516,shape:Bubble});break;
    case`bramble`:n.vfx.add.spawn({x:a,y:s+.4,z:o,vy:.5,life:1.6,size:.7,endSize:1.3,color:10107608,shape:Wisp,glow:.3});break;
    case`quicksand`:n.vfx.norm.spawn({x:a,y:s+.2,z:o,vx:(e.x-a)*.5-Math.sin(r)*2,vz:(e.z-o)*.5+Math.cos(r)*2,vy:.2,life:.9,size:.5,endSize:.1,color:14203e3,shape:Soft,drag:1});break;
    case`fire`:n.vfx.add.spawn({x:a,y:s+.3,z:o,vy:F.range(1.5,3),life:.7,size:.7,endSize:0,color:16777215,shape:PixFlame,glow:.4}),Math.random()<.4&&n.vfx.add.spawn({x:a,y:s+.5,z:o,vx:F.range(-.5,.5),vy:F.range(2,4),vz:F.range(-.5,.5),life:1.1,size:.2,endSize:0,color:16752704,shape:Spark,glow:.8})
  }
}
```

- 触发概率：`random() <= dt*(4+r)`，即约 `4+r` 个/秒。
- 位置：半径 `sqrt(random())*r*.9`，高度贴地。

### 5.7 迁移/清空

```js
drop(e){let t=this.list[e];t.mesh.parent?.remove(t.mesh),t.mesh.geometry.dispose(),t.mat.dispose(),this.list.splice(e,1)}

clear(){for(let e=this.list.length-1;e>=0;e--)this.drop(e);this.run.player.hazardSlow=1}
```

- 迁移到新地图时 `clear()` 全清，并把 `player.hazardSlow=1`。
- 迁移同样清空商人 Meowth 与传送门/彗星（`onMigrate()` @1407307）。

### 5.8 危险地形 i18n key

| key | 场景 |
|---|---|
| `Charca de barro` | mud 名 |
| `¡Terreno hostil! Una charca de barro frena a todo el que la pisa` | mud 生成 toast |
| `Zarzal venenoso` | bramble 名 |
| `¡Terreno hostil! Un zarzal venenoso pincha a todo el que lo cruza` | bramble 生成 toast |
| `Arenas movedizas` | quicksand 名 |
| `¡Terreno hostil! Unas arenas movedizas tragan a todo lo que se acerca` | quicksand 生成 toast |
| `Suelo en llamas` | fire 名 |
| `¡Terreno hostil! El suelo arde: no te quedes encima` | fire 生成 toast |

### 5.9 Godot 落点与差距

- 数据：`data/pb/hazards.json` 与 `_D`/`vD` **逐字段一致**，无需重建。
- **需新增运行层**（建议 `src/core/pb_hazards.gd`）：
  - `schedule(state, dt)`：`nextT=180`、`range(45,70)`、上限 `stage>=3?3:2`、`mewtwo.active` gate；
  - `flat_spot`：24 次 / 半径 4.5 / 12 角度 × .5,1 / 高度差 1.2；
  - `spawn`：圆盘网格 + 18×18 顶点贴地 `+0.07`；
  - `update`：`age` 阶段、`hazardSlow`/`hazSlow`、`hurt`/`bite`、`tick=.2 → .5`。
- **接入点**：
  - `src/core/pb_run.gd:197 _tick_director` 末尾调用 `PbHazards.schedule/update`（与 Web 一致：无 `state==='play'` gate）；
  - 玩家速度：`src/core/pb_run.gd:808` 的 `speed` 乘 `hazardSlow`；
  - 敌人速度：`PbEnemies` 移动结算处乘 `hazSlow` 并重置（需先加每槽位字段）；
  - 迁移：`PbRun` 的迁图流程里调用 `clear()`。
- `data/pb/hazards.json` 已可直接读取；`name`/`say` 为西语 i18n key。

---

## 6. 建议实现优先级

| 优先级 | 系统 | 理由 |
|---|---|---|
| P0 | 维生素出卡权重、`loaded-dice` | 直接影响每局构筑与数值；现有 `roll_vitamin` 分布偏差明显 |
| P0 | 进化运行层 | 当前完全缺失；影响图鉴/难度曲线/演出 |
| P1 | 商店无尽/塔分支 + 出售价 | 现有非无尽分支已可用；无尽是主要长线模式 |
| P1 | 天气事件调度 + meowth | 影响节奏与金币；依赖 director timeline |
| P2 | 危险地形运行层 | 数据已就位，缺运行时；影响移动手感与地形互动 |
| P2 | 商店 NPC 计时/UI | 纯表现层，可后补 |

---

## 7. 未定位 / 推断清单

| 项 | 状态 | 依据 |
|---|---|---|
| `dD/fD/pD` 与商店刷新有关 | **已否定** | 三常量只出现在交互提示系统；商店用 `meowthT/meowthLeft` |
| `meowth` 事件的 `this.marker` 定义 | **推断** | `updateMeowth` 用 `this.marker` 判活，另有 `meowthGen` 字段；未逐字 dump |
| `roster.branch / evoLevel / evoLevels` | **部分未定位** | 属于 roster/league 模式；普通模式不触发。`planEvolution` 已给全码 |
| `eliteBonus` 的使用方 | **未定位** | 只确认 getter `kind==='eclipse'?.12:0`；未找到消费点 |
| `JS(e,t)` / `Ey(t,Ot[n])` 等出卡应用函数 | **未展开** | 本文只到「卡片生成/展示」层；具体数值落地在 `doLevelUp` 的 `JS` 分支 |
| `F` RNG 的具体实现 | **已知语义** | `F.range(a,b)`、`F.pick`、`F.weighted`、`F.chance`、`F.shuffle` 均在 bundle 内；未逐字抄实现 |
| `Yt(n)`（director 阶段） | **未展开** | 与商店/维生素无关；影响 `enterPhase` |
| `dS=52` 的物种名 | **已确认语义** | `sT.meowth:52`；`dS` 即 Meowth 物种 id |
