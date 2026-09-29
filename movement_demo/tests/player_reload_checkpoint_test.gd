extends SceneTree

var checks := 0
var failures := 0
var scene
var player
var combat
var slots
var weapon: WeaponData

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	player = scene.get_node("Player")
	combat = player.get_node("Combat")
	slots = player.get_node("WeaponSlots")
	player.set_physics_process(false)
	scene.get_node("Arena/Enemy/AI").set_physics_process(false)
	player.get_node("Health").debug_invincible = false
	weapon = WeaponData.new()
	weapon.reload_seconds = 2.0
	weapon.magazine_capacity = 12
	weapon.shot_noise = null
	slots.primary_weapon = weapon
	slots.secondary_weapon = weapon
	slots.select_slot(0)
	combat.sprint_reload_speed_multiplier = 0.5
	player.global_position = Vector3(0, 0, -1)
	for frame in range(5): await physics_frame

	prepare()
	combat.request_reload()
	combat.end_frame(0.98, false)
	player.is_sprinting = true
	combat.end_frame(0.5, true)
	check(not combat.ammo.is_reloading and combat.ammo.reload_progress == 0.0 and combat.ammo.reload_checkpoint == 0.0, "49%奔跑中断清零并取消")
	player.is_sprinting = false
	combat.end_frame(0.5, false)
	var shots: int = combat.shot_count
	combat.begin_frame(1.0, true)
	combat.shoot()
	check(not combat.ammo.is_reloading and combat.shot_count == shots + 1 and combat.ammo.magazine_rounds == 2, "前半程取消后停跑可真实开火，不自动重启")
	check(combat.request_reload() and combat.ammo.reload_progress == 0.0, "再次按R从零开始")

	for fraction in [0.5, 0.8]:
		prepare()
		combat.request_reload()
		combat.end_frame(2.0 * fraction, false)
		player.is_sprinting = true
		combat.end_frame(0.5, true)
		check(not combat.ammo.is_reloading and close(combat.ammo.reload_progress, 0.5) and close(combat.ammo.reload_checkpoint, 0.5), "%d%%中断只保留半程" % int(fraction * 100))
		check(combat.ammo.magazine_rounds == 3 and slots.reserve_ammo[weapon.ammo_type] == 60 and not combat.ammo.can_fire(), "已保留半程不会提前补弹或扣备弹，余弹也不能开火")
		combat.end_frame(2.0, true)
		check(close(combat.ammo.reload_progress, 0.5) and not combat.request_reload(), "快速换弹在持续奔跑中暂停，R不能绕过强制续换阶段")
		slots._update_display()
		check(slots.get_node("Panel/Content/Hint").text.contains("暂停 50%"), "普通HUD显示保留的半程与暂停状态")
		player.is_sprinting = false
		combat.end_frame(0.0, false)
		check(combat.ammo.is_reloading and close(combat.ammo.reload_progress, 0.5) and combat.accuracy == 0.0, "停跑自动从半程续换并保持最低准度")
		shots = combat.shot_count
		combat.begin_frame(1.0, true)
		combat.shoot()
		check(combat.shot_count == shots, "强制续换过程中真实射击入口拒绝开火")
		combat.end_frame(0.4, false)
		player.is_sprinting = true
		combat.end_frame(0.2, true)
		check(close(combat.ammo.reload_progress, 0.5), "再次奔跑仍退回半程，不能积攒多个中断后的额外进度")
		player.is_sprinting = false
		combat.end_frame(0.99, false)
		check(combat.ammo.is_reloading and combat.ammo.magazine_rounds == 3, "续换不足剩余时长不会提前完成")
		combat.end_frame(0.01, false)
		check(not combat.ammo.is_reloading and combat.ammo.reload_checkpoint == 0.0 and combat.ammo.magazine_rounds == 12 and slots.reserve_ammo[weapon.ammo_type] == 51, "续换足够一秒才补满，且只扣一次缺口备弹")

	prepare()
	combat.request_reload()
	combat.end_frame(0.8, false)
	var first = combat.ammo
	slots.select_slot(1)
	slots.select_slot(0)
	check(combat.ammo == first and not first.is_reloading and first.reload_progress == 0.0 and first.can_fire(), "前半程切枪后切回保持取消并保留余弹")
	prepare()
	combat.request_reload()
	combat.end_frame(1.6, false)
	first = combat.ammo
	slots.select_slot(1)
	check(first != combat.ammo and first.weapon == combat.ammo.weapon and close(first.reload_checkpoint, 0.5), "同一武器资源双槽独立保存半程状态")
	var second = combat.ammo
	second.magazine_rounds = 5
	combat.end_frame(3.0, false)
	check(close(first.reload_progress, 0.5) and second.can_fire(), "收起的枪不后台换弹，另一把枪仍可开火")
	slots._update_display()
	check(slots.primary_label.text.contains("保留 50%"), "普通装备栏显示收起武器的半程状态")
	slots.select_slot(0)
	check(first.is_reloading and close(first.reload_progress, 0.5), "切回半程武器立即强制续换")
	slots.select_slot(1)
	player.is_sprinting = true
	slots.select_slot(0)
	check(not first.is_reloading and close(first.reload_checkpoint, 0.5) and not first.can_fire(), "奔跑中切回快速换弹武器继续暂停，余弹不能绕过阶段")
	player.is_sprinting = false
	combat.end_frame(1.0, false)
	check(first.magazine_rounds == 12 and second.magazine_rounds == 5 and first.reload_checkpoint == 0.0, "切回续换只补当前枪，不污染另一槽弹匣")

	prepare()
	player.is_sprinting = true
	combat.request_reload()
	combat.end_frame(2.4, true)
	check(combat.is_slow_reload() and close(combat.ammo.reload_progress, 0.6), "主动边跑按R仍选择固定慢速换弹")
	first = combat.ammo
	slots.select_slot(1)
	player.is_sprinting = false
	slots.select_slot(0)
	check(combat.is_slow_reload() and first.is_reloading and close(first.reload_progress, 0.5), "慢速换弹切枪也只保留半程，切回仍沿用慢速")
	combat.end_frame(1.0, false)
	check(close(first.reload_progress, 0.75), "慢速半程剩余时间不因停止奔跑缩短")
	combat.end_frame(1.0, false)
	check(first.magazine_rounds == 12 and not first.is_reloading, "慢速半程按完整剩余两秒完成")

	prepare()
	combat.request_reload()
	combat.end_frame(1.6, false)
	first = combat.ammo
	slots.select_slot(1)
	slots.reserve_ammo[weapon.ammo_type] = 0
	slots.select_slot(0)
	check(first.is_reloading and not first.can_fire(), "共享备弹耗尽仍能继续已保留阶段，不永久卡住")
	combat.end_frame(1.0, false)
	check(first.magazine_rounds == 3 and first.can_fire() and slots.reserve_ammo[weapon.ammo_type] == 0, "无备弹完成动作后不凭空补弹并恢复原有余弹可用")

	prepare()
	combat.request_reload()
	combat.end_frame(1.6, false)
	player.is_sprinting = true
	combat.end_frame(0.1, true)
	paused = true
	player.is_sprinting = false
	combat.end_frame(2.0, false)
	check(not combat.ammo.is_reloading and close(combat.ammo.reload_checkpoint, 0.5), "暂停世界时不自动续换或推进保存的半程")
	paused = false
	player.set_dialogue_active(true)
	check(combat.ammo.reload_checkpoint == 0.0 and not combat.ammo.is_reloading, "对话按原生命周期规则清理当前武器换弹")
	player.set_dialogue_active(false)
	prepare()
	combat.request_reload()
	combat.end_frame(1.6, false)
	player.is_sprinting = true
	combat.end_frame(0.1, true)
	player.receive_hit(player.get_node("Health").max_health * 2.0)
	check(player.is_dead() and combat.ammo.reload_checkpoint == 0.0 and not combat.ammo.is_reloading, "死亡清理保留阶段")
	player.get_node("Health")._request_restart()
	for frame in range(8): await process_frame
	var restarted = current_scene.get_node("Player/Combat")
	check(not paused and restarted.ammo.reload_checkpoint == 0.0 and restarted.ammo.magazine_rounds == restarted.weapon.magazine_capacity, "真实重开恢复满匣且无旧阶段残留")
	print("PLAYER RELOAD CHECKPOINT: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func prepare() -> void:
	for state in slots._ammo_states:
		if state != null: state.cancel_reload()
	player.is_sprinting = false
	slots.select_slot(0)
	combat.cancel_reload()
	combat.ammo.magazine_rounds = 3
	slots.reserve_ammo[weapon.ammo_type] = 60

func close(a: float, b: float) -> bool:
	return absf(a - b) < 0.00001

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
