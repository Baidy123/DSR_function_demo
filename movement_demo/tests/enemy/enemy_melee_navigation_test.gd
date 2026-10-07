extends SceneTree

const Approach = preload("res://scripts/enemy/services/enemy_melee_approach.gd")
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
	ai.training.profile = load("res://resources/enemy/training/arena.tres").duplicate(true)
	ai.training.profile.selected_tactics.assign([&"melee_cover", &"melee_rush"])
	enemy.equip_weapon(load("res://resources/weapons/enemy_test_melee.tres").duplicate(true))
	ai.refresh_configuration(true)
	# 现场记录：玩家贴 CoverA 西面，距导航边界约 17 厘米；敌人刚绕出北端。
	enemy.global_position = Vector3(15.578, 0, -2.937)
	player.global_position = Vector3(15.418901, 0, 0.775821)
	enemy.health = 30.0
	enemy.look_at(player.global_position)
	for frame in 5: await physics_frame
	var visible: bool = ai.perception.can_see_player()
	ai.context.update_evidence(0.0, visible)
	check(visible, "现场贴墙玩家确实可见")
	check(ai.cover_selection._path_to(enemy.global_position, player.global_position).is_empty(), "通用导航仍拒绝边界外落点，未放宽全局可达条件")
	var path: PackedVector3Array = Approach.contact_path(ai.context)
	check(not path.is_empty(), "近战为导航边界外的可见玩家找到有效接敌路线")
	check(not ai.actions[&"melee_engage"].collect_candidates(visible).is_empty(), "重新看见玩家后普通接近仍有合法候选")
	if not path.is_empty():
		check(path[path.size() - 1].distance_to(player.global_position) < enemy.weapon.melee_range, "估计接敌终点计入导航偏移，仍在武器范围内")
	var saved_position: Vector3 = enemy.global_position
	var saved_target: Vector3 = ai.agent.target_position
	var known: Vector3 = ai.context.last_known_position
	player.global_position = Vector3(12, 0, 9)
	await physics_frame
	check(not ai.perception.can_see_player(), "路径记忆隔离用例的玩家确实不可见")
	check(Approach.contact_path(ai.context) == path and ai.context.last_known_position == known, "移动隐藏玩家不改变基于最后目击的接敌路线")
	check(enemy.global_position == saved_position and ai.agent.target_position == saved_target, "路径评估不移动角色或改写导航目标")
	# 动态遮挡不在旧烘焙网格中，投影点仍须经过身体空间与真实遮挡检查。
	var blocker := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 2.0, 1.0)
	collision.shape = shape
	blocker.add_child(collision)
	root.add_child(blocker)
	blocker.global_position = Vector3(15.25, 1.0, known.z)
	await physics_frame
	check(Approach.contact_path(ai.context).is_empty(), "导航投影落点被实体占据时拒绝接敌路线")
	blocker.queue_free()
	await physics_frame
	check(not Approach.contact_path(ai.context).is_empty(), "动态障碍移除后接敌路线恢复")
	ai.context.last_known_position = Vector3(-100, 0, -100)
	check(Approach.contact_path(ai.context).is_empty(), "远离导航的记忆目标不能靠吸附预支近战收益")
	ai.context.last_known_position = Vector3(16.377497, known.y, 0.0)
	check(Approach.contact_path(ai.context).is_empty(), "墙体内的记忆位置不能通过投影产生隔墙近战路线")
	ai.context.last_known_position = known + Vector3.UP * 3.0
	check(Approach.contact_path(ai.context).is_empty(), "导航投影不把高差超过挥击范围的目标当成可接敌")
	ai.context.last_known_position = known
	player.global_position = known
	await physics_frame
	var initial_health: float = player.health.health
	var longest_idle := 0
	var idle_frames := 0
	var cover_entries := 0
	var last_id: StringName = &""
	for frame in 900:
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		var id: StringName = ai.utility_current.get("id", &"")
		if id == &"melee_cover" and last_id != id: cover_entries += 1
		last_id = id
		idle_frames = idle_frames + 1 if id.is_empty() and ai.context.sees_player else 0
		longest_idle = maxi(longest_idle, idle_frames)
		if player.health.health < initial_health: break
	print("NAV TRACE cover_entries=", cover_entries, " longest_visible_idle=", longest_idle, " position=", enemy.global_position)
	check(longest_idle < 60, "可见玩家时不会因接近候选消失而长时间待命")
	check(player.health.health < initial_health and enemy.melee_count > 0, "30血现场自主接续接近或突进并实际命中，不循环绕掩体")
	# 无战术、短武器也必须完成同一场景的接近，不能依靠强制突进掩盖导航缺口。
	enemy.reset_target()
	ai.training.profile.selected_tactics.clear()
	enemy.weapon.melee_range = 0.9
	ai.refresh_configuration(true)
	enemy.global_position = Vector3(15.578, 0, -2.937)
	player.global_position = known
	enemy.look_at(known)
	initial_health = player.health.health
	for frame in 5: await physics_frame
	for frame in 360:
		await physics_frame
		ai._physics_process(1.0 / 60.0)
		if player.health.health < initial_health: break
	check(player.health.health < initial_health, "未解锁战术的短武器近战兵也能实际接近并命中贴墙玩家")
	print("Melee navigation: %d/%d passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
