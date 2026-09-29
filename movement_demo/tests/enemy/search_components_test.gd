extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	var hints = preload("res://scripts/enemy/services/enemy_search_hints.gd").new()
	# 同一输入的预期值来自六种配置含义，不复写实现公式。
	var expected := [0.8, 0.44, 0.4, 0.44, 0.22, 0.24]
	for mode in range(6):
		var result: float = hints.chance(0.8, mode, 4.0, 3.0, 0.1, 8.0, 4.0, 6.0, func(_time, _distance): return 0.3)
		check(is_equal_approx(result, expected[mode]), "提示衰减模式%d保持原数值语义" % mode)
	check(is_equal_approx(hints.chance(0.8, 4, 100.0, 100.0, 0.1, 8.0, 4.0, 6.0, Callable()), 0.08), "组合衰减保留最低倍率")
	check(hints.chance(0.0, 5, 1.0, 1.0, 0.1, 8.0, 4.0, 6.0, Callable()) == 0.0, "关闭提示不调用自定义扩展")
	seed(123)
	var unchanged := randf()
	seed(123)
	check(hints.sample(Vector3.ONE, 0.0) == Vector3.ONE and randf() == unchanged, "零误差不额外消耗随机数")
	seed(251)
	var angle := randf_range(0.0, TAU)
	var radius := sqrt(randf()) * 1.25
	var after := randf()
	seed(251)
	check(hints.sample(Vector3.ONE, 1.25).is_equal_approx(Vector3.ONE + Vector3(cos(angle), 0, sin(angle)) * radius) and randf() == after, "误差采样顺序保持兼容且每次只取一个样本")
	print("SEARCH COMPONENTS: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
