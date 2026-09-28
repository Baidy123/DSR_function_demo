extends SceneTree

var checks: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene = load("res://main.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	var actor = scene.get_node("Arena/Enemy")
	var ai = actor.get_node("AI")
	ai.set_physics_process(false)
	for path in ["Perception", "Cover"]:
		_check("独立服务 " + path, ai.has_node(path))
	var modules := {"Tactics": ai.tactics, "Search": ai.search, "CoverAction": ai.cover}
	for entry in modules:
		var module = modules[entry]
		_check("独立运行对象 " + entry, module is RefCounted and not module is Node)
	if checks.values().has(false):
		_finish()
		return
	var tactics = ai.tactics
	var action = tactics.cover
	var selector = ai.get_node("Cover")
	var player = scene.get_node("Player")
	player.set_physics_process(false)
	player.get_node("Health").debug_invincible = true
	player.global_position = actor.global_position + Vector3(0, 0, 4.8)
	actor.look_at(player.global_position)
	actor.equip_weapon(actor.weapon.duplicate())
	actor.weapon.initial_accuracy = 1.0
	actor.weapon.shot_accuracy_penalty = 0.0
	actor.weapon.target_move_accuracy_loss_per_meter_slow = 0.0
	actor.weapon.target_move_accuracy_loss_per_meter_fast = 0.0
	actor.weapon.player_move_accuracy_loss_per_meter = 0.0
	actor.weapon_stability = 1.0
	tactics.fire_reaction_seconds = 0.0
	tactics.burst_pause_seconds = 0.0
	action.covering_retreat_chance = 1.0
	selector.debug_cover_selection = false
	for frame in range(5):
		await physics_frame
	_check("默认保留现有撤退能力", tactics.ai.can_use_action(&"covering_retreat"))
	preload("res://tests/enemy_fire_fixture.gd").set_training_action(tactics.ai, &"covering_retreat", false)
	action._start_move(action.Phase.RUN_TO_COVER, actor.global_position + Vector3(0, 0, -3))
	_check("未掌握时100%选择概率也不能撤退射击", not action.covering_retreat)
	# 即使动作标记来自旧存档/调试修改，射击出口仍应遵守能力限制。
	action.covering_retreat = true
	ai.state = ai.State.TRACK
	tactics.update_shooting(1.0, true, true)
	_check("能力关闭时射击出口拒绝撤退开火", actor.shot_count == 0)
	action.reset()
	preload("res://tests/enemy_fire_fixture.gd").set_training_action(tactics.ai, &"covering_retreat", true)
	action._start_move(action.Phase.RUN_TO_COVER, actor.global_position + Vector3(0, 0, -3))
	_check("掌握能力后允许选择撤退动作", action.covering_retreat)
	tactics.update_shooting(1.0, true, true)
	_check("掌握能力且满足条件可真实命中", actor.shot_count == 1 and actor.last_shot_collider == player)
	action.reset()
	action.covering_retreat_chance = 0.0
	action._start_move(action.Phase.RUN_TO_COVER, actor.global_position + Vector3(0, 0, -3))
	_check("掌握能力不代表每次必用", not action.covering_retreat)
	preload("res://tests/enemy_fire_fixture.gd").set_training_action(tactics.ai, &"covering_retreat", false)
	actor.reset_target()
	_check("战斗复位保留能力配置并清空动作", not tactics.ai.can_use_action(&"covering_retreat") and not action.is_active() and actor.shot_count == 0)
	actor.look_at(player.global_position)
	ai.state = ai.State.HOLD_POSITION
	tactics.update_shooting(1.0, true, true)
	_check("关闭撤退能力不影响普通接敌移动射击", actor.shot_count == 1 and actor.last_shot_collider == player)
	var other = load("res://arena.tscn").instantiate()
	root.add_child(other)
	var other_tactics = other.get_node("Enemy/AI").tactics
	_check("不同敌人的能力配置相互独立", other_tactics.ai.can_use_action(&"covering_retreat") and not tactics.ai.can_use_action(&"covering_retreat"))
	other.free()
	_check("掩体选择板块没有动作循环", not selector.has_method("step") and not selector.has_method("notice_shot"))
	_check("搜寻状态归搜寻板块", ai.get("search_sweep_points") == null and ai.search.get("search_sweep_points") != null)
	_check("射击时序归战术板块", ai.get("fire_pause_remaining") == null and tactics.get("fire_pause_remaining") != null)
	_finish()

func _check(label: String, passed: bool) -> void:
	checks[label] = passed
	print("PASS " if passed else "FAIL ", label)

func _finish() -> void:
	var failed: int = checks.values().count(false)
	print("ENEMY MODULES: %d/%d passed" % [checks.size() - failed, checks.size()])
	quit(0 if failed == 0 else 1)
