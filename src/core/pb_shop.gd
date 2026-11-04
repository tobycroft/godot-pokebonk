class_name PbShop
extends RefCounted
## The run's Meowth shop, ported from the main Web bundle
## (assets/main-C5MieX6g-mvpjh5lt.js):
##   nC()      @1103831  stock: 4 distinct items, at most 16 draws
##   aC()      @1104019  price = round(rC[rarity] * rT(stage) * shopHeat * oC)
##   XS()      @1101219  rarity band + weighted item pick
##   GS()      @1096826  rarity roll used by XS
##   openShop / rerollShop / buyShopItem @1547939..1548502
##
## Prices are the web's constants: rC=[80,130,220,400,750], rT=2.2^(stage-1)
## (stage clamped to 1..4), shopHeat multiplies iC=[1.15,1.25,1.4,1.6,2] for
## every purchase past the first two, and gold-teeth discounts 8 % up to 24 %.

## Every number below lives in data/pb/shop.json (exported from the bundle
## offsets listed in its `source` block). The helpers fall back to the same
## values so a missing table cannot change the port's behaviour.
static var _config: Dictionary = {}


static func config() -> Dictionary:
	if _config.is_empty():
		_config = PbJson.as_dict(PbData.pb_table("shop"))
	return _config


static func _table(name: String, fallback: Array) -> Array:
	return PbJson.as_array(config().get(name, fallback))


static func _num(name: String, fallback: float) -> float:
	return PbJson.as_float(config().get(name, fallback), fallback)


static func stock_size() -> int:
	return int(_num("stock_size", 4.0))


static func stock_tries() -> int:
	return int(_num("stock_tries", 16.0))


static func price_by_rarity() -> Array:
	return _table("price_by_rarity", [80, 130, 220, 400, 750])


static func heat_by_rarity() -> Array:
	return _table("heat_by_rarity", [1.15, 1.25, 1.4, 1.6, 2.0])


## NPC timings live under `npc` in data/pb/shop.json.
static func npc_num(name: String, fallback: float) -> float:
	return PbJson.as_float(PbJson.as_dict(config().get("npc", {})).get(name, fallback), fallback)


static func data_of(state: Dictionary) -> Dictionary:
	return PbJson.as_dict(state.get("shop", {}))


static func item_def(key: String) -> Dictionary:
	return PbData.item_game(key)


static func stock(state: Dictionary) -> Array:
	return PbJson.as_array(data_of(state).get("stock", []))


## openShop(): the stock key is the stage in regular runs, 100+shopVisit in
## endless and 200+floor in the tower. Leaving and returning with the same key
## keeps the stock (and its sold flags).
static func open(state: Dictionary) -> void:
	var stage_key := shop_key(state)
	var shop := data_of(state)
	if shop.is_empty() or int(shop.get("stage", -1)) != stage_key:
		state["shop"] = {
			"stage": stage_key,
			"stock": _roll_stock(state),
			"rerolls": 0,
		}


static func is_endless(state: Dictionary) -> bool:
	return str(state.get("mode", "")) == "endless" or state.get("endless", null) != null


static func is_tower(state: Dictionary) -> bool:
	return state.get("tower", null) != null


## openShop() -> `endless ? 100+shopVisit : tower ? 200+floor : stage`.
static func shop_key(state: Dictionary) -> int:
	if is_endless(state):
		return 100 + int(PbJson.as_dict(state.get("endless", {})).get("shopVisit",
			state.get("shopVisit", 0)))
	if is_tower(state):
		return 200 + int(PbJson.as_dict(state.get("tower", {})).get("floor", 0))
	return int(state.get("stage", 1))


## aC(): the current price of `key`. The stock keeps the price it was rolled at;
## this helper is also what the smoke test compares against the web formula.
static func price_for(state: Dictionary, key: String) -> int:
	var def := item_def(key)
	var prices := price_by_rarity()
	var rarity := clampi(int(def.get("rarity", 0)), 0, prices.size() - 1)
	var value := float(prices[rarity]) * _stage_scale(state) \
		* shop_heat(state) * discount(state)
	return int(roundf(value))


## rerollCost(): .5 * rC[0] * rT * growth^rerolls * oC. The cost never includes
## shopHeat; endless grows at 1.6^shop.rerolls, regular at 1.5^shopRerolls.
static func reroll_cost(state: Dictionary) -> int:
	var prices := price_by_rarity()
	var growth := _num("endless_reroll_growth", 1.6) if is_endless(state) \
		else _num("reroll_growth", 1.5)
	var count := int(data_of(state).get("rerolls", 0)) if is_endless(state) \
		else int(state.get("shopRerolls", 0))
	var value := _num("reroll_share", 0.5) * float(prices[0]) * _stage_scale(state) \
		* pow(growth, float(count)) * discount(state)
	return int(roundf(value))


## rerollShop(): validates the cost, charges it through econ.shop, and rolls a
## brand-new stock.
static func reroll(state: Dictionary) -> bool:
	var shop := data_of(state)
	if shop.is_empty():
		return false
	var cost := reroll_cost(state)
	if int(state.get("gold", 0)) < cost:
		return false
	state["gold"] = float(int(state.get("gold", 0)) - cost)
	_charge(state, cost)
	shop["stock"] = _roll_stock(state)
	shop["rerolls"] = int(shop.get("rerolls", 0)) + 1
	state["shopRerolls"] = int(state.get("shopRerolls", 0)) + 1
	return true


## buyShopItem(): fails on sold items, short gold or a full stack; otherwise it
## charges the price, marks the row sold, grants the item and remembers its
## rarity for the heat multiplier.
static func buy(state: Dictionary, index: int) -> bool:
	var shop := data_of(state)
	var rows := PbJson.as_array(shop.get("stock", []))
	if index < 0 or index >= rows.size():
		return false
	var entry := PbJson.as_dict(rows[index])
	if bool(entry.get("sold", false)):
		return false
	var key := str(entry.get("key", ""))
	var price := int(entry.get("price", 0))
	if int(state.get("gold", 0)) < price or not can_hold(state, key):
		return false
	state["gold"] = float(int(state.get("gold", 0)) - price)
	_charge(state, price)
	entry["sold"] = true
	_grant(state, key)
	PbJson.as_array(state["shopBuys"]).append(int(item_def(key).get("rarity", 0)))
	return true


## oT(): `round(max(lower[rarity]*stage, min(.5*rC*rarity*rT, cap[rarity]*eT)))`.
## `eT` = 18 * chest growth * endless chest curse.
static func sell_price(state: Dictionary, rarity: int) -> int:
	var prices := price_by_rarity()
	var r := clampi(rarity, 0, prices.size() - 1)
	var lower := _table("sell_lower_by_rarity", [10, 18, 30, 50, 90])
	var cap := _table("sell_cap_by_rarity", [0.3, 0.45, 0.65, 1, 1.5])
	var stage := float(int(state.get("stage", 1)))
	var base := _num("sell_share", 0.5) * float(prices[r]) * _stage_scale(state)
	var biggest := maxf(float(lower[r]) * stage, minf(base, float(cap[r]) * chest_price(state)))
	return int(roundf(biggest))


## eT(e) = 18 * $w(chestsBought) * (endless.curse.chest ?? 1).
static func chest_price(state: Dictionary) -> float:
	var chests := int(state.get("chestsBought", 0))
	var curse := PbJson.as_dict(PbJson.as_dict(state.get("endless", {})).get("curse", {}))
	return _num("chest_base", 18.0) * _chest_growth(chests) \
		* PbJson.as_float(curse.get("chest", 1.0), 1.0)


## $w(): the chest price curve; the 30/40/50 bands all key off `e-30`.
static func _chest_growth(chests: int) -> float:
	var t := 35.0 * float(chests)
	if chests > 10:
		t += 300.0 * float(chests - 10)
	if chests > 20:
		t += 550.0 * float(chests - 20)
	if chests > 30:
		t += 1200.0 * float(chests - 30)
	if chests > 40:
		t += 2400.0 * float(chests - 30)
	if chests > 50:
		t += 4500.0 * float(chests - 30)
	return (pow(1.22, float(chests)) + t / 30.0) \
		* pow(1.12, maxf(0.0, float(chests - 12)))


## Selling (the panel's right column): remove one copy, add the oT price and
## bump econ.sold. The 3 s armed confirmation lives in the UI.
static func sell(state: Dictionary, key: String) -> int:
	var player := PbJson.as_dict(state["player"])
	if int(PbActor.item_power(player, key)) <= 0:
		return 0
	var price := sell_price(state, int(item_def(key).get("rarity", 0)))
	state["gold"] = float(state.get("gold", 0.0)) + float(price)
	var econ := PbJson.as_dict(state.get("econ", {}))
	econ["sold"] = int(econ.get("sold", 0)) + 1
	state["econ"] = econ
	PbActor.give_item(player, key, float(maxi(0, int(PbActor.item_power(player, key)) - 1)))
	PbActor.recompute(player)
	return price


## Every owned item with a run definition, for the panel's sell column.
static func sellable(state: Dictionary) -> Array:
	var player := PbJson.as_dict(state["player"])
	var out := []
	for key in PbJson.as_dict(player.get("items", {})).keys():
		var count := int(PbActor.item_power(player, str(key)))
		if count <= 0:
			continue
		var def := item_def(str(key))
		if def.is_empty():
			continue
		var rarity := int(def.get("rarity", 0))
		out.append({"key": str(key), "count": count, "rarity": rarity,
			"price": sell_price(state, rarity)})
	return out


## canHold(): count < item.max (10 when the table omits it).
static func can_hold(state: Dictionary, key: String) -> bool:
	var def := item_def(key)
	return int(PbActor.item_power(PbJson.as_dict(state["player"]), key)) \
		< int(def.get("max", _num("default_max", 10.0)))


## shopHeat getter: 1 for the first two purchases, then the product of the
## bought rarities' multipliers (chestsBought trims that window too). Endless
## keeps heat at 1.
static func shop_heat(state: Dictionary) -> float:
	if is_endless(state):
		return 1.0
	var bought := PbJson.as_array(state.get("shopBuys", []))
	var skip := 2 + int(floor(float(state.get("chestsBought", 0)) / 3.0))
	var heat := 1.0
	var mults := heat_by_rarity()
	for i in range(skip, bought.size()):
		var rarity := clampi(int(bought[i]), 0, mults.size() - 1)
		heat *= float(mults[rarity])
	return heat


## oC(): 1 - .08 * min(3, gold-teeth copies in the player's bag).
static func discount(state: Dictionary) -> float:
	var teeth := int(PbActor.item_power(PbJson.as_dict(state["player"]), "gold-teeth"))
	return 1.0 - _num("teeth_discount", 0.08) * float(mini(int(_num("teeth_max", 3.0)), teeth))


## rT(): regular runs scale by 2.2^(clamp(stage,1,4)-1); endless scales every
## 300 s starting at 210 s and multiplies the active chest curse.
static func _stage_scale(state: Dictionary) -> float:
	if is_endless(state):
		var time := float(state.get("time", 0.0))
		var epoch := _num("endless_epoch", 210.0)
		var period := _num("endless_period", 300.0)
		var step := maxf(0.0, floor((time - epoch) / period))
		var curse := PbJson.as_dict(PbJson.as_dict(state.get("endless", {})).get("curse", {}))
		return pow(_num("endless_scale", 1.7), step) \
			* PbJson.as_float(curse.get("chest", 1.0), 1.0)
	var clamp_range := _table("stage_scale_clamp", [1, 4])
	var stage := clampi(int(state.get("stage", 1)),
		int(clamp_range[0]), int(clamp_range[1]))
	return pow(_num("stage_scale", 2.2), float(stage - 1))


static func _charge(state: Dictionary, amount: int) -> void:
	var econ := PbJson.as_dict(state.get("econ", {}))
	econ["shop"] = int(econ.get("shop", 0)) + amount
	state["econ"] = econ
	state["goldSpent"] = float(state.get("goldSpent", 0.0)) + float(amount)


## nC(): 16 draws at most, 4 distinct keys.
static func _roll_stock(state: Dictionary) -> Array:
	var rows := []
	for n in stock_tries():
		if rows.size() >= stock_size():
			break
		var key := _pick(state)
		if key.is_empty():
			continue
		var duplicate := false
		for row in rows:
			if str(PbJson.as_dict(row).get("key", "")) == key:
				duplicate = true
				break
		if duplicate:
			continue
		rows.append({"key": key, "price": price_for(state, key), "sold": false})
	return rows


## XS(): pick an item respecting the rarity bands and the player's type tags.
static func _pick(state: Dictionary, min_rarity: int = 0) -> String:
	var pool := _available(state)
	var flags := []
	for r in price_by_rarity().size():
		flags.append(_has_rarity(pool, r))
	if min_rarity >= 3:
		var any := false
		for r in range(min_rarity, flags.size()):
			any = any or bool(flags[r])
		if not any:
			return ""
	var chosen := maxi(min_rarity, _rarity_roll(state, min_rarity,
		_num("pick_luck_bonus", 10.0), flags))
	var candidates := _rarity_items(pool, chosen)
	var r := chosen - 1
	while candidates.is_empty() and r >= 0:
		candidates = _rarity_items(pool, r)
		r -= 1
	if candidates.is_empty():
		candidates = pool
	if candidates.is_empty():
		return ""
	var entries := []
	var types := PbJson.as_array(PbJson.as_dict(state["player"]).get("types", []))
	for def in candidates:
		var weight := 1.0
		var tags := PbJson.as_array(def.get("tags", []))
		if not tags.is_empty():
			weight = 0.35
			for tag in tags:
				if types.has(str(tag).substr(5)):
					weight = 4.0
					break
		entries.append([weight, str(def.get("key", ""))])
	return str(PbRng.weighted(entries))


## GS(): rarity weights with the level/stage ramp and the availability mask.
static func _rarity_roll(state: Dictionary, min_rarity: int, luck_bonus: float,
		available: Array) -> int:
	var player := PbJson.as_dict(state["player"])
	var stats := PbJson.as_dict(player.get("stats", {}))
	var luck := maxf(0.0, float(stats.get("luck", 0.0)) + luck_bonus)
	var a := luck / 100.0
	var offset := float(player.get("level", 1)) + luck / 8.0 \
		+ float(int(state.get("stage", 1)) - 1) * 12.0
	var ramp := func(from: float, to: float) -> float:
		return maxf(0.0, minf(1.0, (offset - from) / (to - from)))
	var weights := [
		70.0 / (1.0 + a),
		24.0 * (1.0 + 0.5 * a),
		5.0 * pow(1.0 + a, 2.0) * ramp.call(3.0, 10.0),
		0.9 * pow(1.0 + a, 3.0) * ramp.call(8.0, 18.0),
		0.12 * pow(1.0 + a, 4.0) * ramp.call(14.0, 26.0),
	]
	for n in weights.size():
		if n < min_rarity:
			weights[n] = float(weights[n]) * 1.0e-4
		if n < available.size() and not bool(available[n]):
			weights[n] = 0.0
	var total := 0.0
	for w in weights:
		total += float(w)
	if total <= 1.0e-6:
		return min_rarity
	var roll := PbRng.randf() * total
	for n in weights.size():
		roll -= float(weights[n])
		if roll <= 0.0:
			return n
	return 0


## Item pool (XS's `r`): premium items require ownership; itemsOff excludes;
## full stacks are out.
static func _available(state: Dictionary) -> Array:
	var owned := PbJson.as_array(Save.store.get("itemsOwned", []))
	var off := PbJson.as_array(Save.store.get("itemsOff", []))
	var player := PbJson.as_dict(state["player"])
	var out := []
	for raw in PbJson.as_array(PbData.pb_table("items_game")):
		var def := PbJson.as_dict(raw)
		var key := str(def.get("key", ""))
		if key.is_empty():
			continue
		if bool(def.get("premium", false)) and not owned.has(key):
			continue
		if off.has(key):
			continue
		if int(PbActor.item_power(player, key)) >= int(def.get("max", _num("default_max", 10.0))):
			continue
		out.append(def)
	return out


static func _has_rarity(pool: Array, rarity: int) -> bool:
	for def in pool:
		if int(PbJson.as_dict(def).get("rarity", 0)) == rarity:
			return true
	return false


static func _rarity_items(pool: Array, rarity: int) -> Array:
	var out := []
	for def in pool:
		if int(PbJson.as_dict(def).get("rarity", 0)) == rarity:
			out.append(def)
	return out


## addItem(): one more copy, recompute, plus the max-revive charge. rare-candy
## needs gainLevel() (not ported yet) -- 待确认.
static func _grant(state: Dictionary, key: String) -> void:
	var player := PbJson.as_dict(state["player"])
	var count := int(PbActor.item_power(player, key)) + 1
	PbActor.give_item(player, key, float(count))
	if key == "max-revive":
		player["revives"] = int(player.get("revives", 0)) + 1
	PbActor.recompute(player)
