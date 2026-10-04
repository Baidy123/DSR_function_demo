extends RefCounted

## 所有动作的统一协议。实例只属于一个敌人；定义与参数资源不存执行进度。
var context
var definition: EnemyActionDefinition
var action_id: StringName
var config_section: StringName
var plan: Dictionary = {}
var _running := false
var _standalone_settings: Dictionary = {}
var actor:
	get: return context.actor if context != null else null
var enemy:
	get: return actor
var agent:
	get: return context.agent
var selection:
	get: return context.cover_selection

func setup(shared_context, section: StringName = &"") -> void:
	context = shared_context
	if not section.is_empty():
		config_section = section

func configuration_changed() -> void:
	config_section = definition.config_section

func is_enabled() -> bool:
	return context != null and context.can_use_action(action_id)

func _setting(key: StringName, fallback: Variant) -> Variant:
	if context != null and context.training != null:
		return context.training.setting(config_section, key, fallback, definition.parameters if definition != null else {})
	return _standalone_settings.get(key, definition.parameters.get(key, fallback) if definition != null else fallback)

func _set_setting(key: StringName, value: Variant) -> void:
	if context != null and context.training != null:
		context.training.set_setting(config_section, key, value)
	else:
		_standalone_settings[key] = value

func collect_candidates(_visible: bool) -> Array[Dictionary]:
	return []

func validate(candidate: Dictionary, _visible: bool) -> bool:
	if not is_enabled():
		return false
	var destination: Dictionary = candidate.get("destination", {})
	if destination.is_empty():
		return true
	var point: Vector3 = destination.get("position", destination.get("hide", Vector3.INF))
	return point.is_finite() and context.is_position_free(point) and not selection._path_to(actor.global_position, point).is_empty()

func begin(candidate: Dictionary, _visible: bool) -> bool:
	plan = candidate
	_running = true
	return true

func valid(visible: bool) -> bool:
	return _running and validate(plan, visible)

func tick(_delta: float, _visible: bool) -> Dictionary:
	return motion(Vector3.ZERO)

func cancel(_reason: StringName = &"switch") -> void:
	_running = false
	plan = {}
	reset()

func reset() -> void:
	pass

func can_interrupt(_next: Dictionary, _visible: bool) -> bool:
	return true

func hold_released() -> bool:
	return false

func on_event(_event: StringName, _data: Dictionary) -> void:
	pass

func on_shot_fired() -> void:
	pass

func state_label() -> String:
	return definition.display_name if definition != null else String(action_id)

func motion(direction: Vector3, multiplier: float = 1.0, facing: Vector3 = Vector3.INF, fire_request: Dictionary = {}, melee_request: Dictionary = {}) -> Dictionary:
	if not facing.is_finite():
		facing = context.last_known_position - actor.global_position if context.is_alerted else direction
	return {"direction": direction, "multiplier": multiplier, "facing": facing, "fire": fire_request, "melee": melee_request, "running": _running}

func option(destination: Dictionary, unavailable: float, exposure: float, information: float = 0.0, variant: StringName = &"") -> Dictionary:
	return {"id": action_id, "destination": destination, "plan": variant,
		"outcome": {"unavailable_seconds": unavailable, "exposed_seconds": exposure, "information_loss": information}}

func evaluation_points() -> Array:
	return []

func evaluate_point(_point: Variant) -> Dictionary:
	return {}

func evaluation_weight() -> int:
	return 1

## 仅控制空间查询预算，不影响动作评分、解锁或选择优先级。
func evaluation_priority_count() -> int:
	return 0

func evaluation_channel() -> StringName:
	return action_id
