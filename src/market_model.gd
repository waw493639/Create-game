class_name MarketModel
extends RefCounted

const Types = preload("res://src/market_types.gd")
const Hex = preload("res://src/hex_grid.gd")
const Content = preload("res://src/content.gd")

const BOARD_RADIUS := 3
const MAX_DAYS := 7
const DAILY_TIME := 6
const STARTING_COINS := 12

var seed_value: int
var rng := RandomNumberGenerator.new()
var phase: int = Types.Phase.SETUP
var day := 1
var coins := STARTING_COINS
var time_left := DAILY_TIME
var reputation := 0
var total_income := 0
var completed_groups := 0
var failed_groups := 0
var total_waits := 0

var stalls: Array = []
var offers: Array = []
var scheduled_customers: Array[Dictionary] = []
var last_day_stats: Dictionary = {}
var next_instance_id := 1

var _stall_catalog: Array = []
var _customer_catalog: Array = []

func _init(run_seed: int = 260902) -> void:
	begin_new_run(run_seed)

func begin_new_run(run_seed: int) -> void:
	seed_value = run_seed
	rng.seed = seed_value
	phase = Types.Phase.SETUP
	day = 1
	coins = STARTING_COINS
	time_left = DAILY_TIME
	reputation = 0
	total_income = 0
	completed_groups = 0
	failed_groups = 0
	total_waits = 0
	stalls.clear()
	offers.clear()
	scheduled_customers.clear()
	last_day_stats.clear()
	next_instance_id = 1
	_stall_catalog = Content.stalls()
	_customer_catalog = Content.customers()

func place_starter(cell: Vector2i, rotation: int = 0) -> Dictionary:
	if phase != Types.Phase.SETUP:
		return _error("起始摊位已经放置。")
	var placement := placement_result(cell)
	if not placement.ok:
		return placement
	stalls.append(Types.StallInstance.new(next_instance_id, Content.starter_stall(), cell, rotation))
	next_instance_id += 1
	phase = Types.Phase.PLANNING
	_fill_initial_offers()
	_prepare_base_customers()
	return _ok()

func placement_result(cell: Vector2i, ignored_stall_id: int = -1) -> Dictionary:
	if not Hex.is_inside(cell, BOARD_RADIUS):
		return _error("摊位必须放在市场范围内。")
	if Hex.is_gate(cell, BOARD_RADIUS):
		return _error("六个入口必须保持畅通。")
	for stall in stalls:
		if stall.instance_id != ignored_stall_id and stall.cell == cell:
			return _error("这里已经有摊位。")
	return _ok()

func purchase_offer(offer_index: int, cell: Vector2i, rotation: int = 0) -> Dictionary:
	if phase != Types.Phase.PLANNING:
		return _error("只能在筹备阶段招租。")
	if offer_index < 0 or offer_index >= offers.size() or offers[offer_index] == null:
		return _error("这个招租位暂时为空。")
	var offer = offers[offer_index]
	if offer.taken:
		return _error("这个招租项已经选过。")
	var cost: int = offer.current_cost()
	if coins < cost:
		return _error("金币不足。")
	if time_left < offer.stall_definition.time_cost:
		return _error("今日筹备时间不足。")
	var placement := placement_result(cell)
	if not placement.ok:
		return placement
	coins -= cost
	time_left -= offer.stall_definition.time_cost
	stalls.append(Types.StallInstance.new(
		next_instance_id,
		offer.stall_definition,
		cell,
		rotation
	))
	next_instance_id += 1
	offer.taken = true
	scheduled_customers.append({
		"definition": offer.customer_definition,
		"gate": offer.gate_index,
		"source": "招租",
	})
	return _ok()

func reposition_stall(stall_id: int, cell: Vector2i, rotation: int) -> Dictionary:
	if phase != Types.Phase.PLANNING:
		return _error("开市后不能调整摊位。")
	var stall = stall_by_id(stall_id)
	if stall == null:
		return _error("没有找到这个摊位。")
	var placement := placement_result(cell, stall_id)
	if not placement.ok:
		return placement
	stall.cell = cell
	stall.rotation = posmod(rotation, 6)
	return _ok()

func rotate_stall(stall_id: int, amount: int = 1) -> Dictionary:
	var stall = stall_by_id(stall_id)
	if stall == null:
		return _error("没有找到这个摊位。")
	return reposition_stall(stall_id, stall.cell, stall.rotation + amount)

func stall_by_id(stall_id: int):
	for stall in stalls:
		if stall.instance_id == stall_id:
			return stall
	return null

func stall_at(cell: Vector2i):
	for stall in stalls:
		if stall.cell == cell:
			return stall
	return null

func blocked_cells(ignored_stall_id: int = -1) -> Dictionary:
	var result := {}
	for stall in stalls:
		if stall.instance_id != ignored_stall_id:
			result[stall.cell] = true
	return result

func service_cells(stall) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var blocked := blocked_cells()
	for local_edge in stall.definition.frontage_edges:
		var world_edge: int = posmod(int(local_edge) + stall.rotation, 6)
		var cell := Hex.neighbor(stall.cell, world_edge)
		if Hex.is_inside(cell, BOARD_RADIUS) and not blocked.has(cell):
			result.append({"cell": cell, "edge": world_edge})
	return result

func start_open() -> Dictionary:
	if phase != Types.Phase.PLANNING:
		return _error("当前不能开市。")
	phase = Types.Phase.OPEN
	return _ok()

func finish_open(stats: Dictionary) -> void:
	last_day_stats = stats.duplicate(true)
	completed_groups += int(stats.get("completed", 0))
	failed_groups += int(stats.get("failed", 0))
	total_waits += int(stats.get("waits", 0))
	if day >= MAX_DAYS:
		phase = Types.Phase.FINISHED
	else:
		phase = Types.Phase.DAY_SUMMARY

func advance_day() -> Dictionary:
	if phase != Types.Phase.DAY_SUMMARY:
		return _error("当前不能进入下一日。")
	_rotate_and_refill_offers()
	day += 1
	time_left = DAILY_TIME
	phase = Types.Phase.PLANNING
	_prepare_base_customers()
	return _ok()

func add_sale(income: int, stall_id: int) -> void:
	coins += income
	total_income += income
	var stall = stall_by_id(stall_id)
	if stall != null:
		stall.service_count += 1

func add_reputation(amount: int) -> void:
	reputation += amount

func get_stall_detail(stall_id: int) -> Dictionary:
	var stall = stall_by_id(stall_id)
	if stall == null:
		return {}
	var edges: Array[String] = []
	for service in service_cells(stall):
		edges.append(Hex.edge_name(int(service["edge"])))
	return {
		"name": stall.definition.name,
		"category": Types.CATEGORY_FULL_NAMES[stall.definition.category],
		"description": stall.definition.description,
		"rent": stall.definition.coin_cost,
		"time": stall.definition.time_cost,
		"income": stall.definition.income,
		"service_ticks": stall.definition.service_ticks,
		"reputation_bonus": stall.definition.reputation_bonus,
		"frontage_count": stall.definition.frontage_edges.size(),
		"frontage": ", ".join(edges),
		"service_count": stall.service_count,
		"status": _stall_status_text(),
	}

func get_offer_detail(offer_index: int) -> Dictionary:
	if offer_index < 0 or offer_index >= offers.size() or offers[offer_index] == null:
		return {}
	var offer = offers[offer_index]
	return {
		"name": offer.stall_definition.name,
		"category": Types.CATEGORY_FULL_NAMES[offer.stall_definition.category],
		"rent": offer.current_cost(),
		"time": offer.stall_definition.time_cost,
		"income": offer.stall_definition.income,
		"service_ticks": offer.stall_definition.service_ticks,
		"reputation_bonus": offer.stall_definition.reputation_bonus,
		"customer": offer.customer_definition.name,
	}

func _stall_status_text() -> String:
	match phase:
		Types.Phase.OPEN:
			return "营业中"
		Types.Phase.DAY_SUMMARY:
			return "今日收市"
		Types.Phase.FINISHED:
			return "本周结束"
	return "筹备中"

func rating_text() -> String:
	if reputation >= 28:
		return "金牌夜市"
	if reputation >= 20:
		return "银牌夜市"
	if reputation >= 12:
		return "铜牌夜市"
	return "刚刚起步"

func _fill_initial_offers() -> void:
	offers.resize(6)
	for index in range(6):
		offers[index] = _make_offer(index)

func _rotate_and_refill_offers() -> void:
	var next_offers: Array = [null, null, null, null, null, null]
	for index in range(offers.size()):
		var offer = offers[index]
		if offer != null and not offer.taken:
			var next_index := (index + 1) % 6
			offer.gate_index = next_index
			offer.discount += 1
			next_offers[next_index] = offer
	for index in range(6):
		if next_offers[index] == null:
			next_offers[index] = _make_offer(index)
	offers = next_offers

func _make_offer(gate_index: int):
	var stall = _stall_catalog[rng.randi_range(0, _stall_catalog.size() - 1)]
	var customer = _customer_catalog[rng.randi_range(0, _customer_catalog.size() - 1)]
	return Types.OfferState.new(stall, customer, gate_index)

func _prepare_base_customers() -> void:
	scheduled_customers.clear()
	var count := day + 1
	for index in range(count):
		var catalog_index := posmod(seed_value + day * 3 + index * 5, _customer_catalog.size())
		var gate := posmod(seed_value + day + index * 2, 6)
		scheduled_customers.append({
			"definition": _customer_catalog[catalog_index],
			"gate": gate,
			"source": "固定",
		})

func _ok() -> Dictionary:
	return {"ok": true, "message": ""}

func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}
