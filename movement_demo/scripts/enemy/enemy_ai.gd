extends Node

## 通用生命周期协调：不依赖任何可选动作 ID，不保存其执行进度。
const Library = preload("res://scripts/enemy/enemy_action_library.gd")
const State = preload("res://scripts/enemy/services/enemy_memory.gd").State
const CombatType = preload("res://scripts/enemy/services/enemy_memory.gd").CombatType
var context = preload("res://scripts/enemy/services/enemy_context.gd").new()
var action_selector = preload("res://scripts/enemy/enemy_action_selector.gd").new()
var actions: Dictionary = {}
var current_action
var utility_options: Array[Dictionary] = []
var _utility_timer := 0.0
var _utility_boundary_recheck := false
var _utility_elapsed := 0.0
var utility_decision_count := 0
var command_decision_count := 0
var _battle_profile_serial := 0
var _configuration := 0
var _implementations: Dictionary = {}
var _enabled_last_frame := false
var _restoring_environment := false
var _physics_was_enabled := true
var frame_costs: Dictionary = {}
@onready var actor: CharacterBody3D = get_parent()
@onready var unit_type: Node = get_node("../UnitType")
@onready var training: Node = get_node("../Training")
@onready var perception: Node = $Perception
@onready var cover_selection: Node = $Cover
var player: Node3D:
	get: return context.player
var agent: NavigationAgent3D:
	get: return context.agent
var arena_zone: Area3D:
	get: return context.arena_zone
var navigation_region: NavigationRegion3D:
	get: return context.navigation_region
var utility_current: Dictionary:
	get: return context.utility_current
	set(value): context.utility_current = value
@export_group("Utility AI")
## 所有动作共同估计未来多少秒的火力缺失、暴露和信息损失，单位为秒。
## 调大更重视转移到位后的持续收益，调小更重视眼前收益；实际动作仍可提前结束或重评。
@export_range(1.0, 12.0, 0.5) var utility_horizon_seconds: float = 4.0
## 每秒有效火力缺失的代价权重；各项相加后选择总代价最低的方案。
## 调大更倾向维持射击、尽快恢复火力；调小更能接受停火转移或躲藏。0表示不计此项代价。
@export_range(0.0, 10.0, 0.1) var utility_fire_weight: float = 3.0
## 暴露风险的基础权重，还会乘上伤势、近期受击/近弹压力和可见目标的近身压力。
## 调大更重视掩护和拉开距离，调小更愿意暴露交战；没有压力时不会仅因权重大就强制躲藏。
## 0表示不计暴露风险；本参数不改变受到命中时的准度惩罚。
@export_range(0.0, 10.0, 0.1) var utility_risk_weight: float = 3.0
## 每秒信息损失的代价权重，例如躲进掩体后无法持续观察目标。
## 调大更重视保持/重新获得目标信息，调小更能接受失视躲藏；0表示不计此项代价。
@export_range(0.0, 10.0, 0.1) var utility_information_weight: float = 1.0
## 正常情况下重新收集并比较动作候选的间隔，单位为秒；受击、配置变化等可请求提前重评。
## 调小反应更及时但评估更频繁，调大更省计算但可能反应较慢；重评后仍需满足切换条件。
@export_range(0.1, 2.0, 0.1) var utility_recheck_seconds: float = 0.4
## 新方案开始后通常至少保持的时间，单位为秒，减少动作反复切换。
## 调大执行更稳定但接管更慢；0取消此等待。当前方案失效或动作主动释放保持时可提前切换。
## 保持时间结束后仍需满足切换优势，并且当前动作允许被中断。
@export_range(0.0, 3.0, 0.1) var utility_hold_seconds: float = 0.6
## 新方案的总代价须比当前有效方案低超过此分值，才通常允许切换；这是绝对分差。
## 调大更愿意继续当前方案，调小更容易换动作；与三个代价权重的尺度相关。
## 0仍只会因更优方案而切换；当前方案失效或动作主动释放保持时不受此分差限制。
@export_range(0.0, 5.0, 0.1) var utility_switch_advantage: float = 0.5
## 没有目击、受伤或近弹的新证据时，旧威胁确定性每过这么多秒减半。
## 调大使旧威胁的避险影响保留更久，调小更快降低旧威胁影响；不会删除位置记忆或强制出掩体。
## 只控制风险估计中的威胁确定性，不控制受击/近弹压力自身的消退速度，也不削弱可见目标的近身压力。
@export_range(0.5, 30.0, 0.5) var utility_threat_half_life_seconds: float = 4.0
## 与 Debug 总开关同时开启时，在动作切换成功后输出选中动作、总代价及火力/风险/信息代价。
## cost越低越有利于被选中；未选候选可在运行时查看本节点的utility_options。
@export var debug_utility: bool = false

func _ready() -> void:
	context.setup(actor, perception, cover_selection)
	context.spatial = preload("res://scripts/enemy/services/enemy_spatial_evaluator.gd").new()
	context.spatial.context = context
	context.fire = preload("res://scripts/enemy/services/enemy_fire_controller.gd").new()
	context.fire.setup(context)
	context.melee = preload("res://scripts/enemy/services/enemy_melee_controller.gd").new()
	context.melee.setup(context)
	context.reevaluate.connect(invalidate_utility)
	context.event_received.connect(_dispatch_event)
	context.fire.shot_fired.connect(_on_shot_fired)
	perception.noise_heard.connect(_on_noise_heard)
	actor.hit_received.connect(_on_hit_received)
	actor.reset_completed.connect(_reset_decisions)
	add_to_group("shot_listener")
	refresh_configuration(true)
	_reset_decisions()

func refresh_configuration(force: bool = false) -> void:
	var unit: EnemyUnitProfile = unit_type.profile
	var profile: EnemyTrainingProfile = training.profile
	var team_abilities: Dictionary = context.team_cooperation_abilities()
	var fingerprint := hash([unit.fingerprint() if unit != null else 0, profile.fingerprint() if profile != null else 0, team_abilities])
	if not force and fingerprint == _configuration: return
	_configuration = fingerprint
	context.unit = unit
	context.training = profile
	var resolved := Library.resolve(unit, profile, team_abilities)
	context.permitted = resolved.definitions
	for error in resolved.errors: push_warning(error)
	for id in actions.keys():
		var definition = resolved.definitions.get(id)
		if definition == null or _implementations.get(id) != definition.implementation:
			if current_action == actions[id]: _cancel_utility_execution(&"configuration")
			else: actions[id].cancel(&"configuration")
			context.spatial.unregister(actions[id])
			actions.erase(id)
			_implementations.erase(id)
	for id in resolved.definitions.keys():
		if actions.has(id):
			actions[id].definition = resolved.definitions[id]
			actions[id].configuration_changed()
			continue
		var action = Library.instantiate(resolved.definitions[id], context)
		if action == null:
			context.permitted.erase(id)
			continue
		actions[id] = action
		_implementations[id] = action.get_script()
		context.spatial.register(action)
	context.spatial.reset_evaluation()
	context.coordination_configuration_changed()
	invalidate_utility()

func _physics_process(delta: float) -> void:
	if _restoring_environment: return
	if context.refresh_environment():
		_reset_decisions()
	var stamp := Time.get_ticks_usec()
	if not context.commanded() or context.member_capability_snapshot().is_empty(): refresh_configuration()
	if context.member_capability_snapshot().is_empty(): _capture_battle_capabilities()
	frame_costs.configuration = Time.get_ticks_usec() - stamp
	stamp = Time.get_ticks_usec()
	for key in [&"utility_horizon_seconds", &"utility_fire_weight", &"utility_risk_weight", &"utility_information_weight", &"utility_threat_half_life_seconds"]:
		context.set(key, get(key))
	var enabled: bool = not actor.is_dead and is_arena_active() and not player.is_dead() and not player.is_in_dialogue
	if not enabled:
		if is_instance_valid(player) and player.is_in_dialogue: actor.clear_melee_hit_effects()
		if _enabled_last_frame: reset_actions()
		_enabled_last_frame = false
		actor.cancel_reload()
		context.melee.cancel()
		if not actor.is_vaulting(): actor.velocity = Vector3.ZERO
		else: actor.body_motion.interrupt()
		context.fire.update(delta, false, false, {})
		return
	_enabled_last_frame = true
	if NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) == 0: return
	var visible: bool = perception.can_see_player()
	context.update_evidence(delta, visible)
	frame_costs.perception = Time.get_ticks_usec() - stamp
	stamp = Time.get_ticks_usec()
	if context.commanded():
		context.advance_coordination_map(4, Time.get_ticks_usec() + 500, Engine.get_physics_frames())
	else:
		context.spatial.advance_evaluation()
	frame_costs.spatial = Time.get_ticks_usec() - stamp
	stamp = Time.get_ticks_usec()
	if context.commanded(): _update_command_decision()
	else: _update_utility_decision(delta, visible)
	frame_costs.decision = Time.get_ticks_usec() - stamp
	stamp = Time.get_ticks_usec()
	var output: Dictionary = {}
	if current_action != null:
		output = current_action.execute_command(delta, visible) if context.commanded() else current_action.execute_tick(delta, visible)
	var direction: Vector3 = output.get("direction", Vector3.ZERO)
	var scheduled_members: Array = output.get("scheduled_members", [])
	if scheduled_members.is_empty() and direction.is_zero_approx(): scheduled_members = context.coordinated_stationary_members()
	actor.request_crouch(output.get("crouch", false))
	if not output.get("vault", {}).is_empty(): actor.begin_vault(output.vault)
	actor.face_direction(output.get("facing", Vector3.ZERO), delta)
	# 先登记近战执行占用，再消费移动／射击意图；新行为同帧提交冲突请求也受身体约束。
	context.melee.update(delta, visible, output.get("melee", {}))
	actor.move_character(direction, delta, output.get("multiplier", 1.0), output.get("stop_position", Vector3.INF), scheduled_members)
	var moving: bool = not actor.get_local_movement_velocity().is_zero_approx() or Vector2(actor.velocity.x, actor.velocity.z).length_squared() > 0.0025
	context.fire.update(delta, visible, moving, output.get("fire", {}))
	context.cooperation_publish_execution(output)
	frame_costs.execution = Time.get_ticks_usec() - stamp
	if current_action != null and not output.get("running", true):
		context.investigation_hint_allowed = true
		_cancel_utility_execution(&"finished")
		invalidate_utility()
	_update_label()

func _update_utility_decision(delta: float, visible: bool) -> void:
	assert(not context.commanded())
	_utility_elapsed += delta
	_utility_timer -= delta
	if _utility_boundary_recheck and is_zero_approx(_utility_timer): _utility_timer = 0.0
	if actor.is_vaulting(): return
	var valid: bool = current_action != null and current_action.valid(visible)
	if _utility_timer > 0.0 and (valid or current_action == null): return
	_utility_timer = utility_recheck_seconds
	_utility_boundary_recheck = false
	utility_decision_count += 1
	context.prepare_coordination_evaluation()
	utility_options = action_selector.assess_options(self, visible)
	var choices: Array[Dictionary] = context.personal_position_choices(utility_options)
	var best: Dictionary = action_selector.choose_option(choices, utility_current)
	var cost := INF
	for candidate in choices:
		if action_selector.same_option(candidate, utility_current):
			cost = candidate.cost
			utility_current = candidate
			if current_action != null: current_action.plan = candidate
	valid = valid and is_finite(cost)
	if valid: valid = context.maintain_coordination_choice(utility_current)
	if current_action != null and not current_action.can_interrupt(best, visible): return
	if best.is_empty():
		_cancel_utility_execution()
		context.state = State.IDLE
		return
	if valid and action_selector.same_option(best, utility_current): return
	if valid and not current_action.hold_released():
		if _utility_elapsed < utility_hold_seconds and not is_equal_approx(_utility_elapsed, utility_hold_seconds):
			if not best.get("route", {}).is_empty() and best.cost + utility_switch_advantage < cost:
				var remaining := utility_hold_seconds - _utility_elapsed
				if remaining < _utility_timer:
					_utility_timer = remaining
					_utility_boundary_recheck = true
			return
		if best.cost + utility_switch_advantage >= cost: return
	_start_utility_option(best, visible)

func _start_utility_option(candidate: Dictionary, visible: bool) -> void:
	var next = actions.get(candidate.get("id"))
	if next == null or not next.validate(candidate, visible):
		invalidate_utility()
		return
	var transaction: Dictionary = context.prepare_coordination_choice(candidate)
	if transaction.required and transaction.token.is_empty():
		invalidate_utility()
		return
	_cancel_utility_execution(&"switch")
	current_action = next
	utility_current = candidate
	_utility_elapsed = 0.0
	if not next.begin(candidate, visible) or not context.commit_coordination_choice(transaction):
		context.rollback_coordination_choice(transaction)
		_cancel_utility_execution(&"failed")
		invalidate_utility()
		return
	if debug_utility and actor.debug_settings.enabled:
		print("[AI][Utility] ", candidate.id, " cost=", candidate.get("cost", 0.0), " ", candidate.get("breakdown", {}))

func _capture_battle_capabilities() -> void:
	_battle_profile_serial += 1
	var installed := {}
	for id in actions:
		if actions[id].is_enabled(): installed[id] = actions[id].freeze_command_capability()
	var weapon := {}
	if actor.weapon != null:
		for key in [&"fire_range", &"magazine_capacity", &"reload_seconds", &"melee_enabled", &"melee_range"]:
			weapon[key] = actor.weapon.get(key)
	context.install_member_capabilities({"ready": true, "member_id": actor.get_instance_id(),
		"profile_id": "%s:%s" % [actor.get_instance_id(), _battle_profile_serial],
		"unit_id": context.unit.unit_id if context.unit != null else &"",
		"capabilities": context.unit.capabilities.duplicate() if context.unit != null else [],
		"training": context.training.display_name if context.training != null else "",
		"stress_tolerance": float(context.setting(&"tactics", &"stress_tolerance", 0.4)),
		"actions": installed, "firearms": actor.can_use_firearms(), "weapon": weapon,
		"body": context.coordination_motion_state()})

func _update_command_decision() -> void:
	assert(context.commanded())
	utility_options.clear()
	var task: Dictionary = context.coordination_assignment()
	if task.is_empty():
		if current_action != null: _cancel_utility_execution(&"awaiting_command")
		return
	if current_action != null and preload("res://scripts/enemy/services/squad_contract.gd").same_task(current_action.command, task): return
	if actor.is_vaulting() or actor.melee_active:
		context.report_command(task, &"occupied", {"reason": &"body_busy"})
		return
	var next = actions.get(task.get("action"))
	if next == null or not context.validate_command_post(task, context.member_capability_snapshot()):
		context.report_command(task, &"blocked", {"reason": &"executor_unavailable"})
		return
	_cancel_utility_execution(&"command_replaced")
	if not next.begin_command(task) or not context.accept_command(task):
		next.cancel(&"accept_failed")
		context.report_command(task, &"blocked", {"reason": &"accept_failed"})
		return
	current_action = next
	utility_current = next.plan
	command_decision_count += 1

func _cancel_utility_execution(reason: StringName = &"switch") -> void:
	if current_action != null: current_action.cancel(reason)
	context.cooperation_clear_execution(reason)
	current_action = null
	utility_current = {}
	context.fire.request = {}
	context.melee.cancel()
	agent.target_position = actor.global_position

func invalidate_utility() -> void:
	_utility_timer = 0.0

func is_arena_active() -> bool:
	return context.is_arena_active()

func is_active() -> bool:
	return context.is_alerted and not actor.is_dead

func can_use_action(id: StringName) -> bool:
	return context.can_use_action(id)

func reset_actions() -> void:
	actor.clear_local_movement()
	_cancel_utility_execution(&"reset")
	utility_options.clear()
	for action in actions.values():
		action._running = false
		action.plan = {}
		action.route_motion.reset()
		action.reset()
	context.fire.request = {}
	context.fire.reset_fire_timing()
	context.spatial.reset_evaluation()
	_utility_timer = 0.0
	_utility_elapsed = 0.0

func _reset_decisions() -> void:
	reset_actions()
	context.reset_memory()
	agent.target_position = actor.global_position
	_update_label()

func _dispatch_event(event: StringName, data: Dictionary) -> void:
	if context.commanded(): return
	for action in actions.values(): action.on_event(event, data)

func _on_hit_received(damage: float, attacker_position: Vector3) -> void:
	if actor.is_dead:
		reset_actions()
		context.reset_memory()
		context.state = State.DEAD
	elif damage > 0.0:
		context.utility_threat_age_seconds = 0.0
		context.recent_damage_pressure = minf(2.0, context.recent_damage_pressure + 0.5 + damage / maxf(actor.max_health, 1.0))
		_dispatch_event(&"damage", {"amount": damage})
		if attacker_position.is_finite(): context._investigate_attack(attacker_position)
		invalidate_utility()
	_update_label()

func notice_shot(origin: Vector3, endpoint: Vector3) -> void:
	context.notice_shot(origin, endpoint)

func _on_noise_heard(position: Vector3) -> void:
	if actor.is_dead or not is_arena_active() or perception.can_see_player(): return
	if NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) == 0: return
	context.publish_coordination_noise(position)
	if not context.commanded() and current_action != null and not utility_current.get("accepts_noise", false): return
	if context.noise_search_origin.is_finite() and context.noise_search_origin.distance_to(position) < 0.35: return
	context.noise_search_origin = position
	context.last_known_position = position
	context.is_alerted = true
	_dispatch_event(&"noise", {"position": position})
	invalidate_utility()

func _on_shot_fired() -> void:
	if current_action != null: current_action.on_shot_fired()

func _update_label() -> void:
	var label: String = current_action.state_label() if current_action != null else ("已死亡" if actor.is_dead else "待命")
	if context.commanded() and not actor.is_dead:
		var task: Dictionary = context.coordination_assignment()
		var names := {&"engage": "接敌", &"support": "支援", &"flank": "侧翼机动", &"search": "搜索", &"guard": "警戒", &"reload": "换弹", &"move": "让路", &"patrol": "巡逻"}
		label = "队伍指挥·%s" % names.get(task.get("role"), "等待任务")
	var name: String = context.unit.display_name if context.unit != null else "未配置兵种"
	actor.set_status_text("%s：%s\n生命 %d / %d" % [name, label, ceili(actor.health), ceili(actor.max_health)])

func _exit_tree() -> void:
	_physics_was_enabled = is_physics_processing()
	context.detach_environment()
	# 打破公共 RefCounted 服务之间的所有权环；运行中实例由 actions 唯一持有。
	if context.fire != null:
		context.fire.detach()
	if context.melee != null:
		context.melee.detach()
	for action in actions.values():
		action.cancel(&"exit_tree")
		context.spatial.unregister(action)
	if context.spatial != null: context.spatial.context = null
	context.routes.context = null
	current_action = null
	actions.clear()


func _enter_tree() -> void:
	if context.fire != null:
		_restoring_environment = true
		call_deferred("_resume_after_reparent")


func _resume_after_reparent() -> void:
	if not is_inside_tree(): return
	context.refresh_environment()
	context.fire.setup(context)
	context.melee.setup(context)
	context.spatial.context = context
	context.routes.context = context
	refresh_configuration(true)
	if context.area_changed_this_refresh: _reset_decisions()
	else:
		reset_actions()
		_update_label()
	_restoring_environment = false
	set_physics_process(_physics_was_enabled)

var state: int:
	get: return context.state
	set(value): context.state = value

var last_known_position: Vector3:
	get: return context.last_known_position
	set(value): context.last_known_position = value

var last_seen_position: Vector3:
	get: return context.last_seen_position
	set(value): context.last_seen_position = value

var last_seen_direction: Vector3:
	get: return context.last_seen_direction
	set(value): context.last_seen_direction = value

var has_visual_memory: bool:
	get: return context.has_visual_memory
	set(value): context.has_visual_memory = value

var is_alerted: bool:
	get: return context.is_alerted
	set(value): context.is_alerted = value

var was_seeing_player: bool:
	get: return context.was_seeing_player
	set(value): context.was_seeing_player = value

var utility_unseen_seconds: float:
	get: return context.utility_unseen_seconds
	set(value): context.utility_unseen_seconds = value

var utility_threat_age_seconds: float:
	get: return context.utility_threat_age_seconds
	set(value): context.utility_threat_age_seconds = value

var utility_suppression_pending: bool:
	get: return context.utility_suppression_pending
	set(value): context.utility_suppression_pending = value

var recent_damage_pressure: float:
	get: return context.recent_damage_pressure
	set(value): context.recent_damage_pressure = value

var nearby_shot_pressure: float:
	get: return context.nearby_shot_pressure
	set(value): context.nearby_shot_pressure = value

var patrol_pause_timer: float:
	get: return context.patrol_pause_timer
	set(value): context.patrol_pause_timer = value
