extends RefCounted

## Old action fixtures explicitly exercise the personal Training compatibility path.
## The saved arena's shared default is covered by the team scene integration test.
static func legacy_scene() -> Node:
	var scene = load("res://scenes/main.tscn").instantiate()
	var arena: Node = scene.get_node("Arena")
	# Also usable with the pre-migration runtime in paired baseline comparisons.
	if arena.get("team_cooperation_bindings") is Array:
		arena.team_cooperation_bindings.clear()
	return scene

## Opt-in fixture for a solo benchmark, or a benchmark that spawns N-1 peers.
## Preserve the primary actor's complete behavior; remove unmeasured saved peers
## before they enter the tree so the declared population is the real population.
static func single_member_scene() -> Node:
	var scene := legacy_scene()
	var arena := scene.get_node("Arena")
	var primary := primary_enemy(scene)
	for child in arena.get_children():
		if child != primary and child.has_node("AI"): child.free()
	return scene

## Locate the saved test member without assuming the user's instance name.
## Do not rename, spawn, remove, or reconfigure any scene node here.
static func primary_enemy(scene: Node) -> Node:
	var arena := scene.get_node_or_null("Arena")
	if arena == null: arena = scene
	var original := arena.get_node_or_null("Enemy")
	if original != null: return original
	for child in arena.get_children():
		if child.has_node("AI") and child.has_node("UnitType") and child.has_node("Training"): return child
	push_error("The fixture requires an AI member in its arena.")
	return null

static func advance_evaluation(ai, visible: bool) -> void:
	ai.context.sees_player = visible
	ai.context.spatial.advance_evaluation()

static func tick_selected(ai, delta: float, visible: bool) -> Vector3:
	var action = ai.actions.get(ai.utility_current.get("id"))
	if action == null: return Vector3.ZERO
	action.plan = ai.utility_current
	var output: Dictionary = action.tick(delta, visible)
	if not output.get("running", true): ai._cancel_utility_execution(&"finished")
	return output.get("direction", Vector3.ZERO)

# 测试只修改本实例的训练名单；不会替兵种补能力或修改资源文件。
static func set_training_action(ai: Node, id: StringName, enabled: bool) -> void:
	var entries: Array[StringName] = ai.training.profile.selected_tactics
	entries.erase(id)
	if enabled: entries.append(id)
	ai.refresh_configuration(true)

static func configure_timing(enemy: Node) -> void:
	_configure_common(enemy)
	var weapon := _new_weapon()
	weapon.initial_accuracy = 1.0
	weapon.shot_accuracy_penalty = 0.0
	weapon.player_move_accuracy_loss_per_meter = 0.0
	weapon.target_move_accuracy_loss_per_meter_slow = 0.0
	weapon.target_move_accuracy_loss_per_meter_fast = 0.0
	enemy.equip_weapon(weapon)


# 决策测试主动制造低于70%的跟枪状态，检查等待压力能否让AI继续开火。
static func configure_decision(enemy: Node) -> void:
	_configure_common(enemy)
	var weapon := _new_weapon()
	weapon.initial_accuracy = 0.5
	weapon.stabilize_seconds = 2.0
	weapon.accuracy_recovery_delay = 0.6
	weapon.shot_accuracy_penalty = 0.15
	weapon.minimum_accuracy = 0.1
	weapon.player_move_accuracy_loss_per_meter = 0.15
	weapon.moving_accuracy_cap = 0.35
	weapon.target_move_accuracy_loss_per_meter_slow = 0.3
	weapon.target_move_accuracy_loss_per_meter_fast = 0.3
	weapon.target_move_minimum_accuracy = 0.3
	weapon.target_move_fast_speed = 6.0
	enemy.equip_weapon(weapon)


static func _new_weapon() -> WeaponData:
	var weapon := WeaponData.new()
	weapon.damage = 10.0
	weapon.fire_range = 30.0
	weapon.shot_interval = 0.8
	return weapon


static func _configure_common(enemy: Node) -> void:
	var ai = enemy.get_node("AI")
	var unit = enemy.get_node("UnitType")
	var training = enemy.get_node("Training")
	# 固定本测试所需权限，不让用户在检查器增删动作影响射击流程验证。
	unit.profile = preload("res://resources/enemy/units/ranged.tres").duplicate(true)
	training.profile.selected_tactics.assign([&"cover", &"covering_retreat"])
	training.profile.set_setting(&"tactics", &"fire_while_moving", true)
	training.profile.set_setting(&"tactics", &"fire_reaction_seconds", 0.5)
	training.profile.set_setting(&"tactics", &"burst_shot_count", 3)
	training.profile.set_setting(&"tactics", &"burst_pause_seconds", 1.0)
	# These legacy timing fixtures describe the mechanical cadence explicitly.
	# The slower production default and covering bursts have a separate runtime test.
	training.profile.set_setting(&"tactics", &"shot_interval_multiplier", 1.0)
	training.profile.set_setting(&"tactics", &"fire_stability_target", 0.7)
	training.profile.set_setting(&"tactics", &"ranged_min_distance", 4.0)
	training.profile.set_setting(&"tactics", &"ranged_max_distance", 6.0)
	training.profile.set_setting(&"perception", &"sight_distance", 10.0)
	training.profile.set_setting(&"perception", &"sight_angle_degrees", 120.0)
	training.profile.set_setting(&"fire_decision", &"recovery_gain_weight", 0.35)
	training.profile.set_setting(&"fire_decision", &"close_range_weight", 0.35)
	training.profile.set_setting(&"fire_decision", &"wait_pressure_per_second", 0.45)
	enemy.shooting_enabled = true
	enemy.aim_turn_speed_degrees = 90.0
	ai.refresh_configuration(true)
	ai.reset_actions()
