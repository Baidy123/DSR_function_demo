extends SceneTree

var checks := 0
var failed := 0
var scene
var player
var combat
var slots


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	scene = load("res://main.tscn").instantiate()
	# 行为断言使用独立初值；用户在检查器调整备弹不影响测试。
	var initial_slots = scene.get_node("Player/WeaponSlots")
	for field in ["starting_rifle_ammo", "starting_pistol_ammo", "starting_smg_ammo", "starting_shotgun_ammo"]:
		initial_slots.set(field, 36)
	root.add_child(scene)
	current_scene = scene
	player = scene.get_node("Player")
	combat = player.get_node("Combat")
	slots = player.get_node("WeaponSlots")
	player.set_physics_process(false)
	scene.get_node("Arena/Enemy/AI").set_physics_process(false)
	check(combat.has_method("request_reload"), "玩家提供主动换弹接口")
	if failed > 0:
		finish()
		return
	check(InputMap.has_action("reload"), "注册换弹输入")
	var r_bound := false
	for event in InputMap.action_get_events("reload"):
		if event is InputEventKey and event.physical_keycode == KEY_R:
			r_bound = true
	check(r_bound, "换弹绑定物理R键")
	check(slots.reserve_ammo.size() == 4 and slots.reserve_ammo.values().all(func(value): return value == 36), "玩家提供四类初始备弹")
	var weapon := WeaponData.new()
	weapon.magazine_capacity = 12
	weapon.reload_seconds = 2.0
	weapon.shot_noise = null
	slots.primary_weapon = weapon
	slots.secondary_weapon = weapon
	slots.select_slot(0)
	player.global_position = Vector3(0, 0, -1)
	for frame in range(5):
		await physics_frame
	for shot in range(12):
		combat.begin_frame(1.0, true)
		combat.shoot()
	check(combat.ammo.magazine_rounds == 0 and combat.shot_count == 12, "真实玩家开火消耗有限弹匣")
	var shots: int = combat.shot_count
	combat.begin_frame(1.0, true)
	combat.shoot()
	check(combat.shot_count == shots and not combat.ammo.is_reloading, "打空扣扳机无弹道且不会自动换弹")
	_key_r()
	check(combat.ammo.is_reloading, "实际R键开始换弹")
	combat.end_frame(0.5, false)
	check(is_equal_approx(combat.ammo.reload_progress, 0.25), "非奔跑按正常速度换弹")
	player.is_sprinting = true
	combat.end_frame(1.0, false)
	check(is_equal_approx(combat.ammo.reload_progress, 0.75), "快速换弹开始后不因奔跑标志改变进度速度")
	player.is_sprinting = false
	combat.end_frame(0.5, true)
	check(not combat.ammo.is_reloading and combat.ammo.magazine_rounds == 12, "快速换弹固定两秒完成")
	check(slots.reserve_ammo[WeaponData.AmmoType.PISTOL] == 24, "完成换弹从对应共享池扣弹")
	combat.ammo.magazine_rounds = 3
	combat.request_reload()
	combat.end_frame(0.5, false)
	var first = combat.ammo
	slots.select_slot(1)
	check(not first.is_reloading and first.magazine_rounds == 3 and first.reserve_count() == 24, "切枪取消且不损失原弹匣和备弹")
	check(combat.ammo != first and combat.ammo.magazine_rounds == 12, "同武器资源双槽仍各自保存弹匣")
	combat.ammo.magazine_rounds = 0
	combat.request_reload()
	combat.end_frame(2.0, false)
	check(combat.ammo.reserve_count() == 12 and first.reserve_count() == 12, "同类主副枪共用备弹")
	slots.select_slot(0)
	check(combat.ammo == first and combat.ammo.magazine_rounds == 3, "切回保留该枪弹量")
	combat.request_reload()
	check(combat.ammo.reload_progress == 0.0, "中断后重新换弹从零开始")
	combat.end_frame(0.5, false)
	player.get_node("Health").debug_invincible = false
	player.receive_hit(1.0)
	check(combat.ammo.is_reloading and is_equal_approx(combat.ammo.reload_progress, 0.25), "普通受击不打断玩家换弹")
	player.set_dialogue_active(true)
	check(not combat.ammo.is_reloading and combat.ammo.magazine_rounds == 3, "进入对话立即取消换弹")
	check(not combat.request_reload(), "对话期间不能重新换弹")
	player.set_dialogue_active(false)
	var rifle := WeaponData.new()
	rifle.ammo_type = WeaponData.AmmoType.RIFLE
	slots.secondary_weapon = rifle
	slots.select_slot(1)
	combat.ammo.magazine_rounds = 0
	combat.request_reload()
	combat.end_frame(2.0, false)
	check(combat.ammo.reserve_count() == 24 and first.reserve_count() == 12, "不同弹药类型互不消耗")
	combat.ammo.magazine_rounds = 2
	player.global_position = Vector3(0, 0, 100)
	for frame in range(4):
		await physics_frame
	check(not combat.can_combat() and combat.request_reload(), "场外可准备换弹")
	combat.fire_held = true
	combat.shot_requested = true
	combat.cancel_reload()
	combat.request_reload()
	check(not combat.fire_held and not combat.shot_requested, "开始换弹清理待发射击")
	paused = true
	combat.end_frame(1.0, false)
	check(combat.ammo.reload_progress == 0.0 and not combat.request_reload(), "暂停不推进换弹且不能启动请求")
	paused = false
	combat.end_frame(0.5, false)
	_key_r(true)
	check(is_equal_approx(combat.ammo.reload_progress, 0.25), "长按R重复事件不重置进度")
	await process_frame
	await process_frame
	check(slots.get_node("Panel/Content/Hint").text.contains("换弹中"), "原装备栏显示换弹状态")
	check(slots.primary_label.text.contains("3/12"), "非当前槽也显示保留弹量")
	player.receive_hit(1000.0)
	check(player.is_dead() and not combat.ammo.is_reloading, "死亡立即取消换弹")
	player.get_node("Health")._request_restart()
	for frame in range(8):
		await process_frame
	player = current_scene.get_node("Player")
	combat = player.get_node("Combat")
	slots = player.get_node("WeaponSlots")
	player.set_physics_process(false)
	check(not paused and combat.ammo.magazine_rounds == combat.weapon.magazine_capacity and not combat.ammo.is_reloading, "实际重开恢复初始武器满弹及换弹状态")
	check(slots.reserve_ammo[0] == slots.starting_rifle_ammo and slots.reserve_ammo[1] == slots.starting_pistol_ammo and slots.reserve_ammo[2] == slots.starting_smg_ammo and slots.reserve_ammo[3] == slots.starting_shotgun_ammo, "重开恢复四类备弹初值")
	# 下面断言按0.5进度倍率验证固定方式，只配置测试实例；用户场景可用其他倍率。
	combat.sprint_reload_speed_multiplier = 0.5
	# 驱动真实Player物理流程，验证按R时锁定方式以及快速换弹禁跑。
	var movement_weapon := WeaponData.new()
	slots.primary_weapon = movement_weapon
	slots.select_slot(0)
	combat.ammo.magazine_rounds = 0
	combat.request_reload()
	player.rotation = Vector3.ZERO
	Input.action_press("move_up")
	Input.action_press("sprint")
	player._physics_process(0.1)
	check(not player.is_sprinting and is_equal_approx(combat.ammo.reload_progress, 0.05), "快速换弹期间按Shift仍按走路状态和快速进度执行")
	check(player.current_speed <= player.move_speed and player.stamina == player.MAX_STAMINA, "快速换弹限步行速度且不消耗奔跑耐力")
	await process_frame
	await process_frame
	check(slots.get_node("Panel/Content/Hint").text.contains("快速换弹") and slots.get_node("Panel/Content/Hint").text.contains("禁跑"), "快速换弹界面明确提示禁跑")
	player.current_speed = player.move_speed * player.sprint_speed_multiplier
	player._physics_process(0.01)
	check(player.current_speed <= player.move_speed, "快速换弹不能保留先前奔跑的高速惯性")
	combat.cancel_reload()
	player._physics_process(0.1)
	check(player.is_sprinting, "取消快速换弹后按住Shift恢复奔跑")
	_key_r()
	combat.end_frame(0.5, false)
	check(is_equal_approx(combat.ammo.reload_progress, 0.125), "奔跑中按R以慢速开始换弹")
	Input.action_release("sprint")
	player._physics_process(0.1)
	check(not player.is_sprinting and is_equal_approx(combat.ammo.reload_progress, 0.15), "慢速换弹中松开Shift仍保持慢速进度")
	await process_frame
	await process_frame
	check(slots.get_node("Panel/Content/Hint").text.contains("慢速换弹") and slots.get_node("Panel/Content/Hint").text.contains("可跑"), "停跑后界面仍显示慢速换弹可跑")
	Input.action_press("sprint")
	player._physics_process(0.1)
	check(player.is_sprinting and is_equal_approx(combat.ammo.reload_progress, 0.175), "慢速换弹允许重新奔跑且不重置进度")
	Input.action_release("sprint")
	combat.end_frame(3.3, false)
	check(not combat.ammo.is_reloading and combat.ammo.magazine_rounds == 12, "慢速换弹累计四秒完成")
	player._physics_process(0.1)
	combat.ammo.magazine_rounds = 1
	_key_r()
	Input.action_press("sprint")
	player._physics_process(0.1)
	check(not player.is_sprinting, "下一次非奔跑开始重新选择快速换弹")
	combat.end_frame(1.9, false)
	player._physics_process(0.1)
	check(player.is_sprinting, "快速换弹完成后按住Shift恢复奔跑")
	Input.action_release("sprint")
	Input.action_release("move_up")
	finish()


func _key_r(echo: bool = false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = KEY_R
	event.pressed = true
	event.echo = echo
	root.push_input(event)
	event = event.duplicate()
	event.pressed = false
	event.echo = false
	root.push_input(event)


func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failed += 1
	print("PASS " if ok else "FAIL ", label)


func finish() -> void:
	print("PLAYER RELOAD: %d/%d passed" % [checks - failed, checks])
	quit(0 if failed == 0 else 1)
