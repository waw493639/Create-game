class_name CustomerSimulator
extends RefCounted

const Types = preload("res://src/market_types.gd")
const Hex = preload("res://src/hex_grid.gd")

const MAX_TICKS := 24
const ROAD_CAPACITY := 2

var model
var customers: Array = []
var tick_count := 0
var finished := false
var stats := {
	"completed": 0,
	"failed": 0,
	"waits": 0,
	"sales": 0,
}

func _init(market_model) -> void:
	model = market_model
	for index in range(model.scheduled_customers.size()):
		var entry: Dictionary = model.scheduled_customers[index]
		var gate := int(entry["gate"])
		customers.append(Types.CustomerState.new(
			index,
			entry["definition"],
			gate,
			Hex.gate_cell(gate, model.BOARD_RADIUS)
		))

func step() -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if finished:
		return events
	tick_count += 1
	for customer in customers:
		if _is_terminal(customer.status):
			continue
		if customer.status == "waiting_spawn":
			if tick_count <= customer.spawn_tick:
				continue
			if _occupancy(customer.cell, customer) >= ROAD_CAPACITY:
				continue
			customer.status = "seeking"
			events.append(_event("spawn", customer, "%s从%s门入场" % [customer.definition.name, Types.GATE_NAMES[customer.entry_gate]]))
		_process_customer(customer, events)

	if tick_count >= MAX_TICKS:
		for customer in customers:
			if not _is_terminal(customer.status):
				_fail(customer, events, "营业结束时仍未完成行程")

	finished = _all_terminal()
	if finished:
		model.finish_open(stats)
	return events

func preview_path_for_entry(entry: Dictionary) -> Array[Vector2i]:
	var gate := int(entry["gate"])
	var start := Hex.gate_cell(gate, model.BOARD_RADIUS)
	var definition = entry["definition"]
	var choice := _best_service(start, int(definition.needs[0]))
	if choice.is_empty():
		return []
	var result: Array[Vector2i] = [start]
	result.append_array(choice["path"])
	return result

func active_customers() -> Array:
	var result: Array = []
	for customer in customers:
		if customer.status != "waiting_spawn" and not _is_terminal(customer.status):
			result.append(customer)
	return result

func _process_customer(customer, events: Array[Dictionary]) -> void:
	if customer.status == "seeking":
		var need := int(customer.definition.needs[customer.current_need])
		var choice := _best_service(customer.cell, need)
		if choice.is_empty():
			_fail(customer, events, "找不到%s摊位" % Types.CATEGORY_FULL_NAMES[need])
			return
		customer.target_stall_id = int(choice["stall_id"])
		customer.target_cell = choice["cell"]
		customer.route = choice["path"].duplicate()
		customer.status = "moving"

	if customer.status == "seeking_exit":
		var exit_choice := _best_exit(customer.cell)
		if exit_choice.is_empty():
			_fail(customer, events, "找不到离场道路")
			return
		customer.target_stall_id = -1
		customer.target_cell = exit_choice["cell"]
		customer.route = exit_choice["path"].duplicate()
		customer.status = "moving_exit"

	if customer.status == "servicing":
		customer.service_left -= 1
		if customer.service_left <= 0:
			_complete_service(customer, events)
		return

	if customer.status == "moving" or customer.status == "moving_exit":
		if customer.route.is_empty():
			if customer.status == "moving_exit":
				_complete_customer(customer, events)
			else:
				var stall = model.stall_by_id(customer.target_stall_id)
				if stall == null:
					_fail(customer, events, "目标摊位已经不存在")
					return
				customer.service_left = stall.definition.service_ticks
				customer.status = "servicing"
				events.append(_event("queue", customer, "%s在%s等待服务" % [customer.definition.name, stall.definition.name]))
			return
		if customer.steps_left <= 0:
			_fail(customer, events, "移动步数耗尽")
			return
		var next: Vector2i = customer.route[0]
		if _occupancy(next, customer) >= ROAD_CAPACITY:
			customer.patience -= 1
			customer.wait_count += 1
			stats["waits"] = int(stats["waits"]) + 1
			events.append(_event("wait", customer, "%s遇到拥堵" % customer.definition.name))
			if customer.patience <= 0:
				_fail(customer, events, "耐心耗尽")
			return
		customer.cell = next
		customer.route.pop_front()
		customer.steps_left -= 1
		events.append(_event("move", customer, ""))

func _complete_service(customer, events: Array[Dictionary]) -> void:
	var stall = model.stall_by_id(customer.target_stall_id)
	if stall == null:
		_fail(customer, events, "服务中断")
		return
	model.add_sale(stall.definition.income, stall.instance_id)
	customer.reputation_bonus += stall.definition.reputation_bonus
	stats["sales"] = int(stats["sales"]) + 1
	events.append(_event(
		"sale",
		customer,
		"%s在%s消费，收入+%d" % [customer.definition.name, stall.definition.name, stall.definition.income]
	))
	customer.current_need += 1
	customer.route.clear()
	if customer.current_need >= customer.definition.needs.size():
		customer.status = "seeking_exit"
	else:
		customer.status = "seeking"

func _complete_customer(customer, events: Array[Dictionary]) -> void:
	customer.status = "completed"
	stats["completed"] = int(stats["completed"]) + 1
	var earned_reputation: int = 3 + customer.reputation_bonus
	model.add_reputation(earned_reputation)
	events.append(_event("complete", customer, "%s完成行程，口碑+%d" % [customer.definition.name, earned_reputation]))

func _fail(customer, events: Array[Dictionary], reason: String) -> void:
	if _is_terminal(customer.status):
		return
	customer.status = "failed"
	stats["failed"] = int(stats["failed"]) + 1
	events.append(_event("failed", customer, "%s离场：%s" % [customer.definition.name, reason]))

func _best_service(start: Vector2i, category: int) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var blocked: Dictionary = model.blocked_cells()
	for stall in model.stalls:
		if stall.definition.category != category:
			continue
		for service in model.service_cells(stall):
			var target: Vector2i = service["cell"]
			var path := Hex.find_path(start, target, model.BOARD_RADIUS, blocked)
			if start != target and path.is_empty():
				continue
			candidates.append({
				"stall_id": stall.instance_id,
				"cell": target,
				"path": path,
				"distance": path.size(),
				"queue": _occupancy(target, null),
			})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["distance"] != b["distance"]:
			return a["distance"] < b["distance"]
		if a["queue"] != b["queue"]:
			return a["queue"] < b["queue"]
		if a["stall_id"] != b["stall_id"]:
			return a["stall_id"] < b["stall_id"]
		var a_cell: Vector2i = a["cell"]
		var b_cell: Vector2i = b["cell"]
		return a_cell.x * 100 + a_cell.y < b_cell.x * 100 + b_cell.y
	)
	return candidates[0]

func _best_exit(start: Vector2i) -> Dictionary:
	var candidates: Array[Dictionary] = []
	var blocked: Dictionary = model.blocked_cells()
	for gate in range(6):
		var target := Hex.gate_cell(gate, model.BOARD_RADIUS)
		var path := Hex.find_path(start, target, model.BOARD_RADIUS, blocked)
		if start != target and path.is_empty():
			continue
		candidates.append({"cell": target, "path": path, "distance": path.size(), "gate": gate})
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["distance"] != b["distance"]:
			return a["distance"] < b["distance"]
		return a["gate"] < b["gate"]
	)
	return candidates[0]

func _occupancy(cell: Vector2i, ignored_customer) -> int:
	var count := 0
	for customer in customers:
		if customer == ignored_customer or customer.status == "waiting_spawn" or _is_terminal(customer.status):
			continue
		if customer.cell == cell:
			count += 1
	return count

func _all_terminal() -> bool:
	for customer in customers:
		if not _is_terminal(customer.status):
			return false
	return true

func _is_terminal(status: String) -> bool:
	return status == "completed" or status == "failed"

func _event(kind: String, customer, message: String) -> Dictionary:
	return {
		"kind": kind,
		"customer": customer,
		"message": message,
		"tick": tick_count,
	}
