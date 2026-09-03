class_name HexGrid
extends RefCounted

const SQRT_3 := 1.7320508075688772
const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0),
	Vector2i(1, -1),
	Vector2i(0, -1),
	Vector2i(-1, 0),
	Vector2i(-1, 1),
	Vector2i(0, 1),
]

static func edge_name(edge: int) -> String:
	return ["东", "东北", "西北", "西", "西南", "东南"][posmod(edge, 6)]

static func cells(radius: int) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for q in range(-radius, radius + 1):
		var r_min: int = maxi(-radius, -q - radius)
		var r_max: int = mini(radius, -q + radius)
		for r in range(r_min, r_max + 1):
			result.append(Vector2i(q, r))
	return result

static func is_inside(cell: Vector2i, radius: int) -> bool:
	return maxi(maxi(abs(cell.x), abs(cell.y)), abs(cell.x + cell.y)) <= radius

static func gate_cell(gate_index: int, radius: int) -> Vector2i:
	return DIRECTIONS[posmod(gate_index, 6)] * radius

static func is_gate(cell: Vector2i, radius: int) -> bool:
	for direction in DIRECTIONS:
		if cell == direction * radius:
			return true
	return false

static func neighbor(cell: Vector2i, direction: int) -> Vector2i:
	return cell + DIRECTIONS[posmod(direction, 6)]

static func neighbors(cell: Vector2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for direction in DIRECTIONS:
		result.append(cell + direction)
	return result

static func axial_to_pixel(cell: Vector2i, size: float) -> Vector2:
	return Vector2(
		size * SQRT_3 * (float(cell.x) + float(cell.y) * 0.5),
		size * 1.5 * float(cell.y)
	)

static func pixel_to_axial(point: Vector2, size: float) -> Vector2i:
	var q := (SQRT_3 / 3.0 * point.x - 1.0 / 3.0 * point.y) / size
	var r := (2.0 / 3.0 * point.y) / size
	return _cube_round(q, r)

static func polygon(center: Vector2, size: float, inset: float = 0.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	var actual_size := maxf(1.0, size - inset)
	for index in range(6):
		var angle := deg_to_rad(float(index * 60 - 30))
		points.append(center + Vector2(cos(angle), sin(angle)) * actual_size)
	return points

static func distance(a: Vector2i, b: Vector2i) -> int:
	var delta := a - b
	return maxi(maxi(abs(delta.x), abs(delta.y)), abs(delta.x + delta.y))

static func find_path(
	start: Vector2i,
	goal: Vector2i,
	radius: int,
	blocked: Dictionary
) -> Array[Vector2i]:
	if start == goal:
		return []
	if not is_inside(start, radius) or not is_inside(goal, radius) or blocked.has(goal):
		return []
	var frontier: Array[Vector2i] = [start]
	var came_from: Dictionary = {start: start}
	var head := 0
	while head < frontier.size():
		var current: Vector2i = frontier[head]
		head += 1
		for direction in DIRECTIONS:
			var next := current + direction
			if not is_inside(next, radius) or blocked.has(next) or came_from.has(next):
				continue
			came_from[next] = current
			if next == goal:
				return _reconstruct_path(came_from, start, goal)
			frontier.append(next)
	return []

static func _reconstruct_path(
	came_from: Dictionary,
	start: Vector2i,
	goal: Vector2i
) -> Array[Vector2i]:
	var reversed: Array[Vector2i] = []
	var current := goal
	while current != start:
		reversed.append(current)
		current = came_from[current]
	reversed.reverse()
	return reversed

static func _cube_round(q: float, r: float) -> Vector2i:
	var x: float = q
	var z: float = r
	var y: float = -x - z
	var rx: int = roundi(x)
	var ry: int = roundi(y)
	var rz: int = roundi(z)
	var x_diff: float = abs(float(rx) - x)
	var y_diff: float = abs(float(ry) - y)
	var z_diff: float = abs(float(rz) - z)
	if x_diff > y_diff and x_diff > z_diff:
		rx = -ry - rz
	elif y_diff > z_diff:
		ry = -rx - rz
	else:
		rz = -rx - ry
	return Vector2i(rx, rz)
