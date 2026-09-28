extends SceneTree

# 动作库迁移契约：真实场景、真实权限入口；不依赖随机抽中具体墙角。
var checks: Dictionary = {}
const ACTION_IDS := ["patrol", "search", "engage", "cover", "attack_position", "suppression", "exit_suppression"]

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var actor = scene.get_node("Arena/Enemy")
	_check("兵种配置独立节点", actor.has_node("UnitType"))
	_check("训练配置独立节点", actor.has_node("Training"))
	if checks.values().has(false):
		_finish()
		return
	var ai = actor.get_node("AI")
	var unit = actor.get_node("UnitType")
	var training = actor.get_node("Training")
	var player = scene.get_node("Player")
	ai.set_physics_process(false)
	player.set_physics_process(false)
	player.get_node("Health").debug_invincible = true
	ai.cover_selection.debug_cover_selection = false
	ai.cover_selection.debug_attack_points = false
	player.global_position = Vector3(19.92596, 0, -4.2821)
	for frame in range(60):
		await physics_frame
		if ai.is_arena_active():
			break
	_check("测试实际进入竞技场", ai.is_arena_active())
	_check("AI只保留感知与空间辅助服务节点", ai.get_child_count() == 2 and ai.has_node("Perception") and ai.has_node("Cover"))
	_check("战术协调和射击决策为普通对象", ai.tactics is RefCounted and ai.tactics.fire_decision is RefCounted)
	for id in ACTION_IDS:
		var action = ai.actions.get(id)
		_check("动作库含独立普通对象 " + id, action is RefCounted and not action is Node)
		_check("动作显式绑定本敌人AI " + id, action != null and action.ai == ai)
	_check("搜索与掩体引用库中同一实例", ai.search == ai.actions["search"] and ai.cover == ai.actions["cover"])
	var default_training = load("res://enemy_training.gd").new()
	_check("新训练配置出口压制默认关闭", not default_training.tactics_can_suppress_exits)
	default_training.free()
	training.tactics_can_suppress_exits = true
	var available: Array = unit.available_actions.duplicate()
	var allowed: Array = training.allowed_actions.duplicate()
	for id in ACTION_IDS:
		unit.available_actions = available.duplicate()
		training.allowed_actions = allowed.duplicate()
		_check("兵种与训练同时允许 " + id, unit.has_action(id) and training.allows_action(id) and ai.can_use_action(id))
		_remove_action(unit.available_actions, id)
		_check("兵种没有动作时训练不能赋予 " + id, not unit.has_action(id) and not ai.can_use_action(id))
		unit.available_actions = available.duplicate()
		_remove_action(training.allowed_actions, id)
		_check("兵种拥有动作仍需训练授权 " + id, unit.has_action(id) and not training.allows_action(id) and not ai.can_use_action(id))
	unit.available_actions = available.duplicate()
	training.allowed_actions = allowed.duplicate()
	training.tactics_can_suppress_exits = false
	training.tactics_attack_position_chance = 1.0
	training.cover_hide_seconds = 2.75
	training.search_track_seconds = 4.25
	_check("训练参数由动作读取单一来源", ai.tactics.attack_position_chance == 1.0 and ai.cover.hide_seconds == 2.75 and ai.search.track_seconds == 4.25)
	ai.cover.hide_seconds = 3.25
	_check("兼容动作参数写入训练配置", training.cover_hide_seconds == 3.25)
	ai.has_visual_memory = true
	ai.last_seen_position = player.global_position
	ai.last_known_position = player.global_position
	ai.combat_type = ai.CombatType.RANGED
	var attack = ai.tactics.attack_position
	_remove_action(unit.available_actions, "attack_position")
	ai.try_attack_position()
	_check("架枪概率1不能绕过兵种权限", not attack.is_active() and not attack.can_start() and not attack.start(player.global_position))
	unit.available_actions = available.duplicate()
	_remove_action(training.allowed_actions, "attack_position")
	ai.try_attack_position(true)
	_check("受击架枪概率1不能绕过训练权限", not attack.is_active() and not attack.can_start() and not attack.start(player.global_position, true))
	training.allowed_actions = allowed.duplicate()
	training.tactics_can_use_attack_positions = false
	ai.try_attack_position()
	_check("原布尔能力关闭不能被名单绕过", not ai.can_use_action("attack_position") and not attack.is_active())
	training.tactics_can_use_attack_positions = true
	ai.try_attack_position()
	_check("架枪请求不绕过统一评分直接启动", not attack.is_active())
	attack.start(player.global_position)
	_check("双权限满足时确实启动架枪", attack.is_active())
	_remove_action(unit.available_actions, "attack_position")
	attack.step(0.016, false)
	_check("架枪运行中撤销兵种权限立即停止", not attack.is_active())
	unit.available_actions = available.duplicate()
	attack.start(player.global_position)
	_remove_action(training.allowed_actions, "attack_position")
	attack.step(0.016, false)
	_check("架枪运行中撤销训练权限立即停止", not attack.is_active())
	training.allowed_actions = allowed.duplicate()
	ai.last_seen_position = actor.global_position + Vector3(0, 0, 3)
	ai.start_suppression()
	var suppression = ai.tactics.area_suppression
	_check("压制请求只标记统一重评", not suppression.is_active() and ai.utility_suppression_pending)
	suppression.on_target_lost()
	_check("双权限允许时启动区域压制", suppression.is_active())
	_remove_action(unit.available_actions, "suppression")
	suppression.step(0.016, false)
	_check("压制运行中撤销兵种权限停止", not suppression.is_active())
	ai.start_suppression()
	_check("区域压制启动不能绕过兵种权限", not suppression.is_active())
	unit.available_actions = available.duplicate()
	_remove_action(training.allowed_actions, "suppression")
	ai.start_suppression()
	_check("区域压制启动不能绕过训练权限", not suppression.is_active())
	training.allowed_actions = allowed.duplicate()
	ai.reset_actions()
	ai.is_alerted = true
	ai.was_seeing_player = false
	ai.state = ai.State.SEARCH
	_remove_action(training.allowed_actions, "search")
	ai._enforce_action_permissions()
	_check("撤销搜索权限停止搜索", ai.state == ai.State.IDLE)
	training.allowed_actions = allowed.duplicate()
	ai._enforce_action_permissions()
	_check("恢复搜索权限按已有记忆继续", ai.state in [ai.State.TRACK, ai.State.SEARCH, ai.State.INVESTIGATE])
	ai.reset_actions()
	var other_arena = load("res://arena.tscn").instantiate()
	root.add_child(other_arena)
	var other = other_arena.get_node("Enemy/AI")
	other.set_physics_process(false)
	for id in ACTION_IDS:
		_check("不同敌人动作实例独立 " + id, ai.actions[id] != other.actions[id])
	ai.tactics.fire_pause_remaining = 1.23
	suppression.remaining = 2.34
	ai.search.track_timer = 3.45
	_check("运行计时互不串扰", other.tactics.fire_pause_remaining == 0.0 and other.tactics.area_suppression.remaining == 0.0 and other.search.track_timer == 0.0)
	_check("训练配置互不串扰", other.get_parent().get_node("Training").cover_hide_seconds != 3.25)
	other_arena.free()
	# 替换单一实现，沿用原动作接口，观察真实调用而非仅检查脚本类型。
	var replacement := GDScript.new()
	replacement.source_code = 'extends "res://enemy_attack_position_action.gd"\nvar starts: int = 0\nfunc start(known_position: Vector3, from_hit: bool = false) -> bool:\n\tstarts += 1\n\treturn super.start(known_position, from_hit)\n'
	var compile_result := replacement.reload()
	_check("可替换动作脚本继承原接口", compile_result == OK)
	var replacement_arena = load("res://arena.tscn").instantiate()
	var replacement_unit = replacement_arena.get_node("Enemy/UnitType")
	_replace_action(replacement_unit, &"attack_position", replacement)
	root.add_child(replacement_arena)
	var replacement_ai = replacement_arena.get_node("Enemy/AI")
	replacement_ai.set_physics_process(false)
	_check("兵种替换单一动作实现", replacement_ai.actions["attack_position"].get_script() == replacement)
	replacement_ai.actions["attack_position"].start(Vector3.ZERO)
	_check("替换实现收到真实接口调用", replacement_ai.actions["attack_position"].starts == 1)
	_check("替换单动作不改变其他库实现", replacement_ai.actions["cover"].get_script() == ai.actions["cover"].get_script())
	replacement_arena.free()
	_check_patrol_reset()
	# 设置已有运行状态，再走真实伤害与刷新信号。
	suppression.active = true
	suppression.remaining = 2.0
	ai.tactics.fire_pause_remaining = 1.0
	actor.receive_hit(actor.health)
	_check("死亡清理动作和战斗状态", actor.is_dead and ai.state == ai.State.DEAD and not suppression.is_active() and not attack.is_active() and not ai.cover.is_active())
	actor.reset_target()
	_check("刷新清理计时与目击记忆", not actor.is_dead and not ai.has_visual_memory and ai.tactics.fire_pause_remaining == 0.0 and suppression.remaining == 0.0 and ai.search.track_timer == 0.0)
	_check("死亡刷新保留兵种训练配置", unit.available_actions == available and training.allowed_actions == allowed and training.tactics_attack_position_chance == 1.0 and training.cover_hide_seconds == 3.25 and training.search_track_seconds == 4.25)
	_finish()

func _check_patrol_reset() -> void:
	var implementation := GDScript.new()
	implementation.source_code = 'extends "res://enemy_patrol_action.gd"\nvar reset_count: int = 0\nvar private_timer: float = 0.0\nfunc reset() -> void:\n\treset_count += 1\n\tprivate_timer = 0.0\n\tsuper.reset()\n'
	var result := implementation.reload()
	_check("巡逻替换实现提供独立清理接口", result == OK)
	if result != OK:
		return
	var arenas: Array[Node] = []
	for index in range(2):
		var arena = load("res://arena.tscn").instantiate()
		_replace_action(arena.get_node("Enemy/UnitType"), &"patrol", implementation)
		root.add_child(arena)
		arena.get_node("Enemy/AI").set_physics_process(false)
		arenas.append(arena)
	var actor = arenas[0].get_node("Enemy")
	var patrol = actor.get_node("AI").actions[&"patrol"]
	var peer = arenas[1].get_node("Enemy/AI").actions[&"patrol"]
	var previous: int = patrol.reset_count
	var peer_previous: int = peer.reset_count
	patrol.private_timer = 7.0
	peer.private_timer = 9.0
	actor.receive_hit(actor.health)
	_check("死亡统一通知巡逻覆写清理一次", patrol.reset_count == previous + 1 and patrol.private_timer == 0.0)
	_check("单敌人死亡不清另一巡逻实例", peer.reset_count == peer_previous and peer.private_timer == 9.0)
	patrol.private_timer = 5.0
	actor.reset_target()
	_check("刷新统一通知巡逻覆写清理一次", patrol.reset_count == previous + 2 and patrol.private_timer == 0.0)
	_check("单敌人刷新不清另一巡逻实例", peer.reset_count == peer_previous and peer.private_timer == 9.0)
	for arena in arenas:
		arena.free()

func _check(label: String, passed: bool) -> void:
	checks[label] = passed
	print("PASS " if passed else "FAIL ", label)

func _finish() -> void:
	var failed: int = checks.values().count(false)
	print("ENEMY ACTION LIBRARY: %d/%d passed" % [checks.size() - failed, checks.size()])
	quit(0 if failed == 0 else 1)

func _remove_action(entries: Array, id: StringName) -> void:
	for index in range(entries.size()):
		if entries[index] != null and entries[index].action_id == id:
			entries.remove_at(index)
			return

func _replace_action(unit: Node, id: StringName, implementation: Script) -> void:
	for index in range(unit.available_actions.size()):
		if unit.available_actions[index].action_id == id:
			var definition = unit.available_actions[index].duplicate()
			definition.implementation = implementation
			unit.available_actions[index] = definition
			return
