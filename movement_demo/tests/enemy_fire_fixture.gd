extends RefCounted

# 只在测试进程中配置实例。使用新武器，不读取或改写用户调参资源。
# 时序测试固定：半秒反应、每组三枪、组间停一秒、枪械间隔0.8秒。
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
	unit.available_actions.assign([
		preload("res://enemy_actions/engage.tres"),
		preload("res://enemy_actions/patrol.tres"),
		preload("res://enemy_actions/search.tres"),
		preload("res://enemy_actions/cover.tres"),
		preload("res://enemy_actions/covering_retreat.tres"),
	])
	training.allowed_actions = unit.available_actions.duplicate()
	unit.combat_type = unit.CombatType.RANGED
	training.tactics_can_use_attack_positions = false
	training.tactics_can_suppress_fire = false
	training.tactics_can_covering_retreat = true
	training.tactics_fire_while_moving = true
	training.tactics_fire_reaction_seconds = 0.5
	training.tactics_burst_shot_count = 3
	training.tactics_burst_pause_seconds = 1.0
	training.tactics_fire_stability_target = 0.7
	training.tactics_ranged_min_distance = 4.0
	training.tactics_ranged_max_distance = 6.0
	training.perception_sight_distance = 10.0
	training.perception_sight_angle_degrees = 120.0
	training.fire_decision_recovery_gain_weight = 0.35
	training.fire_decision_close_range_weight = 0.35
	training.fire_decision_wait_pressure_per_second = 0.45
	enemy.shooting_enabled = true
	enemy.aim_turn_speed_degrees = 90.0
	ai.reset_actions()
