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
var _initial_geometry_revision := 0
var _team_decision_revision := 0
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
## 每秒有效协作收益的信用；0保留协作候选但关闭团队收益偏好。
@export_range(0.0, 10.0, 0.1) var utility_cooperation_weight: float = 4.0
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
	refresh_configuration()
	frame_costs.configuration = Time.get_ticks_usec() - stamp
	stamp = Time.get_ticks_usec()
	for key in [&"utility_horizon_seconds", &"utility_fire_weight", &"utility_risk_weight", &"utility_information_weight", &"utility_cooperation_weight", &"utility_threat_half_life_seconds"]:
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
	context.spatial.advance_evaluation()
	if _initial_geometry_revision != context.spatial.initial_ready_revision:
		_initial_geometry_revision = context.spatial.initial_ready_revision
		# A newly prepared squad option can disappear as this member walks before
		# the ordinary timer elapses. Reconsider once through the normal selector;
		# this does not scan extra points, force an action or release a body lock.
		if context.team_cooperation_abilities().get("level", 0) == 2 and context.cooperation_member_count() > 1: invalidate_utility()
	var team_revision: int = context.coordination_decision_revision()
	if _team_decision_revision != team_revision:
		_team_decision_revision = team_revision
		invalidate_utility()
	frame_costs.spatial = Time.get_ticks_usec() - stamp
	stamp = Time.get_ticks_usec()
	_update_utility_decision(delta, visible)
	frame_costs.decision = Time.get_ticks_usec() - stamp
	stamp = Time.get_ticks_usec()
	var output: Dictionary = {}
	if current_action != null:
		output = current_action.execute_tick(delta, visible)
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
	var execution: Dictionary = current_action.execution_contract(visible) if current_action != null else {}
	context.publish_execution_availability(execution, current_action.action_id if current_action != null else &"")
	if current_action != null and not context._coordination_execution.is_empty():
		context.report_coordination_execution(execution)
	frame_costs.execution = Time.get_ticks_usec() - stamp
	if current_action != null and not output.get("running", true):
		context.investigation_hint_allowed = true
		_cancel_utility_execution(&"finished")
		invalidate_utility()
	_update_label()

func _update_utility_decision(delta: float, visible: bool) -> void:
	_utility_elapsed += delta
	_utility_timer -= delta
	# A specifically scheduled hold-boundary check must not slip one physics
	# step because subtraction leaves a positive floating-point tail.
	if _utility_boundary_recheck and is_zero_approx(_utility_timer): _utility_timer = 0.0
	if actor.is_vaulting(): return
	var valid: bool = current_action != null and current_action.valid(visible)
	if _utility_timer > 0.0 and (valid or current_action == null): return
	_utility_timer = utility_recheck_seconds
	_utility_boundary_recheck = false
	context.prepare_coordination_evaluation()
	utility_options = action_selector.assess_options(self, visible)
	_publish_coordination_inputs(visible)
	var pending: Dictionary = context.coordination_assignment()
	if not pending.is_empty() and not pending.get("accepted", false) and context.coordination_motion_state().get("available_in", 0.0) <= 0.0:
		if not utility_options.any(func(candidate): return candidate.get("id") == pending.owner_action and pending.allowed_offer_keys.has(candidate.get("coordination_offer_key", ""))):
			context.reject_coordination_assignment(&"candidate_unavailable")
	var contract: Dictionary = current_action.execution_contract(visible) if current_action != null and not context._coordination_execution.is_empty() else {}
	context.report_coordination_execution(contract)
	var bound: bool = current_action != null and context.coordination_continuation(contract, current_action.action_id)
	var choices: Array[Dictionary] = context.coordination_choices(utility_options)
	if bound and not contract.get("segment_boundary", true):
		choices = choices.filter(func(candidate): return candidate.get("assignment_escape_verified", false) or candidate.get("coordination_offer_key", "") == context._coordination_execution.get("selected_offer_key", ""))
	var best: Dictionary = action_selector.choose_option(choices, utility_current)
	var cost := INF
	for candidate in utility_options:
		if not action_selector.same_option(candidate, utility_current): continue
		cost = candidate.cost
		if bound:
			# A refreshed score does not replace the accepted short segment.
			utility_current = utility_current.duplicate()
			utility_current.cost = candidate.cost
			utility_current.breakdown = candidate.get("breakdown", {})
		else:
			utility_current = candidate
		if current_action != null: current_action.plan = utility_current
	var current_choice: Dictionary = {}
	for candidate in choices:
		if action_selector.same_option(candidate, utility_current):
			current_choice = candidate
			break
	valid = valid and is_finite(cost) and not current_choice.is_empty()
	if valid: valid = context.maintain_coordination_choice(current_choice)
	# Body/action protection is independent of candidate availability or orders.
	if current_action != null and not current_action.can_interrupt(best, visible): return
	if bound and best.is_empty(): return
	if best.is_empty():
		_cancel_utility_execution()
		context.state = State.IDLE
		return
	var transition: bool = context.assignment_requires_transition(best, utility_current)
	if bound and not transition and action_selector.same_option(best, utility_current): return
	if valid and not transition and action_selector.same_option(best, utility_current): return
	if valid and not transition and not current_action.hold_released():
		if _utility_elapsed < utility_hold_seconds and not is_equal_approx(_utility_elapsed, utility_hold_seconds):
			# Preserve the original bounded reconsideration at the hold boundary.
			if not best.get("route", {}).is_empty() and best.cost + utility_switch_advantage < cost:
				var remaining := utility_hold_seconds - _utility_elapsed
				if remaining < _utility_timer:
					_utility_timer = remaining
					_utility_boundary_recheck = true
			return
		if best.cost + utility_switch_advantage >= cost: return
	_start_utility_option(best, visible)

func _publish_coordination_inputs(visible: bool) -> void:
	var offers: Array[Dictionary] = []
	var assignment: Dictionary = context.coordination_assignment()
	var execution: Dictionary = current_action.execution_contract(visible) if current_action != null else {}
	context.publish_execution_availability(execution, current_action.action_id if current_action != null else &"")
	if context.cooperation_enabled() and context.cooperation != null and context.cooperation_member_count() > 1:
		for action in actions.values():
			if action.is_enabled(): offers.append_array(action.coordination_offers(visible))
	# Preview only work that the current execution can actually accept. An
	# already accepted, valid segment keeps its own continuation while protected.
	var publishable: Array[Dictionary] = utility_options
	if context.cooperation_enabled() and context.cooperation != null and context.cooperation_member_count() > 1:
		publishable = []
		var contract: Dictionary = execution
		var continuing: bool = current_action != null and context.coordination_continuation(contract, current_action.action_id)
		var acceptance_times: Dictionary = {}
		for candidate in utility_options:
			var same_execution: bool = continuing and candidate.get("id") == current_action.action_id and candidate.get("coordination_offer_key", "") == context._coordination_execution.get("selected_offer_key", "")
			var occupied: float = float(contract.get("available_after_seconds", 0.0))
			if not same_execution and candidate.has("coordination_offer_key") and is_finite(occupied) and occupied > 0.0:
				publishable.append(candidate)
				acceptance_times[candidate.coordination_offer_key] = context.evidence_elapsed_seconds + occupied + utility_recheck_seconds
			elif same_execution or current_action == null or current_action.can_interrupt(candidate, visible):
				publishable.append(candidate)
			elif candidate.get("id") == current_action.action_id and contract.get("valid", false):
				var remaining: float = float(contract.get("remaining_seconds", 0.0))
				if is_finite(remaining) and remaining > 0.0:
					publishable.append(candidate)
					acceptance_times[candidate.get("coordination_offer_key", "")] = context.evidence_elapsed_seconds + remaining + utility_recheck_seconds
		for offer in offers:
			if acceptance_times.has(offer.get("offer_key", "")): offer.accept_after = acceptance_times[offer.offer_key]
	context.publish_coordination_offers(publishable, offers)
	for candidate in utility_options:
		# Always overwrite caller metadata; an urgent label grants no permission.
		candidate.assignment_escape_verified = false
		if assignment.is_empty() and context.inspection_order().is_empty(): continue
		var owner = actions.get(candidate.get("id"))
		if owner != null: candidate.assignment_escape_verified = owner.assignment_escape(candidate, visible)

func _start_utility_option(candidate: Dictionary, visible: bool) -> void:
	var next = actions.get(candidate.get("id"))
	if next == null or not next.validate(candidate, visible):
		if not candidate.get("coordination_assignment", {}).is_empty(): context.reject_coordination_assignment(&"local_validation_failed")
		invalidate_utility()
		return
	var transaction: Dictionary = context.prepare_coordination_choice(candidate)
	if transaction.required and transaction.token.is_empty():
		invalidate_utility()
		return
	_cancel_utility_execution(&"self_preservation" if candidate.get("assignment_escape_verified", false) and not context.coordination_assignment().is_empty() else &"switch")
	current_action = next
	utility_current = candidate
	_utility_elapsed = 0.0
	if not next.begin(candidate, visible):
		context.rollback_coordination_choice(transaction)
		_cancel_utility_execution(&"failed")
		context.state = State.IDLE
		invalidate_utility()
		return
	if not context.commit_coordination_choice(transaction):
		context.rollback_coordination_choice(transaction)
		_cancel_utility_execution(&"reservation_failed")
		invalidate_utility()
		return
	# This same decision may have published previews before choosing a protected
	# personal action. Withdraw those previews immediately; accepted work stays.
	if context.cooperation_enabled() and context.cooperation != null and context.cooperation_member_count() > 1 and context._coordination_execution.is_empty() and not current_action.can_interrupt({}, visible):
		_publish_coordination_inputs(visible)
	if debug_utility and actor.debug_settings.enabled:
		print("[AI][Utility] ", candidate.id, " cost=", candidate.get("cost", 0.0), " ", candidate.get("breakdown", {}))

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
	if actor.is_dead or not is_arena_active() or perception.can_see_player() or (current_action != null and not utility_current.get("accepts_noise", false)): return
	if NavigationServer3D.map_get_iteration_id(agent.get_navigation_map()) == 0: return
	if context.noise_search_origin.is_finite() and context.noise_search_origin.distance_to(position) < 0.35: return
	context.noise_search_origin = position
	context.publish_coordination_noise(position)
	context.last_known_position = position
	context.is_alerted = true
	_dispatch_event(&"noise", {"position": position})
	invalidate_utility()

func _on_shot_fired() -> void:
	if current_action != null: current_action.on_shot_fired()

func _update_label() -> void:
	var label: String = current_action.state_label() if current_action != null else ("已死亡" if actor.is_dead else "待命")
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
