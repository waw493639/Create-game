extends Node2D

const Types = preload("res://src/market_types.gd")
const Hex = preload("res://src/hex_grid.gd")
const Model = preload("res://src/market_model.gd")
const Simulator = preload("res://src/customer_simulator.gd")
const Content = preload("res://src/content.gd")

const BOARD_ORIGIN := Vector2(390, 342)
const HEX_SIZE := 46.0
const TICK_SECONDS := 0.45
const BOARD_RECT := Rect2(18, 78, 750, 522)
const OFFER_RECT := Rect2(786, 78, 476, 522)
const BOTTOM_RECT := Rect2(18, 610, 1244, 92)
const STALL_DETAIL_SIZE := Vector2(292, 226)
const STALL_DETAIL_MARGIN := 12.0
const STALL_DETAIL_OFFSET := Vector2(20, 18)

const COLOR_BG := Color("10161d")
const COLOR_PANEL := Color("18212a")
const COLOR_PANEL_ALT := Color("202c35")
const COLOR_BORDER := Color("42515a")
const COLOR_ROAD := Color("26343c")
const COLOR_GATE := Color("4f4558")
const COLOR_TEXT := Color("e9eee9")
const COLOR_MUTED := Color("9eb0b1")
const COLOR_ACCENT := Color("f2b84b")
const COLOR_BAD := Color("e96b67")
const CATEGORY_COLORS := [
	Color("d66b4f"),
	Color("3aa8a5"),
	Color("d5a93b"),
	Color("698f5b"),
]

var model
var simulator
var simulation_accumulator := 0.0
var simulation_speed := 1.0
var simulation_paused := false

var drag_kind := ""
var drag_offer_index := -1
var drag_stall_id := -1
var drag_rotation := 0
var drag_cell := Vector2i.ZERO
var mouse_position := Vector2.ZERO

var preview_path: Array[Vector2i] = []
var event_log: Array[String] = []
var shop_textures: Dictionary = {}
var hover_stall_id := -1

var day_label: Label
var coin_label: Label
var time_label: Label
var reputation_label: Label
var phase_label: Label
var message_label: Label
var help_label: Label
var log_label: RichTextLabel
var open_button: Button
var starter_button: Button
var offer_buttons: Array[Button] = []
var forecast_flow: HFlowContainer
var speed_buttons: Array[Button] = []
var pause_button: Button
var summary_panel: PanelContainer
var summary_title: Label
var summary_detail: Label
var summary_primary: Button
var summary_same_seed: Button
var summary_new_seed: Button

func _ready() -> void:
	_load_shop_textures()
	_build_interface()
	_start_run(260902)
	set_process(true)
	queue_redraw()

func _process(delta: float) -> void:
	if model == null or model.phase != Types.Phase.OPEN or simulator == null:
		return
	if simulation_paused:
		return
	simulation_accumulator += delta * simulation_speed
	while simulation_accumulator >= TICK_SECONDS and not simulator.finished:
		simulation_accumulator -= TICK_SECONDS
		var events: Array[Dictionary] = simulator.step()
		for event in events:
			if not String(event["message"]).is_empty():
				_append_log(String(event["message"]))
		_refresh_ui()
		queue_redraw()
	if simulator.finished:
		_show_summary()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_position = event.position
		_update_hover_stall(mouse_position)
		if not drag_kind.is_empty():
			drag_cell = _screen_to_cell(mouse_position)
			queue_redraw()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and not drag_kind.is_empty():
			_cancel_drag()
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventMouseButton):
		return
	mouse_position = event.position
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_try_begin_stall_drag(mouse_position)
		elif not drag_kind.is_empty():
			_commit_drag()
			get_viewport().set_input_as_handled()
	elif event.pressed and event.button_index in [MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var amount := -1 if event.button_index == MOUSE_BUTTON_WHEEL_DOWN else 1
		_rotate_at_mouse(amount)
		get_viewport().set_input_as_handled()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), COLOR_BG)
	draw_rect(Rect2(0, 0, 1280, 68), Color("0c1117"))
	draw_rect(BOARD_RECT, COLOR_PANEL)
	draw_rect(OFFER_RECT, COLOR_PANEL)
	draw_rect(BOTTOM_RECT, COLOR_PANEL)
	draw_rect(BOARD_RECT, COLOR_BORDER, false, 2.0)
	draw_rect(OFFER_RECT, COLOR_BORDER, false, 2.0)
	draw_rect(BOTTOM_RECT, COLOR_BORDER, false, 2.0)
	_draw_board()
	_draw_preview_path()
	_draw_stalls()
	_draw_customers()
	_draw_drag_preview()
	_draw_stall_detail()

func _draw_board() -> void:
	if model == null:
		return
	var font := ThemeDB.fallback_font
	for cell in Hex.cells(model.BOARD_RADIUS):
		var center := BOARD_ORIGIN + Hex.axial_to_pixel(cell, HEX_SIZE)
		var fill := COLOR_GATE if Hex.is_gate(cell, model.BOARD_RADIUS) else COLOR_ROAD
		var points := Hex.polygon(center, HEX_SIZE - 2.0)
		draw_colored_polygon(points, fill)
		draw_polyline(_closed(points), COLOR_BORDER, 1.5, true)
		if Hex.is_gate(cell, model.BOARD_RADIUS):
			var gate_index := _gate_index_for_cell(cell)
			draw_circle(center, 15.0, Color(COLOR_ACCENT, 0.18))
			draw_string(font, center + Vector2(-16, 6), Types.GATE_NAMES[gate_index], HORIZONTAL_ALIGNMENT_CENTER, 32, 15, COLOR_ACCENT)

func _draw_stalls() -> void:
	if model == null:
		return
	var font := ThemeDB.fallback_font
	for stall in model.stalls:
		if drag_kind == "stall" and stall.instance_id == drag_stall_id:
			continue
		var center := BOARD_ORIGIN + Hex.axial_to_pixel(stall.cell, HEX_SIZE)
		var color: Color = CATEGORY_COLORS[stall.definition.category]
		var points := Hex.polygon(center, HEX_SIZE - 5.0)
		draw_colored_polygon(points, color.darkened(0.18))
		draw_polyline(_closed(points), color.lightened(0.28), 2.0, true)
		var texture = shop_textures.get(stall.definition.id)
		if texture != null:
			draw_texture_rect(texture, Rect2(center - Vector2(28, 28), Vector2(56, 56)), false)
		else:
			draw_string(font, center + Vector2(-18, 5), "缺图", HORIZONTAL_ALIGNMENT_CENTER, 36, 11, COLOR_BAD)
		_draw_frontages(center, stall.definition, stall.rotation, color)
		draw_string(font, center + Vector2(-32, 27), stall.definition.name, HORIZONTAL_ALIGNMENT_CENTER, 64, 11, COLOR_TEXT)

func _draw_frontages(center: Vector2, definition, rotation: int, color: Color) -> void:
	for local_edge in definition.frontage_edges:
		var direction: int = posmod(int(local_edge) + rotation, 6)
		var angle := deg_to_rad(float(direction * 60))
		var marker_center := center + Vector2(cos(angle), sin(angle)) * HEX_SIZE * 0.72
		var tangent := Vector2(-sin(angle), cos(angle)) * 10.0
		draw_line(marker_center - tangent, marker_center + tangent, COLOR_ACCENT, 5.0, true)
		draw_circle(marker_center, 4.0, color.lightened(0.35))

func _draw_customers() -> void:
	if simulator == null or model.phase != Types.Phase.OPEN:
		return
	var font := ThemeDB.fallback_font
	for customer in simulator.active_customers():
		var center := BOARD_ORIGIN + Hex.axial_to_pixel(customer.cell, HEX_SIZE)
		var offset_index: int = customer.spawn_index % 3
		center += Vector2(float(offset_index - 1) * 8.0, float(customer.spawn_index % 2) * 6.0 - 3.0)
		var category: int = customer.definition.needs[mini(customer.current_need, customer.definition.needs.size() - 1)]
		var color: Color = CATEGORY_COLORS[category]
		draw_circle(center, 13.0, Color("f4f0e6"))
		draw_arc(center, 14.0, 0.0, TAU, 24, color, 3.0, true)
		draw_string(font, center + Vector2(-8, 5), Types.CATEGORY_NAMES[category], HORIZONTAL_ALIGNMENT_CENTER, 16, 12, Color("18212a"))
		if customer.status == "servicing":
			draw_arc(center, 18.0, -PI * 0.5, PI * 1.5, 28, COLOR_ACCENT, 2.0, true)

func _draw_preview_path() -> void:
	if preview_path.size() < 2:
		return
	var points := PackedVector2Array()
	for cell in preview_path:
		points.append(BOARD_ORIGIN + Hex.axial_to_pixel(cell, HEX_SIZE))
	draw_polyline(points, Color(COLOR_ACCENT, 0.72), 4.0, true)
	for point in points:
		draw_circle(point, 4.0, COLOR_ACCENT)

func _draw_drag_preview() -> void:
	if drag_kind.is_empty() or model == null:
		return
	var definition = _drag_definition()
	if definition == null:
		return
	var ignored_id := drag_stall_id if drag_kind == "stall" else -1
	var result: Dictionary = model.placement_result(drag_cell, ignored_id)
	var center := BOARD_ORIGIN + Hex.axial_to_pixel(drag_cell, HEX_SIZE)
	var color: Color = CATEGORY_COLORS[definition.category] if result.ok else COLOR_BAD
	var points := Hex.polygon(center, HEX_SIZE - 5.0)
	draw_colored_polygon(points, Color(color, 0.62))
	draw_polyline(_closed(points), color.lightened(0.25), 3.0, true)
	var texture = shop_textures.get(definition.id)
	if texture != null:
		draw_texture_rect(texture, Rect2(center - Vector2(28, 28), Vector2(56, 56)), false, Color(1, 1, 1, 0.78))
	_draw_frontages(center, definition, drag_rotation, color)

func _build_interface() -> void:
	day_label = _make_label(Vector2(24, 15), Vector2(130, 40), "", 22)
	coin_label = _make_label(Vector2(170, 15), Vector2(150, 40), "", 19)
	time_label = _make_label(Vector2(330, 15), Vector2(180, 40), "", 19)
	reputation_label = _make_label(Vector2(520, 15), Vector2(170, 40), "", 19)
	phase_label = _make_label(Vector2(690, 15), Vector2(190, 40), "", 17, COLOR_ACCENT)
	message_label = _make_label(Vector2(24, 558), Vector2(560, 34), "", 15, COLOR_MUTED)
	help_label = _make_label(Vector2(34, 91), Vector2(710, 30), "", 14, COLOR_MUTED)
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var restart_same := _make_button(Vector2(1050, 16), Vector2(92, 36), "重开")
	restart_same.pressed.connect(_restart_same_seed)
	var restart_new := _make_button(Vector2(1150, 16), Vector2(106, 36), "新种子")
	restart_new.pressed.connect(_restart_new_seed)

	starter_button = _make_button(Vector2(825, 142), Vector2(398, 106), "起始摊位  街角面摊\n食品 · 免费 · 双售卖面\n按住并拖到棋盘")
	starter_button.icon = shop_textures.get("starter_noodles")
	starter_button.expand_icon = true
	starter_button.tooltip_text = "街角面摊\n免费 · 收入2金币 · 服务1节拍 · 口碑+0"
	starter_button.button_down.connect(_begin_starter_drag)

	for index in range(6):
		var col := index % 2
		var row := index / 2
		var button := _make_button(
			Vector2(806 + col * 224, 113 + row * 127),
			Vector2(210, 112),
			""
		)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		button.button_down.connect(_begin_offer_drag.bind(index))
		offer_buttons.append(button)

	log_label = RichTextLabel.new()
	log_label.position = Vector2(806, 496)
	log_label.size = Vector2(436, 92)
	log_label.bbcode_enabled = false
	log_label.fit_content = false
	log_label.scroll_active = false
	log_label.add_theme_font_size_override("normal_font_size", 13)
	log_label.add_theme_color_override("default_color", COLOR_MUTED)
	add_child(log_label)

	open_button = _make_button(Vector2(606, 548), Vector2(146, 42), "开市")
	open_button.pressed.connect(_start_open)

	forecast_flow = HFlowContainer.new()
	forecast_flow.position = Vector2(32, 643)
	forecast_flow.size = Vector2(742, 51)
	forecast_flow.add_theme_constant_override("h_separation", 7)
	forecast_flow.add_theme_constant_override("v_separation", 5)
	add_child(forecast_flow)

	pause_button = _make_button(Vector2(806, 640), Vector2(88, 40), "暂停")
	pause_button.pressed.connect(_toggle_pause)
	for index in range(3):
		var speeds := [1.0, 2.0, 4.0]
		var button := _make_button(Vector2(904 + index * 82, 640), Vector2(72, 40), "%dx" % int(speeds[index]))
		button.pressed.connect(_set_speed.bind(speeds[index]))
		speed_buttons.append(button)

	_build_summary_panel()

func _build_summary_panel() -> void:
	summary_panel = PanelContainer.new()
	summary_panel.position = Vector2(354, 168)
	summary_panel.size = Vector2(572, 382)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("202a33")
	style.border_color = COLOR_ACCENT
	style.set_border_width_all(2)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 32
	style.content_margin_right = 32
	style.content_margin_top = 28
	style.content_margin_bottom = 24
	summary_panel.add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	summary_panel.add_child(column)
	summary_title = Label.new()
	summary_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_title.add_theme_font_size_override("font_size", 28)
	summary_title.add_theme_color_override("font_color", COLOR_ACCENT)
	column.add_child(summary_title)
	summary_detail = Label.new()
	summary_detail.custom_minimum_size = Vector2(480, 188)
	summary_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_detail.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	summary_detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_detail.add_theme_font_size_override("font_size", 17)
	summary_detail.add_theme_color_override("font_color", COLOR_TEXT)
	column.add_child(summary_detail)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	summary_primary = Button.new()
	summary_primary.custom_minimum_size = Vector2(126, 42)
	summary_primary.pressed.connect(_next_day)
	row.add_child(summary_primary)
	summary_same_seed = Button.new()
	summary_same_seed.text = "同种子重开"
	summary_same_seed.custom_minimum_size = Vector2(136, 42)
	summary_same_seed.pressed.connect(_restart_same_seed)
	row.add_child(summary_same_seed)
	summary_new_seed = Button.new()
	summary_new_seed.text = "新种子"
	summary_new_seed.custom_minimum_size = Vector2(112, 42)
	summary_new_seed.pressed.connect(_restart_new_seed)
	row.add_child(summary_new_seed)
	add_child(summary_panel)
	summary_panel.visible = false

func _make_label(position_value: Vector2, size_value: Vector2, text_value: String, font_size: int, color: Color = COLOR_TEXT) -> Label:
	var label := Label.new()
	label.position = position_value
	label.size = size_value
	label.text = text_value
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	add_child(label)
	return label

func _make_button(position_value: Vector2, size_value: Vector2, text_value: String) -> Button:
	var button := Button.new()
	button.position = position_value
	button.size = size_value
	button.text = text_value
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	button.add_theme_color_override("font_pressed_color", COLOR_ACCENT)
	var normal := StyleBoxFlat.new()
	normal.bg_color = COLOR_PANEL_ALT
	normal.border_color = COLOR_BORDER
	normal.set_border_width_all(1)
	normal.corner_radius_top_left = 5
	normal.corner_radius_top_right = 5
	normal.corner_radius_bottom_left = 5
	normal.corner_radius_bottom_right = 5
	var hover := normal.duplicate()
	hover.bg_color = Color("2a3a43")
	hover.border_color = COLOR_ACCENT
	var pressed := normal.duplicate()
	pressed.bg_color = Color("344049")
	pressed.border_color = COLOR_ACCENT
	button.add_theme_stylebox_override("normal", normal)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("pressed", pressed)
	add_child(button)
	return button

func _start_run(run_seed: int) -> void:
	model = Model.new(run_seed)
	simulator = null
	simulation_accumulator = 0.0
	simulation_speed = 1.0
	simulation_paused = false
	event_log.clear()
	preview_path.clear()
	_cancel_drag()
	_append_log("种子 %d：先把街角面摊放进市场。" % run_seed)
	_refresh_ui()
	queue_redraw()

func _begin_starter_drag() -> void:
	if model.phase != Types.Phase.SETUP:
		return
	drag_kind = "starter"
	drag_rotation = 0
	drag_cell = _screen_to_cell(get_viewport().get_mouse_position())
	message_label.text = "拖到非入口格；右键或滚轮旋转。"
	queue_redraw()

func _begin_offer_drag(index: int) -> void:
	if model.phase != Types.Phase.PLANNING or index >= model.offers.size():
		return
	var offer = model.offers[index]
	if offer == null or offer.taken:
		return
	drag_kind = "offer"
	drag_offer_index = index
	drag_rotation = 0
	drag_cell = _screen_to_cell(get_viewport().get_mouse_position())
	message_label.text = "拖放%s；这会让%s从%s门入场。" % [offer.stall_definition.name, offer.customer_definition.name, Types.GATE_NAMES[index]]
	queue_redraw()

func _try_begin_stall_drag(position_value: Vector2) -> void:
	if not drag_kind.is_empty() or model == null or model.phase != Types.Phase.PLANNING:
		return
	var cell := _screen_to_cell(position_value)
	if not Hex.is_inside(cell, model.BOARD_RADIUS):
		return
	var stall = model.stall_at(cell)
	if stall == null:
		return
	drag_kind = "stall"
	drag_stall_id = stall.instance_id
	drag_rotation = stall.rotation
	drag_cell = stall.cell
	message_label.text = "免费重新布置；松开鼠标确认。"
	queue_redraw()

func _commit_drag() -> void:
	var result := {"ok": false, "message": "没有可放置的摊位。"}
	match drag_kind:
		"starter":
			result = model.place_starter(drag_cell, drag_rotation)
		"offer":
			result = model.purchase_offer(drag_offer_index, drag_cell, drag_rotation)
		"stall":
			result = model.reposition_stall(drag_stall_id, drag_cell, drag_rotation)
	if result.ok:
		if drag_kind == "starter":
			_append_log("街角面摊开张，第一日开始筹备。")
		elif drag_kind == "offer":
			var offer = model.offers[drag_offer_index]
			_append_log("招租%s；%s加入今日客流。" % [offer.stall_definition.name, offer.customer_definition.name])
		message_label.text = "布局已更新。空格就是街道。"
	else:
		message_label.text = String(result.message)
	_cancel_drag(false)
	_refresh_ui()
	queue_redraw()

func _cancel_drag(clear_message: bool = true) -> void:
	drag_kind = ""
	drag_offer_index = -1
	drag_stall_id = -1
	drag_rotation = 0
	if clear_message and message_label != null:
		message_label.text = "已取消。"
	queue_redraw()

func _rotate_at_mouse(amount: int) -> void:
	if model == null:
		return
	if not drag_kind.is_empty():
		drag_rotation = posmod(drag_rotation + amount, 6)
		queue_redraw()
		return
	if model.phase != Types.Phase.PLANNING:
		return
	var cell := _screen_to_cell(mouse_position)
	var stall = model.stall_at(cell)
	if stall != null:
		model.rotate_stall(stall.instance_id, amount)
		message_label.text = "%s旋转60°。" % stall.definition.name
		queue_redraw()

func _start_open() -> void:
	var result: Dictionary = model.start_open()
	if not result.ok:
		message_label.text = String(result.message)
		return
	simulator = Simulator.new(model)
	simulation_accumulator = 0.0
	simulation_paused = false
	preview_path.clear()
	_append_log("第%d日开市，共%d批顾客。" % [model.day, model.scheduled_customers.size()])
	_refresh_ui()
	queue_redraw()

func _next_day() -> void:
	var result: Dictionary = model.advance_day()
	if not result.ok:
		return
	simulator = null
	summary_panel.visible = false
	preview_path.clear()
	_append_log("第%d日：旧招租项轮转并降价。" % model.day)
	_refresh_ui()
	queue_redraw()

func _toggle_pause() -> void:
	if model.phase != Types.Phase.OPEN:
		return
	simulation_paused = not simulation_paused
	pause_button.text = "继续" if simulation_paused else "暂停"

func _set_speed(speed: float) -> void:
	simulation_speed = speed
	for index in range(speed_buttons.size()):
		var expected: float = [1.0, 2.0, 4.0][index]
		speed_buttons[index].text = ("● %dx" if is_equal_approx(expected, speed) else "%dx") % int(expected)

func _restart_same_seed() -> void:
	_start_run(model.seed_value)

func _restart_new_seed() -> void:
	var new_seed := int(Time.get_unix_time_from_system() * 1000.0) & 0x7fffffff
	_start_run(new_seed)

func _show_summary() -> void:
	if summary_panel.visible:
		return
	_refresh_ui()
	summary_panel.visible = true
	if model.phase == Types.Phase.FINISHED:
		summary_title.text = "%s · %d口碑" % [model.rating_text(), model.reputation]
		var total_groups: int = model.completed_groups + model.failed_groups
		var average_wait := float(model.total_waits) / float(maxi(1, total_groups))
		var utilization := _utilization_text()
		summary_detail.text = "七日经营结束\n\n总收入：%d金币    完成：%d批    失败：%d批\n平均等待：%.1f次/批\n\n%s" % [
			model.total_income,
			model.completed_groups,
			model.failed_groups,
			average_wait,
			utilization,
		]
		summary_primary.visible = false
		summary_same_seed.visible = true
		summary_new_seed.visible = true
	else:
		var stats: Dictionary = model.last_day_stats
		summary_title.text = "第%d日收市" % model.day
		summary_detail.text = "今日完成 %d 批，失败 %d 批\n产生 %d 次消费，遇到 %d 次拥堵\n\n未选招租项将在明日顺时针轮转并降价。" % [
			int(stats.get("completed", 0)),
			int(stats.get("failed", 0)),
			int(stats.get("sales", 0)),
			int(stats.get("waits", 0)),
		]
		summary_primary.text = "进入第%d日" % (model.day + 1)
		summary_primary.visible = true
		summary_same_seed.visible = false
		summary_new_seed.visible = false

func _refresh_ui() -> void:
	if model == null:
		return
	day_label.text = "第 %d / %d 日" % [model.day, model.MAX_DAYS]
	coin_label.text = "金币  %d" % model.coins
	time_label.text = "筹备时间  %d / %d" % [model.time_left, model.DAILY_TIME]
	reputation_label.text = "口碑  %d" % model.reputation
	phase_label.text = _phase_text()
	starter_button.visible = model.phase == Types.Phase.SETUP
	help_label.text = "把起始摊位拖入棋盘，售卖面需朝向空街。" if model.phase == Types.Phase.SETUP else "空格是街道；入口不可建造。右键或滚轮旋转，开市前可免费重排。"
	for index in range(offer_buttons.size()):
		var button := offer_buttons[index]
		button.visible = model.phase != Types.Phase.SETUP
		if index >= model.offers.size() or model.offers[index] == null:
			button.text = "%s门\n暂无招租" % Types.GATE_NAMES[index]
			button.disabled = true
			continue
		var offer = model.offers[index]
		button.text = "%s门  %s\n%s · %d币 / %d时\n带来：%s  %s" % [
			Types.GATE_NAMES[index],
			offer.stall_definition.name,
			Types.CATEGORY_FULL_NAMES[offer.stall_definition.category],
			offer.current_cost(),
			offer.stall_definition.time_cost,
			offer.customer_definition.name,
			offer.needs_text(),
		]
		button.icon = shop_textures.get(offer.stall_definition.id)
		button.expand_icon = true
		button.tooltip_text = "%s\n租金 %d金币 · 筹备 %d时 · 收入 %d金币 · 口碑+%d\n顾客：%s %s" % [offer.stall_definition.name, offer.current_cost(), offer.stall_definition.time_cost, offer.stall_definition.income, offer.stall_definition.reputation_bonus, offer.customer_definition.name, offer.needs_text()]
		button.disabled = offer.taken or model.phase != Types.Phase.PLANNING or model.coins < offer.current_cost() or model.time_left < offer.stall_definition.time_cost
		button.modulate = Color(1, 1, 1, 0.48) if offer.taken else Color.WHITE
	open_button.visible = model.phase == Types.Phase.PLANNING
	pause_button.visible = model.phase == Types.Phase.OPEN
	for button in speed_buttons:
		button.visible = model.phase == Types.Phase.OPEN
	_refresh_forecast()
	_refresh_log()

func _refresh_forecast() -> void:
	for child in forecast_flow.get_children():
		forecast_flow.remove_child(child)
		child.queue_free()
	if model.phase == Types.Phase.SETUP:
		var label := Label.new()
		label.text = "客流预报将在起始摊位放置后出现。"
		label.add_theme_color_override("font_color", COLOR_MUTED)
		forecast_flow.add_child(label)
		return
	for index in range(model.scheduled_customers.size()):
		var entry: Dictionary = model.scheduled_customers[index]
		var definition = entry["definition"]
		var button := Button.new()
		button.custom_minimum_size = Vector2(112, 38)
		button.text = "%s门 %s→%s" % [
			Types.GATE_NAMES[int(entry["gate"])],
			Types.CATEGORY_NAMES[definition.needs[0]],
			Types.CATEGORY_NAMES[definition.needs[1]],
		]
		button.tooltip_text = "%s（%s客流）：悬停查看首段预计路线" % [definition.name, entry["source"]]
		button.mouse_entered.connect(_preview_customer.bind(index))
		button.mouse_exited.connect(_clear_preview)
		forecast_flow.add_child(button)

func _preview_customer(index: int) -> void:
	if model.phase != Types.Phase.PLANNING or index >= model.scheduled_customers.size():
		return
	var preview_sim = Simulator.new(model)
	preview_path = preview_sim.preview_path_for_entry(model.scheduled_customers[index])
	message_label.text = "黄色路线为首项需求的预计最短路，不计动态拥堵。" if preview_path.size() >= 2 else "当前布局无法满足这批顾客的首项需求。"
	queue_redraw()

func _clear_preview() -> void:
	preview_path.clear()
	queue_redraw()

func _append_log(message: String) -> void:
	if message.is_empty():
		return
	event_log.append(message)
	while event_log.size() > 6:
		event_log.pop_front()
	_refresh_log()

func _refresh_log() -> void:
	if log_label != null:
		log_label.text = "\n".join(event_log)

func _utilization_text() -> String:
	var rows: Array[String] = []
	var ordered: Array = model.stalls.duplicate()
	ordered.sort_custom(func(a, b) -> bool: return a.service_count > b.service_count)
	for index in range(mini(4, ordered.size())):
		var stall = ordered[index]
		rows.append("%s：%d次服务" % [stall.definition.name, stall.service_count])
	return "摊位利用率\n" + "    ".join(rows)

func _phase_text() -> String:
	match model.phase:
		Types.Phase.SETUP:
			return "准备入场"
		Types.Phase.PLANNING:
			return "筹备中"
		Types.Phase.OPEN:
			return "营业中 · 第%d节拍" % (simulator.tick_count if simulator != null else 0)
		Types.Phase.DAY_SUMMARY:
			return "今日收市"
		Types.Phase.FINISHED:
			return "七日结算"
	return ""

func _load_shop_textures() -> void:
	for definition in Content.stalls():
		if not definition.asset_path.is_empty():
			shop_textures[definition.id] = load(definition.asset_path)
	var starter = Content.starter_stall()
	if not starter.asset_path.is_empty():
		shop_textures[starter.id] = load(starter.asset_path)

func _update_hover_stall(position_value: Vector2) -> void:
	var next_id := -1
	if model != null:
		var cell := _screen_to_cell(position_value)
		if Hex.is_inside(cell, model.BOARD_RADIUS):
			var stall = model.stall_at(cell)
			if stall != null:
				next_id = stall.instance_id
	if next_id != hover_stall_id:
		hover_stall_id = next_id
		queue_redraw()
	elif next_id >= 0:
		queue_redraw()

func _draw_stall_detail() -> void:
	if model == null:
		return
	var detail: Dictionary = model.get_stall_detail(hover_stall_id) if hover_stall_id >= 0 else {}
	if not drag_kind.is_empty():
		var definition = _drag_definition()
		if definition != null:
			detail = _definition_detail(definition)
	if detail.is_empty():
		return
	var panel_rect := _stall_detail_rect()
	draw_rect(panel_rect, Color("202c35"))
	draw_rect(panel_rect, COLOR_ACCENT, false, 2.0)
	var font := ThemeDB.fallback_font
	draw_string(font, panel_rect.position + Vector2(14, 26), "%s · %s" % [detail["name"], detail["category"]], HORIZONTAL_ALIGNMENT_LEFT, 264, 17, COLOR_ACCENT)
	draw_string(font, panel_rect.position + Vector2(14, 49), String(detail["description"]), HORIZONTAL_ALIGNMENT_LEFT, 264, 12, COLOR_TEXT)
	var lines := ["租金 %d金币    筹备 %d时" % [detail["rent"], detail["time"]], "单次收入 %d金币    服务 %d节拍" % [detail["income"], detail["service_ticks"]], "口碑加成 +%d    售卖面 %d个" % [detail["reputation_bonus"], detail["frontage_count"]], "当前售卖面：%s" % (detail["frontage"] if not String(detail["frontage"]).is_empty() else "暂无有效朝向"), "累计服务 %d次    状态：%s" % [detail["service_count"], detail["status"]]]
	for index in range(lines.size()):
		draw_string(font, panel_rect.position + Vector2(14, 82 + index * 25), lines[index], HORIZONTAL_ALIGNMENT_LEFT, 264, 13, COLOR_TEXT)

func _stall_detail_rect() -> Rect2:
	var viewport_size := get_viewport_rect().size
	var panel_position := mouse_position + STALL_DETAIL_OFFSET
	if panel_position.x + STALL_DETAIL_SIZE.x > viewport_size.x - STALL_DETAIL_MARGIN:
		panel_position.x = mouse_position.x - STALL_DETAIL_SIZE.x - STALL_DETAIL_OFFSET.x
	if panel_position.y + STALL_DETAIL_SIZE.y > viewport_size.y - STALL_DETAIL_MARGIN:
		panel_position.y = mouse_position.y - STALL_DETAIL_SIZE.y - STALL_DETAIL_OFFSET.y
	panel_position.x = clampf(panel_position.x, STALL_DETAIL_MARGIN, viewport_size.x - STALL_DETAIL_SIZE.x - STALL_DETAIL_MARGIN)
	panel_position.y = clampf(panel_position.y, STALL_DETAIL_MARGIN, viewport_size.y - STALL_DETAIL_SIZE.y - STALL_DETAIL_MARGIN)
	return Rect2(panel_position, STALL_DETAIL_SIZE)

func _definition_detail(definition) -> Dictionary:
	var edge_names: Array[String] = []
	for local_edge in definition.frontage_edges:
		edge_names.append(Hex.edge_name(int(local_edge) + drag_rotation))
	return {"name": definition.name, "category": Types.CATEGORY_FULL_NAMES[definition.category], "description": definition.description, "rent": definition.coin_cost, "time": definition.time_cost, "income": definition.income, "service_ticks": definition.service_ticks, "reputation_bonus": definition.reputation_bonus, "frontage_count": definition.frontage_edges.size(), "frontage": ", ".join(edge_names), "service_count": 0, "status": "拖动中"}

func _screen_to_cell(screen_position: Vector2) -> Vector2i:
	return Hex.pixel_to_axial(screen_position - BOARD_ORIGIN, HEX_SIZE)

func _drag_definition():
	match drag_kind:
		"starter":
			return Content.starter_stall()
		"offer":
			if drag_offer_index >= 0 and drag_offer_index < model.offers.size():
				return model.offers[drag_offer_index].stall_definition
		"stall":
			var stall = model.stall_by_id(drag_stall_id)
			return stall.definition if stall != null else null
	return null

func _gate_index_for_cell(cell: Vector2i) -> int:
	for index in range(6):
		if Hex.gate_cell(index, model.BOARD_RADIUS) == cell:
			return index
	return 0

func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var result := points.duplicate()
	if not result.is_empty():
		result.append(result[0])
	return result
