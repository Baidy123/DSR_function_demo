extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var settings = root.get_node_or_null("DebugSettings")
	check(settings != null, "提供统一 Debug 状态")
	if settings == null:
		finish()
		return
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var player = scene.get_node("Player")
	var enemy = scene.get_node("Arena/Enemy")
	var health = player.get_node("Health")
	var combat = player.get_node("Combat")
	var noise = health.get_node("NoiseRanges")
	var toggle = health.get_node("Debug/Controls/Invincible")
	player.set_physics_process(false)
	enemy.get_node("AI").set_physics_process(false)
	await process_frame
	check(not settings.enabled and not health.is_invincible(), "默认 Debug 关闭且可受伤")
	check(not debug_navigation_hint, "关闭总开关也隐藏编辑器开启的导航网格")
	check(not enemy.get_node("Label").visible and not combat.get_node("HUD/Panel").visible, "默认隐藏敌人文字和战斗调试信息")
	health.receive_hit(25.0)
	check(health.health == health.max_health - 25.0, "关闭时正常扣血")
	toggle.button_pressed = true
	check(settings.enabled and health.is_invincible(), "界面总开关同时开启无敌")
	check(debug_navigation_hint == OS.get_cmdline_user_args().has("--expect-navigation"), "开启总开关保留编辑器原导航显示选择")
	check(enemy.get_node("Label").visible and combat.get_node("HUD/Panel").visible, "开启立即显示文字和战斗信息")
	check(noise.enabled, "开启总开关自动允许声音范围")
	noise.receive_noise(player, player.global_position, 6.0, 0.4)
	check(noise.get_child_count() == 1, "开启时实际声音生成范围圈")
	health.receive_hit(25.0)
	check(health.health == health.max_health - 25.0, "无敌不扣血也不回血")
	check(health.get_node("Status").visible and player.get_node("WeaponSlots/Panel").visible, "开启时保留正常状态和弹药界面")
	toggle.button_pressed = false
	check(not settings.enabled and not health.is_invincible(), "关闭总开关同时关闭无敌")
	check(noise.get_child_count() == 0 and not noise.enabled, "关闭立即清理声音圈")
	noise.set_enabled(true)
	noise.receive_noise(player, player.global_position, 6.0, 0.4)
	check(noise.get_child_count() == 0, "细项不能绕过总开关")
	check(not enemy.get_node("Label").visible and not combat.get_node("HUD/Panel").visible, "关闭立即隐藏文字和战斗信息")
	health.receive_hit(25.0)
	check(health.health == health.max_health - 50.0, "关闭后重新正常扣血")
	health.debug_mode = true
	check(settings.enabled and toggle.button_pressed, "检查器总开关与界面同步")
	player.set_dialogue_active(true)
	combat._update_status()
	check(not combat.get_node("HUD/Panel").visible, "对话时仍隐藏战斗信息")
	player.set_dialogue_active(false)
	health.debug_mode = false
	check(health.get_node("Status").visible and player.get_node("WeaponSlots/Panel").visible, "关闭 Debug 仍保留正常生命体力弹药")
	finish()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("PASS " if ok else "FAIL ", label)

func finish() -> void:
	print("DEBUG MODE: ", checks - failures, "/", checks)
	quit(0 if failures == 0 else 1)
