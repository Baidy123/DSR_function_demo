extends SceneTree

var checks: Dictionary = {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	# 本组只验证原行为；射击与玩家死亡联动由 enemy_shooting_test 覆盖。
	scene.get_node("Arena/Enemy").shooting_enabled = false
	for frame in range(5):
		await physics_frame
	var actor = scene.get_node("Arena/Enemy")
	var ai = actor.get_node_or_null("AI")
	_check("Enemy接入独立AI子节点", ai != null)
	if ai == null:
		_finish()
		return
	_check("父节点是物理角色而AI只是普通节点", actor is CharacterBody3D and ai is Node and not ai is Node3D)
	_check("基础脚本不包含感知和搜索方法", not actor.has_method("can_see_player") and not actor.has_method("_begin_search"))
	_check("AI协调独立感知与搜寻板块", ai.perception.has_method("can_see_player") and ai.search.has_method("begin_search"))
	# 原默认值继续对比旧脚本；当前场景覆盖值从保存的场景读取，允许用户调参。
	var legacy = load("res://enemy_tactical_v8.gd").new()
	var overrides: Dictionary = {}
	var saved: SceneState = load("res://arena.tscn").get_state()
	for index in range(saved.get_node_count()):
		if not String(saved.get_node_path(index)).trim_prefix("./").begins_with("Enemy"):
			continue
		for property_index in range(saved.get_node_property_count(index)):
			overrides[String(saved.get_node_property_name(index, property_index))] = saved.get_node_property_value(index, property_index)
	var migrated := true
	for property in legacy.get_script().get_script_property_list():
		if not property.usage & PROPERTY_USAGE_EDITOR:
			continue
		var key: String = property.name
		if key in ["Tracking Cheat", "Tracking Movement", "Search"]:
			continue
		var expected = overrides.get(key, legacy.get(key))
		var owner_node = null
		for candidate in [actor, ai, ai.tactics, ai.search, ai.perception]:
			if candidate.get(key) != null:
				owner_node = candidate
				break
		if owner_node == null:
			print("CONFIG MISSING ", key)
			migrated = false
			continue
		if owner_node.get(key) != expected:
			print("CONFIG MISMATCH ", key, " expected=", expected, " actual=", owner_node.get(key))
			migrated = false
	_check("所有导出参数默认值和场景调参保持", migrated)
	legacy.free()
	_check("场景生命一万未被默认值覆盖", actor.max_health == 10000.0 and actor.health == 10000.0)
	_check("掩体读取对应AI和实体", actor.get_node("AI").cover.ai == ai and actor.get_node("AI").cover.enemy == actor)
	var p = scene.get_node("Player")
	p.set_physics_process(false)
	ai.set_physics_process(false)
	ai.perception.sight_distance = 0.0
	ai.perception.close_awareness_radius = 0.0
	p.global_position = actor.global_position + Vector3(1.0, 0.0, 0.0)
	for frame in range(5):
		await physics_frame
	actor.reset_target()
	ai._physics_process(ai.patrol_pause_seconds + 0.1)
	_check("AI决定进入巡逻", ai.state == ai.State.PATROL)
	ai.attack_position_uncertainty = 0.0
	actor.receive_hit(25.0, p.global_position)
	_check("实体结算伤害", actor.health == actor.max_health - 25.0)
	_check("伤害信号驱动AI调查", ai.is_alerted and ai.last_known_position.is_equal_approx(Vector3(p.global_position.x, actor.global_position.y, p.global_position.z)))
	actor.receive_hit(actor.health)
	_check("死亡同步AI与掩体", actor.is_dead and ai.state == ai.State.DEAD and not actor.get_node("AI").cover.is_active())
	actor.reset_target()
	_check("复位同步生命与AI记忆", not actor.is_dead and actor.health == actor.max_health and ai.state == ai.State.IDLE and not ai.is_alerted and not ai.has_visual_memory)
	# 走真实 Combat 射线入口，确认命中物仍是 Enemy 身体，AI 接到受击信号。
	p.global_position = actor.global_position + Vector3(0.0, 0.0, 2.0)
	p.rotation = Vector3.ZERO
	actor.get_node("AI").cover.take_cover_chance = 0.0
	var combat = p.get_node("Combat")
	var weapon = combat.weapon.duplicate()
	weapon.min_spread_angle_degrees = 0.0
	weapon.max_spread_angle_degrees = 0.0
	weapon.damage = 25.0
	combat.aim_mode = combat.AimMode.SPREAD_CONE
	combat.equip_weapon(weapon)
	for frame in range(5):
		await physics_frame
	combat.begin_frame(0.0, true)
	_check("玩家仍能锁定敌人实体", combat.locked_target == actor)
	combat.shoot()
	_check("真实弹道扣血并通知AI", combat.last_shot_collider == actor and actor.health == actor.max_health - 25.0 and ai.is_alerted)
	weapon.damage = actor.health
	combat.shot_cooldown = 0.0
	combat.shoot()
	_check("真实致命弹道结束AI并退出锁定", actor.is_dead and ai.state == ai.State.DEAD and not actor.is_in_group("combat_target"))
	actor.reset_target()
	# 移除决策层后，父节点仍然可以独立移动、转向、受伤、死亡和复位。
	var detached = actor.duplicate()
	detached.name = "ActorWithoutAI"
	detached.get_node("AI").free()
	detached.position = Vector3(0, 0, 2)
	root.add_child(detached)
	for frame in range(3):
		await physics_frame
	var start: Vector3 = detached.global_position
	for frame in range(20):
		await physics_frame
		detached.move_character(Vector3.RIGHT, 1.0 / 60.0)
	_check("没有AI仍能执行移动", detached.global_position.x > start.x + 0.3)
	var before_rotation: float = detached.rotation.y
	detached.face_direction(Vector3.BACK, 0.05)
	_check("没有AI仍能平滑转向", not is_equal_approx(detached.rotation.y, before_rotation) and absf(angle_difference(before_rotation, detached.rotation.y)) <= deg_to_rad(detached.turn_speed_degrees) * 0.05 + 0.0001)
	detached.receive_hit(25.0)
	_check("没有AI仍能独立扣血", detached.health == detached.max_health - 25.0)
	detached.receive_hit(detached.max_health)
	start = detached.global_position
	detached.move_character(Vector3.RIGHT, 1.0)
	_check("死亡实体拒绝移动", detached.is_dead and detached.global_position.is_equal_approx(start))
	detached.reset_target()
	_check("没有AI仍可复位", not detached.is_dead and detached.health == detached.max_health and detached.transform.is_equal_approx(detached.initial_transform))
	detached.free()
	_finish()


func _check(label: String, passed: bool) -> void:
	checks[label] = passed
	print("PASS " if passed else "FAIL ", label)


func _finish() -> void:
	var failures: int = checks.values().count(false)
	print("AI SPLIT: %d/%d passed" % [checks.size() - failures, checks.size()])
	quit(0 if failures == 0 else 1)
