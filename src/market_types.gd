class_name MarketTypes
extends RefCounted

enum Phase {
	SETUP,
	PLANNING,
	OPEN,
	DAY_SUMMARY,
	FINISHED,
}

enum Category {
	FOOD,
	DRINK,
	FUN,
	CRAFT,
}

const CATEGORY_NAMES := ["食", "饮", "乐", "艺"]
const CATEGORY_FULL_NAMES := ["食品", "饮料", "娱乐", "手作"]
const GATE_NAMES := ["东", "东北", "西北", "西", "西南", "东南"]

class StallDefinition:
	extends RefCounted

	var id: String
	var name: String
	var category: int
	var coin_cost: int
	var time_cost: int
	var income: int
	var service_ticks: int
	var frontage_edges: Array[int]
	var asset_path: String
	var description: String
	var reputation_bonus: int

	func _init(
		definition_id: String,
		display_name: String,
		stall_category: int,
		cost_coins: int,
		cost_time: int,
		stall_income: int,
		service_duration: int,
		edges: Array[int],
		asset: String = "",
		stall_description: String = "",
		stall_reputation_bonus: int = 0
	) -> void:
		id = definition_id
		name = display_name
		category = stall_category
		coin_cost = cost_coins
		time_cost = cost_time
		income = stall_income
		service_ticks = service_duration
		frontage_edges = edges.duplicate()
		asset_path = asset
		description = stall_description
		reputation_bonus = stall_reputation_bonus

class StallInstance:
	extends RefCounted

	var instance_id: int
	var definition
	var cell: Vector2i
	var rotation: int
	var service_count := 0

	func _init(id_value: int, stall_definition, stall_cell: Vector2i, facing: int = 0) -> void:
		instance_id = id_value
		definition = stall_definition
		cell = stall_cell
		rotation = posmod(facing, 6)

class CustomerDefinition:
	extends RefCounted

	var id: String
	var name: String
	var needs: Array[int]
	var max_steps: int
	var patience: int

	func _init(
		definition_id: String,
		display_name: String,
		customer_needs: Array[int],
		movement_steps: int = 12,
		wait_patience: int = 3
	) -> void:
		id = definition_id
		name = display_name
		needs = customer_needs.duplicate()
		max_steps = movement_steps
		patience = wait_patience

class CustomerState:
	extends RefCounted

	var spawn_index: int
	var definition
	var entry_gate: int
	var cell: Vector2i
	var current_need := 0
	var steps_left: int
	var patience: int
	var status := "waiting_spawn"
	var target_stall_id := -1
	var target_cell := Vector2i.ZERO
	var route: Array[Vector2i] = []
	var service_left := 0
	var spawn_tick: int
	var wait_count := 0
	var reputation_bonus := 0

	func _init(order: int, customer_definition, gate: int, gate_cell: Vector2i) -> void:
		spawn_index = order
		definition = customer_definition
		entry_gate = gate
		cell = gate_cell
		steps_left = definition.max_steps
		patience = definition.patience
		spawn_tick = order

class OfferState:
	extends RefCounted

	var stall_definition
	var customer_definition
	var gate_index: int
	var discount: int
	var taken := false

	func _init(stall, customer, gate: int, current_discount: int = 0) -> void:
		stall_definition = stall
		customer_definition = customer
		gate_index = gate
		discount = current_discount

	func current_cost() -> int:
		return maxi(1, stall_definition.coin_cost - discount)

	func needs_text() -> String:
		return "%s→%s" % [
			MarketTypes.CATEGORY_NAMES[customer_definition.needs[0]],
			MarketTypes.CATEGORY_NAMES[customer_definition.needs[1]],
		]
