class_name MarketContent
extends RefCounted

const Types = preload("res://src/market_types.gd")

static func starter_stall():
	return Types.StallDefinition.new(
		"starter_noodles", "街角面摊", Types.Category.FOOD,
		0, 0, 2, 1, [0, 1], "res://assets/shops/starter_noodles/clean.png", "稳定的基础食品摊，适合放在入口附近。", 0
	)

static func stalls() -> Array:
	return [
		Types.StallDefinition.new("skewer", "炭火串摊", Types.Category.FOOD, 3, 1, 2, 2, [0, 1], "res://assets/shops/skewer/clean.png", "双面出餐，服务稳定。", 1),
		Types.StallDefinition.new("dumpling", "蒸笼小铺", Types.Category.FOOD, 4, 2, 3, 1, [0], "res://assets/shops/dumpling/clean.png", "单面高效率食品摊。", 2),
		Types.StallDefinition.new("rice", "饭团车", Types.Category.FOOD, 2, 1, 1, 1, [0, 2], "res://assets/shops/rice/clean.png", "便宜灵活，拥有两个售卖面。", 0),
		Types.StallDefinition.new("tea", "冷泡茶铺", Types.Category.DRINK, 3, 1, 2, 1, [0, 1], "res://assets/shops/tea/clean.png", "快速饮品，适合疏导入口客流。", 1),
		Types.StallDefinition.new("juice", "鲜果饮站", Types.Category.DRINK, 4, 2, 3, 2, [0, 2], "res://assets/shops/juice/clean.png", "高收入但需要更长服务时间。", 2),
		Types.StallDefinition.new("soda", "汽水推车", Types.Category.DRINK, 2, 1, 1, 1, [0], "res://assets/shops/soda/clean.png", "低租金的单面饮品摊。", 0),
		Types.StallDefinition.new("ring_toss", "投环游戏", Types.Category.FUN, 3, 1, 2, 2, [0, 1], "res://assets/shops/ring_toss/clean.png", "双面娱乐摊，能承接两条路线。", 1),
		Types.StallDefinition.new("stage", "街头舞台", Types.Category.FUN, 5, 3, 4, 2, [0, 2], "res://assets/shops/stage/clean.png", "高收入舞台，筹备成本最高。", 2),
		Types.StallDefinition.new("fortune", "签运小摊", Types.Category.FUN, 2, 1, 1, 1, [0], "res://assets/shops/fortune/clean.png", "轻量娱乐，适合填补狭窄道路。", 0),
		Types.StallDefinition.new("pottery", "手捏陶坊", Types.Category.CRAFT, 4, 2, 3, 2, [0, 1], "res://assets/shops/pottery/clean.png", "双面手作摊，口碑表现出色。", 2),
		Types.StallDefinition.new("paper", "纸艺灯铺", Types.Category.CRAFT, 3, 1, 2, 1, [0, 2], "res://assets/shops/paper/clean.png", "快速手作服务，路线适应性好。", 1),
		Types.StallDefinition.new("carving", "木刻工坊", Types.Category.CRAFT, 5, 3, 4, 2, [0], "res://assets/shops/carving/clean.png", "高价值单面手作，服务较慢。", 2),
	]

static func customers() -> Array:
	var F := Types.Category.FOOD
	var D := Types.Category.DRINK
	var E := Types.Category.FUN
	var C := Types.Category.CRAFT
	return [
		Types.CustomerDefinition.new("workers", "晚班职员", [F, D]),
		Types.CustomerDefinition.new("students", "结伴学生", [F, E]),
		Types.CustomerDefinition.new("tourists", "外地游客", [C, F]),
		Types.CustomerDefinition.new("families", "亲子家庭", [E, F]),
		Types.CustomerDefinition.new("collectors", "手作藏家", [C, D]),
		Types.CustomerDefinition.new("night_owls", "夜游青年", [D, E]),
		Types.CustomerDefinition.new("foodies", "美食探店客", [F, F], 13, 3),
		Types.CustomerDefinition.new("tea_friends", "茶友小聚", [D, C]),
		Types.CustomerDefinition.new("date", "约会客人", [E, D], 13, 4),
		Types.CustomerDefinition.new("tour_group", "旅行团", [C, E], 11, 2),
		Types.CustomerDefinition.new("parents", "带娃家长", [F, C], 12, 4),
		Types.CustomerDefinition.new("performers", "散场观众", [E, F], 11, 3),
	]
