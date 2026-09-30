extends SceneTree

class ConflictingRequests extends "res://scripts/enemy/actions/enemy_action.gd":
	func tick(_delta: float, _visible: bool) -> Dictionary:
		return motion(Vector3.RIGHT, 3.0, Vector3.FORWARD, {"owner": action_id}, {"owner": action_id})

var checks := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var actor = scene.get_node("Arena/Enemy")
	var ai = actor.get_node("AI")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	actor.set_physics_process(false)
	player.set_physics_process(false)
	player.health.debug_invincible = true
	for cover in get_nodes_in_group("cover_region"): cover.collision_layer = 0
	actor.global_position = Vector3(24, 0, -2)
	actor.rotation = Vector3.ZERO
	player.global_position = Vector3(24, 0, -3.1)
	var weapon := WeaponData.new()
	weapon.melee_windup_seconds = 0.1
	weapon.melee_recovery_seconds = 0.2
	actor.equip_weapon(weapon)
	for index in 4:
		await physics_frame
		await process_frame
	var melee = ai.context.melee
	var queries: bool = actor.has_method("can_move") and actor.has_method("can_turn") and actor.has_method("can_reload") and melee.has_method("allows_movement") and melee.has_method("presentation_state")
	check(queries, "基础执行提供条件查询，行为无需读取近战阶段")
	if queries:
		ai.utility_current = {"id": &"engage", "plan": &"melee"}
		actor.ammo.magazine_rounds = 1
		check(actor.can_reload() and actor.request_reload(), "空闲身体允许换弹")
		melee.update(0.0, true, {"owner": &"engage"})
		check(actor.melee_active and not actor.ammo.is_reloading, "近战执行负责中断换弹")
		check(not actor.can_move() and not actor.can_turn() and not actor.can_reload(), "前摇统一拒绝自主移动、转向与换弹")
		check(not melee.allows_movement(&"engage") and not melee.allows_movement(&"search"), "移动查询核对阶段和请求所有者")
		var start: Vector3 = actor.global_position
		var facing: Vector3 = actor.rotation
		actor.move_character(Vector3.RIGHT, 0.05, 3.0)
		actor.face_direction(Vector3.RIGHT, 0.05)
		actor.has_aim = true
		actor.aim_acquired = true
		actor.aim_direction = Vector3.FORWARD
		check(actor.global_position.distance_to(start) < 0.001 and actor.rotation == facing, "直接调用身体也不能绕过前摇移动与转向限制")
		check(not actor.request_reload() and not actor.try_fire(), "伪造瞄准或直接请求也不能绕过挥击互斥")
		var snapshot: Dictionary = melee.presentation_state()
		snapshot.active = false
		check(melee.presentation_state().active and melee.elapsed == 0.0, "表现快照的修改与查询不影响执行状态或计时")
		melee.update(0.1, true, {"owner": &"engage"})
		check(melee.allows_movement(&"engage") and not melee.allows_movement(&"search"), "出手后允许所属行为退让")
		check(actor.can_move() and not actor.can_turn() and not actor.can_reload() and not actor.can_fire(), "收招放开移动，保持其他执行限制")
		start = actor.global_position
		actor.move_character(Vector3.RIGHT, 0.05, 3.0)
		check(actor.global_position.x > start.x and actor.global_position.x - start.x <= actor.move_speed * 0.051, "收招可移动但不能通过倍率绕过普通速度上限")
		var cooldown: float = actor.melee_cooldown
		melee.cancel()
		check(actor.can_move() and actor.can_turn() and actor.can_reload() and actor.melee_cooldown == cooldown, "取消恢复执行许可但不清空近战冷却")
		actor.melee_cooldown = 0.0
		actor.begin_melee(0.5)
		actor.receive_melee_hit(0.0, actor.global_position - Vector3.RIGHT, 0.5, 0.2)
		start = actor.global_position
		actor.move_character(Vector3.ZERO, 0.05)
		check(not actor.can_move() and actor.global_position.x > start.x, "前摇限制自主移动，不阻止真实受击推移")
		actor.cancel_melee()
		actor.reset_target()
		check(actor.can_move() and actor.can_turn() and not actor.melee_active and actor.melee_cooldown == 0.0, "复位清除近战限制与冷却")
		actor.global_position = Vector3(24, 0, -2)
		actor.rotation = Vector3.ZERO
		player.global_position = Vector3(24, 0, -3.1)
		# 模拟后续新增行为误发冲突意图；实际协调器必须仍遵守执行层限制。
		for index in 3:
			await physics_frame
			await process_frame
		var conflicting := ConflictingRequests.new()
		conflicting.action_id = &"engage"
		conflicting.setup(ai.context)
		conflicting.begin({"id": &"engage"}, true)
		ai.current_action = conflicting
		ai.utility_current = conflicting.plan
		ai._utility_timer = 1.0
		start = actor.global_position
		var shots: int = actor.shot_count
		ai._physics_process(0.05)
		check(actor.melee_active and actor.global_position.distance_to(start) < 0.001 and actor.shot_count == shots, "协调器同帧收到移动、开火与近战请求时，前摇不会漏走或漏开一枪")
		ai.reset_actions()
		var source := FileAccess.get_file_as_string("res://scripts/enemy/actions/enemy_tactics.gd")
		check(not source.contains("melee.phase") and not source.contains("melee.Phase"), "接敌行为不绑定近战控制器阶段枚举")
	scene.queue_free()
	await process_frame
	await process_frame
	print("Execution contract: %d/%d passed" % [checks - failures, checks])
	quit(1 if failures else 0)

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	print(("PASS " if ok else "FAIL ") + label)
