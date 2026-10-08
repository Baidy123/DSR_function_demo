extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var enemy = scene.get_node("Arena/Enemy")
	var ai = enemy.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	player.combat.set_physics_process(false)
	enemy.global_position = Vector3(24, 0, -2)
	enemy.rotation = Vector3.ZERO
	player.global_position = Vector3(24, 0, -4.5)
	for frame in 5: await physics_frame
	var context = ai.context
	check(context.has_method("observed_reload_window"), "公共感知提供已观察换弹的机会窗口")
	if failures > 0:
		quit(1)
		return
	var weapon := WeaponData.new()
	weapon.reload_seconds = 4.0
	player.combat.equip_weapon(weapon)
	player.combat.ammo.infinite_reserve = true
	player.combat.ammo.magazine_rounds = 0
	check(player.combat.request_reload(), "玩家真实进入换弹")
	check(ai.perception.can_see_player(), "观察测试起点存在真实视线")
	context.update_evidence(0.05, true)
	check(context.observed_reload_window() == 0.0, "观察换弹遵守反应时间")
	context.update_evidence(0.2, true)
	check(context.observed_reload_window() > 0.0, "持续目击换弹后形成接近机会")
	var observed: float = context.observed_reload_window()
	var remembered: Vector3 = context.last_known_position
	player.combat.cancel_reload()
	player.global_position = Vector3(23, 0, -4)
	context.update_evidence(0.1, false)
	check(is_equal_approx(context.observed_reload_window(), observed - 0.1), "失视后不读取隐藏玩家的取消换弹状态")
	check(context.last_known_position == remembered, "失视后的换弹记忆不泄露玩家位置")
	context.update_evidence(2.0, false)
	check(context.observed_reload_window() == 0.0, "失视换弹证据按时过期")
	player.combat.ammo.magazine_rounds = 0
	player.combat.request_reload()
	context.update_evidence(0.5, false)
	check(context.observed_reload_window() == 0.0, "未目击的墙后换弹不会生成机会")
	await physics_frame # Synchronize the moved collider before checking actual torso visibility.
	context.update_evidence(0.3, true)
	check(context.observed_reload_window() > 0.0, "重新目击可以重新形成证据")
	player.combat.cancel_reload()
	context.update_evidence(0.01, true)
	check(context.observed_reload_window() == 0.0, "看到换弹取消立即撤销机会")
	player.combat.ammo.magazine_rounds = 0
	player.combat.request_reload()
	context.update_evidence(0.3, true)
	player.combat.ammo.advance_reload(10.0)
	context.update_evidence(0.01, true)
	check(context.observed_reload_window() == 0.0, "看到换弹完成立即撤销机会")
	player.combat.ammo.magazine_rounds = 0
	player.combat.request_reload()
	context.update_evidence(0.3, true)
	context.reset_memory()
	check(context.observed_reload_window() == 0.0, "区域复位清理换弹证据")
	var settings = ai.training.profile.perception
	settings.reload_observation_seconds = 0.35
	settings.reload_memory_seconds = 0.6
	DirAccess.make_dir_recursive_absolute("res://logs")
	check(ResourceSaver.save(ai.training.profile, "res://logs/reload_observation_training.tres") == OK, "观察参数可保存")
	var restored = load("res://logs/reload_observation_training.tres")
	check(is_equal_approx(restored.perception.reload_observation_seconds, 0.35) and is_equal_approx(restored.perception.reload_memory_seconds, 0.6), "观察参数及显式覆盖可重载")
	print("Reload observation: %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
