class_name PbShop
extends RefCounted
## The run's Meowth shop, ported from the bundle helpers:
##   nC()      @1104993  stock: 4 distinct items, at most 16 draws
##   aC()      @1105132  price = round(rC[rarity] * rT(stage) * shopHeat * oC)
##   XS()      @1102366  rarity band + weighted item pick
##   GS()      @1097955  rarity roll used by XS
##   openShop / rerollShop / buyShopItem @1549750..1550350
##
## Prices are the web's constants: rC=[80,130,220,400,750], rT=2.2^(stage-1)
## (stage clamped to 1..4), shopHeat multiplies iC=[1.15,1.25,1.4,1.6,2] for
## every purchase past the first two, and gold-teeth discounts 8 % up to 24 %.

const STOCK_SIZE := 4
const STOCK_TRIES := 16
const PRICE_BY_RARITY := [80, 130, 220, 400, 750]
const HEAT_BY_RARITY := [1.15, 1.25, 1.4, 1.6, 2.0]
const STAGE_SCALE := 2.2
const REROLL_SHARE := 0.5
const REROLL_GROWTH := 1.5
const TEETH_DISCOUNT := 0.08
const TEETH_MAX := 3
const DEFAULT_MAX := 10
## XS(e, 10) -- the shop asks the rarity roll for a +10 luck bonus.
const PICK_LUCK_BONUS := 10.0


static func data_of(state: Dictionary) -> Dictionary:
	return PbJson.as_dict(state.get("shop", {}))


static func item_def(key: String) -> Dictionary:
	return PbData.item_game(key)


static func stock(state: Dictionary) -> Array:
	return PbJson.as_array(data_of(state).get("stock", []))


## openShop(): the stock is per stage and survives leaving/returning until the
## stage changes, exactly like `this.shop.stage !== e` in the bundle.
static func open(state: Dictionary) -> void:
	var stage_key := int(state.get("stage", 1))
	var shop := data_of(state)
	if shop.is_empty() or int(shop.get("stage", -1)) != stage_key:
		state["shop"] = {
			"stage": stage_key,
			"stock": _roll_stock(state),
			"rerolls": 0,
		}


## aC(): the current price of `key`. The stock keeps the price it was rolled at;
## this helper is also what the smoke test compares against the web formula.
static func price_for(state: Dictionary, key: String) -> int:
	var def := item_def(key)
	var rarity := clampi(int(def.get("rarity", 0)), 0, PRICE_BY_RARITY.size() - 1)
	var value := float(PRICE_BY_RARITY[rarity]) * _stage_scale(state) \
		* shop_heat(state) * discount(state)
	return int(roundf(value))


## rerollCost(): .5 * rC[0] * rT * 1.5^shopRerolls * oC (non-endless branch).
static func reroll_cost(state: Dictionary) -> int:
	var value := REROLL_SHARE * float(PRICE_BY_RARITY[0]) * _stage_scale(state) \
		* pow(REROLL_GROWTH, float(state.get("shopRerolls", 0))) * discount(state)
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


## canHold(): count < item.max (10 when the table omits it).
static func can_hold(state: Dictionary, key: String) -> bool:
	var def := item_def(key)
	return int(PbActor.item_power(PbJson.as_dict(state["player"]), key)) \
		< int(def.get("max", DEFAULT_MAX))


## shopHeat getter: 1 for the first two purchases, then the product of the
## bought rarities' multipliers (chestsBought trims that window too).
static func shop_heat(state: Dictionary) -> float:
	var bought := PbJson.as_array(state.get("shopBuys", []))
	var skip := 2 + int(floor(float(state.get("chestsBought", 0)) / 3.0))
	var heat := 1.0
	for i in range(skip, bought.size()):
		var rarity := clampi(int(bought[i]), 0, HEAT_BY_RARITY.size() - 1)
		heat *= float(HEAT_BY_RARITY[rarity])
	return heat


## oC(): 1 - .08 * min(3, gold-teeth copies in the player's bag).
static func discount(state: Dictionary) -> float:
	var teeth := int(PbActor.item_power(PbJson.as_dict(state["player"]), "gold-teeth"))
	return 1.0 - TEETH_DISCOUNT * float(mini(TEETH_MAX, teeth))


static func _stage_scale(state: Dictionary) -> float:
	var stage := clampi(int(state.get("stage", 1)), 1, 4)
	return pow(STAGE_SCALE, float(stage - 1))


static func _charge(state: Dictionary, amount: int) -> void:
	var econ := PbJson.as_dict(state.get("econ", {}))
	econ["shop"] = int(econ.get("shop", 0)) + amount
	state["econ"] = econ
	state["goldSpent"] = float(state.get("goldSpent", 0.0)) + float(amount)


## nC(): 16 draws at most, 4 distinct keys.
static func _roll_stock(state: Dictionary) -> Array:
	var rows := []
	for n in STOCK_TRIES:
		if rows.size() >= STOCK_SIZE:
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
	for r in PRICE_BY_RARITY.size():
		flags.append(_has_rarity(pool, r))
	if min_rarity >= 3:
		var any := false
		for r in range(min_rarity, flags.size()):
			any = any or bool(flags[r])
		if not any:
			return ""
	var chosen := maxi(min_rarity, _rarity_roll(state, min_rarity, PICK_LUCK_BONUS, flags))
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
		if int(PbActor.item_power(player, key)) >= int(def.get("max", DEFAULT_MAX)):
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
