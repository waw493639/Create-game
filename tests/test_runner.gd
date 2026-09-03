extends SceneTree

const Types = preload("res://src/market_types.gd")
const Hex = preload("res://src/hex_grid.gd")
const Content = preload("res://src/content.gd")
const Model = preload("res://src/market_model.gd")
const Simulator = preload("res://src/customer_simulator.gd")

var assertions := 0
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run_suite")

func _run_suite() -> void:
	print("[TEST] 六面开市规则验证")
	_test_hex_coordinates()
	_test_placement_and_rotation()
	_test_purchase_and_offer_rotation()
	_test_deterministic_content()
	_test_deterministic_week()
	_test_customer_journey()
	_test_unreachable_customer_fails()
	_test_week_run_terminates()
	_test_stall_details_and_assets()
	if failures.is_empty():
		print("[PASS] %d 项断言全部通过" % assertions)
		quit(0)
	else:
		for failure in failures:
			printerr("[FAIL] %s" % failure)
		printerr("[RESULT] %d 项断言，%d 项失败" % [assertions, failures.size()])
		quit(1)

func _test_hex_coordinates() -> void:
	var cells: Array[Vector2i] = Hex.cells(3)
	_expect(cells.size() == 37, "半径3棋盘不是37格")
	for cell in cells:
		var point := Hex.axial_to_pixel(cell, 46.0)
		_expect(Hex.pixel_to_axial(point, 46.0) == cell, "坐标往返失败：%s" % cell)
		_expect(Hex.neighbors(cell).size() == 6, "六边格邻居数量错误")
	for gate in range(6):
		_expect(Hex.is_gate(Hex.gate_cell(gate, 3), 3), "入口格识别失败：%d" % gate)

func _test_placement_and_rotation() -> void:
	var market = Model.new(42)
	var gate := Hex.gate_cell(0, market.BOARD_RADIUS)
	_expect(not bool(market.placement_result(gate).ok), "允许在入口格建造")
	_expect(bool(market.place_starter(Vector2i.ZERO, 0).ok), "无法放置起始摊位")
	_expect(not bool(market.placement_result(Vector2i.ZERO).ok), "允许摊位重叠")
	var stall = market.stalls[0]
	var initial_rotation: int = stall.rotation
	for _index in range(6):
		market.rotate_stall(stall.instance_id, 1)
	_expect(stall.rotation == initial_rotation, "旋转六次没有回到原朝向")
	var coins_before: int = market.coins
	var time_before: int = market.time_left
	_expect(bool(market.reposition_stall(stall.instance_id, Vector2i(0, 1), 2).ok), "免费重排失败")
	_expect(market.coins == coins_before and market.time_left == time_before, "免费重排错误地消耗资源")

func _test_purchase_and_offer_rotation() -> void:
	var market = Model.new(77)
	market.place_starter(Vector2i.ZERO, 0)
	var chosen_index := -1
	for index in range(market.offers.size()):
		var offer = market.offers[index]
		if offer.current_cost() <= market.coins and offer.stall_definition.time_cost <= market.time_left:
			chosen_index = index
			break
	_expect(chosen_index >= 0, "没有可购买的首日招租项")
	if chosen_index >= 0:
		var offer = market.offers[chosen_index]
		var coins_before: int = market.coins
		var time_before: int = market.time_left
		var customer_count: int = market.scheduled_customers.size()
		var result: Dictionary = market.purchase_offer(chosen_index, Vector2i(0, 1), 0)
		_expect(bool(result.ok), "有效招租购买失败")
		_expect(market.coins == coins_before - offer.current_cost(), "招租金币扣除错误")
		_expect(market.time_left == time_before - offer.stall_definition.time_cost, "招租时间扣除错误")
		_expect(market.scheduled_customers.size() == customer_count + 1, "招租没有加入客流")
		_expect(int(market.scheduled_customers.back()["gate"]) == chosen_index, "招租客流入口错误")

	var old_offer = null
	var old_index := -1
	for index in range(market.offers.size()):
		if not market.offers[index].taken:
			old_offer = market.offers[index]
			old_index = index
			break
	market.phase = Types.Phase.DAY_SUMMARY
	market.advance_day()
	_expect(market.offers[(old_index + 1) % 6] == old_offer, "未选招租项没有顺时针轮转")
	_expect(old_offer.discount == 1, "未选招租项没有降价")

func _test_deterministic_content() -> void:
	var first = Model.new(8675309)
	var second = Model.new(8675309)
	first.place_starter(Vector2i.ZERO, 0)
	second.place_starter(Vector2i.ZERO, 0)
	for index in range(6):
		_expect(first.offers[index].stall_definition.id == second.offers[index].stall_definition.id, "同种子摊位招租不一致")
		_expect(first.offers[index].customer_definition.id == second.offers[index].customer_definition.id, "同种子顾客招租不一致")

func _test_deterministic_week() -> void:
	var first := _run_week_signature(314159)
	var second := _run_week_signature(314159)
	_expect(first == second, "相同种子的完整七日结果不一致")

func _run_week_signature(run_seed: int) -> Dictionary:
	var market = Model.new(run_seed)
	market.place_starter(Vector2i.ZERO, 0)
	var daily: Array[String] = []
	for expected_day in range(1, 8):
		var customer_ids: Array[String] = []
		for entry in market.scheduled_customers:
			customer_ids.append("%s@%d" % [entry["definition"].id, entry["gate"]])
		market.start_open()
		var simulator = Simulator.new(market)
		while not simulator.finished:
			simulator.step()
		daily.append("%d:%s:%s" % [expected_day, ",".join(customer_ids), JSON.stringify(simulator.stats)])
		if expected_day < 7:
			market.advance_day()
	return {"days": daily, "income": market.total_income, "reputation": market.reputation, "completed": market.completed_groups, "failed": market.failed_groups}

func _test_customer_journey() -> void:
	var market = _two_stall_fixture()
	var customer = Types.CustomerDefinition.new(
		"test_guest", "测试顾客", [Types.Category.FOOD, Types.Category.DRINK], 14, 4
	)
	market.scheduled_customers.clear()
	market.scheduled_customers.append({"definition": customer, "gate": 3, "source": "测试"})
	market.start_open()
	var simulator = Simulator.new(market)
	for _index in range(30):
		if simulator.finished:
			break
		simulator.step()
	_expect(simulator.finished, "顾客模拟没有终止")
	_expect(int(simulator.stats["completed"]) == 1, "可达顾客没有完成两段消费")
	_expect(int(simulator.stats["sales"]) == 2, "顾客消费次数错误")
	_expect(market.reputation == 4, "完整离场口碑结算错误")
	_expect(market.total_income > 0, "消费没有产生收入")

func _test_unreachable_customer_fails() -> void:
	var market = Model.new(99)
	market.place_starter(Vector2i(-2, 0), 3)
	var customer = Types.CustomerDefinition.new(
		"needs_drink", "口渴顾客", [Types.Category.DRINK, Types.Category.DRINK]
	)
	market.scheduled_customers.clear()
	market.scheduled_customers.append({"definition": customer, "gate": 3, "source": "测试"})
	market.start_open()
	var simulator = Simulator.new(market)
	simulator.step()
	_expect(simulator.finished, "无可达摊位的模拟没有及时结束")
	_expect(int(simulator.stats["failed"]) == 1, "无可达摊位的顾客没有失败")

func _test_week_run_terminates() -> void:
	var market = Model.new(12345)
	market.place_starter(Vector2i.ZERO, 0)
	for expected_day in range(1, 8):
		_expect(market.day == expected_day, "经营日推进错误")
		_expect(market.scheduled_customers.size() == expected_day + 1, "第%d日基础客流数量错误" % expected_day)
		market.start_open()
		var simulator = Simulator.new(market)
		for _tick in range(30):
			if simulator.finished:
				break
			simulator.step()
		_expect(simulator.finished, "第%d日模拟没有终止" % expected_day)
		if expected_day < 7:
			_expect(market.phase == Types.Phase.DAY_SUMMARY, "非最终日没有进入日结")
			market.advance_day()
	_expect(market.phase == Types.Phase.FINISHED, "第七日结束后没有进入终局")

func _test_stall_details_and_assets() -> void:
	var market = Model.new(20260903)
	_expect(bool(market.place_starter(Vector2i.ZERO, 0).ok), "详情测试无法放置起始摊位")
	var detail := market.get_stall_detail(market.stalls[0].instance_id)
	_expect(String(detail.get("asset_path", "")) == "", "详情接口不应暴露内部路径")
	_expect(int(detail.get("income", -1)) == 2, "店铺详情收入错误")
	_expect(int(detail.get("reputation_bonus", -1)) == 0, "起始摊位口碑错误")
	var offer_detail := market.get_offer_detail(0)
	_expect(offer_detail.has("rent") and offer_detail.has("customer"), "招租详情字段不完整")
	for definition in Content.stalls():
		_expect(not String(definition.asset_path).is_empty(), "%s 缺少素材路径" % definition.id)
		_expect(FileAccess.file_exists(definition.asset_path), "%s 的素材文件不存在" % definition.id)
	var starter = Content.starter_stall()
	_expect(FileAccess.file_exists(starter.asset_path), "起始面摊素材文件不存在")

func _two_stall_fixture():
	var market = Model.new(2026)
	market.place_starter(Vector2i(-2, 0), 3)
	var drink_definition = null
	for definition in Content.stalls():
		if definition.category == Types.Category.DRINK:
			drink_definition = definition
			break
	market.stalls.append(Types.StallInstance.new(market.next_instance_id, drink_definition, Vector2i(0, 0), 3))
	market.next_instance_id += 1
	return market

func _expect(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures.append(message)
