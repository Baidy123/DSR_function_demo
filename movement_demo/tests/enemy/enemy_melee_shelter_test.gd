extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	seed(20261007)
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
	player.health.debug_invincible = false
	enemy.get_node("UnitType").profile = load("res://resources/enemy/units/melee.tres").duplicate(true)
	ai.training.profile = load("res://resources/enemy/training/melee_assault.tres").duplicate(true)
	ai.training.profile.selected_tactics.assign([&"melee_cover"])
	ai.training.profile.set_setting(&"search", &"tracking_cheat_enabled", false)
	ai.training.profile.set_setting(&"perception", &"hearing_enabled", false)
	enemy.equip_weapon(load("res://resources/weapons/enemy_test_melee.tres").duplicate(true))
	ai.refresh_configuration(true)
	check(ai.actions.has(&"cover") and ai.actions.has(&"melee_cover"), "近战掩体接近自动包含基础掩体躲藏")
	if ai.actions.has(&"cover"):
		check(ai.actions[&"cover"] != ai.actions[&"melee_cover"] and ai.actions[&"cover"].transfer != ai.actions[&"melee_cover"].transfer, "升级与基础动作保留独立实例和移动状态")
	ai.training.profile.selected_tactics.assign([&"cover", &"melee_cover"])
	ai.refresh_configuration(true)
	ai.training.profile.selected_tactics.erase(&"melee_cover")
	ai.refresh_configuration(true)
	check(ai.actions.has(&"cover") and not ai.actions.has(&"melee_cover"), "撤销升级保留手动解锁的基础掩体")
	check(not ai.actions.has(&"covering_retreat") and not enemy.can_use_firearms(), "基础躲藏不会赋予近战兵枪械或掩护射击资格")
	if ai.actions.has(&"cover"):
		var action = ai.actions[&"cover"]
		enemy.global_position = Vector3(22, 0, 4)
		player.global_position = Vector3(24, 0, -4.5)
		enemy.look_at(player.global_position)
		for frame in 5: await physics_frame
		ai.context.update_evidence(0.0, ai.perception.can_see_player())
		check(action.collect_candidates(true).is_empty(), "平静时基础躲藏不让近战兵无故放弃接敌")
		enemy.receive_hit(65.0, player.global_position)
		var initial_health: float = player.health.health
		var saw_cover := false
		var hid := false
		var resumed := false
		var peak_usec := 0
		for frame in 1000:
			await physics_frame
			ai._physics_process(1.0 / 60.0)
			peak_usec = maxi(peak_usec, ai.frame_costs.decision + ai.frame_costs.execution)
			if ai.current_action == action:
				saw_cover = true
				hid = hid or (action.transfer.phase == action.transfer.Phase.HIDE and ai.context.cover_selection.is_hidden_at(enemy.global_position, player.global_position + Vector3.UP * 0.8))
			elif hid:
				resumed = true
			if player.health.health < initial_health: break
		check(saw_cover and hid, "只解锁基础掩体的近战兵受击后自主跑到真实遮挡后躲藏")
		check(resumed and enemy.melee_count > 0 and player.health.health < initial_health, "压力消退后低血量近战兵离开躲藏并接续实际近战命中")
		check(peak_usec < 20000, "基础躲藏接敌决策与执行保留20毫秒门槛")
		print("SHELTER peak_usec=", peak_usec)
		enemy.reset_target()
		enemy.global_position = Vector3(22, 0, 4)
		player.global_position = Vector3(22, 0, 3.2)
		enemy.look_at(player.global_position)
		for frame in 4: await physics_frame
		enemy.receive_hit(10.0, player.global_position)
		ai.context.update_evidence(0.0, ai.perception.can_see_player())
		check(ai.context.melee.can_request(true) and action.collect_candidates(true).is_empty(), "贴脸可有效挥击时受击不会强制退去躲藏")
		ai.training.profile.selected_tactics.clear()
		ai.refresh_configuration(true)
		check(not ai.actions.has(&"cover") and not action.transfer.is_active(), "撤销训练清理基础躲藏资格和执行状态")
	print("MELEE SHELTER: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print("PASS " if ok else "FAIL ", label)
